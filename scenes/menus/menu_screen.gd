extends Control
class_name MenuScreen

# A full-screen menu: its entries (see MenuEntry) in a centered column, plus
# a back arrow in the top-left corner when there's a screen to go back to.
# A new menu is a subclass that only overrides _entries() -- App (see
# app.gd) handles the navigation between them.

var app: App

var _column := MenuColumn.new()
var _back := ArrowButton.new(ArrowButton.Direction.LEFT)

# The options of this menu, top to bottom.
func _entries() -> Array[MenuEntry]:
	return []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = UiStyle.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(_column)
	_column.build(_entries())

	_back.pressed.connect(func(): app.back())
	add_child(_back)
	_relayout()

# Re-reads every entry's value, visibility and enabled state -- e.g. when
# coming back to this screen after another one changed something.
func refresh() -> void:
	_column.refresh()
	_back.visible = app != null and app.can_go_back()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_relayout()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and visible:
		refresh()

func _relayout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var unit := UiStyle.unit_for(size)
	_column.apply_unit(unit, minf(unit * UiStyle.COLUMN_WIDTH, size.x * UiStyle.COLUMN_MAX_SHARE))
	var back_side: float = unit * UiStyle.BACK_SIZE
	_back.size = Vector2(back_side, back_side)
	_back.position = Vector2(unit * UiStyle.BACK_MARGIN, unit * UiStyle.BACK_MARGIN)
	refresh()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and app != null and app.can_go_back():
		app.back()
		get_viewport().set_input_as_handled()
