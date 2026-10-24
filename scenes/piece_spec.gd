class_name PieceSpec
extends RefCounted

var shape_type: Shapes.Type
var color: Shapes.PieceColor

func _init(p_shape_type: Shapes.Type, p_color: Shapes.PieceColor) -> void:
	shape_type = p_shape_type
	color = p_color
