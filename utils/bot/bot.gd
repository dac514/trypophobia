class_name Bot
extends Node

signal best_move(best_move: BotMove)

var worker: BotWorker = null


## Starts thinking on a worker thread; emits best_move when done (null if the board is full).
## Everything the worker needs is copied here, on the main thread, so it never touches nodes.
func find_best_move(
	grid_state: Array, player_id: int, chip_inventory: Dictionary, next_rotation_states: Array, difficulty: Globals.Difficulty
) -> void:
	if worker and worker.is_alive():
		print("Bot: Still thinking...")
		return

	var board := BotBoard.new()
	board.setup(grid_state)
	var rotations: Array = []
	for state: Dictionary in next_rotation_states:
		rotations.append({"direction": int(state.get("direction", 0)), "degrees": int(state.get("degrees", 0))})

	worker = BotWorker.new(board, player_id, chip_inventory.duplicate(true), rotations, difficulty)
	worker.connect("bot_worker_finished", _on_bot_worker_finished)
	worker.start(worker.run)


func _on_bot_worker_finished(move: BotMove) -> void:
	best_move.emit(move)
