# Releasing Fallet

Fallet's free release path is a source-build [Homebrew tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap). It does not need an Apple Developer Program membership, Developer ID signature, notarization, paid signing service, or a DMG. `build.sh` signs the locally built app ad hoc. Do not upload that app or an ad-hoc signed DMG as a public download and imply that Gatekeeper will accept it as notarized.

## One-time setup

1. Create a public GitHub repository named `Shinvitiya/homebrew-fallet`, with a `main` branch. Copy [TapTemplate/Formula/fallet.rb](TapTemplate/Formula/fallet.rb) to `Formula/fallet.rb` and [TapTemplate/README.md](TapTemplate/README.md) to `README.md` in that repository. The seed formula uses the existing `source-v1.5` archive; the first free release replaces it automatically. The application source stays in `Shinvitiya/Fallet`.
2. Create a **fine-grained personal access token** scoped only to `Shinvitiya/homebrew-fallet`, with **Contents: Read and write**. Add it as the `FALLET_TAP_TOKEN` Actions secret in `Shinvitiya/Fallet`. Do not put it in either repository or in release logs. The source repository's built-in `GITHUB_TOKEN` is used for its own formula and release; it cannot write to the separate tap.
3. Ensure Actions are enabled and the workflow's job-level `contents: write` permission can update `Formula/fallet.rb` on the source repository's `main` branch. If branch rules block that update, allow the GitHub Actions identity or adjust the rule before tagging. The workflow deliberately fails without publishing a release if either formula cannot be updated.

GitHub's [token scope documentation](https://docs.github.com/en/actions/concepts/security/github_token) explains why a separate tap credential is needed. Homebrew's [tap trust documentation](https://docs.brew.sh/Tap-Trust) explains why `brew install Shinvitiya/fallet/fallet` is the recommended one-command install: the fully qualified name trusts this formula without trusting the whole tap.

## Publish the first free release

The current bundle version is `1.6`. After this work is committed, the tap repository and secret exist, and `main` has been pushed, run these commands **from this repository**:

```sh
python3 Scripts/version.py check v1.6
zsh Scripts/test.sh
zsh build.sh
git push origin main
git tag v1.6
git push origin v1.6
```

Never force-push or reuse a release tag. The older `source-v1.5` tag stays in place for existing installs. New releases use `v<version>` tags.

## Publish later versions

Change the version through one command; it updates both `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`. For example, to publish `v1.7`:

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

The tag must point to a commit on `main`. CI validates that tag, both version fields, all offline tests, both executable architectures, and the ad-hoc signature. It downloads the tag's GitHub source archive, computes its SHA-256, and updates the source repository's existing `Formula/fallet.rb` and the dedicated tap's `Formula/fallet.rb`. Each API update compares the current formula to the proposed one; reruns skip unchanged files and refuse to roll a formula back to an older version. The workflow checks the committed formula after each update. Only after both repositories succeed does it publish a stable GitHub Release as **Latest**. The app checks that release through GitHub's `releases/latest` API, so it cannot advertise a version before the Homebrew formula is available.

If a step fails, inspect the **Publish free Homebrew release** Actions run, fix the problem, and rerun that job. If GitHub rejected the workflow file before creating jobs, push the workflow fix to `main`, then use **Actions → Publish free Homebrew release → Run workflow** with `main` selected and the existing tag (for example `v1.6`) in the `tag` input. Do not move or recreate the tag. A failed run leaves the release unpublished. The workflow does not overwrite a tag or create duplicate formula commits on rerun. If the release already exists as a draft, a successful rerun publishes it after the formula checks. A prerelease is rejected.

## Existing Homebrew installations

The workflow also updates the formula in `Shinvitiya/Fallet`, so users of the original custom tap can continue with `brew upgrade fallet`. For a one-time switch to the dedicated tap without uninstalling or touching shelf data:

```sh
brew tap --custom-remote Shinvitiya/fallet https://github.com/Shinvitiya/homebrew-fallet.git
brew update
brew upgrade fallet
```

New users install with `brew install Shinvitiya/fallet/fallet`, then launch with `fallet`. If Homebrew's trust model requires an explicit trust action for a short-name operation, use `brew trust --formula Shinvitiya/fallet/fallet`; do not disable tap trust globally.

## Optional notarized DMG later

`.github/workflows/release.yml` is manual only. If you later join the Apple Developer Program, configure `FALLET_DEVELOPER_ID_P12_BASE64`, `FALLET_DEVELOPER_ID_P12_PASSWORD`, `FALLET_SIGNING_IDENTITY`, `FALLET_NOTARY_KEY_BASE64`, `FALLET_NOTARY_KEY_ID`, and optionally `FALLET_NOTARY_ISSUER_ID` in the source repository's Actions secrets. Run **Optional notarized macOS DMG** with an existing stable release tag. It uses `package-dmg.sh` and attaches the signed, notarized DMG to that release. This optional workflow does not run on tag pushes and cannot block the free Homebrew release.
