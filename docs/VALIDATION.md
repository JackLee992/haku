# Validation

The acceptance criteria are in [ARCHITECTURE.md](ARCHITECTURE.md).

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
