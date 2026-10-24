extends Panel
class_name Divisor

const ShapePieceScene := preload("res://scenes/shape_piece/shape_piece.tscn")
const LABEL := "Divide"

var tray: Tray = null
var piece_size: Vector2 = Vector2(80, 80)

var _press_position: Vector2 = Vector2.ZERO
var _press_active: bool = false

func detach(_piece: ShapePiece) -> void:
	pass  # Divisor never holds a piece -- it processes and splits instantly.

func can_accept(piece: ShapePiece) -> bool:
	return piece.is_big

func _draw() -> void:
	# Fully proportional to size (no fixed pixel values) -- resizing this node
	# is all that's needed to scale the whole thing correctly.
	var dim: float = min(size.x, size.y)
	var border_width: float = dim * 0.025
	var inset: float = dim * 0.0375
	var radius: float = dim * 0.5 - inset
	draw_circle(size * 0.5, radius, Color(0.8, 0.85, 0.95, 0.9), false, border_width, true)
	var font := ThemeDB.fallback_font
	var font_size := int(dim * 0.1125)
	var text_size := font.get_string_size(LABEL, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var label_margin: float = dim * 0.0875
	draw_string(font, Vector2(size.x * 0.5 - text_size.x * 0.5, size.y - label_margin), LABEL, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.9, 0.9, 0.95))

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is ShapePiece and can_accept(data as ShapePiece)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	place_piece(data as ShapePiece)

func place_piece(piece: ShapePiece, animate: bool = false) -> void:
	var start_global: Vector2 = piece.global_position
	BoardCell.release_from_current_parent(piece)
	add_child(piece)
	piece.visible = true
	var target := (size - piece.size) * 0.5
	if animate:
		piece.global_position = start_global
		piece.animate_to(target, Selection.MOVE_DURATION, func(): _split(piece))
	else:
		piece.position = target
		_split(piece)

func _split(piece: ShapePiece) -> void:
	var spec_a: PieceSpec = piece.original_a
	var spec_b: PieceSpec = piece.original_b
	piece.queue_free()
	var p1 := _make_piece(spec_a)
	var p2 := _make_piece(spec_b)
	tray.launch_from([p1, p2], self, [Tray.Side.TOP])

func _make_piece(spec: PieceSpec) -> ShapePiece:
	var p: ShapePiece = ShapePieceScene.instantiate()
	p.setup_single(spec, piece_size)
	return p

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_position = event.position
			_press_active = true
		elif _press_active:
			_press_active = false
			if event.position.distance_to(_press_position) < 6.0:
				Selection.try_place_in(self)
