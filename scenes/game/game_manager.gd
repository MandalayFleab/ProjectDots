extends Control

const ShapePieceScene := preload("res://scenes/shape_piece/shape_piece.tscn")

enum State { SHOWING, PLAYING, WON }
enum LayoutMode { AUTO, HORIZONTAL, VERTICAL }
# Memory: the solution shows on the board for a few seconds, then must be
# rebuilt from memory. Puzzle: no reveal -- a miniature of the solution
# (SolutionPreview) stays in the scramble zone for the whole round.
enum GameMode { MEMORY, PUZZLE }

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

# Placeholders in front of the info zone's texts. Only characters the
# built-in font has (e.g. × # • ∞), so they look the same on every platform
# -- emojis come from the system's own font, which a web export (Chrome)
# doesn't have.
const TIMER_ICON := "T"
const MISTAKES_ICON := "×"
const MOVES_ICON := "#"

# The "+15" that pops up under the timer when HELP adds its time penalty:
# starts green at PENALTY_FONT_RATIO of the timer's font size, and floats up
# while fading out to a desaturated grey and shrinking to PENALTY_END_SCALE.
const PENALTY_FONT_RATIO := 1.6
const PENALTY_END_SCALE := 0.3
const PENALTY_COLOR := Color(0.3, 0.9, 0.4)
const PENALTY_FADED_COLOR := Color(0.6, 0.6, 0.6, 0.0)
const PENALTY_FLOAT_SECONDS := 2.0

# The pause between HELP's auto-play moves, so each one reads on its own.
const HELP_STEP_PAUSE := 0.15
# Longest an auto-play step waits for the ShapeShifter/Divisor to send
# its result back before giving up -- input is off during the auto-play, so
# a step that never finished must never leave the game stuck.
const HELP_STEP_TIMEOUT := 3.0

@onready var board: Board = $Board
@onready var tray: Tray = $Tray
@onready var shifter: ShapeShifter = $ShapeShifter
@onready var divisor: Divisor = $Divisor
@onready var reveal_timer: Timer = $RevealTimer
@onready var chronometer_label: Label = $ChronometerLabel
@onready var result_label: Label = $ResultLabel
@onready var replay_button: Button = $ReplayButton
@onready var mistakes_label: Label = $MistakesLabel
@onready var mode_button: Button = $ModeButton
@onready var help_button: Button = $HelpButton
@onready var solution_preview: SolutionPreview = $SolutionPreview

var state: State = State.SHOWING
var elapsed_time: float = 0.0
var level: LevelData
var mistakes: int = 0
# Puzzle mode's counter in place of mistakes (see _count_move()).
var moves: int = 0
var game_mode: GameMode = GameMode.MEMORY
var help_uses_left: int = 0
# ShapeShifter/Divisor uses the current HELP auto-play has made so far
# (each one adds help_move_time_penalty).
var _help_moves: int = 0
var _help_penalty_applied: bool = false

# What each mode generates its levels from (see LevelSettings) -- kept
# separate so each mode can have its own board sizes and shape counts.
var memory_settings := LevelSettings.from_dict({"min_rows": 3, "max_rows": 5, "min_columns": 3, "max_columns": 5, "min_shapes": 2, "max_shapes": 5, "min_combined_color_shapes": 0, "max_combined_color_shapes": 2, "max_slack": 4, "max_filled_big_cells": 4, "help_uses": 1, "help_time_penalty": 15, "help_move_time_penalty": 5})
var puzzle_settings := LevelSettings.from_dict({"min_rows": 4, "max_rows": 6, "min_columns": 4, "max_columns": 6, "min_shapes": 5, "max_shapes": 9, "min_combined_color_shapes": 1, "max_combined_color_shapes": 3, "max_slack": 4, "max_filled_big_cells": 4})

# The two standard distributions (see LayoutConfig) -- which one applies
# depends only on the screen's shape, and each is tuned separately, so the
# same element can take a different proportion in each. Tuned live through
# the debug layout panel (F1, debug builds only), whose "Copy values" button
# prints these exact lines with the values picked there.
var horizontal_layout := LayoutConfig.from_dict({"side_ratio": 0.15, "board_ratio": 0.50, "menu_ratio": 0.15, "info_ratio": 0.08, "margin_ratio": 0.00, "board_fill": 1.00, "items_fill": 0.95, "info_text_scale": 1.00, "preview_ratio": 0.30})
var vertical_layout := LayoutConfig.from_dict({"side_ratio": 0.18, "board_ratio": 0.45, "menu_ratio": 0.45, "info_ratio": 0.25, "margin_ratio": 0.00, "board_fill": 1.00, "items_fill": 1.00, "info_text_scale": 1.00, "preview_ratio": 0.30})

