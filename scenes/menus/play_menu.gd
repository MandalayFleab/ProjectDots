extends MenuScreen
class_name PlayMenu

# The game mode switch, one button per play type, and the allowed places
# indicator. An option that only makes sense in one mode just needs
# .shown_when(func(): return Settings.game_mode == GameManager.GameMode.X)
# -- changing the switch refreshes the whole menu.

func _entries() -> Array[MenuEntry]:
	return [
		MenuEntry.switch(["MEMORY", "PUZZLE"],
			func(): return Settings.game_mode,
			func(index): Settings.game_mode = index),
		MenuEntry.button("DAILY GAME", _start.bind(GameSetup.PlayType.DAILY)),
		MenuEntry.button("QUICK GAME", _start.bind(GameSetup.PlayType.QUICK)),
		MenuEntry.button("INFINITE MODE", _start.bind(GameSetup.PlayType.INFINITE)),
		# Memory only: Puzzle is always played without it.
		MenuEntry.checkbox("ALLOWED PLACES INDICATOR",
			func(): return Settings.places_indicator,
			func(on): Settings.places_indicator = on) \
			.shown_when(func(): return Settings.game_mode == GameManager.GameMode.MEMORY),
	]

func _start(play_type: GameSetup.PlayType) -> void:
	app.start_game(GameSetup.from_settings(play_type))
