@tool
class_name Globals

enum ChipType { EYE, BOMB, PACMAN }

static var game_info := """
[url=back_to_menu][font_size=22]< Back[/font_size][/url]

Get four eyeballs in a row to win.

Wins are only counted after the rotation finishes. The board rotates randomly after each turn. The next 3 rotations are shown in the upper left corner.

When it's your turn, click the column where you want to drop your eyeball.

Press T to toggle special chips. Press R to rotate special chips. Bombs destroy adjacent eyeballs. Mushroom chips destroy facing eyeballs.

Choose "Play Bot" to play against the AI. Choose "Pass & Play" to play against a friend. The AI can take up to 5 seconds to make a move.

Credits:

Game by Dac Chartrand
Art by [url=https://www.deviantart.com/dackcode]dackcode[/url]
Made in Godot

[font_size=10]With help from: [url=https://www.gdquest.com]GDQuest[/url], [url=https://godotshaders.com/shader/2d-fireworks]fencerdevlog[/url], [url=https://godotshaders.com/shader/highlight-canvasitem]andich-xyz[/url], [url=https://opengameart.org/content/2d-explosion-animations-frame-by-frame]sinestesiaguy[/url]

Code available on [url=https://github.com/dac514/trypophobia]GitHub[/url][/font_size]

[url=back_to_menu][font_size=22]< Back[/font_size][/url]
"""
