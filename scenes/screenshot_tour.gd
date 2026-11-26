class_name ScreenshotTour
extends Node

## Debug helper: plays through the game's main screens and saves a screenshot of each, then quits.
## Start the game with:  godot --path . --resolution 720x1280 -- --screenshot-tour=<directory>
## Used to check layout and colours in every orientation without clicking through by hand.

const ARG_PREFIX = "--screenshot-tour="

var _directory: String
var _main: Node


## Returns the target directory if the tour was requested on the command line, else ""
static func requested_directory() -> String:
	if not OS.is_debug_build():
		return ""  # Never in release exports
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(ARG_PREFIX):
			return arg.trim_prefix(ARG_PREFIX)
	return ""


func _init(main: Node, directory: String) -> void:
	_main = main
	_directory = directory
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_directory)
	seed(514)  # Same rotations every run, so screenshots are comparable
	_run.call_deferred()


func _run() -> void:
	await _wait(1.5)
	await _capture("menu")

	_main.set("is_against_bot", false)
	_main.call("start_new_game")
	for column: int in [2, 3, 2, 4, 1, 3]:
		await _drop(column)
	await _wait(0.5)
	await _capture("game")

	# Turn the "device" mid-game: the layout must follow, with every chip in place
	var size := DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(size.y, size.x))
	var board: Board = _main.get("board")
	await _wait_until(func() -> bool: return not board.is_busy)
	await _wait(1.0)
	await _capture("game_turned")
	DisplayServer.window_set_size(size)
	await _wait(1.0)

	for step: Callable in _extra_steps():
		await step.call()

	print("ScreenshotTour: done, saved to %s" % _directory)
	get_tree().quit()


## More screens to capture, added as features land
func _extra_steps() -> Array[Callable]:
	return [
		_capture_distinct_chips_and_options,
		_play_bot_turns,
		_check_full_column,
		_check_full_board_draw,
		_check_tutorial_during_bot_think,
		_play_tutorial,
	]


func _check(ok: bool, what: String) -> void:
	print("ScreenshotTour CHECK %s: %s" % ["PASS" if ok else "FAIL", what])


func _no_rotations() -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	for i in range(40):
		none.append({"direction": 0, "degrees": 0})
	return none


## Six chips fill a column; a seventh must be refused (it used to land above the grid)
func _check_full_column() -> void:
	var board: Board = _main.get("board")
	_main.set("is_against_bot", false)
	_main.call("start_new_game")
	board.board_rotator.set_scripted_rotations(_no_rotations())
	for i in range(6):
		var started := Time.get_ticks_msec()
		await _drop(0)
		await _wait_until(func() -> bool: return bool(_main.get("is_waiting_to_drop")))
		# A turn takes the drop plus the (here: no) rotation; settle timeouts would add 2-3 s
		print("ScreenshotTour: turn %d took %d ms" % [i + 1, Time.get_ticks_msec() - started])
	var column_count := func() -> int:
		var count := 0
		for chip: Variant in board.grid_state[0]:
			if chip != null:
				count += 1
		return count
	_check(column_count.call() == 6, "six chips fill column 0")
	await _drop(0)
	await _wait(2.0)
	var held: Chip = _main.get("current_chip")
	_check(column_count.call() == 6, "a 7th chip is refused (column still has 6)")
	_check(bool(_main.get("is_waiting_to_drop")) and is_instance_valid(held) and held.freeze, "the 7th chip is still held")
	await _capture("full_column")


## A full board with no four in a row is a draw
func _check_full_board_draw() -> void:
	var board: Board = _main.get("board")
	_main.set("is_against_bot", false)
	_main.call("start_new_game")
	board.board_rotator.set_scripted_rotations(_no_rotations())
	# The same no-lines pattern the bot tests use, leaving one top cell open: pick a column where
	# player 1's last chip doesn't make a line
	var open_column := -1
	var stacks := {}
	for column in range(Board.GRID_SIZE.x):
		var grid: Array = []
		for col in range(Board.GRID_SIZE.x):
			var cells: Array = []
			for row in range(Board.GRID_SIZE.y):
				cells.append(1 if (col + floori(row / 2.0)) % 2 == 0 else 2)
			grid.append(cells)
		grid[column][0] = 0
		var trial := BotBoard.new()
		trial.setup_from_ids(grid)
		var after := trial.simulate_move(BotMove.new(Globals.ChipType.EYE, column), 1)
		if not trial.has_winning_line(1) and not trial.has_winning_line(2) and after.outcome_for(1) == BotBoard.Outcome.DRAW:
			open_column = column
			for col in range(Board.GRID_SIZE.x):
				var stack: Array = []
				for row in range(Board.GRID_SIZE.y - 1, -1, -1):
					if grid[col][row] != 0:
						stack.append(grid[col][row])
				stacks[col] = stack
			break
	_check(open_column >= 0, "found a full board without lines")
	board.load_layout(stacks)
	await _drop(open_column)
	await _wait_until(func() -> bool: return not board.is_busy)
	await _wait(3.0)
	var label: RichTextLabel = _main.get("player_label")
	_check(label.text.contains("tie"), "a full board without lines ends in a tie")
	await _capture("full_board_draw")
	await _wait(3.0)  # Let the game-over pause finish before the next step


