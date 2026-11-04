extends RefCounted
class_name GeneralParameters

# The starting point of every difficulty level, shared by both game modes:
# the ranges LevelGenerator's counts are rolled from every round (see roll()).

# How many shapes the solution holds -- a big cell's shape (or a two-colour
# piece) counts once.
var range_shapes: IntRange
# How many active cells are left intentionally empty (an empty big cell
# counts once too).
var range_empty_cells: IntRange
# How many of the shapes are a compound colour (purple, orange, green).
var range_compound_colors: IntRange

static func from_dict(values: Dictionary) -> GeneralParameters:
	var parameters := GeneralParameters.new()
	parameters.range_shapes = IntRange.from_array(values["shapes"])
	parameters.range_empty_cells = IntRange.from_array(values["empty_cells"])
	parameters.range_compound_colors = IntRange.from_array(values["compound_colors"])
	return parameters

# This round's {"shapes", "empty_cells", "compound_colors"}, following both
# rules between the ranges:
#   1. At the minimum shapes, neither of the other two is at its minimum.
#   2. At the maximum shapes, compound colours are neither at their maximum
#      nor one below it.
# A rule that would leave no value at all inside a range (e.g. C[0,1] at the
# maximum shapes) is relaxed to that range's minimum. Shapes and empty cells
# together never go past `capacity` cells, and compound colours never past
# the shapes.
func roll(capacity: int) -> Dictionary:
	var shape_options: Array = range_shapes.values()
	shape_options.shuffle()
	for shapes in shape_options:
		var at_min: bool = shapes == range_shapes.min_value
		var at_max: bool = shapes == range_shapes.max_value
		var empty_excluded: Array = []
		var compound_excluded: Array = []
		if at_min:
			empty_excluded.append(range_empty_cells.min_value)
			compound_excluded.append(range_compound_colors.min_value)
		if at_max:
			compound_excluded.append_array([range_compound_colors.max_value, range_compound_colors.max_value - 1])
		var empties := _allowed(range_empty_cells, empty_excluded).filter(func(e): return shapes + e <= capacity)
		var compounds := _allowed(range_compound_colors, compound_excluded).filter(func(c): return c <= shapes)
		if empties.is_empty() or compounds.is_empty():
			continue
		return {"shapes": shapes, "empty_cells": empties.pick_random(), "compound_colors": compounds.pick_random()}

	push_warning("No shapes/empty cells combination fits %d cells -- using the smallest." % capacity)
	var fallback_shapes: int = mini(range_shapes.min_value, capacity)
	return {
		"shapes": fallback_shapes,
		"empty_cells": clampi(range_empty_cells.min_value, 0, capacity - fallback_shapes),
		"compound_colors": mini(range_compound_colors.min_value, fallback_shapes),
	}

static func _allowed(values_range: IntRange, excluded: Array) -> Array:
	var allowed: Array = values_range.values().filter(func(v): return not excluded.has(v))
	if allowed.is_empty():
		allowed = [values_range.min_value]
	return allowed
