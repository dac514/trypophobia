class_name BotBoard extends RefCounted

## The BotBoard class simulates and evaluates game states for the AI bot.
##
## It represents the board as a grid of player IDs and provides methods for duplication, chip counting,
## move validation, rotation, and win detection. By simplifying the board to a grid of integers, avoiding
## full game objects or physics, it reduces computational overhead, enabling efficient and isolated evaluations
## for AI decision-making.

const GRID_SIZE: Vector2i = Board.GRID_SIZE

var current_board_permutation: Array
var chip_count: int
var last_action_meta: Dictionary = {}


## Creates a new BotBoard grid with PlayerIDs from a grid of Chip objects
func setup(grid_state: Array) -> void:
	chip_count = _count_placed_chips(grid_state)
	current_board_permutation = _convert_grid_of_chips_to_player_ids(grid_state)


## Creates a copy of this BotBoard with the same state
func duplicate() -> BotBoard:
	var new_board := BotBoard.new()
	new_board.chip_count = chip_count
	new_board.current_board_permutation = current_board_permutation.duplicate(true)
	new_board.last_action_meta = last_action_meta.duplicate(true)
	return new_board


## Gets all valid column moves for current board state
## Returns one placeholder per open column using EYE as a neutral default
## May override chip_type & direction when expanding actual actions
func get_valid_drop_moves() -> Array[BotMove]:
	var moves: Array[BotMove] = []
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
	return _check_for_win_on(current_board_permutation, column, row)


func _check_for_win_on(board_arr: Array, column: int, row: int) -> bool:
	var player_id: int = board_arr[column][row]
	if player_id == 0:
		return false

	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for direction in directions:
		var chips_in_a_row := 1
		chips_in_a_row += _count_line(board_arr, column + direction.x, row + direction.y, direction, player_id)
		chips_in_a_row += _count_line(board_arr, column - direction.x, row - direction.y, Vector2i(-direction.x, -direction.y), player_id)
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
			# Left 90° (CCW): (col,row) -> (row, GRID_SIZE.y-1-col)
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
			# Right 90° (CW): (col,row) -> (GRID_SIZE.x-1-row, col)
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

	# Reset meta by default
	new_board.last_action_meta = {}

	# Step 1: Place the chip
	var drop_row: int = _find_drop_row(current_board, move.column)
	if drop_row == -1:
		return new_board  # Invalid move - column full

	current_board[move.column][drop_row] = player_id

	# Step 2: Apply chip effects only
	if move.chip_type == Globals.ChipType.BOMB:
		var before_counts := _count_pieces_by_player(current_board)
		_apply_bomb_effect(current_board, move.column, drop_row)
		var after_counts := _count_pieces_by_player(current_board)
		var self_id := player_id
		var opp_id := 3 - player_id
		var destroyed_self: int = max(0, int(before_counts.get(self_id, 0)) - int(after_counts.get(self_id, 0)))
		var destroyed_opp: int = max(0, int(before_counts.get(opp_id, 0)) - int(after_counts.get(opp_id, 0)))
		new_board.last_action_meta = {
			"move_type": "bomb",
			"destroyed_self": destroyed_self,
			"destroyed_opp": destroyed_opp,
		}
	elif move.chip_type == Globals.ChipType.PACMAN:
		var before_counts := _count_pieces_by_player(current_board)
		var direction := _get_pacman_direction(move.direction)
		_apply_pacman_effect(current_board, move.column, drop_row, direction)
		var after_counts := _count_pieces_by_player(current_board)
		var self_id := player_id
		var opp_id := 3 - player_id
		var destroyed_self: int = max(0, int(before_counts.get(self_id, 0)) - int(after_counts.get(self_id, 0)))
		var destroyed_opp: int = max(0, int(before_counts.get(opp_id, 0)) - int(after_counts.get(opp_id, 0)))
		new_board.last_action_meta = {
			"move_type": "pacman",
			"destroyed_self": destroyed_self,
			"destroyed_opp": destroyed_opp,
		}

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
func evaluate_position(player_id: int, rotation_states: Array = []) -> float:
	# Base score on current snapshot
	var base_score := _score_board_array(current_board_permutation, player_id)

	# Bomb/Pacman delta: discourage self-damage
	if last_action_meta.has("move_type"):
		var destroyed_self: int = int(last_action_meta.get("destroyed_self", 0))
		var destroyed_opp: int = int(last_action_meta.get("destroyed_opp", 0))
		# Weights tuned conservatively
		base_score += 3.0 * destroyed_opp - 3.5 * destroyed_self

		# Rule for pacman: penalty for eating nothing, or eating self
		if last_action_meta.get("move_type", "") == "pacman":
			if destroyed_opp == 0 or destroyed_self >= 2:
				base_score -= 300.0

		# Rule for bombs: only good if we destroy at least 2 more than we lose
		if last_action_meta.get("move_type", "") == "bomb":
			var ratio_ok := destroyed_opp >= destroyed_self + 2
			if not ratio_ok:
				# Strong penalty to avoid non-emergency bombs
				var shortfall := (destroyed_self + 2) - destroyed_opp
				base_score -= 300.0 + float(shortfall) * 100.0
			# If the bomb leaves an immediate opponent win, punish heavily
			var opp_id := 3 - player_id
			if _opponent_can_win_in_one(current_board_permutation, opp_id):
				base_score -= 500.0

	# Rotation projections over up to next 3 known rotations
	var r_weights := [0.7, 0.2, 0.1]
	var proj_score := 0.0
	var work_array := current_board_permutation.duplicate(true)
	for i in range(min(3, rotation_states.size())):
		work_array = _apply_rotation_to_array(work_array, rotation_states[i])
		var w := float(r_weights[i])
		proj_score += w * _score_board_array(work_array, player_id)

	# Threat stress: if opponent has a one-move win after the very next rotation
	if rotation_states.size() > 0:
		var after_r1 := _apply_rotation_to_array(current_board_permutation, rotation_states[0])
		var opp_id := 3 - player_id
		if _opponent_can_win_in_one(after_r1, opp_id):
			base_score -= 600.0

	# Blend scores; if no projections, just base
	return base_score + proj_score


