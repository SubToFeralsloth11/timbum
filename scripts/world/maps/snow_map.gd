extends RefCounted
## Snow Fort: two mirrored stone forts (walkways behind crenellated front
## walls, a keep with a roof nest) facing each other across a pine forest
## with a frozen pond, a rocky hill and a log cabin. Snowy cliffs all round.

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(64, 30, 64)
const KILL_Y := -10.0
const SEED := 5505
const ATMOSPHERE := {
	"sky_top": Color("7f9bbd"), "sky_horizon": Color("dfe7ef"), "ground_bottom": Color("c9d3dd"),
	"sun_pitch": -28.0, "sun_yaw": 150.0, "sun_color": Color("ffe9d0"), "sun_energy": 1.1,
	"fog_color": Color("d9e2ec"), "fog_density": 0.006, "ambient": 0.9, "exposure": 0.95,
	"fog_sky": 0.3, "ambient_color": Color("d4dde8"), "saturation": 1.0,
}
const F := 5
const POND := Vector2(31.5, 31.5)
const CABIN := Rect2i(28, 49, 8, 7)
## Jump pads (MapKit.jump_pads): from the forest floor in front of each fort up onto its walkway.
const JUMP_PADS := [
	[Vector3i(12, 5, 22), Vector3i(12, 10, 28), 1.5],
	[Vector3i(52, 5, 22), Vector3i(52, 10, 28), 1.5],
]


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var sx := g.size.x
	var hm := Kit.heightmap(g, 0)
	var lock := PackedByteArray()
	lock.resize(sx * g.size.z)
	for z in g.size.z:
		for x in sx:
			var e := mini(mini(x, z), mini(sx - 1 - x, g.size.z - 1 - z))
			var n := (G.noise2(x / 10.0, z / 10.0, SEED) - 0.5) * 3.5
			var hill := maxf(0.0, 3.5 - Vector2(x - 31.5, z - 11).length() / 1.8)
			hm[z * sx + x] = F + roundi(n + hill + maxf(0.0, 4.0 - e))
			if _in_pond(x, z):
				hm[z * sx + x] = F - 1
				lock[z * sx + x] = 1
	for mode: int in [Kit.XF_NONE, Kit.XF_MIRROR_X]:
		var a := Kit.xf(g, mode, 4, 0, 18)
		var b := Kit.xf(g, mode, 23, 0, 45)
		Kit.rect(g, hm, mini(a.x, b.x), 18, maxi(a.x, b.x), 45, F)
		for z in range(18, 46):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				lock[z * sx + x] = 1
	Kit.rect(g, hm, CABIN.position.x - 2, CABIN.position.y - 2, CABIN.end.x + 1, CABIN.end.y + 1, F)
	for z in range(CABIN.position.y - 2, CABIN.end.y + 2):
		for x in range(CABIN.position.x - 2, CABIN.end.x + 2):
			lock[z * sx + x] = 1
	Kit.limit_steps(g, hm, lock)
	g.apply_heightmap(hm, B.SNOW, B.DIRT, B.STONE)
	g.auto_ramps(hm, B.SNOW)
	for z in g.size.z:
		for x in sx:
			if _in_pond(x, z):
				g.set_block(x, hm[z * sx + x] - 1, z, B.ICE)

	_fort(g, Kit.XF_NONE, B.RED)
	_fort(g, Kit.XF_MIRROR_X, B.BLUE)
	_cabin(g, hm)
	_cliffs(g, hm)
	_forest(g, hm, rng)

	for s: Vector2i in [
		Vector2i(17, 23), Vector2i(4, 25), Vector2i(8, 41), Vector2i(46, 23), Vector2i(59, 25),
		Vector2i(55, 41), Vector2i(26, 17), Vector2i(37, 17), Vector2i(26, 47), Vector2i(38, 46),
		Vector2i(12, 9), Vector2i(51, 9), Vector2i(12, 55), Vector2i(51, 55), Vector2i(31, 24),
	]:
		Kit.spawn(g, hm, info, s.x, s.y)
	Kit.pickup(g, hm, info, "health", 13, 28, F + 5)
	Kit.pickup(g, hm, info, "health", 50, 35, F + 5)
	Kit.pickup(g, hm, info, "ammo", 31, 31)
	Kit.pickup(g, hm, info, "grenade", 32, 52)
	Kit.pickup(g, hm, info, "health", 31, 11)
	Kit.pickup(g, hm, info, "ammo", 19, 22, F + 3)
	Kit.pickup(g, hm, info, "ammo", 44, 41, F + 3)
	Kit.pickup(g, hm, info, "grenade", 31, 39)
	Kit.jump_pads(g, info, JUMP_PADS)


