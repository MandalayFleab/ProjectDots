class_name LevelData
extends RefCounted

enum CellKind { INACTIVE, NORMAL, BIG_ANCHOR, BIG_OCCUPIED }

var rows: int
var columns: int
# The biggest row/column count a level can have -- Board sizes its cells
# against this instead of the level's own rows/columns.
var max_dimension: int
var cells: Array = []
var shapes_to_place: Array[PieceSpec] = []
# How shapes_to_place is grouped into pieces for the scramble (see
# PieceDecomposer.random_disposition()) -- rolled with the level, so Puzzle
# mode can work out its best solution (see BestSolution) before playing.
var disposition: Array = []