# Debug layout panel only: forces one distribution whatever the screen's
# shape, so both can be tuned from the same window.
var orientation_override: LayoutMode = LayoutMode.AUTO

# Content rect of every zone ("menu", "items", "info", "board", "scramble") from the
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
	mode_button.toggled.connect(_on_mode_toggled)
	help_button.pressed.connect(_on_help_pressed)
	for item in [shifter, divisor]:
		item.used.connect(_count_move)
	_update_mode_button()
	await _new_game()

func _on_replay_pressed() -> void:
	await _new_game()

# Switching mode starts a fresh round in the new mode right away.
func _on_mode_toggled(puzzle: bool) -> void:
	game_mode = GameMode.PUZZLE if puzzle else GameMode.MEMORY
	_update_mode_button()
	await _new_game()

func _update_mode_button() -> void:
	mode_button.set_pressed_no_signal(game_mode == GameMode.PUZZLE)
	mode_button.text = "Puzzle" if game_mode == GameMode.PUZZLE else "Memory"

func _level_settings() -> LevelSettings:
	return puzzle_settings if game_mode == GameMode.PUZZLE else memory_settings

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

	_apply_zones()
	_reset_tray_walls()
	shifter.rescale(scale_factor)
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
	shifter.clear()
	result_label.text = ""
	mistakes = 0
	moves = 0
	_update_counter_label()

	# On web, the browser canvas can take a couple of frames to report its
	# real size after load -- wait for this root Control to actually have one
	# before computing the board's cell size from it, instead of trusting a
	# single frame (or Board ends up sized for a near-zero area).
	while size.x <= 0.0 or size.y <= 0.0:
		await get_tree().process_frame

	level = LevelGenerator.generate(_level_settings())
	solution_preview.visible = game_mode == GameMode.PUZZLE
	help_button.visible = game_mode == GameMode.MEMORY
	help_uses_left = _level_settings().help_uses
	solution_preview.show_level(level)
	zones = _compute_zones()
	board.build(level, tray, _board_budget())
	for cell in board.get_cells():
		cell.piece_changed.connect(_on_piece_changed)
		cell.piece_placed.connect(_count_move)
		cell.piece_expelled.connect(_count_move)
	Selection.set_cells(board.get_cells())

	_place_board()
	_place_tray()
	shifter.tray = tray
	divisor.tray = tray
	divisor.piece_size = board.cell_size * 0.8
	_apply_zones()
	_reset_tray_walls()
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
		# One top row across the first two columns: the menu over the items
		# (below) and the info over the scramble zone, at the same height --
		# the board keeps the full height of its own column.
		var scramble_parts := _cut(result["scramble"], true, [config.menu_ratio, 1.0 - config.menu_ratio])
		result["info"] = scramble_parts[0]
		result["scramble"] = scramble_parts[1]
	if vertical:
		# The bottom band: the items across its full width, over a last row
		# with the menu on the left and the info on the right.
		var rows := _cut(side_band, true, [1.0 - config.info_ratio, config.info_ratio])
		result["items"] = rows[0]
		var row_parts := _cut(rows[1], false, [config.menu_ratio, 1.0 - config.menu_ratio])
		result["menu"] = row_parts[0]
		result["info"] = row_parts[1]
	else:
		# The left column: the menu on top of the items.
		var halves := _cut(side_band, true, [config.menu_ratio, 1.0 - config.menu_ratio])
		result["menu"] = halves[0]
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

# Nothing else lives inside the scramble zone -- its own edges are the only
# walls. Reassigning also re-clamps every loose piece into the (possibly
# resized) zone, so it must run after Tray.rescale().
func _reset_tray_walls() -> void:
	var no_walls: Array[Rect2] = []
	tray.exclusion_rects = no_walls

func _apply_zones() -> void:
	var config := active_layout()
	_apply_items(zones["items"], config)
	_apply_menu(zones["menu"], config)
	_apply_info(zones["info"], config)
	_apply_result(zones["scramble"], config)

