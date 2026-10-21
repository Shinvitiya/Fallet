# Fallet Homebrew tap

This repository is the Homebrew tap for the free, open-source [Fallet](https://github.com/Shinvitiya/Fallet) macOS app. The application source stays in `Shinvitiya/Fallet`; this tap contains only its SHA-pinned source-build formula.

```sh
brew install Shinvitiya/fallet/fallet
fallet-app-link link
fallet
```

The second command creates a real launcher at `/Applications/Fallet.app` so you can open Fallet from Finder or the macOS Apps view (Launchpad on older systems). It opens Homebrew's stable `opt/fallet` path and survives upgrades. After installation, it removes the managed entry in `~/Applications` from older Fallet releases. Run `fallet-uninstall` for a complete uninstall, including Fallet's shelf data and caches. To keep shelf data for a future reinstall, run `fallet-app-link unlink` followed by `brew uninstall fallet`.

Fallet builds on your Mac with Xcode Command Line Tools and is signed ad hoc. It is not Apple-notarized. The fully qualified install command automatically taps and trusts this one formula; it does not require trusting every formula in the tap.

Release automation in the application repository updates `Formula/fallet.rb` only after it has validated the source archive and its SHA-256. See [release instructions](https://github.com/Shinvitiya/Fallet/blob/main/RELEASING.md).
