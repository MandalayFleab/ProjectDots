extends BoardCell
class_name BigCell

const ShapePieceScene := preload("res://scenes/shape_piece/shape_piece.tscn")

var slot_a: ShapePiece = null
var slot_b: ShapePiece = null
var merged_display: ShapePiece = null

func is_full() -> bool:
	return slot_a != null and slot_b != null

func is_solved() -> bool:
	return is_full() \
		and slot_a.shape_type == required_spec.shape_type and slot_a.color == required_spec.color \
		and slot_b.shape_type == required_spec.shape_type and slot_b.color == required_spec.color

func detach(piece: ShapePiece) -> void:
	if slot_a == piece:
		slot_a = null
		_update_display()
	elif slot_b == piece:
		slot_b = null
		_update_display()

func release_wrong_pieces() -> Array[ShapePiece]:
	var result: Array[ShapePiece] = []
	if slot_a != null:
		slot_a.visible = true
		remove_child(slot_a)
		result.append(slot_a)
		slot_a = null
	if slot_b != null:
		slot_b.visible = true
		remove_child(slot_b)
		result.append(slot_b)
		slot_b = null
	_update_display()
	return result

func lock() -> void:
	locked = true
	if slot_a != null:
		slot_a.locked = true
	if slot_b != null:
		slot_b.locked = true

func _get_drag_data(_at_position: Vector2) -> Variant:
	# Grabbing the merged shape breaks it apart: both pieces pop back out
	# instead of the merged display itself being draggable as one object.
	if not locked and _is_merged():
		tray.scatter(release_wrong_pieces())
	return null

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var piece := data as ShapePiece
	BoardCell.release_from_current_parent(piece)

	if _is_merged():
		# Breaking an existing merge: both pieces pop out, the new one takes slot_a.
		tray.scatter(release_wrong_pieces())
		slot_a = piece
	elif slot_a == null:
		slot_a = piece
	else:
		slot_b = piece

	add_child(piece)
	_update_display()

	# Two different shapes together is never a valid state: expel both at once
	# instead of waiting for the end-of-round check.
	if is_full() and not _is_merged():
		tray.scatter(release_wrong_pieces())

	piece_changed.emit()

func _is_merged() -> bool:
	return slot_a != null and slot_b != null \
		and slot_a.shape_type == slot_b.shape_type and slot_a.color == slot_b.color

func _update_display() -> void:
	if merged_display != null:
		merged_display.queue_free()
		merged_display = null
	if slot_a != null:
		slot_a.visible = not _is_merged()
	if slot_b != null:
		slot_b.visible = not _is_merged()
	_layout_slots()
	if _is_merged():
		_show_merged()

func _layout_slots() -> void:
	if slot_a != null:
		slot_a.position = Vector2(size.x * 0.25 - slot_a.size.x * 0.5, (size.y - slot_a.size.y) * 0.5)
	if slot_b != null:
		slot_b.position = Vector2(size.x * 0.75 - slot_b.size.x * 0.5, (size.y - slot_b.size.y) * 0.5)

func _show_merged() -> void:
	merged_display = ShapePieceScene.instantiate()
	merged_display.shape_type = slot_a.shape_type
	merged_display.color = slot_a.color
	merged_display.size = size - Vector2(20, 20)
	merged_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	merged_display.position = (size - merged_display.size) * 0.5
	add_child(merged_display)
