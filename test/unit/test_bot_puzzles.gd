extends "res://test/unit/bot_search_helpers.gd"

## Puzzles for BotSearch: positions with one right answer that check the bot plans with the
## three known rotations (wins and threats that only exist after a rotation), scores ties and
## fake lines correctly, and spends special chips only when they're worth it.

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


func test_four_in_a_row_before_the_rotation_is_not_a_win() -> void:
	# Dropping into column 0 makes four in a column, but the clockwise turn lays it flat onto
	# columns of different heights and the line falls apart. Wins only count after the turn.
	var board := _board_from_stacks({0: [P2, P2, P2], 1: [P1, P1], 2: [P1], 3: [P2], 4: [P1], 5: [P2]})
	var move := BotMove.new(Globals.ChipType.EYE, 0)
	assert_true(board.simulate_move(move, P2).has_winning_line(P2), "premise: four before the rotation")
	var search := _search(1)
	var packed := BotSearch.pack_inventory(_inventory())
	var move_value := _ref_move_value(search, board, move, P2, [RIGHT_90, NONE, NONE], 1, packed)
	assert_lt(move_value, BotSearch.WIN_SCORE, "the rotation breaks the line, so it is no win")


func test_forced_win_in_two_moves_that_needs_the_third_rotation() -> void:
	# Found by searching random positions: with rotations (none, clockwise, half turn) player 2
	# forces a win on its second move, whatever player 1 does in between. Any other third
	# rotation and the win disappears, so the bot must be planning with all three rotations.
	var board := _board_from_stacks({0: [P1, P1, P2, P2], 1: [P1, P2], 2: [P1], 3: [P2]})
	var rotations := [NONE, RIGHT_90, HALF]
	var search := _search(3)
	assert_lt(search.value(board, P2, _inventory(), rotations, 1), BotSearch.WIN_SCORE, "no win on the first move")
	assert_almost_eq(search.value(board, P2, _inventory(), rotations, 3), BotSearch.WIN_SCORE + 1, EPSILON, "win on the second move")
	for other in [NONE, RIGHT_90, LEFT_90]:
		var value := _search(3).value(board, P2, _inventory(), [NONE, RIGHT_90, other], 3)
		assert_lt(value, BotSearch.WIN_SCORE, "third rotation %s: no forced win" % BotSearch.rotation_code(other))
	var move := search.choose(board, P2, _inventory(), rotations)
	var packed := BotSearch.pack_inventory(_inventory())
	assert_almost_eq(_ref_move_value(search, board, move, P2, rotations, 3, packed), BotSearch.WIN_SCORE + 1, EPSILON)


func test_best_reply_depends_on_the_third_known_rotation() -> void:
	# The information the preview adds: here player 1's best move changes with the third
	# rotation shown. The chance nodes give each revealed rotation its own reply like this.
	var board := _board_from_stacks({0: [P1, P1, P2], 1: [P2, P2], 2: [P1], 3: [P2], 4: [P1], 5: [P1]})
	var with_half := _search(3).choose(board, P1, _inventory(), [RIGHT_90, LEFT_90, HALF])
	var with_none := _search(3).choose(board, P1, _inventory(), [RIGHT_90, LEFT_90, NONE])
	assert_ne(with_half.column, with_none.column)


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
