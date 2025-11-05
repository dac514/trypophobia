class_name BotWorker extends Thread

## The BotWorker class uses the minimax algorithm with alpha-beta pruning to calculate the optimal
## move for the AI player.
##
## It evaluates moves based on the current board state, chip inventory, and upcoming rotations,
## with support for special chips like BOMB and PACMAN. The class runs in a thread asynchronously,
## leveraging a transposition table for caching, and emits the best move once the computation is
## complete.

@warning_ignore("UNUSED_SIGNAL")
signal bot_worker_finished(best_move: BotMove)

## Maximum search depth for minimax algorithm
const MAX_DEPTH = 8
## Maximum thinking time in seconds
const MAX_THINKING_TIME = 5.0

var chip_inventory: Dictionary
var grid_state: Array
var next_rotation_states: Array
var is_bot_dumb: bool = false
var player_id: int
var start_time: int
var transposition_table: Dictionary = {}


func _init(gs: Array, p: int, ci: Dictionary, nrs: Array, isb: bool) -> void:
	grid_state = gs
	player_id = p
	chip_inventory = ci
	next_rotation_states = nrs
	is_bot_dumb = isb


# Run the minimax search (CPU heavy, use a thread)
func run() -> void:
	print("Bot: Finding best move for player %d" % player_id)
	print(
		(
			"Bot: Available chips - Eyes: %d, Bombs: %d, Pacmans: %d"
			% [
				chip_inventory[player_id][Globals.ChipType.EYE],
				chip_inventory[player_id][Globals.ChipType.BOMB],
				chip_inventory[player_id][Globals.ChipType.PACMAN]
			]
		)
	)

	var best_move: BotMove
	var best_score: float = -INF
	var chip_types: Array = [Globals.ChipType.EYE, Globals.ChipType.BOMB, Globals.ChipType.PACMAN]
	var board := BotBoard.new()
	board.setup(grid_state)

	# Default to left column on empty board
	if board.chip_count == 0:
		best_move = BotMove.new(Globals.ChipType.EYE, 0)
		call_deferred("emit_signal", "bot_worker_finished", best_move)
		return

	# Don't use bomb or pacman on first moves - save special chips for later
	if board.chip_count < 6:
		chip_types = [Globals.ChipType.EYE]
	elif board.chip_count < 10:
		chip_types = [Globals.ChipType.EYE, Globals.ChipType.PACMAN]

	# Checks for immediate winning moves
	var should_check_win: bool = not is_bot_dumb
	if should_check_win:
		var immediate_win: BotMove = _check_win(board, player_id, chip_inventory, next_rotation_states)
		if immediate_win != null:
			call_deferred("emit_signal", "bot_worker_finished", immediate_win)
			return

	# Check for blocking moves
	# Hard bot always checks, dumb bot has 1/2 chance
	var should_check_block: bool = not is_bot_dumb or (randi() % 2 == 0)
	if should_check_block:
		var immediate_block: BotMove = _check_block(board, player_id, chip_inventory, next_rotation_states)
		if immediate_block != null:
			call_deferred("emit_signal", "bot_worker_finished", immediate_block)
			return

	var valid_moves: Array = board.get_valid_drop_moves()

	# Easy mode, select random move
	if is_bot_dumb:
		print("Easy mode, random move")
		var random_move: BotMove = valid_moves[randi() % valid_moves.size()]
		best_move = BotMove.new(Globals.ChipType.EYE, random_move.column)
		call_deferred("emit_signal", "bot_worker_finished", best_move)
		return

	# Hard mode, minimax search
	start_time = Time.get_ticks_msec()
	var dynamic_depth := MAX_DEPTH
	var directions: Array = ["right", "down", "left"]
	for chip_type: int in chip_types:
		var player_inventory: Dictionary = chip_inventory.get(player_id, {}) as Dictionary
		var available_count: int = player_inventory.get(chip_type, 0) as int
		if available_count > 0:
			for base_move: BotMove in valid_moves:
				var score: float
				var best_dir_idx: int = 0
				if [Globals.ChipType.PACMAN].has(chip_type):
					# Simulate moves for every useful direction
					var best_dir_score: float = -INF
					for dir_idx: int in range(directions.size()):
						var direction: String = directions[dir_idx]
						var move := BotMove.new(chip_type, base_move.column, direction)
						var temp_board: BotBoard = board.simulate_move_and_rotation(move, player_id, next_rotation_states)
						var score_dir: float = _minimax(
							temp_board, dynamic_depth, -INF, INF, false, player_id, chip_inventory, next_rotation_states
						)
						if score_dir > best_dir_score:
							best_dir_score = score_dir
							best_dir_idx = dir_idx
					score = best_dir_score
				else:
					# Similuate move
					var move := BotMove.new(chip_type, base_move.column)
					var temp_board: BotBoard = board.simulate_move_and_rotation(move, player_id, next_rotation_states)
					score = _minimax(temp_board, dynamic_depth, -INF, INF, false, player_id, chip_inventory, next_rotation_states)

				# Prioritize EYE when scores are equal (>= for EYE, > for special chips)
				var should_update: bool = false
				if chip_type == Globals.ChipType.EYE:
					should_update = score >= best_score  # EYE wins ties
				else:
					should_update = score > best_score  # Special chips need higher score

				if should_update:
					best_score = score
					if chip_type == Globals.ChipType.PACMAN:
						best_move = BotMove.new(chip_type, base_move.column, directions[best_dir_idx])
					else:
						best_move = BotMove.new(chip_type, base_move.column)

	print("Hard mode, minimax best score: " + str(best_score))

	call_deferred("emit_signal", "bot_worker_finished", best_move)


