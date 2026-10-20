#!/bin/bash
set -euo pipefail

# GH_TOKEN must have Contents: write for the chosen repository.
repo="${1:?repository required}"
formula="${2:?formula path required}"
tag="${3:?release tag required}"
case "$repo" in
  Shinvitiya/Fallet|Shinvitiya/homebrew-fallet) ;;
  *) echo "Unexpected formula repository: $repo" >&2; exit 1 ;;
esac
: "${GH_TOKEN:?Missing repository token}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
local_tag="$(python3 "$script_dir/formula.py" verify "$formula" | awk '{print $1}')"
test "$local_tag" = "$tag"

remote_formula="$(mktemp)"
trap 'rm -f "$remote_formula"' EXIT
endpoint="repos/$repo/contents/Formula/fallet.rb"
gh api "$endpoint?ref=main" --jq .content | base64 -D > "$remote_formula"
remote_sha="$(gh api "$endpoint?ref=main" --jq .sha)"
python3 "$script_dir/formula.py" assert-upgrade "$remote_formula" "$tag" >/dev/null

if cmp -s "$formula" "$remote_formula"; then
  echo "$repo formula already points to $tag"
  exit 0
fi
remote_tag="$(python3 "$script_dir/formula.py" verify "$remote_formula" | awk '{print $1}')"
if [[ "$remote_tag" == "$tag" ]]; then
  echo "$repo already has a different formula for $tag; refusing to overwrite it" >&2
  exit 1
fi

encoded="$(base64 -i "$formula" | tr -d '\n')"
gh api --silent --method PUT "$endpoint" \
  -f message="Update Fallet formula for $tag" \
  -f content="$encoded" -f sha="$remote_sha" -f branch=main
gh api "$endpoint?ref=main" --jq .content | base64 -D > "$remote_formula"
cmp "$formula" "$remote_formula"
echo "Updated $repo formula to $tag"
