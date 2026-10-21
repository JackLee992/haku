from pathlib import Path
import importlib.util
import io
import plistlib
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("haku_build", ROOT / "scripts/build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class PackageTests(unittest.TestCase):
    def test_installed_app_version_matches_package(self):
        info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleShortVersionString'], build.VERSION)

    def test_rootless_archive_has_parent_directories_and_safe_modes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Haku.app"
            app.mkdir()
            (app / "Haku").write_bytes(b"synthetic executable")
            (app / "Info.plist").write_bytes(b"synthetic metadata")
            package = root / "fixture.deb"
            build.create_deb(app, package)
            data = package.read_bytes()
            self.assertEqual(data[:8], b"!<arch>\n")
            at, members = 8, {}
            while at < len(data):
                header = data[at:at + 60]
                self.assertEqual(header[58:], b"`\n")
                name = header[:16].decode().strip().rstrip("/")
                size = int(header[48:58])
                members[name] = data[at + 60:at + 60 + size]
                at += 60 + size + size % 2
            self.assertEqual(members["debian-binary"], b"2.0\n")
            with tarfile.open(fileobj=io.BytesIO(members["data.tar.gz"])) as archive:
                seen = set()
                for entry in archive:
                    path = Path(entry.name)
                    if entry.isfile():
                        self.assertIn(path.parent.as_posix(), seen)
                    if entry.isdir():
                        seen.add(path.as_posix())
                    self.assertEqual((entry.uid, entry.gid), (0, 0))
                    self.assertTrue(entry.name == "./var" or entry.name.startswith("./var/"))
                    self.assertFalse(entry.mode & 0o022)
                executable = archive.getmember("./var/jb/Applications/Haku.app/Haku")
                self.assertEqual(executable.mode, 0o755)
            with tarfile.open(fileobj=io.BytesIO(members["control.tar.gz"])) as archive:
                control = archive.extractfile("./control").read().decode()
                self.assertIn("Architecture: iphoneos-arm64", control)
                self.assertIn(f"com.jacklee.haku-server (= {build.HAKU_SERVER_VERSION})", control)
                self.assertNotIn("re.frida.server", control)
                self.assertTrue(archive.extractfile("./postinst").read().startswith(b"#!/var/jb/usr/bin/sh\n"))
