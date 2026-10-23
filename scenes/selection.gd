extends Node

# How long the auto-drag animation takes, in seconds. Change this one value
# to make click-to-place feel faster or slower.
const MOVE_DURATION := 0.35

var selected_piece: ShapePiece = null
var _cells: Array = []

# Called by game_manager once per round, after the board is built.
func set_cells(cells: Array) -> void:
	_cells = cells

func select(piece: ShapePiece) -> void:
	if piece.locked:
		return
	if selected_piece == piece:
		deselect()
		return
	deselect()
	selected_piece = piece
	piece.set_selected(true)
	_highlight_for(piece)

func deselect() -> void:
	if selected_piece != null:
		selected_piece.set_selected(false)
	selected_piece = null
	_clear_highlights()

# Untyped target: works for BoardCell/BigCell, and also Combiner/Divisor --
# anything exposing can_accept(piece) and place_piece(piece, animate).
func try_place_in(target) -> void:
	if selected_piece == null or not target.can_accept(selected_piece):
		return
	var piece := selected_piece
	deselect()
	target.place_piece(piece, true)

# Used by ShapePiece while a real mouse-drag is in progress.
func highlight_for_drag(piece: ShapePiece) -> void:
	_highlight_for(piece)

func clear_drag_highlight() -> void:
	_clear_highlights()

func _highlight_for(piece: ShapePiece) -> void:
	for cell in _cells:
		cell.set_highlight(BoardCell.Highlight.CAN_ACCEPT if cell.can_accept(piece) else BoardCell.Highlight.CANNOT_ACCEPT)

func _clear_highlights() -> void:
	for cell in _cells:
		cell.set_highlight(BoardCell.Highlight.NONE)
