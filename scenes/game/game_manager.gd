extends Control

const ShapePieceScene := preload("res://scenes/shape_piece/shape_piece.tscn")

enum State { SHOWING, PLAYING, WON }
enum LayoutMode { AUTO, HORIZONTAL, VERTICAL }

# After every layout pass -- lets the debug layout panel follow an automatic
# switch between the horizontal and vertical distributions.
signal layout_applied

# How long the viewport must sit still before a live resize is treated as
# "settled" and actually relaid out. Browsers fire resize continuously while
# a window is being dragged -- without this, every single intermediate
# frame would trigger a full board/tray/UI recompute.
const RESIZE_SETTLE_SECONDS := 0.3

# How long the solution previews take to shrink away once the reveal time is
# up, before the pieces are scrambled out of the board.
const PREVIEW_SHRINK_SECONDS := 0.4

@onready var board: Board = $Board
@onready var tray: Tray = $Tray
@onready var combiner: Combiner = $Combiner
@onready var divisor: Divisor = $Divisor
@onready var resizer: Resizer = $Resizer
@onready var reveal_timer: Timer = $RevealTimer
@onready var chronometer_label: Label = $ChronometerLabel
@onready var result_label: Label = $ResultLabel
@onready var replay_button: Button = $ReplayButton
@onready var mistakes_label: Label = $MistakesLabel

var state: State = State.SHOWING
var elapsed_time: float = 0.0
var level: LevelData
var mistakes: int = 0

# The two standard distributions (see LayoutConfig) -- which one applies
# depends only on the screen's shape, and each is tuned separately, so the
# same element can take a different proportion in each. Tuned live through
# the debug layout panel (F1, debug builds only), whose "Copy values" button
# prints these exact lines with the values picked there.
var horizontal_layout := LayoutConfig.from_dict({"side_ratio": 0.15, "board_ratio": 0.50, "info_ratio": 0.40, "margin_ratio": 0.02, "board_fill": 1.00, "items_fill": 0.85, "info_text_scale": 1.00})
var vertical_layout := LayoutConfig.from_dict({"side_ratio": 0.20, "board_ratio": 0.50, "info_ratio": 0.28, "margin_ratio": 0.02, "board_fill": 1.00, "items_fill": 0.85, "info_text_scale": 1.00})

# Debug layout panel only: forces one distribution whatever the screen's
# shape, so both can be tuned from the same window.
var orientation_override: LayoutMode = LayoutMode.AUTO

# Content rect of every zone ("info", "items", "board", "scramble") from the
# last layout pass, margins already taken out.
var zones: Dictionary = {}

var _checking_solution: bool = false
var _ready_for_resize: bool = false
var _resize_watch_active: bool = false
var _last_resize_time: float = 0.0

func _ready() -> void:
	# The tray is placed over the scramble zone explicitly (see
	# _place_tray()) -- its scene's full-rect anchors would otherwise keep
	# stretching it back over the whole screen on every resize.
	tray.set_anchors_preset(Control.PRESET_TOP_LEFT)
	reveal_timer.timeout.connect(_on_reveal_timer_timeout)
	replay_button.pressed.connect(_on_replay_pressed)
	await _new_game()

func _on_replay_pressed() -> void:
	await _new_game()

# Fires whenever this (full-rect-anchored) control's own size changes, which
# happens automatically whenever the viewport/browser window does. Ignored
# until the first _new_game() has actually finished building a board --
# otherwise the startup size-settling in _new_game() could race this.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_on_viewport_resized()

func _on_viewport_resized() -> void:
	if not _ready_for_resize:
		return
	_last_resize_time = Time.get_ticks_msec() / 1000.0
	if _resize_watch_active:
		return
	_resize_watch_active = true
	_watch_resize_settle()

