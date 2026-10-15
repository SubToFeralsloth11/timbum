extends RefCounted
## Sky Islands: a central island with a ruined tower, four mid islands and
## four corner islands at alternating heights, joined by plank bridges with
## ramp sections. Falling off means death (kill_y).

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(64, 40, 64)
const KILL_Y := -15.0
const SEED := 4404
const ATMOSPHERE := {
	"sky_top": Color("3576d4"), "sky_horizon": Color("c4e2f8"), "ground_bottom": Color("8fbfe6"),
	"sun_pitch": -40.0, "sun_yaw": -150.0, "sun_color": Color("fff4dc"), "sun_energy": 1.4,
	"fog_color": Color("cfe6f7"), "fog_density": 0.003, "ambient": 0.85, "exposure": 1.0,
	"fog_sky": 0.1, "ambient_color": Color("c9d8e6"), "sky_energy": 1.1,
}
## Islands: [centre x, centre z, radius, floor height].
const CENTER := [32, 32, 9, 20]
const MIDS := [[32, 9, 5, 20], [32, 54, 5, 20], [9, 32, 5, 20], [54, 32, 5, 20]]
const CORNERS := [[11, 11, 6, 17], [52, 11, 6, 23], [52, 52, 6, 17], [11, 52, 6, 23]]


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var hm := Kit.heightmap(g, 0)
	_island(g, hm, CENTER)
	for i: Array in MIDS + CORNERS:
		_island(g, hm, i)
	# Unreachable floating rocks for depth.
	for r: Array in [[21, 44, 3, 29], [43, 20, 2, 28], [19, 19, 2, 10], [45, 45, 3, 11]]:
		_island(g, Kit.heightmap(g, 0), r)

	# Spokes from the centre to the mid islands.
	_bridge(g, Vector2i(31, 23), Vector2i(31, 14), 20, 20, false)
	_bridge(g, Vector2i(31, 41), Vector2i(31, 49), 20, 20, false)
	_bridge(g, Vector2i(23, 31), Vector2i(14, 31), 20, 20, true)
	_bridge(g, Vector2i(41, 31), Vector2i(49, 31), 20, 20, true)
	# Ring from the mid islands to the corners (with ramps).
	_bridge(g, Vector2i(27, 9), Vector2i(17, 9), 20, 17, true)
	_bridge(g, Vector2i(37, 9), Vector2i(46, 9), 20, 23, true)
	_bridge(g, Vector2i(27, 52), Vector2i(17, 52), 20, 23, true)
	_bridge(g, Vector2i(37, 52), Vector2i(46, 52), 20, 17, true)
	_bridge(g, Vector2i(9, 27), Vector2i(9, 17), 20, 17, false)
	_bridge(g, Vector2i(9, 37), Vector2i(9, 46), 20, 23, false)
	_bridge(g, Vector2i(52, 27), Vector2i(52, 17), 20, 23, false)
	_bridge(g, Vector2i(52, 37), Vector2i(52, 46), 20, 17, false)

	_tower(g)
	for t: Vector2i in [Vector2i(26, 37), Vector2i(38, 26)]:
		Kit.oak(g, t.x, 20, t.y, rng)
	g.fill(Vector3i(36, 20, 37), Vector3i(37, 20, 37), B.CRATE)
	g.set_block(36, 21, 37, B.CRATE)
	g.fill(Vector3i(26, 20, 27), Vector3i(26, 20, 28), B.CRATE)
	for m: Array in MIDS:
		_mid_props(g, m)
	_hut(g, CORNERS[0], B.PLANKS, rng)
	_hut(g, CORNERS[2], B.COBBLE, rng)
	_ruin(g, CORNERS[1])
	_ruin(g, CORNERS[3])

	for s: Vector2i in [
		Vector2i(27, 33), Vector2i(37, 31), Vector2i(32, 7), Vector2i(32, 56), Vector2i(7, 32),
		Vector2i(56, 32), Vector2i(9, 13), Vector2i(14, 8), Vector2i(50, 9), Vector2i(55, 14),
		Vector2i(54, 50), Vector2i(49, 55), Vector2i(13, 54), Vector2i(8, 49),
	]:
		Kit.spawn(g, hm, info, s.x, s.y)
	Kit.pickup(g, hm, info, "health", 33, 33, 24)
	Kit.pickup(g, hm, info, "ammo", 28, 30)
	Kit.pickup(g, hm, info, "grenade", 34, 10)
	Kit.pickup(g, hm, info, "grenade", 30, 53)
	Kit.pickup(g, hm, info, "ammo", 12, 12)
	Kit.pickup(g, hm, info, "health", 51, 10)
	Kit.pickup(g, hm, info, "ammo", 51, 51)
	Kit.pickup(g, hm, info, "health", 10, 51)


