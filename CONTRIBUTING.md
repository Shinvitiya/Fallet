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
swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path .build/module-cache Sources/ShakeDetector.swift Tests/ShakeDetectorTests.swift -o .build/shake-detector-tests
.build/shake-detector-tests
```

Run the shelf persistence checks with:

```sh
swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path .build/module-cache Sources/ShelfStore.swift Tests/ShelfStoreTests.swift -o .build/shelf-store-tests
.build/shelf-store-tests
```

Run the local ZIP, image, and script checks with:

```sh
swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path .build/module-cache -framework Vision -framework ImageIO Sources/ShelfOperations.swift Tests/ShelfOperationsTests.swift -o .build/shelf-operations-tests
.build/shelf-operations-tests
```

For drag and drop changes, also check these flows in Finder:

1. Drag several files onto the shelf, then move one to a different folder.
2. Drag the remaining files using **Drag all**.
3. Copy an item to another volume and confirm the source remains available on the shelf.
4. Use **Move to**, **Clear**, and **More actions → Add Files…** with the shelf both visible and hidden.
5. Rename or move a saved file while Fallet is closed, then reopen it. Delete a different source and disconnect an external drive; check that each state is shown and can be recovered.
6. Shake the pointer while dragging files in Finder and confirm the shelf opens. Drag selected text in a browser and shake the pointer; the shelf should stay hidden.
7. Add a URL, plain text, and a browser image, then drag each to an appropriate destination. Switch between **Collect** and **Actions** and confirm the dropdown stays fixed in size.
8. Check preview, rename, reorder, ZIP, resize, OCR, AirDrop, the keyboard shortcut, menu bar drop, and the notch target on hardware that has one.

## Project layout

- `Sources/Fallet.swift` — shelf state, Finder drag and drop, menu bar app, and file moving.
- `Sources/ShelfStore.swift` — persisted paths and bookmarks, source availability, and relinking.
- `Sources/ShelfActionMenu.swift` — glass action dropdown.
- `Sources/ContentEntryWindow.swift` — compact glass window for links and text.
- `Sources/ShelfOperations.swift` — ZIP creation, image resizing, and OCR.
- `Sources/GlassUI.swift` — shelf appearance and controls.
- `Sources/GuideWindow.swift` — in-app guide.
- `Sources/ShakeDetector.swift` — pointer shake detection.
- `Resources/Info.plist` — app bundle metadata.
- `branding/Fallet-icon-approved.png` — selected source artwork.
- `Scripts/remove-icon-border.swift` — clips its outer black background to make the transparent `Resources/FalletIcon.png` build asset.
- `Resources/FalletSystemIcon.png` — opaque full-bleed tile artwork for the macOS app icon.
- `Scripts/make-icns.swift` — packs the generated icon sizes into an `.icns` resource.
- `Scripts/make-demo-video.swift` — builds the short MP4 from the checked-in demo captures.
- `Scripts/capture-persistence-demo.swift` — renders the four README persistence states from isolated test files.
- `Scripts/capture-guide-slides.swift` — renders the four current guide slides for the README.
- `docs/guide/` — all four in-app guide slides, shown inline in the README.
- `docs/demo/` — app captures and the short demo video.
- `Tests/ShakeDetectorTests.swift` — shake detection checks.
- `Tests/ShelfStoreTests.swift` — rename, move, missing source, relinking, and disconnected-volume persistence checks.
- `Tests/ShelfOperationsTests.swift` — ZIP contents and resize dimensions.
- `Tests/ClipboardDragTests.swift` — copied-image export, image thumbnails, and shelf scroll continuity.
- `Formula/fallet.rb` — source-built Homebrew formula in this repository's custom tap.

Keep generated files in `.build/` and `dist/`; both are ignored by Git. Please avoid adding personal file paths, credentials, or copyrighted assets you cannot redistribute.

For signed public releases, see [RELEASING.md](RELEASING.md).
