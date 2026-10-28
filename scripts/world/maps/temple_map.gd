extends RefCounted
## Jungle Temple: a stepped pyramid with stairs on two faces, a shrine on top
## and a pillared chamber inside reached by four tunnels, in a jungle of tall
## trees. A river gorge cuts off the south ruins and is crossed by a stone
## bridge, a plank bridge and a fallen tree. Falling into the river means
## death (kill_y).

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(64, 34, 64)
## Above the river surface (y = 2), well below the lowest bank.
const KILL_Y := 3.0
const SEED := 7707
const ATMOSPHERE := {
	"sky_top": Color("4c84b4"), "sky_horizon": Color("d2e2c6"), "ground_bottom": Color("3b5530"),
	"sun_pitch": -55.0, "sun_yaw": 30.0, "sun_color": Color("fff0c6"), "sun_energy": 1.3,
	"fog_color": Color("b6cbab"), "fog_density": 0.008, "ambient": 0.8, "exposure": 1.0,
	"saturation": 1.15, "fog_sky": 0.35, "ambient_color": Color("b7c7a8"),
}
const F := 7
const WATER_TOP := 2
## Pyramid centre and the half-widths of its three tiers (two cells each).
const PC := Vector2i(32, 26)
const TIERS := [10, 7, 4]
## Bridges across the river: [x0, x1, kind] (0 stone, 1 planks, 2 fallen log).
const BRIDGES := [[8, 10, 1], [30, 34, 0], [52, 54, 2]]
const TOWER := [4, 4, 12, 12]
const TERRACE := [26, 55, 38, 60]


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var sx := g.size.x
	var hm := Kit.heightmap(g, 0)
	for z in g.size.z:
		for x in sx:
			var e := mini(mini(x, z), mini(sx - 1 - x, g.size.z - 1 - z))
			var n := (G.noise2(x / 9.0, z / 9.0, SEED) - 0.5) * 4.5
			hm[z * sx + x] = F + roundi(n + maxf(0.0, 4.0 - e))
	var lock := PackedByteArray()
	lock.resize(sx * g.size.z)
	var reserved := PackedByteArray()
	reserved.resize(sx * g.size.z)
	_pad(g, hm, lock, PC.x - 13, PC.y - 14, PC.x + 13, PC.y + 14)
	_pad(g, hm, lock, TOWER[0] - 2, TOWER[1] - 2, TOWER[2] + 2, TOWER[3] + 2)
	_pad(g, hm, lock, TERRACE[0] - 6, TERRACE[1] - 3, TERRACE[2] + 6, TERRACE[3] + 1)
	_pad(g, hm, lock, 44, 6, 58, 18)
	for b: Array in BRIDGES:
		var zr := _river_span(b[0], b[1])
		_pad(g, hm, lock, b[0] - 2, zr.x - 4, b[1] + 2, zr.y + 4)
		_mark(reserved, sx, b[0] - 2, zr.x - 5, b[1] + 2, zr.y + 5)
	Kit.limit_steps(g, hm, lock)
	g.apply_heightmap(hm, B.GRASS, B.DIRT, B.STONE)
	g.auto_ramps(hm, B.GRASS)
	_mark(reserved, sx, PC.x - 13, PC.y - 14, PC.x + 13, PC.y + 14)
	_mark(reserved, sx, TOWER[0] - 1, TOWER[1] - 1, TOWER[2] + 1, TOWER[3] + 1)
	_mark(reserved, sx, TERRACE[0] - 5, TERRACE[1] - 3, TERRACE[2] + 5, TERRACE[3] + 1)
	_mark(reserved, sx, 44, 6, 58, 18)

	# The gorge: sheer earth banks down to the water.
	for z in g.size.z:
		for x in sx:
			if _in_river(x, z):
				g.clear(Vector3i(x, WATER_TOP, z), Vector3i(x, g.size.y - 1, z))
				g.fill(Vector3i(x, 0, z), Vector3i(x, WATER_TOP - 1, z), B.WATER)
				hm[z * sx + x] = WATER_TOP
				_mark(reserved, sx, x - 2, z - 2, x + 2, z + 2)
			elif _in_river(x, z - 1) or _in_river(x, z + 1):
				var h := hm[z * sx + x]
				for y in range(WATER_TOP, h - 1):
					if G.hash01(x, y, SEED + 3) > 0.7:
						g.set_block(x, y, z, B.MOSSY_BRICK if y < 4 else B.STONE)

	_pyramid(g)
	for b: Array in BRIDGES:
		_bridge(g, b)
	_tower(g)
	_terrace(g)
	_colonnade(g, rng)
	_ruin_wall(g, hm, Vector2i(7, 27), Vector2i(7, 35))
	_ruin_wall(g, hm, Vector2i(8, 27), Vector2i(14, 27))
	_ruin_wall(g, hm, Vector2i(52, 30), Vector2i(57, 30))
	_ruin_wall(g, hm, Vector2i(52, 31), Vector2i(52, 36))
	_ruin_wall(g, hm, Vector2i(6, 56), Vector2i(13, 56))
	_ruin_wall(g, hm, Vector2i(50, 57), Vector2i(57, 57))
	_ruin_wall(g, hm, Vector2i(19, 15), Vector2i(19, 20))
	_ruin_wall(g, hm, Vector2i(45, 33), Vector2i(45, 38))
	for p: Vector2i in [Vector2i(5, 25), Vector2i(4, 54), Vector2i(48, 55), Vector2i(48, 29), Vector2i(17, 14), Vector2i(43, 32)]:
		_mark(reserved, sx, p.x, p.y, p.x + 11, p.y + 11)

	# Hedge of jungle along the edges.
	for z in g.size.z:
		for x in sx:
			var e := mini(mini(x, z), mini(sx - 1 - x, g.size.z - 1 - z))
			if e <= 1 and not _in_river(x, z):
				var h := hm[z * sx + x]
				g.fill(Vector3i(x, h, z), Vector3i(x, h + 2 + (1 if G.hash01(x, z, SEED) > 0.5 else 0), z), B.LEAVES)
	_jungle(g, hm, reserved, rng)

	for s: Vector2i in [
		Vector2i(8, 20), Vector2i(20, 6), Vector2i(44, 4), Vector2i(58, 22), Vector2i(6, 38),
		Vector2i(58, 38), Vector2i(15, 31), Vector2i(48, 25), Vector2i(8, 59), Vector2i(19, 59),
		Vector2i(45, 59), Vector2i(57, 60), Vector2i(32, 9),
	]:
		Kit.spawn(g, hm, info, s.x, s.y)
	Kit.spawn(g, hm, info, 32, 23, F)
	Kit.spawn(g, hm, info, 32, 58, F + 2)
	Kit.pickup(g, hm, info, "health", 33, 27, F + 6)
	Kit.pickup(g, hm, info, "grenade", 32, 29, F)
	Kit.pickup(g, hm, info, "health", 35, 58, F + 2)
	Kit.pickup(g, hm, info, "ammo", 8, 6, F + 4)
	Kit.pickup(g, hm, info, "ammo", 21, 30)
	Kit.pickup(g, hm, info, "ammo", 46, 26)
	Kit.pickup(g, hm, info, "grenade", 51, 12)
	Kit.pickup(g, hm, info, "health", 11, 59)
	Kit.pickup(g, hm, info, "ammo", 53, 60)


