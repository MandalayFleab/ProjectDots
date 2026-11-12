extends HBoxContainer
class_name SegmentedSwitch

# One-of-many choice laid out as adjoining segments (MEMORY | PUZZLE): the
# selected one is drawn inverted. One segment per option, so it takes any
# number of them.

signal changed(index: int)

var _group := ButtonGroup.new()
var _buttons: Array[Button] = []

func _init() -> void:
	add_theme_constant_override("separation", 0)

func set_options(options: Array) -> void:
	for button in _buttons:
		button.queue_free()
	_buttons.clear()
	for i in options.size():
		var button := Button.new()
		button.text = str(options[i])
		button.toggle_mode = true
		button.button_group = _group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.pressed.connect(func(): changed.emit(i))
		add_child(button)
		_buttons.append(button)

func set_index(index: int) -> void:
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == index)

func set_enabled(enabled: bool) -> void:
	for button in _buttons:
		button.disabled = not enabled

func apply_unit(unit: float, height: float, font_units: float) -> void:
	custom_minimum_size.y = height
	for button in _buttons:
		UiStyle.style_button(button, unit, font_units, 0.0)
