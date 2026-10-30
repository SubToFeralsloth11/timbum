extends RefCounted
## Desert Ruins: a stepped temple with a lamp-lit inner chamber in the
## middle, a colonnade, broken walls, obelisks and two sniper towers on
## rolling dunes ringed by sandstone cliffs. Long sightlines everywhere.

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(64, 30, 64)
const KILL_Y := -10.0
const SEED := 2202
const ATMOSPHERE := {
	"sky_top": Color("3d7cc9"), "sky_horizon": Color("efd9b0"), "ground_bottom": Color("b4986a"),
	"sun_pitch": -60.0, "sun_yaw": 125.0, "sun_color": Color("ffe4b8"), "sun_energy": 1.55,
	"fog_color": Color("e9d3a8"), "fog_density": 0.0035, "ambient": 0.7, "exposure": 0.95,
	"saturation": 1.05, "fog_sky": 0.12, "ambient_color": Color("d9c6a2"),
}
const TEMPLE := [24, 24, 39, 39]
const TOWERS := [[6, 6, 11, 11], [52, 52, 57, 57]]
const FLOOR := 5
## Jump pads (MapKit.jump_pads): onto the temple's east and west terraces, and onto a ruin top in
## the north-east (with a drop back to the sand).
const JUMP_PADS := [
	[Vector3i(42, 5, 34), Vector3i(38, 9, 37), 1.5],
	[Vector3i(30, 5, 42), Vector3i(26, 9, 38), 1.5],
	[Vector3i(36, 4, 14), Vector3i(46, 12, 19), 1.5, Vector3(46.5, 12, 17.5), Vector3(47.5, 5, 17.5)],
]


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var sx := g.size.x
	var hm := Kit.heightmap(g, 0)
	for z in g.size.z:
		for x in sx:
			var n := G.noise2(x / 9.0, z / 9.0, SEED) * 3.2 + G.noise2(x / 4.0, z / 4.0, SEED + 1) * 0.4
			hm[z * sx + x] = 3 + roundi(n)
	var lock := PackedByteArray()
	lock.resize(sx * g.size.z)
	_pad(g, hm, lock, TEMPLE[0] - 6, TEMPLE[1] - 6, TEMPLE[2] + 6, TEMPLE[3] + 6, FLOOR)
	_pad(g, hm, lock, 4, 4, 17, 13, 4)
	_pad(g, hm, lock, 46, 50, 59, 59, 4)
	Kit.limit_steps(g, hm, lock)
	g.apply_heightmap(hm, B.SAND, B.SAND, B.SANDSTONE)
	g.auto_ramps(hm, B.SAND)

	_temple(g)
	_tower(g, hm, TOWERS[0], G.RAMP_NX, Vector3i(15, 0, 7))
	_tower(g, hm, TOWERS[1], G.RAMP_PX, Vector3i(48, 0, 54))
	_colonnade(g, hm)
	_ruin(g, hm, 45, 40, 54, 47, rng)
	_ruin(g, hm, 44, 9, 53, 16, rng)
	_ruin(g, hm, 9, 46, 16, 53, rng)
	_obelisk(g, hm, 22, 10)
	_obelisk(g, hm, 41, 53)
	_cliffs(g, hm)
	_scatter(g, hm, rng)

	for s: Vector2i in [
		Vector2i(8, 20), Vector2i(8, 38), Vector2i(7, 57), Vector2i(20, 56), Vector2i(33, 57),
		Vector2i(57, 44), Vector2i(57, 30), Vector2i(56, 16), Vector2i(57, 5), Vector2i(33, 6),
		Vector2i(20, 18), Vector2i(43, 22), Vector2i(43, 44), Vector2i(20, 44), Vector2i(31, 31),
	]:
		Kit.spawn(g, hm, info, s.x, s.y)
	Kit.pickup(g, hm, info, "health", 31, 33, FLOOR + 7)
	Kit.pickup(g, hm, info, "grenade", 29, 31, FLOOR)
	Kit.pickup(g, hm, info, "ammo", 14, 30)
	Kit.pickup(g, hm, info, "ammo", 50, 30)
	Kit.pickup(g, hm, info, "health", 49, 44)
	Kit.pickup(g, hm, info, "health", 12, 49)
	Kit.pickup(g, hm, info, "ammo", 9, 9, 8)
	Kit.pickup(g, hm, info, "grenade", 32, 47)
	Kit.jump_pads(g, info, JUMP_PADS)


static func _pad(g: VoxelGrid, hm: PackedInt32Array, lock: PackedByteArray, x0: int, z0: int, x1: int, z1: int, h: int) -> void:
	Kit.rect(g, hm, x0, z0, x1, z1, h)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			lock[z * g.size.x + x] = 1


