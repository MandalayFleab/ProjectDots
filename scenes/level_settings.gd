extends RefCounted
class_name LevelSettings

# Everything LevelGenerator randomizes a level from. Each game mode keeps its
# own instance (see game_manager.gd), so Memory and Puzzle can generate
# boards of different sizes and difficulty.

var min_rows: int = 3
var max_rows: int = 5
var min_columns: int = 3
var max_columns: int = 5
# How many shapes a level holds in total, whatever their size or colour (a
# big cell's shape counts once), picked at random within this range every
# round.
var min_shapes: int = 2
var max_shapes: int = 5
# How many of those shapes are a combined colour (purple, orange, green),
# at either size -- the rest are primaries (red, yellow, blue).
var min_combined_color_shapes: int = 0
var max_combined_color_shapes: int = 1
# Most normal cells left intentionally empty (only when there's no empty
# big cell already acting as the trap).
var max_slack: int = 4
var max_filled_big_cells: int = 4

static func from_dict(values: Dictionary) -> LevelSettings:
	var settings := LevelSettings.new()
	for field in values:
		settings.set(field, values[field])
	return settings
