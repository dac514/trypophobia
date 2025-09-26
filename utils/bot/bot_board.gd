class_name BotBoard
extends RefCounted

const GRID_SIZE: Vector2i = Board.GRID_SIZE

var current_board_permutation: Array
var chip_count: int


## Creates a new BotBoard grid with PlayerIDs from a grid of Chip objects
func _init(grid_state: Array) -> void:
	chip_count = _count_placed_chips(grid_state)
	current_board_permutation = _convert_grid_of_chips_to_player_ids(grid_state)


## Helper to count chips in an integer grid
func _count_chips_in_integer_grid(grid: Array) -> int:
	var count: int = 0
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			if grid[col][row] != 0:
				count += 1
	return count


## Creates a copy of this BotBoard with the same state
func duplicate() -> BotBoard:
	var original_grid: Array = []
	for col in range(GRID_SIZE.x):
		var column: Array = []
		for row in range(GRID_SIZE.y):
			column.append(null)
		original_grid.append(column)

	var new_board := BotBoard.new(original_grid)
	new_board.chip_count = chip_count
	new_board.current_board_permutation = current_board_permutation.duplicate(true)
	return new_board


## Gets all valid column moves for current board state
func get_valid_moves() -> Array:
	var moves: Array = []
	for col in range(GRID_SIZE.x):
		# Check if the top row of this column is empty (can drop chip)
		if current_board_permutation[col][0] == 0:
			var bot_move := BotMove.new(Globals.ChipType.EYE, col)
			moves.append(bot_move)

	return moves


## Sets rotated board as current permutation
func simulate_rotation(rotation_state: Dictionary) -> void:
	var direction: int = rotation_state.get("direction", 0)
	var degrees: int = rotation_state.get("degrees", 0)
	# Apply rotation transformation (cached)
	if degrees == 90:
		if direction == 1:  # Right 90°
			current_board_permutation = _rotate_grid_right_90(current_board_permutation)
		else:  # Left 90°
			current_board_permutation = _rotate_grid_left_90(current_board_permutation)
	elif degrees == 180:
		current_board_permutation = _rotate_grid_180(current_board_permutation)
	else:
		return


func check_for_win(column: int, row: int) -> bool:
	var player_id: int = current_board_permutation[column][row]
	if player_id == 0:
		return false

	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for direction in directions:
		var chips_in_a_row := 1
		chips_in_a_row += _count_line(current_board_permutation, column + direction.x, row + direction.y, direction, player_id)
		chips_in_a_row += _count_line(current_board_permutation, column - direction.x, row - direction.y, Vector2i(-direction.x, -direction.y), player_id)
		if chips_in_a_row >= 4:
			return true

	return false


func _count_placed_chips(grid_state: Array) -> int:
	var count: int = 0
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			var chip: Variant = grid_state[col][row]
			if chip != null:
				count += 1

	return count


func _convert_grid_of_chips_to_player_ids(grid_state: Array) -> Array:
	var copied_grid: Array = []
	for col in range(GRID_SIZE.x):
		var column: Array = []
		for row in range(GRID_SIZE.y):
			var chip: Chip = grid_state[col][row]
			column.append(chip.player_id if chip else 0)
		copied_grid.append(column)

	return copied_grid


func _rotate_grid_left_90(current_board: Array) -> Array:
	var rotated_board: Array = []
	for col in range(GRID_SIZE.x):
		var column: Array = []
		for row in range(GRID_SIZE.y):
			column.append(0)
		rotated_board.append(column)

	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			# Right 90°: (col,row) -> (row, GRID_SIZE.y-1-col)
			var new_col: int = row
			var new_row: int = GRID_SIZE.y - 1 - col
			if new_col < GRID_SIZE.x and new_row < GRID_SIZE.y:
				var player_id: int = current_board[col][row]
				rotated_board[new_col][new_row] = player_id

	return _apply_gravity(rotated_board)


func _rotate_grid_right_90(current_board: Array) -> Array:
	var rotated_board: Array = []
	for col in range(GRID_SIZE.x):
		var column: Array = []
		for row in range(GRID_SIZE.y):
			column.append(0)
		rotated_board.append(column)

	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			# Left 90°: (col,row) -> (GRID_SIZE.x-1-row, col)
			var new_col: int = GRID_SIZE.x - 1 - row
			var new_row: int = col
			if new_col < GRID_SIZE.x and new_row < GRID_SIZE.y:
				var player_id: int = current_board[col][row]
				rotated_board[new_col][new_row] = player_id

	return _apply_gravity(rotated_board)


