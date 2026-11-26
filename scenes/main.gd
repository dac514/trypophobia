class_name Main
extends Node2D

## Shortest time the bot appears to think, so its moves never feel abrupt
const BOT_MIN_THINK_SECONDS = 0.6

var chip_inventory := {
	1: {Globals.ChipType.EYE: 999, Globals.ChipType.PACMAN: 2, Globals.ChipType.BOMB: 1},
	2: {Globals.ChipType.EYE: 999, Globals.ChipType.PACMAN: 2, Globals.ChipType.BOMB: 1}
}
var current_chip: Chip = null
var current_chip_type: Globals.ChipType = Globals.ChipType.EYE
var current_player_id: int = 2
var current_turn: int = 0
var is_against_bot: bool = false
var is_mobile_device: bool = false
var is_waiting_to_drop: bool = false
var layout: Layout
## Highest the waiting chip may go (set by Layout in portrait, so it stays clear of the preview)
var hold_top_limit: float = -INF

@onready var board: Board = $Board

@onready var next_moves: NextMoves = %UI/Mask/NextMoves
@onready var pause_screen: PauseScreen = %PauseScreen
@onready var play_bot_button: Button = %PauseScreen/%PlayBotButton
@onready var play_friend_button: Button = %PauseScreen/%PlayFriendButton
@onready var player_eye: ChipEye = %UI/PlayerEye
@onready var player_label: RichTextLabel = %UI/PlayerLabel
@onready var pause_button: TextureButton = %UI/PauseButton
@onready var r_button: Button = %UI/RButton
@onready var t_button: Button = %UI/TButton

@onready var fireworks_bg: ColorRect = $Backgrounds/Fireworks
@onready var lotus_bg: TextureRect = $Backgrounds/Lotus
@onready var main_bg: TextureRect = $Backgrounds/Main


func _ready() -> void:
	_is_mobile_device()
	_connect_board()
	layout = Layout.new(self)
	layout.layout_applied.connect(_on_layout_applied)
	add_child(layout)
	pause_button.pressed.connect(
		func() -> void:
			if pause_screen.game_in_progress and not pause_screen.visible:
				pause_screen.toggle()
	)
	player_label.bbcode_enabled = true  # Player names can be coloured
	Settings.changed.connect(
		func(key: String) -> void:
			if key == Settings.DISTINCT_CHIPS and pause_screen.game_in_progress and current_turn > 0:
				update_player_label(false)
	)
	pause_screen.tutorial_requested.connect(pause_screen.show_info)
	t_button.pressed.connect(
		func() -> void:
			if is_waiting_to_drop:
				toggle_chip_type()
	)
	r_button.pressed.connect(
		func() -> void:
			if is_waiting_to_drop:
				toggle_chip_feature()
	)
	play_bot_button.pressed.connect(
		func() -> void:
			is_against_bot = true
			start_new_game()
	)
	play_friend_button.pressed.connect(
		func() -> void:
			is_against_bot = false
			start_new_game()
	)
	if not pause_screen.visible:
		pause_screen.toggle()
	var tour_directory := ScreenshotTour.requested_directory()
	if tour_directory != "":
		add_child(ScreenshotTour.new(self, tour_directory))


## Keeps the chip waiting to be dropped above the board after the board moved
func _on_layout_applied() -> void:
	if current_chip and is_instance_valid(current_chip) and current_chip.freeze and not board.is_busy:
		current_chip.global_position = hold_rect().get_center()


func _is_mobile_device() -> void:
	is_mobile_device = DisplayServer.is_touchscreen_available()


func _connect_board() -> void:
	board.board_has_settled.connect(func() -> void: start_new_turn.call_deferred())
	board.game_over.connect(func(player_id: int) -> void: game_over(player_id))


