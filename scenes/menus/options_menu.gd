extends MenuScreen
class_name OptionsMenu

func _entries() -> Array[MenuEntry]:
	return [
		MenuEntry.selector("Default difficulty for quick game", Difficulty.level_display_names(),
			func(): return Settings.quick_difficulty,
			func(index): Settings.quick_difficulty = index),
		MenuEntry.selector("Language", Settings.language_names(),
			func(): return Settings.language,
			func(index): Settings.language = index),
		MenuEntry.checkbox("ASK BEFORE GIVING UP",
			func(): return Settings.confirm_give_up,
			func(on): Settings.confirm_give_up = on),
		MenuEntry.checkbox("ASK BEFORE NEXT LEVEL",
			func(): return Settings.ask_next_level,
			func(on): Settings.ask_next_level = on),
	]
