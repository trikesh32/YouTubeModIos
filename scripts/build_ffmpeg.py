"""Build the pinned LGPL-only FFmpeg dependency from its official source."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/ffmpeg-work'
HASH='464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c'
def digest(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def build(sdk):
    archive=WORK/'.build/ffmpeg/ffmpeg-8.1.2.tar.xz';archive.parent.mkdir(parents=True,exist_ok=True)
    if not archive.exists():
        pending=archive.with_suffix('.download')
        urllib.request.urlretrieve('https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz',pending)
        if digest(pending)!=HASH:raise ValueError('FFmpeg source checksum mismatch')
        pending.rename(archive)
    if digest(archive)!=HASH:raise ValueError('FFmpeg source checksum mismatch')
    output=WORK/'Vendor/FFmpeg';marker=output/'build.json'
    source=(ROOT/'vendor/ytkace/Scripts/build-ffmpeg.sh').read_text()
    source=source.replace('$(xcrun -sdk iphoneos -f clang)','$(xcrun -f clang)')
    fingerprint=hashlib.sha256((source+sdk).encode()).hexdigest()
    if marker.exists():
        previous=json.loads(marker.read_text())
        if previous.get('fingerprint')==fingerprint and all((output/name).exists() and digest(output/name)==sha for name,sha in previous['libraries'].items()):return output
    script=WORK/'Scripts/build-ffmpeg.sh';script.parent.mkdir(parents=True,exist_ok=True);script.write_text(source)
    env=dict(os.environ,SDK=sdk,THEOS=str(WORK/'unused-theos'),JOBS='6')
    subprocess.run(['bash',str(script)],env=env,check=True)
    marker.write_text(json.dumps({'source_sha256':HASH,'fingerprint':fingerprint,'libraries':{str(p.relative_to(output)):digest(p) for p in (output/'lib').glob('*.a')}},indent=2)+'\n')
    return output
if __name__=='__main__':
    sdk=os.environ.get('IOS_SDK_PATH') or subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
    print(build(sdk))
