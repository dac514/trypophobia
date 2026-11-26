class_name BotSearch
extends RefCounted

## Rotation-aware game-tree search for the bot.
##
## A turn ("ply") is: drop a chip, apply its effect, rotate the board, apply gravity, then check
## for four in a row. Only the board after the rotation counts.
##
## Both players always see the next three rotations. After every turn one more rotation is
## revealed, so the player who moves next already knows a rotation that was unknown a turn
## earlier. The search models that exactly: after each ply a chance node reveals the next
## rotation (weighted by Globals.ROTATION_STATES) before the next player decides. Chance nodes
## are only expanded when the search is deep enough to reach the ply that uses that rotation,
## so searches up to three plies deep are plain minimax over the known rotations.
##
## Decision nodes use negamax with alpha-beta pruning and a transposition table; chance nodes
## take the exact weighted average of their outcomes. Iterative deepening keeps a finished
## answer ready at all times, so the search can stop on a wall-clock budget without ever
## returning a half-searched move. Results are deterministic unless noise is enabled.

enum Flag { EXACT, LOWER, UPPER }

## Score of a win; a win found sooner gets more (WIN_SCORE + remaining depth)
const WIN_SCORE: float = 1_000_000.0
## Static evaluations are clamped well below WIN_SCORE so they can never outweigh a real result
const HEURISTIC_LIMIT: float = 10_000.0
## Value of holding a bomb or pacman, so they're only spent when the search shows it pays off
const SPECIAL_CHIP_VALUE: float = 25.0
## How many search nodes between clock checks
const TIME_CHECK_INTERVAL: int = 256
## Cost of the next depth is estimated as this many times the last one
const DEPTH_GROWTH_ESTIMATE: float = 4.0
const PACMAN_DIRECTIONS: Array[String] = ["right", "down", "left"]

## Search settings
var max_depth: int = 6
## Wall-clock budget in milliseconds, 0 means unlimited. Depth 1 always completes.
var time_limit_ms: int = 0
## Random +/- noise added to root move scores (not to wins or losses). Makes Normal mode fallible.
var noise: float = 0.0
## Consider bombs and pacmans for the player to move at the root and below
var allow_specials: bool = true
var rng := RandomNumberGenerator.new()

## Statistics from the last call to choose()
var nodes: int = 0
var reached_depth: int = 0
var elapsed_ms: int = 0
var best_value: float = 0.0

var _tt: Dictionary = {}
var _best_moves: Dictionary = {}
var _chance_outcomes: Array[Dictionary] = []
var _column_order: Array[int] = []
var _start_ms: int = 0
var _aborted: bool = false
var _can_abort: bool = false


func _init() -> void:
	_chance_outcomes = rotation_outcomes()
	# Center columns first: good moves early make alpha-beta prune more
	for col in range(BotBoard.GRID_SIZE.x):
		_column_order.append(col)
	var center := (BotBoard.GRID_SIZE.x - 1) / 2.0
	_column_order.sort_custom(func(a: int, b: int) -> bool: return absf(a - center) < absf(b - center))


## Distinct board outcomes of a random rotation and their probabilities.
## Left and right 180 degree turns give the same board, so they are merged.
static func rotation_outcomes() -> Array[Dictionary]:
	var total := 0.0
	var merged: Dictionary = {}
	var order: Array[String] = []
	for state: Dictionary in Globals.ROTATION_STATES:
		total += float(state.weight)
		var code := rotation_code(state)
		if not merged.has(code):
			merged[code] = {"rotation": {"direction": state.direction, "degrees": state.degrees}, "p": 0.0}
			order.append(code)
		merged[code].p += float(state.weight)
	var outcomes: Array[Dictionary] = []
	for code in order:
		var outcome: Dictionary = merged[code]
		outcome.p = outcome.p / total
		outcomes.append(outcome)
	return outcomes


