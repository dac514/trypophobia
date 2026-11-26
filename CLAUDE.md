# Trypophobia

Four-in-a-row puzzle game in **Godot 4.8 (GDScript)**. After every turn the board rotates randomly and gravity re-settles the chips. Players get four eyeballs in a row to win. See [README.md](README.md) for the rules, and [DEVELOPMENT.md](DEVELOPMENT.md) for setup, upgrades and machine config.

## Commands

All tooling is plain bash in `scripts/`. Run the scripts from the repo root. Under Windows Git Bash (Claude Code's Bash tool on Windows), each script re-runs itself inside the default WSL distro (Fedora). Don't call `wsl.exe` yourself, and don't use PowerShell.

- `bash scripts/lint.sh [paths]`: runs gdlint (`.gdlintrc`). It must pass before finishing a change.
- `bash scripts/format.sh [--check|--diff] [paths]`: runs gdformat (`gdformatrc`, 140 columns). The codebase is currently fully formatted.
- `bash scripts/test.sh [GUT args]`: runs the GUT unit tests headless (`.gutconfig.json`, `test/unit/`). For example, `-gselect=test_bot_board -gunit_test_name=bomb`.
- `bash scripts/doctor.sh`: read-only health check of the tools, Godot version and machine settings.
- `bash scripts/update-gut.sh <tag>`: replaces `addons/gut` with a GUT release.

The Godot binary is auto-detected from the version in `project.godot`; override it with `GODOT=/path/to/godot`.

## Rules for editing

- **Don't edit `.tscn`, `.tres` or `project.godot` while the user's Godot editor may have them open.** Godot can't silently reload those files: it shows a reload/resave dialog and may overwrite your change. Ask the user to close the scene (or Godot) first, or describe the change so they can make it in the editor. `.gd` files are safe to edit, because Godot reloads them automatically.
- Never hand-write `.uid` files. Godot generates `<file>.gd.uid` when it scans a new script; commit them with the script.
- Never edit `addons/gut/` (vendored; replaced wholesale by `update-gut.sh`).
- Keep static typing; the project warns on untyped declarations and unsafe access (`project.godot` `[debug]`).
- New tests go in `test/unit/test_*.gd`, `extends GutTest`. Prefer testing pure logic (`utils/bot/`), not physics scenes.
- Git commits use `Dac Chartrand <dac.chartrand@gmail.com>`, which is set repo-locally. Don't change it.

## Architecture

### Core game flow
- **`scenes/main.gd`**: the central coordinator: player input, turn management, UI state, chip inventory.
- **`scenes/board.gd`**: the 6x6 grid (`Board.GRID_SIZE`), chip placement and win detection. `grid_state` is indexed `[column][row]`, and row 0 is the top.
- **`scenes/board_rotator.gd`**: random board rotations with a weighted probability system.
- **`scenes/chip.gd`**: the abstract chip base class, with `chip_eye.gd`, `chip_bomb.gd` and `chip_pacman.gd` as implementations. Chips are `RigidBody2D`. `utils/chip_watcher.gd` detects when physics has settled.
- **`scenes/next_moves.gd`**: previews the next 3 rotations.
- **`utils/globals.gd`**: the `ChipType` enum (EYE, BOMB, PACMAN) and the info text.

### Special chips
- BOMB destroys adjacent chips.
- PACMAN destroys the chip it faces. R rotates its direction, and T toggles the special chip type.

### AI bot (`utils/bot/`)
The bot runs on a separate thread. Easy plays mostly random moves; Normal and Hard use a rotation-aware expectiminimax search.
- **`bot_search.gd`** (`BotSearch`): pure, synchronous search. It uses negamax with alpha-beta and a transposition table at decision nodes, and iterative deepening on a wall-clock budget, always returning the last completed depth. Both players see the next 3 rotations, and one more is revealed after every turn. So after each ply a chance node, weighted by `Globals.ROTATION_STATES`, reveals the next rotation before the opponent decides. Chance nodes are only expanded when the search reaches the ply that uses that rotation. Wins score `WIN_SCORE + remaining depth`.
- **`bot_worker.gd`** (`BotWorker extends Thread`): picks the difficulty settings: Hard is depth 6 within 2.5 s, Normal is depth 2 with noise. `choose_move()` runs synchronously for tests.
- **`bot.gd`** (`Bot`): copies the grid, inventory and rotations into plain data on the main thread, then starts the worker.
- **`bot_board.gd`** (`BotBoard`): a lightweight simulation of the board covering moves, effects, rotation, gravity, turn outcomes and the heuristic.
  - It stores the grid as a flat `PackedByteArray` (`cells`, index `col * 6 + row`).
  - `current_board_permutation` is a `[col][row]` copy, for convenience.
- **`bot_move.gd`** (`BotMove`): the column, the chip type and the pacman direction.
- Tests:
  - `test_bot_board.gd` and `test_bot_rules.gd` cover the board model.
  - `test_bot_search.gd` holds the brute-force equivalence (helpers in `bot_search_helpers.gd`) and `test_bot_puzzles.gd` the rotation puzzles. They are the place to prove a search change still finds optimal moves.
  - `test_bot_worker.gd` covers the difficulties.

### Debugging
- `board.gd` provides `_print_ascii_grid()`, and `BotBoard` provides `print_ascii_grid()`.
- The bot logs its move evaluation to the console.
