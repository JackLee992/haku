import ctypes
import hashlib
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build/tests"


def fixture(encrypted=True, uuid=True):
    commands = (struct.pack("<II", 0x1B, 24) + bytes(range(16))) if uuid else b""
    commands += struct.pack("<IIIIII", 0x2C, 24, 4096, 4096, int(encrypted), 0)
    header = struct.pack("<IIIIIIII", 0xFEEDFACF, 0x100000C, 0, 2, 2 if uuid else 1, len(commands), 0, 0)
    data = bytearray(hashlib.shake_256(b"haku-synthetic-fixture").digest(12288))
    data[:len(header + commands)] = header + commands
    return data


def decrypted(data):
    result = data.copy()
    struct.pack_into("<I", result, 32 + 24 + 16, 0)
    result[4096:8192] = hashlib.shake_256(b"haku-synthetic-plaintext").digest(4096)
    return result


class MachOTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)
        library = BUILD / ("libhaku.dylib" if sys.platform == "darwin" else "libhaku.so")
        subprocess.run(["clang", "-shared", "-fPIC", "-Wall", "-Wextra", "-Werror", str(ROOT / "Sources/HakuMachO.c"), "-o", str(library)], check=True)
        cls.lib = ctypes.CDLL(str(library))
        cls.lib.haku_validate_transition.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]

    def validate(self, original, derived):
        self.assertEqual(len(original), len(derived))
        error = ctypes.create_string_buffer(256)
        a, b = ctypes.create_string_buffer(bytes(original)), ctypes.create_string_buffer(bytes(derived))
        return bool(self.lib.haku_validate_transition(a, b, len(original), error, len(error))), error.value.decode()

    def test_valid_uuid_bound_transition(self):
        original = fixture()
        self.assertTrue(self.validate(original, decrypted(original))[0])

    def test_header_only_fake_decryption_rejected(self):
        original = fixture()
        derived = original.copy()
        struct.pack_into("<I", derived, 72, 0)
        self.assertIn("did not change", self.validate(original, derived)[1])

    def test_stable_bytes_corruption_rejected(self):
        original = fixture()
        derived = decrypted(original)
        derived[10000] ^= 0x80
        self.assertIn("Stable bytes", self.validate(original, derived)[1])

    def test_uuid_substitution_rejected(self):
        original = fixture()
        derived = decrypted(original)
        derived[40] ^= 1
        self.assertIn("identity", self.validate(original, derived)[1])

    def test_remaining_encryption_rejected(self):
        original = fixture()
        derived = decrypted(original)
        struct.pack_into("<I", derived, 72, 1)
        self.assertIn("remains", self.validate(original, derived)[1])

    def test_missing_uuid_rejected(self):
        original = fixture(uuid=False)
        derived = original.copy()
        struct.pack_into("<I", derived, 48, 0)
        derived[4096] ^= 1
        self.assertIn("no UUID", self.validate(original, derived)[1])

    def test_range_outside_slice_rejected(self):
        original = fixture()
        struct.pack_into("<I", original, 64, 12000)
        self.assertIn("outside", self.validate(original, original)[1])

    def test_range_overlapping_commands_rejected(self):
        original = fixture()
        struct.pack_into("<I", original, 64, 32)
        self.assertIn("overlaps", self.validate(original, original)[1])

    def test_bad_load_command_rejected(self):
        original = fixture()
        struct.pack_into("<I", original, 36, 4)
        self.assertIn("command", self.validate(original, original)[1])

    def test_clear_image_must_remain_identical(self):
        original = fixture(encrypted=False)
        self.assertTrue(self.validate(original, original)[0])
        derived = original.copy()
        derived[4096] ^= 1
        self.assertFalse(self.validate(original, derived)[0])

    def test_fat_slice_transition(self):
        a, b = fixture(), None
        b = decrypted(a)
        prefix = bytearray(4096)
        prefix[:28] = struct.pack(">IIiiIII", 0xCAFEBABE, 1, 0x100000C, 0, 4096, len(a), 12)
        self.assertTrue(self.validate(prefix + a, prefix + b)[0])
        invalid = prefix + a
        struct.pack_into(">I", invalid, 16, 0xFFFFFFF0)
        self.assertIn("outside", self.validate(invalid, invalid)[1])


