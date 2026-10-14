#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

fail() {
  print -u2 -- "Release stopped: $1"
  exit 1
}

identity="${FALLET_SIGNING_IDENTITY:-}"
[[ "$identity" == "Developer ID Application:"* ]] || fail "Set FALLET_SIGNING_IDENTITY to a Developer ID Application certificate name."
security find-identity -v -p codesigning | grep -Fq -- "$identity" || fail "The Developer ID signing identity is not available in this Mac's keychain."

typeset -a notary_args
if [[ -n "${FALLET_NOTARY_PROFILE:-}" ]]; then
  notary_args=(--keychain-profile "$FALLET_NOTARY_PROFILE")
elif [[ -n "${FALLET_NOTARY_KEY_PATH:-}" && -n "${FALLET_NOTARY_KEY_ID:-}" ]]; then
  [[ -f "$FALLET_NOTARY_KEY_PATH" ]] || fail "The App Store Connect API key file does not exist."
  notary_args=(--key "$FALLET_NOTARY_KEY_PATH" --key-id "$FALLET_NOTARY_KEY_ID")
  if [[ -n "${FALLET_NOTARY_ISSUER_ID:-}" ]]; then
    notary_args+=(--issuer "$FALLET_NOTARY_ISSUER_ID")
  fi
else
  fail "Set FALLET_NOTARY_PROFILE, or FALLET_NOTARY_KEY_PATH and FALLET_NOTARY_KEY_ID."
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
name="Fallet-${version}-macOS-universal.dmg"
app="dist/Fallet.app"
candidate=".build/$name"
release="dist/$name"
[[ ! -e "$release" ]] || fail "$release already exists. Bump the app version before making another release."

zsh build.sh

# Ad hoc signing in build.sh is only for local development. Replace it with the
# release certificate, hardened runtime, and Apple's secure timestamp.
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
lipo "$app/Contents/MacOS/Fallet" -verify_arch arm64 x86_64

notarize() {
  local item="$1"
  local label="$2"
  local result=".build/notarization-${label}.json"
  local report=".build/notarization-${label}-log.json"
  xcrun notarytool submit "$item" "${notary_args[@]}" --wait --timeout 30m --output-format json > "$result"
  local status=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status", "Unknown"))' "$result")
  if [[ "$status" != "Accepted" ]]; then
    local submission=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$result")
    if [[ -n "$submission" ]]; then
      xcrun notarytool log "$submission" "${notary_args[@]}" "$report" || true
    fi
    fail "Apple rejected $label notarization ($status). See $result and $report."
  fi
  print -- "Apple accepted $label notarization."
}

# Staple the app before copying it into the disk image so the installed copy
# carries its own ticket, including when the user is offline after install.
archive=".build/Fallet-${version}-notarization.zip"
ditto -c -k --keepParent "$app" "$archive"
notarize "$archive" app
xcrun stapler staple "$app"
xcrun stapler validate "$app"

stage=$(mktemp -d "${PWD}/dist/.fallet-dmg-staging.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
ditto "$app" "$stage/Fallet.app"
ln -s /Applications "$stage/Applications"
cp Resources/Share-README.txt "$stage/Read Me.txt"

hdiutil create -volname "Fallet" -srcfolder "$stage" -format UDZO -imagekey zlib-level=9 -ov "$candidate"
codesign --force --timestamp --sign "$identity" "$candidate"
hdiutil verify "$candidate"
codesign --verify --verbose=2 "$candidate"
notarize "$candidate" dmg
xcrun stapler staple "$candidate"
xcrun stapler validate "$candidate"
spctl --assess --type open --context context:primary-signature --verbose=2 "$candidate"

mount=$(mktemp -d "${TMPDIR:-/tmp/}/fallet-mounted.XXXXXX")
trap 'hdiutil detach "$mount" -quiet 2>/dev/null || true; rm -rf -- "$mount" "$stage"' EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$candidate" -quiet
[[ -d "$mount/Fallet.app" && -L "$mount/Applications" ]] || fail "The disk image is missing the app or Applications shortcut."
codesign --verify --deep --strict --verbose=2 "$mount/Fallet.app"
spctl --assess --type execute --verbose=2 "$mount/Fallet.app"
hdiutil detach "$mount" -quiet
mv "$candidate" "$release"
shasum -a 256 "$release" > "${release}.sha256"
print -- "Ready to publish: ${PWD}/$release"
