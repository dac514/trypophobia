class_name ChipBomb
extends Chip

const BOMB_BG = preload("res://assets/bomb-2x.png")

@onready var exploding_area: Area2D = $ExplodingArea
@onready var bomb: Sprite2D = $BombBackground

func _ready() -> void:
	bomb.texture = BOMB_BG


func get_type() -> Globals.ChipType:
	return Globals.ChipType.BOMB


func set_visual_rotation(angle: float) -> void:
	bomb.rotation = -angle


func on_chips_settled(chips: Array) -> void:
	var chips_to_explode: Array[ChipEye] = []
	for body in exploding_area.get_overlapping_bodies():
		if body is ChipEye and body != self and body not in chips_to_explode:
			chips_to_explode.append(body)
	await _explode_all(chips_to_explode)
	super.on_chips_settled(chips)
	# chip_has_settled.emit(self)
	queue_free()


func _explode_all(chips_to_explode: Array[ChipEye]) -> void:
	for i in chips_to_explode.size():
		var chip: ChipEye = chips_to_explode[i]
		var is_last := i == chips_to_explode.size() - 1
		chip.animate_explode()
		if is_last:
			await chip.animate_explode_finished
	for chip in chips_to_explode:
		chip.queue_free()
