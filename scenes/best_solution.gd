class_name BestSolution
extends RefCounted

# The fewest moves (as Puzzle mode counts them, see game_manager._count_move())
# that solve a level from its scramble (LevelData.disposition):
#   - Every shape takes one move into its cell.
#   - Two single units combine in the ShapeShifter in one move (the first one
#     going in isn't a move yet), always into a big piece.
#   - A compound colour switches size in the ShapeShifter in one move.
#   - A big piece splits in the Divisor in one move -- a normal compound one
#     has to be made big first, so two.
#
# Two-unit pieces only ever pair units of the same shape, and a two-unit
# piece the solution needs is either one from the scramble with those exact
# units (resized if it's the wrong size) or two single units combined. Every
# scrambled two-unit piece not kept that way is split. Single units then
# always balance out on their own -- the scramble holds the same units as
# the solution -- so the count comes down to matching the two-unit pieces of
# each unit set.
static func moves(level: LevelData) -> int:
	# Unit set -> [big, normal] counts, for the scramble and the solution.
	var scrambled := {}
	var solution := {}
	var placements := 0
	for cell in level.cells:
		var spec: PieceSpec = cell["spec"]
		if spec == null:
			continue
		var big: bool = cell["kind"] == LevelData.CellKind.BIG_ANCHOR
		placements += 1
		var units := PieceDecomposer.to_units(spec, big)
		if units.size() == 2:
			_count(solution, units, big)
	for group in level.disposition:
		if group["units"].size() == 2:
			_count(scrambled, group["units"], group["big"])

	var total := placements
	var keys: Dictionary = scrambled.duplicate()
	keys.merge(solution)
	for key in keys:
		var have: Array = scrambled.get(key, [0, 0])
		var need: Array = solution.get(key, [0, 0])
		total += _pair_cost(have[0], have[1], need[0], need[1])
	return total

static func _count(counts: Dictionary, units: Array, big: bool) -> void:
	var key := _key(units)
	if not counts.has(key):
		counts[key] = [0, 0]
	counts[key][0 if big else 1] += 1

# Same shape and colours, whatever their order.
static func _key(units: Array) -> String:
	var parts: Array = []
	for unit in units:
		parts.append("%d:%d" % [unit.shape_type, unit.color])
	parts.sort()
	return ",".join(parts)

# Cheapest way to turn the scramble's two-unit pieces of one unit set (big
# and normal counts) into the solution's: keep some as they are (resizing
# those of the wrong size), split the rest, build the missing ones.
static func _pair_cost(have_big: int, have_normal: int, need_big: int, need_normal: int) -> int:
	var best := -1
	for big_to_big in mini(have_big, need_big) + 1:
		for normal_to_normal in mini(have_normal, need_normal) + 1:
			for big_to_normal in mini(have_big - big_to_big, need_normal - normal_to_normal) + 1:
				for normal_to_big in mini(have_normal - normal_to_normal, need_big - big_to_big) + 1:
					var resizes: int = big_to_normal + normal_to_big
					var splits: int = (have_big - big_to_big - big_to_normal) \
						+ (have_normal - normal_to_normal - normal_to_big) * 2
					var builds: int = (need_big - big_to_big - normal_to_big) \
						+ (need_normal - normal_to_normal - big_to_normal) * 2
					var cost: int = resizes + splits + builds
					if best < 0 or cost < best:
						best = cost
	return best
