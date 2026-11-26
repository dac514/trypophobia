class_name OptionsPanel
extends VBoxContainer

## The Options page of the menu. It is built in code so every section and row shares the same
## spacing. Add new settings as rows in a section, e.g. the music and sound effect volume sliders:
##
##     var audio := _add_section("SOUND")
##     _add_row(audio, "Music", _make_slider(Settings.MUSIC_VOLUME))

signal back_pressed
signal rules_pressed

const TITLE_FONT_SIZE := 30
const SECTION_FONT_SIZE := 17
const ROW_FONT_SIZE := 24
const HINT_FONT_SIZE := 16
const BUTTON_FONT_SIZE := 32
const SECTION_GAP := 18
const ROW_GAP := 10
const SECTION_COLOR := Color("dba8ea")
const HINT_COLOR := Color(1.0, 1.0, 1.0, 0.7)

var _distinct_toggle: CheckButton
var _shimmer_toggle: CheckButton
var _preview: ChipPairPreview


func _ready() -> void:
	add_theme_constant_override("separation", SECTION_GAP)

	var title := Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	add_child(title)

	var accessibility := _add_section("ACCESSIBILITY")
	_distinct_toggle = _make_toggle("Distinct player chips", Settings.DISTINCT_CHIPS)
	accessibility.add_child(_distinct_toggle)
	_preview = ChipPairPreview.new()
	accessibility.add_child(_preview)
	accessibility.add_child(_make_hint("Red pupils and coloured rims make each player's chips easy to tell apart."))
	_shimmer_toggle = _make_toggle("Board shimmer", Settings.BOARD_SHIMMER)
	accessibility.add_child(_shimmer_toggle)
	accessibility.add_child(_make_hint("The light that sweeps across the board. Switch it off if it's distracting."))

	var about := _add_section("ABOUT")
	about.add_child(_make_button("Rules & Credits", rules_pressed.emit))

	add_child(_make_button("Back", back_pressed.emit))

	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed(key: String) -> void:
	if key == Settings.DISTINCT_CHIPS:
		_distinct_toggle.set_pressed_no_signal(Settings.distinct_chips)
		_preview.queue_redraw()
	elif key == Settings.BOARD_SHIMMER:
		_shimmer_toggle.set_pressed_no_signal(Settings.board_shimmer)


## An on/off switch bound to a boolean setting
func _make_toggle(text: String, setting_key: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	toggle.button_pressed = bool(Settings.get_value(setting_key))
	toggle.toggled.connect(func(on: bool) -> void: Settings.set_value(setting_key, on))
	return toggle


## A titled group of rows
func _add_section(title: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", ROW_GAP)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	label.add_theme_color_override("font_color", SECTION_COLOR)
	section.add_child(label)
	add_child(section)
	return section


func _make_hint(text: String) -> Label:
	var hint := Label.new()
	hint.text = text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 300.0
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.add_theme_color_override("font_color", HINT_COLOR)
	return hint


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.pressed.connect(on_pressed)
	return button


## A player 1 and a player 2 eye side by side, drawn exactly as on the board, so the effect of the
## "distinct player chips" option is visible right where it's switched.
class ChipPairPreview:
	extends Control

	const CHIP_SCALE := 0.75
	const NAMES := {1: "Player 1", 2: "Player 2"}

	func _init() -> void:
		custom_minimum_size = Vector2(300.0, 100.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := get_theme_default_font()
		for player_id: int in [1, 2]:
			var center := Vector2(size.x * (0.27 if player_id == 1 else 0.73), 40.0)
			draw_set_transform(center, 0.0, Vector2(CHIP_SCALE, CHIP_SCALE))
			var eye: Texture2D = ChipEye.EYE_BG
			var pupil := ChipEye.pupil_texture(player_id)
			draw_texture_rect(eye, Rect2(-eye.get_size() / 4.0, eye.get_size() / 2.0), false)
			draw_texture_rect(pupil, Rect2(-pupil.get_size() / 4.0, pupil.get_size() / 2.0), false)
			if Settings.distinct_chips:
				ChipRim.draw_rim(self, Vector2.ZERO, player_id)
			draw_set_transform(Vector2.ZERO)
			var label: String = NAMES[player_id]
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, Vector2(center.x - width / 2.0, size.y - 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
