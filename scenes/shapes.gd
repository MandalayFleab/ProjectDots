class_name Shapes

enum Type { SQUARE, TRIANGLE, CIRCLE }
enum PrimaryColor { RED, YELLOW, BLUE }

# Corner rounding as a fraction of the shape's drawn size, so big (combined)
# pieces get proportionally rounder corners instead of a fixed pixel radius.
const CORNER_ROUNDING_RATIO := 0.15
const CORNER_SEGMENTS := 6

# Replaces each corner of a closed polygon with a smooth curve: the corner is
# cut back `radius` px along both of its edges (never more than half an edge,
# so neighbouring corners can't overlap), and a quadratic Bezier with the
# original corner as its control point bridges the cut.
static func rounded_polygon(points: PackedVector2Array, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count := points.size()
	for i in count:
		var corner := points[i]
		var prev := points[(i - 1 + count) % count]
		var next := points[(i + 1) % count]
		var cut: float = minf(radius, minf(corner.distance_to(prev), corner.distance_to(next)) * 0.5)
		var from := corner.move_toward(prev, cut)
		var to := corner.move_toward(next, cut)
		for s in CORNER_SEGMENTS + 1:
			var t := float(s) / CORNER_SEGMENTS
			result.append(from.lerp(corner, t).lerp(corner.lerp(to, t), t))
	return result

static func color_for(primary: PrimaryColor) -> Color:
	match primary:
		PrimaryColor.RED:
			return Color(0.86, 0.15, 0.15)
		PrimaryColor.YELLOW:
			return Color(0.95, 0.77, 0.06)
		PrimaryColor.BLUE:
			return Color(0.13, 0.4, 0.85)
	return Color.WHITE
