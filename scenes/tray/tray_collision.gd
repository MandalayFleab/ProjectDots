extends RefCounted
class_name TrayCollision

# Lightweight push/overlap solver for pieces loose in the Tray -- not Godot
# physics, since pieces are Controls that hop between parents (Tray, cells,
# Combiner) and the native drag moves only a preview, never the piece itself.
# Pieces are treated as circles (smooth sliding pushes, no corner snagging);
# walls (board/Combiner/Divisor and the tray's own edges) as real rectangles,
# since those are what decide whether a piece stays reachable.
#
# Air-hockey feel: whatever displacement a hit causes in a frame is turned
# into a slide velocity (faster hit = bigger push per frame = faster slide),
# which then decays through friction and bounces off walls.

const PUSH_STIFFNESS := 0.35   # fraction of an overlap fixed per frame -- lower = softer nudge
const SOLVER_ITERATIONS := 3   # lets pushes chain through neighbours within a single frame
const WALL_PADDING := 8.0      # same margin Tray._is_excluded() keeps around exclusion zones

const IMPULSE_TRANSFER := 0.6  # how much of a hit's speed the struck piece keeps sliding with
const FRICTION := 3.5          # exponential decay per second -- lower = longer, icier slides
const WALL_BOUNCE := 0.5       # fraction of speed kept when bouncing off a wall (0 = dead stop)
const MAX_SPEED := 1200.0      # px/s cap, so a fast touch-drag can't fling pieces across the screen
const STOP_SPEED := 8.0        # px/s below which a slide just ends

# Something travelling across the tray (a mouse-drag, or a click-to-place
# animation) that pushes pieces aside but is never pushed back itself.
class Mover:
	var center: Vector2
	var radius: float

	func _init(mover_center: Vector2, mover_radius: float) -> void:
		center = mover_center
		radius = mover_radius

# Sets a slide that coasts to a stop about `distance` px away -- with
# exponential friction, total travel = speed / FRICTION. Not capped by
# MAX_SPEED on purpose: that cap tames hits, while launches are chosen.
static func launch(p: ShapePiece, direction: Vector2, distance: float) -> void:
	p.slide_velocity = direction.normalized() * distance * FRICTION

static func any_sliding(pieces: Array) -> bool:
	return pieces.any(func(p): return p.slide_velocity != Vector2.ZERO)

# All positions are in the tray's local space. Walls run LAST on purpose: a
# piece squeezed between a mover and the board ends up overlapping the mover
# instead of being shoved behind the board, where it would be unreachable.
static func resolve(pieces: Array, movers: Array[Mover], bounds: Rect2, walls: Array[Rect2], delta: float) -> void:
	if delta <= 0.0:
		return
	_integrate(pieces, delta)

	# Collision pushes are accumulated separately from wall corrections, so
	# only hits (not being shoved out of a wall) turn into slide velocity.
	var pushes := {}
	for p in pieces:
		pushes[p] = Vector2.ZERO
	for i in SOLVER_ITERATIONS:
		for p in pieces:
			for mover in movers:
				pushes[p] += _separate(p, mover.center, mover.radius, 1.0)
		for a in pieces.size():
			for b in range(a + 1, pieces.size()):
				var pa: ShapePiece = pieces[a]
				var pb: ShapePiece = pieces[b]
				var center_a := center_of(pa)
				pushes[pa] += _separate(pa, center_of(pb), radius_of(pb), 0.5)
				pushes[pb] += _separate(pb, center_a, radius_of(pa), 0.5)
		for p in pieces:
			apply_walls(p, bounds, walls)

	for p in pieces:
		_absorb_hit(p, pushes[p] / delta * IMPULSE_TRANSFER)

# Pushes the piece out of every wall along its shallowest axis, then clamps
# it inside the tray's bounds -- bouncing its slide velocity off whichever
# side it hit. Also used on its own for drops and resizes.
static func apply_walls(p: ShapePiece, bounds: Rect2, walls: Array[Rect2]) -> void:
	for wall in walls:
		if wall.size == Vector2.ZERO:
			continue
		var r := Rect2(p.position, p.size)
		var w := wall.grow(WALL_PADDING)
		if not r.intersects(w):
			continue
		var pushes: Array[Vector2] = [
			Vector2(w.position.x - r.end.x, 0.0),
			Vector2(w.end.x - r.position.x, 0.0),
			Vector2(0.0, w.position.y - r.end.y),
			Vector2(0.0, w.end.y - r.position.y),
		]
		var best := pushes[0]
		for push in pushes:
			if push.length() < best.length():
				best = push
		p.position += best
		_bounce(p, best)
	var unclamped := p.position
	p.position = p.position.clamp(bounds.position, (bounds.end - p.size).max(bounds.position))
	_bounce(p, p.position - unclamped)

static func center_of(p: ShapePiece) -> Vector2:
	return p.position + p.size * 0.5

static func radius_of(p: ShapePiece) -> float:
	return minf(p.size.x, p.size.y) * 0.5

static func _integrate(pieces: Array, delta: float) -> void:
	for p in pieces:
		if p.slide_velocity == Vector2.ZERO:
			continue
		p.position += p.slide_velocity * delta
		p.slide_velocity *= exp(-FRICTION * delta)
		if p.slide_velocity.length() < STOP_SPEED:
			p.slide_velocity = Vector2.ZERO

# Raises the velocity along the hit direction to at least the hit's speed,
# instead of adding to it -- otherwise a sustained push (a slow drag held
# against a piece) would keep stacking speed every frame.
static func _absorb_hit(p: ShapePiece, hit_velocity: Vector2) -> void:
	var hit_speed := hit_velocity.length()
	if hit_speed < STOP_SPEED:
		return
	var dir := hit_velocity / hit_speed
	var along := p.slide_velocity.dot(dir)
	if along < hit_speed:
		p.slide_velocity += dir * (hit_speed - along)
	p.slide_velocity = p.slide_velocity.limit_length(MAX_SPEED)

# Reflects the velocity component pointing into a wall the piece was just
# pushed out of (push is the correction the wall applied).
static func _bounce(p: ShapePiece, push: Vector2) -> void:
	if push.x != 0.0 and signf(p.slide_velocity.x) == -signf(push.x):
		p.slide_velocity.x = -p.slide_velocity.x * WALL_BOUNCE
	if push.y != 0.0 and signf(p.slide_velocity.y) == -signf(push.y):
		p.slide_velocity.y = -p.slide_velocity.y * WALL_BOUNCE

static func _separate(p: ShapePiece, other_center: Vector2, other_radius: float, share: float) -> Vector2:
	var delta := center_of(p) - other_center
	var distance := delta.length()
	var overlap := radius_of(p) + other_radius - distance
	if overlap <= 0.0:
		return Vector2.ZERO
	var dir := delta / distance if distance > 0.01 else Vector2.RIGHT
	var push := dir * overlap * share * PUSH_STIFFNESS
	p.position += push
	return push
