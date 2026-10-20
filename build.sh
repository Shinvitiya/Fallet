#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
app="dist/Fallet.app"
iconset=".build/Fallet.iconset"
host_arch=$(uname -m)
mkdir -p .build/module-cache "$iconset" "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
swiftc -target "${host_arch}-apple-macosx13.0" -module-cache-path .build/module-cache Scripts/remove-icon-border.swift -o .build/remove-icon-border
.build/remove-icon-border branding/Fallet-icon-approved.png Resources/FalletIcon.png
cp Resources/FalletIcon.png "$app/Contents/Resources/FalletIcon.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/FalletSystemIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Resources/FalletSystemIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
swiftc -target "${host_arch}-apple-macosx13.0" -module-cache-path .build/module-cache Scripts/make-icns.swift -o .build/make-icns
.build/make-icns "$iconset" "$app/Contents/Resources/Fallet.icns"
# Each Mac runs its native slice of the universal executable.
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -target "${arch}-apple-macosx13.0" -module-cache-path .build/module-cache \
    -framework AppKit -framework Carbon -framework QuartzCore -framework UniformTypeIdentifiers -framework QuickLookUI -framework Vision -framework ImageIO \
    Sources/Fallet.swift Sources/ShelfStore.swift Sources/GlassUI.swift Sources/GuideWindow.swift Sources/ShakeDetector.swift Sources/ShelfActionMenu.swift Sources/ContentEntryWindow.swift Sources/ShelfOperations.swift Sources/ScriptActionStore.swift \
    -o ".build/Fallet-${arch}"
done
lipo -create .build/Fallet-arm64 .build/Fallet-x86_64 -output "$app/Contents/MacOS/Fallet"
codesign --force --sign - "$app"
echo "Built ${PWD}/$app"
