class_name Shapes

enum Type { SQUARE, TRIANGLE, CIRCLE }
# The first three are primaries; the rest are mixes of exactly two of them
# (see components()). A mixed-colour piece is always made of one unit of
# each of its primaries, whatever its size.
enum PieceColor { RED, YELLOW, BLUE, PURPLE, ORANGE, GREEN }

const MIXES := {
	PieceColor.PURPLE: [PieceColor.RED, PieceColor.BLUE],
	PieceColor.ORANGE: [PieceColor.RED, PieceColor.YELLOW],
	PieceColor.GREEN: [PieceColor.YELLOW, PieceColor.BLUE],
}

static func is_primary(color: PieceColor) -> bool:
	return not MIXES.has(color)

# The primaries a colour is made of: itself for a primary, its two mixed
# primaries otherwise.
static func components(color: PieceColor) -> Array:
	return MIXES[color] if MIXES.has(color) else [color]

# Same primary twice stays that primary; two different primaries give their
# mix (order doesn't matter).
static func mix(a: PieceColor, b: PieceColor) -> PieceColor:
	if a == b:
		return a
	for mixed in MIXES:
		if MIXES[mixed].has(a) and MIXES[mixed].has(b):
			return mixed
	push_error("Can't mix %s with %s" % [a, b])
	return a

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

static func color_for(color: PieceColor) -> Color:
	match color:
		PieceColor.RED:
			return Color(0.86, 0.15, 0.15)
		PieceColor.YELLOW:
			return Color(0.95, 0.77, 0.06)
		PieceColor.BLUE:
			return Color(0.13, 0.4, 0.85)
		PieceColor.PURPLE:
			return Color(0.56, 0.25, 0.78)
		PieceColor.ORANGE:
			return Color(0.97, 0.5, 0.1)
		PieceColor.GREEN:
			return Color(0.18, 0.66, 0.3)
	return Color.WHITE
