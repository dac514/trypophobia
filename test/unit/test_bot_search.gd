extends GutTest

## Tests for BotSearch, the bot's rotation-aware game-tree search.
##
## "Optimal" here means optimal in the BotBoard model, up to the search depth:
## - Equivalence tests compare the real search (alpha-beta, transposition table, move
##   de-duplication, move ordering, lazy chance nodes) against a slow brute-force reference
##   written independently below. Equal values on many random positions show the
##   optimisations never change the answer.
## - Puzzle tests check that the bot uses the three known rotations correctly: wins that only
##   exist after a rotation, threats that only appear after the opponent's move plus the next
##   rotation, and so on.
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


# --- Rotation model -----------------------------------------------------------


func test_rotation_outcomes_merge_half_turns_and_sum_to_one() -> void:
	var probabilities: Dictionary = {}
	var total := 0.0
	for outcome in BotSearch.rotation_outcomes():
		probabilities[BotSearch.rotation_code(outcome.rotation)] = outcome.p
		total += float(outcome.p)
	assert_almost_eq(total, 1.0, EPSILON)
	assert_almost_eq(float(probabilities["N"]), 0.4, EPSILON, "no rotation")
	assert_almost_eq(float(probabilities["H"]), 0.4, EPSILON, "180 degrees, both directions merged")
	assert_almost_eq(float(probabilities["R"]), 0.1, EPSILON, "90 degrees clockwise")
	assert_almost_eq(float(probabilities["L"]), 0.1, EPSILON, "90 degrees counter-clockwise")


func test_reveal_is_only_searched_when_the_rotation_will_be_used() -> void:
	# With 3 known rotations, the child sees 2 known ones plus the revealed one, which is used
	# on the child's third ply. So a depth-3 search never needs chance nodes, depth 4 does.
	assert_false(BotSearch.reveal_needed(2, 2))
	assert_true(BotSearch.reveal_needed(3, 2))


# --- Equivalence with brute force ----------------------------------------------


func test_matches_brute_force_eyes_only_depth_3() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in range(12):
		var board := _random_position(rng, 6 + rng.randi() % 14)
		_assert_matches_reference(board, P1 + i % 2, _random_rotations(rng), 3, _inventory(), "eyes depth 3 #%d" % i)


func test_matches_brute_force_with_chance_nodes_depth_4() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(3):
		var board := _random_position(rng, 18 + rng.randi() % 8)
		_assert_matches_reference(board, P1 + i % 2, _random_rotations(rng), 4, _inventory(), "chance depth 4 #%d" % i)


func test_matches_brute_force_with_special_chips() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(6):
		var board := _random_position(rng, 8 + rng.randi() % 16)
		var inventory := _inventory(1, 2, 1, 2)
		_assert_matches_reference(board, P1 + i % 2, _random_rotations(rng), 2, inventory, "specials depth 2 #%d" % i)


func test_matches_brute_force_with_special_chips_depth_3_on_crowded_boards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for i in range(2):
		var board := _random_position(rng, 26 + rng.randi() % 4)
		var inventory := _inventory(0, 1, 1, 0)
		_assert_matches_reference(board, P2 - i % 2, _random_rotations(rng), 3, inventory, "specials depth 3 #%d" % i)


# --- Puzzles: using the known rotations --------------------------------------


# Board for the rotation puzzles. Row 4 (second from the bottom) holds three of player 2's eyes
# with a gap at column 2 (which is empty, so a chip dropped there lands on the bottom row).
# Column 4 has one chip, so a chip dropped there lands in row 4.
#
#     . . . . . .
#     2 2 . 2 . .     <- row 4
#     1 1 . 2 1 .     <- bottom row
#
# A clockwise quarter turn makes every row a column, and gravity closes the gaps. So after
# dropping into column 4, row 4 becomes a column of four 2s, a win that doesn't exist before
# the rotation.
func _rotation_puzzle_board(swap_players: bool = false) -> BotBoard:
	var a := P2 if not swap_players else P1
	var b := P1 if not swap_players else P2
	return _board_from_stacks({0: [b, a], 1: [b, a], 3: [a, a], 4: [b]})


func test_finds_win_that_only_exists_after_the_rotation() -> void:
	var board := _rotation_puzzle_board()
	var rotations := [RIGHT_90, NONE, NONE]
	var move := _search(1).choose(board, P2, _inventory(), rotations)
	assert_eq(move.column, 4)
	assert_eq(move.chip_type, Globals.ChipType.EYE)
	# Premise: there is no four in a row before the rotation
	var before := board.simulate_move(move, P2)
	assert_false(before.has_winning_line(P2), "the line must only exist after the rotation")


