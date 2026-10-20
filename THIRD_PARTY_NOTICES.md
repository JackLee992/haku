# Third-party notices

Haku links the official Frida Core 17.24.3 development kit at build time.
Its download URL and SHA-256 are pinned in `scripts/build.py`.
Frida Core is licensed under LGPL-2.0 with the wxWindows Library Licence exception.
See [Frida Core COPYING](https://github.com/frida/frida-core/blob/17.24.3/COPYING)
and the licenses of the dependencies in the official development kit.
The development kit is downloaded, not checked into this repository.

The capture design was informed by the MIT-licensed
[frida-ios-dump](https://github.com/AloneMonkey/frida-ios-dump), including the
locally verified suspended-start workflow. Haku's native implementation and
capture agent were written for this project.

[TrollDecrypt](https://github.com/donato-fiore/TrollDecrypt) and
[bfdecryptor](https://github.com/abxyap/bfdecryptor) were reviewed as interface
and packaging references. Their implementation and assets are not copied.