# The ShapeShifter and Divisor share the playable items zone in equal
# slots, laid along its longer side (a column in the horizontal distribution,
# a row in the vertical one). Puzzle mode's solution preview goes first in
# that same line (top of the column, left of the row), in its own slot taking
# preview_ratio of the zone's length. The slot is reserved in every mode (just
# empty in Memory), so the items keep the same size and position in both.
func _apply_items(zone: Rect2, config: LayoutConfig) -> void:
	var items: Array[Control] = [shifter, divisor]
	var in_row: bool = zone.size.x >= zone.size.y
	var parts := _cut(zone, not in_row, [config.preview_ratio, 1.0 - config.preview_ratio])
	var preview_slot: Rect2 = parts[0]
	var preview_side: float = minf(preview_slot.size.x, preview_slot.size.y) * config.items_fill
	var preview_rect := Rect2(preview_slot.get_center() - Vector2(preview_side, preview_side) * 0.5, Vector2(preview_side, preview_side))
	solution_preview.fit(preview_rect.position, preview_side)
	# Memory mode's HELP button takes the same spot the preview has in
	# Puzzle mode.
	help_button.add_theme_font_size_override("font_size", _fit_font_size("HELP", preview_side * 0.6, preview_side * 0.3, config.info_text_scale))
	help_button.size = preview_rect.size
	help_button.position = preview_rect.position
	var shares: Array = []
	for item in items:
		shares.append(1.0 / items.size())
	var slots := _cut(parts[1], not in_row, shares)
	# The ShapeShifter draws its hold-charge bar just below its own square --
	# all items are sized and placed as if they had one, so they stay the same
	# size and aligned with each other, and the bar never leaves the zone.
	var height_factor: float = 1.0 + ShapeShifter.HOLD_BAR_GAP_RATIO + ShapeShifter.HOLD_BAR_HEIGHT_RATIO
	var slot_size: Vector2 = slots[0].size
	var side: float = minf(slot_size.x, slot_size.y / height_factor) * config.items_fill
	for i in items.size():
		items[i].size = Vector2(side, side)
		items[i].position = slots[i].get_center() - Vector2(side, side * height_factor) * 0.5

# The mode switch above the Replay button, one row each -- side by side in
# the vertical distribution, to keep its last row short. Both are fitted
# from the same (longest) sample, so they come out the same size whatever
# the mode button currently says.
func _apply_menu(zone: Rect2, config: LayoutConfig) -> void:
	var rows := _cut(zone, not is_vertical_layout(), [0.5, 0.5])
	_fit_button(mode_button, rows[0], config.info_text_scale)
	_fit_button(replay_button, rows[1], config.info_text_scale)

# The timer above the counter, both left-aligned in the info zone -- or,
# in the vertical distribution, side by side on one line (the counter just
# after the timer) centered in the zone, to keep its last row short. One font size is fitted so
# both always fit.
func _apply_info(zone: Rect2, config: LayoutConfig) -> void:
	var timer_sample: String = _timer_text(0)
	var counter_sample: String = "%s 000" % MISTAKES_ICON
	if is_vertical_layout():
		_apply_info_in_line(zone, config, timer_sample, counter_sample)
		return
	var rows := _cut(zone, true, [0.5, 0.5])
	var widest: String = timer_sample if _text_width(timer_sample) >= _text_width(counter_sample) else counter_sample
	var font_size: int = _fit_font_size(widest, zone.size.x, rows[0].size.y * 0.7, config.info_text_scale)
	for i in 2:
		var label: Label = [chronometer_label, mistakes_label][i]
		label.add_theme_font_size_override("font_size", font_size)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = rows[i].size
		label.position = rows[i].position