## Floating island: flat grass top at the floor height, ragged rim, and a
## tapering rocky underside.
static func _island(g: VoxelGrid, hm: PackedInt32Array, i: Array) -> void:
	var cx: int = i[0]
	var cz: int = i[1]
	var r: int = i[2]
	var top: int = i[3]
	for z in range(cz - r - 2, cz + r + 3):
		for x in range(cx - r - 2, cx + r + 3):
			if not g.in_bounds(x, 0, z):
				continue
			var d := Vector2(x - cx, z - cz).length()
			var rim := r + (G.noise2(x / 2.5, z / 2.5, SEED) - 0.5) * 2.4
			if d > rim:
				continue
			var depth := mini(3 + int((rim - d) * 1.4 + G.noise2(x / 2.0, z / 2.0, SEED + 1) * 3.0), r * 2 + 1)
			var bottom := maxi(top - 1 - depth, 1)
			g.fill(Vector3i(x, bottom, z), Vector3i(x, top - 1, z), B.STONE)
			g.fill(Vector3i(x, maxi(top - 3, bottom), z), Vector3i(x, top - 2, z), B.DIRT)
			g.set_block(x, top - 1, z, B.GRASS)
			if G.hash01(x, z, SEED + 2) > 0.8 and bottom > 2:
				g.set_block(x, bottom - 1, z, B.COBBLE)
			hm[z * g.size.x + x] = top


## Three-wide plank bridge from `a` to `b` (axis-aligned, both on island
## rims). It reaches two cells into each island so ragged rims never leave
## a gap. Height changes happen mid-span as a ramp flight; logs hang under
## the deck as beams.
static func _bridge(g: VoxelGrid, a: Vector2i, b: Vector2i, from_y: int, to_y: int, along_x: bool) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	a -= step * 2
	b += step * 2
	var len := absi(b.x - a.x) + absi(b.y - a.y)
	var side := Vector2i(0, 1) if along_x else Vector2i(1, 0)
	var rise := to_y - from_y
	var n := absi(rise)
	var ramp_start := (len + 1 - n) / 2
	var facing: int
	if along_x:
		facing = G.RAMP_PX if step.x * signi(rise) > 0 else G.RAMP_NX
	else:
		facing = G.RAMP_PZ if step.y * signi(rise) > 0 else G.RAMP_NZ
	for k in len + 1:
		var y := from_y
		var ramp_y := -1
		if k >= ramp_start + n:
			y = to_y
		elif k >= ramp_start:
			var j := k - ramp_start
			if rise > 0:
				y = from_y + j
				ramp_y = y
			else:
				y = from_y - j - 1
				ramp_y = y
		for w in 3:
			var p := a + step * k + side * w
			if ramp_y >= 0:
				g.set_ramp(p.x, ramp_y, p.y, facing, B.PLANKS)
				g.set_block(p.x, ramp_y - 1, p.y, B.DARK_PLANKS)
			else:
				if g.is_air(p.x, y - 1, p.y) or g.get_shape(p.x, y - 1, p.y) != G.CUBE:
					g.set_block(p.x, y - 1, p.y, B.PLANKS)
				for h in 3:
					if g.get_block(p.x, y + h, p.y) == B.LEAVES:
						g.set_block(p.x, y + h, p.y, B.AIR)
		if ramp_y < 0 and k % 4 == 2:
			for w: int in [0, 2]:
				var p := a + step * k + side * w
				if g.is_air(p.x, y - 2, p.y):
					g.set_block(p.x, y - 2, p.y, B.LOG)


