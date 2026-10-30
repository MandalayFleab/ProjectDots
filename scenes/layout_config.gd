extends RefCounted
class_name LayoutConfig

# One screen distribution (horizontal or vertical). Both orientations share
# the same fields, but each keeps its own instance -- so the same element
# can take a different proportion of the screen in each one.
#
# The screen is split along a main axis (X when horizontal, Y when vertical)
# into three bands: the side band (menu + playable items), the board zone and
# the scramble zone, which simply takes whatever is left. The side band is
# then split along the other axis into the menu zone and the playable items
# zone. The info zone (timer above counter, left-aligned) is a strip across
# the top of the scramble zone when horizontal -- one top row with the menu,
# at the same height. When vertical, the bottom band is the items across its
# full width over a last row with the menu and the info side by side.
#
#   Horizontal:  [ menu / items | info / scramble | board ]   (left to right)
#   Vertical:    board, scramble, items, [ menu | info ]      (top to bottom)

# Below this the scramble zone has no usable room left for the pieces --
# board_ratio is capped so the three bands never add up past it.
const MIN_SCRAMBLE_RATIO := 0.05

const FIELDS := [
	"side_ratio",
	"board_ratio",
	"menu_ratio",
	"info_ratio",
	"margin_ratio",
	"board_fill",
	"items_fill",
	"info_text_scale",
	"preview_ratio",
]

# Share of the main axis taken by the side band (horizontal: left column
# width; vertical: bottom band height, items + menu/info row).
var side_ratio: float = 0.15
# Share of the main axis taken by the board zone.
var board_ratio: float = 0.50
# Horizontal: share of the left column's height taken by the menu zone (the
# info zone's height too). Vertical: share of the last row's width taken by
# the menu zone (the info zone gets the rest).
var menu_ratio: float = 0.15
# Vertical only: share of the bottom band's height taken by its last row
# (menu + info), below the items.
var info_ratio: float = 0.08
# Gap between zones (and around the screen edge), as a fraction of the
# screen's smallest dimension.
var margin_ratio: float = 0.02
# How much of the board zone the biggest possible board fills.
var board_fill: float = 1.0
# How much of its slot each playable item (ShapeShifter/Divisor) fills.
var items_fill: float = 0.85
# Multiplier over the auto-fitted font size of every text (info, menu
# buttons, result).
var info_text_scale: float = 1.0
# Puzzle mode's solution preview: its slot's share of the playable items
# zone's length (the ShapeShifter/Divisor split the rest). Reserved in
# every mode, left empty in Memory, so the items never move between modes.
var preview_ratio: float = 0.35

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
