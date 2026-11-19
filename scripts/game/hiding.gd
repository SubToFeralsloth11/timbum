class_name Hiding
extends RefCounted
## What a seeker bot can make out of a hider (Hide and Seek, Block Hunt), and where a hider bot
## should hide. Seekers build suspicion of each hider they have a line of sight to (`Watch`): fast
## when the hider moves, slowly when it holds still, scaled by how much of it shows past cover, its
## stance, the light and above all how its colour stands out against what lies behind it from the
## seeker's eye (the block the sight line hits beyond, or the sky). Close up nothing hides.
## Hiding spots are navmesh points scored for cover (walls around them) and distance from seekers;
## in Block Hunt also for how many blocks around match the hider's disguise.

## Colour behind a sight line that reaches no block within BACKDROP_REACH.
const SKY := Color(0.62, 0.76, 0.92)
const BACKDROP_REACH := 30.0
## Seekers always spot a hider this close.
const BUMP_RANGE := 2.2
## Speed (m/s) above which a hider counts as moving.
const MOVING := 0.7
## Suspicion gained per second at full rate, per bot difficulty (Easy, Normal, Hard).
const SKILL := [0.6, 1.0, 1.5]
## Suspicion lost per second out of sight.
const FADE := 0.35
## Spot search: navmesh samples tried, rays used to measure cover around a spot and their reach.
const SAMPLES := 28
const COVER_RAYS := 8
const COVER_REACH := 3.5

static var _grids := {}


## The block grid of the current map (generated once per map and cached; built maps keep none).
static func grid_of(world: World) -> VoxelGrid:
	var id := str(world.map_info.id)
	if not _grids.has(id):
		_grids.clear()
		_grids[id] = MapBuilder.generate(id, MapInfo.new())
	return _grids[id]


## Block id at world position `pos` (AIR outside the grid).
static func block_at(world: World, pos: Vector3) -> int:
	var g := grid_of(world)
	var c := Vector3i((pos - world.map_info.bounds.position).floor())
	return g.get_block(c.x, c.y, c.z) if g.in_bounds(c.x, c.y, c.z) else BlockAtlas.AIR


## Horizontal speed of `p` as this (server) peer sees it.
static func speed_of(p: Player) -> float:
	if p.mode == Player.Mode.REMOTE:
		return p.observed_speed()
	return Vector2(p.velocity.x, p.velocity.z).length()


## 0..1, how much a `col` stands out against `bg` (0 the same colour).
static func contrast(col: Color, bg: Color) -> float:
	var d := Vector3(col.r - bg.r, col.g - bg.g, col.b - bg.b).length()
	return clampf(d / 0.55, 0.0, 1.0)


## [colour, block id] behind `target` seen from `eye`: the first block the sight line meets past it.
static func backdrop(world: World, eye: Vector3, target: Vector3) -> Array:
	var dir := (target - eye).normalized()
	var from := target + dir * 0.6
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * BACKDROP_REACH, Player.MASK_WORLD)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return [SKY, BlockAtlas.AIR]
	var block := block_at(world, (hit.position as Vector3) - (hit.normal as Vector3) * 0.2)
	if block == BlockAtlas.AIR:
		return [SKY, block]
	return [BlockAtlas.top_color(block), block]


## Fraction (0..1) of `target`'s head, chest and knees with a clear line from `eye`.
static func exposure(world: World, eye: Vector3, target: Player) -> float:
	var space := world.get_world_3d().direct_space_state
	var feet := target.global_position
	var top := target.head.global_position
	var seen := 0
	for point: Vector3 in [top, feet.lerp(top, 0.55), feet + Vector3.UP * 0.35]:
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, point, Player.MASK_WORLD)).is_empty():
			seen += 1
	return seen / 3.0


## Main colour of a hider's outfit (shirt and trousers), what a seeker's eye catches.
static func outfit_color(p: Player) -> Color:
	var o: Dictionary = Data.OUTFITS.get(str(p.info.get("outfit", "classic")), Data.OUTFITS.classic)
	return (o.shirt as Color).lerp(o.pants as Color, 0.35)


## Daylight factor: hiders are harder to see at night and in sunset gloom.
static func light() -> float:
	match str(Net.config.get("time_of_day", "day")):
		"night": return 0.55
		"sunset": return 0.8
	return 1.0


