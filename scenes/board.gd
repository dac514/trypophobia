class_name Board
extends Node2D

signal board_has_settled
signal game_over(playerId: int)

const GRID_SIZE: Vector2i = Vector2i(6, 6)
## Size of one grid cell, in pixels
const CELL_SIZE: float = 96.0
## Half the width (and height) of the grid, in pixels; the Board node sits at the grid's center
const HALF_EXTENT: float = CELL_SIZE * GRID_SIZE.x / 2.0

var grid_state: Array
## True from the moment a chip is dropped until the board has rotated and settled
var is_busy: bool = false

@onready var chip_positions: Node2D = %ChipPositions
@onready var board_rotator: BoardRotator = %BoardRotator


func _ready() -> void:
	reset_grid()
	board_rotator.board_has_settled.connect(
		func(chips: Array[Chip]) -> void:
			reset_grid()
			for chip in chips:
				if is_instance_valid(chip):
					place_chip(chip)
			_print_ascii_grid()
			is_busy = false
			if has_winning_line():
				return
			if is_board_full():
				game_over.emit(0)  # No column left and no line: a draw
				return
			board_has_settled.emit()
	)


## Column under a board-local x position, or -1 when it's outside the grid
static func column_at_local_x(x: float) -> int:
	if x < -HALF_EXTENT or x > HALF_EXTENT:
		return -1
	return clampi(floori((x + HALF_EXTENT) / CELL_SIZE), 0, GRID_SIZE.x - 1)


## Board-local x position of a column's center
static func column_center_local_x(column: int) -> float:
	return -HALF_EXTENT + CELL_SIZE * (column + 0.5)


## True when the column's top cell is taken, so no chip can be dropped into it
func is_column_full(column: int) -> bool:
	return grid_state[column][0] != null


func is_board_full() -> bool:
	for column in range(GRID_SIZE.x):
		if not is_column_full(column):
			return false
	return true


## Briefly tints a column red, to show a chip can't go there
func flash_column(column: int) -> void:
	var flash := ColorRect.new()
	flash.color = Color(0.9, 0.15, 0.2, 0.0)
	flash.size = Vector2(CELL_SIZE, CELL_SIZE * GRID_SIZE.y)
	flash.position = Vector2(-HALF_EXTENT + CELL_SIZE * column, -HALF_EXTENT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 3
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.35, 0.08)
	tween.tween_property(flash, "color:a", 0.0, 0.35)
	tween.tween_callback(flash.queue_free)


## Reset the logical grid
func reset_grid() -> void:
	grid_state.resize(GRID_SIZE.x)
	for i in range(GRID_SIZE.x):
		var grid_sub_state := Array()
		grid_sub_state.resize(GRID_SIZE.y)
		grid_state[i] = grid_sub_state


## Clear chips from the board
func clear_chips() -> void:
	for pos_node in chip_positions.get_children():
		for child in pos_node.get_children():
			if child is Chip:
				child.queue_free()
	for node in board_rotator.get_children():
		if node is Chip:
			node.queue_free()
	reset_grid()


func find_nearest_pos(chip_to_check: Chip) -> Node2D:
	var positions := chip_positions.get_children()
	var nearest_pos: Node2D = null
	var min_distance := INF

	for pos_node in positions:
		var distance: float = chip_to_check.global_position.distance_to((pos_node as Node2D).global_position)
		if distance < min_distance:
			min_distance = distance
			nearest_pos = pos_node

	return nearest_pos


func place_chip(chip: Chip, pos: Node2D = null) -> void:
	if pos == null:
		pos = find_nearest_pos(chip)
	var pos_name := pos.name
	var parts := pos_name.split("_")
	var row := int(parts[1])
	var column := int(parts[2])
	if grid_state[column][row] != null and grid_state[column][row] != chip:
		# Never stack two chips in one cell; the physics shouldn't allow it, but be safe
		push_warning("Board: cell %d,%d is already taken, ignoring %s" % [column, row, chip.name])
		return
	grid_state[column][row] = chip
	chip.call_deferred("lock_into_place", pos)


func rotate_and_settle() -> void:
	await board_rotator.rotate_and_settle()


## Checks if there are winning lines on the board
func has_winning_line() -> bool:
	var player_1_win: bool = false
	var player_2_win: bool = false
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			if check_for_win(col, row) == 1:
				player_1_win = true
			elif check_for_win(col, row) == 2:
				player_2_win = true

	if player_1_win and player_2_win:
		game_over.emit(0)
		return true
	if player_1_win:
		game_over.emit(1)
		return true
	if player_2_win:
		game_over.emit(2)
		return true

	return false


## Returns the player ID of the winner if there's a winning line at the specified position,
## or -1 if none
func check_for_win(column: int, row: int) -> int:
	if grid_state[column][row] == null:
		return -1

	var player_id: int = grid_state[column][row].player_id
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]

	for direction in directions:
		var chips_in_a_row := [grid_state[column][row]]
		# Check one direction
		chips_in_a_row.append_array(_get_line(column + direction.x, row + direction.y, direction, player_id))
		# Check the opposite direction
		chips_in_a_row.append_array(_get_line(column - direction.x, row - direction.y, Vector2i(-direction.x, -direction.y), player_id))
		if chips_in_a_row.size() >= 4:
			_highlight_winning_chips(chips_in_a_row)
			# game_over.emit(player_id)
			return player_id

	return -1


# A helper function to find a continuous line of chips
func _get_line(col: int, row: int, direction: Vector2i, player_id: int) -> Array:
	var line_chips: Array[Chip] = []
	if col < 0 or col >= GRID_SIZE.x or row < 0 or row >= GRID_SIZE.y:
		return line_chips

	var current_chip: Chip = grid_state[col][row] if is_instance_valid(grid_state[col][row]) else null
	if current_chip and current_chip.player_id == player_id:
		line_chips.append(current_chip)
		line_chips.append_array(_get_line(col + direction.x, row + direction.y, direction, player_id))

	return line_chips


# A helper function to highlight winning chips
func _highlight_winning_chips(chips: Array) -> void:
	for chip: Chip in chips:
		var tween := create_tween()
		tween.tween_property(chip, "modulate", Color.LIME_GREEN, 0.5)


# A debug function to print the grid state in ASCII format
func _print_ascii_grid() -> void:
	print("--- GRID STATE ---")  # Divider before grid
	for row in range(GRID_SIZE.y):
		var line := ""
		for col in range(GRID_SIZE.x):
			var chip: Chip = grid_state[col][row]
			if chip == null:
				line += "0 "
			else:
				line += str(chip.player_id) + " "
		print(line)
	print("------------------")  # Divider after grid