## Two-tier stepped temple. Tunnels cross the lower tier into a lamp-lit
## chamber; pinwheel ramps climb both tiers to a pillared summit.
static func _temple(g: VoxelGrid) -> void:
	var y0 := FLOOR
	g.fill(Vector3i(24, y0 - 1, 24), Vector3i(39, y0 - 1, 39), B.SANDSTONE)
	g.fill(Vector3i(24, y0, 24), Vector3i(39, y0 + 3, 39), B.SANDSTONE)
	g.walls(Vector3i(24, y0 + 1, 24), Vector3i(39, y0 + 1, 39), B.CARVED)
	g.fill(Vector3i(28, y0 + 4, 28), Vector3i(35, y0 + 6, 35), B.SANDSTONE)
	g.walls(Vector3i(28, y0 + 5, 28), Vector3i(35, y0 + 5, 35), B.CARVED)
	# Tunnels and chamber.
	g.clear(Vector3i(30, y0, 24), Vector3i(33, y0 + 2, 39))
	g.clear(Vector3i(24, y0, 30), Vector3i(39, y0 + 2, 33))
	g.clear(Vector3i(28, y0, 28), Vector3i(35, y0 + 2, 35))
	g.fill(Vector3i(31, y0, 31), Vector3i(32, y0, 32), B.GOLD)
	for p: Vector2i in [Vector2i(28, 28), Vector2i(35, 28), Vector2i(28, 35), Vector2i(35, 35), Vector2i(31, 25), Vector2i(32, 38), Vector2i(25, 32), Vector2i(38, 31)]:
		g.set_block(p.x, y0 + 3, p.y, B.LAMP)
	for p: Vector2i in [Vector2i(28, 28), Vector2i(35, 28), Vector2i(28, 35), Vector2i(35, 35)]:
		g.fill(Vector3i(p.x, y0, p.y), Vector3i(p.x, y0 + 2, p.y), B.CARVED)
	# Lower tier ramps (4 long), then upper tier ramps (3 long) on the ledge.
	g.ramp_run(Vector3i(25, y0, 20), G.RAMP_PZ, 4, 3, B.SANDSTONE, B.SANDSTONE)
	g.ramp_run(Vector3i(36, y0, 43), G.RAMP_NZ, 4, 3, B.SANDSTONE, B.SANDSTONE)
	g.ramp_run(Vector3i(20, y0, 36), G.RAMP_PX, 4, 3, B.SANDSTONE, B.SANDSTONE)
	g.ramp_run(Vector3i(43, y0, 25), G.RAMP_NX, 4, 3, B.SANDSTONE, B.SANDSTONE)
	g.ramp_run(Vector3i(33, y0 + 4, 25), G.RAMP_PZ, 3, 3, B.SANDSTONE, B.SANDSTONE)
	g.ramp_run(Vector3i(28, y0 + 4, 38), G.RAMP_NZ, 3, 3, B.SANDSTONE, B.SANDSTONE)
	g.ramp_run(Vector3i(25, y0 + 4, 28), G.RAMP_PX, 3, 3, B.SANDSTONE, B.SANDSTONE)
	g.ramp_run(Vector3i(38, y0 + 4, 33), G.RAMP_NX, 3, 3, B.SANDSTONE, B.SANDSTONE)
	# Summit: corner pillars under a shading slab, low cover and an idol.
	var top := y0 + 7
	for p: Vector2i in [Vector2i(28, 28), Vector2i(35, 28), Vector2i(28, 35), Vector2i(35, 35)]:
		g.fill(Vector3i(p.x, top, p.y), Vector3i(p.x, top + 2, p.y), B.CARVED)
	g.fill(Vector3i(28, top + 3, 28), Vector3i(35, top + 3, 35), B.SANDSTONE)
	g.clear(Vector3i(30, top + 3, 30), Vector3i(33, top + 3, 33))
	g.walls(Vector3i(27, top + 4, 27), Vector3i(36, top + 4, 36), B.SANDSTONE)
	g.set_block(31, top, 31, B.GOLD)
	g.set_block(32, top, 32, B.GOLD)
	g.fill(Vector3i(30, top, 34), Vector3i(31, top, 34), B.SANDSTONE)
	g.fill(Vector3i(33, top, 29), Vector3i(34, top, 29), B.SANDSTONE)


## Sniper tower: a solid block with a crenellated top reached by a ramp.
static func _tower(g: VoxelGrid, hm: PackedInt32Array, t: Array, facing: int, ramp_start: Vector3i) -> void:
	var f := hm[t[1] * g.size.x + t[0]]
	var x0: int = t[0]
	var z0: int = t[1]
	var x1: int = t[2]
	var z1: int = t[3]
	g.fill(Vector3i(x0, f, z0), Vector3i(x1, f + 3, z1), B.SANDSTONE)
	g.walls(Vector3i(x0, f + 2, z0), Vector3i(x1, f + 2, z1), B.CARVED)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var edge := x == x0 or x == x1 or z == z0 or z == z1
			if edge and (x + z) % 2 == 0:
				g.set_block(x, f + 4, z, B.SANDSTONE)
	g.ramp_run(Vector3i(ramp_start.x, f, ramp_start.z), facing, 4, 3, B.SANDSTONE, B.SANDSTONE)
	var landing := ramp_start + G.FACING_DIR[facing] * 4
	g.clear(Vector3i(landing.x, f + 4, landing.z), Vector3i(landing.x, f + 4, landing.z + 2))
	for p: Vector2i in [Vector2i(x0, z0), Vector2i(x1, z1)]:
		g.set_block(p.x, f + 4, p.y, B.LAMP)


