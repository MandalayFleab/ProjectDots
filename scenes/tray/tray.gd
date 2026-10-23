extends Control
class_name Tray

var exclusion_rects: Array[Rect2] = []

func clear() -> void:
	for child in get_children():
		child.queue_free()

# Rescales every piece currently scattered in the tray (by the same factor
# board.relayout() applied to cell_size, so pieces stay correctly sized
# relative to the board) and remaps each one's position by the tray's own
# resize ratio, so a piece near, say, the right edge stays near the right
# edge instead of drifting toward a corner or off-screen after a resize.
func rescale(scale_factor: float, old_size: Vector2, new_size: Vector2) -> void:
	var ratio := Vector2(
		new_size.x / old_size.x if old_size.x > 0.0 else 1.0,
		new_size.y / old_size.y if old_size.y > 0.0 else 1.0
	)
	for child in get_children():
		if child is ShapePiece:
			child.size *= scale_factor
			child.position *= ratio

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
	piece.visible = true
	piece.position = target_position

func _find_free_position(piece_size: Vector2, placed_rects: Array[Rect2]) -> Vector2:
	var max_x: float = max(size.x - piece_size.x, 0.0)
	var max_y: float = max(size.y - piece_size.y, 0.0)

	# Tier 1: avoid both exclusion zones (board/combiner/divisor) and other
	# already-placed pieces.
	for attempt in 40:
		var candidate := Vector2(randf() * max_x, randf() * max_y)
		if _is_excluded(candidate, piece_size):
			continue
		if _overlaps_any(candidate, piece_size, placed_rects):
			continue
		return candidate

	# Tier 2: with enough pieces/excluded area, 40 random tries can all fail.
	# Overlapping another scattered piece is only cosmetic (still clickable),
	# but landing inside an exclusion zone makes a piece unreachable and the
	# puzzle unsolvable -- that constraint must never be dropped, even here.
	for attempt in 60:
		var candidate := Vector2(randf() * max_x, randf() * max_y)
		if not _is_excluded(candidate, piece_size):
			return candidate

	# Tier 3: last resort, exhaustive grid scan for any non-excluded spot.
	var step: float = max(min(piece_size.x, piece_size.y) * 0.5, 8.0)
	var y := 0.0
	while y <= max_y:
		var x := 0.0
		while x <= max_x:
			var candidate := Vector2(x, y)
			if not _is_excluded(candidate, piece_size):
				return candidate
			x += step
		y += step

	# The exclusion zones cover the entire tray -- genuinely nowhere is safe.
	return Vector2.ZERO

func _is_excluded(candidate: Vector2, piece_size: Vector2) -> bool:
	var candidate_rect := Rect2(candidate, piece_size)
	for ex in exclusion_rects:
		if ex.size != Vector2.ZERO and candidate_rect.grow(8).intersects(ex):
			return true
	return false

func _overlaps_any(candidate: Vector2, piece_size: Vector2, placed_rects: Array[Rect2]) -> bool:
	var candidate_rect := Rect2(candidate, piece_size)
	for rect in placed_rects:
		if candidate_rect.intersects(rect.grow(8)):
			return true
	return false
