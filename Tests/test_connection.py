from pathlib import Path
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform=="darwin", "Foundation connection tests require macOS")
class ConnectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        build=ROOT/".build/tests"
        build.mkdir(parents=True,exist_ok=True)
        cls.tool=build/"connection-test"
        subprocess.run(["clang","-fobjc-arc","-I",str(ROOT/"Sources"),str(ROOT/"Tests/connection-main.m"),str(ROOT/"Sources/HakuConnection.m"),"-framework","Foundation","-o",str(cls.tool)],check=True)

    def result(self,*args):
        return subprocess.run([str(self.tool),*args],capture_output=True,text=True)

    def test_default_is_separate_from_frida(self):
        self.assertEqual(self.result().stdout.strip(),"127.0.0.1:57042")

    def test_custom_port_is_used(self):
        for port in ("1","58000","65535"):
            with self.subTest(port=port):
                r=self.result(port)
                self.assertEqual(r.returncode,0)
                self.assertEqual(r.stdout.strip(),f"127.0.0.1:{int(port)}")

    def test_invalid_and_frida_ports_are_rejected(self):
        for port in ("","0","65536","-1","+57","57.0","57042 "," 57042","５７０４２","27042","27043","000001","1;echo wrong"):
            with self.subTest(port=port):
                r=self.result(port)
                self.assertEqual(r.returncode,2)
                self.assertIn("Enter a port",r.stderr)
