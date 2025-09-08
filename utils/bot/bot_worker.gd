class_name BotWorker
extends Thread

signal bot_worker_finished(best_move: BotMove)

## Maximum search depth for minimax algorithm
const MAX_DEPTH = 5
## Large value for minimax initialization
const INF = 1e9
## Maximum thinking time in seconds
const MAX_THINKING_TIME = 5.0

var grid_state: Array
var player_id: int
var chip_inventory: Dictionary
var next_rotation_states: Array
var start_time: int

func _init(gs: Array, p: int, ci: Dictionary, nrs: Array) -> void:
	grid_state = gs
	player_id = p
	chip_inventory = ci
	next_rotation_states = nrs


# Run the minimax search (CPU heavy, use a thread)
func run() -> void:
	print("Bot: Finding best move for player %d" % player_id)
	print("Bot: Available chips - Eyes: %d, Bombs: %d, Pacmans: %d" % [
		chip_inventory[player_id][Globals.ChipType.EYE],
		chip_inventory[player_id][Globals.ChipType.BOMB],
		chip_inventory[player_id][Globals.ChipType.PACMAN]
	])

	var best_move: BotMove
	var best_score: float = -INF
	var chip_types: Array = [Globals.ChipType.EYE, Globals.ChipType.BOMB, Globals.ChipType.PACMAN]
	var board := BotBoard.new(grid_state)
	var valid_moves: Array = board.get_valid_moves()

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

	# Checks for immediate winning moves or necessary blocks before minimax search
	var immediate_move: BotMove = _check_win(board, player_id, chip_inventory, next_rotation_states)
	if immediate_move != null:
		call_deferred("emit_signal", "bot_worker_finished", immediate_move)
		return
	immediate_move = _check_block(board, player_id, chip_inventory, next_rotation_states)
	if immediate_move != null:
		call_deferred("emit_signal", "bot_worker_finished", immediate_move)
		return

	start_time = Time.get_ticks_msec()
	var dynamic_depth := MAX_DEPTH
	for chip_type: int in chip_types:
		var player_inventory: Dictionary = chip_inventory.get(player_id, {}) as Dictionary
		var available_count: int = player_inventory.get(chip_type, 0) as int
		if available_count > 0:
			for base_move: BotMove in valid_moves:
				var score: float
				var best_dir_idx: int = 0
				if [Globals.ChipType.PACMAN].has(chip_type):
					# Chip with special power
					var best_dir_score: float = -INF
					var directions: Array = ["right", "down", "left"]
					for dir_idx: int in range(directions.size()):
						var direction: String = directions[dir_idx]
						var move := BotMove.new(chip_type, base_move.column, direction)
						var temp_board: BotBoard = board.simulate_move_and_rotation(move, player_id, next_rotation_states)
						var score_dir: float = _minimax(temp_board, dynamic_depth , -INF, INF, false, player_id, chip_inventory, next_rotation_states)
						if score_dir > best_dir_score:
							best_dir_score = score_dir
							best_dir_idx = dir_idx
					score = best_dir_score
				else:
					# Regular chip
					var move := BotMove.new(chip_type, base_move.column)
					var temp_board: BotBoard = board.simulate_move_and_rotation(move, player_id, next_rotation_states)
					score = _minimax(temp_board, dynamic_depth, -INF, INF, false, player_id, chip_inventory, next_rotation_states)

				if score > best_score:
					best_score = score
					if chip_type == Globals.ChipType.PACMAN:
						var directions: Array = ["right", "down", "left"]
						best_move = BotMove.new(chip_type, base_move.column, directions[best_dir_idx])
					else:
						best_move = BotMove.new(chip_type, base_move.column)

	call_deferred("emit_signal", "bot_worker_finished", best_move)


