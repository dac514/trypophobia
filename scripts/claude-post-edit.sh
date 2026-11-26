#!/usr/bin/env bash
# Claude Code PostToolUse hook: lint a .gd file right after Claude edits it.
# Reads the hook JSON on stdin. Exit 2 sends gdlint's output back to Claude.
# Runs from Git Bash (Windows) or Linux; lint.sh forwards to WSL as needed.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

file="$(sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
[[ "$file" == *.gd ]] || exit 0

# JSON-escaped Windows path (c:\\Users\\...) -> POSIX path
file="${file//\\\\/\\}"
if command -v cygpath > /dev/null; then
	file="$(cygpath -u "$file")"
fi
case "$file" in
	"$root"/*) rel="${file#"$root"/}" ;;
	*) exit 0 ;; # outside this project
esac
case "$rel" in
	addons/* | .godot/*) exit 0 ;;
esac

if ! out="$(bash "$root/scripts/lint.sh" "$rel" 2>&1)"; then
	echo "gdlint failed for $rel:" >&2
	echo "$out" >&2
	exit 2
fi
exit 0
