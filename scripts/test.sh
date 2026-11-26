#!/usr/bin/env bash
# Run GUT unit tests headless (config: .gutconfig.json).
# Usage: scripts/test.sh [extra GUT args]
#   e.g. scripts/test.sh -gselect=test_bot_board -gunit_test_name=win
# Override the Godot binary with GODOT=/path/to/godot.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
forward_to_wsl "$@"
cd "$PROJECT_ROOT"

godot="$(find_godot)"
path="$(godot_project_path "$godot")"
echo "Using $("$godot" --version | tr -d '\r') ($godot)"

# A fresh clone has no .godot/ cache yet; class_name lookups need an import first.
if [[ ! -f .godot/global_script_class_cache.cfg ]]; then
	echo "No .godot cache, importing project first..."
	"$godot" --headless --path "$path" --import > /dev/null 2>&1 || true
fi

exec "$godot" --headless --path "$path" -s res://addons/gut/gut_cmdln.gd "$@"
