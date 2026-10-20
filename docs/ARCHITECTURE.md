# Architecture and acceptance criteria

Haku is a UIKit application delivered as a rootless Debian package, using
`iphoneos-arm64` and `/var/jb/Applications/Haku.app`. It uses the installed Frida
server's existing capabilities. It installs no persistent daemon, system hook,
remote listener, or exploit. The app is unsandboxed on the jailbroken device so
it can read the explicitly selected installed bundle. Its entitlements are kept
in `Resources/entitlements.plist`.

## Components

| Component | Responsibility |
| --- | --- |
| `HakuApp.m` | App list, search, capture progress, cancellation, export sharing; terminal interface |
| `HakuEngine.m` | Loopback Frida client, exact bundle selection, suspended spawn, private copy, chunk coverage, reports, cleanup |
| `capture.js` | Loaded-image identity and segment-aware range capture, without ObjC/main-queue work or forced framework loading |
| `HakuMachO.c` | Bounded Mach-O/FAT parser and strict encryption/stable-byte comparator |
| `HakuArchive.m` | Streaming deflate ZIP creation and per-member CRC verification |
| `scripts/build.py` | Pinned devkit, native build, entitlement signature, rootless `.deb` |

The app runs Frida work on one serial background queue and pumps the GLib context
there; UIKit stays on the main queue. Only the explicitly selected existing
target is restarted. Cleanup terminates the process created by that capture
before detaching. The capture profile suppresses `exit`, `_exit`, `abort`, `raise`
and self-directed `kill` in
that process during the capture; this is an acquisition aid, not an ordinary
launch or functional-behavior claim.

## Acceptance criteria

1. The selected installed bundle ID equals the runtime bundle ID and main path.
2. Every requested range matches the loaded image UUID and CPU identity.
3. Every chunk is within range, arrives once in order, and is fully written.
4. `cryptid` is cleared only after every requested byte has been captured.
5. The derived binary retains file size, UUID, architecture, load-command layout,
   and all bytes outside encrypted ranges and their `cryptid` words.
6. Each formerly encrypted range changes, and no encryption command remains in
   a file declared verified. Missing/unloaded or unsupported images are reported.
7. No final IPA is promoted if the main executable fails. A partial-image export
   keeps `fully_verified: false` and identifies each incomplete image.
8. ZIP creation and independent ZIP reading agree on inventory, bytes and CRC.
9. Existing export destinations are rejected and source app files remain intact.
10. Host tests, physical engine tests, visible UI and manual touch interaction are
    separate evidence gates.

## Current limits

Rootless iOS 15+ is the initial packaging lane. Rootful and RootHide relocation
are not implemented. Only little-endian 64-bit Mach-O slices are parsed. Universal
files with encrypted slices not loaded on this device cannot be fully verified.
Only loaded images are captured; extensions are not silently launched and unused
frameworks are not force-loaded. ZIP64 exports (4 GiB or 65,535 entries) are
rejected. Frida/API or device transport failures preserve partial results.

The native transition gate proves acquisition structure and full chunk coverage;
it is not a disassembler or a claim that every byte is meaningful plaintext.
Independent disassembly or a second capture can corroborate an important image.