# Keeps extending the wait as long as new resize events keep arriving, so
# the actual relayout only runs once the resize has genuinely stopped.
func _watch_resize_settle() -> void:
	while Time.get_ticks_msec() / 1000.0 - _last_resize_time < RESIZE_SETTLE_SECONDS:
		await get_tree().create_timer(0.1).timeout
	_resize_watch_active = false
	_relayout_for_resize()

# Public entry point for the debug layout panel (F1, debug builds only) --
# forces an immediate reflow after the user changes a layout value,
# reusing the exact same code path a live resize goes through.
func apply_layout_now() -> void:
	_relayout_for_resize()

# Live counterpart to _new_game()'s layout pass: reflows the board, tray,
# playable items and info zone to the new screen size in place, without
# touching the level, locked cells, placed pieces, elapsed time or mistakes
# -- a resize should never cost the player their progress.
func _relayout_for_resize() -> void:
	while size.x <= 0.0 or size.y <= 0.0:
		await get_tree().process_frame

	var old_tray_size: Vector2 = tray.size
	zones = _compute_zones()
	var scale_factor: float = board.relayout(_board_budget())
	_place_board()

	_place_tray()
	tray.rescale(scale_factor, old_tray_size, tray.size)
	_reset_tray_walls()

	_apply_zones()
	combiner.rescale(scale_factor)
	divisor.piece_size = board.cell_size * 0.8
	layout_applied.emit()

func _new_game() -> void:
	# Guards against a live-resize relayout racing an in-progress rebuild --
	# board.gd's _level and _cells are about to be replaced wholesale.
	_ready_for_resize = false
	reveal_timer.stop()
	Selection.deselect()
	Selection.set_cells([])
	tray.clear()
	combiner.clear()
	result_label.text = ""
	mistakes = 0
	mistakes_label.text = "Mistakes: 0"

	# On web, the browser canvas can take a couple of frames to report its
	# real size after load -- wait for this root Control to actually have one
	# before computing the board's cell size from it, instead of trusting a
	# single frame (or Board ends up sized for a near-zero area).
	while size.x <= 0.0 or size.y <= 0.0:
		await get_tree().process_frame

	level = LevelGenerator.generate()
	zones = _compute_zones()
	board.build(level, tray, _board_budget())
	for cell in board.get_cells():
		cell.piece_changed.connect(_on_piece_changed)
	Selection.set_cells(board.get_cells())

	_place_board()
	_place_tray()
	_reset_tray_walls()
	combiner.tray = tray
	divisor.tray = tray
	resizer.tray = tray
	divisor.piece_size = board.cell_size * 0.8
	_apply_zones()
	_start_round()
	_ready_for_resize = true
	layout_applied.emit()

func active_layout() -> LayoutConfig:
	return vertical_layout if is_vertical_layout() else horizontal_layout

func is_vertical_layout() -> bool:
	match orientation_override:
		LayoutMode.HORIZONTAL:
			return false
		LayoutMode.VERTICAL:
			return true
	return size.y > size.x

# Splits the screen into the active distribution's four zones. Each zone is
# carved out of the screen exclusively, so nothing (the board, the scattered
# pieces, the chrome) can ever size itself into another one's room.
func _compute_zones() -> Dictionary:
	var config := active_layout()
	var vertical := is_vertical_layout()
	var margin: float = config.margin_ratio * minf(size.x, size.y)
	var screen := _inset(Rect2(Vector2.ZERO, size), margin * 0.5)
	var shares := [config.side_ratio, config.effective_board_ratio(), config.scramble_ratio()]

	var result := {}
	var side_band: Rect2
	if vertical:
		var bands := _cut(screen, true, [shares[1], shares[2], shares[0]])
		result["board"] = bands[0]
		result["scramble"] = bands[1]
		side_band = bands[2]
	else:
		var bands := _cut(screen, false, [shares[0], shares[2], shares[1]])
		side_band = bands[0]
		result["scramble"] = bands[1]
		result["board"] = bands[2]
	# The side band splits along the other axis: info on top of the items
	# when it's a column, to their left when it's a row.
	var halves := _cut(side_band, not vertical, [config.info_ratio, 1.0 - config.info_ratio])
	result["info"] = halves[0]
	result["items"] = halves[1]

	# Half a margin off every zone (plus the half already off the screen
	# edge) leaves exactly one margin between any two neighbours.
	for key in result:
		result[key] = _inset(result[key], margin * 0.5)
	return result