static func _in_pond(x: int, z: int) -> bool:
	var d := Vector2((x + 0.5 - POND.x) / 4.5, (z + 0.5 - POND.y) / 6.5)
	return d.length() <= 1.0


## West fort in local coordinates; `mode` mirrors it to the east side.
static func _fort(g: VoxelGrid, m: int, banner: int) -> void:
	# Curtain wall with a cobble footing, gates on all four sides.
	Kit.box(g, m, 6, F, 20, 21, F + 3, 20, B.STONE_BRICK)
	Kit.box(g, m, 6, F, 43, 21, F + 3, 43, B.STONE_BRICK)
	Kit.box(g, m, 6, F, 20, 6, F + 3, 43, B.STONE_BRICK)
	Kit.box(g, m, 21, F, 20, 21, F + 3, 43, B.STONE_BRICK)
	for z: int in [20, 43]:
		Kit.box(g, m, 6, F, z, 21, F, z, B.COBBLE)
	for x: int in [6, 21]:
		Kit.box(g, m, x, F, 20, x, F, 43, B.COBBLE)
	for x in range(6, 22):
		for z in range(20, 44):
			var edge := x == 6 or x == 21 or z == 20 or z == 43
			if edge and (x + z) % 2 == 0:
				Kit.put(g, m, x, F + 4, z, B.SNOW_BLOCK if (x * 7 + z) % 5 == 0 else B.STONE_BRICK)
	Kit.box(g, m, 21, F, 30, 21, F + 4, 33, B.AIR)
	Kit.box(g, m, 6, F, 30, 6, F + 4, 32, B.AIR)
	Kit.box(g, m, 12, F, 20, 14, F + 4, 20, B.AIR)
	Kit.box(g, m, 12, F, 43, 14, F + 4, 43, B.AIR)
	# Plank walkways behind the front wall, each half with its own ramp.
	Kit.box(g, m, 19, F + 2, 21, 20, F + 2, 25, B.DARK_PLANKS)
	Kit.box(g, m, 19, F + 2, 38, 20, F + 2, 42, B.DARK_PLANKS)
	Kit.ramp(g, m, Vector3i(19, F, 28), G.RAMP_NZ, 3, 2, B.DARK_PLANKS, B.DARK_PLANKS)
	Kit.ramp(g, m, Vector3i(19, F, 35), G.RAMP_PZ, 3, 2, B.DARK_PLANKS, B.DARK_PLANKS)
	for z: int in [22, 41]:
		Kit.box(g, m, 19, F, z, 19, F + 1, z, B.LOG)
	# Keep with a ramp to its crenellated roof.
	Kit.box(g, m, 9, F, 26, 15, F + 4, 37, B.STONE_BRICK)
	Kit.box(g, m, 10, F, 27, 14, F + 3, 36, B.AIR)
	Kit.box(g, m, 10, F + 4, 31, 12, F + 4, 35, B.AIR)
	Kit.ramp(g, m, Vector3i(10, F, 35), G.RAMP_NZ, 5, 3, B.STONE_BRICK, B.STONE_BRICK)
	Kit.box(g, m, 15, F, 28, 15, F + 2, 30, B.AIR)
	Kit.box(g, m, 9, F, 27, 9, F + 2, 28, B.AIR)
	Kit.box(g, m, 13, F, 37, 14, F + 2, 37, B.AIR)
	Kit.box(g, m, 10, F + 2, 26, 10, F + 2, 26, B.GLASS)
	for x in range(9, 16):
		for z in range(26, 38):
			var edge := x == 9 or x == 15 or z == 26 or z == 37
			if edge and (x + z) % 2 == 1:
				Kit.put(g, m, x, F + 5, z, B.STONE_BRICK)
	Kit.put(g, m, 14, F + 3, 27, B.LAMP)
	Kit.put(g, m, 9, F + 5, 26, B.LAMP)
	# Turrets at the front corners, banners on the front face.
	for z: int in [19, 43]:
		Kit.box(g, m, 21, F, z, 22, F + 6, z + 1, B.STONE_BRICK)
		Kit.box(g, m, 21, F + 7, z, 22, F + 7, z + 1, B.SNOW_BLOCK)
	for z: int in [26, 37]:
		Kit.box(g, m, 22, F + 1, z, 22, F + 3, z, banner)
	# Courtyard: campfire and supplies.
	Kit.put(g, m, 17, F, 24, B.LAMP)
	Kit.box(g, m, 16, F, 40, 17, F, 40, B.CRATE)
	Kit.put(g, m, 16, F + 1, 40, B.CRATE)
	Kit.box(g, m, 7, F, 22, 8, F, 22, B.CRATE)


