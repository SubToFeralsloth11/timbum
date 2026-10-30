extends RefCounted
## Village: cottages and a two-storey inn around a cobbled market square,
## a windmill with a lookout floor on the north-west hill, farm fields,
## orchards, and a hedge ring around rolling meadows.

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(64, 30, 64)
const KILL_Y := -10.0
const SEED := 1101
const ATMOSPHERE := {
	"sky_top": Color("3f7fd6"), "sky_horizon": Color("a9cbe8"), "ground_bottom": Color("4d5a3a"),
	"sun_pitch": -48.0, "sun_yaw": -35.0, "sun_color": Color("fff1d6"), "sun_energy": 1.35,
	"fog_color": Color("b9d2e6"), "fog_density": 0.0025, "ambient": 0.75, "exposure": 1.0, "fog_sky": 0.15,
}

## Cottages: [x0, z0, x1, z1, ridge along x, doors as [side, offset]] with
## sides 0 north (-Z), 1 south (+Z), 2 west (-X), 3 east (+X).
const COTTAGES := [
	[22, 13, 28, 19, true, [[1, 2], [2, 2]], B.PLANKS],
	[45, 26, 51, 33, false, [[2, 3], [3, 3]], B.BRICK],
	[44, 42, 50, 48, true, [[0, 2], [2, 2]], B.PLANKS],
	[11, 31, 17, 38, false, [[3, 3], [2, 3]], B.COBBLE],
	[25, 47, 31, 53, true, [[0, 2], [1, 2]], B.BRICK],
]
const INN := [34, 12, 42, 20]
const MILL := [6, 6, 12, 13]
const SQUARE := [22, 24, 41, 41]
## Jump pads (MapKit.jump_pads): onto three of the market stalls' awnings, each with a drop back
## down to the square.
const JUMP_PADS := [
	[Vector3i(28, 5, 32), Vector3i(25, 9, 39), 1.5, Vector3(25.5, 9, 36.5), Vector3(25.5, 5, 35.5)],
	[Vector3i(42, 5, 36), Vector3i(37, 9, 27), 1.5, Vector3(37.5, 9, 26.5), Vector3(37.5, 5, 25.5)],
	[Vector3i(14, 5, 26), Vector3i(24, 9, 27), 1.5, Vector3(24.5, 9, 26.5), Vector3(24.5, 5, 25.5)],
]


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var sx := g.size.x
	var hm := Kit.heightmap(g, 0)
	for z in g.size.z:
		for x in sx:
			var e := mini(mini(x, z), mini(sx - 1 - x, g.size.z - 1 - z))
			var hill := maxf(0.0, 6.0 - Vector2(x - 9, z - 9).length() / 2.4)
			var center_fade := clampf(Vector2(x - 32, z - 33).length() / 22.0, 0.0, 1.0)
			var n := (G.noise2(x / 11.0, z / 11.0, SEED) - 0.5) * 4.0 * center_fade
			var berm := maxf(0.0, 4.0 - e)
			hm[z * sx + x] = 5 + roundi(hill + n + berm)

	var lock := PackedByteArray()
	lock.resize(sx * g.size.z)
	var reserved := PackedByteArray()
	reserved.resize(sx * g.size.z)
	var pads: Array = [SQUARE, INN, MILL]
	for c: Array in COTTAGES:
		pads.append(c)
	for p: Array in pads:
		var h := 5 if p == SQUARE else 0
		if h == 0:
			for z in range(p[1] - 1, p[3] + 2):
				for x in range(p[0] - 1, p[2] + 2):
					h = maxi(h, hm[z * sx + x])
		Kit.rect(g, hm, p[0] - 1, p[1] - 1, p[2] + 1, p[3] + 1, h)
		_mark(lock, sx, p[0] - 1, p[1] - 1, p[2] + 1, p[3] + 1)
		_mark(reserved, sx, p[0] - 3, p[1] - 3, p[2] + 3, p[3] + 3)
	Kit.limit_steps(g, hm, lock)
	g.apply_heightmap(hm, B.GRASS, B.DIRT, B.STONE)
	g.auto_ramps(hm, B.GRASS)

	_paths(g, hm, reserved)
	Kit.paint_top(g, hm, SQUARE[0], SQUARE[1], SQUARE[2], SQUARE[3], B.COBBLE)
	_square(g, rng)
	for c: Array in COTTAGES:
		_cottage(g, hm, c, rng)
	_inn(g, hm)
	_mill(g, hm)
	_fields(g, hm, reserved)

	# Hedge ring along the berm.
	for z in g.size.z:
		for x in sx:
			var e := mini(mini(x, z), mini(sx - 1 - x, g.size.z - 1 - z))
			if e <= 1:
				var h := hm[z * sx + x]
				g.fill(Vector3i(x, h, z), Vector3i(x, h + 2 + (1 if G.hash01(x, z, SEED) > 0.5 else 0), z), B.LEAVES)
	_trees(g, hm, reserved, rng)

	for s: Vector2i in [
		Vector2i(7, 26), Vector2i(20, 6), Vector2i(31, 7), Vector2i(53, 7), Vector2i(57, 21),
		Vector2i(57, 38), Vector2i(55, 56), Vector2i(39, 57), Vector2i(19, 57), Vector2i(6, 52),
		Vector2i(6, 41), Vector2i(29, 29), Vector2i(38, 37), Vector2i(36, 25), Vector2i(19, 23),
	]:
		Kit.spawn(g, hm, info, s.x, s.y)
	Kit.pickup(g, hm, info, "health", 31, 35)
	Kit.pickup(g, hm, info, "ammo", 24, 39)
	Kit.pickup(g, hm, info, "ammo", 47, 37)
	Kit.pickup(g, hm, info, "grenade", 12, 47)
	Kit.pickup(g, hm, info, "health", 38, 15, hm[16 * sx + 38] + 4)
	Kit.pickup(g, hm, info, "ammo", 11, 10, hm[9 * sx + 9] + 4)
	Kit.pickup(g, hm, info, "health", 52, 15)
	Kit.pickup(g, hm, info, "grenade", 20, 44)
	Kit.jump_pads(g, info, JUMP_PADS)


