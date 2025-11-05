@tool
class_name PauseScreen
extends Control

## Controls how much the menu is opened. This isn't actually used in the running game
## but it allows us to preview the menu animation in the editor.
@export_range(0, 1.0) var menu_opened_amount := 0.0:
	set = set_menu_opened_amount

## How fast the pause menu opens
@export_range(0.1, 10.0, 0.01, "or_greater") var animation_duration := 2.3

var game_in_progress := false
var is_bot_dumb: bool = false
var _tween: Tween
var _is_currently_opening := false

@onready var blur_color_rect: ColorRect = $BlurColorRect
@onready var info_button: Button = %InfoButton
@onready var info_container: ScrollContainer = $UIPanelContainer/InfoContainer
@onready var info_label: RichTextLabel = $UIPanelContainer/InfoContainer/InfoLabel
@onready var play_friend_button: Button = %PlayFriendButton
@onready var play_bot_button: Button = %PlayBotButton
@onready var quit_button: Button = %QuitButton
@onready var resume_button: Button = %ResumeButton
@onready var ui_panel_container: PanelContainer = $UIPanelContainer
@onready var v_box_container: VBoxContainer = $UIPanelContainer/VBoxContainer
@onready var settings_button: OptionButton = %SettingsButton


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	quit_button.pressed.connect(get_tree().quit)
	info_button.pressed.connect(show_info)
	resume_button.pressed.connect(func() -> void: toggle())
	settings_button.item_selected.connect(_on_settings_button_item_selected)
	info_label.meta_clicked.connect(_on_meta_clicked)
	menu_opened_amount = 0.0
	info_container.visible = false
	info_label.text = Globals.game_info


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if info_container.visible:
			hide_info()
		elif game_in_progress:
			toggle()


## Called when [member menu_opened_amount] is changed.
func set_menu_opened_amount(amount: float) -> void:
	menu_opened_amount = amount
	visible = amount > 0
	# we set the value
	# we ensure the nodes exist (in case the function gets called before _ready)
	if ui_panel_container == null or blur_color_rect == null:
		return
	# we lerp all the values between 0 and 1, the two regular extremes of the
	# menu_opened_amount variable.
	# first, the shader. We set the blur amount and the saturation
	if blur_color_rect.material is ShaderMaterial:
		var shader_material := blur_color_rect.material as ShaderMaterial
		shader_material.set_shader_parameter("blur_amount", lerp(0.0, 1.3, amount))
		shader_material.set_shader_parameter("saturation", lerp(1.0, 0.3, amount))
		shader_material.set_shader_parameter("tint_strength", lerp(0.0, 0.1, amount))
	ui_panel_container.modulate.a = amount
	if not Engine.is_editor_hint():
		get_tree().paused = amount > 0.3


func toggle() -> void:
	play_friend_button.visible = not game_in_progress
	play_bot_button.visible = not game_in_progress
	resume_button.visible = game_in_progress

	# Switch the flag to the opposite value
	_is_currently_opening = not _is_currently_opening

	var duration := animation_duration
	# If there's a tween, and it is animating, we want to kill it.
	# This stops the previous animation.
	if _tween != null:
		if not _is_currently_opening:
			# If the previous tween was animating, we want to animate back
			# from the current point in the animation.
			duration = _tween.get_total_elapsed_time()
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_QUART)

	var target_amount := 1.0 if _is_currently_opening else 0.0
	_tween.tween_property(self, "menu_opened_amount", target_amount, duration)


func show_info() -> void:
	v_box_container.visible = false
	info_container.visible = true


func hide_info() -> void:
	v_box_container.visible = true
	info_container.visible = false


func _on_meta_clicked(meta: Variant) -> void:
	if meta == "back_to_menu":
		hide_info()
	elif typeof(meta) == TYPE_STRING and (meta as String).begins_with("https"):
		OS.shell_open(meta)


func _on_settings_button_item_selected(index: int) -> void:
	is_bot_dumb = settings_button.get_item_id(index) == 1