func _apply_info_in_line(zone: Rect2, config: LayoutConfig, timer_sample: String, counter_sample: String) -> void:
	# A one-font-size gap (the "  ") between the two.
	var font_size: int = _fit_font_size(timer_sample + "  " + counter_sample, zone.size.x, zone.size.y * 0.7, config.info_text_scale)
	var timer_width: float = _text_width(timer_sample) * font_size / 100.0
	var counter_width: float = _text_width(counter_sample) * font_size / 100.0
	for label in [chronometer_label, mistakes_label]:
		label.add_theme_font_size_override("font_size", font_size)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The pair is centered as a whole, measured from the samples (not the
	# live texts) so it doesn't shift as the counter's digits change.
	var left: float = zone.position.x + maxf(zone.size.x - (timer_width + font_size + counter_width), 0.0) * 0.5
	chronometer_label.size = Vector2(timer_width, zone.size.y)
	chronometer_label.position = Vector2(left, zone.position.y)
	mistakes_label.size = Vector2(counter_width, zone.size.y)
	mistakes_label.position = Vector2(left + timer_width + font_size, zone.position.y)

static func _text_width(text: String) -> float:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x

func _fit_button(button: Button, row: Rect2, text_scale: float) -> void:
	var font_size: int = _fit_font_size("Memory", row.size.x * 0.7, row.size.y * 0.45, text_scale)
	button.add_theme_font_size_override("font_size", font_size)
	button.size = Vector2(minf(row.size.x, font_size * 5.5), minf(row.size.y * 0.85, font_size * 2.0))
	button.position = row.get_center() - button.size * 0.5

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

# Puzzle mode counts moves instead of mistakes: every ShapeShifter combine,
# resize or long-press expel, Divisor split, piece put into a cell, and
# piece sent out of one (long press, eviction, or dragged out). Memory mode
# only counts mistakes.
func _count_move() -> void:
	if game_mode != GameMode.PUZZLE or state != State.PLAYING:
		return
	moves += 1
	_update_counter_label()

# The info strip's counter: mistakes in Memory mode, moves in Puzzle mode.
func _update_counter_label() -> void:
	if game_mode == GameMode.PUZZLE:
		mistakes_label.text = "%s %d" % [MOVES_ICON, moves]
	else:
		mistakes_label.text = "%s %d" % [MISTAKES_ICON, mistakes]

static func _format_time(total_seconds: int) -> String:
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]

static func _timer_text(total_seconds: int) -> String:
	return "%s %s" % [TIMER_ICON, _format_time(total_seconds)]

func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	elapsed_time += delta
	chronometer_label.text = _timer_text(int(elapsed_time))

func _start_round() -> void:
	state = State.SHOWING
	_update_help_button()
	elapsed_time = 0.0
	chronometer_label.text = _timer_text(0)
	if game_mode == GameMode.PUZZLE:
		# The solution preview stays up the whole round -- nothing to
		# memorize first, so the pieces scramble out right away.
		_scramble_pieces()
		return
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
	_scramble_pieces()

func _scramble_pieces() -> void:
	var piece_size: Vector2 = board.cell_size * 0.8
	var pieces: Array[ShapePiece] = []
	for group in PieceDecomposer.random_disposition(level.shapes_to_place):
		pieces.append(_make_scramble_piece(group, piece_size))

	state = State.PLAYING
	_update_help_button()
	tray.launch_from(pieces, board, Tray.ALL_SIDES)

# Only while actually playing (not during the reveal, nor once won), and
# only while uses are left.
func _update_help_button() -> void:
	help_button.disabled = help_uses_left <= 0 or state != State.PLAYING

# Memory mode's HELP: plays one still-unsolved shape into its cell for the
# player, at the cost of a use and a time penalty: help_time_penalty, plus
# help_move_time_penalty for every ShapeShifter/Divisor use it took (see
# _help_plan()). Applied right before the final drag into the cell (see
# _help_move()), so it always matches the moves actually made, and still
# lands before that drag can win the round and stop the timer. When nothing
# can be placed at all, neither a use nor time is spent.
func _on_help_pressed() -> void:
	if help_uses_left <= 0 or state != State.PLAYING:
		return
	var plan := _help_plan()
	if plan.is_empty():
		return
	help_uses_left -= 1
	_update_help_button()

	# The auto-play takes a few moves -- the player sitting still for them
	# keeps a stray tap from grabbing a piece it's about to use.
	get_viewport().gui_disable_input = true
	_help_moves = 0
	_help_penalty_applied = false
	if plan["exact"]:
		await _help_move(plan["sources"][0], plan["cell"])
	else:
		await _help_build(plan["cell"], plan["sources"])
	get_viewport().gui_disable_input = false
	# An auto-play cut short by a timed-out step still pays for what it did.
	_apply_help_penalty()

func _apply_help_penalty() -> void:
	if _help_penalty_applied or state != State.PLAYING:
		return
	_help_penalty_applied = true
	var settings := _level_settings()
	var penalty: float = settings.help_time_penalty + _help_moves * settings.help_move_time_penalty
	if penalty > 0.0:
		elapsed_time += penalty
		_show_time_penalty(penalty)

