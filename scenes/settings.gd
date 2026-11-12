extends Node

# Autoload "Settings": the player's choices that outlive a session (the
# options screen, and the last mode and indicator picked on the play
# screen), saved to user:// on every change.

const PATH := "user://settings.cfg"
const SECTION := "settings"

# Locale codes and the names shown in the options screen, in order.
const LANGUAGES := [
	{"locale": "en", "name": "ENGLISH"},
	{"locale": "es", "name": "ESPAÑOL"},
]

const FIELDS := ["quick_difficulty", "language", "game_mode", "places_indicator", "confirm_give_up", "ask_next_level"]

# Difficulty.Level a quick game starts at.
var quick_difficulty: int = Difficulty.Level.EASY:
	set(value):
		quick_difficulty = value
		_save()
# Index into LANGUAGES.
var language: int = 0:
	set(value):
		language = clampi(value, 0, LANGUAGES.size() - 1)
		_apply_language()
		_save()
# GameManager.GameMode last picked on the play screen.
var game_mode: int = 0:
	set(value):
		game_mode = value
		_save()
# The "allowed places indicator" (Memory mode only): highlighting which
# cells a selected piece can go to.
var places_indicator: bool = true:
	set(value):
		places_indicator = value
		_save()

# Whether GIVE UP (daily and infinite games) asks for confirmation first.
var confirm_give_up: bool = true:
	set(value):
		confirm_give_up = value
		_save()

# Infinite mode: whether the score between levels waits for CONTINUE (or
# GIVE UP) instead of moving on by itself.
var ask_next_level: bool = false:
	set(value):
		ask_next_level = value
		_save()

var _loading := false

func _ready() -> void:
	_load()
	_apply_language()

static func language_names() -> Array:
	return LANGUAGES.map(func(language_entry): return language_entry["name"])

func _apply_language() -> void:
	TranslationServer.set_locale(LANGUAGES[language]["locale"])

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	_loading = true
	for field in FIELDS:
		set(field, config.get_value(SECTION, field, get(field)))
	_loading = false

func _save() -> void:
	if _loading or not is_inside_tree():
		return
	var config := ConfigFile.new()
	for field in FIELDS:
		config.set_value(SECTION, field, get(field))
	config.save(PATH)
