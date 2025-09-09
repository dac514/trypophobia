extends Node2D

const CHIP_X_MIN = 398
const CHIP_X_MAX = 882
const CHIP_Y_MIN = 0
const CHIP_Y_MAX = 96

const DROP_X_MIN = 350
const DROP_X_MAX = 930
const DROP_Y_MIN = 0
const DROP_Y_MAX = 720

var chip_inventory := {
	1: {Globals.ChipType.EYE: 999, Globals.ChipType.PACMAN: 2, Globals.ChipType.BOMB: 1},
	2: {Globals.ChipType.EYE: 999, Globals.ChipType.PACMAN: 2, Globals.ChipType.BOMB: 1}
}
var current_chip: Chip = null
var current_chip_type: Globals.ChipType = Globals.ChipType.EYE
var current_player_id: int = 2
var current_turn: int = 0
var is_against_bot: bool = false
var is_waiting_to_drop: bool = false

@onready var board: Board = $Board

@onready var next_moves: NextMoves = %UI/NextMoves
@onready var pause_screen: PauseScreen = %PauseScreen
@onready var play_bot_button: Button = %PauseScreen/%PlayBotButton
@onready var play_friend_button: Button = %PauseScreen/%PlayFriendButton
@onready var player_eye: ChipEye = %UI/PlayerEye
@onready var player_label: RichTextLabel = %UI/PlayerLabel
@onready var r_button: Button = %UI/RButton
@onready var t_button: Button = %UI/TButton

@onready var fireworks_bg: ColorRect = $Backgrounds/Fireworks
@onready var lotus_bg: TextureRect = $Backgrounds/Lotus
@onready var main_bg: TextureRect = $Backgrounds/Main

func _ready() -> void:
	_connect_board()
	t_button.pressed.connect(func() -> void:
		if is_waiting_to_drop:
			toggle_chip_type()
	)
	r_button.pressed.connect(func() -> void:
		if is_waiting_to_drop:
			toggle_chip_feature()
	)
	play_bot_button.pressed.connect(func() -> void:
		is_against_bot = true
		start_new_game()
	)
	play_friend_button.pressed.connect(func() -> void:
		is_against_bot = false
		start_new_game()
	)
	if not pause_screen.visible:
		pause_screen.toggle()


func _connect_board() -> void:
	board.board_has_settled.connect(func() -> void:
		start_new_turn.call_deferred()
	)
	board.game_over.connect(func(player_id: int) -> void:
		game_over(player_id)
	)


func _process(_delta: float) -> void:
	if current_chip:
		var pos := get_global_mouse_position()
		current_chip.global_cursor_position = pos
		if is_waiting_to_drop:
			follow_chip(pos)


func _input(event: InputEvent) -> void:
	if is_waiting_to_drop:
		# Click to drop
		var pos := get_global_mouse_position()
		if event is InputEventMouse:
			pos = (event as InputEventMouse).position
		elif event is InputEventScreenTouch:
			pos = (event as InputEventScreenTouch).position
		if event.is_action_pressed("click") and can_drop_chip(pos):
			drop_chip(pos)
		# Keyboard controls
		elif event.is_action_pressed("toggle_chip"):
			await _trigger_button_press(t_button)
		elif event.is_action_pressed("toggle_feature"):
			await _trigger_button_press(r_button)


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
	next_moves.draw_next_moves(board)
	if is_against_bot && current_player_id == 2:
		await make_bot_move()


## Make the chip follow the cursor within bounds
func follow_chip(pos: Vector2) -> void:
	current_chip.global_position = Vector2(clamp(pos.x, CHIP_X_MIN, CHIP_X_MAX), clamp(pos.y, CHIP_Y_MIN, CHIP_Y_MAX))


## Check if the position is within the drop area
func can_drop_chip(pos: Vector2) -> bool:
	var in_drop_area: bool = pos.x >= DROP_X_MIN and pos.x <= DROP_X_MAX and pos.y >= DROP_Y_MIN and pos.y <= DROP_Y_MAX
	return in_drop_area


## Update the player label with current turn and inventory
func update_player_label(animate: bool) -> void:
	var player1_name := "Player 1"
	var player2_name := "Player 2"
	if is_against_bot:
		player2_name = "Bot"

	var current_chip_img := "👾" if current_chip_type == Globals.ChipType.PACMAN else "💣" if current_chip_type == Globals.ChipType.BOMB else "👁️"
	var turn_text := "%s, Turn %d, Chip %s" % [player1_name if current_player_id == 1 else player2_name, current_turn, current_chip_img]
	var player1_text := "%s has %d 💣 and %d 👾" % [player1_name, chip_inventory[1][Globals.ChipType.BOMB], chip_inventory[1][Globals.ChipType.PACMAN]]
	var player2_text := "%s has %d 💣 and %d 👾" % [player2_name, chip_inventory[2][Globals.ChipType.BOMB], chip_inventory[2][Globals.ChipType.PACMAN]]
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
	var player1_name := "Player 1"
	var player2_name := "Player 2"
	if is_against_bot:
		player2_name = "Bot"

	var new_text: String
	if player_id:
		new_text = "GAME OVER\nThe winner is: " + (player1_name if player_id == 1 else player2_name)
	else:
		new_text = "GAME OVER\nIt's a tie!"

	player_label.text = new_text
	player_eye.player_id = player_id
	player_eye.update_texture()

	await get_tree().create_timer(5.0).timeout
	pause_screen.game_in_progress = false
	if not pause_screen.visible:
		pause_screen.toggle()


## Drop the current chip onto the board
func drop_chip(pos: Vector2 = Vector2.ZERO) -> void:
	is_waiting_to_drop = false
	if pos != Vector2.ZERO:
		follow_chip(pos)
	current_chip.disable_physics(false)
	chip_inventory[current_player_id][current_chip_type] -= 1
	await current_chip.chip_has_settled
	if is_instance_valid(current_chip):
		board.place_chip(current_chip)
	board.rotate_and_settle.call_deferred()


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
	var center_x := (CHIP_X_MIN + CHIP_X_MAX) / 2.0
	var center_y := (CHIP_Y_MIN + CHIP_Y_MAX) / 2.0
	current_chip.global_position = Vector2(center_x, center_y)
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
	var thinking_pos := Vector2((CHIP_X_MIN + CHIP_X_MAX) / 2.0, (CHIP_Y_MIN + CHIP_Y_MAX) / 2.0)
	follow_chip(thinking_pos)
	# Calculate move
	var bot := Bot.new()
	add_child(bot)
	bot.find_best_move(board.grid_state, current_player_id, chip_inventory, board.board_rotator.next_rotation_states)
	var move: BotMove = await bot.best_move
	bot.worker.wait_to_finish()
	bot.queue_free()
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
	var column_width: float = (DROP_X_MAX - DROP_X_MIN) / float(board.GRID_SIZE.x - 1)
	var drop_x: float = DROP_X_MIN + (column * column_width)
	var drop_y: float = DROP_Y_MIN + 100  # Drop near top of the drop area
	var drop_position := Vector2(drop_x, drop_y)
   	# Animate chip movement to drop position
	follow_chip(thinking_pos)
	var tween := create_tween()
	tween.tween_property(current_chip, "global_position", drop_position, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	# Execute the drop
	print("Bot dropping %s chip at column %d" % [Globals.ChipType.keys()[move.chip_type], column])
	drop_chip(drop_position)
