extends RefCounted
class_name PuzzleParameters

# What a difficulty level sets only for Puzzle mode (see PuzzleMode).

# move_margin value for a round with no move limit at all.
const NO_MOVE_LIMIT := -1

# Seconds the countdown starts from -- reaching zero loses the round.
var solve_seconds: float = 60.0
# Moves allowed on top of the round's best solution (see BestSolution) --
# one more and the round is lost. NO_MOVE_LIMIT for no limit.
var move_margin: int = NO_MOVE_LIMIT
# Seconds still on the countdown at which SOLVE TIME points stop decreasing
# (see ModeRules.time_points()).
var score_floor_seconds_left: float = 10.0

static func from_dict(values: Dictionary) -> PuzzleParameters:
	var parameters := PuzzleParameters.new()
	parameters.solve_seconds = values["solve_seconds"]
	parameters.move_margin = values["move_margin"]
	parameters.score_floor_seconds_left = values["score_floor_seconds_left"]
	return parameters

func has_move_limit() -> bool:
	return move_margin != NO_MOVE_LIMIT
