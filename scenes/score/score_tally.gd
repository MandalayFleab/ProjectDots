extends RefCounted
class_name ScoreTally

# The points of one game, level by level: one level in a quick or daily
# game, every level of an infinite run. Each level keeps its own lines (SOLVE
# TIME, NO MISTAKES...: what ModeRules.score_lines() said it was worth, plus
# e.g. what giving up paid), so a level's score and the game's total are
# both always at hand.

# Infinite mode: points for every level solved in the run (the "strike"),
# only added once the run is over (see total()).
const STRIKE_POINTS := 100

class Level:
	# [[label, points], ...]
	var lines: Array = []
	var solved: bool = false

	func total() -> int:
		var sum := 0
		for line in lines:
			sum += int(line[1])
		return sum

# Whether the strike counts (infinite mode only).
var counts_strikes: bool = false
# Levels solved so far.
var strikes: int = 0

var _levels: Array[Level] = []

func reset() -> void:
	strikes = 0
	_levels.clear()

# `lines` as ModeRules.score_lines() returns them: [[label, points], ...].
func add_level(lines: Array, solved: bool) -> void:
	var level := Level.new()
	level.lines = lines
	level.solved = solved
	_levels.append(level)
	if solved:
		strikes += 1

func last_level() -> Level:
	return _levels.back() if not _levels.is_empty() else null

func level_count() -> int:
	return _levels.size()

func strike_points() -> int:
	return strikes * STRIKE_POINTS if counts_strikes else 0

# Every solved level's points, added up.
func solved_points() -> int:
	var sum := 0
	for level in _levels:
		if level.solved:
			sum += level.total()
	return sum

# Every level's points, added up. `with_strike`: the run is over, so the
# strike counts too.
func total(with_strike: bool = false) -> int:
	var sum := strike_points() if with_strike else 0
	for level in _levels:
		sum += level.total()
	return sum
