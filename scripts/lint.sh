#!/usr/bin/env bash
# Lint GDScript with gdlint (config: .gdlintrc).
# Usage: scripts/lint.sh [paths...]   (default: scenes utils test)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
forward_to_wsl "$@"
cd "$PROJECT_ROOT"

if (($# == 0)); then
	set -- scenes utils test
fi
gdtk gdlint "$@"
