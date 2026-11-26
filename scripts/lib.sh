#!/usr/bin/env bash
# Shared helpers for scripts/*.sh. Source it, don't run it:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#   forward_to_wsl "$@"
#
# Works on native Linux, inside WSL, and from Windows Git Bash (which re-runs
# the calling script inside the default WSL distro, so tools only need to be
# installed once, in Linux).

set -euo pipefail

# ---- Pinned tool versions (bump here) --------------------------------------
# gdtoolkit (gdlint/gdformat) runs through uvx: a cached, self-healing env that
# is rebuilt automatically if the system Python changes after an OS upgrade.
GDTOOLKIT_SPEC="gdtoolkit==4.*"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
	echo "error: $*" >&2
	exit 1
}

is_windows_bash() {
	case "$(uname -s)" in
		MINGW* | MSYS* | CYGWIN*) return 0 ;;
		*) return 1 ;;
	esac
}

# Re-exec the calling script inside WSL when running under Windows Git Bash.
# Set TRYPO_NO_WSL=1 to opt out (tools must then be on the Windows PATH).
forward_to_wsl() {
	if is_windows_bash && [[ -z "${TRYPO_NO_WSL:-}" ]] && command -v wsl.exe > /dev/null; then
		local script
		script="scripts/$(basename "${BASH_SOURCE[1]}")"
		# --exec skips WSL's shell re-parsing so arguments keep their quoting.
		MSYS_NO_PATHCONV=1 exec wsl.exe --cd "$(cd "$PROJECT_ROOT" && pwd -W)" --exec bash "$script" "$@"
	fi
}

# The Godot major.minor this project targets, read from project.godot,
# e.g. config/features=PackedStringArray("4.8", ...) -> 4.8
project_godot_version() {
	sed -n 's/^config\/features=PackedStringArray("\([0-9.]*\)".*/\1/p' "$PROJECT_ROOT/project.godot"
}

# Print the Godot binary to use for headless runs.
#   1. $GODOT, if set
#   2. Newest Godot_v<project version>* found in ~/Godot, ~/.local/bin, or
#      C:\Users\*\Godot (via /mnt/c). On Windows the *_console.exe build is
#      used so stdout and exit codes reach the terminal.
#   3. godot / godot4 on PATH
find_godot() {
	if [[ -n "${GODOT:-}" ]]; then
		echo "$GODOT"
		return
	fi
	local ver
	ver="$(project_godot_version)"
	local -a candidates=()
	local dir
	shopt -s nullglob
	for dir in "$HOME/Godot" "$HOME/.local/bin" /mnt/c/Users/*/Godot; do
		candidates+=("$dir"/Godot_v"$ver"[-.]*_console.exe "$dir"/Godot_v"$ver"[-.]*linux*.x86_64 "$dir"/Godot_v"$ver"[-.]*linux*.arm64)
	done
	shopt -u nullglob
	if ((${#candidates[@]})); then
		# Newest by version: beta < rc < stable, 4.8 < 4.8.1
		printf '%s\n' "${candidates[@]}" | awk -F/ '{print $NF "\t" $0}' | sort -V | tail -n1 | cut -f2
		return
	fi
	local c
	for c in godot godot4; do
		if command -v "$c" > /dev/null; then
			command -v "$c"
			return
		fi
	done
	die "no Godot $ver binary found. Put Godot_v${ver}-*_console.exe (Windows) or Godot_v${ver}-*_linux.x86_64 in ~/Godot, or set GODOT=/path/to/godot"
}

# The project path as the Godot binary expects it (Windows path for .exe).
godot_project_path() {
	local godot="$1"
	if [[ "$godot" == *.exe ]] && command -v wslpath > /dev/null; then
		wslpath -w "$PROJECT_ROOT"
	else
		echo "$PROJECT_ROOT"
	fi
}

# Run a gdtoolkit command: gdtk gdlint <args>, gdtk gdformat <args>
gdtk() {
	command -v uvx > /dev/null || die "uv not found. Install it: Fedora 'sudo dnf install uv', other: https://docs.astral.sh/uv/"
	local tool="$1"
	shift
	uvx -q --from "$GDTOOLKIT_SPEC" "$tool" "$@"
}