static func _river_z(x: int) -> float:
	return 47.5 + 2.5 * sin(x / 6.5)


static func _in_river(x: int, z: int) -> bool:
	return absf(z + 0.5 - _river_z(x)) <= 3.0


## Inclusive z range of the river over columns x0..x1.
static func _river_span(x0: int, x1: int) -> Vector2i:
	var r := Vector2i(1 << 20, -1)
	for x in range(x0, x1 + 1):
		for z in SIZE.z:
			if _in_river(x, z):
				r = Vector2i(mini(r.x, z), maxi(r.y, z))
	return r


static func _pad(g: VoxelGrid, hm: PackedInt32Array, lock: PackedByteArray, x0: int, z0: int, x1: int, z1: int) -> void:
	Kit.rect(g, hm, x0, z0, x1, z1, F)
	_mark(lock, g.size.x, x0, z0, x1, z1)


static func _mark(mask: PackedByteArray, sx: int, x0: int, z0: int, x1: int, z1: int) -> void:
	for z in range(maxi(z0, 0), mini(z1, mask.size() / sx - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, sx - 1) + 1):
			mask[z * sx + x] = 1


## Three two-high tiers of mossy brick with stone-brick capping, ramp stairs
## up the south and north faces, a pillared chamber inside and an open shrine
## on top.
static func _pyramid(g: VoxelGrid) -> void:
	for t in TIERS.size():
		var r: int = TIERS[t]
		var y := F + t * 2
		g.fill(Vector3i(PC.x - r, y, PC.y - r), Vector3i(PC.x + r, y, PC.y + r), B.MOSSY_BRICK)
		g.fill(Vector3i(PC.x - r, y + 1, PC.y - r), Vector3i(PC.x + r, y + 1, PC.y + r), B.STONE_BRICK)
		# Vines and moss creeping over the faces.
		for k in range(-r, r + 1):
			for p: Vector2i in [Vector2i(PC.x + k, PC.y - r), Vector2i(PC.x + k, PC.y + r), Vector2i(PC.x - r, PC.y + k), Vector2i(PC.x + r, PC.y + k)]:
				if G.hash01(p.x, p.y + t * 7, SEED + 4) > 0.8:
					g.set_block(p.x, y, p.y, B.LEAVES)
	var top := F + TIERS.size() * 2
	# Stairs: south face (x 31..33) and north face (x 34..36).
	for t in TIERS.size():
		var r: int = TIERS[t]
		g.ramp_run(Vector3i(PC.x - 1, F + t * 2, PC.y + r + 2), G.RAMP_NZ, 2, 3, B.STONE_BRICK, B.MOSSY_BRICK)
		g.ramp_run(Vector3i(PC.x + 2, F + t * 2, PC.y - r - 2), G.RAMP_PZ, 2, 3, B.STONE_BRICK, B.MOSSY_BRICK)
	# Chamber and tunnels.
	var c: int = TIERS[2]
	g.clear(Vector3i(PC.x - c, F, PC.y - c), Vector3i(PC.x + c, F + 3, PC.y + c))
	g.fill(Vector3i(PC.x - c, F - 1, PC.y - c), Vector3i(PC.x + c, F - 1, PC.y + c), B.STONE_BRICK)
	g.fill(Vector3i(PC.x - 1, F - 1, PC.y - 1), Vector3i(PC.x + 1, F - 1, PC.y + 1), B.GOLD)
	g.set_block(PC.x, F, PC.y, B.CARVED)
	for d: Vector2i in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
		g.fill(Vector3i(PC.x + d.x, F, PC.y + d.y), Vector3i(PC.x + d.x, F + 3, PC.y + d.y), B.CARVED)
	var r0: int = TIERS[0]
	g.clear(Vector3i(PC.x - r0, F, PC.y - 1), Vector3i(PC.x - c, F + 2, PC.y + 1))
	g.clear(Vector3i(PC.x + c, F, PC.y - 1), Vector3i(PC.x + r0, F + 2, PC.y + 1))
	g.clear(Vector3i(PC.x - 1, F, PC.y - r0), Vector3i(PC.x + 1, F + 2, PC.y - c))
	g.clear(Vector3i(PC.x - 4, F, PC.y + c), Vector3i(PC.x - 2, F + 2, PC.y + r0))
	for p: Vector3i in [Vector3i(PC.x - c - 1, F + 2, PC.y - 3), Vector3i(PC.x + c + 1, F + 2, PC.y + 3), Vector3i(PC.x + 3, F + 2, PC.y - c - 1), Vector3i(PC.x + 2, F + 2, PC.y + c + 1)]:
		g.set_block(p.x, p.y, p.z, B.LAMP)
	# Shrine: four pillars and a slab roof around a golden altar.
	for d: Vector2i in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
		g.fill(Vector3i(PC.x + d.x, top, PC.y + d.y), Vector3i(PC.x + d.x, top + 2, PC.y + d.y), B.CARVED)
	g.fill(Vector3i(PC.x - 2, top + 3, PC.y - 2), Vector3i(PC.x + 2, top + 3, PC.y + 2), B.STONE_BRICK)
	g.fill(Vector3i(PC.x - 1, top + 4, PC.y - 1), Vector3i(PC.x + 1, top + 4, PC.y + 1), B.MOSSY_BRICK)
	g.set_block(PC.x, top, PC.y, B.GOLD)
	g.set_block(PC.x, top + 2, PC.y, B.LAMP)
	# Braziers on the base corners.
	for d: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		g.set_block(PC.x + d.x * r0, F + 2, PC.y + d.y * r0, B.LAMP)


