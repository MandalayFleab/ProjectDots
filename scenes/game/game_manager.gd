extends Control

const ShapePieceScene := preload("res://scenes/shape_piece/shape_piece.tscn")

enum State { SHOWING, PLAYING, WON }

@onready var board: Board = $Board
@onready var tray: Tray = $Tray
@onready var reveal_timer: Timer = $RevealTimer
@onready var chronometer_label: Label = $ChronometerLabel
@onready var result_label: Label = $ResultLabel
@onready var replay_button: Button = $ReplayButton

var state: State = State.SHOWING
var elapsed_time: float = 0.0
var level: LevelData

func _ready() -> void:
	reveal_timer.timeout.connect(_on_reveal_timer_timeout)
	replay_button.pressed.connect(_on_replay_pressed)
	await _new_game()

func _on_replay_pressed() -> void:
	await _new_game()

func _new_game() -> void:
	reveal_timer.stop()
	tray.clear()
	result_label.text = ""

	# On web, the browser canvas can take a couple of frames to report its
	# real size after load -- wait for this root Control to actually have one
	# before computing the board's cell size from it, instead of trusting a
	# single frame (or Board ends up sized for a near-zero area).
	while size.x <= 0.0 or size.y <= 0.0:
		await get_tree().process_frame

	level = LevelGenerator.generate()
	board.build(level, tray, size)
	for cell in board.get_cells():
		cell.piece_changed.connect(_on_piece_changed)

	board.position = (size - board.size) * 0.5
	tray.exclusion_rect = Rect2(board.position, board.size)
	_start_round()

func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	elapsed_time += delta
	var total := int(elapsed_time)
	chronometer_label.text = "%02d:%02d" % [total / 60, total % 60]

func _start_round() -> void:
	state = State.SHOWING
	elapsed_time = 0.0
	chronometer_label.text = "00:00"
	for cell in board.get_cells():
		if not cell.has_requirement():
			continue
		var preview := ShapePieceScene.instantiate() as ShapePiece
		preview.shape_type = cell.required_spec.shape_type
		preview.color = cell.required_spec.color
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.size = cell.size * 0.8
		cell.add_child(preview)
		preview.position = (cell.size - preview.size) * 0.5
	reveal_timer.start()

func _on_reveal_timer_timeout() -> void:
	for cell in board.get_cells():
		for child in cell.get_children():
			child.queue_free()

	var piece_size: Vector2 = board.cell_size * 0.8
	var pieces: Array[ShapePiece] = []
	for spec in level.shapes_to_place:
		var piece := ShapePieceScene.instantiate() as ShapePiece
		piece.shape_type = spec.shape_type
		piece.color = spec.color
		piece.size = piece_size
		pieces.append(piece)

	state = State.PLAYING
	# Tray's size comes from anchors, not an explicit assignment like Board's --
	# force it in sync with the root's (reliably measured) size right before
	# scattering, instead of trusting anchor propagation already happened.
	tray.size = size
	tray.scatter(pieces)

func _on_piece_changed() -> void:
	if state != State.PLAYING:
		return
	# Intentionally-empty cells are correctly solved by staying empty, so
	# "every open cell is full" is no longer a valid readiness check -- check
	# once every scattered piece has been placed SOMEWHERE instead.
	if tray.get_child_count() > 0:
		return
	var open_cells: Array = []
	for cell in board.get_cells():
		if not cell.locked:
			open_cells.append(cell)
	_check_solution(open_cells)

func _check_solution(open_cells: Array) -> void:
	var wrong_pieces: Array[ShapePiece] = []
	for cell in open_cells:
		if cell.is_solved():
			cell.lock()
		else:
			wrong_pieces.append_array(cell.release_wrong_pieces())

	if wrong_pieces.is_empty():
		state = State.WON
		result_label.text = "Solved in %s!" % chronometer_label.text
	else:
		tray.size = size
		tray.scatter(wrong_pieces)
