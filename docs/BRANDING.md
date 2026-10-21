# Haku icon

<img src="../Resources/Brand/haku-chestnut.png" width="256" alt="A cheerful manga-style chestnut popping out of its open shell">

Haku's mascot is a golden chestnut kernel shrugging off an open brown shell.
The warm cream background, cocoa outlines, golden kernel and coral expression
replace the earlier realistic direction with a playful Japanese manga character.

The master is [Resources/Brand/haku-chestnut.png](../Resources/Brand/haku-chestnut.png),
a 1024 × 1024 opaque PNG. The package build resamples that asset into the existing
120 × 120 and 180 × 180 iPhone icon slots in sRGB; it no longer draws the old H
mark. Keep the outer canvas square so iOS supplies its own corner mask.

The design follows the simplicity, centered-content, legibility and unmasked
canvas guidance in [Apple's App icons HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons).
This release uses flattened PNGs for the existing iOS 15+ rootless package; it
does not add an Icon Composer project or appearance variants.

The artwork was generated from scratch with the built-in imagegen tool after
the owner requested a more creative manga direction. Earlier images were not
used as references. The final [generation prompt](brand-prompt.txt) is retained
for future art revisions. The only subsequent processing was resizing for the
1024-pixel master and the package's icon slots.