# Splits rect along X (or Y when vertical) into consecutive parts of the
# given shares of its length.
static func _cut(rect: Rect2, vertical: bool, shares: Array) -> Array[Rect2]:
	var parts: Array[Rect2] = []
	var length: float = rect.size.y if vertical else rect.size.x
	var offset := 0.0
	for share in shares:
		var part: float = length * share
		if vertical:
			parts.append(Rect2(rect.position + Vector2(0.0, offset), Vector2(rect.size.x, part)))
		else:
			parts.append(Rect2(rect.position + Vector2(offset, 0.0), Vector2(part, rect.size.y)))
		offset += part
	return parts

static func _inset(rect: Rect2, amount: float) -> Rect2:
	var shrunk := rect.grow(-amount)
	return Rect2(shrunk.position, shrunk.size.max(Vector2.ZERO))

func _board_budget() -> Vector2:
	return zones["board"].size * active_layout().board_fill

func _place_board() -> void:
	var zone: Rect2 = zones["board"]
	board.position = zone.position + (zone.size - board.size) * 0.5

# The tray IS the scramble zone: loose pieces stay inside it, and pieces
# coming out of the board or the playable items enter it through the edge
# facing them (see Tray.launch_from()).
func _place_tray() -> void:
	var zone: Rect2 = zones["scramble"]
	tray.position = zone.position
	tray.size = zone.size

# Nothing else lives inside the scramble zone anymore -- its own edges are
# the only walls left. Reassigning also re-clamps every loose piece into the
# (possibly resized) zone, so it must run after Tray.rescale().
func _reset_tray_walls() -> void:
	var no_walls: Array[Rect2] = []
	tray.exclusion_rects = no_walls

func _apply_zones() -> void:
	var config := active_layout()
	_apply_items(zones["items"], config)
	_apply_info(zones["info"], config)
	_apply_result(zones["scramble"], config)

# Combiner, Resizer and Divisor share the playable items zone in equal
# slots, laid along its longer side (a column in the horizontal distribution,
# a row in the vertical one).
func _apply_items(zone: Rect2, config: LayoutConfig) -> void:
	var items: Array[Control] = [combiner, resizer, divisor]
	var in_row: bool = zone.size.x >= zone.size.y
	var slots := _cut(zone, not in_row, [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])
	# Combiner draws its hold-charge bar just below its own square -- all
	# three are sized and placed as if they had one, so they stay the same
	# size and aligned with each other, and the bar never leaves the zone.
	var height_factor: float = 1.0 + Combiner.HOLD_BAR_GAP_RATIO + Combiner.HOLD_BAR_HEIGHT_RATIO
	var slot_size: Vector2 = slots[0].size
	var side: float = minf(slot_size.x, slot_size.y / height_factor) * config.items_fill
	for i in items.size():
		items[i].size = Vector2(side, side)
		items[i].position = slots[i].get_center() - Vector2(side, side * height_factor) * 0.5

# Chronometer, mistakes and the Replay button, one row each, every font
# fitted to its row (and to the zone's width) instead of a fixed size.
func _apply_info(zone: Rect2, config: LayoutConfig) -> void:
	var rows := _cut(zone, true, [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])
	_fit_label(chronometer_label, rows[0], "00:00", 0.7, config.info_text_scale)
	_fit_label(mistakes_label, rows[1], "Mistakes: 00", 0.5, config.info_text_scale)

	var row: Rect2 = rows[2]
	var font_size: int = _fit_font_size("Replay", row.size.x * 0.7, row.size.y * 0.45, config.info_text_scale)
	replay_button.add_theme_font_size_override("font_size", font_size)
	replay_button.size = Vector2(minf(row.size.x, font_size * 5.0), minf(row.size.y * 0.85, font_size * 2.0))
	replay_button.position = row.get_center() - replay_button.size * 0.5

