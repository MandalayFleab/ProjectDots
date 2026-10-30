extends Control
class_name SolutionPreview

# Puzzle mode's miniature "screenshot" of the solved board, shown in the
# playable items zone for the whole round (see game_manager._apply_items()).
# Drawn straight from the LevelData (not from the real board's cells), so it
# always shows the solution, whatever the player has placed so far.
#
# Tapping it zooms it up to the middle of the screen; the next tap anywhere
# (on it or not) shrinks it back. That tap only closes the zoom -- it never
# also reaches the game underneath, so closing it can't accidentally pick up
# or drop a piece.

# Same proportions as the real board, so the miniature reads as the same grid.
const GAP_RATIO := Board.GAP_RATIO
const PADDING_RATIO := 0.06
const SHAPE_MARGIN_RATIO := 0.1

const BACKGROUND_COLOR := Color(0.07, 0.08, 0.1, 0.9)
const CELL_COLOR := Color(0.78, 0.81, 0.9)

# Zoomed size, as a fraction of the screen's smaller side.
const ZOOM_SCREEN_RATIO := 0.7
const ZOOM_SECONDS := 0.2

var _level: LevelData = null
var _background := StyleBoxFlat.new()
var _padding: float = 0.0
var _cell: float = 0.0
var _zoomed: bool = false
# Where fit() last put it, to return to after a zoom.
var _rest_position: Vector2 = Vector2.ZERO
var _zoom_tween: Tween = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_background.bg_color = BACKGROUND_COLOR

func show_level(level: LevelData) -> void:
	_level = level
	_unzoom(false)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not _zoomed and _is_press(event):
		accept_event()
		_zoom()

# While zoomed, catches the next press anywhere before the GUI sees it.
func _input(event: InputEvent) -> void:
	if _zoomed and _is_press(event):
		get_viewport().set_input_as_handled()
		_unzoom(true)

static func _is_press(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT

# Scales up (rather than resizing and redrawing) from wherever it sits, so
# fit() keeps owning its resting size and position.
func _zoom() -> void:
	if size == Vector2.ZERO:
		return
	_zoomed = true
	# Drawn over every sibling while zoomed, whatever their tree order.
	z_index = 1
	var screen: Vector2 = get_parent_area_size()
	var target_scale: float = minf(screen.x, screen.y) * ZOOM_SCREEN_RATIO / size.x
	_tween_to(target_scale, (screen - size * target_scale) * 0.5)

func _unzoom(animate: bool) -> void:
	if not _zoomed:
		return
	_zoomed = false
	if animate:
		_tween_to(1.0, _rest_position)
		_zoom_tween.finished.connect(func(): z_index = 0)
	else:
		_kill_zoom_tween()
		scale = Vector2.ONE
		position = _rest_position
		z_index = 0

func _tween_to(target_scale: float, target_position: Vector2) -> void:
	_kill_zoom_tween()
	_zoom_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(self, "scale", Vector2(target_scale, target_scale), ZOOM_SECONDS)
	_zoom_tween.tween_property(self, "position", target_position, ZOOM_SECONDS)

func _kill_zoom_tween() -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null

# Always a side x side square with its top left corner at origin, whatever
# this round's rows/columns -- cells are sized against the mode's maximum
# board dimension (same as Board does), and a smaller grid is just centered
# inside. Otherwise the miniature (and its cells) would change size from
# round to round.
func fit(origin: Vector2, side: float) -> void:
	# A relayout (resize, new round) snaps a zoomed preview back first --
	# its zoomed scale/position were worked out for the old size.
	_unzoom(false)
	_rest_position = origin
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
