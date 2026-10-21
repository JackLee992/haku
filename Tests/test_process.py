from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == 'darwin', 'Foundation process tests require macOS')
class ProcessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        build = ROOT / '.build/tests'
        build.mkdir(parents=True, exist_ok=True)
        cls.tool = build / 'process-test'
        subprocess.run(['clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-I', str(ROOT/'Sources'),
            str(ROOT/'Tests/process-main.m'), str(ROOT/'Sources/HakuProcess.m'), '-framework', 'Foundation',
            '-o', str(cls.tool)], check=True)

    def check_mode(self, mode):
        result = subprocess.run([str(self.tool), mode], capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_process_left_alive_by_a_stop_request_is_terminated(self):
        self.check_mode('left-running')

    def test_already_exited_process_is_accepted(self):
        self.check_mode('already-exited')

    def test_worker_cannot_terminate_itself(self):
        self.check_mode('self')

    def test_process_groups_and_invalid_pids_are_rejected(self):
        self.check_mode('invalid')
