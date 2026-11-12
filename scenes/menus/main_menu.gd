extends MenuScreen
class_name MainMenu

func _entries() -> Array[MenuEntry]:
	return [
		MenuEntry.button("PLAY", func(): app.open(PlayMenu.new())),
		# No tutorial yet.
		MenuEntry.button("TUTORIAL", func(): pass).enabled_when(func(): return false),
		MenuEntry.button("OPTIONS", func(): app.open(OptionsMenu.new())),
	]
