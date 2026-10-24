extends Panel
class_name BoardCell

enum Highlight { NONE, CAN_ACCEPT, CANNOT_ACCEPT }

signal piece_changed

var required_spec: PieceSpec = null
var tray: Tray = null
var locked: bool = false
var current_piece: ShapePiece = null
var highlight: Highlight = Highlight.NONE
# Drawn over `highlight` (not stored in it) so that when a drag moves out of
# range the cell falls straight back to its own blue/red state.
var targeted: bool = false
# (row, column) anchor in the board's grid -- set once by Board.build() and
# reused by Board.relayout() to reposition this same cell instance on a live
# resize without needing to rebuild the level/cells from scratch.
var grid_position: Vector2i = Vector2i.ZERO

var _press_position: Vector2 = Vector2.ZERO
var _press_active: bool = false
var _tried_specs: Array = []
var _hold_active: bool = false
var _hold_id: int = 0
var _hold_progress: float = 0.0

func has_requirement() -> bool:
	return required_spec != null

# Normal cells expect a normal piece; BigCell overrides this to true.
func expects_big() -> bool:
	return false

func is_solved() -> bool:
	if required_spec == null:
		# An intentionally empty cell is solved by staying empty -- it's still
		# a valid drop target (that's the trap), just not a correct one.
		return current_piece == null
	return current_piece != null and current_piece.is_big == expects_big() \
		and current_piece.shape_type == required_spec.shape_type \
		and current_piece.color == required_spec.color

# True when this cell's requirement is trivially satisfied by having nothing
# in it. game_manager defers locking these until the whole board is also
# resolved -- otherwise it'd lock (and start showing red to every type,
# tried or not) the moment it happens to be empty at some evaluation, even
# while other cells are still wrong and the player hasn't actually finished.
func is_solved_by_emptiness() -> bool:
	return required_spec == null and current_piece == null

func detach(piece: ShapePiece) -> void:
	if current_piece == piece:
		current_piece = null

func release_wrong_pieces() -> Array[ShapePiece]:
	var result: Array[ShapePiece] = []
	if current_piece != null:
		current_piece.cancel_animation()
		remove_child(current_piece)
		result.append(current_piece)
		current_piece = null
	return result

# A "type" is shape+color+is_big: a normal Red Triangle and a combined (big)
# Red Triangle are tracked separately, so a mistaken big-piece attempt can
# never block a normal piece of the same shape+color from being tried later.
# Only call this during solution evaluation (game_manager._check_solution),
# not on placement -- freely repositioning pieces during the "shape
# colocation" phase shouldn't burn an attempt, only an actual evaluated miss.
func remember_tried(piece: ShapePiece) -> void:
	if not _has_tried(piece.shape_type, piece.color, piece.is_big):
		_tried_specs.append({"shape_type": piece.shape_type, "color": piece.color, "is_big": piece.is_big})

func can_accept(piece: ShapePiece) -> bool:
	return not locked and piece.is_big == expects_big() \
		and not _has_tried(piece.shape_type, piece.color, piece.is_big)

func set_highlight(state: Highlight) -> void:
	if highlight == state:
		return
	highlight = state
	queue_redraw()

# Green "a drop right now lands here" state -- only ever on one cell at a
# time, driven by Selection while a drag is in progress.
func set_targeted(active: bool) -> void:
	if targeted == active:
		return
	targeted = active
	queue_redraw()

func lock() -> void:
	locked = true
	if current_piece != null:
		current_piece.locked = true

func _draw() -> void:
	if targeted:
		_draw_inner_glow(Color(0.35, 0.95, 0.45))
	else:
		match highlight:
			Highlight.CAN_ACCEPT:
				_draw_inner_glow(Color(0.35, 0.65, 1.0))
			Highlight.CANNOT_ACCEPT:
				_draw_inner_glow(Color(1.0, 0.3, 0.3))
			Highlight.NONE:
				pass
	if _hold_progress > 0.0:
		_draw_hold_snake()

# Long-press charge indicator: a line that grows along the cell's border,
# starting at the bottom-left corner and running clockwise (up the left
# side, across the top, down the right, back along the bottom).
func _draw_hold_snake() -> void:
	var width: float = min(size.x, size.y) * 0.06
	var inset := width * 0.5
	var r := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2)
	var corners: Array[Vector2] = [
		Vector2(r.position.x, r.end.y), r.position,
		Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y),
	]
	var remaining: float = (r.size.x + r.size.y) * 2.0 * _hold_progress
	var points := PackedVector2Array([corners[0]])
	for i in range(1, corners.size()):
		var segment: float = corners[i - 1].distance_to(corners[i])
		if remaining >= segment:
			points.append(corners[i])
			remaining -= segment
		else:
			points.append(corners[i - 1].move_toward(corners[i], remaining))
			break
	draw_polyline(points, Color(1.0, 0.55, 0.2, 0.95), width)

