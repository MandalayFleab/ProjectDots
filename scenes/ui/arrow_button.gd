extends Button
class_name ArrowButton

# A triangle-outline arrow (the selectors' < > and the menus' back button),
# drawn rather than typed so it looks the same whatever font is in use.

enum Direction { LEFT, RIGHT }

var direction: Direction = Direction.LEFT

func _init(p_direction: Direction = Direction.LEFT) -> void:
	direction = p_direction
	flat = true
	focus_mode = Control.FOCUS_NONE

func _draw() -> void:
	var color: Color = UiStyle.TEXT_DISABLED if disabled else UiStyle.TEXT
	if is_hovered() and not disabled:
		draw_rect(Rect2(Vector2.ZERO, size), UiStyle.SURFACE_HOVER)
	var side: float = minf(size.x, size.y) * 0.5
	var center: Vector2 = size * 0.5
	var tip := Vector2(-side * 0.5, 0.0) if direction == Direction.LEFT else Vector2(side * 0.5, 0.0)
	var back_x: float = -tip.x
	var points := PackedVector2Array([
		center + tip,
		center + Vector2(back_x, -side * 0.5),
		center + Vector2(back_x, side * 0.5),
		center + tip,
	])
	draw_polyline(points, color, maxf(side * 0.08, 1.0), true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		queue_redraw()
