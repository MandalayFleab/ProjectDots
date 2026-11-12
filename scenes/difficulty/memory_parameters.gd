extends RefCounted
class_name MemoryParameters

# What a difficulty level sets only for Memory mode (see MemoryMode).

# Mistakes the player can make -- one more and the round is lost.
var mistakes_allowed: int = 5
# Times per round the HELP button can be used.
var help_uses: int = 1
# Seconds the solution shows on the board before it must be rebuilt.
var reveal_seconds: float = 3.0
# Seconds taken off the solve time (once solved) when the round was played
# with the allowed places indicator off.
var indicator_off_time_reduction: float = 5.0
# Solve time at which SOLVE TIME points stop decreasing (see
# ModeRules.time_points()).
var score_floor_seconds: float = 30.0

static func from_dict(values: Dictionary) -> MemoryParameters:
	var parameters := MemoryParameters.new()
	parameters.mistakes_allowed = values["mistakes_allowed"]
	parameters.help_uses = values["help_uses"]
	parameters.reveal_seconds = values["reveal_seconds"]
	parameters.indicator_off_time_reduction = values["indicator_off_time_reduction"]
	parameters.score_floor_seconds = values["score_floor_seconds"]
	return parameters