# The scramble zone is empty once the round is won, so the result shows up
# in its middle.
func _apply_result(zone: Rect2, config: LayoutConfig) -> void:
	var band_height: float = zone.size.y * 0.2
	var band := Rect2(zone.position + Vector2(0.0, (zone.size.y - band_height) * 0.5), Vector2(zone.size.x, band_height))
	_fit_label(result_label, band, "Solved in 00:00!", 0.7, config.info_text_scale)

func _fit_label(label: Label, rect: Rect2, sample: String, height_share: float, text_scale: float) -> void:
	label.add_theme_font_size_override("font_size", _fit_font_size(sample, rect.size.x * 0.95, rect.size.y * height_share, text_scale))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = rect.size
	label.position = rect.position

# Largest font size at which `sample` fits both max_width and max_height,
# then scaled by text_scale.
func _fit_font_size(sample: String, max_width: float, max_height: float, text_scale: float) -> int:
	var width_at_100: float = ThemeDB.fallback_font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	var by_width: float = max_width / width_at_100 * 100.0 if width_at_100 > 0.0 else max_height
	return maxi(int(minf(by_width, max_height) * text_scale), 8)

# Drops in the gaps between zones (e.g. just outside the board, inside its
# zone's margin) go to whichever cell is in range, same as the board's own
# gaps -- the tray no longer covers the whole screen to catch them.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is ShapePiece and Selection.find_drop_target(data) != null

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	Selection.drop_into_target(data)

func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	elapsed_time += delta
	var total := int(elapsed_time)
	chronometer_label.text = "%02d:%02d" % [total / 60, total % 60]

func _start_round() -> void:
	state = State.SHOWING
	elapsed_time = 0.0
	chronometer_label.text = "00:00"
	for cell in board.get_cells():
		if not cell.has_requirement():
			continue
		var preview := ShapePieceScene.instantiate() as ShapePiece
		preview.shape_type = cell.required_spec.shape_type
		preview.color = cell.required_spec.color
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.size = cell.size * 0.8
		cell.add_child(preview)
		preview.position = (cell.size - preview.size) * 0.5
	reveal_timer.start()

# Shrinks each control toward its own center and resolves once they're gone,
# returning false if Replay was pressed meanwhile (the round no longer
# exists). The tweens are bound to the controls themselves, so a Replay
# mid-shrink frees them along with their cells, while the wait uses a scene
# timer that always fires. Input is ignored while shrinking -- callers that
# keep the controls afterwards reset scale and mouse_filter themselves.
func _shrink_away(controls: Array) -> bool:
	var tweens: Array[Tween] = []
	for control in controls:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.pivot_offset = control.size * 0.5
		var tween: Tween = control.create_tween()
		tween.tween_property(control, "scale", Vector2.ZERO, PREVIEW_SHRINK_SECONDS) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tweens.append(tween)
	var round_level := level
	await get_tree().create_timer(PREVIEW_SHRINK_SECONDS).timeout
	# The timer and the tweens end on the same frame, and the timer can fire
	# first -- without this, a tween's final step would land AFTER a caller
	# restored scale, shrinking a re-scrambled piece back to zero (invisible
	# in the tray, which also stalls the next solution check).
	for tween in tweens:
		if tween.is_valid():
			tween.kill()
	for control in controls:
		if is_instance_valid(control):
			control.scale = Vector2.ZERO
	return level == round_level

