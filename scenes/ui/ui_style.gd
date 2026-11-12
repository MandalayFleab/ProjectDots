extends RefCounted
class_name UiStyle

# The one place the menus' look is defined: colors, borders, corners and
# every size. Every size is in "units" -- 1 unit is 1% of the screen's
# smaller side -- so the menus scale with the screen exactly like the
# gameplay zones do. Changing the visual design (colors, fonts, roundness)
# should only ever need edits here.

const BACKGROUND := Color(0.12, 0.13, 0.16)
const SURFACE := Color(0.08, 0.08, 0.10)
const SURFACE_HOVER := Color(0.18, 0.19, 0.23)
const SURFACE_PRESSED := Color(0.24, 0.25, 0.30)
const BORDER := Color(0.92, 0.92, 0.92)
const BORDER_DISABLED := Color(0.92, 0.92, 0.92, 0.25)
const TEXT := Color.WHITE
const TEXT_DISABLED := Color(1.0, 1.0, 1.0, 0.3)
# A selected segment of a switch (or a checked box): inverted colors.
const SELECTED := Color(0.92, 0.92, 0.92)
const SELECTED_TEXT := Color(0.08, 0.08, 0.10)
# Dims the game behind the in-game options panel.
const OVERLAY := Color(0.0, 0.0, 0.0, 0.75)

const BORDER_UNITS := 0.25
const CORNER_UNITS := 2.0

# Large buttons (PLAY, QUICK GAME...).
const LARGE_HEIGHT := 12.0
const LARGE_FONT := 5.5
# Switch segments.
const SMALL_HEIGHT := 6.5
const SMALL_FONT := 3.2
# Label + control rows (selectors, info), and checkboxes.
const ROW_HEIGHT := 9.0
const ROW_FONT := 3.0
const ROW_LABEL_SHARE := 0.45
# Space between consecutive entries of a menu.
const GAP := 4.0
# A tighter version of the menu sizes, for an overlay with a lot to show
# (the end screen).
const COMPACT_GAP := 2.0
const COMPACT_ROW_HEIGHT := 6.5
# Headings: a screen's title, and big numbers like a score total.
const TITLE_FONT := 5.0
# Buttons sharing a row: smaller text, and room for it to wrap to 2 lines.
const ROW_BUTTON_FONT := 4.0
const ROW_BUTTON_HEIGHT := 13.0
# Padding inside a bordered group of entries.
const GROUP_PADDING := 3.0
# A menu column's width, capped at COLUMN_MAX_SHARE of the screen's width.
const COLUMN_WIDTH := 62.0
const COLUMN_MAX_SHARE := 0.9
# Padding inside a panel (the in-game options panel).
const PANEL_PADDING := 5.0
# The back arrow in a menu screen's top-left corner.
const BACK_SIZE := 9.0
const BACK_MARGIN := 3.0

static func unit_for(screen_size: Vector2) -> float:
	return minf(screen_size.x, screen_size.y) / 100.0

static func font_px(unit: float, font_units: float) -> int:
	return maxi(int(unit * font_units), 8)

static func box(unit: float, fill: Color, border: Color, corner_units: float = CORNER_UNITS) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(maxi(int(round(unit * BORDER_UNITS)), 1))
	style.set_corner_radius_all(int(unit * corner_units))
	style.set_content_margin_all(unit)
	return style

# Every button state, for a plain or a toggle button (a pressed toggle is
# drawn as "selected").
static func style_button(button: Button, unit: float, font_units: float, corner_units: float = CORNER_UNITS) -> void:
	var selected := box(unit, SELECTED, BORDER, corner_units)
	var styles := {
		"normal": box(unit, SURFACE, BORDER, corner_units),
		"hover": box(unit, SURFACE_HOVER, BORDER, corner_units),
		"pressed": selected if button.toggle_mode else box(unit, SURFACE_PRESSED, BORDER, corner_units),
		"hover_pressed": selected if button.toggle_mode else box(unit, SURFACE_PRESSED, BORDER, corner_units),
		"disabled": box(unit, SURFACE, BORDER_DISABLED, corner_units),
		"focus": StyleBoxEmpty.new(),
	}
	for state in styles:
		button.add_theme_stylebox_override(state, styles[state])
	var pressed_text: Color = SELECTED_TEXT if button.toggle_mode else TEXT
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_focus_color", TEXT)
	button.add_theme_color_override("font_pressed_color", pressed_text)
	button.add_theme_color_override("font_hover_pressed_color", pressed_text)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	button.add_theme_font_size_override("font_size", font_px(unit, font_units))

static func style_label(label: Label, unit: float, font_units: float) -> void:
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_font_size_override("font_size", font_px(unit, font_units))
