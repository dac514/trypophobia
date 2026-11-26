class_name BotWorker extends Thread

## Runs the bot's move choice on a separate thread and emits the move when done.
##
## Easy mode plays mostly random moves, taking immediate wins and (half the time) blocking
## immediate losses. Normal and Hard use BotSearch, the rotation-aware game-tree search, with
## a wall-clock budget so the bot never takes long to answer, even on slow devices: a slower
## device simply searches less deeply in the same time.

@warning_ignore("UNUSED_SIGNAL")
signal bot_worker_finished(best_move: BotMove)

## Hard: deep search with every chip type
const HARD_MAX_DEPTH = 6
const HARD_TIME_LIMIT_MS = 2500
## Normal: two plies, eyes only unless that loses, with a little noise so it can be beaten
const NORMAL_MAX_DEPTH = 2
const NORMAL_TIME_LIMIT_MS = 800
const NORMAL_NOISE = 15.0

var start_board: BotBoard
var player_id: int
var chip_inventory: Dictionary
var known_rotations: Array
var difficulty: Globals.Difficulty


## All arguments must be plain data (no nodes): they are read on the worker thread.
func _init(b: BotBoard, p: int, ci: Dictionary, rs: Array, d: Globals.Difficulty) -> void:
	start_board = b
	player_id = p
	chip_inventory = ci
	known_rotations = rs
	difficulty = d


func run() -> void:
	var move := choose_move()
	call_deferred("emit_signal", "bot_worker_finished", move)


## Picks a move synchronously. Returns null only when every column is full.
func choose_move() -> BotMove:
	var valid_moves := start_board.get_valid_drop_moves()
	if valid_moves.is_empty():
		print("Bot: No legal move, the board is full")
		return null

	if difficulty == Globals.Difficulty.EASY:
		return _easy_move(valid_moves)

	var search := BotSearch.new()
	if difficulty == Globals.Difficulty.NORMAL:
		search.max_depth = NORMAL_MAX_DEPTH
		search.time_limit_ms = NORMAL_TIME_LIMIT_MS
		search.noise = NORMAL_NOISE
		search.allow_specials = false
		search.rng.randomize()
		var move := search.choose(start_board, player_id, chip_inventory, known_rotations)
		if search.best_value > -BotSearch.WIN_SCORE:
			_log(search, "Normal")
			return move
		# Eyes alone lose: allow special chips in an emergency
		search.allow_specials = true
		move = search.choose(start_board, player_id, chip_inventory, known_rotations)
		_log(search, "Normal (emergency)")
		return move

	search.max_depth = HARD_MAX_DEPTH
	search.time_limit_ms = HARD_TIME_LIMIT_MS
	var best := search.choose(start_board, player_id, chip_inventory, known_rotations)
	_log(search, "Hard")
	return best


func _log(search: BotSearch, label: String) -> void:
	print(
		(
			"Bot (%s): depth %d, %d nodes, %d ms, score %.1f"
			% [label, search.reached_depth, search.nodes, search.elapsed_ms, search.best_value]
		)
	)


func _easy_move(valid_moves: Array[BotMove]) -> BotMove:
	var immediate_win: BotMove = _check_win(start_board, player_id, chip_inventory, known_rotations)
	if immediate_win != null:
		return immediate_win
	if randi() % 2 == 0:
		var immediate_block: BotMove = _check_block(start_board, player_id, chip_inventory, known_rotations)
		if immediate_block != null:
			return immediate_block
	var random_move: BotMove = valid_moves[randi() % valid_moves.size()]
	return BotMove.new(Globals.ChipType.EYE, random_move.column)


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
