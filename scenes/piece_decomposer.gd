class_name PieceDecomposer
extends RefCounted

# Chance that any given unit is paired with the next one of the same shape
# when the round is scrambled, instead of being handed out on its own.
const PAIR_COMBINE_CHANCE := 0.5
# Chance that a mixed-colour pair comes out big rather than normal size.
const MIXED_BIG_CHANCE := 0.5

# Breaks a required piece down into the primary units it's made of: one for
# a normal primary, two of that colour for a big primary, and one of each
# component for a mixed colour (big or normal -- the Resizer only changes
# its size, never its units).
static func to_units(spec: PieceSpec, big: bool) -> Array[PieceSpec]:
	var units: Array[PieceSpec] = []
	if Shapes.is_primary(spec.color):
		for i in (2 if big else 1):
			units.append(PieceSpec.new(spec.shape_type, spec.color))
	else:
		for component in Shapes.components(spec.color):
			units.append(PieceSpec.new(spec.shape_type, component))
	return units

# Randomly regroups a level's primary units for the scramble: any two units
# of the same shape may be handed out as one piece instead -- a big primary
# if they share a colour, otherwise their mixed colour at a random size.
# This never adds or removes a unit, and every grouping stays solvable: the
# Combiner, Divisor and Resizer between them can turn any grouping of the
# same units into any other.
#
# Returns one entry per piece to create: {"units": Array[PieceSpec]} holding
# one unit (a normal primary) or two, plus "big" for the piece's size.
static func random_disposition(units: Array[PieceSpec]) -> Array:
	var by_shape := {}
	for unit in units:
		if not by_shape.has(unit.shape_type):
			by_shape[unit.shape_type] = []
		by_shape[unit.shape_type].append(unit)

	var groups: Array = []
	for same_shape in by_shape.values():
		# Shuffled first, so which colours end up paired is random too.
		same_shape.shuffle()
		var i := 0
		while i < same_shape.size():
			var has_pair: bool = i + 1 < same_shape.size()
			if has_pair and randf() < PAIR_COMBINE_CHANCE:
				var a: PieceSpec = same_shape[i]
				var b: PieceSpec = same_shape[i + 1]
				var big: bool = a.color == b.color or randf() < MIXED_BIG_CHANCE
				groups.append({"units": [a, b], "big": big})
				i += 2
			else:
				groups.append({"units": [same_shape[i]], "big": false})
				i += 1
	groups.shuffle()
	return groups
