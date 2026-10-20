# GitHub references reviewed on 2026-10-20

| Project | What it contributes to the decision | Fit for Haku |
| --- | --- | --- |
| [AloneMonkey/frida-ios-dump](https://github.com/AloneMonkey/frida-ios-dump) | Frida-based acquisition and IPA export; MIT license | Engine design reference. Haku moves the locally verified suspended-start approach onto the phone. |
| [donato-fiore/TrollDecrypt](https://github.com/donato-fiore/TrollDecrypt) | On-device app list, export/file management; rootless Theos configuration | Closest existing product. Its v1.2.4 release includes `iphoneos-arm64.deb`, rootful `.deb`, and `.tipa` assets. A useful first existing-tool trial, but Haku's exact workflow is a separate implementation. |
| [abxyap/bfdecryptor](https://github.com/abxyap/bfdecryptor) | Rootless/ElleKit tweak with per-app preferences and in-process dump | Closest tweak-style package. Its constructor dispatches the dump inside the target; that differs from an external suspended-process capture. |
| [34306/TrollDecryptJB](https://github.com/34306/TrollDecryptJB) | Rootless app, LLDB dependency, and early-start research | Broader scope includes App Store hooks and system-daemon actions. Haku uses its existing Frida route instead. |
| [ChiChou/bagbak](https://github.com/ChiChou/bagbak) | Frida-based export with extension modes; MIT license | Upstream currently marks this approach deprecated. It is a secondary reference, not the initial base. |

Reviewed TrollDecrypt default-branch revision:
`c4bd8c1b7efd248068fb82d7efacbf9d98a9ccf7`.
Reviewed TrollDecryptJB default-branch revision:
`1dad89b0132a0c3772aceddf53cbf25f0ac3ecfb`.
Reviewed bagbak default-branch revision:
`39621f9159ef906edcc65cc4813c0f283c8d136d`.

The GitHub metadata and root listings reviewed did not identify a repository-level
license for TrollDecrypt or TrollDecryptJB. Haku copies neither their source nor
their icons. Its UI, native engine, ZIP code and JS agent are maintained here.
Source review is not a physical compatibility test of any of these projects.
