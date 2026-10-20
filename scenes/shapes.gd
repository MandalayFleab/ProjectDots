class_name Shapes

enum Type { SQUARE, TRIANGLE, CIRCLE }
enum PrimaryColor { RED, YELLOW, BLUE }

static func color_for(primary: PrimaryColor) -> Color:
	match primary:
		PrimaryColor.RED:
			return Color(0.86, 0.15, 0.15)
		PrimaryColor.YELLOW:
			return Color(0.95, 0.77, 0.06)
		PrimaryColor.BLUE:
			return Color(0.13, 0.4, 0.85)
	return Color.WHITE
