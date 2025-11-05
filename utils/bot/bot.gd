class_name Bot
extends Node

signal best_move(best_move: BotMove)

var worker: BotWorker = null


func find_best_move(
	grid_state: Array,
	player_id: int,
	chip_inventory: Dictionary,
	next_rotation_states: Array,
	is_bot_dumb: bool
) -> void:
	if worker and worker.is_alive():
		print("Bot: Still thinking...")
		return

	worker = BotWorker.new(grid_state, player_id, chip_inventory, next_rotation_states, is_bot_dumb)
	worker.connect("bot_worker_finished", _on_bot_worker_finished)
	worker.start(worker.run)


func _on_bot_worker_finished(move: BotMove) -> void:
	best_move.emit(move)
