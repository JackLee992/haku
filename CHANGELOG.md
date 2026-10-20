# Changelog

## 0.2.0 — 2026-10-21 (prerelease)

- Separate haku-server package dependency, based on Frida Core 17.24.3.
- Default loopback port 57042, independent of ordinary Frida ports 27042/27043.
- Connection screen with a saved custom port; terminal `--port`, `--connection`
  and `--set-port` options. Invalid and reserved Frida ports are rejected.
- Export reports identify the selected server endpoint and current app version.
- Three additional host connection tests, including boundary and invalid inputs.

## 0.1.0 — 2026-10-20 (prerelease)

- Native application list/search, capture progress, cancellation, export history,
  share action, and deletion of selected export folders.
- On-device loopback Frida client and suspended-start capture of loaded images.
- UUID/architecture binding, acknowledged chunk coverage and stable-byte checks.
- Streaming IPA creation with CRC, size, directory and member verification.
- Rootless Sileo package, pinned Frida development kit, embedded source identity,
  and GitHub build/release workflow.
- Eighteen host regression checks and a completed physical-device engine run.
- GUI idle assertion during export; hands-on GUI acceptance deferred to owner.
