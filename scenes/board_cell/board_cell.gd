extends Panel
class_name BoardCell

signal piece_changed

# Half the gap between cells, so a drop landing in the gap still snaps to
# the nearer cell instead of requiring the cursor to be exactly inside it.
const DROP_MARGIN := Board.GAP * 0.5

var required_spec: PieceSpec = null
var tray: Tray = null
var locked: bool = false
var current_piece: ShapePiece = null

func has_requirement() -> bool:
	return required_spec != null

func is_full() -> bool:
	return current_piece != null

func is_solved() -> bool:
	return current_piece != null \
		and current_piece.shape_type == required_spec.shape_type \
		and current_piece.color == required_spec.color

func detach(piece: ShapePiece) -> void:
	if current_piece == piece:
		current_piece = null

func release_wrong_pieces() -> Array[ShapePiece]:
	var result: Array[ShapePiece] = []
	if current_piece != null:
		remove_child(current_piece)
		result.append(current_piece)
		current_piece = null
	return result

func lock() -> void:
	locked = true
	if current_piece != null:
		current_piece.locked = true

func _has_point(point: Vector2) -> bool:
	return Rect2(-DROP_MARGIN, -DROP_MARGIN, size.x + DROP_MARGIN * 2, size.y + DROP_MARGIN * 2).has_point(point)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return has_requirement() and not locked and data is ShapePiece

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var piece := data as ShapePiece
	BoardCell.release_from_current_parent(piece)
	if current_piece != null:
		tray.scatter([current_piece])
	add_child(piece)
	piece.position = (size - piece.size) * 0.5
	current_piece = piece
	piece_changed.emit()

static func release_from_current_parent(piece: ShapePiece) -> void:
	var parent := piece.get_parent()
	if parent is BoardCell:
		(parent as BoardCell).detach(piece)
	if parent != null:
		parent.remove_child(piece)
