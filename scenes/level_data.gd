class_name LevelData
extends RefCounted

enum CellKind { INACTIVE, NORMAL, BIG_ANCHOR, BIG_OCCUPIED }

var rows: int
var columns: int
var cells: Array = []
var shapes_to_place: Array[PieceSpec] = []
