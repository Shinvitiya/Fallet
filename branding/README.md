# Fallet icon

`Fallet-icon-approved.png` is the selected source artwork. It uses a distinct four-by-four field of soft tiles, with the guide's blue and red. The build script clips away its outer black background with `Scripts/remove-icon-border.swift`, producing the transparent `Resources/FalletIcon.png` used inside the shelf.

`Resources/FalletSystemIcon.png` is a full-bleed, opaque adaptation of the same tile artwork for the macOS app icon. On macOS 26, an inset transparent legacy `.icns` receives a gray rounded backing. The full-bleed version lets the system mask the tiles directly without that visible gray border.