static func _mark(mask: PackedByteArray, sx: int, x0: int, z0: int, x1: int, z1: int) -> void:
	for z in range(maxi(z0, 0), mini(z1, mask.size() / sx - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, sx - 1) + 1):
			mask[z * sx + x] = 1


static func _paths(g: VoxelGrid, hm: PackedInt32Array, reserved: PackedByteArray) -> void:
	var sx := g.size.x
	for seg: Array in [
		[25, 20, 26, 23], [37, 21, 38, 23], [42, 29, 44, 30], [42, 37, 47, 38], [46, 39, 47, 41],
		[18, 34, 21, 35], [28, 42, 29, 46], [14, 14, 15, 30], [16, 14, 21, 15],
		[30, 42, 31, 62], [42, 30, 62, 31], [0, 30, 10, 31], [30, 0, 31, 11],
	]:
		Kit.paint_top(g, hm, seg[0], seg[1], seg[2], seg[3], B.GRAVEL)
		_mark(reserved, sx, seg[0], seg[1], seg[2], seg[3])


static func _square(g: VoxelGrid, rng: RandomNumberGenerator) -> void:
	var f := 5
	# Well with a little roof in the middle.
	g.walls(Vector3i(30, f, 31), Vector3i(33, f, 34), B.COBBLE)
	g.fill(Vector3i(31, f - 1, 32), Vector3i(32, f - 1, 33), B.ICE)
	for p: Vector2i in [Vector2i(30, 31), Vector2i(33, 31), Vector2i(30, 34), Vector2i(33, 34)]:
		g.fill(Vector3i(p.x, f + 1, p.y), Vector3i(p.x, f + 2, p.y), B.LOG)
	Kit.gable_roof(g, 29, 30, 34, 35, f + 3, true, B.ROOF, B.DARK_PLANKS)
	# Market stalls with striped awnings.
	var cloth := [B.RED, B.BLUE, B.YELLOW, B.GREEN]
	var stalls := [Vector2i(24, 27), Vector2i(37, 27), Vector2i(24, 37), Vector2i(37, 37)]
	for s in stalls.size():
		var p: Vector2i = stalls[s]
		g.fill(Vector3i(p.x, f, p.y), Vector3i(p.x + 2, f, p.y), B.PLANKS)
		g.set_block(p.x + rng.randi_range(0, 2), f + 1, p.y, B.CRATE)
		for c: Vector2i in [Vector2i(p.x, p.y), Vector2i(p.x + 2, p.y), Vector2i(p.x, p.y + 2), Vector2i(p.x + 2, p.y + 2)]:
			g.fill(Vector3i(c.x, f + 1 if c.y == p.y else f, c.y), Vector3i(c.x, f + 2, c.y), B.LOG)
		for x in range(p.x - 1, p.x + 4):
			for z in range(p.y - 1, p.y + 4):
				g.set_block(x, f + 3, z, cloth[s] if (x + z) % 2 == 0 else B.WHITE)
	# Lamp posts and hay bales for cover.
	for p: Vector2i in [Vector2i(22, 24), Vector2i(41, 24), Vector2i(22, 41), Vector2i(41, 41)]:
		g.fill(Vector3i(p.x, f, p.y), Vector3i(p.x, f + 2, p.y), B.LOG)
		g.set_block(p.x, f + 3, p.y, B.LAMP)
	for p: Vector3i in [Vector3i(28, 0, 26), Vector3i(35, 0, 39), Vector3i(27, 0, 39), Vector3i(35, 0, 31)]:
		g.fill(Vector3i(p.x, f, p.z), Vector3i(p.x + 1, f, p.z), B.YELLOW)
		g.set_block(p.x, f + 1, p.z, B.YELLOW)