## Starting the tutorial while the bot thinks must not let the bot's move leak into lesson 1
func _check_tutorial_during_bot_think() -> void:
	_main.set("is_against_bot", true)
	_main.call("start_new_game")
	await _drop(2)
	await _wait_until(func() -> bool: return int(_main.get("current_player_id")) == 2 and not bool(_main.get("is_waiting_to_drop")))
	_main.call("start_tutorial")
	await _wait(6.0)
	var tutorial: Tutorial = _main.get("tutorial")
	var board: Board = _main.get("board")
	var stray := 0
	for child in _main.get_children():
		if child is Chip:
			stray += 1
	_check(is_instance_valid(tutorial) and int(tutorial.get("_index")) == 0, "tutorial still on lesson 1")
	_check(stray == 0, "no stray chip from the abandoned bot turn")
	_check(board.count_chips(1) + board.count_chips(2) == 7, "board shows exactly the lesson's 7 chips")
	_main.call("finish_tutorial", false)
	await _wait(1.0)


## A real game against the (threaded) bot: it must answer each move
func _play_bot_turns() -> void:
	_main.set("is_against_bot", true)
	_main.call("start_new_game")
	for column: int in [2, 3]:
		await _drop(column)
		var started := Time.get_ticks_msec()
		await _wait_until(func() -> bool: return int(_main.get("current_player_id")) == 1 and bool(_main.get("is_waiting_to_drop")), 30.0)
		print("ScreenshotTour: bot answered in %d ms" % (Time.get_ticks_msec() - started))
	await _wait(0.5)
	await _capture("bot_game")


## Plays the whole tutorial the way a player would, capturing each lesson
func _play_tutorial() -> void:
	_main.call("start_tutorial")
	await _wait(1.0)
	var tutorial: Tutorial = _main.get("tutorial")
	await _capture("tutorial_1_welcome")
	tutorial.call("_on_next_pressed")
	await _wait(0.6)
	await _capture("tutorial_2_drop")
	await _drop(2)
	await _wait_for_step(tutorial, 2)
	await _wait(0.8)
	await _capture("tutorial_3_preview")
	tutorial.call("_on_next_pressed")
	await _drop(3)
	await _wait_for_step(tutorial, 4)
	tutorial.call("_on_next_pressed")
	await _wait(0.8)
	await _capture("tutorial_6_puzzle")
	await _drop(4)  # The winning column
	await _wait_until(func() -> bool: return bool(tutorial.get("_showing_result")))
	await _wait(1.0)
	await _capture("tutorial_6_solved")
	tutorial.call("_on_next_pressed")
	await _wait(0.8)
	await _capture("tutorial_7_bomb")
	await _wait_until(func() -> bool: return bool(_main.get("is_waiting_to_drop")))
	_main.call("toggle_chip_type")
	await _wait(0.6)
	await _capture("tutorial_7_bomb_selected")
	await _drop(2)
	await _wait_for_step(tutorial, 7)
	await _wait_until(func() -> bool: return bool(_main.get("is_waiting_to_drop")))
	_main.call("toggle_chip_type")
	_main.call("toggle_chip_feature")  # Face down
	await _wait(0.6)
	await _capture("tutorial_8_mushroom")
	await _drop(2)
	await _wait_for_step(tutorial, 8)
	await _wait(0.6)
	await _capture("tutorial_9_done")


func _wait_for_step(tutorial: Tutorial, index: int) -> void:
	await _wait_until(func() -> bool: return int(tutorial.get("_index")) == index, 20.0)
	if int(tutorial.get("_index")) != index:
		push_error("ScreenshotTour: tutorial did not reach lesson %d (at %d)" % [index + 1, int(tutorial.get("_index")) + 1])


func _capture_distinct_chips_and_options() -> void:
	var original: bool = Settings.distinct_chips
	Settings.distinct_chips = true
	await _wait(0.4)
	await _capture("game_distinct")
	var pause_screen: PauseScreen = _main.get("pause_screen")
	pause_screen.toggle()
	await _wait(1.0)
	await _capture("menu_in_game")
	pause_screen.show_options()
	await _wait(0.3)
	await _capture("options")
	Settings.distinct_chips = original


func _drop(column: int) -> void:
	await _wait_until(func() -> bool: return bool(_main.get("is_waiting_to_drop")))
	var board: Board = _main.get("board")
	var x := board.global_position.x + Board.column_center_local_x(column)
	var y: float = (_main.call("hold_rect") as Rect2).get_center().y
	_main.call("try_drop_chip", Vector2(x, y))
	await _wait(0.2)


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var size := DisplayServer.window_get_size()
	var path := "%s/%s_%dx%d.png" % [_directory, shot_name, size.x, size.y]
	image.save_png(path)
	print("ScreenshotTour: saved %s" % path)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _wait_until(condition: Callable, timeout: float = 15.0) -> void:
	var waited := 0.0
	while not condition.call() and waited < timeout:
		await _wait(0.1)
		waited += 0.1
