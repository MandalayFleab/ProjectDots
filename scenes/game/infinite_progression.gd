extends RefCounted
class_name InfiniteProgression

# The difficulty of every round of an infinite run. Rounds come in groups of
# GROUP_SIZE; each group completed makes the next one harder, until it
# settles:
#
#   group:   1      2      3      4      5         6         7 and after
#            4E 2M  3E 3M  2E 4M  1E 5M  1E 4M 1H  1E 3M 2H  1E 2M 3H
#
# i.e. first one easy round per group turns medium (down to MIN_EASY easy),
# then one medium per group turns hard (down to MIN_MEDIUM medium). Within a
# group the order is random, except it always starts with an easy round.

const GROUP_SIZE := 6
const FIRST_GROUP_EASY := 4
const MIN_EASY := 1
const MIN_MEDIUM := 2

# Groups completed so far in this run.
var groups_completed: int = 0
# The rest of the current group, next round first.
var _queue: Array[Difficulty.Level] = []

func reset() -> void:
	groups_completed = 0
	_queue.clear()

# The difficulty of the next round. Only call it once per round actually
# played -- reaching the end of a group counts it as completed.
func next_level() -> Difficulty.Level:
	if _queue.is_empty():
		_queue = make_group(groups_completed)
	var level: Difficulty.Level = _queue.pop_front()
	if _queue.is_empty():
		groups_completed += 1
	return level

# How many rounds of each level the group at `index` (0-based) has:
# {Level: count}.
static func group_counts(index: int) -> Dictionary:
	var easy: int = maxi(FIRST_GROUP_EASY - index, MIN_EASY)
	var easy_steps: int = FIRST_GROUP_EASY - MIN_EASY
	var max_hard: int = GROUP_SIZE - MIN_EASY - MIN_MEDIUM
	var hard: int = clampi(index - easy_steps, 0, max_hard)
	return {
		Difficulty.Level.EASY: easy,
		Difficulty.Level.MEDIUM: GROUP_SIZE - easy - hard,
		Difficulty.Level.HARD: hard,
	}

static func make_group(index: int) -> Array[Difficulty.Level]:
	var group: Array[Difficulty.Level] = []
	var counts := group_counts(index)
	for level in counts:
		for i in counts[level]:
			group.append(level)
	group.shuffle()
	# Every group has at least one easy round (MIN_EASY) to start with.
	group.erase(Difficulty.Level.EASY)
	group.push_front(Difficulty.Level.EASY)
	return group