##  Check if we can win immediately
func _check_win(board: BotBoard, current_player_id: int, current_chip_inventory: Dictionary, rotation_states: Array) -> BotMove:
	var player_inventory: Dictionary = current_chip_inventory.get(current_player_id, {}) as Dictionary
	for chip_type: int in [Globals.ChipType.EYE]:
		var available_count: int = player_inventory.get(chip_type, 0) as int
		if available_count > 0:
			for base_move: BotMove in board.get_valid_drop_moves():
				var move := BotMove.new(chip_type, base_move.column)
				var temp_board: BotBoard = board.simulate_move_and_rotation(move, current_player_id, rotation_states)
				if temp_board.has_winning_line(current_player_id):
					print("Bot: Found winning move: Column %d, Chip Type: %d" % [move.column, move.chip_type])
					return move
	return null


## Check if we need to block opponent's win
func _check_block(board: BotBoard, current_player_id: int, current_chip_inventory: Dictionary, rotation_states: Array) -> BotMove:
	var player_inventory: Dictionary = current_chip_inventory.get(current_player_id, {}) as Dictionary
	var opponent_id: int = 3 - current_player_id
	var rotation_states_1 := [rotation_states[0]]
	var rotation_states_2 := [rotation_states[1]]
	var board_valid_moves := board.get_valid_drop_moves()
	var safe_moves: Array[BotMove] = []
	var opponent_can_win_somewhere := false

	# First pass: evaluate ALL possible moves to categorize them
	for base_move: BotMove in board_valid_moves:
		var move := BotMove.new(Globals.ChipType.EYE, base_move.column)
		var temp_board: BotBoard = board.simulate_move_and_rotation(move, current_player_id, rotation_states_1)

		# Check if opponent can win after this move
		var opponent_can_win_after_this_move := false
		var opp_valid_moves: Array = temp_board.get_valid_drop_moves()

		for opp_base_move: BotMove in opp_valid_moves:
			var opp_move := BotMove.new(Globals.ChipType.EYE, opp_base_move.column)
			var opp_temp_board: BotBoard = temp_board.simulate_move_and_rotation(opp_move, opponent_id, rotation_states_2)
			if opp_temp_board.has_winning_line(opponent_id):
				print("Opponent has winning line after move column %d" % move.column)
				# opp_temp_board.print_ascii_grid()
				opponent_can_win_after_this_move = true
				opponent_can_win_somewhere = true
				break

		# If opponent can't win after this move, it's safe
		if not opponent_can_win_after_this_move:
			safe_moves.append(move)

	# If opponent can win somewhere but we have safe moves, pick the first safe move
	if opponent_can_win_somewhere and safe_moves.size() > 0:
		var safe_move: BotMove = safe_moves[randi() % safe_moves.size()]
		print("Bot: Found safe move: Column %d, Chip Type: %d" % [safe_move.column, safe_move.chip_type])
		return safe_move

	# If no safe moves with regular chips, try special chips
	if opponent_can_win_somewhere:
		var blocking_chip_types := [Globals.ChipType.PACMAN, Globals.ChipType.BOMB]
		var bomb_candidates: Array = []
		for base_move: BotMove in board_valid_moves:
			for chip_type: int in blocking_chip_types:
				var available_count: int = player_inventory.get(chip_type, 0)
				if available_count > 0:
					var blocking_moves: Array = []

					if chip_type == Globals.ChipType.PACMAN:
						var directions: Array = ["right", "down", "left"]
						for direction: String in directions:
							blocking_moves.append(BotMove.new(chip_type, base_move.column, direction))
					else:
						blocking_moves.append(BotMove.new(chip_type, base_move.column))

					# Test each potential blocking move
					for blocking_move: BotMove in blocking_moves:
						var blocking_board := board.simulate_move_and_rotation(blocking_move, current_player_id, rotation_states_1)
						var still_can_win := false
						var valid_moves_after_block := blocking_board.get_valid_drop_moves()

						for opp_base_move: BotMove in valid_moves_after_block:
							var opp_move := BotMove.new(Globals.ChipType.EYE, opp_base_move.column)
							var opp_temp_board := blocking_board.simulate_move_and_rotation(opp_move, opponent_id, rotation_states_2)
							if opp_temp_board.has_winning_line(opponent_id):
								still_can_win = true
								break

						if not still_can_win:
							if chip_type == Globals.ChipType.PACMAN:
								print(
									(
										"Bot: Found blocking move with Pacman: Column %d, Direction: %s"
										% [blocking_move.column, blocking_move.direction]
									)
								)
								return blocking_move

							# Collect bomb candidate to choose the least self-destructive later
							var meta := blocking_board.last_action_meta
							var self_d: int = int(meta.get("destroyed_self", 0))
							var opp_d: int = int(meta.get("destroyed_opp", 0))
							var center_col: int = int(float(board.GRID_SIZE.x) / 2.0)
							var tie: int = abs(blocking_move.column - center_col)
							(
								bomb_candidates
								. append(
									{
										"move": blocking_move,
										"self_d": self_d,
										"opp_d": opp_d,
										"tie": tie,
									}
								)
							)

		# If any bomb candidates were collected, choose the least self-destructive one
		if bomb_candidates.size() > 0:
			print("Bot: Bomb block candidates considered: %d" % bomb_candidates.size())
			var best_move: BotMove = null
			var best_self_d: int = 1_000_000
			var best_opp_d: int = -1
			var best_tie: int = 1_000_000
			for cand: Dictionary in bomb_candidates:
				var cdict: Dictionary = cand
				var self_d: int = int(cdict.get("self_d", 0))
				var opp_d: int = int(cdict.get("opp_d", 0))
				var tie: int = int(cdict.get("tie", 0))
				if self_d < best_self_d or (self_d == best_self_d and (opp_d > best_opp_d or (opp_d == best_opp_d and tie < best_tie))):
					best_self_d = self_d
					best_opp_d = opp_d
					best_tie = tie
					best_move = cdict.get("move")
			if best_move != null:
				print("Bot: Optimized bomb block: Column %d (self -%d, opp -%d)" % [best_move.column, best_self_d, best_opp_d])
				return best_move

		print("Failed to block opponent - no safe moves found")

		# Least-bad blocker fallback: choose the move that minimizes opponent immediate wins
		var best_block_move: BotMove = null
		var best_block_score: int = 1_000_000
		for base_move: BotMove in board_valid_moves:
			var move := BotMove.new(Globals.ChipType.EYE, base_move.column)
			var temp_board: BotBoard = board.simulate_move_and_rotation(move, current_player_id, rotation_states_1)
			var opp_valid_moves: Array = temp_board.get_valid_drop_moves()
			var opp_win_count := 0
			for opp_base_move: BotMove in opp_valid_moves:
				var opp_move := BotMove.new(Globals.ChipType.EYE, opp_base_move.column)
				var opp_temp_board: BotBoard = temp_board.simulate_move_and_rotation(opp_move, opponent_id, rotation_states_2)
				if opp_temp_board.has_winning_line(opponent_id):
					opp_win_count += 1
			# Prefer fewer opponent wins; tie-break toward center columns
			var center_col: int = int(float(board.GRID_SIZE.x) / 2.0)
			var tie_break: int = abs(base_move.column - center_col)
			var composite: int = opp_win_count * 10 + tie_break
			if composite < best_block_score:
				best_block_score = composite
				best_block_move = move

		if best_block_move != null:
			print("Selecting least-bad rotation blocker: Column %d" % best_block_move.column)
			return best_block_move

	return null


