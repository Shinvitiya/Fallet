#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
mkdir -p .build/module-cache
target="$(uname -m)-apple-macosx13.0"

swiftc -target "$target" -module-cache-path .build/module-cache \
  Sources/ShakeDetector.swift Tests/ShakeDetectorTests.swift -o .build/shake-detector-tests
.build/shake-detector-tests

swiftc -target "$target" -module-cache-path .build/module-cache \
  Sources/ShelfStore.swift Tests/ShelfStoreTests.swift -o .build/shelf-store-tests
.build/shelf-store-tests

swiftc -target "$target" -module-cache-path .build/module-cache -framework Vision -framework ImageIO \
  Sources/ShelfStore.swift Sources/ShelfOperations.swift Tests/ShelfOperationsTests.swift \
  -o .build/shelf-operations-tests
.build/shelf-operations-tests

app_sources=(Sources/Fallet.swift Sources/ShelfStore.swift Sources/GlassUI.swift
  Sources/GuideWindow.swift Sources/ShakeDetector.swift Sources/ShelfActionMenu.swift
  Sources/ContentEntryWindow.swift Sources/ShelfOperations.swift Sources/ShelfImageFilePromise.swift
  Sources/UpdateChecker.swift Sources/UpdatePopover.swift)
frameworks=(-framework AppKit -framework Carbon -framework QuartzCore
  -framework UniformTypeIdentifiers -framework QuickLookUI -framework Vision -framework ImageIO)
for suite in ClipboardDragTests UpdateCheckerTests; do
  swiftc -target "$target" -DFALLET_CAPTURE -module-cache-path .build/module-cache \
    "${frameworks[@]}" "${app_sources[@]}" "Tests/${suite}.swift" \
    -o ".build/${suite}"
  ".build/${suite}"
done

python3 Tests/FormulaTests.py
