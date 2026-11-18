"""Build the pinned MIT feature engine with the local integration, without Theos."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
VENDOR=ROOT/'vendor/ytkace'
BUILD=ROOT/'build'
ENGINE=BUILD/'engine'

def sha(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def replace(path,old,new):
    text=path.read_text()
    if old not in text:raise ValueError(f'Patch context changed: {path.name}')
    path.write_text(text.replace(old,new))

def prepare():
    lock=json.loads((ROOT/'vendor/ytkace.lock.json').read_text())
    for name,digest in lock['files'].items():
        if sha(VENDOR/name)!=digest:raise ValueError(f'Pinned source changed: {name}')
    if ENGINE.exists():shutil.rmtree(ENGINE)
    shutil.copytree(VENDOR,ENGINE)
    entry=ENGINE/'Tweak/Entry.mm'
    replace(entry,'#import "YTKACE.h"','#import "YTKACE.h"\n#import "FullBridge.h"\n#import "Core.h"')
    replace(entry,'    YTKACEInstallSideloadCompatibilityHooks();','    if (!YMLiveContainer()) YTKACEInstallSideloadCompatibilityHooks();')
    replace(entry,'    YTKACEInstallBackgroundPlaybackHooks();','    YMInstall();')
    replace(entry,'    YTKACEInstallSettingsEntryHooks();','    // Native settings category only; no extra navigation button.')
    replace(entry,'__attribute__((constructor))\nstatic void YTKACEEntryPoint(void)', 'static void YTKACEEntryPoint(void)')
    replace(entry,'        YTKACERegisterDefaults();','        YMPrepareFullDefaults();\n        YTKACERegisterDefaults();\n        YMApplyFullDefaults();')
    replace(entry,'        YTKACEScheduleFirstLaunch();','        // Integration defaults replace the upstream first-launch wizard.')
    replace(entry,'        YTKACEInstallModules();','        YTKACEInstallModules();\n        YMStartFullDiagnostics();')
    with entry.open('a') as f:f.write('''
__attribute__((constructor)) static void YouTubeModEntry(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[NSBundle.mainBundle objectForInfoDictionaryKey:@"YouTubeModVersion"] isEqual:@"0.2.0"])
            YTKACEEntryPoint();
    });
}
''')
    native=ENGINE/'Tweak/Settings/NativeSettingsEntry.mm'
    replace(native,'return @"YTKACE";', 'return @"YouTube Mod";')
    replace(native,'items, category, @"YTKACE",','items, category, @"Настройки мода",')
    backup=ENGINE/'Tweak/Features/Downloads/YTKACEBackupManager.mm'
    replace(backup, 'if ([key isKindOfClass:NSString.class] && value != nil) {',
            'if ([key isKindOfClass:NSString.class] && [key hasPrefix:@"YTKACE.Preference."] && value != nil) {')
    return lock

def build():
    BUILD.mkdir(exist_ok=True);lock=prepare()
    sdk=os.environ.get('IOS_SDK_PATH') or subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
    from build_ffmpeg import build as build_ffmpeg
    ffmpeg=build_ffmpeg(sdk)
    shutil.copytree(ffmpeg,ENGINE/'Vendor/FFmpeg',dirs_exist_ok=True)
    makefile=(ENGINE/'Makefile').read_text()
    names=re.findall(r'(?:Tweak|Vendor)/[^\s\\]+\.(?:mm|m)',makefile.split('YTKACE_CFLAGS')[0])
    # Our tested six background getters replace the engine's background module.
    names=[x for x in names if x!='Tweak/Features/Playback/BackgroundPlaybackHooks.mm']
    sources=[ENGINE/x for x in names]+[ROOT/'src/Core.m',ROOT/'src/FullBridge.m',ROOT/'src/FullDefaults.m']
    objects=BUILD/'full-objects';objects.mkdir(exist_ok=True)
    common=['-target','arm64-apple-ios17.0','-isysroot',sdk,'-fobjc-arc','-fblocks','-O2','-Wall','-Wextra','-Werror=return-type','-Wno-module-import-in-extern-c','-DYTKACE_COMBINED_SABR=1','-DYTKACE_VERSION_STRING="1.1.8"','-DYM_FULL=1','-I'+str(ROOT/'src'),'-I'+str(ENGINE/'Vendor/FFmpeg/include'),'-I'+str(ENGINE/'Vendor/DuoKit')]
    def compile_one(pair):
        index,source=pair;obj=objects/(f'{index:03d}-'+source.stem+'.o')
        flags=['-std=c++17'] if source.suffix=='.mm' else []
        proc=subprocess.run(['xcrun','clang++' if flags else 'clang',*common,*flags,'-c',str(source),'-o',str(obj)],capture_output=True,text=True)
        (objects/(obj.stem+'.log')).write_text(proc.stdout+proc.stderr)
        if proc.returncode:raise RuntimeError(source.name+'\n'+proc.stderr[-10000:])
        return obj
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        compiled=list(pool.map(compile_one,enumerate(sources)))
    frameworks='Foundation UIKit JavaScriptCore AVFoundation AVFAudio AVKit AudioToolbox Photos QuartzCore MediaPlayer Security SystemConfiguration UniformTypeIdentifiers VideoToolbox CoreMedia CoreVideo CoreGraphics ImageIO'.split()
    library=BUILD/'YouTubeMod.dylib'
    args=['xcrun','clang++','-target','arm64-apple-ios17.0','-isysroot',sdk,'-dynamiclib','-install_name','@rpath/YouTubeMod.dylib',*[str(p) for p in compiled]]
    for name in frameworks:args+=['-framework',name]
    args+=['-lz','-licucore']+[str(ENGINE/f'Vendor/FFmpeg/lib/lib{name}.a') for name in ('avformat','avcodec','avutil','swscale')]+['-o',str(library)]
    subprocess.run(args,check=True)
    subprocess.run(['codesign','--force','--sign','-','--timestamp=none',str(library)],check=True)
    subprocess.run(['codesign','--verify','--strict',str(library)],check=True)
    (BUILD/'full-build.json').write_text(json.dumps({'engine_commit':lock['commit'],'compiled_units':len(compiled),'library_sha256':sha(library),'sdk':str(sdk)},indent=2)+'\n')
    print(f'Full feature engine: {len(compiled)} compilation units built')

if __name__=='__main__':build()
