extends RefCounted
class_name MenuEntry

# One option of a menu, as data: what kind of control it is, what it says,
# and how it reads and writes the value it stands for. A menu is just an
# Array[MenuEntry] (see MenuColumn, which turns it into controls), so adding,
# removing or reordering an option is one line in the menu that lists it --
# and anything that depends on the game mode, the play type, etc. is a
# shown_when()/enabled_when() condition on the entry itself.
#
# Values are never stored here: a getter reads the current one every time
# the menu refreshes, and a setter receives the new one. So an entry always
# shows the real state, wherever else it was changed.

enum Kind {
	BUTTON,    # a large button that runs `action`
	SWITCH,    # segmented choice between `options` (e.g. MEMORY | PUZZLE)
	SELECTOR,  # "label   < value >" -- arrows step through `options`
	CHECKBOX,  # a box with `text` next to it
	INFO,      # "label   value" -- read-only text
	HEADING,   # centered read-only text, at its own font size
	ROW,       # its `children` (buttons) side by side
	GROUP,     # its `children` in a bordered box
}

var kind: Kind
# Text of a button or checkbox.
var text: String = ""
# Shown on the left of SELECTOR and INFO rows.
var label: String = ""
# Choices of a SWITCH or SELECTOR.
var options: Array = []
# BUTTON: called when pressed.
var action: Callable
# Returns the current value: option index (SWITCH/SELECTOR), bool
# (CHECKBOX) or String (INFO).
var getter: Callable
# Receives the new value from the player.
var setter: Callable
# HEADING: font size, in UiStyle units.
var font_units: float = UiStyle.ROW_FONT
# ROW and GROUP: the entries inside. A ROW only takes BUTTON entries.
var children: Array = []
# Both return a bool -- an empty Callable means "always".
var visible_if: Callable
var enabled_if: Callable

static func button(p_text: String, p_action: Callable) -> MenuEntry:
	var entry := MenuEntry.new()
	entry.kind = Kind.BUTTON
	entry.text = p_text
	entry.action = p_action
	return entry

static func switch(p_options: Array, p_getter: Callable, p_setter: Callable) -> MenuEntry:
	var entry := MenuEntry.new()
	entry.kind = Kind.SWITCH
	entry.options = p_options
	entry.getter = p_getter
	entry.setter = p_setter
	return entry

static func selector(p_label: String, p_options: Array, p_getter: Callable, p_setter: Callable) -> MenuEntry:
	var entry := MenuEntry.new()
	entry.kind = Kind.SELECTOR
	entry.label = p_label
	entry.options = p_options
	entry.getter = p_getter
	entry.setter = p_setter
	return entry

static func checkbox(p_text: String, p_getter: Callable, p_setter: Callable) -> MenuEntry:
	var entry := MenuEntry.new()
	entry.kind = Kind.CHECKBOX
	entry.text = p_text
	entry.getter = p_getter
	entry.setter = p_setter
	return entry

static func info(p_label: String, p_getter: Callable) -> MenuEntry:
	var entry := MenuEntry.new()
	entry.kind = Kind.INFO
	entry.label = p_label
	entry.getter = p_getter
	return entry

# `value` is either a fixed String or a Callable returning the text.
static func heading(value: Variant, p_font_units: float = UiStyle.ROW_FONT) -> MenuEntry:
	var entry := MenuEntry.new()
	entry.kind = Kind.HEADING
	entry.getter = value if value is Callable else func(): return value
	entry.font_units = p_font_units
	return entry

static func button_row(p_children: Array) -> MenuEntry:
	var entry := MenuEntry.new()
	entry.kind = Kind.ROW
	entry.children = p_children
	return entry

static func group(p_children: Array) -> MenuEntry:
	var entry := MenuEntry.new()
	entry.kind = Kind.GROUP
	entry.children = p_children
	return entry

func shown_when(condition: Callable) -> MenuEntry:
	visible_if = condition
	return self

func enabled_when(condition: Callable) -> MenuEntry:
	enabled_if = condition
	return self

func is_visible() -> bool:
	return not visible_if.is_valid() or visible_if.call()

func is_enabled() -> bool:
	return not enabled_if.is_valid() or enabled_if.call()

func current_value() -> Variant:
	return getter.call() if getter.is_valid() else null

func change(value: Variant) -> void:
	if setter.is_valid():
		setter.call(value)