func _input(event: InputEvent) -> void:
	if not is_waiting_to_drop:
		return

	if event.is_action_pressed("toggle_chip"):
		await _trigger_button_press(t_button)
		return

	if event.is_action_pressed("toggle_feature"):
		await _trigger_button_press(r_button)
		return

	@warning_ignore_start("UNSAFE_PROPERTY_ACCESS")

	# Track mouse/finger/stylus
	var pos := Vector2.ZERO
	if (event is InputEventMouseMotion or event is InputEventScreenDrag) and current_chip:
		pos = event.position
		current_chip.global_cursor_position = pos
		follow_chip(pos)
		return

	var is_click: bool = false
	if event is InputEventScreenTouch:
		# Tracks finger
		pos = event.position
		if event.pressed:
			follow_chip(pos)
			return
		is_click = true
	elif event is InputEventMouseButton:
		# Tracks desktop click/release AND stylus press/release
		pos = event.position
		if not event.pressed:
			is_click = true

	@warning_ignore_restore("UNSAFE_PROPERTY_ACCESS")

	if is_click and can_drop_chip(pos):
		try_drop_chip(pos)


func _trigger_button_press(b: Button) -> void:
	b.toggle_mode = true
	b.button_pressed = true
	b.emit_signal("pressed")
	await get_tree().create_timer(0.1).timeout
	b.toggle_mode = false
	b.button_pressed = false


func start_new_game() -> void:
	is_waiting_to_drop = false
	# Reset chips
	if current_chip:
		current_chip.queue_free()
	current_chip = null
	board.clear_chips()
	next_moves.is_first_rotation = true
	# Reset players
	current_player_id = 2
	current_turn = 0
	chip_inventory = {
		1: {Globals.ChipType.EYE: 999, Globals.ChipType.PACMAN: 2, Globals.ChipType.BOMB: 1},
		2: {Globals.ChipType.EYE: 999, Globals.ChipType.PACMAN: 2, Globals.ChipType.BOMB: 1}
	}
	# Hide backgrounds
	fireworks_bg.visible = false
	lotus_bg.visible = false
	main_bg.visible = false
	if pause_screen.visible:
		pause_screen.toggle()
	# Start first turn
	pause_screen.game_in_progress = true
	start_new_turn()


## Start a new turn, switch players, and spawn a new chip
func start_new_turn() -> void:
	is_waiting_to_drop = true
	current_player_id = 3 - current_player_id
	current_turn += 1
	update_player_label(true)
	current_chip_type = Globals.ChipType.EYE
	spawn_chip()
	var is_bot_turn := is_against_bot && current_player_id == 2
	next_moves.draw_next_moves(board, is_bot_turn)
	if is_bot_turn:
		await make_bot_move()


## Where the held chip can move: above the board, between the outer column centers (global)
func hold_rect() -> Rect2:
	var left := board.global_position.x + Board.column_center_local_x(0)
	var bottom := board.global_position.y - Board.HALF_EXTENT - Board.CELL_SIZE / 2.0
	var top := maxf(bottom - (Board.HOLD_STRIP_HEIGHT - Board.CELL_SIZE / 2.0), minf(hold_top_limit, bottom))
	return Rect2(left, top, Board.column_center_local_x(Board.GRID_SIZE.x - 1) * 2.0, bottom - top)


## Make the chip follow the cursor within bounds
func follow_chip(pos: Vector2) -> void:
	var rect := hold_rect()
	current_chip.global_position = pos.clamp(rect.position, rect.end)


## Check if the position is within the drop area: over the board or the strip above it
func can_drop_chip(pos: Vector2) -> bool:
	var top := board.global_position.y - Board.HALF_EXTENT - Board.HOLD_STRIP_HEIGHT - Board.CELL_SIZE / 2.0
	var bottom := board.global_position.y + Board.HALF_EXTENT
	return absf(pos.x - board.global_position.x) <= Board.HALF_EXTENT + 2.0 and pos.y >= top and pos.y <= bottom


## The column under the held chip, or -1
func held_chip_column() -> int:
	return Board.column_at_local_x(current_chip.global_position.x - board.global_position.x)


