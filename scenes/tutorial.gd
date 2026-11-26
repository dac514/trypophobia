class_name Tutorial
extends CanvasLayer

## Interactive tutorial (issue #6): short lessons played on the real board.
##
## Each lesson is a coach card plus a spotlight on the part of the screen it talks about. Some
## lessons only need "Next"; in the others the player has to do the thing (drop an eye, use a
## bomb, aim a mushroom...) on a prepared board with scripted rotations, and gets another try if
## it didn't work. The player always plays player 1; preset chips stand in for the opponent.
##
## Main owns the game; the tutorial drives it through a few hooks (begin_tutorial_turn,
## finish_tutorial, ...) and is told when the board settles or someone wins.

enum Wait { NEXT, DROP, END }

const NONE := {"direction": 0, "degrees": 0}
const RIGHT_90 := {"direction": 1, "degrees": 90}
const HALF := {"direction": 1, "degrees": 180}
const EYES_ONLY := {Globals.ChipType.EYE: 999, Globals.ChipType.BOMB: 0, Globals.ChipType.PACMAN: 0}

const CARD_WIDTH_LANDSCAPE := 310.0
const CARD_MARGIN := 24.0
const SPOTLIGHT_PADDING := 12.0
const SPOTLIGHT_SECONDS := 0.35
const TITLE_COLOR := Color("dba8ea")

var _main: Main
var _steps: Array[Dictionary] = []
var _index := -1
## True while the card shows a result ("Not quite" or "Four in a row!") and waits for its button
var _showing_result := false
## Whether the result button moves on (success) or sets the lesson up again (failure)
var _advance_after_result := false
## Lesson text currently shown (it can change while the player switches chips)
var _shown_variant := ""

var _dim: ColorRect
var _card: PanelContainer
var _title: Label
var _body: Label
var _counter: Label
var _next_button: Button
var _menu_button: Button
var _skip_button: Button
var _header: HBoxContainer
var _button_row: HBoxContainer
var _holes: Array[Rect2] = [Rect2(), Rect2()]
var _hole_tween: Tween


func _init(main: Main) -> void:
	_main = main
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_overlay()
	_steps = _lessons()
	_main.layout.layout_applied.connect(_refresh_placement)
	_go_to(0)


func _process(_delta: float) -> void:
	# Out of the way while the menu is open
	visible = not get_tree().paused
	if _index >= 0 and not _showing_result and _current_variant() != _shown_variant:
		_show_text()


## True when a screen position is on the coach card (so the click isn't a chip drop)
func covers(canvas_position: Vector2) -> bool:
	return visible and _card.get_global_rect().has_point(canvas_position)


## The board has settled after the player's move
func on_board_settled() -> void:
	_finish_drop(0)


## Someone has four in a row (0 = both, a tie)
func on_game_over(winner: int) -> void:
	_finish_drop(winner)


# --- Lessons -----------------------------------------------------------------


