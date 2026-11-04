extends Node
class_name ModeRules

# What changes between game modes. game_manager owns the board, the layout,
# the scramble and the solution check; a ModeRules decides how a round
# starts once the board is built, what the info zone counts, and when the
# round is lost (see `lost`). One instance per mode lives as a child of the
# game for the whole session -- each round only resets it (begin_round()).

# The round can't be won any more -- `reason` is shown on the lose screen.
signal lost(reason: String)

# Placeholders in front of the info zone's texts. Only characters the
# built-in font has (e.g. × # • ∞), so they look the same on every platform
# -- emojis come from the system's own font, which a web export (Chrome)
# doesn't have.
const TIMER_ICON := "T"
const MISTAKES_ICON := "×"
const MOVES_ICON := "#"

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

# A solution check found `count` wrong cells.
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

static func format_time(total_seconds: int) -> String:
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]

static func timer_text_for(total_seconds: int) -> String:
	return "%s %s" % [TIMER_ICON, format_time(total_seconds)]

func _is_playing() -> bool:
	return game != null and game.state == GameManager.State.PLAYING
