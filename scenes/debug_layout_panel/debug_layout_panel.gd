extends PanelContainer

# Dev-only tool for tuning the horizontal and vertical distributions (see
# LayoutConfig) live instead of editing game_manager.gd and restarting every
# time. Press F1 to toggle it while playing (in the editor, or any debug
# export -- it never appears in a release export, see _ready() below).
#
# The sliders always edit the distribution currently on screen. "Force"
# picks one regardless of the window's shape, so both can be tuned from the
# same window; "Copy values" puts the code for both on the clipboard (and
# prints it) to paste back over the defaults in game_manager.gd.

const COLOR_ZONES := {
	"info": Color(0.35, 0.75, 1.0),
	"items": Color(1.0, 0.75, 0.3),
	"board": Color(0.45, 1.0, 0.5),
	"scramble": Color(1.0, 0.45, 0.6),
}

# field -> [min, max, step, horizontal label, vertical label, is_percent]
const FIELD_SPECS := {
	"side_ratio": [0.05, 0.5, 0.01, "Left column width", "Bottom row height", true],
	"board_ratio": [0.2, 0.9, 0.01, "Board zone width", "Board zone height", true],
	"info_ratio": [0.1, 0.9, 0.01, "Info height (of col)", "Info width (of row)", true],
	"margin_ratio": [0.0, 0.08, 0.005, "Margin", "Margin", true],
	"board_fill": [0.5, 1.0, 0.01, "Board fill", "Board fill", false],
	"items_fill": [0.3, 1.0, 0.01, "Items fill", "Items fill", false],
	"info_text_scale": [0.5, 2.0, 0.05, "Info text scale", "Info text scale", false],
	"preview_ratio": [0.15, 0.8, 0.01, "Puzzle preview size", "Puzzle preview size", true],
}

@onready var vbox: VBoxContainer = $Scroll/Margin/VBox

var _game
var _board
var _overlay: Control
var _defaults := {}
var _dock_left := true

# field -> {"slider", "name", "value"}
var _rows := {}
var _status_label: Label
var _scramble_label: Label
var _cell_size_label: Label
var _orientation_button: OptionButton
var _zones_check: CheckBox
var _dock_button: Button
var _drag_preview_row: Dictionary

func _ready() -> void:
	visible = false
	if not OS.is_debug_build():
		queue_free()
		return

	# Children receive NOTIFICATION_READY before their parent -- Game's own
	# @onready vars (board, the layouts' owner) aren't assigned yet at this
	# point. One frame later, Game's _ready() has already run (its _new_game()
	# may still be mid-flight, but the node references themselves exist).
	await get_tree().process_frame

	_game = get_parent()
	_board = _game.board
	_defaults = {
		_game.horizontal_layout: _snapshot(_game.horizontal_layout),
		_game.vertical_layout: _snapshot(_game.vertical_layout),
	}

	self_modulate.a = 0.9
	_build_rows()
	_build_overlay()
	_apply_dock()
	_game.layout_applied.connect(_on_layout_applied)
	visibility_changed.connect(_update_overlay_visibility)
	_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		visible = not visible
		get_viewport().set_input_as_handled()

func _build_rows() -> void:
	_add_label("Layout tuning (F1 to hide)")
	_status_label = _add_label("")

	var orientation_row := _add_row("Force")
	_orientation_button = OptionButton.new()
	_orientation_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in ["Auto (screen shape)", "Horizontal", "Vertical"]:
		_orientation_button.add_item(item)
	_orientation_button.selected = _game.orientation_override
	_orientation_button.item_selected.connect(_on_orientation_selected)
	orientation_row.add_child(_orientation_button)

	vbox.add_child(HSeparator.new())
	for field in FIELD_SPECS:
		var spec: Array = FIELD_SPECS[field]
		_rows[field] = _add_slider(spec[0], spec[1], spec[2], _on_field_changed.bind(field))
	_scramble_label = _add_label("")

	vbox.add_child(HSeparator.new())
	_drag_preview_row = _add_slider(1.0, 3.0, 0.05, _on_drag_preview_changed)
	_drag_preview_row["name"].text = "Drag preview"
	_drag_preview_row["slider"].set_value_no_signal(ShapePiece.drag_preview_scale)
	_cell_size_label = _add_label("")

	_zones_check = CheckBox.new()
	_zones_check.text = "Show zones"
	_zones_check.button_pressed = true
	_zones_check.toggled.connect(func(_on): _update_overlay_visibility())
	vbox.add_child(_zones_check)

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	_add_button(buttons, "Copy values", _on_copy_pressed)
	_add_button(buttons, "Reset", _on_reset_pressed)
	_dock_button = _add_button(buttons, "", _on_dock_pressed)