static func _bridge(g: VoxelGrid, b: Array) -> void:
	var x0: int = b[0]
	var x1: int = b[1]
	var zr := _river_span(x0, x1)
	var z0 := zr.x - 2
	var z1 := zr.y + 2
	match b[2]:
		0:
			g.fill(Vector3i(x0, F - 1, z0), Vector3i(x1, F - 1, z1), B.STONE_BRICK)
			g.fill(Vector3i(x0 + 1, F - 1, z0), Vector3i(x1 - 1, F - 1, z1), B.COBBLE)
			g.fill(Vector3i(x0, F, zr.x), Vector3i(x0, F, zr.y), B.STONE_BRICK)
			g.fill(Vector3i(x1, F, zr.x), Vector3i(x1, F, zr.y), B.STONE_BRICK)
			var mid := (zr.x + zr.y) / 2
			g.fill(Vector3i(x0, 0, mid - 1), Vector3i(x1, F - 2, mid + 1), B.MOSSY_BRICK)
			g.fill(Vector3i(x0, F - 3, zr.x), Vector3i(x1, F - 2, zr.y), B.STONE_BRICK)
			g.clear(Vector3i(x0 + 1, F - 3, zr.x), Vector3i(x1 - 1, F - 3, mid - 2))
			g.clear(Vector3i(x0 + 1, F - 3, mid + 2), Vector3i(x1 - 1, F - 3, zr.y))
			g.set_block(x0, F + 1, mid, B.LAMP)
			g.set_block(x1, F + 1, mid, B.LAMP)
		1:
			for z in range(z0, z1 + 1):
				for x in range(x0, x1 + 1):
					g.set_block(x, F - 1, z, B.PLANKS if z % 4 != 0 else B.DARK_PLANKS)
				g.set_block(x0, F - 2, z, B.LOG)
				g.set_block(x1, F - 2, z, B.LOG)
			for z: int in [zr.x - 1, zr.y + 1]:
				g.fill(Vector3i(x0 - 1, F, z), Vector3i(x0 - 1, F + 1, z), B.LOG)
				g.fill(Vector3i(x1 + 1, F, z), Vector3i(x1 + 1, F + 1, z), B.LOG)
		2:
			g.fill(Vector3i(x0, F - 1, z0), Vector3i(x1, F - 1, z1), B.LOG)
			g.fill(Vector3i(x0 + 1, F - 2, zr.x), Vector3i(x1 - 1, F - 2, zr.y), B.LOG)
			# Root plate and broken crown at either end.
			g.fill(Vector3i(x0 - 1, F, z0 - 2), Vector3i(x1 + 1, F + 2, z0 - 2), B.DIRT)
			g.clear(Vector3i(x0, F, z0 - 2), Vector3i(x1, F + 2, z0 - 2))
			g.fill(Vector3i(x0 - 1, F, z0 - 2), Vector3i(x0 - 1, F + 3, z0 - 2), B.LOG)
			g.fill(Vector3i(x1 + 1, F, z0 - 2), Vector3i(x1 + 1, F + 3, z0 - 2), B.LOG)
			for z in range(z1 + 1, z1 + 3):
				for x: int in [x0 - 2, x0 - 1, x1 + 1, x1 + 2]:
					g.fill(Vector3i(x, F, z), Vector3i(x, F + 1, z), B.LEAVES)


