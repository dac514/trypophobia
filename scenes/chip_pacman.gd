class_name ChipPacman
extends Chip

const PACMAN_BG = preload("res://assets/mushchomp-2x.png")

var rotation_direction: String = "right"
var rotate_duration: float = 0.3

@onready var munching_area: Area2D = $MunchingArea
@onready var pacman: Sprite2D = $PacmanBackground


func _ready() -> void:
	pacman.texture = PACMAN_BG


func get_type() -> Globals.ChipType:
	return Globals.ChipType.PACMAN


func set_visual_rotation(angle: float) -> void:
	pacman.rotation = -angle


func on_chips_settled(chips: Array) -> void:
	var chips_to_eat: Array[ChipEye] = []
	for body in munching_area.get_overlapping_bodies():
		if body is ChipEye and body != self and body not in chips_to_eat:
			chips_to_eat.append(body)
	await _eat_all(chips_to_eat)
	super.on_chips_settled(chips)
	# chip_has_settled.emit(self)
	queue_free()


func _eat_all(chips_to_eat: Array[ChipEye]) -> void:
	# Pacman munching animation
	var tween := self.create_tween()
	tween.set_loops()
	(
		tween
		. tween_property(self, "scale", Vector2(1.2, 0.8), 0.09)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		tween
		. tween_property(self, "scale", Vector2(0.9, 1.2), 0.08)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	# Chips to eat
	for i in chips_to_eat.size():
		var chip: ChipEye = chips_to_eat[i]
		var is_last := i == chips_to_eat.size() - 1
		chip.animate_ghost()
		if is_last:
			await chip.animate_ghost_finished
	for chip in chips_to_eat:
		chip.queue_free()
	# Stop pacman munching animation
	tween.kill()


# Rotate pacman chip to face a direction
func rotate_to_direction(direction: String) -> void:
	var target_angle: float
	match direction:
		"up":
			target_angle = -PI / 2
		"left":
			target_angle = PI
		"down":
			target_angle = PI / 2
		_:
			target_angle = 0.0

	var current_angle := fposmod(pacman.rotation, TAU)
	var new_target_angle := fposmod(target_angle, TAU)

	var diff := new_target_angle - current_angle
	if diff < 0:
		diff += TAU

	var final_angle := pacman.rotation + diff

	var tween := create_tween()
	tween.tween_property(pacman, "rotation", final_angle, rotate_duration)
	tween.parallel().tween_property(munching_area, "rotation", final_angle, rotate_duration)
	tween.tween_callback(func() -> void: _normalize_angles())


# Normalize angles to stay within 0 to TAU range
func _normalize_angles() -> void:
	pacman.rotation = fmod(pacman.rotation, TAU)
	munching_area.rotation = fmod(munching_area.rotation, TAU)


# Pacman can rotate in 4 directions
func toggle_feature() -> void:
	var current_direction := rotation_direction
	match current_direction:
		"up":
			rotation_direction = "right"
		"left":
			rotation_direction = "up"
		"down":
			rotation_direction = "left"
		_:
			rotation_direction = "down"

	rotate_to_direction(rotation_direction)
