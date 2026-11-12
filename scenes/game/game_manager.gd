extends Control
class_name GameManager

const ShapePieceScene := preload("res://scenes/shape_piece/shape_piece.tscn")

enum State { SHOWING, PLAYING, WON, LOST }
enum LayoutMode { AUTO, HORIZONTAL, VERTICAL }
# What each mode does differently (how a round starts, what's counted, when
# it's lost) lives in its ModeRules -- MemoryMode and PuzzleMode.
enum GameMode { MEMORY, PUZZLE }

# After every layout pass -- lets the debug layout panel follow an automatic
# switch between the horizontal and vertical distributions.
signal layout_applied
# The player asked to leave the game (in-game options > MAIN MENU).
signal exit_requested

# How long the viewport must sit still before a live resize is treated as
# "settled" and actually relaid out. Browsers fire resize continuously while
# a window is being dragged -- without this, every single intermediate
# frame would trigger a full board/tray/UI recompute.
const RESIZE_SETTLE_SECONDS := 0.3

# How long the solution previews take to shrink away once the reveal time is
# up, before the pieces are scrambled out of the board.
const PREVIEW_SHRINK_SECONDS := 0.4

# The "+15" that pops up under the timer when HELP adds its time penalty (or
# the "-5" Memory mode takes off for a round solved without the indicator):
# starts green at PENALTY_FONT_RATIO of the timer's font size, and floats up
# while fading out to a desaturated grey and shrinking to PENALTY_END_SCALE.
const PENALTY_FONT_RATIO := 1.6
const PENALTY_END_SCALE := 0.3
const PENALTY_COLOR := Color(0.3, 0.9, 0.4)
const PENALTY_FADED_COLOR := Color(0.6, 0.6, 0.6, 0.0)
const PENALTY_FLOAT_SECONDS := 2.0

# How long a solved board stays on screen before the score shows up: the
# end screen, or in infinite mode the score so far, before the next round.
const SOLVED_HOLD_SECONDS := 1.5
# Infinite mode: how long the score so far stays up between rounds.
const INFINITE_SCORE_SECONDS := 3.0

@onready var board: Board = $Board
@onready var tray: Tray = $Tray
@onready var shifter: ShapeShifter = $ShapeShifter
@onready var divisor: Divisor = $Divisor
@onready var chronometer_label: Label = $ChronometerLabel
@onready var mistakes_label: Label = $MistakesLabel
@onready var help_button: Button = $HelpButton
@onready var solution_preview: SolutionPreview = $SolutionPreview

# What the play screen picked -- set before this enters the tree (see App).
# Run on its own (e.g. this scene played from the editor), it's a quick game
# with whatever Settings hold.
var setup: GameSetup
var state: State = State.SHOWING
var level: LevelData
var game_mode: GameMode = GameMode.MEMORY
var difficulty_level: Difficulty.Level = Difficulty.Level.EASY
# The difficulty picked in the in-game options -- applied to the next round
# once the panel closes.
var _pending_difficulty: Difficulty.Level = Difficulty.Level.EASY
# This game's points so far (see ScoreTally) -- one round, or a whole
# infinite run.
var score := ScoreTally.new()

# One per GameMode, in its order.
var _modes: Array[ModeRules] = [MemoryMode.new(), PuzzleMode.new()]
var _options_panel := OverlayPanel.new()
var _end_screen := OverlayPanel.new(false, false, true)
# "Give up?" -- see _on_give_up_pressed().
var _give_up_confirm := OverlayPanel.new()
# Runs out SOLVED_HOLD_SECONDS after a round is solved.
var _solved_timer := Timer.new()
# Infinite mode: runs out INFINITE_SCORE_SECONDS after the score shows up.
var _next_round_timer := Timer.new()
# Infinite mode: each round's difficulty.
var _progression := InfiniteProgression.new()
# Whether the end screen up is the one that ends the game (with its
# buttons), not infinite mode's score between rounds.
var _end_screen_final: bool = false