## Single-storey cottage with two doors, windows on every wall and a gable roof.
static func _cottage(g: VoxelGrid, hm: PackedInt32Array, c: Array, rng: RandomNumberGenerator) -> void:
	var x0: int = c[0]
	var z0: int = c[1]
	var x1: int = c[2]
	var z1: int = c[3]
	var wall: int = c[6]
	var f := hm[z0 * g.size.x + x0]
	g.fill(Vector3i(x0, f - 1, z0), Vector3i(x1, f - 1, z1), B.DARK_PLANKS)
	g.walls(Vector3i(x0, f, z0), Vector3i(x1, f + 3, z1), wall)
	for p: Vector2i in [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1)]:
		g.fill(Vector3i(p.x, f, p.y), Vector3i(p.x, f + 3, p.y), B.LOG)
	g.fill(Vector3i(x0, f + 3, z0), Vector3i(x1, f + 3, z0), B.LOG)
	g.fill(Vector3i(x0, f + 3, z1), Vector3i(x1, f + 3, z1), B.LOG)
	g.fill(Vector3i(x0, f + 3, z0), Vector3i(x0, f + 3, z1), B.LOG)
	g.fill(Vector3i(x1, f + 3, z0), Vector3i(x1, f + 3, z1), B.LOG)
	# Windows centred on each wall, then doors (which may replace a window).
	var mx := (x0 + x1) / 2
	var mz := (z0 + z1) / 2
	g.fill(Vector3i(mx, f + 1, z0), Vector3i(mx + 1, f + 2, z0), B.GLASS)
	g.fill(Vector3i(mx, f + 1, z1), Vector3i(mx + 1, f + 2, z1), B.GLASS)
	g.fill(Vector3i(x0, f + 1, mz), Vector3i(x0, f + 2, mz + 1), B.GLASS)
	g.fill(Vector3i(x1, f + 1, mz), Vector3i(x1, f + 2, mz + 1), B.GLASS)
	for d: Array in c[5]:
		var o: int = d[1]
		match d[0]:
			0: g.clear(Vector3i(x0 + o, f, z0), Vector3i(x0 + o + 1, f + 2, z0))
			1: g.clear(Vector3i(x0 + o, f, z1), Vector3i(x0 + o + 1, f + 2, z1))
			2: g.clear(Vector3i(x0, f, z0 + o), Vector3i(x0, f + 2, z0 + o + 1))
			3: g.clear(Vector3i(x1, f, z0 + o), Vector3i(x1, f + 2, z0 + o + 1))
	# Furniture: a table and a bed as cover.
	g.set_block(x0 + 1, f, z0 + 1, B.CRATE)
	g.fill(Vector3i(x1 - 1, f, z1 - 2), Vector3i(x1 - 1, f, z1 - 1), B.RED if rng.randf() < 0.5 else B.BLUE)
	var along_x: bool = c[4]
	Kit.gable_roof(g, x0 - 1, z0 - 1, x1 + 1, z1 + 1, f + 4, along_x, B.ROOF, wall)


