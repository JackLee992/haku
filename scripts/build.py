#!/usr/bin/env python3
"""Build a rootless Sileo package using Xcode and a pinned Frida devkit."""
from pathlib import Path
import gzip
import hashlib
import io
import json
import os
import plistlib
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.1.0"
FRIDA = "17.24.3"
DEVKIT_SHA256 = "8e2daa0087eebeb64848dd2bcab2211380fc9b3294ca003482762ebb8ba113cb"


def run(args):
    subprocess.run([str(a) for a in args], check=True)


def fetch_devkit():
    directory = ROOT / ".build/devkit"
    directory.mkdir(parents=True, exist_ok=True)
    filename = f"frida-core-devkit-{FRIDA}-ios-arm64.tar.xz"
    archive = directory / filename
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != DEVKIT_SHA256:
        temporary = archive.with_suffix(".partial")
        url = f"https://github.com/frida/frida/releases/download/{FRIDA}/{filename}"
        for attempt in range(3):
            try:
                with urllib.request.urlopen(url, timeout=45) as response, temporary.open("wb") as output:
                    shutil.copyfileobj(response, output)
                if hashlib.sha256(temporary.read_bytes()).hexdigest() != DEVKIT_SHA256:
                    raise RuntimeError("Frida devkit checksum mismatch")
                temporary.replace(archive)
                break
            except Exception:
                if attempt == 2:
                    raise
    with tarfile.open(archive) as source:
        for name in ("frida-core.h", "libfrida-core.a"):
            try:
                member = source.getmember(name)
            except KeyError:
                member = source.getmember("./" + name)
            if not member.isfile():
                raise RuntimeError("Unexpected devkit member type")
            with source.extractfile(member) as data, (directory / name).open("wb") as output:
                shutil.copyfileobj(data, output)
    return directory


def tar_bytes(files):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as archive:
        for name, data, mode in files:
            entry = tarfile.TarInfo(name)
            entry.size = len(data) if data is not None else 0
            entry.mode = mode
            entry.uid = entry.gid = 0
            entry.mtime = 0
            if data is None:
                entry.type = tarfile.DIRTYPE
            archive.addfile(entry, io.BytesIO(data) if data is not None else None)
    return gzip.compress(raw.getvalue(), mtime=0)


def create_deb(app, destination):
    control = f"""Package: com.jacklee.haku
Name: Haku
Version: {VERSION}
Architecture: iphoneos-arm64
Description: On-device application acquisition with verified IPA export
Maintainer: JackLee992
Author: JackLee992
Section: Applications
Depends: firmware (>= 15.0), re.frida.server (= {FRIDA}), uikittools
Homepage: https://github.com/JackLee992/haku
"""
    postinst = """#!/var/jb/usr/bin/sh
set -e
if [ "$1" = configure ]; then
    /var/jb/usr/bin/uicache -p /var/jb/Applications/Haku.app
fi
"""
    postrm = """#!/var/jb/usr/bin/sh
if [ "$1" = remove ] || [ "$1" = purge ]; then
    /var/jb/usr/bin/uicache -a >/dev/null 2>&1 || true
fi
"""
    control_tar = tar_bytes([("./control", control.encode(), 0o644), ("./postinst", postinst.encode(), 0o755), ("./postrm", postrm.encode(), 0o755)])
    files = [(name, None, 0o755) for name in ("./var/", "./var/jb/", "./var/jb/Applications/", "./var/jb/Applications/Haku.app/")]
    for path in sorted(app.rglob("*")):
        name = "./var/jb/Applications/Haku.app/" + path.relative_to(app).as_posix()
        if path.is_dir():
            files.append((name + "/", None, 0o755))
        if path.is_file():
            files.append((name, path.read_bytes(), 0o755 if path.name == "Haku" else 0o644))
    data_tar = tar_bytes(files)
    with destination.open("wb") as output:
        output.write(b"!<arch>\n")
        for name, data in [("debian-binary", b"2.0\n"), ("control.tar.gz", control_tar), ("data.tar.gz", data_tar)]:
            header = f"{name+'/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(data):<10}`\n".encode("ascii")
            if len(header) != 60:
                raise RuntimeError("Invalid ar header")
            output.write(header)
            output.write(data)
            if len(data) % 2:
                output.write(b"\n")


def main():
    devkit = fetch_devkit()
    build = ROOT / ".build"
    app = build / "Haku.app"
    if app.exists():
        shutil.rmtree(app)
    app.mkdir()
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    sources = [ROOT / "Sources" / name for name in ("HakuApp.m", "HakuEngine.m", "HakuArchive.m", "HakuMachO.c")]
    run(["xcrun", "--sdk", "iphoneos", "clang", "-arch", "arm64", "-isysroot", sdk, "-mios-version-min=15.0", "-O2", "-fobjc-arc", "-fobjc-exceptions", "-Werror=implicit-function-declaration", "-Wno-deprecated-declarations", "-I", devkit, *sources, "-L", devkit, "-lfrida-core", "-lbsm", "-ldl", "-lm", "-lresolv", "-lz", "-Wl,-dead_strip", "-framework", "Foundation", "-framework", "CoreFoundation", "-framework", "CoreGraphics", "-framework", "UIKit", "-o", app / "Haku"])
    shutil.copy2(ROOT / "Resources/Info.plist", app / "Info.plist")
    shutil.copy2(ROOT / "Agent/capture.js", app / "capture.js")
    shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.md", app / "THIRD_PARTY_NOTICES.md")
    if (ROOT / "LICENSES").exists():
        shutil.copytree(ROOT / "LICENSES", app / "LICENSES")
    run(["swift", ROOT / "scripts/icon.swift", app])
    ldid = os.environ.get("LDID") or shutil.which("ldid")
    if not ldid:
        raise SystemExit("ldid is required: brew install ldid, or set LDID to its absolute path")
    run([ldid, "-S" + str(ROOT / "Resources/entitlements.plist"), app / "Haku"])
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    deb = dist / f"com.jacklee.haku_{VERSION}_iphoneos-arm64.deb"
    create_deb(app, deb)
    metadata = {"version": VERSION, "frida": FRIDA, "devkit_sha256": DEVKIT_SHA256, "package": deb.name, "sha256": hashlib.sha256(deb.read_bytes()).hexdigest(), "architecture": "iphoneos-arm64", "minimum_ios": "15.0"}
    (dist / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
