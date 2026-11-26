class_name ChipRim
extends Node2D

## Coloured ring around a chip, shown when the "distinct player chips" option is on.
##
## Player 1 gets a blue ring, player 2 a gold one. Blue and yellow stay easy to tell apart with the
## common (red-green) colour blindness and differ in brightness, so they also work in grayscale.
## Together with the pupils (black for player 1, red for player 2) every chip shows its owner twice.
##
## Added by Chip as its last child, so it draws on top of the chip's sprites.

const RADIUS := 44.0
const WIDTH := 6.0
const OUTLINE_WIDTH := 2.0
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const COLORS := {1: Color("3d8bff"), 2: Color("f5b83d")}


func _ready() -> void:
	refresh()


## Shows or hides the ring to match the current setting and redraws it
func refresh() -> void:
	visible = Settings.distinct_chips
	queue_redraw()


func _draw() -> void:
	var chip := get_parent() as Chip
	if chip:
		draw_rim(self, Vector2.ZERO, chip.player_id)


## Draws a player's ring centered on a point of any canvas item (also used by option previews)
static func draw_rim(canvas: CanvasItem, center: Vector2, player_id: int) -> void:
	var color: Color = COLORS.get(player_id, Color.WHITE)
	# A thin dark edge on both sides keeps the ring readable on the pale eye and the green board
	canvas.draw_arc(center, RADIUS + WIDTH / 2.0 + OUTLINE_WIDTH / 2.0, 0.0, TAU, 72, OUTLINE_COLOR, OUTLINE_WIDTH, true)
	canvas.draw_arc(center, RADIUS - WIDTH / 2.0 - OUTLINE_WIDTH / 2.0, 0.0, TAU, 72, OUTLINE_COLOR, OUTLINE_WIDTH, true)
	canvas.draw_arc(center, RADIUS, 0.0, TAU, 72, color, WIDTH, true)
