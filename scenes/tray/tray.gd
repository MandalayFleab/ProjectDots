extends Control
class_name Tray

var exclusion_rect: Rect2 = Rect2()

func clear() -> void:
	for child in get_children():
		child.queue_free()

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is ShapePiece

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var piece := data as ShapePiece
	_take_piece(piece, at_position - piece.size * 0.5)

func scatter(pieces: Array[ShapePiece]) -> void:
	var placed_rects: Array[Rect2] = []
	for piece in pieces:
		var pos := _find_free_position(piece.size, placed_rects)
		_take_piece(piece, pos)
		placed_rects.append(Rect2(pos, piece.size))

func _take_piece(piece: ShapePiece, target_position: Vector2) -> void:
	BoardCell.release_from_current_parent(piece)
	add_child(piece)
	piece.position = target_position

func _find_free_position(piece_size: Vector2, placed_rects: Array[Rect2]) -> Vector2:
	var max_x: float = max(size.x - piece_size.x, 0.0)
	var max_y: float = max(size.y - piece_size.y, 0.0)
	for attempt in 30:
		var candidate := Vector2(randf() * max_x, randf() * max_y)
		var candidate_rect := Rect2(candidate, piece_size)
		if exclusion_rect.size != Vector2.ZERO and candidate_rect.grow(8).intersects(exclusion_rect):
			continue
		var overlaps := false
		for rect in placed_rects:
			if candidate_rect.intersects(rect.grow(8)):
				overlaps = true
				break
		if not overlaps:
			return candidate
	return Vector2(randf() * max_x, randf() * max_y)