## Short code for a rotation; rotations giving the same board share a code. null = not known yet.
static func rotation_code(rotation: Variant) -> String:
	if not rotation is Dictionary:
		return "?"
	var degrees: int = (rotation as Dictionary).get("degrees", 0)
	var direction: int = (rotation as Dictionary).get("direction", 0)
	if degrees == 90:
		return "R" if direction == 1 else "L"
	if degrees == 180:
		return "H"
	return "N"


## Packs {player_id: {ChipType: count}} into [p1 bombs, p1 pacmans, p2 bombs, p2 pacmans]
static func pack_inventory(chip_inventory: Dictionary) -> PackedInt32Array:
	var packed := PackedInt32Array([0, 0, 0, 0])
	for player_id: int in [1, 2]:
		var player_inventory: Dictionary = chip_inventory.get(player_id, {})
		packed[_special_index(player_id, Globals.ChipType.BOMB)] = int(player_inventory.get(Globals.ChipType.BOMB, 0))
		packed[_special_index(player_id, Globals.ChipType.PACMAN)] = int(player_inventory.get(Globals.ChipType.PACMAN, 0))
	return packed


## Finds the best move for player_id. Returns null only when no column is open.
## known_rotations: the rotations shown to the players, next one first (normally three).
func choose(board: BotBoard, player_id: int, chip_inventory: Dictionary, known_rotations: Array) -> BotMove:
	_reset()
	var rotations := _normalize_rotations(known_rotations)
	var inventory := pack_inventory(chip_inventory)
	var best_move: BotMove = null
	var previous_best_id := ""

	for depth in range(1, max_depth + 1):
		var iteration_start := Time.get_ticks_msec()
		_can_abort = depth > 1 and time_limit_ms > 0
		var result := _search_root(board, player_id, rotations, depth, inventory, previous_best_id)
		if _aborted:
			break
		if result.move == null:
			break  # No legal move
		best_move = result.move
		best_value = result.value
		previous_best_id = _move_id(best_move)
		reached_depth = depth

		var proven_win: bool = best_value >= WIN_SCORE
		var undecided_moves: int = result.move_count - result.proven_losses
		if proven_win or result.move_count == 1 or undecided_moves <= 1:
			break
		if time_limit_ms > 0:
			var iteration_ms := Time.get_ticks_msec() - iteration_start
			var used_ms := Time.get_ticks_msec() - _start_ms
			if used_ms + iteration_ms * DEPTH_GROWTH_ESTIMATE > time_limit_ms:
				break

	elapsed_ms = Time.get_ticks_msec() - _start_ms
	return best_move


## Exact game value for player_id at a fixed depth (no time limit, no noise). Used by tests.
func value(board: BotBoard, player_id: int, chip_inventory: Dictionary, known_rotations: Array, depth: int) -> float:
	_reset()
	var result := _search_root(board, player_id, _normalize_rotations(known_rotations), depth, pack_inventory(chip_inventory), "")
	return result.value


## Every legal move for mover with the board right after its chip effect (before the rotation).
## Moves of the same chip type that produce the same board are merged.
func legal_moves(board: BotBoard, mover: int, inventory: PackedInt32Array, specials: bool) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var open_columns: Array[int] = []
	for col in _column_order:
		if board.is_column_open(col):
			open_columns.append(col)

	for col in open_columns:
		var move := BotMove.new(Globals.ChipType.EYE, col)
		moves.append({"move": move, "board": board.simulate_move(move, mover)})

	if not specials:
		return moves

	if inventory[_special_index(mover, Globals.ChipType.PACMAN)] > 0:
		var seen: Dictionary = {}
		for col in open_columns:
			for direction in PACMAN_DIRECTIONS:
				var move := BotMove.new(Globals.ChipType.PACMAN, col, direction)
				var after := board.simulate_move(move, mover)
				var key := after.cells
				if not seen.has(key):
					seen[key] = true
					moves.append({"move": move, "board": after})

	if inventory[_special_index(mover, Globals.ChipType.BOMB)] > 0:
		var seen: Dictionary = {}
		for col in open_columns:
			var move := BotMove.new(Globals.ChipType.BOMB, col)
			var after := board.simulate_move(move, mover)
			var key := after.cells
			if not seen.has(key):
				seen[key] = true
				moves.append({"move": move, "board": after})

	return moves


