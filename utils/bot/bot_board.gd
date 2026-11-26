class_name BotBoard extends RefCounted

## The BotBoard class simulates and evaluates game states for the AI bot.
##
## It represents the board as a grid of player IDs and provides methods for duplication,
## chip counting, move validation, rotation, and win detection. By simplifying the board
## to a grid of integers, avoiding full game objects or physics, it reduces computational
## overhead, enabling efficient and isolated evaluations for AI decision-making.
##
## Cells are stored in a flat PackedByteArray, column-major: index = column * GRID_SIZE.y + row,
## row 0 is the top. Copying a board is a single memory copy, which keeps deep searches fast.
## current_board_permutation exposes the same data as a [column][row] Array of Arrays.

enum Outcome { NONE, MOVER_WINS, OPPONENT_WINS, DRAW }

const GRID_SIZE: Vector2i = Board.GRID_SIZE
const CELL_COUNT: int = GRID_SIZE.x * GRID_SIZE.y

## Heuristic weights for a line of four cells only one player occupies
const WINDOW_THREE: float = 40.0
const WINDOW_THREE_PLAYABLE: float = 25.0
const WINDOW_TWO: float = 6.0
const WINDOW_ONE: float = 1.0
## Opponent lines count a bit more: defending is worth more than attacking
const DEFENCE_WEIGHT: float = 1.2

## Every line of four cells, as flat cell indices, four per line
static var _window_cells: PackedInt32Array = _build_window_cells()

## Player IDs per cell (0 = empty), see the class description for the layout
var cells: PackedByteArray
var chip_count: int
var last_action_meta: Dictionary = {}

## The board as a [column][row] Array of Arrays. Reading returns a copy; assign to replace.
var current_board_permutation: Array:
	get:
		return _to_nested()
	set(value):
		_from_nested(value)


func _init() -> void:
	cells.resize(CELL_COUNT)


static func index_of(column: int, row: int) -> int:
	return column * GRID_SIZE.y + row


## Creates a new BotBoard grid with PlayerIDs from a grid of Chip objects.
## Reads Chip nodes, so call it on the main thread.
func setup(grid_state: Array) -> void:
	cells.fill(0)
	chip_count = 0
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			var chip: Chip = grid_state[col][row]
			if chip:
				cells[index_of(col, row)] = chip.player_id
				chip_count += 1


## Creates a BotBoard from a [column][row] grid of player IDs (0 = empty)
func setup_from_ids(grid_ids: Array) -> void:
	_from_nested(grid_ids)


## Creates a copy of this BotBoard with the same state
func duplicate() -> BotBoard:
	var new_board := BotBoard.new()
	new_board.cells = cells.duplicate()
	new_board.chip_count = chip_count
	new_board.last_action_meta = last_action_meta.duplicate(true)
	return new_board


func get_cell(column: int, row: int) -> int:
	return cells[index_of(column, row)]


func set_cell(column: int, row: int, player_id: int) -> void:
	cells[index_of(column, row)] = player_id


## True when a chip can still be dropped into the column
func is_column_open(column: int) -> bool:
	return cells[index_of(column, 0)] == 0


## Gets all valid column moves for current board state
## Returns one placeholder per open column using EYE as a neutral default
## May override chip_type & direction when expanding actual actions
func get_valid_drop_moves() -> Array[BotMove]:
	var moves: Array[BotMove] = []
	for col in range(GRID_SIZE.x):
		if is_column_open(col):
			moves.append(BotMove.new(Globals.ChipType.EYE, col))
	return moves


## Sets rotated board as current permutation
func simulate_rotation(rotation_state: Dictionary, move: BotMove) -> void:
	var degrees: int = rotation_state.get("degrees", 0)
	if degrees == 0:
		# Without a rotation only special chips (which remove chips) leave anything floating
		if move.chip_type != Globals.ChipType.EYE:
			cells = _gravity(cells)
		return
	cells = _rotated(cells, rotation_state)


func check_for_win(column: int, row: int) -> bool:
	var player_id: int = cells[index_of(column, row)]
	if player_id == 0:
		return false
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for direction in directions:
		var chips_in_a_row := 1 + _count_line(column, row, direction, player_id) + _count_line(column, row, -direction, player_id)
		if chips_in_a_row >= 4:
			return true
	return false


## Creates a new BotBoard with a move applied (placement + effects + rotation + gravity)
func simulate_move_and_rotation(move: BotMove, player_id: int, next_rotation_states: Array) -> BotBoard:
	var new_board := simulate_move(move, player_id)
	if next_rotation_states.size() > 0:
		new_board.simulate_rotation(next_rotation_states[0] as Dictionary, move)
	return new_board


