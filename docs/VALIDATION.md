# Validation

The acceptance criteria are in [ARCHITECTURE.md](ARCHITECTURE.md).

## 0.2.2: foreground capture and exact byte counts

Validated on **2026-10-21** on the same iPhone 12 / iOS 16.1.1 / Dopamine
rootless device, with **haku-server 17.24.3+haku.2**. The
[sanitized record](validation/2026-10-21-0.2.2.json) contains the final package
identities and measured gates; raw targets, captures and device identifiers
remain private.

The previous GUI flow launched the target visibly while its main thread was
deliberately suspended for capture. That displayed a white target screen and
allowed iOS to suspend Haku during packaging. Reopening Haku resumed a retained
run. The final pair launches the target in the background; Haku also requests
finite background time, cancels on expiration, and restores its prior idle
setting when finished.

| Gate on the final installed pair | Result |
| --- | --- |
| Client/server host regressions | **28 client**, **9 server** checks passed |
| Physical GUI selection with active search | **Passed** through the real UIKit table callback; 33 samples all show Haku active |
| Export completion and share sheet | **Passed in 9.529 seconds**, including instrumentation setup; `Export verified` and a real `UIActivityViewController` |
| Lifecycle cleanup | Previous idle setting restored; finite background task ended |
| Small encrypted range | Original Mach-O declares **4,096 bytes**; UI displays **4.0 KiB (4096 bytes)** |
| Complete output | **20,628,414 bytes** of app files copied; main executable **4,886,128 bytes**; IPA **16,297,676 bytes** |
| Independent archive verification | All **60** ZIP members pass a separate Python CRC check |
| Independent main validation | Same UUID/size, `cryptid` 1 → 0, unchanged stable bytes; decrypted entry-point instructions are coherent |
| Independent live corroboration | A fresh original process, original USB Frida service and separate one-shot collector produce the exact same **4,096 plaintext bytes** |
| Other native image | Already clear; complete file remains byte-identical to its original |
| Custom port on the final pair | Full export succeeds at **58000**; old 57042 listener rejects connections; both final settings restored to **57042** |
| Mac shared-core integration | Final pair exports/retrieves the IPA; local SHA-256 and all 60 ZIP members pass; a larger target cancels through the exact CLI worker PID with a retained `cancelled` report |
| Original Frida coexistence | Original binary hash and daemon PID unchanged across pair installation |
| Server GitHub CI | [Source build passed](https://github.com/JackLee992/haku-server/actions/runs/39542534072) |
| Client GitHub CI | [Run](https://github.com/JackLee992/haku/actions/runs/39543694781) blocked before steps by the account payment/spending gate; local checks/build passed |

The captured count measures encrypted ranges, rather than total app size. This
sample's independently inspected encryption command declares one 4 KiB range,
containing its entry point. The evidence above checks its actual contents,
rather than relying on the count or a cleared `cryptid` alone. A separate IPA
inspector marks coverage partial for a zero-sized encryption command in the
already-clear framework; that framework has no encrypted bytes to capture and
its entire file was independently compared unchanged.

A separate QA identity was development-signed with an existing device-qualified
profile, verified and installed through the normal iOS installer. Both that
copy and an ordinary fresh launch of the installed original produced white USB
screenshots for 30 seconds. A later read-only diagnostic confirmed the QA copy
was active, its main queue responded, and its SwiftUI hosting controller and
populated view tree existed. The executable also contains explicit screenshot
protection code. That is consistent with capture privacy, but does not by itself
prove the visible screen is correct. **Visual and functional acceptance remain
unverified**. The original app was preserved; no capture protection, account,
entitlement or device-security bypass was added.

The GUI test uses a temporary app-level agent on a physical phone; it is not a
physical-touch or XCTest result. The share sheet was presented, without sending
files. Sileo local-file import remains manual acceptance. The Mac export and
cancellation checks exercise the GUI's shared core through its diagnostic
probe; see [Haku Mac validation](https://github.com/JackLee992/haku-mac/blob/main/docs/VALIDATION.md)
for its separate UI and packaging evidence.

Client build revision: `ac6a3b91bd7765d80dc5a9e9f96c15ea79b93adb`.
Server build revision: `1a30e4b07c059a22787b27c257baf74ee63e54b3`.
Each release's `build.json` records source and package hashes. Documentation
commits after these builds do not alter the tested release assets.

## 0.2.1: unrestricted app discovery and final package verification

Validated on **2026-10-21 (Asia/Shanghai)** on iPhone 12 / iOS 16.1.1 /
Dopamine rootless, using the installed Haku CLI and the GUI's shared engine.
The unchanged server package is **17.24.3+haku.1**, on `127.0.0.1:57042`.
The matching [sanitized JSON record](validation/2026-10-21.json) is also
maintained in the server repository.

| Gate | Result |
| --- | --- |
| Haku host integrity, archive, package, port and process-exit regressions | **25 passed** |
| Maintained server host checks | **8 passed**; server package and executable unchanged |
| Application discovery | **44 applications**, including **37 Apple applications**; no bundle-ID, prefix or installation-directory filtering |
| Previous encrypted target, fresh full export | **Passed in 33 seconds**: 33 encrypted images verified, 2 already clear, 235,618,304 bytes captured |
| Reproducibility | IPA SHA-256 exactly matches the 0.2.0 default-port and earlier custom-port exports; all 35 native image records match |
| Independent validation | All **1,383** ZIP members pass CRC checks; the independent main Mach-O comparator passes against the fresh original from the preceding rerun |
| Owner-built development app | Passed; 1 already-clear image, 29 ZIP members independently checked |
| Apple-prefix system app (Calculator) | Passed; 1 already-clear image, 59 ZIP members independently checked |
| Haku itself from its rootless installation, using a separate CLI worker | Passed; 1 already-clear image, 10 ZIP members independently checked |
| Process restart and cleanup | Passed on the final package, including a pre-existing running development app |
| Output separation | Rejects output inside an app bundle before creating files; original native files unchanged |
| Server coexistence | Both daemon PIDs and server binary hashes unchanged across installation/capture; final connection succeeds on 57042 |
| New manga icon | Installed 120/180-pixel PNGs match the built package; opaque assets generated from the 1024-pixel master |
| Client GitHub-hosted CI | [Tagged run](https://github.com/JackLee992/haku/actions/runs/39533607564) blocked before job steps by the account payment/spending gate; local build and 25 checks passed |
| Sileo local-file GUI install, Haku GUI capture and share sheet | Manual acceptance remains deferred; terminal package installation and CLI capture were tested |

The three extra samples were already clear. Their successful exports establish
coverage beyond the former app filters, not additional FairPlay decryption
results. Enumeration of every installed app does not prove export compatibility
for every system app or device configuration.

The initial development-app attempt exposed a server stop request returning
while the old process remained alive, preventing a fresh spawn. The final client
confirms exit, terminates only the exact selected/capture-created PID when needed,
and waits for a bounded interval. Four host regressions cover a surviving child,
an already-exited process, self protection and process-group rejection. A fresh
complete device pass on the final package succeeded for all four samples.

Final package build revision: `e79d1f316913f73d0332aa87d58b6745ce7e9c22`.
Source SHA-256: `d19b62957d310053cf0da9a487d881ae92bb5392388303ef62789f0aa50c72e4`.
Package SHA-256: `61d75cac40a54ff45f3cc3b47fb67dd6aed70a179956f1434b8d6eb4956aced7`.
Documentation commits after the build do not change these release assets.

## 0.2.0: installed-suite rerun at the default port

The requested reproducibility rerun on **2026-10-21** completed acquisition,
native validation, IPA packaging, report persistence and private retrieval in
**32 seconds**, with Haku 0.2.0 and haku-server 17.24.3+haku.1 at
`127.0.0.1:57042`.

All **35 native image records** matched both the previous custom-port suite run
and the 0.1.0 baseline: **33 encrypted images verified, 2 already clear**, and
**235,618,304 bytes** captured. The IPA's SHA-256 matched the earlier suite export
exactly; a separate ZIP reader verified all **1,383** entries and compared their
contents and modes. The independent main comparator passed: UUID preserved,
`cryptid` 1 → 0, encryption-region bytes changed, stable bytes unchanged, and
no remaining encrypted command in the main executable.

All 35 installed original native images and the Haku/server binaries retained
their pre-run hashes. Both server PIDs remained unchanged and the final app-list
connection succeeded. The successful phone folder contained only the IPA and
JSON report. Raw files and identifiers remain private; the published JSON above
contains only the summary.

## 0.2.0 with haku-server

Validated on 2026-10-21 on the same iPhone 12 / iOS 16.1.1 / Dopamine rootless
environment. The server is the maintained Frida Core 17.24.3 fork, packaged as
`com.jacklee.haku-server` version `17.24.3+haku.1`, with an arm64/arm64e universal
executable and a separate launchd service.

| Gate | Status |
| --- | --- |
| Haku host integrity, package and connection checks | 21 passed |
| Server host package, port and restart checks | 7 passed in the original release lane; maintained branch now has 8 including branded-tag discovery |
| Default 57042 and custom 58000 enumeration | Passed |
| App port preference across fresh processes | Passed |
| Daemon restart and upgrade preserve custom port | Passed |
| Reserved 27042/27043 and malformed values | Rejected on client, server and daemon control |
| Old port after change | Rejected connection; no fallback to ordinary Frida |
| Full acquisition through haku-server on 58000 | Passed: 33 encrypted images verified, 2 originally clear, 235,618,304 captured bytes |
| Archive and independent main checks | 1,383 ZIP members passed independent CRC checks; main comparison passed and matches prior validated bytes |
| Ordinary Frida coexistence | Passed; original PID and executable hash unchanged; enumeration still works |
| Final connection settings | Both client and daemon restored to 57042 |
| Connection screen, GUI capture and share sheet | Owner elected to check manually; remain unverified |
| Haku private-repository hosted CI | Billing/spending gate prevents job steps; local tests/build passed |

Tested Haku code revision: `df132d0a261033144028fe10b51959012e8f2425`.
Source SHA-256: `75bc11d569bc9807dc5c473cd4a387b233cba35bdd878ecaedcac1a420f70cd0`.
Release assets carry their own revision and package hashes in `build.json`.
See the [server validation record](https://github.com/JackLee992/haku-server/blob/haku/haku/VALIDATION.md)
for server build and acceptance details.

## Historical 0.1.0 with the upstream Frida service

| Gate | Current status |
| --- | --- |
| Host Mach-O, archive, cancellation and Debian-package regression tests | **18 passed** on macOS |
| iOS arm64 build and rootless package inspection | **Passed**; deployment target 15.0; `iphoneos-arm64`; `/var/jb/Applications/Haku.app` |
| Package installation and on-device Frida client/app enumeration | **Passed** as the mobile user |
| On-device end-to-end acquisition | **Passed**: main + 32 other encrypted images verified; 2 originally clear images preserved; 235,618,304 bytes captured |
| ZIP gate | **Passed** on-device; 1,383 ZIP entries; a separate Python reader verified the prior identical-workflow archive |
| Independent main-executable gate | **Passed** with the separately maintained Mach-O comparator; source hash matches the authorized original; derived hash also matches the previously validated export |
| Successful temporary bundle cleanup | **Passed**; only the final IPA and JSON report remain in that successful run |
| Visible application list | **Observed** on the physical phone before the final idle-timer fix |
| End-to-end GUI capture, idle-timer restoration and share-sheet delivery | Owner elected to perform the hands-on UI check; these remain **unverified** |
| Other device/OS combinations | **Not tested** |
| GitHub-hosted CI execution | **Blocked by GitHub account billing/spending limit**, before any job steps ran; local build/tests completed |

Physical environment: iPhone 12 (`iPhone13,2`), iOS 16.1.1, Dopamine rootless,
Frida server/client 17.24.3. Acquisition was exercised through Haku's terminal
entry, using the same engine as the GUI. No manual touch result is inferred.

The first native run passed all image transitions but rejected the ZIP during
verification. Independent ZIP reading established that compression was valid;
the verifier was corrected to handle zlib's input-exhausted `Z_BUF_ERROR` state
while retaining CRC, expanded-size, final-stream and inventory checks. A new
complete run on the final code passed. A GUI attempt also exposed auto-lock
suspension; the final GUI takes an idle assertion during export and restores
the previous idle setting on completion. Its physical GUI acceptance is deferred.

Tested code revision: `b8effce2f42579a7ce9de7808aa1786301653e76`.
Source SHA-256: `b1d907a8bc2c8544e27e27874410c06f02998a6a3de907ac6ed11de63bce33ab`.
Package SHA-256: `41fb7e88bb646065dda7279d65b775489630da183fa7930f338fadd372f6fda2`.

These gates concern acquisition and packaging. They do not establish
reinstallation, ordinary target-app launch, signing, or functional behavior.

Real capture evidence remains in private local storage and is not committed.