## Two rows of carved columns along the west avenue, some broken, some
## joined by lintels.
static func _colonnade(g: VoxelGrid, hm: PackedInt32Array) -> void:
	var sx := g.size.x
	for z in range(16, 46, 5):
		for x: int in [11, 18]:
			var f := hm[z * sx + x]
			if g.get_shape(x, f, z) != G.CUBE:
				continue
			var h := 4 if G.hash01(x, z, SEED) > 0.3 else 2
			g.fill(Vector3i(x, f, z), Vector3i(x, f + h - 1, z), B.CARVED)
			if h == 4 and G.hash01(z, x, SEED) > 0.5 and hm[z * sx + 18] == f and hm[z * sx + 11] == f:
				g.fill(Vector3i(11, f + 4, z), Vector3i(18, f + 4, z), B.SANDSTONE)


## Roofless ruined house: crumbling walls with two doorways and windows.
static func _ruin(g: VoxelGrid, hm: PackedInt32Array, x0: int, z0: int, x1: int, z1: int, rng: RandomNumberGenerator) -> void:
	var sx := g.size.x
	var mx := (x0 + x1) / 2
	var mz := (z0 + z1) / 2
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			if x != x0 and x != x1 and z != z0 and z != z1:
				continue
			var door := (z == z0 and absi(x - mx) <= 1) or (x == x1 and absi(z - mz) <= 1) \
					or (x == x0 and (z == mz or z == mz + 1)) or (z == z1 and (x == mx or x == mx + 1))
			if door:
				continue
			var f := hm[z * sx + x]
			var h := 2 + int(G.hash01(x, z, SEED + 7) * 3.0)
			g.fill(Vector3i(x, f, z), Vector3i(x, f + h - 1, z), B.SANDSTONE)
			if h >= 3 and (x + z) % 4 == 0:
				g.set_block(x, f + 1, z, B.CARVED)
	g.set_block(x0 + 2, hm[(z0 + 2) * sx + x0 + 2], z0 + 2, B.CRATE)
	g.set_block(x1 - 2, hm[(z1 - 2) * sx + x1 - 2], z1 - 2, B.ORANGE if rng.randf() < 0.5 else B.CRATE)


static func _obelisk(g: VoxelGrid, hm: PackedInt32Array, x: int, z: int) -> void:
	var f := hm[z * g.size.x + x]
	g.fill(Vector3i(x - 1, f, z - 1), Vector3i(x + 2, f, z + 2), B.SANDSTONE)
	g.fill(Vector3i(x, f + 1, z), Vector3i(x + 1, f + 7, z + 1), B.CARVED)
	g.fill(Vector3i(x, f + 8, z), Vector3i(x + 1, f + 8, z + 1), B.GOLD)


## Sandstone cliffs around the edge, banded and capped with sand.
static func _cliffs(g: VoxelGrid, hm: PackedInt32Array) -> void:
	var sx := g.size.x
	for z in g.size.z:
		for x in sx:
			var e := mini(mini(x, z), mini(sx - 1 - x, g.size.z - 1 - z))
			if e > 2:
				continue
			var top := hm[z * sx + x] + 6 + int(G.noise2(x / 3.0, z / 3.0, SEED + 3) * 5.0) - e * 2
			g.fill(Vector3i(x, 0, z), Vector3i(x, top, z), B.SANDSTONE)
			g.set_block(x, top + 1, z, B.SAND)


## Palms, crates and pots on free open sand.
static func _scatter(g: VoxelGrid, hm: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var sx := g.size.x
	var placed := 0
	var tries := 0
	while placed < 14 and tries < 500:
		tries += 1
		var x := rng.randi_range(5, sx - 6)
		var z := rng.randi_range(5, g.size.z - 6)
		var f := hm[z * sx + x]
		var clear := true
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if not g.is_cube(x + dx, f - 1, z + dz) or not g.is_air(x + dx, f, z + dz) or hm[(z + dz) * sx + x + dx] != f:
					clear = false
		if not clear or (x > 18 and x < 46 and z > 18 and z < 46) or (x < 19 and z < 15) or (x > 44 and z > 48):
			continue
		placed += 1
		if placed % 3 == 0:
			g.fill(Vector3i(x, f, z), Vector3i(x + 1, f, z), B.CRATE)
			g.set_block(x, f + 1, z, B.CRATE)
			g.set_block(x, f, z + 1, B.ORANGE)
		else:
			_palm(g, x, f, z, rng)


static func _palm(g: VoxelGrid, x: int, y: int, z: int, rng: RandomNumberGenerator) -> void:
	var h := rng.randi_range(5, 7)
	for dy in h:
		g.set_block(x, y + dy, z, B.LOG)
	var top := y + h
	g.set_block(x, top, z, B.LEAVES)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var reach := 2 if absi(d.x) + absi(d.y) == 2 else 3
		for k in range(1, reach + 1):
			g.set_block(x + d.x * k, top - (1 if k == reach else 0), z + d.y * k, B.LEAVES)