func test_does_not_see_the_rotation_win_when_the_rotation_differs() -> void:
	# Same board, but nothing rotates: column 4 is no longer a win
	var search := _search(1)
	search.choose(_rotation_puzzle_board(), P2, _inventory(), [NONE, NONE, NONE])
	assert_lt(search.best_value, BotSearch.WIN_SCORE)


func test_prefers_the_immediate_win_over_a_slower_one() -> void:
	var rotations := [RIGHT_90, NONE, NONE]
	var search := _search(3)
	var move := search.choose(_rotation_puzzle_board(), P2, _inventory(), rotations)
	assert_eq(move.column, 4)
	assert_eq(search.reached_depth, 1, "a proven win ends the search early")
	# Searched 3 plies deep, a win on the first ply scores WIN + 3: more than any later win
	var value := _search(3).value(_rotation_puzzle_board(), P2, _inventory(), rotations, 3)
	assert_almost_eq(value, BotSearch.WIN_SCORE + 3, EPSILON, "a win now scores highest")


func test_blocks_a_threat_that_appears_only_after_the_next_rotation() -> void:
	# Player 1 owns the pattern. Nothing rotates after the bot's move, but after player 1's
	# reply the board turns clockwise: player 1 wins by dropping into column 4. The bot must
	# take that cell first.
	var board := _rotation_puzzle_board(true)
	var move := _search(2).choose(board, P2, _inventory(), [NONE, RIGHT_90, NONE])
	assert_eq(move.column, 4)
	assert_eq(move.chip_type, Globals.ChipType.EYE)


func test_avoids_a_move_that_hands_the_opponent_a_rotation_win() -> void:
	# Player 1 needs row 4 of column 4 (or column 2) to complete row 4 before a clockwise turn.
	# Column 4 is empty here, so only a bot chip dropped into column 4 or column 2 would lift
	# that cell into reach.
	var board := _board_from_stacks({0: [P2, P1], 1: [P2, P1], 3: [P1, P1]})
	var search := _search(2)
	var move := search.choose(board, P2, _inventory(), [NONE, RIGHT_90, NONE])
	assert_does_not_have([2, 4], move.column, "columns 2 and 4 hand player 1 a win")
	assert_gt(search.best_value, -BotSearch.WIN_SCORE, "a safe move exists")
	# Premise: column 4 really is losing
	var packed := BotSearch.pack_inventory(_inventory())
	var losing := _ref_move_value(search, board, BotMove.new(Globals.ChipType.EYE, 4), P2, [NONE, RIGHT_90, NONE], 2, packed)
	assert_lt(losing, -BotSearch.WIN_SCORE + 10.0)


func test_simultaneous_lines_score_as_a_draw() -> void:
	# Both players get four after the rotation: it's a tie, not a win
	var board := _board_from_stacks({0: [P1, P2], 1: [P1, P2], 3: [P1, P2], 4: [P1]})
	var after := board.simulate_move(BotMove.new(Globals.ChipType.EYE, 4), P2)
	after.simulate_rotation(RIGHT_90, BotMove.new(Globals.ChipType.EYE, 4))
	assert_eq(after.outcome_for(P2), BotBoard.Outcome.DRAW)
	var search := _search(1)
	var packed := BotSearch.pack_inventory(_inventory())
	var draw_value := _ref_move_value(search, board, BotMove.new(Globals.ChipType.EYE, 4), P2, [RIGHT_90, NONE, NONE], 1, packed)
	assert_almost_eq(draw_value, 0.0, EPSILON)


# --- Puzzles: special chips ----------------------------------------------------


func test_uses_a_special_chip_against_a_double_threat() -> void:
	# Player 1 has three on the bottom row with both ends open: one eye can't block both.
	var board := _board_from_stacks({1: [P1], 2: [P1], 3: [P1], 5: [P2]})
	var search := _search(2)
	var move := search.choose(board, P2, _inventory(0, 0, 1, 2), [NONE, NONE, NONE])
	assert_ne(move.chip_type, Globals.ChipType.EYE, "only a bomb or pacman saves the game")
	assert_gt(search.best_value, -BotSearch.WIN_SCORE)


