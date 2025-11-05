class_name BoardRotator
extends Node2D

signal board_has_settled(chips: Array[Chip])

enum RotationDirection { LEFT = -1, RIGHT = 1 }
enum RotationAmount { DEG_90 = 90, DEG_180 = 180 }

var chip_watcher: ChipWatcher
var possible_rotation_states: Array[Dictionary] = [
	{"direction": RotationDirection.RIGHT, "degrees": RotationAmount.DEG_90, "weight": 1},
	{"direction": RotationDirection.LEFT, "degrees": RotationAmount.DEG_90, "weight": 1},
	{"direction": RotationDirection.RIGHT, "degrees": RotationAmount.DEG_180, "weight": 2},
	{"direction": RotationDirection.LEFT, "degrees": RotationAmount.DEG_180, "weight": 2},
	{"direction": 0, "degrees": 0, "weight": 4},
]
var next_rotation_states: Array[Dictionary] = []

var _chips_in_progress: Array[Chip] = []

@onready var board_rotator: BoardRotator = %BoardRotator
@onready var chip_positions: Node2D = %ChipPositions


func _ready() -> void:
	_prepare_rotation_states()
	next_rotation_states.pop_front()


## Rotate the board and settle the chips
func rotate_and_settle() -> void:
	# Prepare the chips for rotation
	_prepare_rotation_states()
	_prepare_chips()
	var state: Dictionary = next_rotation_states.pop_front()
	# Disable physics so that when the board rotates, the chips don't colide with anything
	_disable_physics(true)
	await _rotate_board_animation(state.direction, state.degrees)
	# Let the chips fall
	_disable_physics(false)
	# Wait for the chips to stop falling
	if _chips_in_progress.size():
		chip_watcher = ChipWatcher.new()
		add_child(chip_watcher)
		chip_watcher.watch(_chips_in_progress, 2.0)
		chip_watcher.all_objects_settled.connect(_on_chips_settled)
	else:
		await get_tree().create_timer(1.0).timeout
		_on_chips_settled(_chips_in_progress)


# Prepare the next rotation states, uses probability weights
func _prepare_rotation_states() -> void:
	while next_rotation_states.size() < 4:
		var total_weight := 0
		for state in possible_rotation_states:
			total_weight += state.weight
		var pick := randi() % total_weight
		for state in possible_rotation_states:
			pick -= state.weight
			if pick < 0:
				next_rotation_states.append(state)
				break


func _prepare_chips() -> void:
	_chips_in_progress = []
	for pos_node in chip_positions.get_children():
		for child in pos_node.get_children():
			if child is Chip:
				# Detach chip from current position and put in BoardRotator
				var current_global_pos: Vector2 = (child as Chip).global_position
				pos_node.remove_child(child)
				board_rotator.add_child(child)
				(child as Chip).global_position = current_global_pos
				_chips_in_progress.append(child)


## Toggle physics OFF or ON for entire board
func _disable_physics(val: bool) -> void:
	for chip in _chips_in_progress:
		if is_instance_valid(chip):
			chip.disable_physics(val)
			chip.set_sleeping(val)


func _rotate_board_animation(direction: int = RotationDirection.RIGHT, degrees: int = RotationAmount.DEG_90) -> void:
	# Scale duration so rotation speed is constant
	var rotation_speed := 0.4 / RotationAmount.DEG_90  # seconds per 90 degrees
	var duration: float = rotation_speed * abs(degrees)
	var target_rotation := board_rotator.rotation_degrees + direction * degrees
	var rotation_tween := create_tween()
	rotation_tween.tween_method(
		func(angle: float) -> void:
			board_rotator.rotation_degrees = angle
			_update_chip_visuals(),
		board_rotator.rotation_degrees,
		target_rotation,
		duration
	)
	await rotation_tween.finished
	# Shake tween
	var shake_tween := create_tween()
	var original_pos := board_rotator.position
	shake_tween.tween_property(board_rotator, "position", original_pos + Vector2(-10, 0), 0.05)
	shake_tween.tween_property(board_rotator, "position", original_pos + Vector2(10, 0), 0.05)
	shake_tween.tween_property(board_rotator, "position", original_pos, 0.05)
	await shake_tween.finished


func _update_chip_visuals() -> void:
	var valid_chips: Array[Chip] = []
	for chip in _chips_in_progress:
		if is_instance_valid(chip):
			valid_chips.append(chip)
			chip.set_visual_rotation(board_rotator.rotation)
	_chips_in_progress = valid_chips


func _on_chips_settled(chips: Array) -> void:
	print("Board has settled or timeout reached.")
	board_has_settled.emit(chips)
	if chip_watcher:
		chip_watcher.queue_free()