# The menu zone's buttons, built from _menu_zone_slots(), and the slot each
# one sits in.
var _menu_entries: Array[MenuEntry] = []
var _menu_buttons: Array[Button] = []
var _menu_button_slots: Array[int] = []
var _menu_slot_count: int = 0

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
	for mode in _modes:
		mode.game = self
		mode.lost.connect(_on_round_lost)
		mode.time_penalty.connect(_show_time_penalty)
		add_child(mode)
	if setup == null:
		setup = GameSetup.from_settings(GameSetup.PlayType.QUICK)
	game_mode = setup.game_mode
	difficulty_level = setup.difficulty
	_pending_difficulty = difficulty_level
	Selection.places_indicator = setup.places_indicator
	# Before the overlays below, so these never take input meant for them.
	_build_menu_buttons()
	score.counts_strikes = setup.play_type == GameSetup.PlayType.INFINITE
	add_child(_end_screen)
	add_child(_options_panel)
	add_child(_give_up_confirm)
	_options_panel.closed.connect(_on_options_closed)
	_solved_timer.one_shot = true
	_solved_timer.timeout.connect(_on_solved_hold_over)
	add_child(_solved_timer)
	_next_round_timer.one_shot = true
	_next_round_timer.timeout.connect(_new_game)
	add_child(_next_round_timer)
	help_button.pressed.connect(_on_help_pressed)
	for item in [shifter, divisor]:
		item.used.connect(_count_move)
	await _new_game()

func active_mode() -> ModeRules:
	return _modes[game_mode]

# A new game from scratch: the score (and an infinite run's strike) resets.
func _on_replay_pressed() -> void:
	score.reset()
	_progression.reset()
	await _new_game()

func _is_quick() -> bool:
	return setup.is_quick()

func _is_infinite() -> bool:
	return setup.play_type == GameSetup.PlayType.INFINITE

# The menu zone's slots, top to bottom (left to right in the vertical
# distribution). A slot can hold several buttons as long as only one of them
# is ever shown at a time. Slots stay put whatever they show (or if they
# show nothing), so OPTIONS is in the same place in every game, and GIVE UP
# always sits at the far end, away from it.
func _menu_zone_slots() -> Array:
	return [
		[MenuEntry.button("OPTIONS", toggle_options)],
		[
			MenuEntry.button("REPLAY", _on_replay_pressed).shown_when(_is_quick),
			MenuEntry.button("GIVE UP", _on_give_up_pressed).shown_when(_can_give_up),
		],
	]

# Daily and infinite games have no REPLAY or MAIN MENU: the only way out
# is to give up, which ends the game on the end screen.
func _can_give_up() -> bool:
	return not setup.is_quick()

# What the in-game options panel lists, top to bottom.
func _options_entries() -> Array[MenuEntry]:
	return [
		MenuEntry.info("CURRENT SCORE:", func(): return _points_text(score.total())),
		MenuEntry.selector("DIFFICULTY:", Difficulty.level_display_names(),
			func(): return _pending_difficulty,
			func(index): _pending_difficulty = index as Difficulty.Level).shown_when(_is_quick),
		MenuEntry.checkbox("ASK BEFORE GIVING UP",
			func(): return Settings.confirm_give_up,
			func(on): Settings.confirm_give_up = on).shown_when(_can_give_up),
		MenuEntry.checkbox("ASK BEFORE NEXT LEVEL",
			func(): return Settings.ask_next_level,
			func(on): Settings.ask_next_level = on).shown_when(_is_infinite),
		MenuEntry.button("RESUME", _options_panel.close),
		MenuEntry.button("MAIN MENU", func(): exit_requested.emit()).shown_when(_is_quick),
	]

func _give_up_confirm_entries() -> Array[MenuEntry]:
	return [
		MenuEntry.heading("GIVE UP?", UiStyle.TITLE_FONT),
		MenuEntry.heading("This game ends here, with the points you have so far."),
		MenuEntry.button_row([
			MenuEntry.button("KEEP PLAYING", _give_up_confirm.close),
			MenuEntry.button("GIVE UP", _give_up),
		]),
	]

func _on_give_up_pressed() -> void:
	if Settings.confirm_give_up:
		Selection.deselect()
		_give_up_confirm.open(_give_up_confirm_entries())
	else:
		_give_up()

# Ends the game as a lost round -- or, if the round was already solved
# (infinite mode, before the next one comes), with what was scored so far.
func _give_up() -> void:
	_give_up_confirm.close()
	const OUTCOME := "You gave up."
	if state == State.WON:
		_solved_timer.stop()
		_next_round_timer.stop()
		var infinite := setup.play_type == GameSetup.PlayType.INFINITE
		_show_end_screen(OUTCOME if infinite else active_mode().won_text())
	else:
		var placed := _correctly_placed_count()
		_on_round_lost(OUTCOME, [["PLACED SHAPES\u00a0:\u00a0%d" % placed, placed * ModeRules.PLACED_SHAPE_POINTS]])