## Drops the held chip into the column under it, or refuses when that column is full
func try_drop_chip(pos: Vector2) -> void:
	follow_chip(pos)
	var column := held_chip_column()
	if column == -1:
		return
	if board.is_column_full(column):
		_refuse_drop(column)
		return
	# Snap to the column center so the chip drops cleanly between the walls
	current_chip.global_position.x = board.global_position.x + Board.column_center_local_x(column)
	drop_chip()


## Shows that the column is full: the column flashes red and the chip shakes its head
func _refuse_drop(column: int) -> void:
	board.flash_column(column)
	var x := current_chip.position.x
	var shake := create_tween()
	for offset: float in [-12.0, 12.0, -8.0, 8.0, 0.0]:
		shake.tween_property(current_chip, "position:x", x + offset, 0.05)


## A player's name for the turn label; coloured like their chip rims with "distinct player chips"
func player_name(player_id: int) -> String:
	var name_text := "Player 1" if player_id == 1 else ("Bot" if is_against_bot else "Player 2")
	if Settings.distinct_chips:
		var color: Color = ChipRim.COLORS[player_id]
		return "[color=#%s]%s[/color]" % [color.to_html(false), name_text]
	return name_text


## Update the player label with current turn and inventory
func update_player_label(animate: bool) -> void:
	var current_chip_img := (
		"👾" if current_chip_type == Globals.ChipType.PACMAN else "💣" if current_chip_type == Globals.ChipType.BOMB else "👁️"
	)
	var turn_text := "%s, Turn %d, Chip %s" % [player_name(current_player_id), current_turn, current_chip_img]
	var player1_text := (
		"%s has %d 💣 and %d 👾" % [player_name(1), chip_inventory[1][Globals.ChipType.BOMB], chip_inventory[1][Globals.ChipType.PACMAN]]
	)
	var player2_text := (
		"%s has %d 💣 and %d 👾" % [player_name(2), chip_inventory[2][Globals.ChipType.BOMB], chip_inventory[2][Globals.ChipType.PACMAN]]
	)
	var new_text := "%s\n%s\n%s" % [turn_text, player1_text, player2_text]

	# Animate the label change
	if animate:
		var tween := create_tween()
		tween.tween_property(player_label, "modulate:a", 0.0, 0.15)
		tween.tween_callback(func() -> void: player_label.text = new_text).set_delay(0.15)
		tween.tween_property(player_label, "modulate:a", 1.0, 0.15)
	else:
		player_label.text = new_text
	player_eye.player_id = current_player_id
	player_eye.update_texture()


## Update the player label with current turn and inventory
func game_over(player_id: int) -> void:
	var new_text: String
	if player_id:
		new_text = "GAME OVER \nThe winner is: " + player_name(player_id) + " \n"
	else:
		new_text = "GAME OVER \nIt's a tie! \n"

	player_label.text = new_text
	player_eye.player_id = 1 if player_id == 1 else 2
	player_eye.update_texture()

	await get_tree().create_timer(5.0).timeout
	pause_screen.game_in_progress = false
	if not pause_screen.visible:
		pause_screen.toggle()


## Drop the current chip onto the board from where it is
func drop_chip() -> void:
	is_waiting_to_drop = false
	board.is_busy = true
	current_chip.disable_physics(false)
	chip_inventory[current_player_id][current_chip_type] -= 1
	next_moves.stop_animation()
	await current_chip.chip_has_settled
	if is_instance_valid(current_chip):
		board.place_chip(current_chip)
	board.rotate_and_settle.call_deferred()
	next_moves.stop_animation()  # Stop again, for when bot drops too quickly