func _add_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(label)
	return label

func _add_row(name_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = name_text
	name_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_label)
	vbox.add_child(row)
	return row

func _add_slider(min_value: float, max_value: float, step: float, on_change: Callable) -> Dictionary:
	var row := _add_row("")
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(52, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return {"slider": slider, "name": row.get_child(0), "value": value_label}

func _add_button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	return button

# Draws every zone's outline and name over the game, just below this panel.
func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_zones)
	_game.add_child(_overlay)
	_game.move_child(_overlay, get_index())
	_update_overlay_visibility()

func _draw_zones() -> void:
	var font := ThemeDB.fallback_font
	for zone_name in _game.zones:
		var rect: Rect2 = _game.zones[zone_name]
		var color: Color = COLOR_ZONES.get(zone_name, Color.WHITE)
		_overlay.draw_rect(rect, Color(color, 0.08))
		_overlay.draw_rect(rect, color, false, 2.0)
		var text := "%s  %.0fx%.0f" % [zone_name, rect.size.x, rect.size.y]
		_overlay.draw_string(font, rect.position + Vector2(6, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

func _update_overlay_visibility() -> void:
	if _overlay != null:
		_overlay.visible = visible and _zones_check.button_pressed
		_overlay.queue_redraw()

func _apply_dock() -> void:
	var preset := Control.PRESET_LEFT_WIDE if _dock_left else Control.PRESET_RIGHT_WIDE
	set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_WIDTH, 8)
	_dock_button.text = "Dock right" if _dock_left else "Dock left"

func _on_orientation_selected(index: int) -> void:
	_game.orientation_override = index
	_game.apply_layout_now()

func _on_field_changed(value: float, field: String) -> void:
	_game.active_layout().set(field, value)
	_game.apply_layout_now()

func _on_drag_preview_changed(value: float) -> void:
	ShapePiece.drag_preview_scale = value
	_refresh()

func _on_copy_pressed() -> void:
	var code := "var horizontal_layout := %s\nvar vertical_layout := %s" % [
		_game.horizontal_layout.to_code(),
		_game.vertical_layout.to_code(),
	]
	DisplayServer.clipboard_set(code)
	print(code)
	_status_label.text = "Copied (also printed to the output)."

func _on_reset_pressed() -> void:
	var config: LayoutConfig = _game.active_layout()
	var values: Dictionary = _defaults[config]
	for field in values:
		config.set(field, values[field])
	_game.apply_layout_now()

func _on_dock_pressed() -> void:
	_dock_left = not _dock_left
	_apply_dock()

func _on_layout_applied() -> void:
	_refresh()
	if _overlay != null:
		_overlay.queue_redraw()

func _snapshot(config: LayoutConfig) -> Dictionary:
	var values := {}
	for field in LayoutConfig.FIELDS:
		values[field] = config.get(field)
	return values

# Re-reads everything from the active distribution -- it may have just
# switched (window reshaped, or "Force" changed), so the sliders must follow.
func _refresh() -> void:
	var vertical: bool = _game.is_vertical_layout()
	var config: LayoutConfig = _game.active_layout()
	var forced: bool = _game.orientation_override != 0  # LayoutMode.AUTO
	_status_label.text = "Editing: %s%s  (%.0fx%.0f)" % [
		"VERTICAL" if vertical else "HORIZONTAL",
		" (forced)" if forced else "",
		_game.size.x, _game.size.y,
	]
	for field in _rows:
		var spec: Array = FIELD_SPECS[field]
		var row: Dictionary = _rows[field]
		var value: float = config.get(field)
		row["name"].text = spec[4] if vertical else spec[3]
		row["slider"].set_value_no_signal(value)
		row["value"].text = _format(value, spec[5])
	_scramble_label.text = "Scramble zone: %s  (board used: %s)" % [
		_format(config.scramble_ratio(), true),
		_format(config.effective_board_ratio(), true),
	]
	_drag_preview_row["value"].text = "%.2fx" % ShapePiece.drag_preview_scale
	_cell_size_label.text = "cell size: %.0fpx" % _board.cell_size.x

static func _format(value: float, is_percent: bool) -> String:
	if is_percent:
		return "%.1f%%" % (value * 100.0)
	return "%.2f" % value
