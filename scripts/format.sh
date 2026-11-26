#!/usr/bin/env bash
# Format GDScript with gdformat (config: gdformatrc).
# Usage: scripts/format.sh [--check|--diff] [paths...]   (default: scenes utils test)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
forward_to_wsl "$@"
cd "$PROJECT_ROOT"

flags=()
while (($#)) && [[ "$1" == --* ]]; do
	flags+=("$1")
	shift
done
if (($# == 0)); then
	set -- scenes utils test
fi
gdtk gdformat "${flags[@]}" "$@"
