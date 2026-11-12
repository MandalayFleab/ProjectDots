extends RefCounted
class_name GameSetup

# Everything the play screen decides about a game before it starts -- handed
# to GameManager (its `setup`) before it enters the tree.

enum PlayType {
	DAILY,     # the same level for everyone on a given (UTC) day
	QUICK,     # a single round at the player's chosen difficulty
	INFINITE,  # rounds keep coming, harder and harder (see
	           # InfiniteProgression), until one is lost
}

# A daily game is one of these, picked by the day itself (see
# daily_level()), so it's the same for everyone -- but never hard two days
# in a row.
const DAILY_LEVELS: Array[Difficulty.Level] = [Difficulty.Level.MEDIUM, Difficulty.Level.HARD]
# How far back daily_level() looks for the start of a run of hard picks --
# a cap only, real runs are a few days long.
const DAILY_LOOKBACK_DAYS := 60
const SECONDS_PER_DAY := 86400

var play_type: PlayType = PlayType.QUICK
var game_mode: GameManager.GameMode = GameManager.GameMode.MEMORY
var difficulty: Difficulty.Level = Difficulty.Level.EASY
var places_indicator: bool = true

# A setup from what's currently picked in Settings.
static func from_settings(p_play_type: PlayType) -> GameSetup:
	var setup := GameSetup.new()
	setup.play_type = p_play_type
	setup.game_mode = Settings.game_mode as GameManager.GameMode
	# Puzzle is always played without the allowed places indicator.
	setup.places_indicator = Settings.places_indicator and setup.game_mode == GameManager.GameMode.MEMORY
	match p_play_type:
		PlayType.DAILY:
			setup.difficulty = daily_level(today(), setup.game_mode)
		PlayType.QUICK:
			setup.difficulty = Settings.quick_difficulty as Difficulty.Level
		PlayType.INFINITE:
			# Each round sets its own (see InfiniteProgression).
			setup.difficulty = Difficulty.Level.EASY
	return setup

func is_quick() -> bool:
	return play_type == PlayType.QUICK

# Seeds the level generator for a daily game: one level per UTC day and mode.
func daily_seed() -> int:
	return seed_for_day(today(), game_mode)

# Today, as a number of UTC days since the Unix epoch.
static func today() -> int:
	return int(Time.get_unix_time_from_system()) / SECONDS_PER_DAY

static func seed_for_day(day: int, mode: GameManager.GameMode) -> int:
	return hash("%s-%d" % [Time.get_date_string_from_unix_time(day * SECONDS_PER_DAY), mode])

# The day's own pick, before the "never hard twice in a row" rule. Drawn
# from a generator seeded with the day, not straight from the seed's bits:
# hashes of consecutive dates differ too little in their low bits, which
# made the days (and the two modes) simply alternate.
static func _raw_daily_level(day: int, mode: GameManager.GameMode) -> Difficulty.Level:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for_day(day, mode)
	return DAILY_LEVELS[rng.randi_range(0, DAILY_LEVELS.size() - 1)]

# The day's difficulty: its own pick, except that a hard pick right after a
# hard day turns medium. Within a run of consecutive hard picks that makes
# the days alternate hard, medium, hard... -- so it only depends on how far
# into its run the day is, and every player works out the same answer
# without any history saved anywhere.
static func daily_level(day: int, mode: GameManager.GameMode) -> Difficulty.Level:
	if _raw_daily_level(day, mode) != Difficulty.Level.HARD:
		return _raw_daily_level(day, mode)
	var run := 1
	while run < DAILY_LOOKBACK_DAYS and _raw_daily_level(day - run, mode) == Difficulty.Level.HARD:
		run += 1
	return Difficulty.Level.HARD if run % 2 == 1 else Difficulty.Level.MEDIUM
