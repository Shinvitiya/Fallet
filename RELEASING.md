# Releasing Fallet

Fallet's free release path is a source-build [Homebrew tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap). It does not need an Apple Developer Program membership, Developer ID signature, notarization, paid signing service, or a DMG. `build.sh` signs the locally built app ad hoc. Do not upload that app or an ad-hoc signed DMG as a public download and imply that Gatekeeper will accept it as notarized.

## One-time setup

1. Maintain the public `Shinvitiya/homebrew-fallet` repository with a `main` branch and `Formula/fallet.rb`. If creating the tap again, seed it from this repository's [Formula/fallet.rb](Formula/fallet.rb) and [TapTemplate/README.md](TapTemplate/README.md). This repository's formula is the source for installation behavior; each release workflow run pins its tag and checksum, then copies it to both formula repositories. There is no second formula template to keep in sync.
2. Create a **fine-grained personal access token** scoped only to `Shinvitiya/homebrew-fallet`, with **Contents: Read and write**. Add it as the `FALLET_TAP_TOKEN` Actions secret in `Shinvitiya/Fallet`. Do not put it in either repository or in release logs. The source repository's built-in `GITHUB_TOKEN` is used for its own formula and release; it cannot write to the separate tap.
3. Ensure Actions are enabled and the workflow's job-level `contents: write` permission can update `Formula/fallet.rb` on the source repository's `main` branch. If branch rules block that update, allow the GitHub Actions identity or adjust the rule before tagging. The workflow deliberately fails without publishing a release if either formula cannot be updated.

GitHub's [token scope documentation](https://docs.github.com/en/actions/concepts/security/github_token) explains why a separate tap credential is needed. Homebrew's [tap trust documentation](https://docs.brew.sh/Tap-Trust) explains why `brew install Shinvitiya/fallet/fallet` is the recommended one-command install: the fully qualified name trusts this formula without trusting the whole tap.

## Publish a new version

First commit and push the code you intend to release. Change the version through one command; it updates both `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`. For example, to publish `v1.7`:

```sh
python3 Scripts/version.py set 1.7
zsh Scripts/test.sh
zsh build.sh
git add Resources/Info.plist
git commit -m "Release v1.7"
git push origin main
git tag v1.7
git push origin v1.7
```

Never force-push or reuse a release tag. The older `source-v1.5` tag stays in place for existing installs. New releases use `v<version>` tags. The tag must point to a commit on `main`.

CI validates the tag against both bundle version fields, runs all offline tests, builds both executable architectures, and verifies the ad-hoc signature. It downloads the tag's GitHub source archive, computes its SHA-256, and updates `Formula/fallet.rb` in the application repository and the dedicated tap. Each API update compares the current formula to the proposed one; reruns skip unchanged files and refuse to roll a formula back to an older version. Only after both repositories read back the expected formula does the workflow publish a stable GitHub Release as **Latest**. Fallet's update checker also checks that the dedicated tap advertises that release tag before showing its badge. If a tap check fails, the badge waits for a later retry. The app never installs an update itself.

If a step fails, inspect the **Publish free Homebrew release** Actions run and rerun that job after correcting external configuration. If GitHub rejected the workflow file before creating jobs, push the workflow fix to `main`, then use **Actions → Publish free Homebrew release → Run workflow** with `main` selected and the existing tag in the `tag` input. Do not move or recreate the tag. If the tagged code needs a fix, commit the fix, increment the bundle version, and publish a new tag. A failed run may leave one formula updated, but it does not publish the new release; the previous stable release remains latest. Reruns finish missing formula updates without duplicate commits. A prerelease is rejected.

## Existing Homebrew installations

The workflow also updates the formula in `Shinvitiya/Fallet`, so users of the original custom tap can continue with `brew upgrade fallet`. For a one-time switch to the dedicated tap without uninstalling or touching shelf data:

```sh
brew tap --custom-remote Shinvitiya/fallet https://github.com/Shinvitiya/homebrew-fallet.git
brew update
brew upgrade fallet
```

New users install with `brew install Shinvitiya/fallet/fallet`, optionally run `fallet-app-link link` to add `~/Applications/Fallet.app`, then launch through Finder or `fallet`. This helper intentionally runs as the user after installation; the formula does not write to the user's home in an install hook. It preserves conflicting apps or shortcuts. The stable `opt/fallet` link keeps the Applications entry valid across upgrades. For uninstall, run `fallet-app-link unlink` before `brew uninstall Shinvitiya/fallet/fallet`; the helper only removes its own shortcut. Launch Services registration is best effort, so Spotlight may take time and Launchpad visibility is not guaranteed. If Homebrew's trust model requires an explicit trust action for a short-name operation, use `brew trust --formula Shinvitiya/fallet/fallet`; do not disable tap trust globally.

## Optional notarized DMG later

`.github/workflows/release.yml` is manual only. If you later join the Apple Developer Program, configure `FALLET_DEVELOPER_ID_P12_BASE64`, `FALLET_DEVELOPER_ID_P12_PASSWORD`, `FALLET_SIGNING_IDENTITY`, `FALLET_NOTARY_KEY_BASE64`, `FALLET_NOTARY_KEY_ID`, and optionally `FALLET_NOTARY_ISSUER_ID` in the source repository's Actions secrets. Run **Optional notarized macOS DMG** with an existing stable release tag. It uses `package-dmg.sh` and attaches the signed, notarized DMG to that release. This optional workflow does not run on tag pushes and cannot block the free Homebrew release.
