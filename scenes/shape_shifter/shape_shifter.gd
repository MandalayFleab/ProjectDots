extends Panel
class_name ShapeShifter

# The old Combiner and Resizer in one playable item -- what it does depends
# on the piece put in, and the two never get in each other's way:
#   - A single primary unit (red, yellow, blue) is held, and the next one of
#     the same shape combines with it into a big piece (Combiner).
#   - A mixed colour (purple, orange, green) switches size and comes straight
#     back out (Resizer) -- any primary being held stays put meanwhile.

const ShapePieceScene := preload("res://scenes/shape_piece/shape_piece.tscn")
const LABEL := "Shift"
const CLICK_DISTANCE_THRESHOLD := 6.0
const LONG_PRESS_SECONDS := 0.5

# Proportions (of this node's own square size) for the hold-charge bar drawn
# just below it -- game_manager._apply_items() reserves room for these too,
# so the bar never leaves the playable items zone.
const HOLD_BAR_GAP_RATIO := 0.08
const HOLD_BAR_HEIGHT_RATIO := 0.12

# Whenever a combine or resize sends its result out into the tray -- lets
# HELP's auto-play follow the piece it just made.
signal produced(pieces: Array)
# A player-visible use (Puzzle mode counts each as a move): every resize, a
# second primary put in on top of a held one -- combined or not -- or a
# long-press expel. The first primary going in isn't a use yet.
signal used

var tray: Tray = null
var held_piece: ShapePiece = null

var _press_position: Vector2 = Vector2.ZERO
var _press_active: bool = false
var _press_id: int = 0
var _charge_progress: float = 0.0

func clear() -> void:
	if held_piece != null:
		held_piece.queue_free()
		held_piece = null

func detach(piece: ShapePiece) -> void:
	if held_piece == piece:
		held_piece = null
		# Leaving the shifter (expelled or consumed by a combine) -- restore normal input handling for wherever it ends up.
		piece.mouse_filter = Control.MOUSE_FILTER_STOP

# Called on a live resize, after this node's own size has already been
# updated by game_manager._apply_ui_scale() -- rescales/recenters whatever
# piece is currently held so it doesn't end up the wrong size or off-center.
func rescale(scale_factor: float) -> void:
	if held_piece != null:
		held_piece.size *= scale_factor
		held_piece.position = (size - held_piece.size) * 0.5

func can_accept(piece: ShapePiece) -> bool:
	return _can_combine(piece) or _can_resize(piece)

# Only single primary units are combined -- a mixed colour is already two
# units, so combining it further would have no valid result.
static func _can_combine(piece: ShapePiece) -> bool:
	return not piece.is_big and Shapes.is_primary(piece.color)

# Mixed colours only, at either size. A primary's size IS its unit count (a
# big red is two red units), so resizing one would create or destroy a unit
# and leave the puzzle with leftover or missing pieces; a mixed colour is
# always exactly two units whatever its size.
static func _can_resize(piece: ShapePiece) -> bool:
	return not Shapes.is_primary(piece.color)

func _draw() -> void:
	# Fully proportional to size (no fixed pixel values) -- resizing this node
	# is all that's needed to scale the whole thing correctly.
	var dim: float = min(size.x, size.y)
	var border_width: float = dim * 0.025
	var inset: float = dim * 0.0375
	var radius: float = dim * 0.5 - inset
	draw_circle(size * 0.5, radius, Color(0.8, 0.85, 0.95, 0.9), false, border_width, true)
	var font := ThemeDB.fallback_font
	var font_size := int(dim * 0.1125)
	var text_size := font.get_string_size(LABEL, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var label_margin: float = dim * 0.0875
	draw_string(font, Vector2(size.x * 0.5 - text_size.x * 0.5, size.y - label_margin), LABEL, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.9, 0.9, 0.95))

	if _charge_progress > 0.0:
		_draw_hold_charge_bar(dim)

# Fills as a long press builds up, just below the circle -- gives the
# player feedback on how close they are to expelling the held piece,
# instead of the expel just happening with no warning at LONG_PRESS_SECONDS.
func _draw_hold_charge_bar(dim: float) -> void:
	var bar_height: float = dim * HOLD_BAR_HEIGHT_RATIO
	var gap: float = dim * HOLD_BAR_GAP_RATIO
	var track_rect := Rect2(Vector2(0.0, size.y + gap), Vector2(size.x, bar_height))
	draw_rect(track_rect, Color(1, 1, 1, 0.18))
	var fill_rect := Rect2(track_rect.position, Vector2(track_rect.size.x * _charge_progress, bar_height))
	draw_rect(fill_rect, Color(1.0, 0.55, 0.2, 0.9))

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is ShapePiece and can_accept(data as ShapePiece)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	place_piece(data as ShapePiece)

# Shared by both the drag-and-drop path (_drop_data, instant) and the
# click-to-select-then-click-to-place path (Selection, animated) -- same
# pattern as BoardCell/BigCell.
func place_piece(piece: ShapePiece, animate: bool = false) -> void:
	if _can_resize(piece):
		_pass_through(piece, animate)
		return
	var start_global: Vector2 = piece.global_position
	var previous := held_piece
	BoardCell.release_from_current_parent(piece)
	add_child(piece)
	piece.visible = true
	_hold(piece)
	var target := (size - piece.size) * 0.5
	if animate:
		piece.global_position = start_global
		# Resolving (combine or expel the previous piece) waits for the new
		# piece to actually arrive, same reason BigCell used to defer its
		# merge decision: acting on it mid-flight would race the tween.
		piece.animate_to(target, Selection.MOVE_DURATION, func(): _resolve(piece, previous))
	else:
		piece.position = target
		_resolve(piece, previous)

