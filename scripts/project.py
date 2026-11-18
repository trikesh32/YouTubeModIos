"""Build and package the independent experimental YouTube module."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat
import subprocess
import tempfile
import zipfile

from macho import MAGIC64, check_decrypted, inject, thin_arm64
from metadata import read_methods, compare_methods

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / 'build' / 'kit'


def digest(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def extract(source, root):
    with zipfile.ZipFile(source) as z:
        names = z.namelist()
        if len(names) != len(set(names)) or len(names) > 100000:
            raise ValueError('Duplicate entries or excessive entry count')
        if sum(x.file_size for x in z.infolist()) > 4 * 1024**3:
            raise ValueError('IPA exceeds 4 GiB unpacked limit')
        for entry in z.infolist():
            path = PurePosixPath(entry.filename)
            mode = entry.external_attr >> 16
            if path.is_absolute() or '..' in path.parts or '\\' in entry.filename or stat.S_ISLNK(mode):
                raise ValueError('Unsafe archive path or symlink')
            target = root.joinpath(*path.parts)
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with z.open(entry) as src, target.open('wb') as dst:
                    shutil.copyfileobj(src, dst)
                target.chmod(0o755 if mode & 0o111 else 0o644)
    apps = list((root / 'Payload').glob('*.app'))
    if len(apps) != 1:
        raise ValueError('Expected one app')
    return apps[0]


def inspect_app(app, contract):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.google.ios.youtube':
        raise ValueError('Expected original YouTube bundle ID')
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable, str) or Path(executable).name != executable:
        raise ValueError('Invalid executable name')
    main = app / executable
    frameworks = app / 'Frameworks'
    # Conservative input policy: a known modded IPA is not a clean baseline.
    extra = [p.name for p in frameworks.iterdir() if p.suffix == '.dylib' and not p.name.startswith('libswift')] if frameworks.exists() else []
    suspicious = [p.name for p in app.iterdir() if p.name in {'YTLite.bundle', 'uYou.bundle'}]
    if extra or suspicious or info.get('YouTubeModVersion'):
        raise ValueError('Input already contains modifications: ' + ', '.join(extra + suspicious))
    check_decrypted(main.read_bytes())
    methods = read_methods(main, {m['class'] for m in contract['required_methods']})
    problems = compare_methods(methods, contract['required_methods'])
    return info, main, {
        'app_version': info.get('CFBundleShortVersionString'),
        'app_build': info.get('CFBundleVersion'), 'executable_sha256': digest(main),
        'checked_methods': len(contract['required_methods']),
        'static_compatible': not problems, 'problems': problems,
        'runtime_verified': False, 'clean_origin_verified': False,
        'scope': 'Selected ABI checks; absence of known mods is not proof of provenance',
    }


def build():
    subprocess.run(['bash', str(ROOT / 'scripts/build.sh')], check=True)
    return assemble_kit()


def assemble_kit():
    KIT.mkdir(parents=True, exist_ok=True)
    library = KIT / 'YouTubeMod.dylib'
    shutil.copy2(ROOT / 'build/YouTubeMod.dylib', library)
    notices = KIT / 'THIRD_PARTY_NOTICES.txt'
    notices.write_text('YouTubeModIos — MIT\n\n' + (ROOT / 'LICENSE').read_text() + '\nFeature engine integrated from YTKACE:\n\n' + (ROOT / 'licenses/YTKACE-MIT.txt').read_text() + '\n' + (ROOT / 'vendor/ytkace/THIRD_PARTY_NOTICES.md').read_text() + '\n' + (ROOT / 'vendor/ytkace/Vendor/FFmpeg/COPYING.LGPLv2.1').read_text() + '\n' + (ROOT / 'vendor/ytkace/Vendor/FFmpeg/COPYING.LGPLv3').read_text())
    from relink_kit import create as create_relink_kit
    create_relink_kit(KIT)
    with notices.open('a') as file:
        file.write('\n' + (ROOT / 'vendor/ytkace/Tweak/Features/Playback/PlaybackFixHooks.mm').read_text().split('*/', 1)[0] + '*/\n')
    resources = KIT / 'YTKACE.bundle'
    if resources.exists():
        shutil.rmtree(resources)
    shutil.copytree(ROOT / 'vendor/ytkace/Resources/YTKACE.bundle', resources)
    resource_hashes = {str(p.relative_to(KIT)): digest(p) for p in resources.rglob('*') if p.is_file()}
    manifest = {'engine': {'name': 'YTKACE', 'version': '1.1.8', 'commit': '5f8cb77bbd50249d2561a129afd3bb04313568ee'}, 'resources': resource_hashes, 'notices_sha256': digest(notices), 'format': 1, 'version': (ROOT / 'VERSION').read_text().strip(),
                'library_sha256': digest(library),
                'contract': json.loads((ROOT / 'compatibility/contract.json').read_text())}
    (KIT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return {'kit': str(KIT), 'version': manifest['version'], 'device_tested': False}


def copy_resources(kit, app, resources):
    for relative, expected in resources.items():
        parts = PurePosixPath(relative)
        if parts.is_absolute() or '..' in parts.parts or not parts.parts or parts.parts[0] != 'YTKACE.bundle' or '\\' in relative:
            raise ValueError('Unsafe resource path')
        resource = kit.joinpath(*parts.parts)
        if not resource.resolve().is_relative_to(kit.resolve()) or resource.is_symlink() or digest(resource) != expected:
            raise ValueError('Invalid resource checksum')
        destination = app.joinpath(*parts.parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(resource, destination)


def package(source, output, kit, allow_untested):
    if not allow_untested:
        raise ValueError('Prototype is not device-validated; use --allow-untested for an intentional test build')
    if output.exists():
        raise ValueError('Output exists; choose another name')
    manifest = json.loads((kit / 'manifest.json').read_text())
    library = kit / 'YouTubeMod.dylib'
    if manifest.get('format') != 1 or digest(library) != manifest.get('library_sha256'):
        raise ValueError('Invalid kit or library checksum')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='youtube-pack-', dir=output.parent) as td:
        temp = Path(td)
        app = extract(source, temp)
        info, main, report = inspect_app(app, manifest['contract'])
        if not report['static_compatible']:
            raise ValueError('Required ABI changed: ' + json.dumps(report['problems']))
        removed = []
        for name in ('PlugIns', 'Watch', 'AppClips'):
            folder = app / name
            if folder.exists():
                removed += [p.name for p in folder.iterdir()]
                shutil.rmtree(folder)
        for p in list(app.rglob('SC_Info')) + list(app.rglob('_CodeSignature')) + list(app.rglob('_MASReceipt')):
            if p.is_dir():
                shutil.rmtree(p)
        for p in app.rglob('embedded.mobileprovision'):
            p.unlink()
        (app / 'Frameworks').mkdir(exist_ok=True)
        shutil.copy2(library, app / 'Frameworks/YouTubeMod.dylib')
        if manifest.get('notices_sha256'):
            notices = kit / 'THIRD_PARTY_NOTICES.txt'
            if digest(notices) != manifest['notices_sha256']:
                raise ValueError('Invalid third-party notices checksum')
            shutil.copy2(notices, app / 'YouTubeMod-Licenses.txt')
        copy_resources(kit, app, manifest.get('resources', {}))
        main.write_bytes(inject(main.read_bytes()))
        info['YouTubeModVersion'] = manifest['version']
        info['UIFileSharingEnabled'] = True
        info['LSSupportsOpeningDocumentsInPlace'] = True
        if manifest.get('engine'):
            info['YouTubeModEngine'] = manifest['engine']['name'] + ' ' + manifest['engine']['version']
        (app / 'Info.plist').write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        images = []
        thinned = []
        for p in app.rglob('*'):
            if p.is_file():
                with p.open('rb') as f:
                    magic = f.read(4)
                if magic == b'\xca\xfe\xba\xbe':
                    p.write_bytes(thin_arm64(p.read_bytes()))
                    thinned.append(str(p.relative_to(app)))
                    magic = MAGIC64
                elif magic in (b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe'):
                    raise ValueError('Unsupported Mach-O format: ' + p.name)
                if magic == MAGIC64:
                    check_decrypted(p.read_bytes())
                    p.chmod(0o755)
                    images.append(p)
        for p in sorted(images, key=lambda p: len(p.parts), reverse=True):
            if p == main:
                continue
            target = p.parent if p.parent.suffix == '.framework' else p
            subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(target)], check=True, capture_output=True)
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(app)], check=True, capture_output=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
        pending = temp / 'result.ipa'
        with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for p in sorted(app.rglob('*')):
                if p.is_file():
                    z.write(p, p.relative_to(temp))
        with zipfile.ZipFile(pending) as z:
            if z.testzip():
                raise ValueError('Output ZIP integrity check failed')
        pending.rename(output)
    report.update({'module_version': manifest['version'], 'sha256': digest(output),
                   'removed_extensions': removed, 'thinned_images': thinned, 'adhoc_signature_verified': True,
                   'signing_required': True, 'input_sha256': digest(source)})
    output.with_suffix('.report.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command', required=True)
    sub.add_parser('build')
    inspect = sub.add_parser('inspect');inspect.add_argument('ipa', type=Path)
    pack = sub.add_parser('pack');pack.add_argument('ipa', type=Path)
    pack.add_argument('--output', type=Path, required=True)
    pack.add_argument('--kit', type=Path, default=KIT)
    pack.add_argument('--allow-untested', action='store_true')
    args = p.parse_args()
    if args.command == 'build':
        result = build()
    elif args.command == 'inspect':
        with tempfile.TemporaryDirectory(prefix='youtube-inspect-') as td:
            app = extract(args.ipa, Path(td))
            _, _, result = inspect_app(app, json.loads((ROOT / 'compatibility/contract.json').read_text()))
    else:
        result = package(args.ipa.resolve(), args.output.resolve(), args.kit.resolve(), args.allow_untested)
    print(json.dumps(result, indent=2))
    if result.get('static_compatible') is False:
        raise SystemExit(2)


if __name__ == '__main__':
    os.umask(0o077)
    try:
        main()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as e:
        raise SystemExit(str(e))
