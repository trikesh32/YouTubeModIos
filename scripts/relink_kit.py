"""Ship objects and exact FFmpeg source so recipients can replace/relink LGPL code."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[1]
def create(kit):
    output=kit/'relink'
    if output.exists():shutil.rmtree(output)
    (output/'objects').mkdir(parents=True)
    for p in (ROOT/'build/full-objects').glob('*.o'):
        shutil.copy2(p,output/'objects'/p.name)
    ff=ROOT/'build/ffmpeg-work'
    shutil.copytree(ff/'Vendor/FFmpeg/lib',output/'ffmpeg-lib')
    shutil.copy2(ff/'.build/ffmpeg/ffmpeg-8.1.2.tar.xz',output)
    shutil.copy2(ff/'Scripts/build-ffmpeg.sh',output/'build-ffmpeg.sh')
    shutil.copy2(ROOT/'build/full-build.json',output)
    (output/'relink.py').write_text('''import os, pathlib, subprocess, sys
root=pathlib.Path(__file__).resolve().parent
sdk=os.environ.get('IOS_SDK_PATH') or subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
libs=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else root/'ffmpeg-lib'
out=root/'YouTubeMod.dylib'
args=['xcrun','clang++','-target','arm64-apple-ios17.0','-isysroot',sdk,'-dynamiclib','-install_name','@rpath/YouTubeMod.dylib']
args += [str(p) for p in sorted((root/'objects').glob('*.o'))]
for name in 'Foundation UIKit JavaScriptCore AVFoundation AVFAudio AVKit AudioToolbox Photos QuartzCore MediaPlayer Security SystemConfiguration UniformTypeIdentifiers VideoToolbox CoreMedia CoreVideo CoreGraphics ImageIO'.split(): args += ['-framework',name]
args += ['-lz','-licucore']+[str(libs/('lib'+name+'.a')) for name in ('avformat','avcodec','avutil','swscale')]+['-o',str(out)]
subprocess.run(args,check=True)
subprocess.run(['codesign','--force','--sign','-','--timestamp=none',str(out)],check=True)
print(out)
''')
    (output/'README.txt').write_text('''FFmpeg is statically linked under LGPL; replacement and debugging of modifications are permitted.
The exact unmodified FFmpeg 8.1.2 source archive, build recipe, original static libraries
and non-FFmpeg object files accompany this kit. Apple SDK/frameworks are not included.
Full integration source: https://github.com/trikesh32/YouTubeModIos (0.2.0).
Rebuild FFmpeg through scripts/build_ffmpeg.py in the source repository, modifying
its source as desired (remove its build.json cache marker to force recompilation).
Run: IOS_SDK_PATH=/path/to/iPhoneOS.sdk python3 relink.py /path/to/rebuilt/FFmpeg/lib
This outputs relink/YouTubeMod.dylib. Copy it over the kit's YouTubeMod.dylib and
update manifest.json library_sha256 to its SHA256, then pack your own decrypted IPA.
Only replacement of FFmpeg is needed for LGPL relinking; rebuilding all modules
from their available MIT sources is also supported. Re-sign/install with your own
installation method. Do not redistribute Apple's SDK or proprietary app binaries here.
''')
