extends "res://test/unit/bot_search_helpers.gd"

## Tests for BotSearch, the bot's rotation-aware game-tree search: the rotation model, the
## equivalence with the brute-force reference (see bot_search_helpers.gd), chance nodes, edge
## cases and the time budget. Puzzles live in test_bot_puzzles.gd.

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