## Check if game is over (all columns full)
func is_game_over() -> bool:
	for col in range(GRID_SIZE.x):
		if current_board_permutation[col][0] == 0:
			return false
	return true


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


func _score_board_array(board_arr: Array, player_id: int) -> float:
	var score: float = 0.0
	var opponent_id: int = 3 - player_id

	# Short-circuit: if anyone already has 4 in a row, return win/loss now
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			var chip_player_id: int = board_arr[col][row]
			if chip_player_id != 0:
				if _check_for_win_on(board_arr, col, row):
					return 1000.0 if chip_player_id == player_id else -1000.0

	# Positional and line potentials
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			var chip_player_id: int = board_arr[col][row]
			if chip_player_id != 0:
				var pmul := 1 if chip_player_id == player_id else -1

				# Bottom weight (gravity-friendly)
				var bottom_bonus: float = (GRID_SIZE.y - row) * 3.0
				score += pmul * bottom_bonus

				# Mild center bias
				var center_distance: float = abs(col - GRID_SIZE.x / 2.0) + abs(row - GRID_SIZE.y / 2.0)
				score += pmul * max(0.0, 1.5 - center_distance * 0.4)

				# Lines
				var line_score := _evaluate_lines_from_position(board_arr, col, row, chip_player_id)
				if pmul == -1:
					line_score *= 1.4
				score += pmul * line_score

	# Reward having more columns you can still drop into
	var valid_count := 0
	for c in range(GRID_SIZE.x):
		if board_arr[c][0] == 0:
			valid_count += 1
	score += float(valid_count) * 5.0

	# Opponent 3-in-a-row threat penalty
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			if board_arr[col][row] == opponent_id:
				var opp_line_score := _evaluate_lines_from_position(board_arr, col, row, opponent_id)
				if opp_line_score >= 9.0:
					score -= 50.0

	return score


func _apply_rotation_to_array(board_arr: Array, rotation_state: Dictionary) -> Array:
	var direction: int = rotation_state.get("direction", 0)
	var degrees: int = rotation_state.get("degrees", 0)
	if degrees == 90:
		return _rotate_grid_right_90(board_arr) if direction == 1 else _rotate_grid_left_90(board_arr)
	elif degrees == 180:
		return _rotate_grid_180(board_arr)
	else:
		return board_arr.duplicate(true)


func _opponent_can_win_in_one(board_arr: Array, opponent_id: int) -> bool:
	for col in range(GRID_SIZE.x):
		if board_arr[col][0] != 0:
			continue
		var drop_row := _find_drop_row(board_arr, col)
		if drop_row == -1:
			continue
		board_arr[col][drop_row] = opponent_id
		var wins := _check_for_win_on(board_arr, col, drop_row)
		board_arr[col][drop_row] = 0
		if wins:
			return true
	return false


func _count_pieces_by_player(board_arr: Array) -> Dictionary:
	var counts: Dictionary = {}
	counts[1] = 0
	counts[2] = 0
	for c in range(GRID_SIZE.x):
		for r in range(GRID_SIZE.y):
			var v: int = board_arr[c][r]
			if v == 1 or v == 2:
				counts[v] = counts.get(v, 0) + 1
	return counts
