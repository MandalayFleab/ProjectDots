extends PanelContainer

# Dev-only tool for trying out different board/chrome proportions live
# instead of editing a constant and restarting every time. Press F1 to
# toggle it while playing (in the editor, or any debug export -- it never
# appears in a release export, see _ready() below).
@onready var ratio_slider: HSlider = $Margin/VBox/RatioRow/RatioSlider
@onready var ratio_value_label: Label = $Margin/VBox/RatioRow/RatioValueLabel
@onready var chrome_slider: HSlider = $Margin/VBox/ChromeRow/ChromeSlider
@onready var chrome_value_label: Label = $Margin/VBox/ChromeRow/ChromeValueLabel
@onready var drag_preview_slider: HSlider = $Margin/VBox/DragPreviewRow/DragPreviewSlider
@onready var drag_preview_value_label: Label = $Margin/VBox/DragPreviewRow/DragPreviewValueLabel
@onready var cell_size_label: Label = $Margin/VBox/CellSizeLabel

var _game
var _board

func _ready() -> void:
	visible = false
	if not OS.is_debug_build():
		queue_free()
		return

	# Children receive NOTIFICATION_READY before their parent -- Game's own
	# @onready vars (board, chrome_scale's owner) aren't assigned yet at this
	# point. One frame later, Game's _ready() has already run (its _new_game()
	# may still be mid-flight, but the node references themselves exist).
	await get_tree().process_frame

	_game = get_parent()
	_board = _game.board

	ratio_slider.min_value = 0.5
	ratio_slider.max_value = 1.0
	ratio_slider.step = 0.01
	ratio_slider.value = _board.board_size_ratio
	ratio_slider.value_changed.connect(_on_ratio_changed)

	chrome_slider.min_value = 0.3
	chrome_slider.max_value = 1.5
	chrome_slider.step = 0.01
	chrome_slider.value = _game.chrome_scale
	chrome_slider.value_changed.connect(_on_chrome_changed)

	drag_preview_slider.min_value = 1.0
	drag_preview_slider.max_value = 3.0
	drag_preview_slider.step = 0.05
	drag_preview_slider.value = ShapePiece.drag_preview_scale
	drag_preview_slider.value_changed.connect(_on_drag_preview_changed)

	_refresh_labels()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		visible = not visible
		get_viewport().set_input_as_handled()

func _on_ratio_changed(value: float) -> void:
	_board.board_size_ratio = value
	_game.apply_layout_now()
	_refresh_labels()

func _on_chrome_changed(value: float) -> void:
	_game.chrome_scale = value
	_game.apply_layout_now()
	_refresh_labels()

func _on_drag_preview_changed(value: float) -> void:
	ShapePiece.drag_preview_scale = value
	_refresh_labels()

func _refresh_labels() -> void:
	ratio_value_label.text = "%.2f" % _board.board_size_ratio
	chrome_value_label.text = "%.2f" % _game.chrome_scale
	drag_preview_value_label.text = "%.2fx (%.0fx area)" % [ShapePiece.drag_preview_scale, ShapePiece.drag_preview_scale * ShapePiece.drag_preview_scale]
	cell_size_label.text = "cell size: %.0fpx" % _board.cell_size.x
