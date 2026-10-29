extends RefCounted
class_name LayoutConfig

# One screen distribution (horizontal or vertical). Both orientations share
# the same fields, but each keeps its own instance -- so the same element
# can take a different proportion of the screen in each one.
#
# The screen is split along a main axis (X when horizontal, Y when vertical)
# into three bands: the side band (info + playable items), the board zone and
# the scramble zone, which simply takes whatever is left. The side band is
# then split along the other axis into the info zone and the playable items
# zone.
#
#   Horizontal:  [ info / items | scramble | board ]   (left to right)
#   Vertical:    board, scramble, [ info | items ]     (top to bottom)

# Below this the scramble zone has no usable room left for the pieces --
# board_ratio is capped so the three bands never add up past it.
const MIN_SCRAMBLE_RATIO := 0.05

const FIELDS := [
	"side_ratio",
	"board_ratio",
	"info_ratio",
	"margin_ratio",
	"board_fill",
	"items_fill",
	"info_text_scale",
]

# Share of the main axis taken by the side band (horizontal: left column
# width; vertical: bottom row height).
var side_ratio: float = 0.15
# Share of the main axis taken by the board zone.
var board_ratio: float = 0.50
# Share of the side band taken by the info zone, along the other axis
# (horizontal: top of the left column; vertical: left of the bottom row).
var info_ratio: float = 0.40
# Gap between zones (and around the screen edge), as a fraction of the
# screen's smallest dimension.
var margin_ratio: float = 0.02
# How much of the board zone the biggest possible board fills.
var board_fill: float = 1.0
# How much of its slot each playable item (Combiner/Resizer/Divisor) fills.
var items_fill: float = 0.85
# Multiplier over the info texts' auto-fitted font size.
var info_text_scale: float = 1.0

static func from_dict(values: Dictionary) -> LayoutConfig:
	var config := LayoutConfig.new()
	for field in values:
		config.set(field, values[field])
	return config

func scramble_ratio() -> float:
	return 1.0 - side_ratio - effective_board_ratio()

func effective_board_ratio() -> float:
	return clampf(board_ratio, 0.0, 1.0 - side_ratio - MIN_SCRAMBLE_RATIO)

# Ready to paste back over the defaults in game_manager.gd once the debug
# layout panel (F1) has settled on the final values.
func to_code() -> String:
	var parts: PackedStringArray = []
	for field in FIELDS:
		parts.append("\"%s\": %.2f" % [field, get(field)])
	return "LayoutConfig.from_dict({%s})" % ", ".join(parts)
