extends Button
class_name CheckToggle

# A square box with the button's text next to it -- the box is drawn in the
# left padding, so the text keeps the theme's font and colors.

const BOX_SHARE := 0.75   # of the button's height
const GAP_SHARE := 0.35   # space between box and text, of the box side

func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggled.connect(func(_on): queue_redraw())

func apply_unit(unit: float, height: float, font_units: float) -> void:
	var box_side: float = height * BOX_SHARE
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = box_side * (1.0 + GAP_SHARE)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		add_theme_color_override(color_name, UiStyle.TEXT)
	add_theme_color_override("font_disabled_color", UiStyle.TEXT_DISABLED)
	add_theme_font_size_override("font_size", UiStyle.font_px(unit, font_units))
	custom_minimum_size.y = height
	queue_redraw()

func _draw() -> void:
	var box_side: float = size.y * BOX_SHARE
	var rect := Rect2(Vector2(0.0, (size.y - box_side) * 0.5), Vector2(box_side, box_side))
	var color: Color = UiStyle.BORDER_DISABLED if disabled else UiStyle.BORDER
	var width: float = maxf(box_side * 0.06, 1.0)
	draw_rect(rect, UiStyle.SURFACE, true)
	draw_rect(rect, color, false, width)
	if button_pressed:
		var check := PackedVector2Array([
			rect.position + rect.size * Vector2(0.22, 0.52),
			rect.position + rect.size * Vector2(0.42, 0.72),
			rect.position + rect.size * Vector2(0.78, 0.30),
		])
		draw_polyline(check, color, width * 1.6, true)
