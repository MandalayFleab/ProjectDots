class_name LevelGenerator
extends RefCounted

const MAX_ROWS := 6
const MAX_COLUMNS := 6
const MAX_SHAPES := 8
const MAX_SLACK := 4
const MAX_FILLED_BIG_CELLS := 4

static func generate() -> LevelData:
	var rows := randi_range(3, MAX_ROWS)
	var columns := randi_range(3, MAX_COLUMNS)

	var level := LevelData.new()
	level.rows = rows
	level.columns = columns
	level.cells = []
	for i in rows * columns:
		level.cells.append({"kind": LevelData.CellKind.INACTIVE, "spec": null})

	var max_blocks: int = (rows / 2) * (columns / 2)
	var filled_big_cell_count: int = randi_range(0, mini(MAX_FILLED_BIG_CELLS, max_blocks))
	var empty_big_cell_count: int = 0
	if max_blocks > filled_big_cell_count:
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

	for i in anchors.size():
		var anchor := anchors[i]
		var spec: PieceSpec = _random_spec() if i < filled_big_cell_count else null
		var idx := _index(anchor.x, anchor.y, columns)
		level.cells[idx] = {"kind": LevelData.CellKind.BIG_ANCHOR, "spec": spec}
		for dr in range(2):
			for dc in range(2):
				if dr == 0 and dc == 0:
					continue
				level.cells[_index(anchor.x + dr, anchor.y + dc, columns)] = {"kind": LevelData.CellKind.BIG_OCCUPIED, "spec": null}

	var free_indices: Array = []
	for i in level.cells.size():
		if level.cells[i]["kind"] == LevelData.CellKind.INACTIVE:
			free_indices.append(i)
	free_indices.shuffle()

	var normal_empty_budget: int = MAX_SLACK if empty_big_cell_count == 0 else 0
	var active_empty_count: int = randi_range(0, mini(normal_empty_budget, free_indices.size()))
	var shape_budget: int = MAX_SHAPES - filled_big_cell_count * 2
	var shape_count: int = maxi(mini(shape_budget, free_indices.size() - active_empty_count), 0)

	var cursor := 0
	for i in active_empty_count:
		level.cells[free_indices[cursor]] = {"kind": LevelData.CellKind.NORMAL, "spec": null}
		cursor += 1
	for i in shape_count:
		level.cells[free_indices[cursor]] = {"kind": LevelData.CellKind.NORMAL, "spec": _random_spec()}
		cursor += 1

	level.shapes_to_place = []
	for cell in level.cells:
		if cell["spec"] == null:
			continue
		if cell["kind"] == LevelData.CellKind.BIG_ANCHOR:
			level.shapes_to_place.append_array(PieceDecomposer.decompose_big(cell["spec"]))
		elif cell["kind"] == LevelData.CellKind.NORMAL:
			level.shapes_to_place.append(cell["spec"])

	return level

static func _index(r: int, c: int, columns: int) -> int:
	return r * columns + c

static func _overlaps_existing(r: int, c: int, anchors: Array[Vector2i]) -> bool:
	for a in anchors:
		if abs(a.x - r) < 2 and abs(a.y - c) < 2:
			return true
	return false

static func _random_spec() -> PieceSpec:
	return PieceSpec.new(Shapes.Type.values().pick_random(), Shapes.PrimaryColor.values().pick_random())