## Spawn a new chip
func spawn_chip() -> void:
	# Hide all backgrounds first
	fireworks_bg.visible = false
	lotus_bg.visible = false
	main_bg.visible = false
	# Instantiate the appropriate chip scene based on current_chip_type
	var chip_scene: PackedScene
	if current_chip_type == Globals.ChipType.EYE:
		chip_scene = preload("res://scenes/chip_eye.tscn")
		main_bg.visible = true
	elif current_chip_type == Globals.ChipType.PACMAN:
		chip_scene = preload("res://scenes/chip_pacman.tscn")
		lotus_bg.visible = true
	elif current_chip_type == Globals.ChipType.BOMB:
		chip_scene = preload("res://scenes/chip_bomb.tscn")
		fireworks_bg.visible = true
	current_chip = chip_scene.instantiate()
	current_chip.z_index = 1 if current_chip_type == Globals.ChipType.EYE else 2
	current_chip.player_id = current_player_id
	current_chip.disable_physics(true)
	add_child(current_chip)
	# Show or hide the R button based on whether the chip has a toggle_feature method
	r_button.visible = current_chip.has_method("toggle_feature") if true else false
	# Show or hide the T button based on inventory
	if chip_inventory[current_player_id][Globals.ChipType.PACMAN] == 0 and chip_inventory[current_player_id][Globals.ChipType.BOMB] == 0:
		t_button.visible = false
	else:
		t_button.visible = true
	# Set chip to center of drop area to avoid upper-left glitch
	current_chip.global_position = hold_rect().get_center()
	# Fade in effect
	current_chip.modulate.a = 0.0
	var chip_tween := create_tween()
	chip_tween.tween_property(current_chip, "modulate:a", 1.0, 0.15)


## Cycle to the next available chip type in inventory
func toggle_chip_type() -> void:
	var chip_types := Globals.ChipType.values()
	var start_idx := chip_types.find(current_chip_type)
	var found := false
	for i in range(1, chip_types.size() + 1):
		var idx := (start_idx + i) % chip_types.size()
		var chip_type_toggle: Globals.ChipType = chip_types[idx]
		if chip_inventory[current_player_id][chip_type_toggle] > 0:
			current_chip_type = chip_type_toggle
			found = true
			break
	if found:
		if current_chip:
			current_chip.queue_free()
		spawn_chip()
	update_player_label(false)


## Toggle the feature of the current chip if it has one
func toggle_chip_feature() -> void:
	if current_chip.has_method("toggle_feature"):
		current_chip.call("toggle_feature")


func make_bot_move() -> void:
	# Pause player control while bot is thinking
	is_waiting_to_drop = false
	var thinking_pos := hold_rect().get_center()
	follow_chip(thinking_pos)
	# Calculate move
	var think_started := Time.get_ticks_msec()
	var bot := Bot.new()
	add_child(bot)
	bot.find_best_move(
		board.grid_state, current_player_id, chip_inventory, board.board_rotator.next_rotation_states, pause_screen.difficulty
	)
	var move: BotMove = await bot.best_move
	bot.worker.wait_to_finish()
	bot.queue_free()
	var thought := (Time.get_ticks_msec() - think_started) / 1000.0
	if thought < BOT_MIN_THINK_SECONDS:
		await get_tree().create_timer(BOT_MIN_THINK_SECONDS - thought).timeout
	if move == null:
		game_over(0)  # No column left: draw
		return
	# Update chip type if different from current
	if current_chip_type != move.chip_type:
		current_chip_type = move.chip_type
		if current_chip:
			current_chip.queue_free()
		spawn_chip()
		update_player_label(false)
	# Set Pacman direction if bot specified one
	if move.chip_type == Globals.ChipType.PACMAN:
		var pacman_chip: ChipPacman = current_chip as ChipPacman
		if pacman_chip != null:
			# Set the rotation index to match bot's choice
			pacman_chip.rotation_direction = move.direction
			pacman_chip.rotate_to_direction(move.direction)

	# Calculate drop position based on column
	var column: int = move.column
	var drop_position := Vector2(board.global_position.x + Board.column_center_local_x(column), hold_rect().end.y)
	# Animate chip movement to drop position
	follow_chip(thinking_pos)
	var tween := create_tween()
	tween.tween_property(current_chip, "global_position", drop_position, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	# Execute the drop
	print("Bot dropping %s chip at column %d" % [Globals.ChipType.keys()[move.chip_type], column])
	drop_chip()
