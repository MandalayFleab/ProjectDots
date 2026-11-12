extends PanelContainer
class_name OptionSelector

# A bordered box "<  VALUE  >": the arrows step through a fixed list of
# options, stopping at both ends.

signal changed(index: int)

var _options: Array = []
var _index: int = 0
var _previous := ArrowButton.new(ArrowButton.Direction.LEFT)
var _next := ArrowButton.new(ArrowButton.Direction.RIGHT)
var _value := Label.new()

func _init() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value.clip_text = true
	row.add_child(_previous)
	row.add_child(_value)
	row.add_child(_next)
	_previous.pressed.connect(_step.bind(-1))
	_next.pressed.connect(_step.bind(1))

func set_options(options: Array) -> void:
	_options = options
	set_index(_index)

func set_index(index: int) -> void:
	_index = clampi(index, 0, maxi(_options.size() - 1, 0))
	_value.text = str(_options[_index]) if not _options.is_empty() else ""
	_update_arrows()

func set_enabled(enabled: bool) -> void:
	_previous.set_meta("locked", not enabled)
	_next.set_meta("locked", not enabled)
	_update_arrows()

func _update_arrows() -> void:
	_previous.disabled = _index <= 0 or _previous.get_meta("locked", false)
	_next.disabled = _index >= _options.size() - 1 or _next.get_meta("locked", false)
	_previous.queue_redraw()
	_next.queue_redraw()

func _step(delta: int) -> void:
	var index := clampi(_index + delta, 0, _options.size() - 1)
	if index == _index:
		return
	set_index(index)
	changed.emit(index)

func apply_unit(unit: float, height: float, font_units: float) -> void:
	add_theme_stylebox_override("panel", UiStyle.box(unit, UiStyle.SURFACE, UiStyle.BORDER, 0.0))
	UiStyle.style_label(_value, unit, font_units)
	custom_minimum_size.y = height
	for arrow in [_previous, _next]:
		arrow.custom_minimum_size = Vector2(height * 0.8, 0.0)
		arrow.queue_redraw()
