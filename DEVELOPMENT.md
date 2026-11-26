# Development

This file covers the tooling for working on Trypophobia with VSCode, Claude Code and Godot. Everything runs through bash scripts in [scripts/](scripts/), which work on native Linux, inside WSL, and from Windows Git Bash. Git Bash re-runs each script inside the default WSL distro, so the tools only need installing on the Linux side.

| Task | Command | VSCode task |
| --- | --- | --- |
| Lint (gdlint, `.gdlintrc`) | `bash scripts/lint.sh [paths]` | Lint |
| Format (gdformat, `gdformatrc`) | `bash scripts/format.sh [--check] [paths]` | Format (check) / (apply) |
| Unit tests (GUT, `.gutconfig.json`) | `bash scripts/test.sh [GUT args]` | Test (default test task) |
| Health check | `bash scripts/doctor.sh` | Doctor |
| Upgrade GUT | `bash scripts/update-gut.sh <tag>` | — |

## Coming back after a few months

1. Run `bash scripts/doctor.sh`. It is read-only and points at anything that has rotted.
2. **Upgrade Godot (optional).**
   1. Download the new build into `~/Godot` (on Windows, `C:\Users\<you>\Godot`). Keep both the normal exe and the `_console.exe`.
   2. Open the project in the new editor and let it upgrade. This bumps `config/features` in `project.godot`, and the scripts pick the matching binary from that automatically.
   3. Update `godotTools.editorPath.godot4` in your VSCode **user** settings.
   4. Redo the [Godot editor settings](#godot-editor-settings): settings files are per minor version (`editor_settings-4.8.tres`, `-4.9.tres`, …).
3. **Upgrade GUT** if the Godot minor version changed. Find the matching release at https://github.com/bitwes/Gut/releases; the release notes say which Godot each targets, and the "Latest" badge isn't always the newest. With Godot closed, run `bash scripts/update-gut.sh <tag>`, open the project once, then run `bash scripts/test.sh`.
4. **Upgrade gdtoolkit (rarely).** It runs through `uvx` with the pin `GDTOOLKIT_SPEC` in [scripts/lib.sh](scripts/lib.sh). uv rebuilds its cached env by itself when the system Python changes, so OS upgrades don't break it.
5. `bash scripts/lint.sh && bash scripts/test.sh`

## One-time setup per machine

### Windows 11 + WSL (Fedora)
- **WSL:** run `sudo dnf install uv`. `curl` and `git` are the only other requirements.
- **Godot:** put `Godot_v<ver>-<status>_win64.exe` and `_console.exe` in `C:\Users\<you>\Godot`. The scripts run the Windows `_console.exe` from WSL (interop) so test output and exit codes come back.
- **VSCode:** install the recommended extensions (`.vscode/extensions.json`). Then add these to your **user** `settings.json`:
  ```jsonc
  "godotTools.editorPath.godot4": "C:\\Users\\<you>\\Godot\\Godot_v4.8-beta5_win64.exe",
  "terminal.integrated.defaultProfile.windows": "FedoraLinux-45 (WSL)" // must match `wsl -l`
  ```
  The profile name changes when you upgrade Fedora (for example 42 → 45); doctor warns when it is stale.
- **Git identity:** `git config --local user.email dac.chartrand@gmail.com` is shared by Windows and WSL git.

### Native Linux
- Install `uv`. Put `Godot_v<ver>-<status>_linux.x86_64` in `~/Godot`, or a `godot` binary on PATH, or set `GODOT=/path`.
- In VSCode user settings, set `godotTools.editorPath.godot4` to that binary.

### Godot editor settings
These are per user, per Godot minor version, and stored in `editor_settings-<ver>.tres`:
- Windows: `%APPDATA%\Godot`
- Linux: `~/.config/godot`

Set them in **Editor → Editor Settings**:

| Setting | Value | Why |
| --- | --- | --- |
| Text Editor → External → Use External Editor | On | Godot opens scripts in VSCode, and its built-in script editor stops holding buffers that conflict with VSCode/Claude edits. |
| Text Editor → External → Exec Path | path to `Code.exe` / `code` | |
| Text Editor → External → Exec Flags | `{project} --goto {file}:{line}:{col}` | |
| Text Editor → Behavior → Files → Auto Reload Scripts on External Change | On (the default in 4.8) | Reloads `.gd` files changed on disk without a dialog. |

**Known limitation:** Godot has no setting that silently reloads `.tscn`/`.tres`/`project.godot` when they change on disk. It always asks. So edit scenes in the Godot editor, and don't edit those files externally while they're open. CLAUDE.md tells Claude the same.

### Exports
`export_presets.cfg` is gitignored, so on each machine add the test files to every preset's **Resources → Filters to exclude**:
```
addons/gut/*, test/*, .gutconfig.json
```

## Claude Code
- [CLAUDE.md](CLAUDE.md) holds the project instructions.
- `.claude/settings.json` holds the shared settings:
  - a permission allowlist for the scripts;
  - a PostToolUse hook ([scripts/claude-post-edit.sh](scripts/claude-post-edit.sh)) that lints each `.gd` file Claude edits and feeds the errors back.