## Simulate a move on the current board: place the chip and apply its effect (no rotation)
func simulate_move(move: BotMove, player_id: int) -> BotBoard:
	var new_board := duplicate()
	new_board.last_action_meta = {}

	var drop_row := _find_drop_row(move.column)
	if drop_row == -1:
		return new_board  # Invalid move - column full

	new_board.cells[index_of(move.column, drop_row)] = player_id
	new_board.chip_count += 1

	if move.chip_type == Globals.ChipType.BOMB:
		var destroyed := new_board._clear_cells(_bomb_targets(move.column, drop_row), player_id)
		new_board.last_action_meta = {"move_type": "bomb", "destroyed_self": destroyed.x, "destroyed_opp": destroyed.y}
	elif move.chip_type == Globals.ChipType.PACMAN:
		var targets := PackedInt32Array([index_of(move.column, drop_row)])
		var facing := Vector2i(move.column, drop_row) + _get_pacman_direction(move.direction)
		if facing.x >= 0 and facing.x < GRID_SIZE.x and facing.y >= 0 and facing.y < GRID_SIZE.y:
			targets.append(index_of(facing.x, facing.y))
		var destroyed := new_board._clear_cells(targets, player_id)
		new_board.last_action_meta = {"move_type": "pacman", "destroyed_self": destroyed.x, "destroyed_opp": destroyed.y}

	return new_board


## Checks if the given player has a winning line on current board
func has_winning_line(player_id: int) -> bool:
	return (_line_owners(cells) & player_id) != 0


## Result of a turn, from the point of view of the player who just moved.
## Wins are only counted after the rotation and gravity have settled (see Board).
func outcome_for(mover_id: int) -> Outcome:
	var owners := _line_owners(cells)
	var mover_line: bool = (owners & mover_id) != 0
	var opponent_line: bool = (owners & (3 - mover_id)) != 0
	if mover_line and opponent_line:
		return Outcome.DRAW
	if mover_line:
		return Outcome.MOVER_WINS
	if opponent_line:
		return Outcome.OPPONENT_WINS
	if is_game_over():
		return Outcome.DRAW
	return Outcome.NONE


## Static evaluation for player_id, positive is good. When the rotation that follows the next
## move is known, the board is also scored as it will look after that rotation, because that
## is the board wins are counted on.
func heuristic(player_id: int, next_rotation: Variant = null) -> float:
	var score := _score_windows(cells, player_id)
	if next_rotation is Dictionary and int((next_rotation as Dictionary).get("degrees", 0)) != 0:
		var rotated := _rotated(cells, next_rotation as Dictionary)
		score = 0.5 * score + 0.5 * _score_windows(rotated, player_id)
	return score


## Check if game is over (all columns full)
func is_game_over() -> bool:
	for col in range(GRID_SIZE.x):
		if is_column_open(col):
			return false
	return true


# A debug function to print the board state in ASCII format
func print_ascii_grid() -> void:
	print("-- GRID STATE BOT --")  # Divider before grid
	for row in range(GRID_SIZE.y):
		var line := ""
		for col in range(GRID_SIZE.x):
			line += str(cells[index_of(col, row)]) + " "
		print(line)
	print("------------------")  # Divider after grid


static func _build_window_cells() -> PackedInt32Array:
	var result := PackedInt32Array()
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			for d in directions:
				var end := Vector2i(col, row) + d * 3
				if end.x < 0 or end.x >= GRID_SIZE.x or end.y < 0 or end.y >= GRID_SIZE.y:
					continue
				for i in range(4):
					var cell := Vector2i(col, row) + d * i
					result.append(index_of(cell.x, cell.y))
	return result


## Bitmask of the players owning at least one line of four: 1 = player 1, 2 = player 2, 3 = both.
static func _line_owners(board_cells: PackedByteArray) -> int:
	var owners := 0
	var i := 0
	var count := _window_cells.size()
	while i < count:
		var player_id: int = board_cells[_window_cells[i]]
		if (
			player_id != 0
			and board_cells[_window_cells[i + 1]] == player_id
			and board_cells[_window_cells[i + 2]] == player_id
			and board_cells[_window_cells[i + 3]] == player_id
		):
			owners |= player_id
			if owners == 3:
				return owners
		i += 4
	return owners


