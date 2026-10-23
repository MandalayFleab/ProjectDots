extends Control
class_name Tray

enum Side { TOP, BOTTOM, LEFT, RIGHT }
const ALL_SIDES := [Side.TOP, Side.BOTTOM, Side.LEFT, Side.RIGHT]

const LAUNCH_SPREAD_DEGREES := 35.0  # random deviation from straight out of the edge
const LAUNCH_DISTANCE_MIN := 1.0     # slide length, in piece widths
const LAUNCH_DISTANCE_MAX := 2.5
const LAUNCH_CANDIDATES := 30        # start spots tried per piece

# Re-applying walls on every reassignment (each new round and every live
# resize) keeps a piece from ending up behind the board just because the
# board grew or moved under it.
var exclusion_rects: Array[Rect2] = []:
	set(value):
		exclusion_rects = value
		for piece in _loose_pieces():
			TrayCollision.apply_walls(piece, _bounds(), exclusion_rects)

# Only runs the solver while something is actually travelling -- a mouse-drag
# in progress, a click-to-place animation, or a piece still sliding from an
# earlier hit -- so idle pieces never drift.
func _process(delta: float) -> void:
	var movers := _collect_movers()
	var pieces := _loose_pieces()
	if movers.is_empty() and not TrayCollision.any_sliding(pieces):
		return
	TrayCollision.resolve(pieces, movers, _bounds(), exclusion_rects, delta)

func _collect_movers() -> Array[TrayCollision.Mover]:
	var movers: Array[TrayCollision.Mover] = []
	var viewport := get_viewport()
	if viewport.gui_is_dragging():
		var dragged = viewport.gui_get_drag_data()
		if dragged is ShapePiece:
			# Hitbox is the real piece size, not the 2x drag preview -- so what
			# gets pushed matches where the piece will actually land.
			movers.append(TrayCollision.Mover.new(get_local_mouse_position(), TrayCollision.radius_of(dragged)))
	# Animated pieces are already parented to their destination (cell,
	# Combiner, Divisor) while they travel, so map them into tray space.
	var to_local := get_global_transform().affine_inverse()
	for node in get_tree().get_nodes_in_group(ShapePiece.MOVING_GROUP):
		var piece := node as ShapePiece
		movers.append(TrayCollision.Mover.new(to_local * piece.get_global_rect().get_center(), TrayCollision.radius_of(piece)))
	return movers

# A piece being dragged out of the tray is still a (hidden) child until it
# drops somewhere -- it must not collide with its own drag.
func _loose_pieces() -> Array:
	return get_children().filter(func(c): return c is ShapePiece and c.visible)

func _bounds() -> Rect2:
	return Rect2(Vector2.ZERO, size)

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

# Slides pieces out of a source control (the board, Combiner, Divisor)
# instead of popping them into place: each starts just outside a random
# point along one of the given sides and is launched outward, so even
# pieces coming from the same cell spread out along the whole edge.
func launch_from(pieces: Array[ShapePiece], source: Control, sides: Array) -> void:
	var to_local := get_global_transform().affine_inverse()
	var source_rect := Rect2(to_local * source.global_position, source.size)
	var starts: Array[Vector2] = []
	for piece in pieces:
		var start := _find_launch_start(piece.size, source_rect, sides, starts)
		if start.is_empty():
			# No room along any of those sides (a squeezed layout) -- fall
			# back to an instant placement rather than start behind a wall.
			scatter([piece])
			continue
		var start_position: Vector2 = start["position"]
		var normal: Vector2 = start["normal"]
		_take_piece(piece, start_position)
		starts.append(start_position)
		var direction := normal.rotated(deg_to_rad(randf_range(-LAUNCH_SPREAD_DEGREES, LAUNCH_SPREAD_DEGREES)))
		TrayCollision.launch(piece, direction, piece.size.x * randf_range(LAUNCH_DISTANCE_MIN, LAUNCH_DISTANCE_MAX))

# Returns {"position", "normal"} for a valid start spot, or {} if none was
# found. Best-candidate sampling: of the valid spots tried, keeps the one
# farthest from pieces already launched in this batch, so they don't start
# stacked on top of each other and shove one another violently.
func _find_launch_start(piece_size: Vector2, source: Rect2, sides: Array, taken: Array[Vector2]) -> Dictionary:
	# Just past the wall padding, so the source's own wall never snags it.
	var gap: float = TrayCollision.WALL_PADDING + 2.0
	var half := piece_size * 0.5
	var best := {}
	var best_spacing := -1.0
	for attempt in LAUNCH_CANDIDATES:
		var t := randf()
		var x_along: float = lerpf(source.position.x, source.end.x, t) - half.x
		var y_along: float = lerpf(source.position.y, source.end.y, t) - half.y
		var candidate: Vector2
		var normal: Vector2
		match sides.pick_random():
			Side.TOP:
				candidate = Vector2(x_along, source.position.y - gap - piece_size.y)
				normal = Vector2.UP
			Side.BOTTOM:
				candidate = Vector2(x_along, source.end.y + gap)
				normal = Vector2.DOWN
			Side.LEFT:
				candidate = Vector2(source.position.x - gap - piece_size.x, y_along)
				normal = Vector2.LEFT
			Side.RIGHT:
				candidate = Vector2(source.end.x + gap, y_along)
				normal = Vector2.RIGHT
		if not _bounds().encloses(Rect2(candidate, piece_size)) or _is_excluded(candidate, piece_size):
			continue
		var spacing := INF
		for other in taken:
			spacing = minf(spacing, candidate.distance_to(other))
		if spacing > best_spacing:
			best_spacing = spacing
			best = {"position": candidate, "normal": normal}
	return best

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
	# Whatever slide it had when it last left the tray is long stale.
	piece.slide_velocity = Vector2.ZERO
	TrayCollision.apply_walls(piece, _bounds(), exclusion_rects)

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
