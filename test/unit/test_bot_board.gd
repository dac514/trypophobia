extends GutTest

## Pure-logic tests for BotBoard: the bot's simplified board model.
## Grid is indexed [column][row]; row 0 is the top, row SIZE.y - 1 the bottom.
## 0 is an empty cell, 1 and 2 are player IDs.

const SIZE: Vector2i = BotBoard.GRID_SIZE
const BOTTOM: int = SIZE.y - 1


func _empty_grid() -> Array:
	var grid: Array = []
	for col in range(SIZE.x):
		var column: Array = []
		column.resize(SIZE.y)
		column.fill(0)
		grid.append(column)
	return grid


## Every cell holds a unique non-zero value, so rotations can be checked exactly
## (a full board is unaffected by gravity).
func _unique_full_grid() -> Array:
	var grid := _empty_grid()
	for col in range(SIZE.x):
		for row in range(SIZE.y):
			grid[col][row] = col * 10 + row + 1
	return grid


func _board(grid: Array) -> BotBoard:
	var board := BotBoard.new()
	board.current_board_permutation = grid
	return board


func _board_with(cells: Array[Vector2i], player_id: int = 1) -> BotBoard:
	var grid := _empty_grid()
	for cell in cells:
		grid[cell.x][cell.y] = player_id
	return _board(grid)


func _rotation(degrees: int, direction: int = 1) -> Dictionary:
	return {"degrees": degrees, "direction": direction}


# --- Win detection -----------------------------------------------------------


func test_horizontal_four_wins() -> void:
	var board := _board_with([Vector2i(0, BOTTOM), Vector2i(1, BOTTOM), Vector2i(2, BOTTOM), Vector2i(3, BOTTOM)])
	assert_true(board.check_for_win(0, BOTTOM))
	assert_true(board.check_for_win(3, BOTTOM))
	assert_true(board.has_winning_line(1))
	assert_false(board.has_winning_line(2))


func test_vertical_four_wins() -> void:
	var board := _board_with([Vector2i(2, BOTTOM), Vector2i(2, BOTTOM - 1), Vector2i(2, BOTTOM - 2), Vector2i(2, BOTTOM - 3)])
	assert_true(board.has_winning_line(1))


func test_diagonal_four_wins() -> void:
	var board := _board_with([Vector2i(0, BOTTOM), Vector2i(1, BOTTOM - 1), Vector2i(2, BOTTOM - 2), Vector2i(3, BOTTOM - 3)])
	assert_true(board.has_winning_line(1))


func test_anti_diagonal_four_wins() -> void:
	var board := _board_with([Vector2i(0, BOTTOM - 3), Vector2i(1, BOTTOM - 2), Vector2i(2, BOTTOM - 1), Vector2i(3, BOTTOM)])
	assert_true(board.has_winning_line(1))


func test_three_in_a_row_does_not_win() -> void:
	var board := _board_with([Vector2i(0, BOTTOM), Vector2i(1, BOTTOM), Vector2i(2, BOTTOM)])
	assert_false(board.has_winning_line(1))


func test_line_broken_by_opponent_does_not_win() -> void:
	var board := _board_with([Vector2i(0, BOTTOM), Vector2i(1, BOTTOM), Vector2i(3, BOTTOM), Vector2i(4, BOTTOM)])
	board.current_board_permutation[2][BOTTOM] = 2
	assert_false(board.has_winning_line(1))


func test_empty_cell_never_wins() -> void:
	assert_false(_board(_empty_grid()).check_for_win(0, BOTTOM))


# --- Valid moves / game over -------------------------------------------------


func test_empty_board_allows_every_column() -> void:
	var moves := _board(_empty_grid()).get_valid_drop_moves()
	assert_eq(moves.size(), SIZE.x)


func test_full_column_is_not_a_valid_move() -> void:
	var grid := _empty_grid()
	(grid[0] as Array).fill(1)
	var moves := _board(grid).get_valid_drop_moves()
	assert_eq(moves.size(), SIZE.x - 1)
	for move in moves:
		assert_ne(move.column, 0)


func test_game_over_only_when_every_column_is_full() -> void:
	var grid := _unique_full_grid()
	assert_true(_board(grid).is_game_over())
	grid[SIZE.x - 1][0] = 0
	assert_false(_board(grid).is_game_over())


# --- Rotation and gravity ----------------------------------------------------


func test_right_then_left_rotation_is_identity_on_full_board() -> void:
	var board := _board(_unique_full_grid())
	var eye := BotMove.new(Globals.ChipType.EYE, 0)
	board.simulate_rotation(_rotation(90, 1), eye)
	assert_ne(board.current_board_permutation, _unique_full_grid())
	board.simulate_rotation(_rotation(90, -1), eye)
	assert_eq(board.current_board_permutation, _unique_full_grid())