# Cells holding the shape they require right now -- locked in by a check or
# not yet checked alike.
func _correctly_placed_count() -> int:
	var count := 0
	for cell in board.get_cells():
		if cell.has_requirement() and cell.is_solved():
			count += 1
	return count

# The end screen, top to bottom: the level's outcome, the score in a box
# (its total, then where it came from), and -- once the game is over -- what
# to do next. What the box holds depends on the game:
#
#   quick / daily      FINAL SCORE: the level's total and its lines (see
#                      ModeRules.score_lines()).
#   infinite, between  LEVEL N SCORE: the level just solved, total and lines,
#   levels             then the run's TOTAL SCORE so far below the box -- and
#                      CONTINUE / GIVE UP when the player asked to wait
#                      (Settings.ask_next_level).
#   infinite, over     FINAL SCORE: the run's total, made of the SOLVED LEVELS
#                      added up, whatever the last (unsolved) level still paid
#                      (e.g. PLACED SHAPES on giving up), and the STRIKE.
func _end_screen_entries(outcome: String, final: bool) -> Array[MenuEntry]:
	var infinite := setup.play_type == GameSetup.PlayType.INFINITE
	var entries: Array[MenuEntry] = [MenuEntry.heading(outcome)]
	if not infinite:
		entries.append(MenuEntry.heading("FINAL SCORE", UiStyle.TITLE_FONT))
		entries.append(MenuEntry.group(_level_detail(score.last_level())))
	elif not final:
		entries.append(MenuEntry.heading("LEVEL %d SCORE" % score.level_count(), UiStyle.TITLE_FONT))
		entries.append(MenuEntry.group(_level_detail(score.last_level())))
		entries.append(MenuEntry.info("TOTAL SCORE", func(): return _points_text(score.total())))
		if Settings.ask_next_level:
			entries.append(MenuEntry.button_row([
				MenuEntry.button("CONTINUE", _new_game),
				MenuEntry.button("GIVE UP", _on_give_up_pressed),
			]))
	else:
		entries.append(MenuEntry.heading("FINAL SCORE", UiStyle.TITLE_FONT))
		var detail: Array = [
			MenuEntry.heading(_points_text(score.total(true)), UiStyle.TITLE_FONT),
			MenuEntry.info("SOLVED LEVELS", func(): return _points_text(score.solved_points(), true)),
		]
		var last := score.last_level()
		if last != null and not last.solved:
			for line in last.lines:
				if int(line[1]) > 0:
					detail.append(_score_line(line))
		detail.append(MenuEntry.info("STRIKE\u00a0:\u00a0%d" % score.strikes, func(): return _points_text(score.strike_points(), true)))
		entries.append(MenuEntry.group(detail))
	if final:
		entries.append(MenuEntry.button_row([
			MenuEntry.button("REPLAY", _on_replay_pressed),
			MenuEntry.button("BACK TO MAIN SCREEN", func(): exit_requested.emit()),
		]))
	return entries

# One level's total, then each of its lines.
func _level_detail(level: ScoreTally.Level) -> Array:
	var detail: Array = [MenuEntry.heading(_points_text(level.total() if level != null else 0), UiStyle.TITLE_FONT)]
	if level != null:
		for line in level.lines:
			detail.append(_score_line(line))
	return detail

static func _score_line(line: Array) -> MenuEntry:
	return MenuEntry.info(line[0], func(): return _points_text(line[1], true))

static func _points_text(points: int, signed: bool = false) -> String:
	return ("+%d POINTS" if signed else "%d POINTS") % points

func _show_end_screen(outcome: String, final: bool = true) -> void:
	_options_panel.close()
	Selection.deselect()
	_end_screen_final = final
	_end_screen.open(_end_screen_entries(outcome, final))

func _build_menu_buttons() -> void:
	var slots := _menu_zone_slots()
	_menu_slot_count = slots.size()
	for slot in slots.size():
		for entry in slots[slot]:
			var button := Button.new()
			button.text = entry.text
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func(): entry.action.call())
			add_child(button)
			_menu_entries.append(entry)
			_menu_buttons.append(button)
			_menu_button_slots.append(slot)
	_refresh_menu_buttons()

