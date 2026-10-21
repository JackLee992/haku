from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == 'darwin', 'Progress formatting uses Foundation')
class ProgressTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        build = ROOT / '.build/tests'
        build.mkdir(parents=True, exist_ok=True)
        cls.tool = build / 'progress-test'
        subprocess.run(['clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-I', str(ROOT/'Sources'),
                        str(ROOT/'Tests/progress-main.m'), str(ROOT/'Sources/HakuProgress.m'),
                        '-framework', 'Foundation', '-o', str(cls.tool)], check=True)

    def format(self, count):
        return subprocess.check_output([str(self.tool), str(count)], text=True).strip()

    def test_ine_four_kib_capture_does_not_round_to_zero(self):
        self.assertEqual(self.format(4096), '4.0 KiB (4096 bytes)')

    def test_bytes_zero_and_unit_boundaries(self):
        for count, expected in [(0, '0 bytes'), (1, '1 byte'), (1023, '1023 bytes'),
                                (1024, '1.0 KiB (1024 bytes)'),
                                (1048576, '1.0 MiB (1048576 bytes)'),
                                (1073741824, '1.0 GiB (1073741824 bytes)')]:
            with self.subTest(bytes=count):
                self.assertEqual(self.format(count), expected)