## Ruined watchtower with a ramp to its battlements (north-west).
static func _tower(g: VoxelGrid) -> void:
	var x0: int = TOWER[0]
	var z0: int = TOWER[1]
	var x1: int = TOWER[2]
	var z1: int = TOWER[3]
	g.fill(Vector3i(x0, F - 1, z0), Vector3i(x1, F - 1, z1), B.COBBLE)
	g.walls(Vector3i(x0, F, z0), Vector3i(x1, F + 3, z1), B.MOSSY_BRICK)
	g.fill(Vector3i(x0, F + 3, z0), Vector3i(x1, F + 3, z1), B.STONE_BRICK)
	g.clear(Vector3i(x0 + 1, F + 3, z0 + 3), Vector3i(x0 + 3, F + 3, z0 + 6))
	g.ramp_run(Vector3i(x0 + 1, F, z0 + 6), G.RAMP_NZ, 4, 3, B.STONE_BRICK, B.MOSSY_BRICK)
	g.clear(Vector3i(x0 + 3, F, z1), Vector3i(x0 + 5, F + 2, z1))
	g.clear(Vector3i(x1, F, z0 + 3), Vector3i(x1, F + 2, z0 + 5))
	g.clear(Vector3i(x1, F, z0 + 6), Vector3i(x1, F + 1, z0 + 6))
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var edge := x == x0 or x == x1 or z == z0 or z == z1
			if edge and (x + z) % 2 == 0 and G.hash01(x, z, SEED + 5) > 0.2:
				g.set_block(x, F + 4, z, B.MOSSY_BRICK)
	g.set_block(x1 - 1, F + 2, z0 + 1, B.LAMP)
	g.set_block(x1, F + 4, z1, B.LAMP)


