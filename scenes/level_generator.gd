class_name LevelGenerator
extends RefCounted

# Every level is laid out on the same BOARD_SIZE x BOARD_SIZE grid -- only
# the cells holding a shape or left intentionally empty are active (visible),
# the rest stay inactive.
const BOARD_SIZE := 5
const BOARD_CELLS := BOARD_SIZE * BOARD_SIZE
# The most 2x2 big cells (filled or empty) a level can have.
const MAX_BIG_CELLS := 4
# Extra grid cells a big cell takes over a normal one (4 instead of 1).
const BIG_CELL_EXTRA := 3

# Rolls this round's counts from the general parameters (see
# GeneralParameters.roll()) and lays them out.
static func generate(parameters: GeneralParameters) -> LevelData:
	var counts := parameters.roll(BOARD_CELLS)
	return generate_counts(counts["shapes"], counts["empty_cells"], counts["compound_colors"])

# Exactly shape_count shapes (a big cell's counts once), compound_count of
# them in a compound colour, and empty_count cells left intentionally empty
# (an empty big cell counts once too). shape_count + empty_count must fit
# in BOARD_CELLS.
static func generate_counts(shape_count: int, empty_count: int, compound_count: int) -> LevelData:
	var rows := BOARD_SIZE
	var columns := BOARD_SIZE

	var level := LevelData.new()
	level.rows = rows
	level.columns = columns
	level.max_dimension = BOARD_SIZE
	level.cells = []
	for i in rows * columns:
		level.cells.append({"kind": LevelData.CellKind.INACTIVE, "spec": null})

	# Each big cell takes BIG_CELL_EXTRA more grid cells than a normal one
	# would -- capped so they always leave room for every shape and empty cell.
	var spare: int = BOARD_CELLS - shape_count - empty_count
	var filled_big_cell_count: int = randi_range(0, mini(mini(MAX_BIG_CELLS, shape_count), maxi(spare, 0) / BIG_CELL_EXTRA))
	spare -= filled_big_cell_count * BIG_CELL_EXTRA
	var empty_big_cell_count: int = 0
	if empty_count > 0 and filled_big_cell_count < MAX_BIG_CELLS and spare >= BIG_CELL_EXTRA:
		empty_big_cell_count = randi_range(0, 1)

	var anchors: Array[Vector2i] = []
	var attempts := 0
	while anchors.size() < filled_big_cell_count + empty_big_cell_count and attempts < 60:
		attempts += 1
		var r := randi_range(0, rows - 2)
		var c := randi_range(0, columns - 2)
		if not _overlaps_existing(r, c, anchors):
			anchors.append(Vector2i(r, c))

	# Placement can fall short if the grid is tight; recompute actual counts
	# from what fit -- a big cell that didn't fit just becomes a normal one,
	# which always takes less room.
	filled_big_cell_count = mini(filled_big_cell_count, anchors.size())
	empty_big_cell_count = anchors.size() - filled_big_cell_count

	var free_indices: Array = []
	for i in level.cells.size():
		var row: int = i / columns
		var column: int = i % columns
		if not anchors.any(func(a): return row - a.x in [0, 1] and column - a.y in [0, 1]):
			free_indices.append(i)
	free_indices.shuffle()

	# Only fewer than asked if the grid itself is too small for it.
	shape_count = mini(shape_count, filled_big_cell_count + free_indices.size())
	var specs := _random_specs(shape_count, compound_count)

	for i in anchors.size():
		var anchor := anchors[i]
		var spec: PieceSpec = specs.pop_back() if i < filled_big_cell_count else null
		var idx := _index(anchor.x, anchor.y, columns)
		level.cells[idx] = {"kind": LevelData.CellKind.BIG_ANCHOR, "spec": spec}
		for dr in range(2):
			for dc in range(2):
				if dr == 0 and dc == 0:
					continue
				level.cells[_index(anchor.x + dr, anchor.y + dc, columns)] = {"kind": LevelData.CellKind.BIG_OCCUPIED, "spec": null}

	# Shapes first, so a tight grid drops intentionally empty cells rather
	# than required shapes.
	var cursor := 0
	while not specs.is_empty():
		level.cells[free_indices[cursor]] = {"kind": LevelData.CellKind.NORMAL, "spec": specs.pop_back()}
		cursor += 1

	var normal_empty_count: int = mini(empty_count - empty_big_cell_count, free_indices.size() - cursor)
	for i in normal_empty_count:
		level.cells[free_indices[cursor]] = {"kind": LevelData.CellKind.NORMAL, "spec": null}
		cursor += 1

	# What gets scrambled: every required piece broken down into its primary
	# units, which PieceDecomposer.random_disposition() then regroups.
	level.shapes_to_place = []
	for cell in level.cells:
		if cell["spec"] == null:
			continue
		if cell["kind"] == LevelData.CellKind.BIG_ANCHOR:
			level.shapes_to_place.append_array(PieceDecomposer.to_units(cell["spec"], true))
		elif cell["kind"] == LevelData.CellKind.NORMAL:
			level.shapes_to_place.append_array(PieceDecomposer.to_units(cell["spec"], false))
	level.disposition = PieceDecomposer.random_disposition(level.shapes_to_place)

	return level

static func _index(r: int, c: int, columns: int) -> int:
	return r * columns + c

static func _overlaps_existing(r: int, c: int, anchors: Array[Vector2i]) -> bool:
	for a in anchors:
		if abs(a.x - r) < 2 and abs(a.y - c) < 2:
			return true
	return false

# count shapes in random order (so big and normal cells share the mixes),
# combined_count of them in a mixed colour -- capped at count -- and the
# rest in a primary one.
static func _random_specs(count: int, combined_count: int) -> Array[PieceSpec]:
	var specs: Array[PieceSpec] = []
	for i in count:
		specs.append(_random_spec(i < combined_count))
	specs.shuffle()
	return specs

static func _random_spec(mixed: bool) -> PieceSpec:
	var colors: Array = Shapes.PieceColor.values().filter(func(c): return Shapes.is_primary(c) != mixed)
	return PieceSpec.new(Shapes.Type.values().pick_random(), colors.pick_random())
