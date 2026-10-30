extends Node

# How long the auto-drag animation takes, in seconds. Change this one value
# to make click-to-place feel faster or slower.
const MOVE_DURATION := 0.35

# How far outside a cell (as a fraction of the smallest cell's side) a
# dragged piece still counts as "in range" of it -- shown green, and where
# the piece lands if dropped there.
const DROP_RANGE_RATIO := 0.5

var selected_piece: ShapePiece = null
var _cells: Array = []
var _drag_piece: ShapePiece = null
var _drag_target: BoardCell = null

# Called by game_manager once per round, after the board is built.
func set_cells(cells: Array) -> void:
	_cells = cells
	_drag_target = null

func select(piece: ShapePiece) -> void:
	if piece.locked:
		return
	if selected_piece == piece:
		deselect()
		return
	deselect()
	selected_piece = piece
	piece.set_selected(true)
	_highlight_for(piece)

func deselect() -> void:
	if selected_piece != null:
		selected_piece.set_selected(false)
	selected_piece = null
	_clear_highlights()

# Untyped target: works for BoardCell/BigCell, and also ShapeShifter/Divisor --
# anything exposing can_accept(piece) and place_piece(piece, animate).
func try_place_in(target) -> void:
	if selected_piece == null or not target.can_accept(selected_piece):
		return
	var piece := selected_piece
	deselect()
	target.place_piece(piece, true)

# Used by ShapePiece while a real mouse-drag is in progress.
func highlight_for_drag(piece: ShapePiece) -> void:
	_drag_piece = piece
	_highlight_for(piece)

func clear_drag_highlight() -> void:
	_drag_piece = null
	_set_drag_target(null)
	_clear_highlights()

func _process(_delta: float) -> void:
	if _drag_piece != null:
		_set_drag_target(find_drop_target(_drag_piece))

# The single cell a drop at the cursor right now would land in, or null.
# Directly over a cell means that cell or nothing -- never a neighbour, so a
# red cell under the cursor can't silently redirect the drop next door.
# Otherwise it's the nearest accepting cell within DROP_RANGE_RATIO.
func find_drop_target(piece: ShapePiece) -> BoardCell:
	if _cells.is_empty():
		return null
	var mouse: Vector2 = (_cells[0] as Control).get_global_mouse_position()
	var range_limit := INF
	for cell in _cells:
		range_limit = minf(range_limit, minf(cell.size.x, cell.size.y) * DROP_RANGE_RATIO)
	var best: BoardCell = null
	var best_distance := INF
	for cell in _cells:
		var rect: Rect2 = cell.get_global_rect()
		if rect.has_point(mouse):
			return cell if cell.can_accept(piece) else null
		if not cell.can_accept(piece):
			continue
		var distance := mouse.distance_to(mouse.clamp(rect.position, rect.end))
		if distance <= range_limit and distance < best_distance:
			best = cell
			best_distance = distance
	return best

# For every drop receiver around the board (cells, pieces sitting in them,
# the board's gaps, the tray): whichever control happens to be under the
# cursor, a drag in range of a cell lands in that cell. Returns false when
# no cell is in range, so the receiver can fall back to its own behavior.
func drop_into_target(piece: ShapePiece) -> bool:
	var target := find_drop_target(piece)
	if target == null:
		return false
	target.place_piece(piece)
	return true

func _set_drag_target(cell: BoardCell) -> void:
	if cell == _drag_target:
		return
	if is_instance_valid(_drag_target):
		_drag_target.set_targeted(false)
	_drag_target = cell
	if cell != null:
		cell.set_targeted(true)

func _highlight_for(piece: ShapePiece) -> void:
	for cell in _cells:
		cell.set_highlight(BoardCell.Highlight.CAN_ACCEPT if cell.can_accept(piece) else BoardCell.Highlight.CANNOT_ACCEPT)

func _clear_highlights() -> void:
	for cell in _cells:
		cell.set_highlight(BoardCell.Highlight.NONE)
