extends ModeRules
class_name MemoryMode

# Memory: the solution shows on the board for a few seconds, then must be
# rebuilt from memory. The timer counts up, and too many mistakes lose the
# round. HELP can play a shape in for the player, at a time cost.

const ShapePieceScene := preload("res://scenes/shape_piece/shape_piece.tscn")

# Seconds added to the timer each time HELP is used: the base, plus the
# second one for every combine, divide or resize it had to make first.
const HELP_TIME_PENALTY := 15.0
const HELP_MOVE_TIME_PENALTY := 5.0

# Whenever HELP adds its time penalty -- lets the game show the "+15".
signal time_penalty(seconds: float)

var parameters: MemoryParameters
var elapsed_time: float = 0.0
var mistakes: int = 0
var help_uses_left: int = 0

var _reveal_timer := Timer.new()
var _autoplay := HelpAutoplay.new()
var _help_penalty_applied: bool = false

func _ready() -> void:
	_reveal_timer.one_shot = true
	_reveal_timer.timeout.connect(_on_reveal_timer_timeout)
	add_child(_reveal_timer)
	add_child(_autoplay)

func display_name() -> String:
	return "Memory"

func apply_difficulty(level: Difficulty.Level) -> void:
	difficulty = Difficulty.for_memory(level)
	parameters = difficulty.memory
	_autoplay.game = game

func has_help() -> bool:
	return true

# Only while actually playing (not during the reveal, nor once over), and
# only while uses are left.
func can_help() -> bool:
	return help_uses_left > 0 and _is_playing()

func begin_round(_level: LevelData) -> void:
	elapsed_time = 0.0
	mistakes = 0
	help_uses_left = parameters.help_uses

# Every required shape shows in its cell until the reveal time is up.
func start_round() -> void:
	for cell in game.board.get_cells():
		if not cell.has_requirement():
			continue
		var preview := ShapePieceScene.instantiate() as ShapePiece
		preview.shape_type = cell.required_spec.shape_type
		preview.color = cell.required_spec.color
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.size = cell.size * 0.8
		cell.add_child(preview)
		preview.position = (cell.size - preview.size) * 0.5
	_reveal_timer.start(parameters.reveal_seconds)

func stop() -> void:
	_reveal_timer.stop()

func _on_reveal_timer_timeout() -> void:
	var previews: Array = []
	for cell in game.board.get_cells():
		previews.append_array(cell.get_children())
	if not await game.shrink_away(previews):
		return
	for cell in game.board.get_cells():
		for child in cell.get_children():
			child.queue_free()
	game.scramble_pieces()

func tick(delta: float) -> void:
	elapsed_time += delta

# Every wrong cell in a check is one mistake -- going past the allowed ones
# loses the round.
func on_mistakes(count: int) -> void:
	mistakes += count
	if mistakes > parameters.mistakes_allowed:
		lost.emit("Too many mistakes: %d, only %d allowed." % [mistakes, parameters.mistakes_allowed])

func timer_text() -> String:
	return timer_text_for(int(elapsed_time))

func counter_text() -> String:
	return "%s %d/%d" % [MISTAKES_ICON, mistakes, parameters.mistakes_allowed]

func counter_sample() -> String:
	return "%s 00/00" % MISTAKES_ICON

func won_text() -> String:
	return "Solved in %s!" % format_time(int(elapsed_time))

# Plays one still-unsolved shape into its cell for the player (see
# HelpAutoplay), at the cost of a use and a time penalty: HELP_TIME_PENALTY,
# plus HELP_MOVE_TIME_PENALTY for every ShapeShifter/Divisor use it took.
# When nothing can be placed at all, neither a use nor time is spent.
func help() -> void:
	if not can_help():
		return
	var plan := _autoplay.plan()
	if plan.is_empty():
		return
	help_uses_left -= 1
	game.update_help_button()
	_help_penalty_applied = false
	var item_uses: int = await _autoplay.play(plan, _apply_help_penalty)
	# An auto-play cut short by a timed-out step still pays for what it did.
	_apply_help_penalty(item_uses)

func _apply_help_penalty(item_uses: int) -> void:
	if _help_penalty_applied or not _is_playing():
		return
	_help_penalty_applied = true
	var penalty: float = HELP_TIME_PENALTY + item_uses * HELP_MOVE_TIME_PENALTY
	if penalty > 0.0:
		elapsed_time += penalty
		time_penalty.emit(penalty)
