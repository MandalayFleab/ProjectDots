extends Control

const ShapePieceScene := preload("res://scenes/shape_piece/shape_piece.tscn")

enum State { SHOWING, PLAYING, WON }

# UI chrome (Combiner, Divisor, Replay button, the info labels) is scaled
# from the SCREEN's own size, not from board.cell_size -- cell_size varies
# round to round purely from the random row/column count LevelGenerator
# picks (fewer cells means bigger individual cells for the same budget),
# which has nothing to do with the device. Tying UI chrome to it made those
# elements balloon or shrink on every replay independent of the screen,
# causing exactly the kind of overlap a fixed-per-device size avoids: the
# same screen always produces the same UI chrome size, no matter what board
# that particular round happens to generate.
const REFERENCE_SCREEN_MIN_DIMENSION := 648.0

# How long the viewport must sit still before a live resize is treated as
# "settled" and actually relaid out. Browsers fire resize continuously while
# a window is being dragged -- without this, every single intermediate
# frame would trigger a full board/tray/UI recompute.
const RESIZE_SETTLE_SECONDS := 0.3

@onready var board: Board = $Board
@onready var tray: Tray = $Tray
@onready var combiner: Combiner = $Combiner
@onready var divisor: Divisor = $Divisor
@onready var reveal_timer: Timer = $RevealTimer
@onready var chronometer_label: Label = $ChronometerLabel
@onready var result_label: Label = $ResultLabel
@onready var replay_button: Button = $ReplayButton
@onready var mistakes_label: Label = $MistakesLabel

var state: State = State.SHOWING
var elapsed_time: float = 0.0
var level: LevelData
var mistakes: int = 0

# Uniform multiplier over every chrome size/margin in _layout_metrics(), on
# top of the screen-based "s" scale -- lets the debug layout panel (F1,
# debug builds only) test "what if the chrome took up more/less room" live,
# separately from "what if the board itself were bigger/smaller"
# (board.board_size_ratio). 0.75 is the value compared and picked via that
# panel, alongside board_size_ratio = 1.0.
var chrome_scale: float = 0.70

var _ready_for_resize: bool = false
var _resize_watch_active: bool = false
var _last_resize_time: float = 0.0

func _ready() -> void:
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
# forces an immediate reflow after the user drags a proportion slider,
# reusing the exact same code path a live resize goes through.
func apply_layout_now() -> void:
	_relayout_for_resize()

# Live counterpart to _new_game()'s layout pass: reflows the board, tray,
# Combiner/Divisor and UI chrome to the new screen size in place, without
# touching the level, locked cells, placed pieces, elapsed time or mistakes
# -- a resize should never cost the player their progress.
func _relayout_for_resize() -> void:
	while size.x <= 0.0 or size.y <= 0.0:
		await get_tree().process_frame

	var old_tray_size: Vector2 = tray.size
	var safe_rect: Rect2 = _safe_board_rect()
	var scale_factor: float = board.relayout(safe_rect.size)
	board.position = safe_rect.position + (safe_rect.size - board.size) * 0.5

	tray.size = size
	tray.rescale(scale_factor, old_tray_size, tray.size)

	_apply_ui_scale()
	combiner.rescale(scale_factor)
	divisor.piece_size = board.cell_size * 0.8

	tray.exclusion_rects = [
		Rect2(board.position, board.size),
		Rect2(combiner.position, combiner.size),
		Rect2(divisor.position, divisor.size),
	]

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
	var safe_rect: Rect2 = _safe_board_rect()
	board.build(level, tray, safe_rect.size)
	for cell in board.get_cells():
		cell.piece_changed.connect(_on_piece_changed)
	Selection.set_cells(board.get_cells())

	board.position = safe_rect.position + (safe_rect.size - board.size) * 0.5
	combiner.tray = tray
	divisor.tray = tray
	divisor.piece_size = board.cell_size * 0.8
	_apply_ui_scale()
	tray.exclusion_rects = [
		Rect2(board.position, board.size),
		Rect2(combiner.position, combiner.size),
		Rect2(divisor.position, divisor.size),
	]
	_start_round()
	_ready_for_resize = true

# Single source of truth for every UI-chrome size, shared by _apply_ui_scale()
# (which positions the chrome) and _safe_board_rect() (which carves out the
# area the board is allowed to grow into). Keeping them derived from the same
# numbers is the actual point -- the board must never be free to size itself
# into a region the chrome already claims.
func _layout_metrics() -> Dictionary:
	var s: float = clampf(min(size.x, size.y) / REFERENCE_SCREEN_MIN_DIMENSION, 0.5, 2.0) * chrome_scale
	return {
		"s": s,
		"margin": 20.0 * s,
		"combiner_divisor_side": 160.0 * s,
		"button_size": Vector2(120.0, 40.0) * s,
		"chrono_size": Vector2(160.0, 32.0) * s,
		"mistakes_size": Vector2(200.0, 32.0) * s,
		"result_size": Vector2(400.0, 32.0) * s,
	}

