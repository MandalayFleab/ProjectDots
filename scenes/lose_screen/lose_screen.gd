extends Control
class_name LoseScreen

# A plain full-screen overlay for a lost round: why it was lost, and a
# button to try again. Placeholder until the real menus are designed.

const BACKGROUND_COLOR := Color(0.05, 0.05, 0.07, 0.85)
# Font sizes as a fraction of the screen's smaller side.
const TITLE_RATIO := 0.09
const REASON_RATIO := 0.04

signal retry

var _title := Label.new()
var _reason := Label.new()
var _retry_button := Button.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallows every press, so nothing under it can still be played.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Drawn over the zoomed solution preview too.
	z_index = 2
	visible = false

	var background := ColorRect.new()
	background.color = BACKGROUND_COLOR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)

	_title.text = "You lose"
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for label in [_title, _reason]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color.WHITE)
		column.add_child(label)

	_retry_button.text = "Try again"
	_retry_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_retry_button.pressed.connect(func(): retry.emit())
	column.add_child(_retry_button)
	_apply_sizes()

func show_reason(reason: String) -> void:
	_reason.text = reason
	_apply_sizes()
	visible = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_sizes()

func _apply_sizes() -> void:
	var side: float = minf(size.x, size.y)
	if side <= 0.0:
		return
	_title.add_theme_font_size_override("font_size", maxi(int(side * TITLE_RATIO), 8))
	_reason.add_theme_font_size_override("font_size", maxi(int(side * REASON_RATIO), 8))
	_retry_button.add_theme_font_size_override("font_size", maxi(int(side * REASON_RATIO), 8))
	_reason.custom_minimum_size.x = size.x * 0.8