##  Check if we can win immediately
func _check_win(board: BotBoard, current_player_id: int, current_chip_inventory: Dictionary, rotation_states: Array) -> BotMove:
	var player_inventory: Dictionary = current_chip_inventory.get(current_player_id, {}) as Dictionary
	for chip_type: int in [Globals.ChipType.EYE]:
		var available_count: int = player_inventory.get(chip_type, 0) as int
		if available_count > 0:
			for base_move: BotMove in board.get_valid_moves():
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
	var opponent_can_win_found := false
	var safe_move: BotMove = null
	var rotation_states_1 := [rotation_states[0]]
	var rotation_states_2 := [rotation_states[1]]
	var board_valid_moves := board.get_valid_moves()

	for base_move: BotMove in board_valid_moves:
		# Try a move with EYE
		var move := BotMove.new(Globals.ChipType.EYE, base_move.column)
		var temp_board: BotBoard = board.simulate_move_and_rotation(move, current_player_id, rotation_states_1)
		# Check all opponent's possible next moves to see if they can win
		var opp_valid_moves: Array = temp_board.get_valid_moves()
		var opp_temp_board: BotBoard;
		var opponent_can_win := false
		for opp_base_move: BotMove in opp_valid_moves:
			var opp_move := BotMove.new(Globals.ChipType.EYE, opp_base_move.column)
			opp_temp_board = temp_board.simulate_move_and_rotation(opp_move, opponent_id, rotation_states_2)
			if opp_temp_board.has_winning_line(opponent_id):
				print("Opponent has winning line")
				opp_temp_board.print_ascii_grid()
				opponent_can_win = true
				opponent_can_win_found = true
				break
		if not opponent_can_win:
			# Track a safe move, but only return it if opponent_can_win_found is true after loop
			safe_move = move

	# If at least one move allows opponent to win, and we found a safe move, play it
	if opponent_can_win_found and safe_move != null:
		print("Bot: Found safe move: Column %d, Chip Type: %d" % [safe_move.column, safe_move.chip_type])
		return safe_move

	if opponent_can_win_found:
		# No safe move found, try special chips
		var blocking_chip_types := [Globals.ChipType.PACMAN, Globals.ChipType.BOMB]
		for base_move: BotMove in board_valid_moves:
			for chip_type: int in blocking_chip_types:
				var available_count: int = player_inventory.get(chip_type, 0)
				if available_count > 0:
					var our_block: BotMove
					if chip_type == Globals.ChipType.PACMAN:
						var directions: Array = ["right", "down", "left"]
						for direction: String in directions:
							our_block = BotMove.new(chip_type, base_move.column, direction)
							var blocking_board := board.simulate_move_and_rotation(our_block, current_player_id, rotation_states_1)
							var still_can_win: bool = false
							var valid_moves_after_block := blocking_board.get_valid_moves()
							for opp_base_move: BotMove in valid_moves_after_block:
								var opp_move := BotMove.new(Globals.ChipType.EYE, opp_base_move.column)
								var opp_temp_board := blocking_board.simulate_move_and_rotation(opp_move, opponent_id, rotation_states_2)
								if opp_temp_board.has_winning_line(opponent_id):
									still_can_win = true
									break
							if not still_can_win:
								print("Bot: Found blocking move with Pacman: Column %d, Direction: %s" % [our_block.column, our_block.direction])
								return our_block
					else:
						our_block = BotMove.new(chip_type, base_move.column)
						var blocking_board := board.simulate_move_and_rotation(our_block, current_player_id, rotation_states_1)
						var still_can_win: bool = false
						var valid_moves_after_block := blocking_board.get_valid_moves()
						for opp_base_move: BotMove in valid_moves_after_block:
							var opp_move := BotMove.new(Globals.ChipType.EYE, opp_base_move.column)
							var opp_temp_board := blocking_board.simulate_move_and_rotation(opp_move, opponent_id, rotation_states_2)
							if opp_temp_board.has_winning_line(opponent_id):
								still_can_win = true
								break
						if not still_can_win:
							print("Bot: Found blocking move: Column %d, Chip Type: %d" % [our_block.column, our_block.chip_type])
							return our_block

	if opponent_can_win_found:
		print("Failed to block opponent")

	return null