func _lessons() -> Array[Dictionary]:
	var drop_how := (
		"Slide your finger along the top of the board, then let go to drop your eye into a column."
		if DisplayServer.is_touchscreen_available()
		else "Move along the top of the board and click to drop your eye into a column."
	)
	return [
		{
			"title": "Welcome to Trypophobia",
			"body": "Line up four eyeballs in a row to win: across, up and down, or diagonally.",
			"spotlight": ["board"],
			"wait": Wait.NEXT,
			"setup": _setup_welcome,
		},
		{
			"title": "Drop an eyeball",
			"body": drop_how,
			"spotlight": ["board_hold"],
			"wait": Wait.DROP,
			"setup": _setup_first_drop,
		},
		{
			"title": "The board turns",
			"body": "After every move the board rotates. The next three turns are shown here; the one on the right is next.",
			"spotlight": ["next_moves"],
			"wait": Wait.NEXT,
			"setup": _setup_preview,
		},
		{
			"title": "Watch it turn",
			"body": "Drop another eye and watch the board make a quarter turn.",
			"spotlight": ["board_hold"],
			"wait": Wait.DROP,
			"setup": _setup_watch_turn,
		},
		{
			"title": "Everything falls",
			"body": "After each turn the eyes fall again, so lines can form or break. Wins only count once all have landed.",
			"spotlight": ["board"],
			"wait": Wait.NEXT,
		},
		{
			"title": "Use the turn",
			"body": "One column wins, but only after the next quarter turn. Which one?",
			"spotlight": ["board_hold", "next_moves"],
			"wait": Wait.DROP,
			"setup": _setup_rotation_puzzle,
			"succeeded": _won,
			"retry": "A quarter turn makes every row a column. Find the row with three of your eyes and fill its gap.",
			"success": "Four in a row! The line only formed after the board turned.",
		},
		{
			"title": "Bombs 💣",
			"body": "Your opponent has three in a row with both ends open. Press T to switch to a bomb.",
			"spotlight": ["t_button", "board"],
			"variants":
			{
				Globals.ChipType.BOMB:
				{
					"body": "Now drop it on their eyes. A bomb destroys every eye around it.",
					"spotlight": ["board_hold"],
				},
			},
			"wait": Wait.DROP,
			"setup": _setup_bomb,
			"succeeded": _opponent_lost_chips.bind(2),
			"retry": "Switch to the bomb with T first, then drop it on the middle of their row.",
		},
		{
			"title": "Mushrooms 👾",
			"body": "Mushrooms eat the eye they're facing. Press T to pick the mushroom.",
			"spotlight": ["t_button", "board"],
			"variants":
			{
				Globals.ChipType.PACMAN:
				{
					"body": "Press R to turn it, then drop it so it faces one of their eyes.",
					"spotlight": ["board_hold", "r_button"],
				},
			},
			"wait": Wait.DROP,
			"setup": _setup_mushroom,
			"succeeded": _opponent_lost_chips.bind(1),
			"retry": "Pick the mushroom with T and turn it with R until it faces one of their eyes, e.g. down, on top of one.",
		},
		{
			"title": "You're ready!",
			"body": "Tip: in Options you can make each player's chips easier to tell apart, or switch off the board shimmer.",
			"spotlight": [],
			"wait": Wait.END,
		},
	]


func _setup_welcome() -> void:
	# Player 1 already has four along the bottom, shown as a winning line
	_load({0: [2], 1: [1, 2], 2: [1], 3: [1, 2], 4: [1]}, [NONE, NONE, NONE], true)
	var line: Array[Chip] = []
	for column in range(1, 5):
		line.append(_main.board.grid_state[column][Board.GRID_SIZE.y - 1] as Chip)
	_main.board.highlight_chips(line)


func _setup_first_drop() -> void:
	_load({}, [NONE, NONE, NONE, RIGHT_90, NONE, HALF, NONE])
	_main.begin_tutorial_turn(EYES_ONLY)


func _setup_preview() -> void:
	_set_rotations([RIGHT_90, NONE, HALF, NONE, NONE], true)


func _setup_watch_turn() -> void:
	_main.begin_tutorial_turn(EYES_ONLY)


func _setup_rotation_puzzle() -> void:
	# Same position as the bot's "win that only exists after the rotation" test: dropping into
	# column 4 completes the second row from the bottom, which the quarter turn makes a column
	_load({0: [2, 1], 1: [2, 1], 3: [1, 1], 4: [2]}, [RIGHT_90, NONE, NONE, NONE])
	_main.begin_tutorial_turn(EYES_ONLY)


func _setup_bomb() -> void:
	_load({1: [2], 2: [2], 3: [2], 5: [1]}, [NONE, NONE, NONE, NONE])
	_main.begin_tutorial_turn({Globals.ChipType.EYE: 999, Globals.ChipType.BOMB: 1, Globals.ChipType.PACMAN: 0})


func _setup_mushroom() -> void:
	_load({0: [1], 1: [2], 2: [2], 3: [2]}, [NONE, NONE, NONE, NONE])
	_main.begin_tutorial_turn({Globals.ChipType.EYE: 999, Globals.ChipType.BOMB: 0, Globals.ChipType.PACMAN: 1})


func _won(winner: int) -> bool:
	return winner == 1


## The three opponent eyes the lesson starts with: at least `count` of them must be gone
func _opponent_lost_chips(_winner: int, count: int) -> bool:
	return _main.board.count_chips(2) <= 3 - count


# --- Flow ----------------------------------------------------------------------


func _go_to(index: int) -> void:
	_index = index
	_showing_result = false
	var step := _steps[_index]
	if step.has("setup"):
		(step.setup as Callable).call()
	if step.wait != Wait.DROP:
		# Nothing to play with on reading-only cards (a new turn shows the right buttons again)
		_main.t_button.visible = false
		_main.r_button.visible = false
	_show_text()


