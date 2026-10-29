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
	# Dropped just outside the board but in range of a (green) cell.
	if Selection.drop_into_target(piece):
		return
	_take_piece(piece, at_position - piece.size * 0.5)

# Slides pieces out of a source control (the board, Combiner, Divisor)
# instead of popping them into place: each starts just outside a random
# point along one of the given sides and is launched outward, so even
# pieces coming from the same cell spread out along the whole edge.
func launch_from(pieces: Array[ShapePiece], source: Control, sides: Array) -> void:
	var source_rect := _local_rect_of(source)
	var starts: Array[Vector2] = []
	var entry := _entry_edge(source_rect)
	for piece in pieces:
		if _launch(piece, source_rect, sides, starts):
			continue
		# The source sits in its own zone, outside the tray -- enter through
		# the tray edge facing it instead.
		if not entry.is_empty() and _launch(piece, entry["rect"], [entry["side"]], starts):
			continue
		# No room right next to the requested sides (e.g. the board sits just
		# above the Resizer, closer than a piece is tall) -- still slide it
		# out from somewhere, rather than teleporting it.
		if _launch(piece, source_rect, ALL_SIDES, starts):
			continue
		if not _launch_from_nearest_free(piece, source_rect):
			scatter([piece])

# Launches a piece out of whichever side of `source` is nearest to `origin`
# (a control inside it, e.g. one cell of the board), starting level with
# origin rather than anywhere along that side. Sides without room are
# skipped in nearest-first order.
func launch_from_nearest_side(piece: ShapePiece, source: Control, origin: Control) -> void:
	var s := _local_rect_of(source)
	var o := _local_rect_of(origin)
	var distances := {
		Side.TOP: o.position.y - s.position.y,
		Side.BOTTOM: s.end.y - o.end.y,
		Side.LEFT: o.position.x - s.position.x,
		Side.RIGHT: s.end.x - o.end.x,
	}
	var sides := distances.keys()
	sides.sort_custom(func(a, b): return distances[a] < distances[b])
	for side in sides:
		var span: Rect2
		if side == Side.LEFT or side == Side.RIGHT:
			span = Rect2(s.position.x, o.position.y, s.size.x, o.size.y)
		else:
			span = Rect2(o.position.x, s.position.y, o.size.x, s.size.y)
		if _launch(piece, span, [side], []):
			return
	var entry := _entry_edge(o)
	if not entry.is_empty() and _launch(piece, entry["rect"], [entry["side"]], []):
		return
	if not _launch_from_nearest_free(piece, o):
		scatter([piece])

func _launch(piece: ShapePiece, source_rect: Rect2, sides: Array, taken: Array[Vector2]) -> bool:
	var start := _find_launch_start(piece.size, source_rect, sides, taken)
	if start.is_empty():
		return false
	var start_position: Vector2 = start["position"]
	var normal: Vector2 = start["normal"]
	_take_piece(piece, start_position)
	taken.append(start_position)
	var direction := normal.rotated(deg_to_rad(randf_range(-LAUNCH_SPREAD_DEGREES, LAUNCH_SPREAD_DEGREES)))
	TrayCollision.launch(piece, direction, piece.size.x * randf_range(LAUNCH_DISTANCE_MIN, LAUNCH_DISTANCE_MAX))
	return true

# Last resort before an instant scatter: starts the piece at the free spot
# closest to the source and slides it straight away from the source, so it
# still visibly comes out of it. False only if the tray has no free spot.
func _launch_from_nearest_free(piece: ShapePiece, source_rect: Rect2) -> bool:
	var origin := source_rect.get_center()
	var step: float = maxf(minf(piece.size.x, piece.size.y) * 0.25, 4.0)
	var max_x: float = size.x - piece.size.x
	var max_y: float = size.y - piece.size.y
	var best := Vector2.ZERO
	var best_distance := INF
	var y := 0.0
	while y <= max_y:
		var x := 0.0
		while x <= max_x:
			var candidate := Vector2(x, y)
			if not _is_excluded(candidate, piece.size):
				var distance := (candidate + piece.size * 0.5).distance_squared_to(origin)
				if distance < best_distance:
					best = candidate
					best_distance = distance
			x += step
		y += step
	if best_distance == INF:
		return false
	_take_piece(piece, best)
	var away := (best + piece.size * 0.5 - origin).normalized()
	var direction := away.rotated(deg_to_rad(randf_range(-LAUNCH_SPREAD_DEGREES, LAUNCH_SPREAD_DEGREES)))
	TrayCollision.launch(piece, direction, piece.size.x * randf_range(LAUNCH_DISTANCE_MIN, LAUNCH_DISTANCE_MAX))
	return true

# For a source entirely outside the tray (the board and the playable items
# each live in their own zone), a zero-thickness source rect just outside
# the tray edge facing it, and the side to launch out of it -- so pieces
# slide in through that edge as if they came straight from the source.
# Narrowed to the source's own span along that edge when they overlap, so a
# piece still enters level with where it came from. {} if the source
# overlaps the tray.
func _entry_edge(source: Rect2) -> Dictionary:
	var bounds := _bounds()
	if source.intersects(bounds):
		return {}
	# How far the source lies beyond each tray edge, keyed by the side that
	# launches into the tray through that edge.
	var distances := {
		Side.RIGHT: bounds.position.x - source.end.x,
		Side.LEFT: source.position.x - bounds.end.x,
		Side.BOTTOM: bounds.position.y - source.end.y,
		Side.TOP: source.position.y - bounds.end.y,
	}
	var side: Tray.Side = Side.RIGHT
	for candidate in distances:
		if distances[candidate] > distances[side]:
			side = candidate
	# Matches _find_launch_start()'s gap, so the start lands right on the
	# edge -- minus half a pixel, so float rounding can't put it a hair out
	# of bounds and get it rejected.
	var gap: float = TrayCollision.WALL_PADDING + 2.0 - 0.5
	var span: Vector2
	var rect: Rect2
	match side:
		Side.RIGHT, Side.LEFT:
			span = _overlap(source.position.y, source.end.y, 0.0, size.y)
			var x: float = -gap if side == Side.RIGHT else size.x + gap
			rect = Rect2(x, span.x, 0.0, span.y - span.x)
		_:
			span = _overlap(source.position.x, source.end.x, 0.0, size.x)
			var y: float = -gap if side == Side.BOTTOM else size.y + gap
			rect = Rect2(span.x, y, span.y - span.x, 0.0)
	return {"rect": rect, "side": side}

# The overlap of [a_start, a_end] and [b_start, b_end], or the whole of the
# second range when they don't overlap.
static func _overlap(a_start: float, a_end: float, b_start: float, b_end: float) -> Vector2:
	var start := maxf(a_start, b_start)
	var end := minf(a_end, b_end)
	return Vector2(start, end) if start < end else Vector2(b_start, b_end)

func _local_rect_of(control: Control) -> Rect2:
	return get_global_transform().affine_inverse() * control.get_global_rect()

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
