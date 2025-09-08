@abstract
class_name Chip
extends RigidBody2D

signal chip_has_settled(chip: Chip)

@export_range(1, 2, 1, "min", "max") var player_id: int = 1

var chip_watcher: ChipWatcher

## Global cursor position to be set by main scene, shared among all chip instances
## Can be used for following the mouse pointer or touch position
static var global_cursor_position: Vector2

@abstract
func get_type() -> Globals.ChipType

@abstract
func set_visual_rotation(angle: float) -> void

## @abtract (optional)
## func toggle_feature() -> void:
## Toggle chip feature (e.g., special ability)
## This optional method that can be implemented in derived classes if the chip has any extra abilities

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# print("Chip is being freed. Run cleanup code.")
		chip_has_settled.emit(self)
		if chip_watcher:
			chip_watcher.queue_free()


## Toggle physics OFF or ON for chip
func disable_physics(val: bool) -> void:
	($CollisionShape2D as CollisionShape2D).disabled = val
	freeze = val
	if val == false:
		global_position.y -= 10  # Move chip up by 10 pixels
		chip_watcher = ChipWatcher.new()
		add_child(chip_watcher)
		chip_watcher.watch([self])
		chip_watcher.all_objects_settled.connect(on_chips_settled)
	else:
		chip_has_settled.emit(self)


## Lock to a chip position node
func lock_into_place(target_pos: Node2D) -> void:
	# Detach from the old parent and attach to the new one
	get_parent().remove_child(self)
	target_pos.add_child(self)
	# Snap to the exact position, ensure face up, freeze
	global_position = target_pos.global_position
	set_visual_rotation(0) #
	freeze = true


func on_chips_settled(chips: Array) -> void:
	# print("Chip has settled or timeout reached.")
	for chip: Chip in chips:
		chip_has_settled.emit(chip)
	if chip_watcher:
			chip_watcher.queue_free()