func _finish_drop(winner: int) -> void:
	if _index < 0 or _steps[_index].wait != Wait.DROP or _showing_result:
		return
	var step := _steps[_index]
	var ok := true
	if step.has("succeeded"):
		ok = (step.succeeded as Callable).call(winner)
	if ok and not step.has("success"):
		_go_to(_index + 1)
		return
	_showing_result = true
	_advance_after_result = ok
	if ok:
		_show_message(step.title as String, step.success as String, "Next", ["board"])
	else:
		_show_message("Not quite", step.retry as String, "Try again", [])


func _on_next_pressed() -> void:
	if _showing_result:
		# Success moves on; "Try again" sets the same lesson up again
		_go_to(_index + 1 if _advance_after_result else _index)
	elif _steps[_index].wait == Wait.END:
		_main.finish_tutorial(true)
	else:
		_go_to(_index + 1)


## Replaces the board and the rotations. Lessons that begin a turn right after don't refresh the
## rotation preview here, because starting the turn redraws it anyway.
func _load(stacks: Dictionary, rotations: Array, refresh_preview := false) -> void:
	_main.current_chip = null  # The board is about to be replaced, chip and all
	_main.board.load_layout(stacks)
	_set_rotations(rotations, refresh_preview)


func _set_rotations(rotations: Array, refresh_preview: bool) -> void:
	var typed: Array[Dictionary] = []
	for state: Dictionary in rotations:
		typed.append(state)
	_main.board.board_rotator.set_scripted_rotations(typed)
	if refresh_preview:
		_main.refresh_next_moves()


# --- Card and spotlight --------------------------------------------------------


func _current_variant() -> String:
	var step := _steps[_index]
	if step.has("variants") and (step.variants as Dictionary).has(_main.current_chip_type):
		return str(_main.current_chip_type)
	return ""


func _show_text() -> void:
	var step := _steps[_index]
	_shown_variant = _current_variant()
	var body: String = step.body
	var spotlight: Array = step.spotlight
	if _shown_variant != "":
		var variant: Dictionary = (step.variants as Dictionary)[_main.current_chip_type]
		body = variant.body
		spotlight = variant.spotlight
	_title.text = step.title
	_body.text = body
	_counter.text = "%d / %d" % [_index + 1, _steps.size()]
	var wait: Wait = step.wait
	_next_button.visible = wait != Wait.DROP
	_next_button.text = "Play the Bot" if wait == Wait.END else "Next"
	_menu_button.visible = wait == Wait.END
	_skip_button.visible = wait != Wait.END
	_card.set_meta("spotlight", spotlight)
	_refresh_placement()


func _show_message(title: String, body: String, button_text: String, spotlight: Array) -> void:
	_title.text = title
	_body.text = body
	_next_button.text = button_text
	_next_button.visible = true
	_menu_button.visible = false
	_skip_button.visible = true
	_card.set_meta("spotlight", spotlight)
	_refresh_placement()


## Puts the card where it doesn't cover what it talks about, and moves the spotlight
func _refresh_placement() -> void:
	if not is_inside_tree():
		return
	var targets: Array = _card.get_meta("spotlight", [])
	var rects: Array[Rect2] = []
	for target: String in targets:
		rects.append(_target_rect(target).grow(SPOTLIGHT_PADDING))
	_move_spotlight(rects)

	var visible_rect := get_viewport().get_visible_rect()
	var portrait := _main.layout.is_portrait
	var width := Board.HALF_EXTENT * 2.0 if portrait else CARD_WIDTH_LANDSCAPE
	_arrange_buttons(portrait)
	_card.custom_minimum_size = Vector2(width, 0.0)
	_card.reset_size()
	# Wrapped text only knows its height once laid out at the new width
	await get_tree().process_frame
	_card.reset_size()
	if not portrait:
		_card.position = visible_rect.position + Vector2(CARD_MARGIN, 150.0)
		return
	# At the top, unless the spotlight is only up there (the rotation preview)
	var spotlight_on_top := not rects.is_empty()
	for rect in rects:
		spotlight_on_top = spotlight_on_top and rect.end.y < visible_rect.size.y * 0.3
	var y := visible_rect.position.y + 16.0
	if spotlight_on_top:
		y = visible_rect.end.y - CARD_MARGIN - 100.0 - _card.size.y
	_card.position = Vector2(visible_rect.get_center().x - width / 2.0, y)


