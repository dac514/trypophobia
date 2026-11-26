extends Node

## Player preferences, saved to user://settings.cfg. Autoloaded as "Settings".
##
## Read with the typed properties; writing one saves the file and emits `changed` with its key.

signal changed(key: String)

const PATH = "user://settings.cfg"

const DISTINCT_CHIPS = "a11y/distinct_chips"
const DIFFICULTY = "game/difficulty"
const TUTORIAL_COMPLETED = "tutorial/completed"
## Reserved for the upcoming volume sliders (0.0 to 1.0)
const MUSIC_VOLUME = "audio/music"
const SFX_VOLUME = "audio/sfx"

const DEFAULTS = {
	DISTINCT_CHIPS: false,
	DIFFICULTY: Globals.Difficulty.HARD,
	TUTORIAL_COMPLETED: false,
	MUSIC_VOLUME: 1.0,
	SFX_VOLUME: 1.0,
}

## Easier-to-tell-apart chips: red pupils for player 2 and a coloured rim on every chip
var distinct_chips: bool:
	get:
		return bool(get_value(DISTINCT_CHIPS))
	set(value):
		set_value(DISTINCT_CHIPS, value)

var difficulty: Globals.Difficulty:
	get:
		return int(get_value(DIFFICULTY)) as Globals.Difficulty
	set(value):
		set_value(DIFFICULTY, value)

var tutorial_completed: bool:
	get:
		return bool(get_value(TUTORIAL_COMPLETED))
	set(value):
		set_value(TUTORIAL_COMPLETED, value)

var _config := ConfigFile.new()


func _init() -> void:
	# A missing or unreadable file just means defaults
	_config.load(PATH)


func get_value(key: String) -> Variant:
	var parts := key.split("/")
	return _config.get_value(parts[0], parts[1], DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if get_value(key) == value:
		return
	var parts := key.split("/")
	_config.set_value(parts[0], parts[1], value)
	var error := _config.save(PATH)
	if error != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, error])
	changed.emit(key)
