extends Control
class_name Board

const BoardCellScene := preload("res://scenes/board_cell/board_cell.tscn")
const BigCellScene := preload("res://scenes/big_cell/big_cell.tscn")

const CELL_SIZE := Vector2(100, 100)
const GAP := 12.0

var _cells: Array = []

func build(level: LevelData, tray: Tray) -> void:
	for child in get_children():
		child.queue_free()
	_cells = []

	size = Vector2(
		level.columns * CELL_SIZE.x + (level.columns - 1) * GAP,
		level.rows * CELL_SIZE.y + (level.rows - 1) * GAP
	)

	for r in level.rows:
		for c in level.columns:
			var cell_info: Dictionary = level.cells[r * level.columns + c]
			var pos := Vector2(c * (CELL_SIZE.x + GAP), r * (CELL_SIZE.y + GAP))
			match cell_info["kind"]:
				LevelData.CellKind.NORMAL:
					var cell: BoardCell = BoardCellScene.instantiate()
					cell.position = pos
					cell.size = CELL_SIZE
					cell.required_spec = cell_info["spec"]
					cell.tray = tray
					add_child(cell)
					_cells.append(cell)
				LevelData.CellKind.BIG_ANCHOR:
					var big: BigCell = BigCellScene.instantiate()
					big.position = pos
					big.size = CELL_SIZE * 2 + Vector2(GAP, GAP)
					big.required_spec = cell_info["spec"]
					big.tray = tray
					add_child(big)
					_cells.append(big)
				_:
					pass

func get_cells() -> Array:
	return _cells