func _rotate_grid_180(current_board: Array) -> Array:
	var rotated_board: Array = []
	for col in range(GRID_SIZE.x):
		var column: Array = []
		for row in range(GRID_SIZE.y):
			column.append(0)
		rotated_board.append(column)

	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			# 180°: (col,row) -> (GRID_SIZE.x-1-col, GRID_SIZE.y-1-row)
			var new_col: int = GRID_SIZE.x - 1 - col
			var new_row: int = GRID_SIZE.y - 1 - row
			var player_id: int = current_board[col][row]
			rotated_board[new_col][new_row] = player_id

	return _apply_gravity(rotated_board)


## Make chips fall to the bottom in each column
func _apply_gravity(current_board: Array) -> Array:
	var gravity_board: Array = []
	for col in range(GRID_SIZE.x):
		var column: Array = []
		for row in range(GRID_SIZE.y):
			column.append(0)
		gravity_board.append(column)

	for col in range(GRID_SIZE.x):
		var chips_in_column: Array = []
		for row in range(GRID_SIZE.y):
			if current_board[col][row] != 0:
				chips_in_column.append(current_board[col][row])
		for j in range((gravity_board[col] as Array).size() - 1, -1, -1):
			if chips_in_column:
				gravity_board[col][j] = chips_in_column.pop_back()

	return gravity_board


# A helper function to find a continuous line of chips
func _count_line(current_board: Array, col: int, row: int, direction: Vector2i, player_id: int) -> int:
	var count := 0
	var current_col := col
	var current_row := row

	while current_col >= 0 and current_col < GRID_SIZE.x and current_row >= 0 and current_row < GRID_SIZE.y:
		if current_board[current_col][current_row] != player_id:
			break
		count += 1
		current_col += direction.x
		current_row += direction.y

	return count


## Creates a new BotBoard with a move applied (placement + effects + rotation + gravity)
func simulate_move_and_rotation(move: BotMove, player_id: int, next_rotation_states: Array) -> BotBoard:
	var new_board := simulate_move(move, player_id)
	# Apply rotation if available
	if next_rotation_states.size() > 0:
		var rotation_state: Dictionary = next_rotation_states[0]
		new_board.simulate_rotation(rotation_state)

	return new_board


## Simulate a move on the current board
func simulate_move(move: BotMove, player_id: int) -> BotBoard:
	var new_board := duplicate()
	var current_board := new_board.current_board_permutation

	# Step 1: Place the chip
	var drop_row: int = _find_drop_row(current_board, move.column)
	if drop_row == -1:
		return new_board  # Invalid move - column full

	current_board[move.column][drop_row] = player_id

	# Step 2: Apply chip effects only
	if move.chip_type == Globals.ChipType.BOMB:
		_apply_bomb_effect(current_board, move.column, drop_row)
	elif move.chip_type == Globals.ChipType.PACMAN:
		var direction := _get_pacman_direction(move.direction)
		_apply_pacman_effect(current_board, move.column, drop_row, direction)

	return new_board


## Checks if the given player has a winning line on current board
func has_winning_line(player_id: int) -> bool:
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			if current_board_permutation[col][row] == player_id:
				if check_for_win(col, row):
					return true
	return false


