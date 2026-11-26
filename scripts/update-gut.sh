#!/usr/bin/env bash
# Replace addons/gut with a specific GUT release.
# Usage: scripts/update-gut.sh <tag>      e.g. scripts/update-gut.sh 9.7.1
#
# Pick the release whose notes match the project's Godot version:
#   https://github.com/bitwes/Gut/releases
# (GitHub's "Latest" badge is not always the newest Godot target.)
# Close the Godot editor first so it doesn't rescan mid-copy.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
forward_to_wsl "$@"
cd "$PROJECT_ROOT"

current="$(sed -n 's/^version="\(.*\)"/\1/p' addons/gut/plugin.cfg 2> /dev/null || true)"
if (($# != 1)); then
	echo "Installed GUT: ${current:-none}. Project Godot: $(project_godot_version)"
	echo "Usage: scripts/update-gut.sh <tag>   (see https://github.com/bitwes/Gut/releases)"
	exit 1
fi
tag="$1"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for ref in "v${tag#v}" "${tag#v}"; do
	if curl -fsSL -o "$tmp/gut.tar.gz" "https://github.com/bitwes/Gut/archive/refs/tags/$ref.tar.gz"; then
		break
	fi
done
[[ -s "$tmp/gut.tar.gz" ]] || die "could not download GUT tag '$tag'"

mkdir "$tmp/x"
tar -xzf "$tmp/gut.tar.gz" -C "$tmp/x"
src="$(find "$tmp/x" -mindepth 3 -maxdepth 3 -type d -path '*/addons/gut' | head -n1)"
[[ -n "$src" && -f "$src/plugin.cfg" ]] || die "archive has no addons/gut/plugin.cfg"

rm -rf addons/gut
mkdir -p addons
cp -r "$src" addons/gut

new="$(sed -n 's/^version="\(.*\)"/\1/p' addons/gut/plugin.cfg)"
echo "GUT ${current:-none} -> $new"
echo "Next: open the project in Godot once (re-imports GUT assets), then run scripts/test.sh"