@unittest.skipUnless(sys.platform == "darwin", "Foundation archive integration requires macOS")
class ArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)
        cls.tool = BUILD / "archive-test"
        subprocess.run(["clang", "-fobjc-arc", "-fobjc-exceptions", "-I", str(ROOT / "Sources"), str(ROOT / "Tests/archive-main.m"), str(ROOT / "Sources/HakuArchive.m"), "-framework", "Foundation", "-lz", "-o", str(cls.tool)], check=True)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.payload = root / "Payload"
        self.app = self.payload / "Fixture.app"
        self.app.mkdir(parents=True)
        self.content = hashlib.shake_256(b"zip-content").digest(256000)
        (self.app / "binary").write_bytes(self.content)
        (self.app / "empty").write_bytes(b"")
        (self.app / "日本語.txt").write_text("Haku export\n")
        (self.app / "Resources").mkdir()
        (self.app / "link").symlink_to("binary")
        self.zip = root / "fixture.ipa"

    def create(self):
        subprocess.run([str(self.tool), "create", str(self.payload), str(self.zip)], check=True)

    def verify(self):
        return subprocess.run([str(self.tool), "verify", str(self.zip)], capture_output=True).returncode

    def test_independent_zip_reader_and_native_verifier(self):
        self.create()
        self.assertEqual(self.verify(), 0)
        with zipfile.ZipFile(self.zip) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(archive.read("Payload/Fixture.app/binary"), self.content)
            self.assertEqual(archive.read("Payload/Fixture.app/日本語.txt").decode(), "Haku export\n")
            self.assertEqual(archive.read("Payload/Fixture.app/link"), b"binary")
            self.assertEqual((archive.getinfo("Payload/Fixture.app/link").external_attr >> 16) & 0o170000, 0o120000)

    def test_archive_truncation_rejected(self):
        self.create()
        self.zip.write_bytes(self.zip.read_bytes()[:-5])
        self.assertNotEqual(self.verify(), 0)

    def test_large_highly_compressible_member(self):
        content = (b"Haku large resource fixture\n" * 300000) + bytes(range(256))
        (self.app / "large-resource").write_bytes(content)
        self.create()
        self.assertEqual(self.verify(), 0)
        with zipfile.ZipFile(self.zip) as archive:
            self.assertEqual(archive.read("Payload/Fixture.app/large-resource"), content)

    def test_payload_corruption_rejected(self):
        self.create()
        data = bytearray(self.zip.read_bytes())
        with zipfile.ZipFile(self.zip) as archive:
            entry = archive.getinfo("Payload/Fixture.app/binary")
            name_length, extra_length = struct.unpack_from("<HH", data, entry.header_offset + 26)
            at = entry.header_offset + 30 + name_length + extra_length + entry.compress_size // 2
        data[at] ^= 0x80
        self.zip.write_bytes(data)
        self.assertNotEqual(self.verify(), 0)

    def test_existing_archive_is_preserved(self):
        self.zip.write_bytes(b"keep-original")
        result = subprocess.run([str(self.tool), "create", str(self.payload), str(self.zip)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.zip.read_bytes(), b"keep-original")

    def test_cancel_preserves_source_and_does_not_finish_archive(self):
        result = subprocess.run([str(self.tool), "cancel", str(self.payload), str(self.zip)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Cancelled", result.stderr)
        self.assertEqual((self.app / "binary").read_bytes(), self.content)
        self.assertNotEqual(self.verify(), 0)


if __name__ == "__main__":
    unittest.main()
