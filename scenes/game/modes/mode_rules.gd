extends Node
class_name ModeRules

# What changes between game modes. game_manager owns the board, the layout,
# the scramble and the solution check; a ModeRules decides how a round
# starts once the board is built, what the info zone counts, and when the
# round is lost (see `lost`). One instance per mode lives as a child of the
# game for the whole session -- each round only resets it (begin_round()).

# The round can't be won any more -- `reason` is shown on the end screen.
signal lost(reason: String)
# Whenever the timer jumps by `seconds` outside of its normal ticking (HELP's
# "+15", the indicator-off bonus...) -- so the game can show it.
signal time_penalty(seconds: float)

# Placeholders in front of the info zone's texts. Only characters the
# built-in font has (e.g. × # • ∞), so they look the same on every platform
# -- emojis come from the system's own font, which a web export (Chrome)
# doesn't have.
const TIMER_ICON := "T"
const MISTAKES_ICON := "×"
const MOVES_ICON := "#"

# Scoring shared by every mode. SOLVE TIME: MAX_TIME_POINTS for solving
# within FULL_POINTS_SECONDS, then down in a straight line to
# MIN_TIME_POINTS at the difficulty's floor time, and MIN_TIME_POINTS from
# there on. A flawless round (each mode says what that means) adds
# FLAWLESS_POINTS. An unsolved round is worth nothing.
const MAX_TIME_POINTS := 20000
const MIN_TIME_POINTS := 1000
const FULL_POINTS_SECONDS := 5.0
const FLAWLESS_POINTS := 5000
# Giving up: what each shape already in its right cell is worth (on top of
# the unsolved round's zeros), so a half-solved board beats an untouched one.
const PLACED_SHAPE_POINTS := 250

var game: GameManager
var difficulty: Difficulty

# Name shown on the mode switch.
func display_name() -> String:
	return ""

# This mode's parameters for the given level (see Difficulty).
func apply_difficulty(_level: Difficulty.Level) -> void:
	pass

func shows_solution_preview() -> bool:
	return false

func has_help() -> bool:
	return false

func can_help() -> bool:
	return false

func help() -> void:
	pass

# A new round is about to be built from `level`: reset every counter.
func begin_round(_level: LevelData) -> void:
	pass

# The board is built -- does whatever comes before the pieces scramble out,
# and then calls game.scramble_pieces().
func start_round() -> void:
	game.scramble_pieces()

# The round is over (won, lost, or replaced) -- stops anything still pending.
func stop() -> void:
	pass

# Called every frame while the round is being played.
func tick(_delta: float) -> void:
	pass

# A Puzzle-mode move was made (see game_manager._count_move()).
func on_move() -> void:
	pass

# A solution check found `count` misplaced shapes.
func on_mistakes(_count: int) -> void:
	pass

func timer_text() -> String:
	return timer_text_for(0)

func counter_text() -> String:
	return ""

# The widest counter_text() can get this round, for the info zone's layout.
func counter_sample() -> String:
	return counter_text()

func won_text() -> String:
	return "Solved!"

# The round was just solved (before its score is taken).
func on_solved() -> void:
	pass

# SOLVE TIME points for solving in `solve_seconds`, when the points stop
# decreasing at `floor_seconds`.
static func time_points(solve_seconds: float, floor_seconds: float) -> int:
	if solve_seconds <= FULL_POINTS_SECONDS:
		return MAX_TIME_POINTS
	if solve_seconds >= floor_seconds:
		return MIN_TIME_POINTS
	var progress: float = (solve_seconds - FULL_POINTS_SECONDS) / (floor_seconds - FULL_POINTS_SECONDS)
	return roundi(lerpf(MAX_TIME_POINTS, MIN_TIME_POINTS, progress))

# What the round that just ended is worth, by category: [[label, points]...]
# (see ScoreTally). Every category is listed even when it earns nothing, so
# the end screen always shows the same lines for a mode.
func score_lines(_solved: bool) -> Array:
	return []

static func format_time(total_seconds: int) -> String:
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]

static func timer_text_for(total_seconds: int) -> String:
	return "%s %s" % [TIMER_ICON, format_time(total_seconds)]

func _is_playing() -> bool:
	return game != null and game.state == GameManager.State.PLAYING
