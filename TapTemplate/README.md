# Fallet Homebrew tap

This repository is the Homebrew tap for the free, open-source [Fallet](https://github.com/Shinvitiya/Fallet) macOS app. The application source stays in `Shinvitiya/Fallet`; this tap contains only its SHA-pinned source-build formula.

```sh
brew install Shinvitiya/fallet/fallet
fallet
```

Fallet builds on your Mac with Xcode Command Line Tools and is signed ad hoc. It is not Apple-notarized. The fully qualified install command automatically taps and trusts this one formula; it does not require trusting every formula in the tap.

Release automation in the application repository updates `Formula/fallet.rb` only after it has validated the source archive and its SHA-256. See [release instructions](https://github.com/Shinvitiya/Fallet/blob/main/RELEASING.md).
