extends ModeRules
class_name PuzzleMode

# Puzzle: no reveal -- a miniature of the solution (SolutionPreview) stays
# in the playable items zone for the whole round. A countdown runs from the
# level's solve time, and every move counts against a limit set from the
# round's best solution (see BestSolution).

var parameters: PuzzleParameters
# The fewest moves that solve this round (see BestSolution.moves()).
var best_solution: int = 0
var moves: int = 0
var time_left: float = 0.0

func display_name() -> String:
	return "Puzzle"

func apply_difficulty(level: Difficulty.Level) -> void:
	difficulty = Difficulty.for_puzzle(level)
	parameters = difficulty.puzzle

func shows_solution_preview() -> bool:
	return true

func begin_round(level: LevelData) -> void:
	moves = 0
	time_left = parameters.solve_seconds
	best_solution = BestSolution.moves(level)

# The most moves the round can take, or NO_MOVE_LIMIT.
func move_limit() -> int:
	if not parameters.has_move_limit():
		return PuzzleParameters.NO_MOVE_LIMIT
	return best_solution + parameters.move_margin

# Nothing to memorize first, so the pieces scramble out right away.
func start_round() -> void:
	game.scramble_pieces()

func tick(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0:
		lost.emit("Time's up!")

func on_move() -> void:
	moves += 1
	var limit := move_limit()
	if limit != PuzzleParameters.NO_MOVE_LIMIT and moves > limit:
		lost.emit("Out of moves: the limit was %d (best solution: %d)." % [limit, best_solution])

func timer_text() -> String:
	return timer_text_for(ceili(time_left))

func counter_text() -> String:
	var limit := move_limit()
	if limit == PuzzleParameters.NO_MOVE_LIMIT:
		return "%s %d" % [MOVES_ICON, moves]
	return "%s %d/%d" % [MOVES_ICON, moves, limit]

func counter_sample() -> String:
	if move_limit() == PuzzleParameters.NO_MOVE_LIMIT:
		return "%s 000" % MOVES_ICON
	return "%s 00/00" % MOVES_ICON

func won_text() -> String:
	return "Solved with %s left!" % format_time(ceili(time_left))

func score_lines(solved: bool) -> Array:
	return [
		["SOLVE TIME", time_points(parameters.solve_seconds - time_left, parameters.solve_seconds - parameters.score_floor_seconds_left) if solved else 0],
		["BEST SOLUTION", FLAWLESS_POINTS if solved and moves <= best_solution else 0],
	]
