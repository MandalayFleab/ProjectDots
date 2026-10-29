class_name LevelData
extends RefCounted

enum CellKind { INACTIVE, NORMAL, BIG_ANCHOR, BIG_OCCUPIED }

var rows: int
var columns: int
# The biggest row/column count the level's mode can generate -- Board sizes
# its cells against this instead of the level's own rows/columns.
var max_dimension: int
var cells: Array = []
var shapes_to_place: Array[PieceSpec] = []
