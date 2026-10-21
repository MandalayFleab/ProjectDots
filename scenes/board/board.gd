extends Control
class_name Board

const BoardCellScene := preload("res://scenes/board_cell/board_cell.tscn")
const BigCellScene := preload("res://scenes/big_cell/big_cell.tscn")

const BOARD_SIZE_RATIO := 0.9
const GAP_RATIO := 0.12
const MIN_CELL_SIZE := 50.0

var cell_size: Vector2 = Vector2(100, 100)
var gap: float = 12.0

var _cells: Array = []

# Cell size is derived from the actually available space instead of being a
# fixed constant, so the board (and the pieces sized relative to it) use
# however much room the screen really has -- a lot more on a narrow portrait
# phone than a fixed logical-pixel size would, since Godot's canvas scaling
# shrinks fixed sizes down hard on narrow screens.
func build(level: LevelData, tray: Tray, available_size: Vector2) -> void:
	for child in get_children():
		child.queue_free()
	_cells = []

	var max_dimension: int = max(level.rows, level.columns)
	var budget: float = min(available_size.x, available_size.y) * BOARD_SIZE_RATIO
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
					add_child(cell)
					_cells.append(cell)
				LevelData.CellKind.BIG_ANCHOR:
					var big: BigCell = BigCellScene.instantiate()
					big.position = pos
					big.size = cell_size * 2 + Vector2(gap, gap)
					big.required_spec = cell_info["spec"]
					big.tray = tray
					add_child(big)
					_cells.append(big)
				_:
					pass

func get_cells() -> Array:
	return _cells
