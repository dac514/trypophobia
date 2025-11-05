class_name ChipEye
extends Chip

signal animate_ghost_finished
signal animate_explode_finished

const EYE_BG = preload("res://assets/Googli-1-2x.png")
const PUPIL_TEXTURES = {1: preload("res://assets/Googli-Black-2x.png"), 2: preload("res://assets/Googli-Green-2x.png")}

var current_jiggle := 0
var max_jiggles := 12
var pupil_radius := 16
var jiggling := false

@onready var eye: Sprite2D = $EyeBackground
@onready var pupil: Sprite2D = $Pupil
@onready var jiggle_timer: Timer = $JiggleTimer


func _ready() -> void:
	update_texture()
	jiggle_timer.connect("timeout", func() -> void: jiggling = false)


func get_type() -> Globals.ChipType:
	return Globals.ChipType.EYE


func follow_pointer(pos: Vector2) -> void:
	var local_mouse := to_local(pos)
	var eye_center := eye.position
	var offset := local_mouse - eye_center
	if offset.length() > pupil_radius:
		offset = offset.normalized() * pupil_radius
	pupil.position = eye_center + offset


func set_visual_rotation(angle: float) -> void:
	eye.rotation = -angle
	pupil.rotation = -angle


func update_texture() -> void:
	eye.texture = EYE_BG
	pupil.texture = PUPIL_TEXTURES[player_id]


func animate_explode() -> void:
	eye.visible = false
	pupil.visible = false
	var explode_anim: AnimatedSprite2D = get_node("ExplosionAnim")
	explode_anim.visible = true
	explode_anim.play("explode")
	explode_anim.animation_finished.connect(func() -> void: animate_explode_finished.emit(), CONNECT_ONE_SHOT)


func animate_ghost() -> void:
	eye.visible = false
	pupil.visible = false
	var ghost_anim: AnimatedSprite2D = get_node("GhostAnim")
	ghost_anim.visible = true
	ghost_anim.play("ghost")
	ghost_anim.animation_finished.connect(func() -> void: animate_ghost_finished.emit(), CONNECT_ONE_SHOT)


func _physics_process(_delta: float) -> void:
	if linear_velocity.length() > 10 and not freeze:
		_start_jiggling()
	if jiggling and not freeze and current_jiggle < max_jiggles:
		_jiggle_pupil()
	else:
		follow_pointer(global_cursor_position)


func _jiggle_pupil() -> void:
	var eye_center := eye.position
	var offset := linear_velocity / 20.0
	if offset.length() > pupil_radius:
		offset = offset.normalized() * pupil_radius
	pupil.position = eye_center + offset
	current_jiggle += 1


func _start_jiggling() -> void:
	current_jiggle = 0
	jiggling = true
	jiggle_timer.stop()  # Stop any running timer
	jiggle_timer.start()  # Always restart for a fresh 0.25s


func _on_jiggle_timeout() -> void:
	jiggling = false
