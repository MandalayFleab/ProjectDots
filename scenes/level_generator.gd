class_name LevelGenerator
extends RefCounted

static func generate(settings: LevelSettings) -> LevelData:
	var rows := randi_range(settings.min_rows, settings.max_rows)
	var columns := randi_range(settings.min_columns, settings.max_columns)

	var level := LevelData.new()
	level.rows = rows
	level.columns = columns
	level.max_dimension = maxi(settings.max_rows, settings.max_columns)
	level.cells = []
	for i in rows * columns:
		level.cells.append({"kind": LevelData.CellKind.INACTIVE, "spec": null})

	# Every shape counts once towards the total, whatever its size or colour
	# -- a big cell's shape included.
	var shape_count: int = randi_range(settings.min_shapes, settings.max_shapes)
	var free_room: int = rows * columns - shape_count

	# A filled big cell takes 4 grid cells for 1 shape (3 more than a normal
	# cell would), an empty one 4 -- capped so the big cells always leave
	# room for every shape.
	var max_blocks: int = (rows / 2) * (columns / 2)
	var max_filled: int = mini(mini(settings.max_filled_big_cells, max_blocks), mini(shape_count, maxi(free_room, 0) / 3))
	var filled_big_cell_count: int = randi_range(0, max_filled)
	var empty_big_cell_count: int = 0
	if max_blocks > filled_big_cell_count and free_room - filled_big_cell_count * 3 >= 4:
		empty_big_cell_count = randi_range(0, 1)

	var anchors: Array[Vector2i] = []
	var attempts := 0
	while anchors.size() < filled_big_cell_count + empty_big_cell_count and attempts < 60:
		attempts += 1
		var r := randi_range(0, rows - 2)
		var c := randi_range(0, columns - 2)
		if not _overlaps_existing(r, c, anchors):
			anchors.append(Vector2i(r, c))

	# Placement can fall short if the grid is tight; recompute actual counts from what fit.
	filled_big_cell_count = mini(filled_big_cell_count, anchors.size())
	empty_big_cell_count = anchors.size() - filled_big_cell_count

	var free_indices: Array = []
	for i in level.cells.size():
		var row: int = i / columns
		var column: int = i % columns
		if not anchors.any(func(a): return row - a.x in [0, 1] and column - a.y in [0, 1]):
			free_indices.append(i)
	free_indices.shuffle()

	# Only fewer than shape_count if the grid itself is too small for it.
	shape_count = mini(shape_count, filled_big_cell_count + free_indices.size())
	var specs := _random_specs(shape_count, randi_range(settings.min_combined_color_shapes, settings.max_combined_color_shapes))

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

	var normal_empty_budget: int = settings.max_slack if empty_big_cell_count == 0 else 0
	var active_empty_count: int = randi_range(0, mini(normal_empty_budget, free_indices.size() - cursor))
	for i in active_empty_count:
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
