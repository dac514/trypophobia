extends Node

enum RotationDirection { LEFT = -1, RIGHT = 1 }
enum RotationAmount { DEG_90 = 90, DEG_180 = 180 }

# Simple test to verify BotBoard works correctly
func _ready():
	print("Testing BotBoard...")
	test_botboard()

func test_botboard() -> void:
	# Create a sample grid state with some chips
	var grid_state: Array = []
	for col in range(6):
		var column: Array = []
		for row in range(6):
			if col % 2 == 0:
				var chip := ChipEye.new()
				chip.player_id = 1
				column.append(chip)
			if col % 3 == 0:
				var chip := ChipEye.new()
				chip.player_id = 0
				column.append(chip)
			else:
				var chip := ChipEye.new()
				chip.player_id = 2
				column.append(chip)

		grid_state.append(column)

	# Test BotBoard creation
	var board = BotBoard.new(grid_state)
	print("BotBoard created successfully!")
	print("Chip count: ", board.chip_count)
	print("Valid moves: ", board.get_valid_moves().size())
	# board.print_ascii_grid()

	var possible_rotation_states: Array[Dictionary] = [
		{"direction": RotationDirection.RIGHT, "degrees": RotationAmount.DEG_90, "weight": 1},
		{"direction": RotationDirection.LEFT, "degrees": RotationAmount.DEG_90, "weight": 1},
		{"direction": RotationDirection.RIGHT, "degrees": RotationAmount.DEG_180, "weight": 2},
		{"direction": RotationDirection.LEFT, "degrees": RotationAmount.DEG_180, "weight": 2},
		{"direction": 0, "degrees": 0, "weight": 4},
	]

	# Test rotation
	board.simulate_rotation(possible_rotation_states[0])
	board.print_ascii_grid()
	board.simulate_rotation(possible_rotation_states[0])
	board.print_ascii_grid()
	board.simulate_rotation(possible_rotation_states[0])
	board.print_ascii_grid()
	board.simulate_rotation(possible_rotation_states[0])
	board.print_ascii_grid()


	## Test duplication
	#var board_copy = board.duplicate()
	#print("BotBoard duplicated successfully!")
	#board_copy.print_ascii_grid()
#
	## Test move simulation
	#var move = BotMove.new(Globals.ChipType.PACMAN, 3, Globals.ChipDirection.UP)
	#var new_board = board.simulate_move(move,2)
	#print("Move simulation completed successfully!")
	#new_board.print_ascii_grid()