## Log cabin in the south clearing (on the CABIN pad) with a snowy roof.
static func _cabin(g: VoxelGrid, hm: PackedInt32Array) -> void:
	var x0: int = CABIN.position.x
	var z0: int = CABIN.position.y
	var x1: int = CABIN.end.x - 1
	var z1: int = CABIN.end.y - 1
	var f := hm[z0 * g.size.x + x0]
	g.fill(Vector3i(x0, f - 1, z0), Vector3i(x1, f - 1, z1), B.DARK_PLANKS)
	g.walls(Vector3i(x0, f, z0), Vector3i(x1, f + 3, z1), B.LOG)
	g.clear(Vector3i(x0 + 3, f, z0), Vector3i(x0 + 4, f + 2, z0))
	g.clear(Vector3i(x0 + 3, f, z1), Vector3i(x0 + 4, f + 2, z1))
	g.clear(Vector3i(x0, f, z0 + 2), Vector3i(x0, f + 2, z0 + 3))
	g.fill(Vector3i(x1, f + 1, z0 + 2), Vector3i(x1, f + 2, z0 + 4), B.GLASS)
	g.set_block(x1 - 1, f + 2, z1 - 1, B.LAMP)
	g.fill(Vector3i(x1 - 1, f, z0 + 1), Vector3i(x1 - 1, f, z0 + 2), B.CRATE)
	Kit.gable_roof(g, x0 - 1, z0 - 1, x1 + 1, z1 + 1, f + 4, true, B.SNOW_BLOCK, B.DARK_PLANKS)


static func _cliffs(g: VoxelGrid, hm: PackedInt32Array) -> void:
	var sx := g.size.x
	for z in g.size.z:
		for x in sx:
			var e := mini(mini(x, z), mini(sx - 1 - x, g.size.z - 1 - z))
			if e > 2:
				continue
			var top := hm[z * sx + x] + 5 + int(G.noise2(x / 3.0, z / 3.0, SEED + 3) * 5.0) - e * 2
			g.fill(Vector3i(x, 0, z), Vector3i(x, top - 2, z), B.STONE)
			g.fill(Vector3i(x, top - 1, z), Vector3i(x, top, z), B.SNOW_BLOCK)


## Pines everywhere outside the forts, the pond and the cabin, plus boulders.
static func _forest(g: VoxelGrid, hm: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var sx := g.size.x
	var placed: Array[Vector2i] = []
	var tries := 0
	while placed.size() < 34 and tries < 900:
		tries += 1
		var x := rng.randi_range(4, sx - 5)
		var z := rng.randi_range(4, g.size.z - 5)
		if (x < 25 or x > 38) and z >= 16 and z <= 47:
			continue
		if (x >= 26 and x <= 37 and z >= 47 and z <= 57) or Vector2(x - POND.x, z - POND.y).length() < 9.0:
			continue
		var f := hm[z * sx + x]
		if not g.is_cube(x, f - 1, z) or not g.is_air(x, f, z):
			continue
		var far := true
		for p in placed:
			if absi(p.x - x) + absi(p.y - z) < 5:
				far = false
				break
		if not far:
			continue
		placed.append(Vector2i(x, z))
		if placed.size() % 6 == 0:
			g.fill(Vector3i(x, f, z), Vector3i(x + 1, f, z + 1), B.COBBLE)
			g.set_block(x, f + 1, z, B.STONE)
		else:
			Kit.pine(g, x, f, z, rng.randi_range(6, 9), true)
