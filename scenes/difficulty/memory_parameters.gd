extends RefCounted
class_name MemoryParameters

# What a difficulty level sets only for Memory mode (see MemoryMode).

# Mistakes the player can make -- one more and the round is lost.
var mistakes_allowed: int = 5
# Times per round the HELP button can be used.
var help_uses: int = 1
# Seconds the solution shows on the board before it must be rebuilt.
var reveal_seconds: float = 3.0
# Time reduction by "places indicator off" -- stored only, its behaviour is
# still to be defined.
var indicator_off_time_reduction: float = 5.0

static func from_dict(values: Dictionary) -> MemoryParameters:
	var parameters := MemoryParameters.new()
	parameters.mistakes_allowed = values["mistakes_allowed"]
	parameters.help_uses = values["help_uses"]
	parameters.reveal_seconds = values["reveal_seconds"]
	parameters.indicator_off_time_reduction = values["indicator_off_time_reduction"]
	return parameters