func _show_time_penalty(seconds: float) -> void:
	var label := Label.new()
	label.text = "+%d" % int(seconds)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", maxi(int(chronometer_label.get_theme_font_size("font_size") * PENALTY_FONT_RATIO), 8))
	label.add_theme_color_override("font_color", PENALTY_COLOR)
	add_child(label)
	label.reset_size()
	# Just after the timer's text, rising up from under it.
	var timer_font_size: int = chronometer_label.get_theme_font_size("font_size")
	var timer_width: float = ThemeDB.fallback_font.get_string_size(chronometer_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, timer_font_size).x
	var start := Vector2(chronometer_label.position.x + timer_width + timer_font_size * 0.3, chronometer_label.position.y + chronometer_label.size.y * 0.8)
	# Kept on screen when the timer sits at its bottom edge (vertical).
	start.y = minf(start.y, size.y - label.size.y)
	label.position = start
	# Shrinks toward its own center.
	label.pivot_offset = label.size * 0.5
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "scale", Vector2.ONE * PENALTY_END_SCALE, PENALTY_FLOAT_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(label, "position:y", start.y - label.size.y, PENALTY_FLOAT_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(color: Color): label.add_theme_color_override("font_color", color),
		PENALTY_COLOR, PENALTY_FADED_COLOR, PENALTY_FLOAT_SECONDS)
	tween.chain().tween_callback(label.queue_free)

# Picks one random unsolved cell and the pieces HELP will play into it:
# {"cell", "sources", "exact"}, or {} if no cell can be helped.
#
# Prefers cells with an exactly matching piece available -- loose in the
# scramble zone, sitting in some other cell it doesn't solve, or held by the
# ShapeShifter -- which simply travels into the cell ("exact"). Otherwise picks
# the fewest pieces that hold the units the cell needs, which _help_build()
# then runs through the Divisor/ShapeShifter exactly as a player would.
func _help_plan() -> Dictionary:
	var pieces: Array = tray.get_children().filter(func(c): return c is ShapePiece and c.visible)
	for cell in board.get_cells():
		if not cell.locked and cell.current_piece != null and not cell.is_solved():
			pieces.append(cell.current_piece)
	if shifter.held_piece != null:
		pieces.append(shifter.held_piece)
	pieces = pieces.filter(func(p): return not p.is_in_group(ShapePiece.MOVING_GROUP))

	var exact := {}
	var builds := {}
	for cell in board.get_cells():
		if cell.locked or not cell.has_requirement() or cell.is_solved():
			continue
		var fitting: Array = pieces.filter(func(p): return p.is_big == cell.expects_big() \
			and p.shape_type == cell.required_spec.shape_type and p.color == cell.required_spec.color)
		if not fitting.is_empty():
			exact[cell] = fitting
			continue
		var sources := _build_sources(PieceDecomposer.to_units(cell.required_spec, cell.expects_big()), pieces)
		if not sources.is_empty():
			builds[cell] = sources

	if not exact.is_empty():
		var cell: BoardCell = exact.keys().pick_random()
		return {"cell": cell, "sources": [exact[cell].pick_random()], "exact": true}
	if not builds.is_empty():
		var cell: BoardCell = builds.keys().pick_random()
		return {"cell": cell, "sources": builds[cell], "exact": false}
	return {}

# Drags a piece into a cell the same way tap-to-place does, and waits for it
# to land. Always HELP's last move, so its penalty is settled here first.
func _help_move(piece: ShapePiece, cell: BoardCell) -> void:
	_apply_help_penalty()
	if Selection.selected_piece == piece:
		Selection.deselect()
	cell.place_piece(piece, true)
	await get_tree().create_timer(Selection.MOVE_DURATION + HELP_STEP_PAUSE).timeout

# Drags a piece into the ShapeShifter or Divisor and returns what comes
# back out into the tray -- [] if nothing did within HELP_STEP_TIMEOUT.
func _help_use_item(item: Control, piece: ShapePiece) -> Array:
	if Selection.selected_piece == piece:
		Selection.deselect()
	_help_moves += 1
	var result: Array = []
	var collect := func(pieces: Array): result.append_array(pieces)
	item.produced.connect(collect, CONNECT_ONE_SHOT)
	item.place_piece(piece, true)
	var deadline: float = Time.get_ticks_msec() / 1000.0 + HELP_STEP_TIMEOUT
	while result.is_empty() and Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().process_frame
	if item.produced.is_connected(collect):
		item.produced.disconnect(collect)
	await get_tree().create_timer(HELP_STEP_PAUSE).timeout
	return result