## Ruined watchtower on the central island with a ramp to its roof.
static func _tower(g: VoxelGrid) -> void:
	var f := 20
	g.fill(Vector3i(28, f - 1, 28), Vector3i(36, f - 1, 36), B.COBBLE)
	g.walls(Vector3i(28, f, 28), Vector3i(36, f + 3, 36), B.STONE_BRICK)
	g.fill(Vector3i(28, f + 3, 28), Vector3i(36, f + 3, 36), B.STONE_BRICK)
	g.clear(Vector3i(29, f + 3, 31), Vector3i(31, f + 3, 34))
	g.ramp_run(Vector3i(29, f, 34), G.RAMP_NZ, 4, 3, B.STONE_BRICK, B.STONE_BRICK)
	g.clear(Vector3i(31, f, 28), Vector3i(33, f + 2, 28))
	g.clear(Vector3i(31, f, 36), Vector3i(33, f + 2, 36))
	g.clear(Vector3i(36, f, 31), Vector3i(36, f + 2, 33))
	for x in range(28, 37):
		for z in range(28, 37):
			var edge := x == 28 or x == 36 or z == 28 or z == 36
			if edge and (x + z) % 2 == 0:
				g.set_block(x, f + 4, z, B.STONE_BRICK if G.hash01(x, z, SEED + 5) > 0.25 else B.COBBLE)
	g.set_block(35, f + 2, 29, B.LAMP)
	g.set_block(28, f + 4, 28, B.LAMP)
	g.set_block(36, f + 4, 36, B.LAMP)


static func _mid_props(g: VoxelGrid, m: Array) -> void:
	var x: int = m[0]
	var z: int = m[1]
	var f: int = m[3]
	var ox := 2 if x < 32 or x == 32 else -2
	g.fill(Vector3i(x + ox, f, z + 2), Vector3i(x + ox, f + 2, z + 2), B.LOG)
	g.set_block(x + ox, f + 3, z + 2, B.LAMP)
	g.fill(Vector3i(x - ox, f, z - 2), Vector3i(x - ox, f, z - 1), B.CRATE)


## Little cabin with doors on all four sides.
static func _hut(g: VoxelGrid, c: Array, wall: int, rng: RandomNumberGenerator) -> void:
	var cx: int = c[0]
	var cz: int = c[1]
	var f: int = c[3]
	g.walls(Vector3i(cx - 2, f, cz - 2), Vector3i(cx + 2, f + 2, cz + 2), wall)
	for p: Vector2i in [Vector2i(cx - 2, cz - 2), Vector2i(cx + 2, cz - 2), Vector2i(cx - 2, cz + 2), Vector2i(cx + 2, cz + 2)]:
		g.fill(Vector3i(p.x, f, p.y), Vector3i(p.x, f + 2, p.y), B.LOG)
	g.clear(Vector3i(cx - 2, f, cz - 1), Vector3i(cx - 2, f + 2, cz))
	g.clear(Vector3i(cx + 2, f, cz), Vector3i(cx + 2, f + 2, cz + 1))
	g.clear(Vector3i(cx - 1, f, cz - 2), Vector3i(cx, f + 2, cz - 2))
	g.clear(Vector3i(cx, f, cz + 2), Vector3i(cx + 1, f + 2, cz + 2))
	Kit.gable_roof(g, cx - 3, cz - 3, cx + 3, cz + 3, f + 3, rng.randf() < 0.5, B.ROOF, wall)


## Broken stone arch and pillars on the high corner islands.
static func _ruin(g: VoxelGrid, c: Array) -> void:
	var cx: int = c[0]
	var cz: int = c[1]
	var f: int = c[3]
	g.fill(Vector3i(cx - 2, f, cz - 2), Vector3i(cx - 2, f + 3, cz - 2), B.STONE_BRICK)
	g.fill(Vector3i(cx + 2, f, cz - 2), Vector3i(cx + 2, f + 3, cz - 2), B.STONE_BRICK)
	g.fill(Vector3i(cx - 2, f + 4, cz - 2), Vector3i(cx + 2, f + 4, cz - 2), B.STONE_BRICK)
	g.fill(Vector3i(cx + 2, f, cz + 2), Vector3i(cx + 2, f + 1, cz + 2), B.STONE_BRICK)
	g.fill(Vector3i(cx - 2, f, cz + 2), Vector3i(cx - 1, f, cz + 2), B.COBBLE)
	g.set_block(cx, f + 4, cz - 2, B.LAMP)