## Per-seeker suspicion of each hider. `rate(seeker, hider)` is the mode's colour/cover sum; `see`
## adds it over the time since the pair was last looked at and says whether the hider is spotted.
class Watch:
	## "seeker:hider" -> [suspicion, World.now() of the last look].
	var _seen := {}

	func see(seeker: Player, hider: Player, rate: float) -> bool:
		var key := "%d:%d" % [seeker.id, hider.id]
		var now := World.now()
		var entry: Array = _seen.get(key, [0.0, now])
		var gap := now - float(entry[1])
		var s := float(entry[0])
		if gap > 0.4:
			# Looked away for a while: suspicion fades, and only this look's own share counts.
			s = maxf(0.0, s - Hiding.FADE * gap)
			gap = BotBrain.PERCEIVE_INTERVAL
		s += rate * gap
		_seen[key] = [minf(s, 1.5), now]
		return s >= 1.0

	## A hider who changed role (caught) or left: forget it everywhere.
	func forget(eid: int) -> void:
		for key: String in _seen.keys():
			var parts := key.split(":")
			if int(parts[0]) == eid or int(parts[1]) == eid:
				_seen.erase(key)


## Navmesh points around the map scored as hiding spots for `p` away from `threats` (positions):
## [[score, pos, best block or -1], ...] best first. `blocks` (Block Hunt): the disguises to match;
## each spot gets the one most like the blocks around it.
static func spots(world: World, p: Player, threats: Array, blocks: Array) -> Array:
	var space := world.get_world_3d().direct_space_state
	var out: Array = []
	for i in SAMPLES:
		var pos := NavigationServer3D.map_get_random_point(world.map_info.nav_map, 1, false)
		if pos.y < world.map_info.kill_y + 1.0:
			continue
		var chest := pos + Vector3.UP * 1.0
		var cover := 0
		for k in COVER_RAYS:
			var a := TAU * k / COVER_RAYS
			var to := chest + Vector3(cos(a), 0.0, sin(a)) * COVER_REACH
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, to, Player.MASK_WORLD)).is_empty():
				cover += 1
		# A roof overhead hides from above and from across open ground.
		var roof := not space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + Vector3.UP * 6.0, Player.MASK_WORLD)).is_empty()
		var near := INF
		var seen := false
		for t: Vector3 in threats:
			near = minf(near, pos.distance_to(t))
			if not seen and pos.distance_to(t) < 40.0:
				seen = space.intersect_ray(PhysicsRayQueryParameters3D.create(chest + Vector3.UP * 0.5, t + Vector3.UP * 1.5, Player.MASK_WORLD)).is_empty()
		var score := cover * 1.2 + (2.0 if roof else 0.0) + minf(near, 45.0) * 0.12 - (6.0 if seen else 0.0)
		# Full cover all round is a dead end you can't flee from; the best spots leave a way out.
		if cover == COVER_RAYS:
			score -= 2.0
		score -= pos.distance_to(p.global_position) * 0.03
		var best_block := -1
		if not blocks.is_empty():
			var match_info := best_disguise(world, pos, blocks)
			best_block = int(match_info[0])
			score += float(match_info[1]) * 8.0
		out.append([score, pos, best_block])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	return out


## [block, 0..1 match] of the disguise in `blocks` that blends in best at feet position `pos`: the
## solid blocks within two cells that touch the air, by kind (exact match) and colour.
static func best_disguise(world: World, pos: Vector3, blocks: Array) -> Array:
	var g := grid_of(world)
	var c := Vector3i((pos - world.map_info.bounds.position).floor())
	var around: Array[int] = []
	for x in range(c.x - 2, c.x + 3):
		for y in range(c.y - 1, c.y + 3):
			for z in range(c.z - 2, c.z + 3):
				if not g.in_bounds(x, y, z) or g.is_air(x, y, z):
					continue
				if (g.in_bounds(x, y + 1, z) and g.is_air(x, y + 1, z)) or (g.in_bounds(x + 1, y, z) and g.is_air(x + 1, y, z)) \
						or (g.in_bounds(x - 1, y, z) and g.is_air(x - 1, y, z)) or (g.in_bounds(x, y, z + 1) and g.is_air(x, y, z + 1)) \
						or (g.in_bounds(x, y, z - 1) and g.is_air(x, y, z - 1)):
					around.append(g.get_block(x, y, z))
	if around.is_empty():
		return [blocks[0], 0.0]
	var best := int(blocks[0])
	var best_v := -1.0
	for b: Variant in blocks:
		var col := BlockAtlas.top_color(int(b))
		var v := 0.0
		for a in around:
			v += 1.0 if a == int(b) else (1.0 - contrast(col, BlockAtlas.top_color(a))) * 0.5
		v /= around.size()
		if v > best_v:
			best_v = v
			best = int(b)
	return [best, best_v]
