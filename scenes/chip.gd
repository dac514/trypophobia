@abstract class_name Chip
extends RigidBody2D

signal chip_has_settled(chip: Chip)

## Global cursor position to be set by main scene, shared among all chip instances
## Can be used for following the mouse pointer or touch position
static var global_cursor_position: Vector2

@export_range(1, 2, 1, "min", "max") var player_id: int = 1

var chip_watcher: ChipWatcher

var _rim: ChipRim

@abstract func get_type() -> Globals.ChipType

@abstract func set_visual_rotation(angle: float) -> void


## Updates the chip's look for its player and the "distinct player chips" setting
func refresh_look() -> void:
	if _rim:
		_rim.refresh()


## Hides the ownership ring, e.g. while the chip explodes or gets eaten
func hide_rim() -> void:
	if _rim:
		_rim.queue_free()
		_rim = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		# Runs after the chip's own _ready, so the ring is the last child and draws on top
		_rim = ChipRim.new()
		add_child(_rim)
		Settings.changed.connect(_on_settings_changed)
	if what == NOTIFICATION_PREDELETE:
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
	set_visual_rotation(0)  #
	freeze = true


func _on_settings_changed(key: String) -> void:
	if key == Settings.DISTINCT_CHIPS:
		refresh_look()


func on_chips_settled(chips: Array) -> void:
	for chip: Chip in chips:
		chip_has_settled.emit(chip)
	if chip_watcher:
		chip_watcher.queue_free()
