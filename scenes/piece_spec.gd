class_name PieceSpec
extends RefCounted

var shape_type: Shapes.Type
var color: Shapes.PrimaryColor

func _init(p_shape_type: Shapes.Type, p_color: Shapes.PrimaryColor) -> void:
	shape_type = p_shape_type
	color = p_color
