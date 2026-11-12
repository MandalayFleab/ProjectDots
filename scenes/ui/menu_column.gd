extends VBoxContainer
class_name MenuColumn

# Turns an Array[MenuEntry] into a column of controls, one row each:
#
#   BUTTON    [        TEXT        ]        full width, large
#   SWITCH    [  OPT A  |  OPT B   ]        full width, small
#   SELECTOR   label      [< VALUE >]       label left, control right
#   INFO       label        value           label left, text right
#   CHECKBOX       [x] TEXT                 centered
#   HEADING          TEXT                   centered, own font size
#   ROW       [  BUTTON  ] [  BUTTON  ]     its children side by side
#   GROUP     +----------------------+      its children, in a nested
#             |  ...                 |      column inside a bordered box
#             +----------------------+
#
# Every change the player makes refreshes the whole column, so entries whose
# visibility, enabled state or value depends on another entry (or on
# anything else) follow along without any extra wiring.

class Row:
	var entry: MenuEntry
	var root: Control      # what's in the column (the widget, or label+widget)
	var widget: Control
	var label: Label
	var buttons: Array[Button] = []   # ROW: one per child entry
	var nested: MenuColumn            # GROUP

# Space between entries and height of label rows, in UiStyle units --
# compact() swaps in the tighter set, for overlays with a lot to show.
var gap_units: float = UiStyle.GAP
var row_units: float = UiStyle.ROW_HEIGHT

var _rows: Array[Row] = []
var _unit: float = 0.0
var _width: float = 0.0

func compact() -> MenuColumn:
	gap_units = UiStyle.COMPACT_GAP
	row_units = UiStyle.COMPACT_ROW_HEIGHT
	return self

func build(entries: Array) -> void:
	for row in _rows:
		row.root.queue_free()
	_rows.clear()
	for entry in entries:
		_rows.append(_make_row(entry))
	refresh()
	if _unit > 0.0:
		apply_unit(_unit, _width)

func refresh() -> void:
	for row in _rows:
		var entry := row.entry
		row.root.visible = entry.is_visible()
		var enabled := entry.is_enabled()
		match entry.kind:
			MenuEntry.Kind.BUTTON:
				(row.widget as Button).disabled = not enabled
			MenuEntry.Kind.SWITCH:
				var switch := row.widget as SegmentedSwitch
				switch.set_index(entry.current_value())
				switch.set_enabled(enabled)
			MenuEntry.Kind.SELECTOR:
				var selector := row.widget as OptionSelector
				selector.set_index(entry.current_value())
				selector.set_enabled(enabled)
			MenuEntry.Kind.CHECKBOX:
				var check := row.widget as CheckToggle
				check.set_pressed_no_signal(entry.current_value())
				check.disabled = not enabled
				check.queue_redraw()
			MenuEntry.Kind.INFO, MenuEntry.Kind.HEADING:
				(row.widget as Label).text = str(entry.current_value())
			MenuEntry.Kind.ROW:
				for i in row.buttons.size():
					var child: MenuEntry = entry.children[i]
					row.buttons[i].visible = child.is_visible()
					row.buttons[i].disabled = not (enabled and child.is_enabled())
			MenuEntry.Kind.GROUP:
				row.nested.refresh()