# Scales and repositions every "playable item" and "informative item" that
# isn't the board/pieces (Combiner, Divisor, Replay button, the chronometer/
# mistakes/result labels). Deliberately based on the screen's own size, not
# board.cell_size -- see the constant's comment above. Clamped so a tiny
# phone doesn't shrink UI chrome into illegibility, and a huge monitor
# doesn't balloon it into something cartoonish.
func _apply_ui_scale() -> void:
	var m: Dictionary = _layout_metrics()
	var s: float = m["s"]
	var margin: float = m["margin"]

	var combiner_divisor_side: float = m["combiner_divisor_side"]
	# Shifted up by the hold-charge bar's height (Divisor too, purely to stay
	# visually level with Combiner) -- otherwise the bar, drawn just below
	# Combiner's own square, would spill past the bottom of the screen.
	var hold_bar_extra: float = combiner_divisor_side * (Combiner.HOLD_BAR_GAP_RATIO + Combiner.HOLD_BAR_HEIGHT_RATIO)
	var bottom_row_y: float = size.y - margin - hold_bar_extra - combiner_divisor_side
	combiner.size = Vector2(combiner_divisor_side, combiner_divisor_side)
	combiner.position = Vector2(margin, bottom_row_y)
	divisor.size = Vector2(combiner_divisor_side, combiner_divisor_side)
	divisor.position = Vector2(size.x - margin - combiner_divisor_side, bottom_row_y)

	var button_size: Vector2 = m["button_size"]
	replay_button.size = button_size
	replay_button.position = Vector2(size.x - margin - button_size.x, margin)
	replay_button.add_theme_font_size_override("font_size", maxi(int(20.0 * s), 10))

	var chrono_size: Vector2 = m["chrono_size"]
	chronometer_label.size = chrono_size
	chronometer_label.position = Vector2(margin, margin)
	chronometer_label.add_theme_font_size_override("font_size", maxi(int(28.0 * s), 12))

	var mistakes_size: Vector2 = m["mistakes_size"]
	mistakes_label.size = mistakes_size
	mistakes_label.position = Vector2(margin, margin + chrono_size.y + 8.0 * s)
	mistakes_label.add_theme_font_size_override("font_size", maxi(int(22.0 * s), 10))

	var result_size: Vector2 = m["result_size"]
	result_label.size = result_size
	result_label.position = Vector2((size.x - result_size.x) * 0.5, margin)
	result_label.add_theme_font_size_override("font_size", maxi(int(28.0 * s), 12))

# The rectangle the board is allowed to grow into: the full screen minus a
# top band (chronometer/mistakes/replay/result) and a bottom band (Combiner/
# Divisor), each with their own margin on top of that. Board.build()/
# relayout() treat this as "available space" instead of the raw screen --
# handing them the whole screen (the previous approach) is exactly how the
# board ended up overlapping the chrome on smaller or squarer screens, since
# nothing stopped it from growing into the same corners the chrome occupies.
func _safe_board_rect() -> Rect2:
	var m: Dictionary = _layout_metrics()
	var s: float = m["s"]
	var margin: float = m["margin"]
	var chrono_size: Vector2 = m["chrono_size"]
	var mistakes_size: Vector2 = m["mistakes_size"]

	var top_block_height: float = max(chrono_size.y + 8.0 * s + mistakes_size.y, m["button_size"].y)
	var top_reserved: float = margin + top_block_height + margin

	# Combiner draws its hold-charge bar just below its own square (see
	# combiner.gd) -- reserve room for that strip too, or it'd get clipped
	# against (or overlap) the board/tray on a short screen.
	var combiner_divisor_side: float = m["combiner_divisor_side"]
	var hold_bar_extra: float = combiner_divisor_side * (Combiner.HOLD_BAR_GAP_RATIO + Combiner.HOLD_BAR_HEIGHT_RATIO)
	var bottom_reserved: float = margin + combiner_divisor_side + hold_bar_extra + margin

	var rect_position := Vector2(margin, top_reserved)
	var rect_size := Vector2(
		max(size.x - margin * 2.0, 0.0),
		max(size.y - top_reserved - bottom_reserved, 0.0)
	)
	return Rect2(rect_position, rect_size)

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

func _on_reveal_timer_timeout() -> void:
	for cell in board.get_cells():
		for child in cell.get_children():
			child.queue_free()

	var piece_size: Vector2 = board.cell_size * 0.8
	var pieces: Array[ShapePiece] = []
	for spec in level.shapes_to_place:
		var piece := ShapePieceScene.instantiate() as ShapePiece
		piece.shape_type = spec.shape_type
		piece.color = spec.color
		piece.size = piece_size
		pieces.append(piece)

	state = State.PLAYING
	# Tray's size comes from anchors, not an explicit assignment like Board's --
	# force it in sync with the root's (reliably measured) size right before
	# scattering, instead of trusting anchor propagation already happened.
	tray.size = size
	tray.scatter(pieces)

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
	var open_cells: Array = []
	for cell in board.get_cells():
		if not cell.locked:
			open_cells.append(cell)
	_check_solution(open_cells)

func _check_solution(open_cells: Array) -> void:
	var wrong_pieces: Array[ShapePiece] = []
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
			var released: Array[ShapePiece] = cell.release_wrong_pieces()
			for piece in released:
				# "Tried" is recorded here, at evaluation time, not when the
				# piece was dropped -- so repositioning pieces during the
				# "shape colocation" phase never burns an attempt by itself.
				cell.remember_tried(piece)
			wrong_pieces.append_array(released)
	mistakes_label.text = "Mistakes: %d" % mistakes

	if wrong_pieces.is_empty():
		for cell in pending_empty_cells:
			cell.lock()
		state = State.WON
		result_label.text = "Solved in %s!" % chronometer_label.text
	else:
		tray.size = size
		tray.scatter(wrong_pieces)
