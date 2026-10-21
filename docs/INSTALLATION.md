# Install Haku with Sileo

## Supported package and tested environment

Use an already activated **rootless jailbreak**, working Sileo, and the
`iphoneos-arm64` packages. The deployment target is iOS 15.0 or later; the
measured environment is **iPhone 12 / iOS 16.1.1 / Dopamine rootless**. A minimum
OS version is not a promise that every device, jailbreak layout or system app
can be captured. These packages use `/var/jb`.

| Install order | Package | Version | Download |
| --- | --- | --- | --- |
| 1 | `com.jacklee.haku-server` | `17.24.3+haku.1` | [Server release](https://github.com/JackLee992/haku-server/releases/tag/haku-v17.24.3-haku.1) · [rootless .deb](https://github.com/JackLee992/haku-server/releases/download/haku-v17.24.3-haku.1/com.jacklee.haku-server_17.24.3%2Bhaku.1_iphoneos-arm64.deb) |
| 2 | `com.jacklee.haku` | `0.2.1` | [Haku release](https://github.com/JackLee992/haku/releases/tag/v0.2.1) · [rootless .deb](https://github.com/JackLee992/haku/releases/download/v0.2.1/com.jacklee.haku_0.2.1_iphoneos-arm64.deb) |

Haku requires that exact server package version, using Frida protocol 17.24.3.
The server depends on `coreutils` and `dash`; Haku also needs `uikittools`.
Sileo can resolve those bootstrap dependencies from the device's existing sources.
The independently installed upstream Frida package does not satisfy Haku's server
dependency and can remain installed alongside it.

The Haku repository is currently **private**. Sign in to GitHub with an account
that has repository access before downloading its release. A private download
may return 404 when unauthenticated. haku-server's repository is public.

## On the iPhone

1. Open the **server release** above in Safari and save its `.deb` to Files.
2. In Files, select the downloaded file, use **Share → Sileo** (look under
   **More** if necessary), and install the local package from Sileo's package
   page. Complete the queue and any restart action Sileo requests.
3. Repeat with the **Haku 0.2.1** `.deb`. Install the server first because its
   release is not in the bootstrap repositories and Haku pins its exact version.
4. Open **Haku**. Both components initially use `127.0.0.1:57042`. Existing
   saved ports survive upgrades, so check **Connection** when upgrading.
5. Choose your installed app, keep Haku in the foreground until export finishes,
   then use **Share** or **Exports** to retrieve `export.ipa` and `report.json`.

Sileo implements local `.deb` import in its
[official 2.5.1 source](https://github.com/Sileo/Sileo/blob/c9f70158a037dc76b91c450e72af2de0514dd3ee/Sileo/AppDelegate.swift#L218-L237).
This is an installation guide based on package metadata and upstream Sileo
behavior; the test device's package installation was exercised from the terminal.
Hands-on Sileo import, Haku GUI export and the share sheet are separate manual
acceptance items in [VALIDATION.md](VALIDATION.md).

There is **no hosted Haku APT source** at present. Install the downloaded local
packages; a GitHub repository or release URL is not an address for Sileo's
**Sources → Add** screen. Future updates require downloading the new release.

## Download from an authenticated Mac

With GitHub CLI already authenticated to an account with Haku access:

```sh
mkdir -p ~/Downloads/Haku
gh release download haku-v17.24.3-haku.1 --repo JackLee992/haku-server \
  --pattern '*.deb' --dir ~/Downloads/Haku
gh release download v0.2.1 --repo JackLee992/haku \
  --pattern '*.deb' --dir ~/Downloads/Haku
```

AirDrop or otherwise transfer both files to the iPhone, then open them in Sileo
in the same server-first order. Each release includes `build.json` with package
SHA-256 and source provenance. To inspect local file hashes on macOS:

```sh
shasum -a 256 ~/Downloads/Haku/*.deb
```

The server package SHA-256 is
`25c0844918bdedc0a3ddfd981bc55294cddf3e33562b63e618d3672ba5a1ec77`.
The Haku 0.2.1 package SHA-256 is
`61d75cac40a54ff45f3cc3b47fb67dd6aed70a179956f1434b8d6eb4956aced7`.
Both values must match the respective release `build.json`; the 0.2.0 and
0.2.1 client packages are different files.

## Terminal installation and a connection check

If a terminal or SSH is already available on the phone, run these as **root**,
replacing the download directory with the actual device location:

```sh
/var/jb/usr/bin/dpkg -i /var/mobile/Downloads/com.jacklee.haku-server_17.24.3+haku.1_iphoneos-arm64.deb
/var/jb/usr/bin/dpkg -i /var/mobile/Downloads/com.jacklee.haku_0.2.1_iphoneos-arm64.deb
/var/jb/usr/bin/hakuctl status
/var/jb/usr/sbin/haku-server --haku-info
```

If a bootstrap dependency is missing, install it through Sileo before retrying.
Then run the app's commands as **mobile**, the same user as its GUI:

```sh
/var/jb/Applications/Haku.app/Haku --connection
/var/jb/Applications/Haku.app/Haku --list
```

`--connection` shows the saved destination; `--list` actually connects to the
server. Read [PORTS.md](PORTS.md) for custom ports, resetting defaults, SSH
forwarding and troubleshooting.

## Selecting applications and interpreting an export

Haku 0.2.1 has no target bundle-ID allowlist, prefix blocklist or fixed
installation-directory filter. It shows every application returned by
haku-server, including system and rootless apps. Select your own app in the
list, or pass its exact installed bundle ID to `--dump`:

```sh
/var/jb/Applications/Haku.app/Haku --dump org.example.myapp \
  /var/mobile/Documents/Haku/myapp-lab-run-001
```

Use a **new absolute output directory outside app bundles** on each run. Haku
restarts the selected app; save its in-progress work first. A worker cannot
restart itself, so capturing Haku while its GUI is the worker requires a
separate terminal process. The target must be discoverable and launchable by
the server, and its runtime identity must match the selected installed app.

`main_verified`, `fully_verified` and `zip_verified` describe different checks.
Originally clear images are `already_clear`; unloaded or unsupported native
images stay explicit. An export does not prove that an app can be resigned,
reinstalled or used normally. Successful runs remove their temporary copy;
failed runs keep their evidence in `~/Documents/Haku/`.

## Common installation problems

| Symptom | Action |
| --- | --- |
| GitHub 404 for Haku | Use a GitHub account with access to the private Haku repository. |
| Sileo reports a missing `com.jacklee.haku-server` version | Install the matching server `.deb` first, then retry Haku. |
| Sileo reports a bad `.deb` | Redownload the actual asset, rather than a saved GitHub HTML page; check its SHA-256 against release metadata. |
| Wrong architecture or layout | Use the rootless `iphoneos-arm64` release in an active `/var/jb` jailbreak environment. |
| Haku cannot list applications | Check jailbreak activation and both saved ports using [PORTS.md](PORTS.md). |
| The old icon remains after upgrade | Finish Sileo's requested refresh/restart action; the package's post-install hook refreshes Haku with `uicache`. |

To uninstall, remove **Haku** through Sileo first, then **haku-server** if no
longer needed. Export files are managed separately in Haku's Exports screen.