func _refresh_menu_buttons() -> void:
	for i in _menu_buttons.size():
		_menu_buttons[i].visible = _menu_entries[i].is_visible()
		_menu_buttons[i].disabled = not _menu_entries[i].is_enabled()

# Esc / Android back: the options panel -- or, once the game is over, back
# to the menus, as the end screen's own button does.
func toggle_options() -> void:
	if _give_up_confirm.visible:
		_give_up_confirm.close()
		return
	if _end_screen.visible:
		# Nothing to do while infinite mode shows the score between rounds.
		if _end_screen_final:
			exit_requested.emit()
		return
	if _options_panel.visible:
		_options_panel.close()
		return
	Selection.deselect()
	_options_panel.open(_options_entries())

# A new difficulty picked in the options starts a fresh round at it.
func _on_options_closed() -> void:
	if _pending_difficulty != difficulty_level:
		difficulty_level = _pending_difficulty
		await _new_game()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_options()
		get_viewport().set_input_as_handled()

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
	for mode in _modes:
		mode.stop()
	_solved_timer.stop()
	_next_round_timer.stop()
	_end_screen.close()
	_refresh_menu_buttons()
	Selection.deselect()
	Selection.set_cells([])
	tray.clear()
	shifter.clear()

	# On web, the browser canvas can take a couple of frames to report its
	# real size after load -- wait for this root Control to actually have one
	# before computing the board's cell size from it, instead of trusting a
	# single frame (or Board ends up sized for a near-zero area).
	while size.x <= 0.0 or size.y <= 0.0:
		await get_tree().process_frame

	if setup.play_type == GameSetup.PlayType.INFINITE:
		difficulty_level = _progression.next_level()
	var mode := active_mode()
	# A daily game's level only depends on the day (and the mode); the rest
	# of the round (the scramble, HELP's picks...) stays random.
	if setup.play_type == GameSetup.PlayType.DAILY:
		seed(setup.daily_seed())
	mode.apply_difficulty(difficulty_level)
	level = LevelGenerator.generate(mode.difficulty.general)
	if setup.play_type == GameSetup.PlayType.DAILY:
		randomize()
	mode.begin_round(level)
	_update_counter_label()
	solution_preview.visible = mode.shows_solution_preview()
	help_button.visible = mode.has_help()
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

# The menu zone's slots (see _menu_zone_slots()) -- stacked, or side by side
# in the vertical distribution, to keep its last row short. Every button is
# fitted from the same (longest) text, so they all come out the same size.
func _apply_menu(zone: Rect2, config: LayoutConfig) -> void:
	if _menu_slot_count == 0:
		return
	var shares: Array = []
	for slot in _menu_slot_count:
		shares.append(1.0 / _menu_slot_count)
	var sample := ""
	for button in _menu_buttons:
		if _text_width(button.text) > _text_width(sample):
			sample = button.text
	var rows := _cut(zone, not is_vertical_layout(), shares)
	for i in _menu_buttons.size():
		_fit_button(_menu_buttons[i], rows[_menu_button_slots[i]], sample, config.info_text_scale)

# The timer above the counter, both left-aligned in the info zone -- or,
# in the vertical distribution, side by side on one line (the counter just
# after the timer) centered in the zone, to keep its last row short. One font size is fitted so
# both always fit.
func _apply_info(zone: Rect2, config: LayoutConfig) -> void:
	var timer_sample: String = ModeRules.timer_text_for(0)
	var counter_sample: String = active_mode().counter_sample()
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