## Evaluates board position strength for the given player
func evaluate_position(player_id: int) -> float:
	var score: float = 0.0
	var opponent_id: int = 3 - player_id

	# Check for immediate wins/losses
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			var chip_player_id: int = current_board_permutation[col][row]
			if chip_player_id != 0:
				if check_for_win(col, row):
					if chip_player_id == player_id:
						return 1000.0  # Win
					else:
						return -1000.0  # Loss

	# Evaluate positions and potential lines
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			var chip_player_id: int = current_board_permutation[col][row]
			if chip_player_id != 0:
				var player_multiplier: int = 1 if chip_player_id == player_id else -1

				# Reduced center control bonus (less relevant with rotations)
				var center_distance: float = abs(col - GRID_SIZE.x / 2.0) + abs(row - GRID_SIZE.y / 2.0)
				score += player_multiplier * max(0, 2.0 - center_distance * 0.5)  # Lower weight

				# Bonus for bottom rows (chips settle here after gravity)
				var bottom_bonus: float = (GRID_SIZE.y - row) * 3.0  # Higher for lower rows
				score += player_multiplier * bottom_bonus

				# Bonus for corner-adjacent positions (likely to cluster)
				var corner_bonus: float = 0.0
				if (col == 0 or col == GRID_SIZE.x - 1) and (row == 0 or row == GRID_SIZE.y - 1):
					corner_bonus = 5.0
				score += player_multiplier * corner_bonus

				# Enhanced line evaluation with blocking heuristic
				var line_score: float = _evaluate_lines_from_position(current_board_permutation, col, row, chip_player_id)
				if player_multiplier == -1:  # Opponent chip: penalize more for threats
					line_score *= 1.5  # Increase penalty for opponent lines
				score += player_multiplier * line_score

	# Add mobility bonus: Favor positions with more valid moves
	var valid_moves: Array = get_valid_moves()
	score += valid_moves.size() * 5.0  # Slight bonus for flexibility

	# Simple threat detection: Penalize if opponent has 3-in-a-row potential
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			if current_board_permutation[col][row] == opponent_id:
				var opp_line_score: float = _evaluate_lines_from_position(current_board_permutation, col, row, opponent_id)
				if opp_line_score >= 9:  # Threshold for 3-in-a-row (3^2)
					score -= 50.0  # Strong penalty for threats

	return score


## Check if game is over (all columns full)
func is_game_over() -> bool:
	for col in range(GRID_SIZE.x):
		if current_board_permutation[col][0] == 0:
			return false
	return true


func _find_drop_row(current_board: Array, column: int) -> int:
	for row in range(GRID_SIZE.y - 1, -1, -1):
		if current_board[column][row] == 0:
			return row
	return -1


func _apply_bomb_effect(current_board: Array, col: int, row: int) -> void:
	# Remove adjacent chips
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			var nx: int = col + dx
			var ny: int = row + dy
			if (dx != 0 or dy != 0) and nx >= 0 and nx < GRID_SIZE.x and ny >= 0 and ny < GRID_SIZE.y:
				current_board[nx][ny] = 0
	# Remove self
	current_board[col][row] = 0


func _apply_pacman_effect(current_board: Array, col: int, row: int, direction: Vector2i) -> void:
	var tx: int = col + direction.x
	var ty: int = row + direction.y
	if tx >= 0 and tx < GRID_SIZE.x and ty >= 0 and ty < GRID_SIZE.y:
		current_board[tx][ty] = 0
	# Remove self
	current_board[col][row] = 0


func _get_pacman_direction(direction: String) -> Vector2i:
	match direction:
		"down":
			return Vector2i(0, 1)
		"left":
			return Vector2i(-1, 0)
		"up":
			return Vector2i(0, -1)
		_:
			return Vector2i(1, 0)


func _evaluate_lines_from_position(current_board: Array, col: int, row: int, player_id: int) -> float:
	var line_score: float = 0.0
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]

	for direction in directions:
		var count: int = 1  # Current chip
		var spaces: int = 0

		# Count in positive direction
		for i in range(1, 4):
			var nx: int = col + direction.x * i
			var ny: int = row + direction.y * i
			if nx < 0 or nx >= GRID_SIZE.x or ny < 0 or ny >= GRID_SIZE.y:
				break
			var chip_player_id: int = current_board[nx][ny]
			if chip_player_id == player_id:
				count += 1
			elif chip_player_id == 0:
				spaces += 1
			else:
				break

		# Count in negative direction
		for i in range(1, 4):
			var nx: int = col - direction.x * i
			var ny: int = row - direction.y * i
			if nx < 0 or nx >= GRID_SIZE.x or ny < 0 or ny >= GRID_SIZE.y:
				break
			var chip_player_id: int = current_board[nx][ny]
			if chip_player_id == player_id:
				count += 1
			elif chip_player_id == 0:
				spaces += 1
			else:
				break

		# Score based on potential
		if count >= 2 and spaces >= (4 - count):
			line_score += count * count  # Exponential scoring for longer lines

	return line_score


# A debug function to print the board state in ASCII format
func print_ascii_grid() -> void:
	print("-- GRID STATE BOT --") # Divider before grid
	for row in range(GRID_SIZE.y):
		var line := ""
		for col in range(GRID_SIZE.x):
			var player_id: int = current_board_permutation[col][row]
			line += str(player_id) + " "
		print(line)
	print("------------------") # Divider after grid