# gdlint:disable = max-returns, no-else-return


## Minimax algorithm with alpha-beta pruning for optimal move evaluation
func _minimax(
	board: BotBoard,
	depth: int,
	alpha: float,
	beta: float,
	maximizing: bool,
	current_player_id: int,
	current_chip_inventory: Dictionary,
	rotation_states: Array
) -> float:
	# Create a unique key for this board state
	var hash_key := _hash_board_state(board, depth, maximizing, current_player_id, current_chip_inventory, rotation_states)

	# Check if we've already evaluated this position
	if transposition_table.has(hash_key):
		return transposition_table[hash_key]

	# Stop recursion if we reach the depth limit, game is over, or no more known rotations
	if depth == 0 or board.is_game_over():
		var eval := board.evaluate_position(current_player_id, rotation_states)
		transposition_table[hash_key] = eval
		return eval

	# Check if thinking time has exceeded
	var elapsed_time_ms := Time.get_ticks_msec() - start_time
	if elapsed_time_ms > MAX_THINKING_TIME * 1000:
		print("Bot: Thinking time exceeded, cutting off search")
		return board.evaluate_position(current_player_id, rotation_states)

	# Check if we're running out of time (90% of max time used)
	var is_time_pressured := elapsed_time_ms > (MAX_THINKING_TIME * 0.9) * 1000

	# If we've used all known rotation states, use a simpler evaluation with reduced depth
	if rotation_states.size() == 0:
		if depth > 1:
			# Reduce depth for unknown rotations to avoid excessive computation
			return _minimax(board, 1, alpha, beta, maximizing, current_player_id, current_chip_inventory, [])
		else:
			var eval := board.evaluate_position(current_player_id, rotation_states)
			transposition_table[hash_key] = eval
			return eval

	var valid_moves: Array = board.get_valid_drop_moves()
	var chip_types: Array = [Globals.ChipType.EYE, Globals.ChipType.BOMB, Globals.ChipType.PACMAN]

	# Only limit moves if there are too many (board-size relative)
	var max_moves: int = max(3, board.GRID_SIZE.x)
	var evaluated_all_moves: bool = valid_moves.size() <= max_moves
	if valid_moves.size() > max_moves:
		valid_moves = valid_moves.slice(0, max_moves)

	# Get the next rotation state and prepare rotation states for next recursion level
	var current_rotation: Dictionary = rotation_states[0]
	var next_rotations: Array = rotation_states.slice(1)

	if maximizing:
		# Maximizing
		var max_eval: float = -INF
		var search_was_cutoff: bool = false
		for chip_type: int in chip_types:
			var player_inventory: Dictionary = current_chip_inventory.get(current_player_id, {}) as Dictionary
			var available_count: int = player_inventory.get(chip_type, 0) as int
			if available_count > 0:
				for base_move: BotMove in valid_moves:
					var eval: float
					if [Globals.ChipType.PACMAN].has(chip_type):
						# Simulate moves for every useful direction
						var best_dir_score: float = -INF
						var directions: Array = ["right", "down", "left"]
						for direction: String in directions:
							var move := BotMove.new(chip_type, base_move.column, direction)
							# Use only the current rotation state for this move
							var temp_rotation_states: Array = [current_rotation]
							var temp_board: BotBoard = board.simulate_move_and_rotation(move, current_player_id, temp_rotation_states)
							var new_inventory: Dictionary = _simulate_inventory(current_chip_inventory, current_player_id, chip_type)
							# Pass the next rotations for deeper recursion
							var eval_dir: float = _minimax(
								temp_board, depth - 1, alpha, beta, false, current_player_id, new_inventory, next_rotations
							)
							if eval_dir > best_dir_score:
								best_dir_score = eval_dir
						eval = best_dir_score
					else:
						# Simulate move
						var move := BotMove.new(chip_type, base_move.column)
						# Use only the current rotation state for this move
						var temp_rotation_states: Array = [current_rotation]
						var temp_board: BotBoard = board.simulate_move_and_rotation(move, current_player_id, temp_rotation_states)
						var new_inventory: Dictionary = _simulate_inventory(current_chip_inventory, current_player_id, chip_type)
						# Pass the next rotations for deeper recursion
						eval = _minimax(temp_board, depth - 1, alpha, beta, false, current_player_id, new_inventory, next_rotations)
					max_eval = max(max_eval, eval)
					alpha = max(alpha, eval)
					if beta <= alpha:
						search_was_cutoff = true
						break
				if search_was_cutoff:
					break
		# Only cache if we evaluated all moves, search wasn't cut off, and we're not time-pressured
		if evaluated_all_moves and not search_was_cutoff and not is_time_pressured:
			transposition_table[hash_key] = max_eval
		return max_eval

	else:
		# Minimizing
		var min_eval: float = INF
		var opponent_id: int = 3 - current_player_id
		var search_was_cutoff: bool = false
		for chip_type: int in chip_types:
			var opponent_inventory: Dictionary = current_chip_inventory.get(opponent_id, {}) as Dictionary
			var available_count: int = opponent_inventory.get(chip_type, 0) as int
			if available_count > 0:
				for base_move: BotMove in valid_moves:
					var eval: float
					if [Globals.ChipType.PACMAN].has(chip_type):
						# Simulate moves for every useful direction
						var best_dir_score: float = INF
						var directions: Array = ["right", "down", "left"]
						for direction: String in directions:
							var move := BotMove.new(chip_type, base_move.column, direction)
							# Use only the current rotation state for this move
							var temp_rotation_states: Array = [current_rotation]
							var temp_board: BotBoard = board.simulate_move_and_rotation(move, opponent_id, temp_rotation_states)
							var new_inventory: Dictionary = _simulate_inventory(current_chip_inventory, opponent_id, chip_type)
							# Pass the next rotations for deeper recursion
							var eval_dir: float = _minimax(
								temp_board, depth - 1, alpha, beta, true, current_player_id, new_inventory, next_rotations
							)
							if eval_dir < best_dir_score:
								best_dir_score = eval_dir
						eval = best_dir_score
					else:
						# Simulate move
						var move := BotMove.new(chip_type, base_move.column)
						# Use only the current rotation state for this move
						var temp_rotation_states: Array = [current_rotation]
						var temp_board: BotBoard = board.simulate_move_and_rotation(move, opponent_id, temp_rotation_states)
						var new_inventory: Dictionary = _simulate_inventory(current_chip_inventory, opponent_id, chip_type)
						# Pass the next rotations for deeper recursion
						eval = _minimax(temp_board, depth - 1, alpha, beta, true, current_player_id, new_inventory, next_rotations)
					min_eval = min(min_eval, eval)
					beta = min(beta, eval)
					if beta <= alpha:
						search_was_cutoff = true
						break
				if search_was_cutoff:
					break
		# Only cache if we evaluated all moves, search wasn't cut off, and we're not time-pressured
		if evaluated_all_moves and not search_was_cutoff and not is_time_pressured:
			transposition_table[hash_key] = min_eval
		return min_eval


