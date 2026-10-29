extends Control
class_name SolutionPreview

# Puzzle mode's miniature "screenshot" of the solved board, shown in a corner
# of the scramble zone for the whole round (see game_manager._apply_preview()). Drawn straight from
# the LevelData (not from the real board's cells), so it always shows the
# solution, whatever the player has placed so far.

# Same proportions as the real board, so the miniature reads as the same grid.
const GAP_RATIO := Board.GAP_RATIO
const PADDING_RATIO := 0.06
const SHAPE_MARGIN_RATIO := 0.1

const BACKGROUND_COLOR := Color(0.07, 0.08, 0.1, 0.9)
const CELL_COLOR := Color(0.78, 0.81, 0.9)

var _level: LevelData = null
var _background := StyleBoxFlat.new()
var _padding: float = 0.0
var _cell: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.bg_color = BACKGROUND_COLOR

func show_level(level: LevelData) -> void:
	_level = level
	queue_redraw()

# Always a side x side square with its top left corner at origin, whatever
# this round's rows/columns -- cells are sized against the mode's maximum
# board dimension (same as Board does), and a smaller grid is just centered
# inside. Otherwise the miniature (and its cells) would change size from
# round to round.
func fit(origin: Vector2, side: float) -> void:
	position = origin
	if _level == null:
		size = Vector2.ZERO
		return
	size = Vector2(side, side)
	_padding = side * PADDING_RATIO
	_cell = _cell_size_for(side - _padding * 2.0, _level.max_dimension)
	_background.set_corner_radius_all(int(_padding))
	queue_redraw()

func _draw() -> void:
	if _level == null or size == Vector2.ZERO:
		return
	draw_style_box(_background, Rect2(Vector2.ZERO, size))
	var cell: float = _cell
	var gap: float = cell * GAP_RATIO
	var grid_origin: Vector2 = (size - _grid_size(cell)) * 0.5
	for r in _level.rows:
		for c in _level.columns:
			var info: Dictionary = _level.cells[r * _level.columns + c]
			var cell_size: float
			match info["kind"]:
				LevelData.CellKind.NORMAL:
					cell_size = cell
				LevelData.CellKind.BIG_ANCHOR:
					cell_size = cell * 2.0 + gap
				_:
					continue
			var rect := Rect2(grid_origin + Vector2(c, r) * (cell + gap), Vector2(cell_size, cell_size))
			draw_rect(rect, CELL_COLOR)
			var spec: PieceSpec = info["spec"]
			if spec != null:
				Shapes.draw_shape(self, spec.shape_type, spec.color, rect, cell_size * SHAPE_MARGIN_RATIO)

func _cell_size_for(length: float, count: int) -> float:
	return maxf(length, 0.0) / (count + (count - 1) * GAP_RATIO)

func _grid_size(cell: float) -> Vector2:
	var gap: float = cell * GAP_RATIO
	return Vector2(
		_level.columns * cell + (_level.columns - 1) * gap,
		_level.rows * cell + (_level.rows - 1) * gap
	)
