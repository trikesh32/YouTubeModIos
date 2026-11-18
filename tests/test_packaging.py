import sys
from pathlib import Path
import tempfile
import unittest
import struct
import zipfile
import plistlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from macho import inject, commands, check_decrypted, thin_arm64
from project import extract, inspect_app
from metadata import compare_methods


def fixture():
    data = bytearray(1024)
    struct.pack_into('<8I', data, 0, 0xfeedfacf, 0x100000c, 0, 2, 1, 152, 0, 0)
    struct.pack_into('<II', data, 32, 0x19, 152)
    struct.pack_into('<I', data, 32 + 64, 1)
    struct.pack_into('<I', data, 32 + 72 + 48, 512)
    return data


class PackagingTests(unittest.TestCase):
    def test_fat_arm64_selection_and_bounds(self):
        data = bytearray(4096 + 1024)
        struct.pack_into('>7I', data, 0, 0xcafebabe, 1, 0x100000c, 0, 4096, 1024, 12)
        data[4096:] = fixture()
        self.assertEqual(thin_arm64(data), fixture())
        struct.pack_into('>I', data, 20, 2048)
        with self.assertRaises(ValueError): thin_arm64(data)

    def test_fat_table_slice_disagreement(self):
        data = bytearray(4096 + 1024)
        struct.pack_into('>7I', data, 0, 0xcafebabe, 1, 0x100000c, 0, 4096, 1024, 12)
        data[4096:] = fixture();struct.pack_into('<I', data, 4100, 7)
        with self.assertRaises(ValueError): thin_arm64(data)

    def test_inject_preserves_payload_and_rejects_duplicate(self):
        original = fixture();original[512:] = b'x' * 512
        result = inject(original)
        self.assertEqual(result[512:], original[512:])
        self.assertEqual(len(commands(result)), 2)
        with self.assertRaises(ValueError): inject(result)

    def test_nonzero_padding_and_wrong_arch(self):
        data = fixture();data[184] = 1
        with self.assertRaises(ValueError): inject(data)
        data = fixture();struct.pack_into('<I', data, 4, 7)
        with self.assertRaises(ValueError): inject(data)

    def test_encrypted_image(self):
        data = fixture()
        struct.pack_into('<II', data, 16, 2, 176)
        struct.pack_into('<6I', data, 184, 0x2c, 24, 0, 100, 1, 0)
        with self.assertRaises(ValueError): check_decrypted(data)
        struct.pack_into('<I', data, 200, 0);check_decrypted(data)

    def test_malformed_commands(self):
        data = fixture();struct.pack_into('<I', data, 36, 0)
        with self.assertRaises(ValueError): commands(data)

    def test_archive_escape(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td);ipa = root / 'input.zip'
            with zipfile.ZipFile(ipa, 'w') as z: z.writestr('../escape', 'bad')
            with self.assertRaises(ValueError): extract(ipa, root / 'out')
            self.assertFalse((root / 'escape').exists())

    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td);ipa = root / 'input.zip'
            entry = zipfile.ZipInfo('Payload/App.app/link');entry.external_attr = 0o120777 << 16
            with zipfile.ZipFile(ipa, 'w') as z: z.writestr(entry, '/tmp/target')
            with self.assertRaises(ValueError): extract(ipa, root / 'out')

    def test_modded_input_rejected_before_metadata(self):
        with tempfile.TemporaryDirectory() as td:
            app = Path(td);(app / 'Frameworks').mkdir()
            (app / 'Frameworks/YTLite.dylib').write_bytes(b'not executed')
            (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.google.ios.youtube','CFBundleExecutable':'YouTube'}))
            with self.assertRaisesRegex(ValueError, 'modifications'):
                inspect_app(app, {'required_methods':[]})

    def test_abi_change_is_reported(self):
        req=[{'class':'Video','kind':'-','selector':'available','types':'B16@0:8'}]
        self.assertEqual(compare_methods({('Video','-','available'):'B16@0:8'}, req), [])
        self.assertEqual(compare_methods({('Video','-','available'):'@16@0:8'}, req)[0]['reason'], 'abi_changed')
        self.assertEqual(compare_methods({}, req)[0]['reason'], 'missing')


if __name__ == '__main__': unittest.main()
