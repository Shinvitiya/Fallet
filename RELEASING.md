# Releasing Fallet

Do not upload the ad hoc signed output of `build.sh` as a public download. macOS Gatekeeper can block that copy on another Mac. Public releases need an [Apple Developer Program account](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) with a Developer ID Application certificate, hardened runtime, Apple's secure timestamp, and notarization.

`package-dmg.sh` builds both arm64 and x86_64 slices, replaces the local signature with a Developer ID signature, notarizes and staples the app, creates and signs a DMG, notarizes and staples the DMG, mounts it, and checks the app and Applications shortcut. It writes a DMG and SHA-256 file to `dist/` only after every release check succeeds.

## GitHub release setup

Add these repository Actions secrets in **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `FALLET_DEVELOPER_ID_P12_BASE64` | Base64 encoding of an exported Developer ID Application `.p12` containing its private key. |
| `FALLET_DEVELOPER_ID_P12_PASSWORD` | Export password for that `.p12`. |
| `FALLET_SIGNING_IDENTITY` | Full identity name, such as `Developer ID Application: Example Name (TEAMID)`. |
| `FALLET_NOTARY_KEY_BASE64` | Base64 encoding of an App Store Connect API `.p8` key with notarization access. |
| `FALLET_NOTARY_KEY_ID` | App Store Connect API key ID. |
| `FALLET_NOTARY_ISSUER_ID` | Issuer ID for a team API key; leave unset for an individual API key. |

Keep the `.p12`, its password, and the `.p8` private. Never commit them to the repository. The workflow imports them into a temporary keychain on a GitHub macOS runner and deletes the files afterward.

Set `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, commit and push the change, then push a tag matching the version, for example `v1.3`. The release workflow creates the signed, notarized DMG and attaches it to a GitHub Release. Only that release asset should be offered as the download.

## Local release

With the Developer ID Application certificate installed in Keychain and notarization credentials available, set `FALLET_SIGNING_IDENTITY` to the exact identity name. For notarization, either set `FALLET_NOTARY_PROFILE` to a profile saved with `xcrun notarytool store-credentials`, or set `FALLET_NOTARY_KEY_PATH`, `FALLET_NOTARY_KEY_ID`, and optionally `FALLET_NOTARY_ISSUER_ID`. Then run `zsh package-dmg.sh`.

The script refuses to create a public DMG without a Developer ID identity and notarization credentials. Check `dist/Fallet-<version>-macOS-universal.dmg.sha256` against the DMG before publishing. Test the downloaded asset on a Mac that has not previously run Fallet when possible.
