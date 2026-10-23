class_name PieceDecomposer
extends RefCounted

# Chance that any given pair of identical normal pieces is handed out
# pre-combined as one big piece when the round is scrambled.
const PAIR_COMBINE_CHANCE := 0.5

static func decompose_big(spec: PieceSpec) -> Array[PieceSpec]:
	return [PieceSpec.new(spec.shape_type, spec.color), PieceSpec.new(spec.shape_type, spec.color)]

# Randomly regroups a level's (all-normal) pieces for the scramble: every
# pair of identical pieces may be handed out as one big piece instead. This
# never adds or removes a piece and always stays solvable -- the Divisor
# splits a big piece back into exactly that pair, and the Combiner rebuilds
# it from them -- so the player just starts from a different disposition.
#
# Returns one entry per piece to create: an Array[PieceSpec] holding either
# a single spec (a normal piece) or the two specs a big piece is made of.
static func random_disposition(specs: Array[PieceSpec]) -> Array:
	var by_type := {}
	for spec in specs:
		var key := Vector2i(spec.shape_type, spec.color)
		if not by_type.has(key):
			by_type[key] = []
		by_type[key].append(spec)

	var groups: Array = []
	for same_type in by_type.values():
		var i := 0
		while i < same_type.size():
			var has_pair: bool = i + 1 < same_type.size()
			if has_pair and randf() < PAIR_COMBINE_CHANCE:
				groups.append([same_type[i], same_type[i + 1]])
				i += 2
			else:
				groups.append([same_type[i]])
				i += 1
	groups.shuffle()
	return groups
