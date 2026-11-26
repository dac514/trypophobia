extends GutTest

## Shared helpers for the BotSearch tests (test_bot_search.gd, test_bot_puzzles.gd).
## Not a test file itself: GUT only runs files named test_*.
##
## "Optimal" here means optimal in the BotBoard model, up to the search depth. The brute-force
## reference below is a plain full-width expectiminimax over the same rules, with no pruning, no
## transposition table, no move de-duplication and no ordering. It shares only the BotBoard
## rules, the leaf evaluation and the terminal scores with BotSearch, so equal results show the
## search's optimisations never change the answer.
##
## Grid: [column][row], row 0 is the top. 0 = empty, 1 and 2 are players.

const SIZE: Vector2i = BotBoard.GRID_SIZE
const BOTTOM: int = SIZE.y - 1
const P1 := 1
const P2 := 2
const EPSILON := 1e-6

const NONE := {"direction": 0, "degrees": 0}
const RIGHT_90 := {"direction": 1, "degrees": 90}
const LEFT_90 := {"direction": -1, "degrees": 90}
const HALF := {"direction": 1, "degrees": 180}

# --- Helpers -----------------------------------------------------------------


func _empty_grid() -> Array:
	var grid: Array = []
	for col in range(SIZE.x):
		var column: Array = []
		column.resize(SIZE.y)
		column.fill(0)
		grid.append(column)
	return grid


## Builds a board from columns listed bottom-up, e.g. {0: [1, 2]} = player 1 at the bottom of
## column 0 with player 2 on top of it.
func _board_from_stacks(stacks: Dictionary) -> BotBoard:
	var grid := _empty_grid()
	for col: int in stacks:
		var stack: Array = stacks[col]
		for i in range(stack.size()):
			grid[col][BOTTOM - i] = stack[i]
	var board := BotBoard.new()
	board.setup_from_ids(grid)
	return board


func _inventory(p1_bombs: int = 0, p1_pacmans: int = 0, p2_bombs: int = 0, p2_pacmans: int = 0) -> Dictionary:
	return {
		P1: {Globals.ChipType.EYE: 999, Globals.ChipType.BOMB: p1_bombs, Globals.ChipType.PACMAN: p1_pacmans},
		P2: {Globals.ChipType.EYE: 999, Globals.ChipType.BOMB: p2_bombs, Globals.ChipType.PACMAN: p2_pacmans},
	}


func _search(max_depth: int) -> BotSearch:
	var search := BotSearch.new()
	search.max_depth = max_depth
	return search


# --- Brute-force reference ---------------------------------------------------
# Plain full-width expectiminimax over the same rules. No pruning, no transposition table,
# no move de-duplication, no ordering. It shares only the BotBoard rules, the leaf
# evaluation and the terminal scores with BotSearch.


func _ref_moves(board: BotBoard, mover: int, inventory: PackedInt32Array) -> Array[BotMove]:
	var moves: Array[BotMove] = []
	var bombs: int = inventory[(mover - 1) * 2]
	var pacmans: int = inventory[(mover - 1) * 2 + 1]
	for col in range(SIZE.x):
		if not board.is_column_open(col):
			continue
		moves.append(BotMove.new(Globals.ChipType.EYE, col))
		if pacmans > 0:
			for direction: String in ["right", "down", "left"]:
				moves.append(BotMove.new(Globals.ChipType.PACMAN, col, direction))
		if bombs > 0:
			moves.append(BotMove.new(Globals.ChipType.BOMB, col))
	return moves


func _ref_value(search: BotSearch, board: BotBoard, mover: int, rotations: Array, depth: int, inventory: PackedInt32Array) -> float:
	if depth == 0:
		return search.evaluate_leaf(board, mover, rotations, inventory)
	var moves := _ref_moves(board, mover, inventory)
	if moves.is_empty():
		return 0.0
	var best := -INF
	for move in moves:
		best = maxf(best, _ref_move_value(search, board, move, mover, rotations, depth, inventory))
	return best


func _ref_move_value(
	search: BotSearch, board: BotBoard, move: BotMove, mover: int, rotations: Array, depth: int, inventory: PackedInt32Array
) -> float:
	var after := board.simulate_move(move, mover)
	after.simulate_rotation(rotations[0] as Dictionary, move)
	var final: Variant = BotSearch.terminal_score(after.outcome_for(mover), depth)
	if final != null:
		return final
	var child_inventory := BotSearch.spend(inventory, mover, move.chip_type)
	var remaining: Array = rotations.slice(1)
	# The rotation revealed now is used (remaining.size() + 1) plies into the child's search
	if depth - 1 >= remaining.size() + 1:
		var expected := 0.0
		for outcome: Dictionary in BotSearch.rotation_outcomes():
			var child_rotations := remaining.duplicate()
			child_rotations.append(outcome.rotation)
			expected += float(outcome.p) * -_ref_value(search, after, 3 - mover, child_rotations, depth - 1, child_inventory)
		return expected
	var child_rotations := remaining.duplicate()
	child_rotations.append(null)
	return -_ref_value(search, after, 3 - mover, child_rotations, depth - 1, child_inventory)


## A random position reached by legal eye drops and random rotations, with no winner yet
func _random_position(rng: RandomNumberGenerator, chips: int) -> BotBoard:
	while true:
		var board := BotBoard.new()
		board.setup_from_ids(_empty_grid())
		var mover := P1
		var ok := true
		for i in range(chips):
			var moves := board.get_valid_drop_moves()
			if moves.is_empty():
				ok = false
				break
			var move: BotMove = moves[rng.randi() % moves.size()]
			board = board.simulate_move(move, mover)
			var outcomes := BotSearch.rotation_outcomes()
			board.simulate_rotation(outcomes[rng.randi() % outcomes.size()].rotation as Dictionary, move)
			if board.outcome_for(mover) != BotBoard.Outcome.NONE:
				ok = false
				break
			mover = 3 - mover
		if ok:
			return board
	return null


## A random position where neither player can win on their next move, so searches run deep
func _quiet_position(rng: RandomNumberGenerator, min_chips: int, max_chips: int, rotations: Array) -> BotBoard:
	var search := _search(1)
	while true:
		var board := _random_position(rng, min_chips + rng.randi() % (max_chips - min_chips + 1))
		if search.value(board, P1, _inventory(), rotations, 1) >= BotSearch.WIN_SCORE:
			continue
		if search.value(board, P2, _inventory(), rotations, 1) >= BotSearch.WIN_SCORE:
			continue
		return board
	return null


func _random_rotations(rng: RandomNumberGenerator) -> Array:
	var outcomes := BotSearch.rotation_outcomes()
	var rotations: Array = []
	for i in range(3):
		rotations.append(outcomes[rng.randi() % outcomes.size()].rotation)
	return rotations


func _assert_matches_reference(board: BotBoard, mover: int, rotations: Array, depth: int, inventory: Dictionary, label: String) -> void:
	var search := _search(depth)
	var packed := BotSearch.pack_inventory(inventory)
	var expected := _ref_value(search, board, mover, rotations, depth, packed)
	var actual := search.value(board, mover, inventory, rotations, depth)
	assert_almost_eq(actual, expected, EPSILON, "%s: search value must equal brute force" % label)
	# The chosen move must itself achieve the optimal value
	var chosen := search.choose(board, mover, inventory, rotations)
	var chosen_value := _ref_move_value(search, board, chosen, mover, rotations, depth, packed)
	assert_almost_eq(chosen_value, expected, EPSILON, "%s: chosen move must be optimal" % label)
