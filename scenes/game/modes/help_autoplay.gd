extends Node
class_name HelpAutoplay

# Memory mode's HELP auto-play: picks one still-unsolved shape and plays it
# into its cell for the player, one visible move at a time, through the
# ShapeShifter/Divisor exactly as a player would (see MemoryMode.help()).

# The pause between auto-play moves, so each one reads on its own.
const STEP_PAUSE := 0.15
# Longest an auto-play step waits for the ShapeShifter/Divisor to send
# its result back before giving up -- input is off during the auto-play, so
# a step that never finished must never leave the game stuck.
const STEP_TIMEOUT := 3.0

var game: GameManager

# ShapeShifter/Divisor uses the current auto-play has made so far.
var _item_uses: int = 0
var _before_final_move: Callable

# Picks one random unsolved cell and the pieces HELP will play into it:
# {"cell", "sources", "exact"}, or {} if no cell can be helped.
#
# Prefers cells with an exactly matching piece available -- loose in the
# scramble zone, sitting in some other cell it doesn't solve, or held by the
# ShapeShifter -- which simply travels into the cell ("exact"). Otherwise picks
# the fewest pieces that hold the units the cell needs, which _build()
# then runs through the Divisor/ShapeShifter exactly as a player would.
func plan() -> Dictionary:
	var pieces: Array = game.tray.get_children().filter(func(c): return c is ShapePiece and c.visible)
	for cell in game.board.get_cells():
		if not cell.locked and cell.current_piece != null and not cell.is_solved():
			pieces.append(cell.current_piece)
	if game.shifter.held_piece != null:
		pieces.append(game.shifter.held_piece)
	pieces = pieces.filter(func(p): return not p.is_in_group(ShapePiece.MOVING_GROUP))

	var exact := {}
	var builds := {}
	for cell in game.board.get_cells():
		if cell.locked or not cell.has_requirement() or cell.is_solved():
			continue
		var fitting: Array = pieces.filter(func(p): return p.is_big == cell.expects_big() \
			and p.shape_type == cell.required_spec.shape_type and p.color == cell.required_spec.color)
		if not fitting.is_empty():
			exact[cell] = fitting
			continue
		var sources := _build_sources(PieceDecomposer.to_units(cell.required_spec, cell.expects_big()), pieces)
		if not sources.is_empty():
			builds[cell] = sources

	if not exact.is_empty():
		var cell: BoardCell = exact.keys().pick_random()
		return {"cell": cell, "sources": [exact[cell].pick_random()], "exact": true}
	if not builds.is_empty():
		var cell: BoardCell = builds.keys().pick_random()
		return {"cell": cell, "sources": builds[cell], "exact": false}
	return {}

# Plays a plan() out with input off, and returns how many ShapeShifter/
# Divisor uses it took. before_final_move(item_uses) is called right before
# the final drag into the cell -- so a time penalty always matches the moves
# actually made, and still lands before that drag can win the round.
func play(p_plan: Dictionary, before_final_move: Callable) -> int:
	# The auto-play takes a few moves -- the player sitting still for them
	# keeps a stray tap from grabbing a piece it's about to use.
	get_viewport().gui_disable_input = true
	_item_uses = 0
	_before_final_move = before_final_move
	if p_plan["exact"]:
		await _move(p_plan["sources"][0], p_plan["cell"])
	else:
		await _build(p_plan["cell"], p_plan["sources"])
	get_viewport().gui_disable_input = false
	return _item_uses

# Drags a piece into a cell the same way tap-to-place does, and waits for it
# to land. Always the auto-play's last move.
func _move(piece: ShapePiece, cell: BoardCell) -> void:
	_before_final_move.call(_item_uses)
	if Selection.selected_piece == piece:
		Selection.deselect()
	cell.place_piece(piece, true)
	await get_tree().create_timer(Selection.MOVE_DURATION + STEP_PAUSE).timeout

# Drags a piece into the ShapeShifter or Divisor and returns what comes
# back out into the tray -- [] if nothing did within STEP_TIMEOUT.
func _use_item(item: Control, piece: ShapePiece) -> Array:
	if Selection.selected_piece == piece:
		Selection.deselect()
	_item_uses += 1
	var result: Array = []
	var collect := func(pieces: Array): result.append_array(pieces)
	item.produced.connect(collect, CONNECT_ONE_SHOT)
	item.place_piece(piece, true)
	var deadline: float = Time.get_ticks_msec() / 1000.0 + STEP_TIMEOUT
	while result.is_empty() and Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().process_frame
	if item.produced.is_connected(collect):
		item.produced.disconnect(collect)
	await get_tree().create_timer(STEP_PAUSE).timeout
	return result