## Raised altar terrace south of the river with ramps on three sides.
static func _terrace(g: VoxelGrid) -> void:
	var x0: int = TERRACE[0]
	var z0: int = TERRACE[1]
	var x1: int = TERRACE[2]
	var z1: int = TERRACE[3]
	g.fill(Vector3i(x0, F, z0), Vector3i(x1, F, z1), B.MOSSY_BRICK)
	g.fill(Vector3i(x0, F + 1, z0), Vector3i(x1, F + 1, z1), B.STONE_BRICK)
	g.ramp_run(Vector3i(x0 - 2, F, z0 + 1), G.RAMP_PX, 2, 4, B.STONE_BRICK, B.MOSSY_BRICK)
	g.ramp_run(Vector3i(x1 + 2, F, z0 + 1), G.RAMP_NX, 2, 4, B.STONE_BRICK, B.MOSSY_BRICK)
	g.ramp_run(Vector3i(31, F, z0 - 2), G.RAMP_PZ, 2, 3, B.STONE_BRICK, B.MOSSY_BRICK)
	# Broken columns and a fallen lintel; low walls for cover.
	for p: Vector2i in [Vector2i(x0 + 1, z1 - 1), Vector2i(x1 - 1, z1 - 1), Vector2i(x0 + 1, z0 + 1)]:
		g.fill(Vector3i(p.x, F + 2, p.y), Vector3i(p.x, F + 4, p.y), B.CARVED)
	g.fill(Vector3i(x0 + 1, F + 5, z1 - 1), Vector3i(x0 + 5, F + 5, z1 - 1), B.STONE_BRICK)
	g.fill(Vector3i(x1 - 4, F + 2, z1 - 1), Vector3i(x1 - 2, F + 2, z1 - 1), B.STONE_BRICK)
	g.fill(Vector3i(x0 + 3, F + 2, z0), Vector3i(x0 + 4, F + 2, z0), B.MOSSY_BRICK)
	g.fill(Vector3i(x1 - 3, F + 2, z0), Vector3i(x1 - 2, F + 2, z0), B.MOSSY_BRICK)
	g.set_block(32, F + 2, z1, B.GOLD)
	g.set_block(32, F + 3, z1, B.LAMP)


## Two rows of broken columns in the north-east, some toppled.
static func _colonnade(g: VoxelGrid, rng: RandomNumberGenerator) -> void:
	for z in range(7, 18):
		for x in range(45, 58):
			if G.hash01(x, z, SEED + 6) > 0.35:
				g.set_block(x, F - 1, z, B.COBBLE)
	for z: int in [8, 16]:
		for x in range(46, 58, 3):
			var h := rng.randi_range(1, 4)
			g.fill(Vector3i(x, F, z), Vector3i(x, F + h - 1, z), B.CARVED)
			if h == 4:
				g.set_block(x, F + 4, z, B.STONE_BRICK)
	g.fill(Vector3i(47, F, 12), Vector3i(51, F, 12), B.STONE_BRICK)
	g.fill(Vector3i(55, F, 10), Vector3i(55, F, 13), B.STONE_BRICK)
	g.set_block(52, F, 11, B.LAMP)


