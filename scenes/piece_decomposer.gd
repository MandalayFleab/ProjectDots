class_name PieceDecomposer
extends RefCounted

static func decompose_big(spec: PieceSpec) -> Array[PieceSpec]:
	return [PieceSpec.new(spec.shape_type, spec.color), PieceSpec.new(spec.shape_type, spec.color)]