## Scores every open line of four: lines only one player occupies are potential wins.
## Threats whose empty cell can be filled right now (gravity-reachable) are worth more.
static func _score_windows(board_cells: PackedByteArray, player_id: int) -> float:
	var score := 0.0
	var i := 0
	var count := _window_cells.size()
	while i < count:
		var own := 0
		var other := 0
		var empty_index := -1
		for k in range(4):
			var index: int = _window_cells[i + k]
			var value: int = board_cells[index]
			if value == 0:
				empty_index = index
			elif value == player_id:
				own += 1
			else:
				other += 1
		i += 4
		if own > 0 and other > 0:
			continue
		var line_count := own if own > 0 else other
		var line_score := 0.0
		if line_count == 3:
			line_score = WINDOW_THREE
			# Gravity-reachable: the empty cell is on the bottom row or sits on a chip
			if empty_index % GRID_SIZE.y == GRID_SIZE.y - 1 or board_cells[empty_index + 1] != 0:
				line_score += WINDOW_THREE_PLAYABLE
		elif line_count == 2:
			line_score = WINDOW_TWO
		elif line_count == 1:
			line_score = WINDOW_ONE
		score += line_score if own > 0 else -line_score * DEFENCE_WEIGHT
	return score


## Rotates the board and lets the chips fall
static func _rotated(board_cells: PackedByteArray, rotation_state: Dictionary) -> PackedByteArray:
	var direction: int = rotation_state.get("direction", 0)
	var degrees: int = rotation_state.get("degrees", 0)
	var rotated := PackedByteArray()
	rotated.resize(CELL_COUNT)
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			var value: int = board_cells[index_of(col, row)]
			if value == 0:
				continue
			var target: Vector2i
			if degrees == 180:
				# 180°: (col,row) -> (GRID_SIZE.x-1-col, GRID_SIZE.y-1-row)
				target = Vector2i(GRID_SIZE.x - 1 - col, GRID_SIZE.y - 1 - row)
			elif direction == 1:
				# Right 90° (CW): (col,row) -> (GRID_SIZE.x-1-row, col)
				target = Vector2i(GRID_SIZE.x - 1 - row, col)
			else:
				# Left 90° (CCW): (col,row) -> (row, GRID_SIZE.y-1-col)
				target = Vector2i(row, GRID_SIZE.y - 1 - col)
			rotated[index_of(target.x, target.y)] = value
	return _gravity(rotated)


## Make chips fall to the bottom in each column, keeping their order
static func _gravity(board_cells: PackedByteArray) -> PackedByteArray:
	var settled := PackedByteArray()
	settled.resize(CELL_COUNT)
	for col in range(GRID_SIZE.x):
		var target_row := GRID_SIZE.y - 1
		for row in range(GRID_SIZE.y - 1, -1, -1):
			var value: int = board_cells[index_of(col, row)]
			if value != 0:
				settled[index_of(col, target_row)] = value
				target_row -= 1
	return settled


# A helper function to find a continuous line of chips
func _count_line(column: int, row: int, direction: Vector2i, player_id: int) -> int:
	var count := 0
	var current := Vector2i(column, row) + direction
	while current.x >= 0 and current.x < GRID_SIZE.x and current.y >= 0 and current.y < GRID_SIZE.y:
		if cells[index_of(current.x, current.y)] != player_id:
			break
		count += 1
		current += direction
	return count


func _find_drop_row(column: int) -> int:
	for row in range(GRID_SIZE.y - 1, -1, -1):
		if cells[index_of(column, row)] == 0:
			return row
	return -1


## The bomb's own cell and every neighbouring cell
func _bomb_targets(col: int, row: int) -> PackedInt32Array:
	var targets := PackedInt32Array()
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			var nx: int = col + dx
			var ny: int = row + dy
			if nx >= 0 and nx < GRID_SIZE.x and ny >= 0 and ny < GRID_SIZE.y:
				targets.append(index_of(nx, ny))
	return targets


## Empties the given cells. Returns how many chips were removed: x = player_id's, y = the opponent's.
func _clear_cells(targets: PackedInt32Array, player_id: int) -> Vector2i:
	var destroyed := Vector2i.ZERO
	for index in targets:
		var value: int = cells[index]
		if value == 0:
			continue
		if value == player_id:
			destroyed.x += 1
		else:
			destroyed.y += 1
		cells[index] = 0
		chip_count -= 1
	return destroyed


func _get_pacman_direction(direction: String) -> Vector2i:
	match direction:
		"down":
			return Vector2i(0, 1)
		"left":
			return Vector2i(-1, 0)
		"up":
			return Vector2i(0, -1)
		_:
			return Vector2i(1, 0)


func _to_nested() -> Array:
	var grid: Array = []
	for col in range(GRID_SIZE.x):
		var column: Array = []
		for row in range(GRID_SIZE.y):
			column.append(int(cells[index_of(col, row)]))
		grid.append(column)
	return grid


func _from_nested(grid_ids: Array) -> void:
	cells.resize(CELL_COUNT)
	cells.fill(0)
	chip_count = 0
	for col in range(GRID_SIZE.x):
		for row in range(GRID_SIZE.y):
			var value: int = grid_ids[col][row]
			cells[index_of(col, row)] = value
			if value != 0:
				chip_count += 1
