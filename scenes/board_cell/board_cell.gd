extends Panel
class_name BoardCell

enum Highlight { NONE, CAN_ACCEPT, CANNOT_ACCEPT }

signal piece_changed

var required_spec: PieceSpec = null
var tray: Tray = null
var locked: bool = false
var current_piece: ShapePiece = null
var highlight: Highlight = Highlight.NONE
# (row, column) anchor in the board's grid -- set once by Board.build() and
# reused by Board.relayout() to reposition this same cell instance on a live
# resize without needing to rebuild the level/cells from scratch.
var grid_position: Vector2i = Vector2i.ZERO

var _press_position: Vector2 = Vector2.ZERO
var _press_active: bool = false
var _tried_specs: Array = []

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

func lock() -> void:
	locked = true
	if current_piece != null:
		current_piece.locked = true

func _draw() -> void:
	match highlight:
		Highlight.CAN_ACCEPT:
			_draw_inner_glow(Color(0.35, 0.65, 1.0))
		Highlight.CANNOT_ACCEPT:
			_draw_inner_glow(Color(1.0, 0.3, 0.3))
		Highlight.NONE:
			pass

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

func _has_tried(shape_type: Shapes.Type, color: Shapes.PrimaryColor, is_big: bool) -> bool:
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

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is ShapePiece and can_accept(data as ShapePiece)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	place_piece(data as ShapePiece)

# Shared by both the drag-and-drop path (_drop_data, instant) and the
# click-to-select-then-click-to-place path (Selection, animated).
func place_piece(piece: ShapePiece, animate: bool = false) -> void:
	var start_global: Vector2 = piece.global_position
	BoardCell.release_from_current_parent(piece)
	if current_piece != null:
		tray.scatter([current_piece])
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

func _gui_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_position = event.position
			_press_active = true
		elif _press_active:
			_press_active = false
			if event.position.distance_to(_press_position) < 6.0:
				Selection.try_place_in(self)

# Duck-typed so any container that holds a single piece and exposes
# detach(piece) works here -- BoardCell/BigCell, but also Combiner.
static func release_from_current_parent(piece: ShapePiece) -> void:
	var parent := piece.get_parent()
	if parent != null and parent.has_method("detach"):
		parent.detach(piece)
	if parent != null:
		parent.remove_child(piece)