func _on_reveal_timer_timeout() -> void:
	var previews: Array = []
	for cell in board.get_cells():
		previews.append_array(cell.get_children())
	if not await _shrink_away(previews):
		return

	for cell in board.get_cells():
		for child in cell.get_children():
			child.queue_free()

	var piece_size: Vector2 = board.cell_size * 0.8
	var pieces: Array[ShapePiece] = []
	for group in PieceDecomposer.random_disposition(level.shapes_to_place):
		pieces.append(_make_scramble_piece(group, piece_size))

	state = State.PLAYING
	tray.launch_from(pieces, board, Tray.ALL_SIDES)

# One group from PieceDecomposer.random_disposition(): a single unit makes a
# normal primary piece, a pair goes through the same setup_pair() the
# Combiner uses, so the Divisor/Resizer treat it exactly like one of theirs.
func _make_scramble_piece(group: Dictionary, piece_size: Vector2) -> ShapePiece:
	var units: Array = group["units"]
	var piece := ShapePieceScene.instantiate() as ShapePiece
	if units.size() == 2:
		piece.setup_pair(units[0], units[1], group["big"], piece_size)
	else:
		piece.setup_single(units[0], piece_size)
	return piece

func _on_piece_changed() -> void:
	if state != State.PLAYING:
		return
	# Intentionally-empty cells are correctly solved by staying empty, so
	# "every open cell is full" is no longer a valid readiness check -- check
	# once every scattered piece has been placed SOMEWHERE instead. A piece
	# sitting unplaced in the Combiner isn't in the tray either, but it also
	# isn't resolving anything, so it must block readiness too.
	if tray.get_child_count() > 0 or combiner.held_piece != null:
		return
	# A check already in progress is mid-shrink -- a late placement callback
	# (e.g. an earlier animated move landing now) must not count mistakes twice.
	if _checking_solution:
		return
	var open_cells: Array = []
	for cell in board.get_cells():
		if not cell.locked:
			open_cells.append(cell)
	_check_solution(open_cells)

func _check_solution(open_cells: Array) -> void:
	var wrong_cells: Array = []
	var pending_empty_cells: Array = []
	for cell in open_cells:
		if cell.is_solved():
			if cell.is_solved_by_emptiness():
				# Don't lock yet -- only "counts" once the rest of the board
				# also holds up this round (see below).
				pending_empty_cells.append(cell)
			else:
				cell.lock()
		else:
			mistakes += 1
			wrong_cells.append(cell)
	mistakes_label.text = "Mistakes: %d" % mistakes

	# Misplaced pieces shrink away in their cells first, same as the reveal
	# previews, and only then get released and re-scrambled.
	var shrinking: Array = []
	for cell in wrong_cells:
		if cell.current_piece != null:
			shrinking.append(cell.current_piece)
	if not shrinking.is_empty():
		# A piece selected before the check could otherwise be tapped into
		# another cell mid-shrink.
		Selection.deselect()
		_checking_solution = true
		var still_this_round: bool = await _shrink_away(shrinking)
		_checking_solution = false
		if not still_this_round:
			return

	var wrong_pieces: Array[ShapePiece] = []
	for cell in wrong_cells:
		var released: Array[ShapePiece] = cell.release_wrong_pieces()
		for piece in released:
			# "Tried" is recorded here, at evaluation time, not when the
			# piece was dropped -- so repositioning pieces during the
			# "shape colocation" phase never burns an attempt by itself.
			cell.remember_tried(piece)
			# Back to full size for the scramble (release_wrong_pieces()'s
			# cancel_animation() already restored its mouse_filter).
			piece.scale = Vector2.ONE
		wrong_pieces.append_array(released)

	if wrong_pieces.is_empty():
		for cell in pending_empty_cells:
			cell.lock()
		state = State.WON
		result_label.text = "Solved in %s!" % chronometer_label.text
	else:
		tray.launch_from(wrong_pieces, board, Tray.ALL_SIDES)