# Simulates a soft light glowing in from the edges: many thin, closely-spaced
# fading borders instead of a flat fill (Godot's 2D draw API has no native
# blur). A crisp, brighter rim right at the edge reads as the light source,
# with a fast (non-linear) falloff inward so it stays a thin rim glow rather
# than a thick banded block.
func _draw_inner_glow(color: Color) -> void:
	var layers := 28
	var max_inset: float = min(size.x, size.y) * 0.12
	for i in layers:
		var t := float(i) / float(layers - 1)
		var inset := lerpf(0.0, max_inset, t)
		var alpha := pow(1.0 - t, 2.2) * 0.75
		var rect := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2)
		draw_rect(rect, Color(color.r, color.g, color.b, alpha), false, 1.6)
	draw_rect(Rect2(Vector2.ZERO, size), Color(color.r, color.g, color.b, 0.9), false, 2.0)

func _has_tried(shape_type: Shapes.Type, color: Shapes.PieceColor, is_big: bool) -> bool:
	for entry in _tried_specs:
		if entry["shape_type"] == shape_type and entry["color"] == color and entry["is_big"] == is_big:
			return true
	return false

func _has_point(point: Vector2) -> bool:
	# Grows the droppable area a bit past the visible edges -- proportional to
	# cell size (not a fixed pixel count) so it still makes sense now that
	# cells are sized dynamically instead of being a fixed 100px constant.
	var margin: float = min(size.x, size.y) * 0.06
	return Rect2(-margin, -margin, size.x + margin * 2, size.y + margin * 2).has_point(point)

# Routed through Selection so a drop lands in the green cell -- with the
# cursor inside this cell that's this cell itself, or nothing.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is ShapePiece and Selection.find_drop_target(data) != null

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	Selection.drop_into_target(data)

# Shared by both the drag-and-drop path (_drop_data, instant) and the
# click-to-select-then-click-to-place path (Selection, animated). Either
# way, a piece already here is evicted to make room (locked cells never get
# this far -- can_accept() refuses them).
func place_piece(piece: ShapePiece, animate: bool = false) -> void:
	var start_global: Vector2 = piece.global_position
	BoardCell.release_from_current_parent(piece)
	if current_piece != null:
		_expel(current_piece)
	add_child(piece)
	piece.visible = true
	current_piece = piece
	var target := (size - piece.size) * 0.5
	if animate:
		piece.global_position = start_global
		# Wait for the piece to actually arrive before announcing the change --
		# otherwise a win-check could lock/evict it while still mid-flight.
		piece.animate_to(target, Selection.MOVE_DURATION, func(): piece_changed.emit())
	else:
		piece.position = target
		piece_changed.emit()

# Slides the piece out of whichever board edge is nearest this cell (level
# with the cell, not anywhere along that edge) -- shared by the long-press
# expel and eviction-on-replace.
func _expel(piece: ShapePiece) -> void:
	piece.cancel_animation()
	piece.cancel_press()
	if Selection.selected_piece == piece:
		Selection.deselect()
	tray.launch_from_nearest_side(piece, get_parent(), self)

func _gui_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_position = event.position
			_press_active = true
			start_hold()
		elif _press_active:
			_press_active = false
			end_hold()
			if event.position.distance_to(_press_position) < 6.0:
				Selection.try_place_in(self)

# Long press (on the cell or the piece sitting in it -- ShapePiece forwards
# its presses here) expels the current piece. Same timing as the Combiner's.
func start_hold() -> void:
	# An IGNORE piece is mid-move or shrinking away after a failed check --
	# expelling it then would race whatever is animating it.
	if locked or current_piece == null or current_piece.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	_hold_active = true
	_hold_id += 1
	_watch_hold(_hold_id)

func end_hold() -> void:
	_hold_active = false
	_hold_id += 1

# Ticks every frame (rather than a single timer) so _hold_progress can drive
# the snake indicator, same approach as Combiner._watch_long_press().
func _watch_hold(id: int) -> void:
	var start_time: float = Time.get_ticks_msec() / 1000.0
	var completed := false
	while id == _hold_id and _hold_active:
		# Starting a drag takes the press over -- no release ever arrives
		# to end the hold, so stop here instead of expelling mid-drag.
		if get_viewport().gui_is_dragging() or current_piece == null:
			break
		var elapsed: float = Time.get_ticks_msec() / 1000.0 - start_time
		_hold_progress = clampf(elapsed / Combiner.LONG_PRESS_SECONDS, 0.0, 1.0)
		queue_redraw()
		if elapsed >= Combiner.LONG_PRESS_SECONDS:
			completed = true
			break
		await get_tree().process_frame

	_hold_progress = 0.0
	queue_redraw()

	if not completed:
		return
	_hold_active = false
	_expel(current_piece)

# Duck-typed so any container that holds a single piece and exposes
# detach(piece) works here -- BoardCell/BigCell, but also Combiner.
static func release_from_current_parent(piece: ShapePiece) -> void:
	var parent := piece.get_parent()
	if parent != null and parent.has_method("detach"):
		parent.detach(piece)
	if parent != null:
		parent.remove_child(piece)