# Drags two single units into the ShapeShifter, one after the other, and returns
# the (always big) piece it makes, or null if it never came out. Clears out
# anything else the player left in there first, so it doesn't get combined
# (or swapped) with ours.
func _help_combine(a: ShapePiece, b: ShapePiece) -> ShapePiece:
	if shifter.held_piece == b:
		var swap := a
		a = b
		b = swap
	if shifter.held_piece != null and shifter.held_piece != a:
		shifter.expel_held()
		await get_tree().create_timer(HELP_STEP_PAUSE).timeout
	if shifter.held_piece != a:
		if Selection.selected_piece == a:
			Selection.deselect()
		shifter.place_piece(a, true)
		await get_tree().create_timer(Selection.MOVE_DURATION + HELP_STEP_PAUSE).timeout
	var result: Array = await _help_use_item(shifter, b)
	return null if result.is_empty() else result[0]

# Builds the cell's piece out of `sources` the way a player would, one
# visible move at a time, then drags it into the cell:
#   1. A source holding exactly the cell's units, just at the other size (a
#      mixed colour), goes through the ShapeShifter to switch size.
#   2. Otherwise every two-unit source goes through the Divisor first, and
#      only the halves the cell needs are kept (the rest stay in the tray).
#   3. Two needed units are combined in the ShapeShifter -- and, if the cell
#      wants a normal-size mixed colour, the (always big) result goes back in
#      to shrink.
# Stops wherever a step times out (see _help_use_item()); whatever was made
# so far just stays in the tray.
func _help_build(cell: BoardCell, sources: Array) -> void:
	var needed := PieceDecomposer.to_units(cell.required_spec, cell.expects_big())
	var exact_units = _subtract_units(_units_of(sources[0]), needed)
	if sources.size() == 1 and exact_units != null and exact_units.is_empty():
		var resized: Array = await _help_use_item(shifter, sources[0])
		if not resized.is_empty():
			await _help_move(resized[0], cell)
		return

	var remaining: Array[PieceSpec] = needed.duplicate()
	var singles: Array[ShapePiece] = []
	for source in sources:
		var parts: Array = [source]
		if _units_of(source).size() == 2:
			parts = await _help_use_item(divisor, source)
			if parts.is_empty():
				return
		for part in parts:
			var left = _subtract_units(remaining, _units_of(part))
			if left != null:
				remaining = left
				singles.append(part)

	if singles.size() != needed.size():
		return
	var result: ShapePiece = singles[0]
	if needed.size() == 2:
		result = await _help_combine(singles[0], singles[1])
		if result == null:
			return
		if not cell.expects_big():
			var resized: Array = await _help_use_item(shifter, result)
			if resized.is_empty():
				return
			result = resized[0]
	await _help_move(result, cell)

# The primary units a piece is made of (see PieceDecomposer).
static func _units_of(piece: ShapePiece) -> Array[PieceSpec]:
	if piece.original_a != null:
		return [piece.original_a, piece.original_b]
	return [PieceSpec.new(piece.shape_type, piece.color)]

# `units` minus every unit in `needed` (matched by shape and colour), or
# null if `units` doesn't hold all of them.
static func _subtract_units(units: Array[PieceSpec], needed: Array[PieceSpec]) -> Variant:
	var left: Array[PieceSpec] = units.duplicate()
	for unit in needed:
		var index := -1
		for i in left.size():
			if left[i].shape_type == unit.shape_type and left[i].color == unit.color:
				index = i
				break
		if index < 0:
			return null
		left.remove_at(index)
	return left

# The fewest pieces (one, or else two) that together hold every unit in
# `needed`, picked at random among the options, or [] if no such pieces
# exist.
func _build_sources(needed: Array[PieceSpec], pieces: Array) -> Array:
	var options: Array = []
	for piece in pieces:
		if _subtract_units(_units_of(piece), needed) != null:
			options.append([piece])
	if options.is_empty() and needed.size() == 2:
		for a in pieces.size():
			for b in range(a + 1, pieces.size()):
				var units: Array[PieceSpec] = _units_of(pieces[a])
				units.append_array(_units_of(pieces[b]))
				if _subtract_units(units, needed) != null:
					options.append([pieces[a], pieces[b]])
	return [] if options.is_empty() else options.pick_random()

# One group from PieceDecomposer.random_disposition(): a single unit makes a
# normal primary piece, a pair goes through the same setup_pair() the
# ShapeShifter uses, so the Divisor/ShapeShifter treat it exactly like one of theirs.
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
	# sitting unplaced in the ShapeShifter isn't in the tray either, but it also
	# isn't resolving anything, so it must block readiness too.
	if tray.get_child_count() > 0 or shifter.held_piece != null:
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
	_update_counter_label()

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
		_update_help_button()
		result_label.text = "Solved in %s!" % _format_time(int(elapsed_time))
	else:
		tray.launch_from(wrong_pieces, board, Tray.ALL_SIDES)
