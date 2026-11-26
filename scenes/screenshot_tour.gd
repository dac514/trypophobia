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
	return [_capture_distinct_chips_and_options, _play_tutorial]


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
