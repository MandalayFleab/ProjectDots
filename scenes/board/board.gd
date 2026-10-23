extends Control
class_name Board

const BoardCellScene := preload("res://scenes/board_cell/board_cell.tscn")
const BigCellScene := preload("res://scenes/big_cell/big_cell.tscn")

const GAP_RATIO := 0.12
const MIN_CELL_SIZE := 50.0

# A var (not a const) so the in-editor debug layout panel (F1, debug builds
# only) can tune it live while comparing proportions, instead of needing a
# code edit + restart per value tried.
var board_size_ratio: float = 1.0

var cell_size: Vector2 = Vector2(100, 100)
var gap: float = 12.0

var _cells: Array = []
var _level: LevelData = null

# Cell size is derived from the actually available space instead of being a
# fixed constant, so the board (and the pieces sized relative to it) use
# however much room the screen really has -- a lot more on a narrow portrait
# phone than a fixed logical-pixel size would, since Godot's canvas scaling
# shrinks fixed sizes down hard on narrow screens.
func build(level: LevelData, tray: Tray, available_size: Vector2) -> void:
	for child in get_children():
		child.queue_free()
	_cells = []
	_level = level

	# Sized against LevelGenerator's fixed maximum board dimension, not this
	# particular level's actual rows/columns -- otherwise a round that
	# happens to generate a smaller board (fewer cells to divide the same
	# budget between) gets visibly bigger cells/pieces than one that
	# generates a bigger board, even on the same screen with the same
	# ratio. Using the worst case keeps cell (and therefore piece) size
	# constant across every round on a given device; a smaller board just
	# ends up with some unused space around it instead.
	var max_dimension: int = max(LevelGenerator.MAX_ROWS, LevelGenerator.MAX_COLUMNS)
	var budget: float = min(available_size.x, available_size.y) * board_size_ratio
	var raw_cell: float = budget / (max_dimension + (max_dimension - 1) * GAP_RATIO)
	raw_cell = max(raw_cell, MIN_CELL_SIZE)
	cell_size = Vector2(raw_cell, raw_cell)
	gap = raw_cell * GAP_RATIO

	size = Vector2(
		level.columns * cell_size.x + (level.columns - 1) * gap,
		level.rows * cell_size.y + (level.rows - 1) * gap
	)

	for r in level.rows:
		for c in level.columns:
			var cell_info: Dictionary = level.cells[r * level.columns + c]
			var pos := Vector2(c * (cell_size.x + gap), r * (cell_size.y + gap))
			match cell_info["kind"]:
				LevelData.CellKind.NORMAL:
					var cell: BoardCell = BoardCellScene.instantiate()
					cell.position = pos
					cell.size = cell_size
					cell.required_spec = cell_info["spec"]
					cell.tray = tray
					cell.grid_position = Vector2i(r, c)
					add_child(cell)
					_cells.append(cell)
				LevelData.CellKind.BIG_ANCHOR:
					var big: BigCell = BigCellScene.instantiate()
					big.position = pos
					big.size = cell_size * 2 + Vector2(gap, gap)
					big.required_spec = cell_info["spec"]
					big.tray = tray
					big.grid_position = Vector2i(r, c)
					add_child(big)
					_cells.append(big)
				_:
					pass

func get_cells() -> Array:
	return _cells

# Reflows the EXISTING cells (and whatever pieces they currently hold) to a
# new available size, without regenerating the level -- used when the screen
# resizes live mid-round, so the player's progress is never thrown away just
# because the window changed size. Returns the scale factor applied (1.0 if
# the change was negligible and nothing moved), so callers can rescale
# pieces elsewhere (tray, combiner) by the same amount.
func relayout(available_size: Vector2) -> float:
	if _level == null:
		return 1.0

	# Same fixed-reference reasoning as build() above -- keeps a live resize
	# consistent with the rest of this round's own sizing.
	var max_dimension: int = max(LevelGenerator.MAX_ROWS, LevelGenerator.MAX_COLUMNS)
	var budget: float = min(available_size.x, available_size.y) * board_size_ratio
	var raw_cell: float = budget / (max_dimension + (max_dimension - 1) * GAP_RATIO)
	raw_cell = max(raw_cell, MIN_CELL_SIZE)

	if absf(raw_cell - cell_size.x) < 0.5:
		return 1.0

	var scale_factor: float = raw_cell / cell_size.x
	cell_size = Vector2(raw_cell, raw_cell)
	gap = raw_cell * GAP_RATIO

	size = Vector2(
		_level.columns * cell_size.x + (_level.columns - 1) * gap,
		_level.rows * cell_size.y + (_level.rows - 1) * gap
	)

	for cell in _cells:
		var r: int = cell.grid_position.x
		var c: int = cell.grid_position.y
		cell.position = Vector2(c * (cell_size.x + gap), r * (cell_size.y + gap))
		cell.size *= scale_factor
		for child in cell.get_children():
			if child is ShapePiece:
				child.size *= scale_factor
				child.position = (cell.size - child.size) * 0.5

	return scale_factor
