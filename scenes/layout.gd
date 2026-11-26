class_name Layout
extends Node

## Arranges the game for landscape or portrait screens and keeps it arranged when the window or
## device turns.
##
## The game is designed at 1280x720 (landscape) and 720x1280 (portrait). The stretch aspect is
## "expand", so the visible area can be wider or taller than that; everything is placed relative
## to the visible area (minus safe-area insets on phones), never at fixed coordinates.
##
## Landscape: next rotations top-left, turn info top-right, board centered at the bottom, chip
## buttons (T, R) down the right side. Portrait: turn info and next rotations on top, the board in
## the middle, chip buttons at the bottom within thumb reach. In both, the menu is a small gear
## tucked into the bottom-right corner, out of the way.

## Emitted after every layout pass
signal layout_applied
## Emitted when the orientation changes (and after the first layout)
signal layout_changed(is_portrait: bool)

const LANDSCAPE_SIZE := Vector2i(1280, 720)
const PORTRAIT_SIZE := Vector2i(720, 1280)
## Space around the edges of the screen
const MARGIN := 24.0
## Size of the chip buttons (T and R)
const BUTTON_SIZE := 104.0
const BUTTON_GAP := 28.0
## Tap area of the menu gear (the 50px icon is drawn centered in it, so it stays crisp and
## easy to hit), and the distance from the screen corner to that area
const GEAR_SIZE := 84.0
const GEAR_MARGIN := 3.0
const FADE_SECONDS := 0.25
## Where portrait mode centers its slice of the forest picture (0 = left edge, 1 = right edge)
const PORTRAIT_FOREST_FOCUS := 0.84

var is_portrait := false

var _main: Node2D
var _board: Board
var _backgrounds: Control
var _ui: Control
var _pending := false
var _first_layout := true


func _init(main: Node2D) -> void:
	_main = main
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_board = _main.get_node("Board")
	_backgrounds = _main.get_node("Backgrounds")
	_ui = _main.get_node("%UI")
	get_tree().root.size_changed.connect(request_layout)
	apply()


## Lays out again now, or as soon as the board is idle if chips are moving
func request_layout() -> void:
	_pending = true
	if _board.is_busy and get_window().size.x > 0 and get_window().size.y > 0:
		# The full layout waits for the chips to settle; until then at least fill the new screen
		# shape with the background, so no empty area shows
		var visible_rect := get_viewport().get_visible_rect()
		_backgrounds.position = visible_rect.position
		_backgrounds.size = visible_rect.size
		var window_size := get_window().size
		_frame_forest(visible_rect.size, window_size.y > window_size.x)


func _process(_delta: float) -> void:
	if _pending and not _board.is_busy:
		_pending = false
		_relayout_with_fade()


func _relayout_with_fade() -> void:
	var window_size := get_window().size
	var wants_portrait := window_size.y > window_size.x
	if wants_portrait == is_portrait:
		apply()  # Same orientation, just a different size: no fade needed
		return
	var fade_out := create_tween()
	fade_out.tween_property(_main, "modulate:a", 0.0, FADE_SECONDS)
	await fade_out.finished
	apply()
	var fade_in := create_tween()
	fade_in.tween_property(_main, "modulate:a", 1.0, FADE_SECONDS)


## Places everything for the current window shape
func apply() -> void:
	var window := get_window()
	if window.size.x <= 0 or window.size.y <= 0:
		return  # Minimized (or headless): nothing to arrange until it has a size again
	var was_portrait := is_portrait
	is_portrait = window.size.y > window.size.x
	window.content_scale_size = PORTRAIT_SIZE if is_portrait else LANDSCAPE_SIZE

	var visible_rect := get_viewport().get_visible_rect()
	var area := _safe_area(visible_rect)

	_backgrounds.position = visible_rect.position
	_backgrounds.size = visible_rect.size
	_frame_forest(visible_rect.size, is_portrait)

	if is_portrait:
		_layout_portrait(area)
	else:
		_layout_landscape(area)

	# The menu gear: small, in the bottom-right corner
	var gear := _ui.get_node("PauseButton") as Control
	gear.size = Vector2(GEAR_SIZE, GEAR_SIZE)
	gear.position = _to_ui(area.end - Vector2(GEAR_MARGIN + GEAR_SIZE, GEAR_MARGIN + GEAR_SIZE))

	layout_applied.emit()
	if is_portrait != was_portrait or _first_layout:
		_first_layout = false
		layout_changed.emit(is_portrait)


## The visible area minus the parts covered by notches and system bars (phones only)
func _safe_area(visible_rect: Rect2) -> Rect2:
	if not OS.has_feature("mobile"):
		return visible_rect
	var screen_safe := Rect2(DisplayServer.get_display_safe_area())
	var window_rect := Rect2(get_window().position, get_window().size)
	if window_rect.size.x <= 0 or window_rect.size.y <= 0:
		return visible_rect
	var to_canvas := visible_rect.size / window_rect.size
	var top_left := ((screen_safe.position - window_rect.position) * to_canvas).max(Vector2.ZERO)
	var bottom_right := ((window_rect.end - screen_safe.end) * to_canvas).max(Vector2.ZERO)
	return Rect2(visible_rect.position + top_left, visible_rect.size - top_left - bottom_right)


