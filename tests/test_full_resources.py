import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from project import copy_resources

class FullResourcesTests(unittest.TestCase):
    def test_resources_verified_and_copied(self):
        with tempfile.TemporaryDirectory() as td:
            kit=Path(td)/'kit'; app=Path(td)/'app'
            source=kit/'YTKACE.bundle/ru.lproj/Localizable.strings'
            source.parent.mkdir(parents=True);source.write_bytes(b'translation')
            files={str(source.relative_to(kit)):hashlib.sha256(source.read_bytes()).hexdigest()}
            copy_resources(kit, app, files)
            self.assertEqual((app/source.relative_to(kit)).read_bytes(),source.read_bytes())
            source.write_bytes(b'changed')
            with self.assertRaises(ValueError):copy_resources(kit,app,files)

    def test_traversal_and_parent_symlinks_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);kit=root/'kit';kit.mkdir();app=root/'app'
            for path in ('../escape','/absolute','YTKACE.bundle/../../escape','Other.bundle/file','YTKACE.bundle\\file'):
                with self.assertRaises(ValueError):copy_resources(kit,app,{path:'unused'})
            outside=root/'outside';outside.mkdir();(outside/'file').write_bytes(b'x')
            (kit/'YTKACE.bundle').symlink_to(outside,target_is_directory=True)
            with self.assertRaises(ValueError):copy_resources(kit,app,{'YTKACE.bundle/file':hashlib.sha256(b'x').hexdigest()})
