@tool
class_name Globals

enum ChipType { EYE, BOMB, PACMAN }
enum Difficulty { EASY, NORMAL, HARD }

## Every rotation the board can make after a turn, with its relative probability weight.
## Shared by BoardRotator (to pick rotations) and the bot (to reason about unknown ones).
## Direction: 1 = clockwise (right), -1 = counter-clockwise (left), 0 = none.
const ROTATION_STATES: Array[Dictionary] = [
	{"direction": 1, "degrees": 90, "weight": 1},
	{"direction": -1, "degrees": 90, "weight": 1},
	{"direction": 1, "degrees": 180, "weight": 2},
	{"direction": -1, "degrees": 180, "weight": 2},
	{"direction": 0, "degrees": 0, "weight": 4},
]

# gdlint: disable=max-line-length
static var game_info := """
[url=back_to_menu][font_size=32]< Back[/font_size][/url]

👁️ Get four eyeballs in a row to win.

Wins are only counted after the rotation finishes. The board rotates randomly after every move. The next 3 rotations are always shown at the top of the screen; the one on the right happens next.

Press T (or tap the T button) to switch to a special chip.

💣 Bombs destroy adjacent eyeballs.

👾 Mushrooms destroy facing eyeballs. Press R (or tap the R button) to turn them.

Choose "Play Bot" to play against the AI (Easy, Normal or Hard). Choose "Pass & Play" to play against a friend. The AI takes a few seconds at most to make a move.

When it's your turn, slide your finger (or move the mouse) along the top of the board and let go (or click) over the column where you want to drop your eyeball.

New to the game? Choose Tutorial in the menu for a short interactive walkthrough.

[b]Credits:[/b]

Game by Dac Chartrand
Art by [url=https://www.deviantart.com/dackcode]dackcode[/url]
Made in Godot

[font_size=14]With help from: [url=https://www.gdquest.com]GDQuest[/url], [url=https://godotshaders.com/shader/2d-fireworks]fencerdevlog[/url], [url=https://godotshaders.com/shader/highlight-canvasitem]andich-xyz[/url], [url=https://opengameart.org/content/2d-explosion-animations-frame-by-frame]sinestesiaguy[/url]

Code available on [url=https://github.com/dac514/trypophobia]GitHub[/url][/font_size]

[url=back_to_menu][font_size=32]< Back[/font_size][/url]
"""
