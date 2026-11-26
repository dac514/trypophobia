#!/usr/bin/env bash
# Check that the dev environment is healthy. Read-only: changes nothing.
# Run this first when coming back to the project after a while.
# Usage: scripts/doctor.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
forward_to_wsl "$@"
cd "$PROJECT_ROOT"
set +e

fails=0
ok() { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }
bad() {
	printf '  \033[31mFAIL\033[0m  %s\n' "$*"
	fails=$((fails + 1))
}

ver="$(project_godot_version)"
echo "Project targets Godot $ver"

echo "Tools"
if command -v uvx > /dev/null; then
	ok "uv $(uv --version | cut -d' ' -f2)"
	if v="$(gdtk gdlint --version 2>&1)"; then ok "$v ($GDTOOLKIT_SPEC)"; else bad "gdlint won't run: $v"; fi
else
	bad "uv missing (Fedora: sudo dnf install uv)"
fi
if godot="$(find_godot 2> /dev/null)"; then
	gv="$("$godot" --version 2> /dev/null | tr -d '\r')"
	if [[ "$gv" == "$ver".* ]]; then ok "Godot $gv ($godot)"; else bad "Godot $gv does not match project $ver ($godot)"; fi
else
	bad "no Godot $ver binary found (see scripts/lib.sh find_godot)"
fi
gut="$(sed -n 's/^version="\(.*\)"/\1/p' addons/gut/plugin.cfg 2> /dev/null)"
if [[ -n "$gut" ]]; then ok "GUT $gut (check it supports Godot $ver: https://github.com/bitwes/Gut/releases)"; else bad "addons/gut missing"; fi
email="$(git config user.email)"
ok "git commits as $(git config user.name) <$email>"

# Per-machine settings, outside the repo
if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
	winhome="$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2> /dev/null | tr -d '\r')" 2> /dev/null)"
	vscode="$winhome/AppData/Roaming/Code/User/settings.json"
	godot_cfg="$winhome/AppData/Roaming/Godot/editor_settings-$ver.tres"
else
	vscode="$HOME/.config/Code/User/settings.json"
	godot_cfg="$HOME/.config/godot/editor_settings-$ver.tres"
fi

echo "VSCode user settings ($vscode)"
if [[ -f "$vscode" ]]; then
	gpath="$(sed -n 's/.*"godotTools.editorPath.godot4"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$vscode")"
	gpath="${gpath//\\\\/\\}" # JSON-unescape backslashes
	if [[ -z "$gpath" ]]; then
		bad "godotTools.editorPath.godot4 not set (godot-tools LSP/debugger need it)"
	else
		gpath_posix="$gpath"
		[[ -n "${WSL_DISTRO_NAME:-}" ]] && gpath_posix="$(wslpath "$gpath" 2> /dev/null)"
		if [[ ! -f "$gpath_posix" ]]; then
			bad "godotTools.editorPath.godot4 points to a missing file: $gpath"
		elif [[ "$(basename "$gpath_posix")" != Godot_v"$ver"[-.]* ]]; then
			warn "godotTools.editorPath.godot4 may not be Godot $ver: $gpath"
		else
			ok "godotTools.editorPath.godot4 = $gpath"
		fi
	fi
	if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
		profile="$(sed -n 's/.*"terminal.integrated.defaultProfile.windows"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$vscode")"
		if [[ "$profile" == "$WSL_DISTRO_NAME (WSL)" ]]; then
			ok "default terminal = $profile"
		else
			warn "default terminal is '${profile:-unset}', this distro is '$WSL_DISTRO_NAME (WSL)'"
		fi
	fi
else
	warn "not found"
fi

echo "Godot editor settings ($godot_cfg)"
if [[ -f "$godot_cfg" ]]; then
	# Godot omits settings that are at their default value, so a missing key means "default".
	if grep -q "^text_editor/external/use_external_editor = true" "$godot_cfg"; then
		ok "use_external_editor (scripts open in VSCode, no conflicting buffers)"
	else
		warn "Use External Editor is off: Godot's script editor will raise reload dialogs on external edits"
	fi
	if grep -q "^text_editor/behavior/files/auto_reload_scripts_on_external_change = false" "$godot_cfg"; then
		warn "Auto Reload Scripts on External Change is off"
	else
		ok "auto_reload_scripts_on_external_change (default on)"
	fi
else
	warn "not found (open Godot $ver once to create it)"
fi

echo
if ((fails)); then
	echo "$fails problem(s) found. See DEVELOPMENT.md."
	exit 1
fi
echo "All good."