## Two-storey inn: interior ramp to an upper floor with windows over the
## square and a balcony.
static func _inn(g: VoxelGrid, hm: PackedInt32Array) -> void:
	var x0: int = INN[0]
	var z0: int = INN[1]
	var x1: int = INN[2]
	var z1: int = INN[3]
	var f := hm[z0 * g.size.x + x0]
	g.fill(Vector3i(x0, f - 1, z0), Vector3i(x1, f - 1, z1), B.DARK_PLANKS)
	g.walls(Vector3i(x0, f, z0), Vector3i(x1, f + 7, z1), B.PLANKS)
	g.walls(Vector3i(x0, f, z0), Vector3i(x1, f + 2, z1), B.COBBLE)
	for p: Vector2i in [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1)]:
		g.fill(Vector3i(p.x, f, p.y), Vector3i(p.x, f + 7, p.y), B.LOG)
	# Upper floor with a hole over the ramp.
	g.fill(Vector3i(x0 + 1, f + 3, z0 + 1), Vector3i(x1 - 1, f + 3, z1 - 1), B.DARK_PLANKS)
	g.clear(Vector3i(x0 + 1, f + 3, z0 + 1), Vector3i(x0 + 5, f + 3, z0 + 2))
	g.ramp_run(Vector3i(x0 + 2, f, z0 + 1), G.RAMP_PX, 4, 2, B.DARK_PLANKS, B.DARK_PLANKS)
	# Ground doors (south to the square, west) and windows.
	g.clear(Vector3i(x0 + 3, f, z1), Vector3i(x0 + 4, f + 2, z1))
	g.clear(Vector3i(x0, f, z0 + 4), Vector3i(x0, f + 2, z0 + 5))
	g.fill(Vector3i(x1, f + 1, z0 + 3), Vector3i(x1, f + 1, z0 + 5), B.GLASS)
	# Upper windows on all sides; open on the south so players can shoot out.
	g.clear(Vector3i(x0 + 2, f + 5, z1), Vector3i(x0 + 6, f + 5, z1))
	g.fill(Vector3i(x0 + 2, f + 5, z0), Vector3i(x0 + 6, f + 6, z0), B.GLASS)
	g.clear(Vector3i(x1, f + 5, z0 + 2), Vector3i(x1, f + 5, z0 + 5))
	g.fill(Vector3i(x0, f + 5, z0 + 2), Vector3i(x0, f + 6, z0 + 5), B.GLASS)
	# Balcony over the south door.
	g.clear(Vector3i(x0 + 6, f + 4, z1), Vector3i(x0 + 7, f + 6, z1))
	g.fill(Vector3i(x0 + 5, f + 3, z1 + 1), Vector3i(x1, f + 3, z1 + 2), B.DARK_PLANKS)
	g.fill(Vector3i(x0 + 5, f + 4, z1 + 2), Vector3i(x1, f + 4, z1 + 2), B.LOG)
	g.set_block(x0 + 5, f + 4, z1 + 1, B.LOG)
	g.set_block(x0 + 6, f + 5, z1 - 1, B.LAMP)
	Kit.gable_roof(g, x0 - 1, z0 - 1, x1 + 1, z1 + 1, f + 8, true, B.ROOF, B.PLANKS)


