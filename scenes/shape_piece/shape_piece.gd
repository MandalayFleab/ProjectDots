extends Control
class_name ShapePiece

const DRAG_PREVIEW_ALPHA := 0.6
const CLICK_DISTANCE_THRESHOLD := 6.0

# Membership marks a piece as mid-animation, so Tray can treat it as a mover
# that pushes loose pieces aside (see TrayCollision).
const MOVING_GROUP := &"moving_pieces"

# A static var (not a const) so every piece shares one tunable value, and
# the debug layout panel (F1, debug builds only) can compare different
# sizes live instead of needing a code edit + restart per value tried.
# 2.0 is a linear scale, i.e. 4x the original drag-preview AREA.
static var drag_preview_scale: float = 2.0

@export var shape_type: Shapes.Type = Shapes.Type.SQUARE
@export var color: Shapes.PieceColor = Shapes.PieceColor.RED

var locked: bool = false
var selected: bool = false

# Only meaningful while loose in the Tray -- driven by TrayCollision so a hit
# piece keeps gliding briefly (air-hockey style) instead of stopping dead.
var slide_velocity: Vector2 = Vector2.ZERO

# Set by setup_pair() when this piece is made of two primary units (a big
# piece, or a mixed colour of either size) -- the units it splits back into.
var is_big: bool = false
var original_a: PieceSpec = null
var original_b: PieceSpec = null

var _press_position: Vector2 = Vector2.ZERO
var _press_active: bool = false
var _pre_drag_parent: Node = null
var _active_tween: Tween = null

# A piece made of a single primary unit -- always normal size.
func setup_single(spec: PieceSpec, unit_size: Vector2) -> void:
	shape_type = spec.shape_type
	color = spec.color
	is_big = false
	original_a = null
	original_b = null
	size = unit_size

# A piece made of two primary units of the same shape, remembered so the
# Divisor can split it back. The same primary twice gives a big piece of
# that colour; two different primaries give their mix, which -- unlike a
# primary -- may be either size, since its two units are accounted for
# either way (see ShapeShifter).
func setup_pair(a: PieceSpec, b: PieceSpec, big: bool, unit_size: Vector2) -> void:
	shape_type = a.shape_type
	color = Shapes.mix(a.color, b.color)
	original_a = PieceSpec.new(a.shape_type, a.color)
	original_b = PieceSpec.new(b.shape_type, b.color)
	is_big = big
	size = unit_size * 2.0 if big else unit_size

# ShapeShifter only: flips a mixed-colour piece between normal and big.
func toggle_size() -> void:
	is_big = not is_big
	size = size * 2.0 if is_big else size * 0.5
	queue_redraw()

func _draw() -> void:
	Shapes.draw_shape(self, shape_type, color, Rect2(Vector2.ZERO, size), 8.0)
	if selected:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.9), false, 4.0)

func set_selected(active: bool) -> void:
	selected = active
	queue_redraw()

func animate_to(target_position: Vector2, duration: float, on_finished: Callable = Callable()) -> void:
	cancel_animation()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(MOVING_GROUP)
	var tween := create_tween()
	_active_tween = tween
	tween.tween_property(self, "position", target_position, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func():
		_leave_moving_group()
		mouse_filter = Control.MOUSE_FILTER_STOP
		if on_finished.is_valid():
			on_finished.call()
	)

# Call when a piece is forcibly removed from a cell (e.g. ejected by the
# round-end check) while it might still be mid-travel from an earlier
# animated placement -- otherwise that old tween keeps running on an
# already-relocated piece and can fire a stale completion callback later.
func cancel_animation() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
	_leave_moving_group()
	mouse_filter = Control.MOUSE_FILTER_STOP

func _leave_moving_group() -> void:
	if is_in_group(MOVING_GROUP):
		remove_from_group(MOVING_GROUP)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if locked:
		return null
	# Once held in the ShapeShifter, a piece only leaves through its long-press
	# expel (or by being combined). Returning null here lets the drag attempt
	# fall through to the ShapeShifter (this piece's mouse filter is PASS), which
	# doesn't offer one either.
	if get_parent() is ShapeShifter:
		return null
	if Selection.selected_piece == self:
		Selection.deselect()
	var preview := duplicate() as ShapePiece
	preview.modulate.a = DRAG_PREVIEW_ALPHA
	preview.pivot_offset = preview.size * 0.5
	preview.scale = Vector2(drag_preview_scale, drag_preview_scale)
	# Godot re-positions whatever control is passed to set_drag_preview() to
	# the cursor every frame, overwriting its .position directly -- so
	# offsetting the preview itself doesn't stick. It does NOT touch that
	# control's children, though, so the fix is to wrap the actual shape in a
	# plain anchor Control and offset the shape within that instead.
	preview.position = -preview.pivot_offset
	var preview_anchor := Control.new()
	preview_anchor.add_child(preview)
	set_drag_preview(preview_anchor)
	# The native drag preview follows the cursor, but this original node stays
	# put until _drop_data reparents it -- hide it for the duration so there
	# isn't a visible duplicate sitting at the start position the whole time.
	_pre_drag_parent = get_parent()
	visible = false
	Selection.highlight_for_drag(self)
	return self

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		Selection.clear_drag_highlight()
		# Only restore visibility ourselves if the drag was cancelled (nobody
		# reparented this piece). A successful drop already reparented it into
		# wherever it landed, and THAT code decides the correct visibility
		# (e.g. a BigCell may want it hidden because it just formed a merge) --
		# forcing it visible here would stomp on that decision.
		if get_parent() == _pre_drag_parent:
			visible = true

func _gui_input(event: InputEvent) -> void:
	if locked:
		return
	# While held in the ShapeShifter, this piece's own hitbox would
	# otherwise swallow every tap meant for the ShapeShifter itself (its mouse
	# filter is PASS specifically so taps still reach it after this returns
	# -- see ShapeShifter._hold()). Dragging it out is blocked separately, in
	# _get_drag_data().
	if get_parent() is ShapeShifter:
		return
	# A piece sitting in a cell covers most of it, so presses on the piece
	# also drive the cell's long-press expel (this piece stays STOP, unlike in
	# the ShapeShifter, so its own tap-to-select keeps working alongside).
	var cell := get_parent() as BoardCell
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_position = event.position
			_press_active = true
			if cell != null:
				cell.start_hold()
		elif _press_active:
			_press_active = false
			if cell != null:
				cell.end_hold()
			if event.position.distance_to(_press_position) < CLICK_DISTANCE_THRESHOLD:
				_on_tap(cell)

# With another piece already selected, tapping a piece that sits in a cell
# means "put the selected one here" -- the same as tapping the cell itself,
# whose border is all that's left uncovered -- so the selected piece
# replaces this one. Only when the cell can't take it (wrong size, already
# tried there) does the tap fall back to selecting this piece instead.
# Dragging this piece out, or long-pressing it, never reaches here (a drag
# isn't a tap, and a long press cancels it -- see cancel_press()).
func _on_tap(cell: BoardCell) -> void:
	var other := Selection.selected_piece
	if cell != null and other != null and other != self and cell.can_accept(other):
		Selection.try_place_in(cell)
		return
	Selection.select(self)

# Called when a long press expels this piece mid-press, so the release that
# follows isn't also read as a tap that selects it.
func cancel_press() -> void:
	_press_active = false

# A piece already sitting in a cell would otherwise block drops onto that
# cell -- forward to whichever cell the drag is in range of (see Selection).
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is ShapePiece and Selection.find_drop_target(data) != null

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	Selection.drop_into_target(data)