# Styled like the menus' buttons (see UiStyle), sized to fit `sample`.
func _fit_button(button: Button, row: Rect2, sample: String, text_scale: float) -> void:
	var font_size: int = _fit_font_size(sample, row.size.x * 0.75, row.size.y * 0.4, text_scale)
	# The style's border and corners follow the button's own size.
	UiStyle.style_button(button, font_size / UiStyle.LARGE_FONT, UiStyle.LARGE_FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.size = Vector2(minf(row.size.x, _text_width(sample) * font_size / 100.0 + font_size * 2.0), minf(row.size.y * 0.85, font_size * 2.2))
	button.position = row.get_center() - button.size * 0.5

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

# A move, as Puzzle mode counts them: every ShapeShifter combine, resize or
# long-press expel, Divisor split, piece put into a cell, and piece sent out
# of one (long press, eviction, or dragged out). Only counted while playing
# -- what the mode does with it is up to the mode.
func _count_move() -> void:
	if state != State.PLAYING:
		return
	active_mode().on_move()
	_update_counter_label()

# The info strip's counter: mistakes in Memory mode, moves in Puzzle mode.
func _update_counter_label() -> void:
	mistakes_label.text = active_mode().counter_text()

func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	active_mode().tick(delta)
	chronometer_label.text = active_mode().timer_text()

func _start_round() -> void:
	state = State.SHOWING
	update_help_button()
	chronometer_label.text = active_mode().timer_text()
	active_mode().start_round()

# `extra_lines` are score lines on top of the mode's own (see ScoreTally),
# e.g. what giving up is worth.
func _on_round_lost(reason: String, extra_lines: Array = []) -> void:
	if state != State.PLAYING and state != State.SHOWING:
		return
	state = State.LOST
	active_mode().stop()
	Selection.deselect()
	update_help_button()
	score.add_level(active_mode().score_lines(false) + extra_lines, false)
	_show_end_screen(reason)

# Shrinks each control toward its own center and resolves once they're gone,
# returning false if Replay was pressed meanwhile (the round no longer
# exists). The tweens are bound to the controls themselves, so a Replay
# mid-shrink frees them along with their cells, while the wait uses a scene
# timer that always fires. Input is ignored while shrinking -- callers that
# keep the controls afterwards reset scale and mouse_filter themselves.
func shrink_away(controls: Array) -> bool:
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

# The round's pieces come out of the board into the scramble zone (see
# LevelData.disposition), and play begins -- called by the mode once
# whatever comes first (e.g. Memory's reveal) is over.
func scramble_pieces() -> void:
	var piece_size: Vector2 = board.cell_size * 0.8
	var pieces: Array[ShapePiece] = []
	for group in level.disposition:
		pieces.append(_make_scramble_piece(group, piece_size))

	state = State.PLAYING
	update_help_button()
	tray.launch_from(pieces, board, Tray.ALL_SIDES)

# Infinite mode shows the score so far, then goes on to the next round (the
# score carries over) -- by itself, or on CONTINUE if the player asked to
# wait. Any other game is over.
func _on_solved_hold_over() -> void:
	if setup.play_type == GameSetup.PlayType.INFINITE:
		_show_end_screen(active_mode().won_text(), false)
		if not Settings.ask_next_level:
			_next_round_timer.start(INFINITE_SCORE_SECONDS)
	else:
		_show_end_screen(active_mode().won_text())

func update_help_button() -> void:
	help_button.disabled = not active_mode().can_help()

func _on_help_pressed() -> void:
	active_mode().help()

# Any jump of the timer outside its normal ticking (see
# ModeRules.time_penalty).
func _show_time_penalty(seconds: float) -> void:
	var label := Label.new()
	label.text = "%+d" % int(seconds)
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
			wrong_cells.append(cell)
	# A mistake is a misplaced shape: one per shape sitting in a wrong cell
	# (one needing another shape, or one that must stay empty). A wrong cell
	# with no shape in it -- one whose shape went somewhere else -- isn't a
	# mistake of its own, so a single misplaced shape never counts twice.
	var mistakes := 0
	for cell in wrong_cells:
		if cell.current_piece != null:
			mistakes += 1
	if mistakes > 0:
		active_mode().on_mistakes(mistakes)
	_update_counter_label()
	# Too many mistakes -- the board stays as it is under the end screen.
	if state != State.PLAYING:
		return

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
		var still_this_round: bool = await shrink_away(shrinking)
		_checking_solution = false
		# Replaced, or lost meanwhile (e.g. Puzzle's countdown ran out).
		if not still_this_round or state != State.PLAYING:
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
		active_mode().stop()
		active_mode().on_solved()
		chronometer_label.text = active_mode().timer_text()
		update_help_button()
		score.add_level(active_mode().score_lines(true), true)
		_solved_timer.start(SOLVED_HOLD_SECONDS)
	else:
		tray.launch_from(wrong_pieces, board, Tray.ALL_SIDES)