## Static evaluation of a position for the player to move
func evaluate_leaf(board: BotBoard, mover: int, rotations: Array, inventory: PackedInt32Array) -> float:
	var next_rotation: Variant = rotations[0] if rotations.size() > 0 else null
	var score := board.heuristic(mover, next_rotation)
	var opponent := 3 - mover
	var own_specials := inventory[_special_index(mover, Globals.ChipType.BOMB)] + inventory[_special_index(mover, Globals.ChipType.PACMAN)]
	var opp_specials := (
		inventory[_special_index(opponent, Globals.ChipType.BOMB)] + inventory[_special_index(opponent, Globals.ChipType.PACMAN)]
	)
	score += SPECIAL_CHIP_VALUE * (own_specials - opp_specials)
	return clampf(score, -HEURISTIC_LIMIT, HEURISTIC_LIMIT)


## Score of a finished game for the player who just moved, or null when the game goes on
static func terminal_score(outcome: BotBoard.Outcome, depth: int) -> Variant:
	match outcome:
		BotBoard.Outcome.MOVER_WINS:
			return WIN_SCORE + depth
		BotBoard.Outcome.OPPONENT_WINS:
			return -(WIN_SCORE + depth)
		BotBoard.Outcome.DRAW:
			return 0.0
	return null


## Inventory after mover spends chip_type
static func spend(inventory: PackedInt32Array, mover: int, chip_type: Globals.ChipType) -> PackedInt32Array:
	if chip_type == Globals.ChipType.EYE:
		return inventory
	var after := inventory.duplicate()
	var index := _special_index(mover, chip_type)
	after[index] = maxi(0, after[index] - 1)
	return after


## Whether the rotation revealed after a ply is used within the remaining search depth.
## child_known is how many known rotations the next player sees before the reveal.
static func reveal_needed(child_depth: int, child_known: int) -> bool:
	return child_depth >= child_known + 1


static func _special_index(player_id: int, chip_type: Globals.ChipType) -> int:
	return (player_id - 1) * 2 + (0 if chip_type == Globals.ChipType.BOMB else 1)


func _reset() -> void:
	_tt.clear()
	_best_moves.clear()
	_aborted = false
	_can_abort = false
	nodes = 0
	reached_depth = 0
	best_value = 0.0
	_start_ms = Time.get_ticks_msec()


## Only direction and degrees matter; anything missing is padded with "no rotation".
func _normalize_rotations(known_rotations: Array) -> Array:
	var rotations: Array = []
	for rotation: Variant in known_rotations:
		if rotation is Dictionary:
			var state: Dictionary = rotation
			rotations.append({"direction": int(state.get("direction", 0)), "degrees": int(state.get("degrees", 0))})
	if rotations.is_empty():
		rotations.append({"direction": 0, "degrees": 0})
	return rotations


func _search_root(board: BotBoard, mover: int, rotations: Array, depth: int, inventory: PackedInt32Array, first_id: String) -> Dictionary:
	var moves := legal_moves(board, mover, inventory, allow_specials)
	_order(moves, first_id)
	var result := {"move": null, "value": -INF, "move_count": moves.size(), "proven_losses": 0}
	var alpha := -INF
	for entry in moves:
		var move: BotMove = entry.move
		# With noise every root move needs an exact score, so don't narrow the window
		var window_alpha := -INF if noise > 0.0 else alpha
		var score := _resolve(entry.board as BotBoard, move, mover, rotations, depth, window_alpha, INF, inventory)
		if _aborted:
			return result
		if score <= -WIN_SCORE:
			result.proven_losses += 1
		if noise > 0.0 and absf(score) < WIN_SCORE:
			score += rng.randf_range(-noise, noise)
		if score > result.value:
			result.value = score
			result.move = move
		alpha = maxf(alpha, score)
	if result.move == null:
		result.value = 0.0
	return result


