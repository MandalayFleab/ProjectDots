extends Control
class_name ShapePiece

@export var shape_type: Shapes.Type = Shapes.Type.SQUARE
@export var color: Shapes.PrimaryColor = Shapes.PrimaryColor.RED

var locked: bool = false

func _draw() -> void:
	var fill := Shapes.color_for(color)
	var margin := 8.0
	match shape_type:
		Shapes.Type.SQUARE:
			draw_rect(Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2), fill)
		Shapes.Type.CIRCLE:
			draw_circle(size * 0.5, size.x * 0.5 - margin, fill)
		Shapes.Type.TRIANGLE:
			var points := PackedVector2Array([
				Vector2(size.x * 0.5, margin),
				Vector2(size.x - margin, size.y - margin),
				Vector2(margin, size.y - margin),
			])
			draw_colored_polygon(points, fill)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if locked:
		return null
	var preview := duplicate() as ShapePiece
	preview.modulate.a = 0.75
	set_drag_preview(preview)
	return self