## Minimax algorithm with alpha-beta pruning for optimal move evaluation
func _minimax(board: BotBoard, depth: int, alpha: float, beta: float, maximizing: bool, current_player_id: int, current_chip_inventory: Dictionary, rotation_states: Array) -> float:
	# Stop recursion if we reach the depth limit, game is over, or no more known rotations
	if depth == 0 or board.is_game_over():
		return board.evaluate_position(current_player_id)

	# Check if thinking time has exceeded
	if Time.get_ticks_msec() - start_time > MAX_THINKING_TIME * 1000:
		print("Bot: Thinking time exceeded, cutting off search")
		return board.evaluate_position(current_player_id)

	# If we've used all known rotation states, use a simpler evaluation with reduced depth
	if rotation_states.size() == 0:
		if depth > 1:
			# Reduce depth for unknown rotations to avoid excessive computation
			return _minimax(board, 1, alpha, beta, maximizing, current_player_id, current_chip_inventory, [])
		else:
			return board.evaluate_position(current_player_id)

	var valid_moves: Array = board.get_valid_moves()
	var chip_types: Array = [Globals.ChipType.EYE, Globals.ChipType.BOMB, Globals.ChipType.PACMAN]

	# Only limit moves if there are too many (board-size relative)
	var max_moves: int = max(3, board.GRID_SIZE.x)  # At least 3, or number of columns
	if valid_moves.size() > max_moves:
		valid_moves = valid_moves.slice(0, max_moves)

	# Get the next rotation state and prepare rotation states for next recursion level
	var current_rotation: Dictionary = rotation_states[0]
	var next_rotations: Array = rotation_states.slice(1)

	if maximizing:
		# Maximizing
		var max_eval: float = -INF
		for chip_type: int in chip_types:
			var player_inventory: Dictionary = current_chip_inventory.get(current_player_id, {}) as Dictionary
			var available_count: int = player_inventory.get(chip_type, 0) as int
			if available_count > 0:
				for base_move: BotMove in valid_moves:
					var eval: float
					if [Globals.ChipType.PACMAN].has(chip_type):
						# Chip with special power
						var best_dir_score: float = -INF
						var directions: Array = ["right", "down", "left"]
						for direction: String in directions:
							var move := BotMove.new(chip_type, base_move.column, direction)
							# Use only the current rotation state for this move
							var temp_rotation_states: Array = [current_rotation]
							var temp_board: BotBoard = board.simulate_move_and_rotation(move, current_player_id, temp_rotation_states)
							var new_inventory: Dictionary = _simulate_inventory(current_chip_inventory, current_player_id, chip_type)
							# Pass the next rotations for deeper recursion
							var eval_dir: float = _minimax(temp_board, depth - 1, alpha, beta, false, current_player_id, new_inventory, next_rotations)
							if eval_dir > best_dir_score:
								best_dir_score = eval_dir
						eval = best_dir_score
					else:
						# Regular chip
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
						break
		return max_eval
	else:
		# Minimizing
		var min_eval: float = INF
		var opponent_id: int = 3 - current_player_id
		for chip_type: int in chip_types:
			var opponent_inventory: Dictionary = current_chip_inventory.get(opponent_id, {}) as Dictionary
			var available_count: int = opponent_inventory.get(chip_type, 0) as int
			if available_count > 0:
				for base_move: BotMove in valid_moves:
					var eval: float
					if [Globals.ChipType.PACMAN].has(chip_type):
						# Chip with special power
						var best_dir_score: float = INF
						var directions: Array = ["right", "down", "left"]
						for direction: String in directions:
							var move := BotMove.new(chip_type, base_move.column, direction)
							# Use only the current rotation state for this move
							var temp_rotation_states: Array = [current_rotation]
							var temp_board: BotBoard = board.simulate_move_and_rotation(move, opponent_id, temp_rotation_states)
							var new_inventory: Dictionary = _simulate_inventory(current_chip_inventory, opponent_id, chip_type)
							# Pass the next rotations for deeper recursion
							var eval_dir: float = _minimax(temp_board, depth - 1, alpha, beta, true, current_player_id, new_inventory, next_rotations)
							if eval_dir < best_dir_score:
								best_dir_score = eval_dir
						eval = best_dir_score
					else:
						# Regular chip
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
						break
		return min_eval


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
