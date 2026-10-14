# Contributing to Fallet

Thanks for helping improve Fallet. Issues that describe a specific Finder drag, macOS version, and expected behavior are especially useful.

## Local development

Build the app on an Apple silicon or Intel Mac with macOS 13 or later and Xcode Command Line Tools:

```sh
zsh build.sh
open dist/Fallet.app
```

The project uses Swift and AppKit directly, without a package manager or third-party runtime dependencies.

Run the shake detection checks with:

```sh
mkdir -p .build/module-cache
swiftc -module-cache-path .build/module-cache Sources/ShakeDetector.swift Tests/ShakeDetectorTests.swift -o .build/shake-detector-tests
.build/shake-detector-tests
```

For drag and drop changes, also check these flows in Finder:

1. Drag several files onto the shelf, then move one to a different folder.
2. Drag the remaining files using **Drag all**.
3. Copy an item to another volume and confirm the source remains available on the shelf.
4. Use **Move to**, **Clear**, and **+** with the shelf both visible and hidden.

## Project layout

- `Sources/Fallet.swift` — shelf state, Finder drag and drop, menu bar app, and file moving.
- `Sources/GlassUI.swift` — shelf appearance and controls.
- `Sources/GuideWindow.swift` — in-app guide.
- `Sources/ShakeDetector.swift` — pointer shake detection.
- `Resources/Info.plist` — app bundle metadata.
- `branding/Fallet-icon-approved.png` — selected source artwork.
- `Scripts/remove-icon-border.swift` — clips its outer black background to make the transparent `Resources/FalletIcon.png` build asset.
- `Resources/FalletSystemIcon.png` — opaque full-bleed tile artwork for the macOS app icon.
- `Scripts/make-icns.swift` — packs the generated icon sizes into an `.icns` resource.
- `Scripts/make-demo-video.swift` — builds the short MP4 from the checked-in demo captures.
- `docs/guide/` — all four in-app guide slides, shown inline in the README.
- `docs/demo/` — app captures and the short demo video.
- `Tests/ShakeDetectorTests.swift` — shake detection checks.

Keep generated files in `.build/` and `dist/`; both are ignored by Git. Please avoid adding personal file paths, credentials, or copyrighted assets you cannot redistribute.

For signed public releases, see [RELEASING.md](RELEASING.md).
