extends RefCounted
class_name IntRange

# An inclusive [min_value, max_value] range of whole numbers -- what every
# general difficulty parameter is made of (see GeneralParameters).

var min_value: int = 0
var max_value: int = 0

static func from_array(bounds: Array) -> IntRange:
	var result := IntRange.new()
	result.min_value = bounds[0]
	result.max_value = bounds[1]
	return result

func values() -> Array:
	var result: Array = []
	for value in range(min_value, max_value + 1):
		result.append(value)
	return result