func _layout_landscape(area: Rect2) -> void:
	# Board: centered, resting on the bottom edge (with the hold strip above it). On screens
	# taller than 16:9 it moves up toward the middle instead of hugging the bottom.
	var board_y := area.position.y + maxf(area.size.y - Board.HALF_EXTENT, area.size.y / 2.0 + 72.0)
	_board.position = Vector2(area.get_center().x, board_y)

	var next_moves := _ui.get_node("Mask") as Control
	next_moves.position = _to_ui(area.position + Vector2(MARGIN, 32.0))

	var label := _ui.get_node("PlayerLabel") as RichTextLabel
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size = Vector2(340.0, 96.0)
	label.position = _to_ui(Vector2(area.end.x - MARGIN - 18.0 - label.size.x, area.position.y + 26.0))

	# Right column: turn indicator, then the chip buttons
	var column_x := area.end.x - MARGIN - 18.0 - BUTTON_SIZE / 2.0
	var eye := _ui.get_node("PlayerEye") as Node2D
	eye.position = _to_ui(Vector2(column_x, area.position.y + 192.0))
	_place_button("TButton", Vector2(column_x - BUTTON_SIZE / 2.0, area.position.y + 262.0))
	_place_button("RButton", Vector2(column_x - BUTTON_SIZE / 2.0, area.position.y + 262.0 + BUTTON_SIZE + BUTTON_GAP))


func _layout_portrait(area: Rect2) -> void:
	# Everything lines up with the board's left and right edges
	var board_left := area.get_center().x - Board.HALF_EXTENT
	var board_right := area.get_center().x + Board.HALF_EXTENT

	# Top: turn indicator and turn info side by side, next rotations centered below them
	var top := area.position.y + 32.0
	var eye := _ui.get_node("PlayerEye") as Node2D
	eye.position = _to_ui(Vector2(board_left + 52.0, top + 52.0))
	var label := _ui.get_node("PlayerLabel") as RichTextLabel
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var label_left := board_left + 104.0 + 20.0
	label.size = Vector2(board_right - label_left, 96.0)
	label.position = _to_ui(Vector2(label_left, top + 4.0))

	var next_moves := _ui.get_node("Mask") as Control
	var next_moves_top := top + 104.0 + 28.0
	next_moves.position = _to_ui(Vector2(area.get_center().x - next_moves.size.x / 2.0, next_moves_top))
	var next_moves_bottom := next_moves_top + next_moves.size.y

	# Bottom: chip buttons under the board's left edge, at fixed spots so they never move
	# under a finger (R only shows up for the pacman)
	var bar_y := area.end.y - 48.0 - GEAR_SIZE / 2.0 - BUTTON_SIZE / 2.0
	_place_button("TButton", Vector2(board_left, bar_y))
	_place_button("RButton", Vector2(board_left + BUTTON_SIZE + BUTTON_GAP, bar_y))

	# Middle: the hold strip and board, centered in the space left between top and bottom
	var block := Board.HOLD_STRIP_HEIGHT + Board.HALF_EXTENT * 2.0
	var free_space := bar_y - next_moves_bottom - block
	var board_top := next_moves_bottom + maxf(free_space / 2.0, 0.0) + Board.HOLD_STRIP_HEIGHT
	_board.position = Vector2(area.get_center().x, board_top + Board.HALF_EXTENT)


## The forest background is a wide picture whose middle is mostly fog. Landscape shows all of it;
## portrait only has room for a slice, so frame a cluster of trees instead of the fog.
func _frame_forest(visible_size: Vector2, portrait: bool) -> void:
	var forest := _backgrounds.get_node("Main") as TextureRect
	if not portrait:
		forest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		forest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var texture_size := forest.texture.get_size()
	var height := visible_size.y
	var width := maxf(texture_size.x * height / texture_size.y, visible_size.x)
	forest.stretch_mode = TextureRect.STRETCH_SCALE
	forest.set_anchors_preset(Control.PRESET_TOP_LEFT)
	forest.size = Vector2(width, height)
	var left := visible_size.x / 2.0 - PORTRAIT_FOREST_FOCUS * width
	forest.position = Vector2(clampf(left, visible_size.x - width, 0.0), 0.0)


## Sizes a chip button and puts its top-left corner at a canvas position
func _place_button(button_name: String, canvas_position: Vector2) -> void:
	var button := _ui.get_node(button_name) as Control
	button.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.position = _to_ui(canvas_position)


## Converts a canvas position to the UI's own coordinates (the UI fills the visible area)
func _to_ui(canvas_position: Vector2) -> Vector2:
	return canvas_position - _backgrounds.position