func test_two_half_turns_are_identity_on_full_board() -> void:
	var board := _board(_unique_full_grid())
	var eye := BotMove.new(Globals.ChipType.EYE, 0)
	board.simulate_rotation(_rotation(180), eye)
	assert_ne(board.current_board_permutation, _unique_full_grid())
	board.simulate_rotation(_rotation(180), eye)
	assert_eq(board.current_board_permutation, _unique_full_grid())


func test_rotation_moves_chip_then_gravity_drops_it() -> void:
	var eye := BotMove.new(Globals.ChipType.EYE, 0)

	# Bottom-left chip: clockwise puts it top-left, then it falls to bottom-left.
	var right := _board_with([Vector2i(0, BOTTOM)])
	right.simulate_rotation(_rotation(90, 1), eye)
	assert_eq(right.current_board_permutation, _board_with([Vector2i(0, BOTTOM)]).current_board_permutation)

	# Counter-clockwise puts it bottom-right.
	var left := _board_with([Vector2i(0, BOTTOM)])
	left.simulate_rotation(_rotation(90, -1), eye)
	assert_eq(left.current_board_permutation, _board_with([Vector2i(SIZE.x - 1, BOTTOM)]).current_board_permutation)

	# 180 puts it top-right, then it falls to bottom-right.
	var half := _board_with([Vector2i(0, BOTTOM)])
	half.simulate_rotation(_rotation(180), eye)
	assert_eq(half.current_board_permutation, _board_with([Vector2i(SIZE.x - 1, BOTTOM)]).current_board_permutation)


func test_no_rotation_applies_gravity_only_after_special_chip() -> void:
	# A chip floating mid-column (as left behind when a bomb clears below it).
	var floating := Vector2i(2, 1)

	var after_eye := _board_with([floating])
	after_eye.simulate_rotation(_rotation(0), BotMove.new(Globals.ChipType.EYE, 2))
	assert_eq(after_eye.current_board_permutation[2][1], 1, "EYE moves don't re-settle the board")

	var after_bomb := _board_with([floating])
	after_bomb.simulate_rotation(_rotation(0), BotMove.new(Globals.ChipType.BOMB, 2))
	assert_eq(after_bomb.current_board_permutation, _board_with([Vector2i(2, BOTTOM)]).current_board_permutation)


# --- Simulated moves ---------------------------------------------------------


func test_simulate_move_drops_to_lowest_free_row_without_mutating_original() -> void:
	var board := _board_with([Vector2i(3, BOTTOM)], 2)
	var after := board.simulate_move(BotMove.new(Globals.ChipType.EYE, 3), 1)
	assert_eq(after.current_board_permutation[3][BOTTOM - 1], 1)
	assert_eq(after.current_board_permutation[3][BOTTOM], 2)
	assert_eq(board.current_board_permutation[3][BOTTOM - 1], 0, "original board must be untouched")


func test_simulate_move_into_full_column_changes_nothing() -> void:
	var grid := _unique_full_grid()
	var after := _board(grid).simulate_move(BotMove.new(Globals.ChipType.EYE, 0), 1)
	assert_eq(after.current_board_permutation, _unique_full_grid())


func test_bomb_clears_itself_and_neighbours() -> void:
	# Bottom row: 2 1 2 under columns 1..3. Player 1 bombs column 2 (lands on top of its own chip).
	var grid := _empty_grid()
	grid[1][BOTTOM] = 2
	grid[2][BOTTOM] = 1
	grid[3][BOTTOM] = 2
	grid[5][BOTTOM] = 2  # out of blast range
	var after := _board(grid).simulate_move(BotMove.new(Globals.ChipType.BOMB, 2), 1)

	var expected := _empty_grid()
	expected[5][BOTTOM] = 2
	assert_eq(after.current_board_permutation, expected)
	assert_eq(after.last_action_meta.get("move_type"), "bomb")
	assert_eq(after.last_action_meta.get("destroyed_opp"), 2)
	# Counts the bomb chip itself plus the player's own chip under it.
	assert_eq(after.last_action_meta.get("destroyed_self"), 2)


func test_pacman_eats_the_chip_it_faces() -> void:
	var grid := _empty_grid()
	grid[1][BOTTOM] = 2
	grid[3][BOTTOM] = 2
	var after := _board(grid).simulate_move(BotMove.new(Globals.ChipType.PACMAN, 2, "left"), 1)

	var expected := _empty_grid()
	expected[3][BOTTOM] = 2
	assert_eq(after.current_board_permutation, expected)
	assert_eq(after.last_action_meta.get("move_type"), "pacman")
	assert_eq(after.last_action_meta.get("destroyed_opp"), 1)
	# The pacman chip removes itself, which counts as one self-destroyed chip.
	assert_eq(after.last_action_meta.get("destroyed_self"), 1)
