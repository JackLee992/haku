# Haku

Haku exports an installed iOS application into a validated analysis IPA, directly
on a rootless jailbreak device. Install its `.deb` with Sileo, open **Haku**,
select an application, and share the IPA and its JSON evidence report.
Keep Haku in the foreground until the export finishes. Swipe an export in the
Exports screen to remove its files, including retained failed runs.

The first implementation targets iOS 15+ on a **previously activated rootless
jailbreak** with **haku-server 17.24.3+haku.1** (Frida protocol 17.24.3).
Device-tested combinations are recorded in
[docs/VALIDATION.md](docs/VALIDATION.md); the deployment target is not a tested
compatibility matrix. Use only applications and devices you own or are authorized
to assess.

## How it works

Haku connects to its own haku-server service at `127.0.0.1:57042`, restarts the
selected application, and captures loaded images while its main thread stays
suspended. It copies the original bundle into a new private export folder and
patches only declared encryption ranges in that copy. It never rewrites the
installed application.

Each captured range is bound to the image's path, architecture and UUID. Chunks
are acknowledged after writing, keeping memory use bounded and rejecting holes
and duplicate/out-of-order chunks. Haku checks unchanged file size, unchanged
identity, `cryptid` transitions, changed encryption bytes and unchanged stable
bytes. It then creates a streaming ZIP and verifies every member's CRC and size.

**Main verified** and **fully verified** are separate report fields. Unloaded
extensions, unsupported slices and malformed images remain explicit. A failed
main gate produces a report and retained partial files without a finished IPA.
Originally clear executables are reported as `already_clear`.

Exports are under `~/Documents/Haku/<bundle>-<run-id>/` on the phone and available
through Haku's **Exports** screen. Failed export folders are preserved. Successful
exports remove only their temporary bundle copy. The derived IPA's original
signature is invalidated; signing, reinstallation and ordinary app behavior are
separate from acquisition validation.

## Build

Requirements: macOS, Xcode command-line tools, Python 3, and `ldid` (`brew install
ldid`). No Theos installation or third-party Python packages are required.

```sh
python3 -m unittest discover -s Tests -v
python3 scripts/build.py
```

The build downloads an official, SHA-256-pinned Frida Core devkit into `.build/`.
Set `LDID` to an absolute executable path when it is outside `PATH`.
Output: `dist/com.jacklee.haku_0.2.0_iphoneos-arm64.deb` and `dist/build.json`.
Install the matching [haku-server package](https://github.com/JackLee992/haku-server/releases)
first; Haku's dependency pins `17.24.3+haku.1`. The original Frida service can
remain installed independently.

## Connection port

Both Haku and haku-server default to loopback port **57042**, separate from
ordinary Frida ports **27042/27043**. To use another port, run `hakuctl port 58000`
as root on the phone, then save **58000** in **Haku > Connection > Port**.
The daemon setting is preserved across upgrades; Haku remembers its connection
port. The app changes its destination only, so set both sides to the same value.
Invalid ports and 27042/27043 are rejected. There is no automatic fallback.

The executable also supports a terminal interface using the same engine:

```sh
/var/jb/Applications/Haku.app/Haku --list
/var/jb/Applications/Haku.app/Haku --port 58000 --list
/var/jb/Applications/Haku.app/Haku --connection
/var/jb/Applications/Haku.app/Haku --set-port 58000
/var/jb/Applications/Haku.app/Haku --dump com.example.ownedapp \
  /var/mobile/Documents/Haku/new-run-folder
```

## Maintenance

GitHub Actions runs integrity tests and builds the rootless package on macOS.
Version tags publish prerelease `.deb` and build metadata to GitHub Releases.
The prereleases were built and tested locally because GitHub currently
blocks this account's jobs at the billing/spending-limit gate.
Only generic source and synthetic tests belong in Git. `.build/`, `dist/`,
`evidence/`, IPAs, device identifiers, credentials and real app captures are
excluded. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/REFERENCES.md](docs/REFERENCES.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