# gdlint:enable = max-returns, no-else-return


## Simulates inventory changes after a chip is used
func _simulate_inventory(inventory: Dictionary, target_player_id: int, chip_type: int) -> Dictionary:
	var new_inventory: Dictionary = {}
	for player_key: Variant in inventory:
		var player_dict: Dictionary = inventory[player_key] as Dictionary
		new_inventory[player_key] = player_dict.duplicate()

	if new_inventory.has(target_player_id):
		var player_inventory: Dictionary = new_inventory[target_player_id] as Dictionary
		if player_inventory.has(chip_type):
			player_inventory[chip_type] = max(0, player_inventory[chip_type] - 1)

	return new_inventory


## Generate hash key for board state
func _hash_board_state(
	board: BotBoard, depth: int, maximizing: bool, current_player_id: int, current_chip_inventory: Dictionary, rotation_states: Array
) -> int:
	var hash_value: int = 0
	var multiplier: int = 31

	# Board state - only hash occupied cells
	for col_idx: int in board.current_board_permutation.size():
		var col: Array = board.current_board_permutation[col_idx]
		for row_idx: int in col.size():
			var cell: int = col[row_idx]
			if cell != 0:  # Skip empty cells
				hash_value = hash_value * multiplier + (cell * 100 + col_idx * 10 + row_idx)

	# Pack core state into integers
	hash_value = hash_value * multiplier + depth
	hash_value = hash_value * multiplier + (1 if maximizing else 0)
	hash_value = hash_value * multiplier + current_player_id

	# Include ALL rotation states since there are only 3 total
	for i: int in rotation_states.size():
		var state: Dictionary = rotation_states[i]
		var dir_val: int = state.get("direction", 0) as int
		var deg_val: int = state.get("degrees", 0) / 90  # Normalize to 0-3
		hash_value = hash_value * multiplier + (dir_val * 4 + deg_val)

	# Only special chips affect strategy significantly
	for player_id_val: int in [1, 2]:
		if current_chip_inventory.has(player_id_val):
			var inventory: Dictionary = current_chip_inventory[player_id_val]
			var bombs: int = inventory.get(Globals.ChipType.BOMB, 0) as int
			var pacmans: int = inventory.get(Globals.ChipType.PACMAN, 0) as int
			hash_value = hash_value * multiplier + (bombs * 10 + pacmans)

	return hash_value
