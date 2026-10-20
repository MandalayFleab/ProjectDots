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

	level = LevelGenerator.generate()
	board.build(level, tray)
	for cell in board.get_cells():
		cell.piece_changed.connect(_on_piece_changed)

	# Board.build() sets sizes directly, but we still wait a frame so every
	# BoardCell/BigCell child's `size` is settled before we position previews
	# and center the board.
	await get_tree().process_frame
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
		preview.size = cell.size - Vector2(20, 20)
		cell.add_child(preview)
		preview.position = (cell.size - preview.size) * 0.5
	reveal_timer.start()

func _on_reveal_timer_timeout() -> void:
	for cell in board.get_cells():
		for child in cell.get_children():
			child.queue_free()

	var pieces: Array[ShapePiece] = []
	for spec in level.shapes_to_place:
		var piece := ShapePieceScene.instantiate() as ShapePiece
		piece.shape_type = spec.shape_type
		piece.color = spec.color
		pieces.append(piece)

	state = State.PLAYING
	tray.scatter(pieces)

func _on_piece_changed() -> void:
	if state != State.PLAYING:
		return
	var open_cells: Array = []
	for cell in board.get_cells():
		if not cell.locked and cell.has_requirement():
			open_cells.append(cell)
	for cell in open_cells:
		if not cell.is_full():
			return
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
		tray.scatter(wrong_pieces)