func _target_rect(target: String) -> Rect2:
	var board := _main.board
	var board_rect := Rect2(board.global_position - Vector2.ONE * Board.HALF_EXTENT, Vector2.ONE * Board.HALF_EXTENT * 2.0)
	match target:
		"board":
			return board_rect
		"board_hold":
			var top := _main.hold_rect().position.y - Board.CELL_SIZE / 2.0
			return Rect2(board_rect.position.x, top, board_rect.size.x, board_rect.end.y - top)
		"next_moves":
			return (_main.next_moves.get_parent() as Control).get_global_rect()
		"t_button":
			return _main.t_button.get_global_rect()
		"r_button":
			return _main.r_button.get_global_rect()
	return Rect2()


## Glides the spotlight holes to new rectangles (up to two)
func _move_spotlight(rects: Array[Rect2]) -> void:
	var target: Array[Rect2] = [Rect2(), Rect2()]
	for i in range(mini(rects.size(), 2)):
		target[i] = rects[i]
	var from: Array[Rect2] = _holes.duplicate()
	if _hole_tween:
		_hole_tween.kill()
	_hole_tween = create_tween()
	_hole_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hole_tween.tween_method(_interpolate_holes.bind(from, target), 0.0, 1.0, SPOTLIGHT_SECONDS)


func _interpolate_holes(t: float, from: Array[Rect2], target: Array[Rect2]) -> void:
	for i in range(2):
		# A new hole grows from its center; a closing hole shrinks into its center
		var start: Rect2 = from[i] if from[i].has_area() else Rect2(target[i].get_center(), Vector2.ZERO)
		var finish: Rect2 = target[i] if target[i].has_area() else Rect2(start.get_center(), Vector2.ZERO)
		_holes[i] = Rect2(start.position.lerp(finish.position, t), start.size.lerp(finish.size, t))
	var shader_material := _dim.material as ShaderMaterial
	var dim_origin := _dim.global_position
	for i in range(2):
		var rect: Rect2 = _holes[i]
		var value := Vector4(rect.position.x - dim_origin.x, rect.position.y - dim_origin.y, rect.size.x, rect.size.y)
		shader_material.set_shader_parameter("hole_rect" if i == 0 else "hole_rect_2", value)


func _build_overlay() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://scenes/spotlight.gdshader")
	_dim.material = shader_material
	add_child(_dim)

	# Same look as the menu panel
	_card = PanelContainer.new()
	_card.theme = (_main.get_node("%UI") as Control).theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.95)
	style.set_border_width_all(3)
	style.border_color = Color(0.85, 0.85, 0.85)
	style.set_corner_radius_all(20)
	style.set_content_margin_all(20.0)
	style.shadow_size = 7
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_card.add_child(column)

	_header = HBoxContainer.new()
	var header := _header
	column.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	header.add_child(_title)
	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 15)
	_counter.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.55))
	header.add_child(_counter)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 19)
	column.add_child(_body)

	_button_row = HBoxContainer.new()
	var buttons := _button_row
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_skip_button = _make_button("Skip tutorial", 17, _main.finish_tutorial.bind(false))
	_skip_button.flat = true
	_skip_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	buttons.add_child(_skip_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_menu_button = _make_button("Menu", 24, _main.finish_tutorial.bind(false))
	buttons.add_child(_menu_button)
	_next_button = _make_button("Next", 24, _on_next_pressed)
	buttons.add_child(_next_button)


func _make_button(text: String, font_size: int, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(on_pressed)
	return button


## Portrait cards sit over the top of the screen, so keep them short: "Skip" moves up into the
## title row, and the button row disappears when it has nothing left to show.
func _arrange_buttons(portrait: bool) -> void:
	var skip_parent: Node = _header if portrait else _button_row
	if _skip_button.get_parent() != skip_parent:
		_skip_button.reparent(skip_parent)
		if portrait:
			_header.move_child(_skip_button, 1)
		else:
			_button_row.move_child(_skip_button, 0)
	_button_row.visible = not portrait or _next_button.visible or _menu_button.visible