# Sizes every row for the given unit (see UiStyle) and column width.
func apply_unit(unit: float, width: float) -> void:
	_unit = unit
	_width = width
	custom_minimum_size.x = width
	add_theme_constant_override("separation", int(unit * gap_units))
	for row in _rows:
		match row.entry.kind:
			MenuEntry.Kind.BUTTON:
				var button := row.widget as Button
				UiStyle.style_button(button, unit, UiStyle.LARGE_FONT)
				button.custom_minimum_size = Vector2(width, unit * UiStyle.LARGE_HEIGHT)
			MenuEntry.Kind.SWITCH:
				row.widget.custom_minimum_size.x = width
				(row.widget as SegmentedSwitch).apply_unit(unit, unit * UiStyle.SMALL_HEIGHT, UiStyle.SMALL_FONT)
			MenuEntry.Kind.SELECTOR:
				_size_labeled(row, unit, width)
				(row.widget as OptionSelector).apply_unit(unit, unit * row_units, UiStyle.ROW_FONT)
			MenuEntry.Kind.INFO:
				_size_labeled(row, unit, width)
				UiStyle.style_label(row.widget as Label, unit, UiStyle.ROW_FONT)
			MenuEntry.Kind.CHECKBOX:
				(row.widget as CheckToggle).apply_unit(unit, unit * row_units, UiStyle.ROW_FONT)
			MenuEntry.Kind.HEADING:
				UiStyle.style_label(row.widget as Label, unit, row.entry.font_units)
				row.widget.custom_minimum_size = Vector2(width, unit * row.entry.font_units * 1.6)
			MenuEntry.Kind.ROW:
				(row.widget as HBoxContainer).add_theme_constant_override("separation", int(unit * UiStyle.GAP))
				row.widget.custom_minimum_size = Vector2(width, unit * UiStyle.ROW_BUTTON_HEIGHT)
				for button in row.buttons:
					UiStyle.style_button(button, unit, UiStyle.ROW_BUTTON_FONT)
			MenuEntry.Kind.GROUP:
				var padding: float = unit * UiStyle.GROUP_PADDING
				var style := UiStyle.box(unit, UiStyle.SURFACE, UiStyle.BORDER, 0.0)
				style.set_content_margin_all(padding)
				row.widget.add_theme_stylebox_override("panel", style)
				row.nested.apply_unit(unit, width - padding * 2.0)

func _size_labeled(row: Row, unit: float, width: float) -> void:
	UiStyle.style_label(row.label, unit, UiStyle.ROW_FONT)
	var label_width: float = width * UiStyle.ROW_LABEL_SHARE
	row.label.custom_minimum_size = Vector2(label_width, unit * row_units)
	row.widget.custom_minimum_size = Vector2(width - label_width, unit * row_units)

func _make_row(entry: MenuEntry) -> Row:
	var row := Row.new()
	row.entry = entry
	match entry.kind:
		MenuEntry.Kind.BUTTON:
			row.widget = _make_button(entry)
		MenuEntry.Kind.SWITCH:
			var switch := SegmentedSwitch.new()
			switch.set_options(entry.options)
			switch.changed.connect(_on_changed.bind(entry))
			row.widget = switch
		MenuEntry.Kind.SELECTOR:
			var selector := OptionSelector.new()
			selector.set_options(entry.options)
			selector.changed.connect(_on_changed.bind(entry))
			row.widget = selector
		MenuEntry.Kind.CHECKBOX:
			var check := CheckToggle.new()
			check.text = entry.text
			check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			check.toggled.connect(_on_changed.bind(entry))
			row.widget = check
		MenuEntry.Kind.INFO, MenuEntry.Kind.HEADING:
			var value := Label.new()
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.widget = value
		MenuEntry.Kind.ROW:
			var line := HBoxContainer.new()
			for child in entry.children:
				var button := _make_button(child)
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				line.add_child(button)
				row.buttons.append(button)
			row.widget = line
		MenuEntry.Kind.GROUP:
			var panel := PanelContainer.new()
			row.nested = MenuColumn.new()
			row.nested.gap_units = gap_units
			row.nested.row_units = row_units
			panel.add_child(row.nested)
			row.nested.build(entry.children)
			row.widget = panel
	row.root = row.widget
	if entry.kind == MenuEntry.Kind.SELECTOR or entry.kind == MenuEntry.Kind.INFO:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		row.label = Label.new()
		row.label.text = entry.label
		row.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(row.label)
		line.add_child(row.widget)
		row.root = line
	add_child(row.root)
	return row

func _make_button(entry: MenuEntry) -> Button:
	var button := Button.new()
	button.text = entry.text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): entry.action.call())
	return button

func _on_changed(value: Variant, entry: MenuEntry) -> void:
	entry.change(value)
	refresh()