func test_uses_an_eye_when_an_eye_is_enough() -> void:
	# Player 1 threatens four in column 1. Capping it with an eye blocks it. The threat is
	# wrapped in the bot's own chips, so a bomb would cost as much as it gains and a pacman
	# would remove just one chip: not worth spending a special chip on.
	var board := _board_from_stacks({0: [P2, P1, P2], 1: [P1, P1, P1], 2: [P1, P2, P2], 4: [P2]})
	var move := _search(2).choose(board, P2, _inventory(0, 0, 1, 2), [NONE, NONE, NONE])
	assert_eq(move.chip_type, Globals.ChipType.EYE)
	assert_eq(move.column, 1)


func test_pacman_direction_is_part_of_the_move() -> void:
	# Only a pacman eating the chip to its left (column 2) can stop player 1 here
	var board := _board_from_stacks({1: [P1], 2: [P1], 3: [P1], 5: [P2]})
	var move := _search(2).choose(board, P2, _inventory(0, 0, 0, 1), [NONE, NONE, NONE])
	assert_eq(move.chip_type, Globals.ChipType.PACMAN)
	var after := board.simulate_move(move, P2)
	var removed := 0
	for col in [1, 2, 3]:
		if after.current_board_permutation[col][BOTTOM] == 0:
			removed += 1
	assert_eq(removed, 1, "the pacman must face one of player 1's chips")


# --- Chance nodes ----------------------------------------------------------------


func test_chance_node_is_the_weighted_average_of_the_revealed_rotations() -> void:
	# Only column 5 is open, so the root has exactly one move and its value is the expectation
	# over the rotation revealed after it.
	var stacks := {}
	for col in range(5):
		stacks[col] = [P1, P2, P2, P1, P1, P2] if col % 2 == 0 else [P2, P1, P1, P2, P2, P1]
	stacks[5] = [P1, P2]
	var board := _board_from_stacks(stacks)
	var rotations := [NONE, NONE, NONE]
	var depth := 4
	var search := _search(depth)
	var move := BotMove.new(Globals.ChipType.EYE, 5)
	var after := board.simulate_move(move, P2)
	after.simulate_rotation(NONE, move)
	if after.outcome_for(P2) != BotBoard.Outcome.NONE:
		fail_test("premise: the game must go on after the only move")
		return

	var expected := 0.0
	for outcome in BotSearch.rotation_outcomes():
		var child := _search(depth - 1)
		expected += float(outcome.p) * -child.value(after, P1, _inventory(), [NONE, NONE, outcome.rotation], depth - 1)
	assert_almost_eq(search.value(board, P2, _inventory(), rotations, depth), expected, EPSILON)


# --- Edge cases and time budget -------------------------------------------------


func test_full_board_has_no_move() -> void:
	var grid := _empty_grid()
	for col in range(SIZE.x):
		for row in range(SIZE.y):
			grid[col][row] = P1 if (col + row / 2) % 2 == 0 else P2
	var board := BotBoard.new()
	board.setup_from_ids(grid)
	assert_null(_search(3).choose(board, P2, _inventory(), [NONE, NONE, NONE]))


func test_respects_the_time_budget() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rotations := [HALF, LEFT_90, NONE]
	var board := _quiet_position(rng, 10, 16, rotations)
	var search := _search(8)
	search.time_limit_ms = 300
	var started := Time.get_ticks_msec()
	var move := search.choose(board, P2, _inventory(1, 2, 1, 2), rotations)
	var took := Time.get_ticks_msec() - started
	assert_not_null(move)
	assert_lt(took, 450, "must answer close to the budget")
	assert_gte(search.reached_depth, 1)
	gut.p("300 ms budget: depth %d, %d nodes, %d ms" % [search.reached_depth, search.nodes, took])


func test_tiny_budget_still_returns_the_depth_one_move() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var rotations := [NONE, HALF, RIGHT_90]
	var board := _quiet_position(rng, 10, 16, rotations)
	var search := _search(8)
	search.time_limit_ms = 1
	var move := search.choose(board, P1, _inventory(1, 2, 1, 2), rotations)
	assert_not_null(move)
	assert_eq(search.reached_depth, 1)


func test_hard_search_depth_reached_in_budget() -> void:
	# Informational: prints how deep the Hard setting gets on a mid-game board
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var rotations := [HALF, NONE, RIGHT_90]
	var board := _quiet_position(rng, 10, 16, rotations)
	var search := _search(BotWorker.HARD_MAX_DEPTH)
	search.time_limit_ms = BotWorker.HARD_TIME_LIMIT_MS
	var move := search.choose(board, P2, _inventory(1, 2, 1, 2), rotations)
	assert_not_null(move)
	gut.p("Hard: depth %d, %d nodes, %d ms" % [search.reached_depth, search.nodes, search.elapsed_ms])
