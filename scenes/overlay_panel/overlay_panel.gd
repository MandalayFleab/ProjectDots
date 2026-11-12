extends Control
class_name OverlayPanel

# A bordered panel over the dimmed game, holding a MenuColumn of whatever
# entries are handed to open() -- the in-game options and the end screen
# are both one of these. It swallows every press, so nothing under it can
# still be played.

signal closed

# Tapping outside the panel (or Esc) closes it.
var dismissable: bool = true
# The game is paused while it's open (this panel keeps processing).
var pauses_game: bool = true

var _panel := PanelContainer.new()
var _column := MenuColumn.new()

func _init(p_dismissable: bool = true, p_pauses_game: bool = true, compact: bool = false) -> void:
	dismissable = p_dismissable
	pauses_game = p_pauses_game
	if compact:
		_column.compact()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Over the zoomed solution preview.
	z_index = 3
	visible = false

	var dim := ColorRect.new()
	dim.color = UiStyle.OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.add_child(_panel)
	_panel.add_child(_column)

func open(entries: Array) -> void:
	_column.build(entries)
	_relayout()
	visible = true
	if pauses_game:
		get_tree().paused = true

func close() -> void:
	if not visible:
		return
	visible = false
	if pauses_game:
		get_tree().paused = false
	closed.emit()

func refresh() -> void:
	_column.refresh()

func _on_dim_input(event: InputEvent) -> void:
	if dismissable and event is InputEventMouseButton and event.pressed:
		close()

func _unhandled_input(event: InputEvent) -> void:
	if visible and dismissable and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_relayout()

func _relayout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var unit := UiStyle.unit_for(size)
	var style := UiStyle.box(unit, UiStyle.SURFACE, UiStyle.BORDER, 0.0)
	style.set_content_margin_all(unit * UiStyle.PANEL_PADDING)
	_panel.add_theme_stylebox_override("panel", style)
	var max_width: float = size.x * UiStyle.COLUMN_MAX_SHARE - unit * UiStyle.PANEL_PADDING * 2.0
	_column.apply_unit(unit, minf(unit * UiStyle.COLUMN_WIDTH, max_width))