# Drags two single units into the ShapeShifter, one after the other, and returns
# the (always big) piece it makes, or null if it never came out. Clears out
# anything else the player left in there first, so it doesn't get combined
# (or swapped) with ours.
func _combine(a: ShapePiece, b: ShapePiece) -> ShapePiece:
	var shifter: ShapeShifter = game.shifter
	if shifter.held_piece == b:
		var swap := a
		a = b
		b = swap
	if shifter.held_piece != null and shifter.held_piece != a:
		shifter.expel_held()
		await get_tree().create_timer(STEP_PAUSE).timeout
	if shifter.held_piece != a:
		if Selection.selected_piece == a:
			Selection.deselect()
		shifter.place_piece(a, true)
		await get_tree().create_timer(Selection.MOVE_DURATION + STEP_PAUSE).timeout
	var result: Array = await _use_item(shifter, b)
	return null if result.is_empty() else result[0]

# Builds the cell's piece out of `sources` the way a player would, one
# visible move at a time, then drags it into the cell:
#   1. A source holding exactly the cell's units, just at the other size (a
#      mixed colour), goes through the ShapeShifter to switch size.
#   2. Otherwise every two-unit source goes through the Divisor first, and
#      only the halves the cell needs are kept (the rest stay in the tray).
#   3. Two needed units are combined in the ShapeShifter -- and, if the cell
#      wants a normal-size mixed colour, the (always big) result goes back in
#      to shrink.
# Stops wherever a step times out (see _use_item()); whatever was made
# so far just stays in the tray.
func _build(cell: BoardCell, sources: Array) -> void:
	var needed := PieceDecomposer.to_units(cell.required_spec, cell.expects_big())
	var exact_units = _subtract_units(_units_of(sources[0]), needed)
	if sources.size() == 1 and exact_units != null and exact_units.is_empty():
		var resized: Array = await _use_item(game.shifter, sources[0])
		if not resized.is_empty():
			await _move(resized[0], cell)
		return

	var remaining: Array[PieceSpec] = needed.duplicate()
	var singles: Array[ShapePiece] = []
	for source in sources:
		var parts: Array = [source]
		if _units_of(source).size() == 2:
			parts = await _use_item(game.divisor, source)
			if parts.is_empty():
				return
		for part in parts:
			var left = _subtract_units(remaining, _units_of(part))
			if left != null:
				remaining = left
				singles.append(part)

	if singles.size() != needed.size():
		return
	var result: ShapePiece = singles[0]
	if needed.size() == 2:
		result = await _combine(singles[0], singles[1])
		if result == null:
			return
		if not cell.expects_big():
			var resized: Array = await _use_item(game.shifter, result)
			if resized.is_empty():
				return
			result = resized[0]
	await _move(result, cell)

# The primary units a piece is made of (see PieceDecomposer).
static func _units_of(piece: ShapePiece) -> Array[PieceSpec]:
	if piece.original_a != null:
		return [piece.original_a, piece.original_b]
	return [PieceSpec.new(piece.shape_type, piece.color)]

# `units` minus every unit in `needed` (matched by shape and colour), or
# null if `units` doesn't hold all of them.
static func _subtract_units(units: Array[PieceSpec], needed: Array[PieceSpec]) -> Variant:
	var left: Array[PieceSpec] = units.duplicate()
	for unit in needed:
		var index := -1
		for i in left.size():
			if left[i].shape_type == unit.shape_type and left[i].color == unit.color:
				index = i
				break
		if index < 0:
			return null
		left.remove_at(index)
	return left

# The fewest pieces (one, or else two) that together hold every unit in
# `needed`, picked at random among the options, or [] if no such pieces
# exist.
func _build_sources(needed: Array[PieceSpec], pieces: Array) -> Array:
	var options: Array = []
	for piece in pieces:
		if _subtract_units(_units_of(piece), needed) != null:
			options.append([piece])
	if options.is_empty() and needed.size() == 2:
		for a in pieces.size():
			for b in range(a + 1, pieces.size()):
				var units: Array[PieceSpec] = _units_of(pieces[a])
				units.append_array(_units_of(pieces[b]))
				if _subtract_units(units, needed) != null:
					options.append([pieces[a], pieces[b]])
	return [] if options.is_empty() else options.pick_random()
