extends GutTest

## Turn outcomes and move generation: the rules BotSearch relies on.
## Grid is indexed [column][row]; row 0 is the top. 0 is empty, 1 and 2 are player IDs.

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


func _board(grid: Array) -> BotBoard:
	var board := BotBoard.new()
	board.current_board_permutation = grid
	return board


func _board_with(cells: Array[Vector2i], player_id: int = 1) -> BotBoard:
	var grid := _empty_grid()
	for cell in cells:
		grid[cell.x][cell.y] = player_id
	return _board(grid)


# --- Turn outcomes -------------------------------------------------------------


func test_outcome_mover_wins() -> void:
	var board := _board_with([Vector2i(0, BOTTOM), Vector2i(1, BOTTOM), Vector2i(2, BOTTOM), Vector2i(3, BOTTOM)])
	assert_eq(board.outcome_for(1), BotBoard.Outcome.MOVER_WINS)


func test_outcome_opponent_wins() -> void:
	# A move can complete the other player's line (e.g. after a rotation): they win
	var board := _board_with([Vector2i(0, BOTTOM), Vector2i(1, BOTTOM), Vector2i(2, BOTTOM), Vector2i(3, BOTTOM)], 2)
	assert_eq(board.outcome_for(1), BotBoard.Outcome.OPPONENT_WINS)


func test_outcome_both_lines_is_a_draw() -> void:
	var board := _board_with([Vector2i(0, BOTTOM), Vector2i(1, BOTTOM), Vector2i(2, BOTTOM), Vector2i(3, BOTTOM)])
	for col in range(4):
		board.set_cell(col, BOTTOM - 1, 2)
	assert_eq(board.outcome_for(1), BotBoard.Outcome.DRAW)


func test_outcome_full_board_without_lines_is_a_draw() -> void:
	var grid := _empty_grid()
	for col in range(SIZE.x):
		for row in range(SIZE.y):
			grid[col][row] = 1 if (col + row / 2) % 2 == 0 else 2
	var board := _board(grid)
	assert_false(board.has_winning_line(1) or board.has_winning_line(2), "premise: no lines")
	assert_eq(board.outcome_for(1), BotBoard.Outcome.DRAW)


func test_outcome_none_while_the_game_goes_on() -> void:
	assert_eq(_board_with([Vector2i(0, BOTTOM)]).outcome_for(1), BotBoard.Outcome.NONE)


# --- Move generation -----------------------------------------------------------


func test_pacman_moves_with_the_same_result_are_merged() -> void:
	# On an empty board a pacman eats nothing whichever way it faces: one move per column
	var search := BotSearch.new()
	var inventory := BotSearch.pack_inventory({1: {Globals.ChipType.PACMAN: 1}, 2: {}})
	var moves := search.legal_moves(_board(_empty_grid()), 1, inventory, true)
	var pacmans := 0
	for entry in moves:
		if (entry.move as BotMove).chip_type == Globals.ChipType.PACMAN:
			pacmans += 1
	assert_eq(pacmans, 1, "every pacman move leaves the board empty, so they are one move")


func test_bomb_and_pacman_are_not_merged_with_each_other() -> void:
	# Both leave an empty board here, but they spend different chips
	var search := BotSearch.new()
	var inventory := BotSearch.pack_inventory({1: {Globals.ChipType.PACMAN: 1, Globals.ChipType.BOMB: 1}, 2: {}})
	var types := {}
	for entry in search.legal_moves(_board(_empty_grid()), 1, inventory, true):
		types[(entry.move as BotMove).chip_type] = true
	assert_eq(types.size(), 3, "eye, pacman and bomb moves are all kept")