## Windmill on the hill: ground floor with two doors, a ramp to a lookout
## floor with open windows, and diagonal sails.
static func _mill(g: VoxelGrid, hm: PackedInt32Array) -> void:
	var x0: int = MILL[0]
	var z0: int = MILL[1]
	var x1: int = MILL[2]
	var z1: int = MILL[3]
	var f := hm[z0 * g.size.x + x0]
	g.fill(Vector3i(x0, f - 1, z0), Vector3i(x1, f - 1, z1), B.PLANKS)
	g.walls(Vector3i(x0, f, z0), Vector3i(x1, f + 8, z1), B.COBBLE)
	g.walls(Vector3i(x0, f + 4, z0), Vector3i(x1, f + 8, z1), B.WHITE)
	for p: Vector2i in [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1)]:
		g.fill(Vector3i(p.x, f, p.y), Vector3i(p.x, f + 8, p.y), B.LOG)
	g.fill(Vector3i(x0 + 1, f + 3, z0 + 1), Vector3i(x1 - 1, f + 3, z1 - 1), B.PLANKS)
	g.clear(Vector3i(x0 + 1, f + 3, z0 + 2), Vector3i(x0 + 2, f + 3, z1 - 2))
	g.ramp_run(Vector3i(x0 + 1, f, z1 - 2), G.RAMP_NZ, 4, 2, B.PLANKS, B.PLANKS)
	g.clear(Vector3i(x0 + 3, f, z1), Vector3i(x0 + 4, f + 2, z1))
	g.clear(Vector3i(x1, f, z0 + 3), Vector3i(x1, f + 2, z0 + 4))
	g.clear(Vector3i(x0 + 3, f + 5, z1), Vector3i(x0 + 5, f + 6, z1))
	g.clear(Vector3i(x1, f + 5, z0 + 2), Vector3i(x1, f + 6, z0 + 4))
	g.fill(Vector3i(x0 + 2, f + 5, z0), Vector3i(x0 + 4, f + 5, z0), B.GLASS)
	g.set_block(x0 + 5, f + 6, z0 + 1, B.LAMP)
	Kit.gable_roof(g, x0 - 1, z0 - 1, x1 + 1, z1 + 1, f + 9, true, B.ROOF, B.WHITE)
	# Sails on the north face: an X of planks with white cloth.
	var hub := Vector3i((x0 + x1) / 2, f + 7, z0 - 1)
	g.set_block(hub.x, hub.y, hub.z, B.LOG)
	g.set_block(hub.x, hub.y, hub.z + 1, B.LOG)
	for diag: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		for k in range(1, 6):
			var p := hub + Vector3i(diag.x * k, diag.y * k, 0)
			g.set_block(p.x, p.y, p.z, B.DARK_PLANKS)
			if k >= 2:
				g.set_block(p.x + diag.x * -diag.y, p.y, p.z, B.WHITE)
				g.set_block(p.x, p.y + diag.y * diag.x, p.z, B.WHITE)


## Wheat rows south-west and a cabbage patch, with 2-wide walkways.
static func _fields(g: VoxelGrid, hm: PackedInt32Array, reserved: PackedByteArray) -> void:
	var sx := g.size.x
	for z in range(45, 57):
		for x in range(6, 19):
			var h := hm[z * sx + x]
			if g.get_shape(x, h, z) != G.CUBE or not g.is_cube(x, h - 1, z):
				continue
			g.set_block(x, h - 1, z, B.DIRT)
			if x % 3 == 0 and z != 50 and z != 51:
				g.set_block(x, h, z, B.YELLOW)
	_mark(reserved, sx, 4, 43, 20, 58)
	# Log fence along the north edge with wide gaps into the walkways.
	for x in range(5, 20):
		if x % 3 == 0 and x != 12:
			g.set_block(x, hm[44 * sx + x], 44, B.LOG)


static func _trees(g: VoxelGrid, hm: PackedInt32Array, reserved: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var sx := g.size.x
	var placed: Array[Vector2i] = []
	var tries := 0
	while placed.size() < 26 and tries < 600:
		tries += 1
		var x := rng.randi_range(4, sx - 5)
		var z := rng.randi_range(4, g.size.z - 5)
		if reserved[z * sx + x] != 0:
			continue
		var h := hm[z * sx + x]
		if not g.is_cube(x, h - 1, z) or not g.is_air(x, h, z):
			continue
		var far := true
		for p in placed:
			if absi(p.x - x) + absi(p.y - z) < 6:
				far = false
				break
		if not far:
			continue
		placed.append(Vector2i(x, z))
		Kit.oak(g, x, h, z, rng)
		_mark(reserved, sx, x - 1, z - 1, x + 1, z + 1)