## Plays the move's rotation and scores the result for the player who made the move
func _resolve(
	after: BotBoard, move: BotMove, mover: int, rotations: Array, depth: int, alpha: float, beta: float, inventory: PackedInt32Array
) -> float:
	# Each generated board is resolved once, so it can be rotated in place
	var board := after
	board.simulate_rotation(rotations[0] as Dictionary, move)
	var final: Variant = terminal_score(board.outcome_for(mover), depth)
	if final != null:
		return final

	var child_inventory := spend(inventory, mover, move.chip_type)
	var remaining: Array = rotations.slice(1)
	var opponent := 3 - mover

	if reveal_needed(depth - 1, remaining.size()):
		# Chance node: the next rotation is revealed before the opponent decides
		var expected := 0.0
		for outcome in _chance_outcomes:
			var child_rotations: Array = remaining.duplicate()
			child_rotations.append(outcome.rotation)
			expected += float(outcome.p) * -_decision(board, opponent, child_rotations, depth - 1, -INF, INF, child_inventory)
			if _aborted:
				return 0.0
		return expected

	var placeholder: Array = remaining.duplicate()
	placeholder.append(null)  # Revealed too deep to matter
	return -_decision(board, opponent, placeholder, depth - 1, -beta, -alpha, child_inventory)


# gdlint:disable = max-returns


## Negamax node: the value of the position for mover, who is about to play
func _decision(board: BotBoard, mover: int, rotations: Array, depth: int, alpha: float, beta: float, inventory: PackedInt32Array) -> float:
	nodes += 1
	if _can_abort and nodes % TIME_CHECK_INTERVAL == 0 and Time.get_ticks_msec() - _start_ms > time_limit_ms:
		_aborted = true
	if _aborted:
		return 0.0
	if depth == 0:
		return evaluate_leaf(board, mover, rotations, inventory)

	var position_key := _position_key(board, mover, rotations, inventory)
	var key := position_key + "|" + str(depth)
	var original_alpha := alpha
	var entry: Variant = _tt.get(key)
	if entry != null:
		var stored: Array = entry
		var stored_value: float = stored[0]
		match stored[1]:
			Flag.EXACT:
				return stored_value
			Flag.LOWER:
				alpha = maxf(alpha, stored_value)
			Flag.UPPER:
				beta = minf(beta, stored_value)
		if alpha >= beta:
			return stored_value

	var moves := legal_moves(board, mover, inventory, allow_specials)
	if moves.is_empty():
		return 0.0  # Board is full: draw
	_order(moves, _best_moves.get(position_key, "") as String)

	var best := -INF
	var best_id := ""
	for move_entry in moves:
		var move: BotMove = move_entry.move
		var score := _resolve(move_entry.board as BotBoard, move, mover, rotations, depth, alpha, beta, inventory)
		if _aborted:
			return 0.0
		if score > best:
			best = score
			best_id = _move_id(move)
		alpha = maxf(alpha, score)
		if alpha >= beta:
			break

	var flag := Flag.EXACT
	if best <= original_alpha:
		flag = Flag.UPPER
	elif best >= beta:
		flag = Flag.LOWER
	_tt[key] = [best, flag]
	_best_moves[position_key] = best_id
	return best


# gdlint:enable = max-returns


func _position_key(board: BotBoard, mover: int, rotations: Array, inventory: PackedInt32Array) -> String:
	var codes := ""
	for rotation: Variant in rotations:
		codes += rotation_code(rotation)
	return "%s|%d|%s|%s" % [board.cells.hex_encode(), mover, codes, inventory.to_byte_array().hex_encode()]


static func _move_id(move: BotMove) -> String:
	if move == null:
		return ""
	return "%d:%d:%s" % [move.chip_type, move.column, move.direction if move.chip_type == Globals.ChipType.PACMAN else ""]


## Moves the move with the given id to the front, keeping the rest in order
static func _order(moves: Array[Dictionary], first_id: String) -> void:
	if first_id == "":
		return
	for i in range(moves.size()):
		if _move_id(moves[i].move as BotMove) == first_id:
			var entry: Dictionary = moves[i]
			moves.remove_at(i)
			moves.push_front(entry)
			return