## Crumbling wall along a straight line, height varying from one to three,
## with gaps.
static func _ruin_wall(g: VoxelGrid, hm: PackedInt32Array, a: Vector2i, b: Vector2i) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var p := a
	while true:
		var hv := G.hash01(p.x, p.y, SEED + 7)
		if hv > 0.15:
			var y := hm[p.y * g.size.x + p.x]
			var h := 1 + int(hv * 3.0)
			for k in h:
				g.set_block(p.x, y + k, p.y, B.MOSSY_BRICK if (k + p.x + p.y) % 3 != 0 else B.STONE_BRICK)
			if hv > 0.85:
				g.set_block(p.x, y + h, p.y, B.LEAVES)
		if p == b:
			break
		p += step


## Tall jungle trees with wide canopies, plus bushes for cover.
static func _jungle(g: VoxelGrid, hm: PackedInt32Array, reserved: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var sx := g.size.x
	var placed: Array[Vector2i] = []
	var tries := 0
	while placed.size() < 24 and tries < 800:
		tries += 1
		var x := rng.randi_range(3, sx - 4)
		var z := rng.randi_range(3, g.size.z - 4)
		if reserved[z * sx + x] != 0:
			continue
		var h := hm[z * sx + x]
		if not g.is_cube(x, h - 1, z) or not g.is_air(x, h, z):
			continue
		var far := true
		for p in placed:
			if absi(p.x - x) + absi(p.y - z) < 7:
				far = false
				break
		if not far:
			continue
		placed.append(Vector2i(x, z))
		_tree(g, x, h, z, rng)
		_mark(reserved, sx, x - 1, z - 1, x + 1, z + 1)
	tries = 0
	var bushes := 0
	while bushes < 34 and tries < 800:
		tries += 1
		var x := rng.randi_range(3, sx - 5)
		var z := rng.randi_range(3, g.size.z - 5)
		if reserved[z * sx + x] != 0:
			continue
		var h := hm[z * sx + x]
		if not g.is_cube(x, h - 1, z) or not g.is_air(x, h, z):
			continue
		bushes += 1
		var w := rng.randi_range(0, 1)
		for dz in 2:
			for dx in w + 1:
				if g.is_air(x + dx, h, z + dz) and g.is_cube(x + dx, h - 1, z + dz):
					g.set_block(x + dx, h, z + dz, B.LEAVES)
		if rng.randf() < 0.4:
			g.set_block(x, h + 1, z, B.LEAVES)
		_mark(reserved, sx, x - 1, z - 1, x + 2, z + 2)


static func _tree(g: VoxelGrid, x: int, y: int, z: int, rng: RandomNumberGenerator) -> void:
	var trunk := rng.randi_range(8, 11)
	var top := y + trunk
	for dy in range(-1, 2):
		var r := 3 if dy < 1 else 2
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r + 1:
					continue
				if g.is_air(x + dx, top + dy, z + dz):
					g.set_block(x + dx, top + dy, z + dz, B.LEAVES)
	# Hanging vines off the canopy rim.
	for k in 5:
		var a := rng.randf() * TAU
		var vx := x + roundi(cos(a) * 3.0)
		var vz := z + roundi(sin(a) * 3.0)
		for dy in rng.randi_range(1, 3):
			if g.is_air(vx, top - 2 - dy, vz):
				g.set_block(vx, top - 2 - dy, vz, B.LEAVES)
	if trunk >= 10:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if g.is_air(x + dx, y + 5, z + dz):
					g.set_block(x + dx, y + 5, z + dz, B.LEAVES)
	for dy in trunk:
		g.set_block(x, y + dy, z, B.LOG)
	# Buttress roots.
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if rng.randf() < 0.5 and g.is_air(x + d.x, y, z + d.y):
			g.set_block(x + d.x, y, z + d.y, B.LOG)
