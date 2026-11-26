extends GutTest

## BotWorker picks moves for each difficulty. choose_move() runs synchronously (no thread).

const SIZE: Vector2i = BotBoard.GRID_SIZE
const ROTATIONS := [{"direction": 0, "degrees": 0}, {"direction": 1, "degrees": 180}, {"direction": 1, "degrees": 90}]


func _inventory() -> Dictionary:
	return {
		1: {Globals.ChipType.EYE: 999, Globals.ChipType.BOMB: 1, Globals.ChipType.PACMAN: 2},
		2: {Globals.ChipType.EYE: 999, Globals.ChipType.BOMB: 1, Globals.ChipType.PACMAN: 2},
	}


func _board(grid: Array) -> BotBoard:
	var board := BotBoard.new()
	board.setup_from_ids(grid)
	return board


func _grid(fill_value: Callable) -> Array:
	var grid: Array = []
	for col in range(SIZE.x):
		var column: Array = []
		for row in range(SIZE.y):
			column.append(fill_value.call(col, row))
		grid.append(column)
	return grid


func _empty_board() -> BotBoard:
	return _board(_grid(func(_c: int, _r: int) -> int: return 0))


func _full_board() -> BotBoard:
	return _board(_grid(func(c: int, r: int) -> int: return 1 if (c + r / 2) % 2 == 0 else 2))


func test_every_difficulty_returns_a_legal_move() -> void:
	for difficulty: Globals.Difficulty in Globals.Difficulty.values():
		var board := _empty_board()
		board.set_cell(2, SIZE.y - 1, 1)
		var worker := BotWorker.new(board, 2, _inventory(), ROTATIONS, difficulty)
		var move := worker.choose_move()
		assert_not_null(move, "difficulty %d" % difficulty)
		assert_true(board.is_column_open(move.column), "difficulty %d must pick an open column" % difficulty)


func test_full_board_returns_no_move_on_every_difficulty() -> void:
	for difficulty: Globals.Difficulty in Globals.Difficulty.values():
		var worker := BotWorker.new(_full_board(), 2, _inventory(), ROTATIONS, difficulty)
		assert_null(worker.choose_move(), "difficulty %d" % difficulty)


func test_every_difficulty_takes_an_immediate_win() -> void:
	# Three in the bottom row, nothing rotates: column 3 wins on the spot
	for difficulty: Globals.Difficulty in Globals.Difficulty.values():
		var board := _empty_board()
		for col in range(3):
			board.set_cell(col, SIZE.y - 1, 2)
		board.set_cell(5, SIZE.y - 1, 1)
		board.set_cell(5, SIZE.y - 2, 1)
		var rotations := [{"direction": 0, "degrees": 0}, {"direction": 0, "degrees": 0}, {"direction": 0, "degrees": 0}]
		var worker := BotWorker.new(board, 2, _inventory(), rotations, difficulty)
		assert_eq(worker.choose_move().column, 3, "difficulty %d" % difficulty)