# A mixed colour isn't held: it travels in, switches size and is sent
# straight back out, leaving any held primary where it is.
func _pass_through(piece: ShapePiece, animate: bool) -> void:
	var start_global: Vector2 = piece.global_position
	BoardCell.release_from_current_parent(piece)
	add_child(piece)
	piece.visible = true
	var target := (size - piece.size) * 0.5
	if animate:
		piece.global_position = start_global
		piece.animate_to(target, Selection.MOVE_DURATION, func(): _resize(piece))
	else:
		piece.position = target
		_resize(piece)

func _resize(piece: ShapePiece) -> void:
	# The round may have been reset mid-animation -- no longer ours to touch.
	if piece.get_parent() != self:
		return
	piece.toggle_size()
	tray.launch_from([piece], self, [Tray.Side.TOP])
	produced.emit([piece])
	used.emit()

func _resolve(piece: ShapePiece, previous: ShapePiece) -> void:
	# piece's own travel animation (if it arrived via the animated path) just
	# reset its mouse_filter to STOP right before calling here, moments ago --
	# if it's still the held piece, restore PASS regardless of which branch
	# below runs. This also covers the early-return "nothing to resolve"
	# case: a single piece placed into a previously-empty shifter (the
	# common case where previous == null) would otherwise stay stuck at
	# STOP forever, silently blocking the shifter's own tap/long-press
	# input exactly as if this fix never happened.
	if held_piece == piece:
		piece.mouse_filter = Control.MOUSE_FILTER_PASS

	# If the previous piece got moved elsewhere in the meantime (e.g. the
	# round was reset mid-animation), leave it alone -- it's no longer ours
	# to touch.
	if previous == null or previous.get_parent() != self:
		return
	if _combinable(previous, piece):
		previous.cancel_animation()
		var combined := _combine(previous, piece)
		previous.queue_free()
		piece.queue_free()
		held_piece = null
		# A big piece can't be combined any further, so it's expelled right
		# away instead of sitting in the shifter waiting for a long press.
		tray.launch_from([combined], self, [Tray.Side.TOP])
		produced.emit([combined])
		used.emit()
	else:
		previous.cancel_animation()
		tray.launch_from([previous], self, [Tray.Side.TOP])
		# A second piece put in counts as trying to combine, whether or not
		# the two actually combined.
		used.emit()

# A piece held in the shifter needs PASS, not the default STOP --
# STOP would swallow every tap before this panel's own _gui_input ever saw
# it, so the long-press expel (now the only way out) would never fire.
# Dragging it out is refused by ShapePiece._get_drag_data() itself.
func _hold(piece: ShapePiece) -> void:
	held_piece = piece
	piece.mouse_filter = Control.MOUSE_FILTER_PASS

# Any two primary units of the same shape: the same colour makes a big piece
# of that colour, different colours make a big piece of their mix.
func _combinable(a: ShapePiece, b: ShapePiece) -> bool:
	return _can_combine(a) and _can_combine(b) and a.shape_type == b.shape_type

# Always big -- a mixed one can be shrunk by putting it back in.
func _combine(a: ShapePiece, b: ShapePiece) -> ShapePiece:
	var combined: ShapePiece = ShapePieceScene.instantiate()
	combined.setup_pair(PieceSpec.new(a.shape_type, a.color), PieceSpec.new(b.shape_type, b.color), true, a.size)
	return combined

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_position = event.position
			_press_active = true
			_press_id += 1
			_watch_long_press(_press_id)
		elif _press_active:
			_press_active = false
			_press_id += 1
			if event.position.distance_to(_press_position) < CLICK_DISTANCE_THRESHOLD:
				Selection.try_place_in(self)

# A short tap places whatever's currently selected (same as tapping an empty
# shifter always did); holding past LONG_PRESS_SECONDS instead expels
# whatever's currently held, so getting it back out doesn't require
# precisely grabbing its (otherwise click-blocking) hitbox. Ticks every
# frame (rather than a single timer) so _charge_progress can drive the
# hold-charge bar instead of the expel just happening with no warning.
func _watch_long_press(id: int) -> void:
	var start_time: float = Time.get_ticks_msec() / 1000.0
	var completed := false
	while id == _press_id and _press_active:
		var elapsed: float = Time.get_ticks_msec() / 1000.0 - start_time
		_charge_progress = clampf(elapsed / LONG_PRESS_SECONDS, 0.0, 1.0)
		queue_redraw()
		if elapsed >= LONG_PRESS_SECONDS:
			completed = true
			break
		await get_tree().process_frame

	_charge_progress = 0.0
	queue_redraw()

	if not completed:
		return
	_press_active = false
	if held_piece != null:
		expel_held()
		used.emit()

# Sends whatever's held back out into the tray (the long-press expel, also
# used by HELP's auto-play to clear the shifter before combining).
func expel_held() -> void:
	if held_piece == null:
		return
	var piece := held_piece
	piece.cancel_animation()
	tray.launch_from([piece], self, [Tray.Side.TOP])
