extends RefCounted
## City Rooftops: seven high-rise roofs at different heights around a central
## tower, linked by steel skybridges and plank walkways (two of them via
## scaffold platforms over the street corners). AC units, water tanks, stair
## huts and billboards give cover. The street far below means death (kill_y).

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(64, 44, 64)
## Well above the street (y = 1) and below the lowest roof (y = 20).
const KILL_Y := 8.0
const SEED := 8808
const ATMOSPHERE := {
	"sky_top": Color("4870a8"), "sky_horizon": Color("e2cfb4"), "ground_bottom": Color("4a4a50"),
	"sun_pitch": -34.0, "sun_yaw": 110.0, "sun_color": Color("ffe3bf"), "sun_energy": 1.35,
	"fog_color": Color("c9c3b9"), "fog_density": 0.006, "ambient": 0.8, "exposure": 1.0,
	"saturation": 1.0, "fog_sky": 0.25, "ambient_color": Color("c3bfb7"),
}
const STREET := 1
## Buildings: [x0, z0, x1, z1, roof height, wall block].
const C := [24, 24, 39, 39, 24, B.CONCRETE]
const N := [22, 3, 41, 14, 20, B.BRICK]
const S := [22, 49, 41, 60, 26, B.STONE_BRICK]
const W := [3, 22, 14, 41, 22, B.BRICK]
const E := [49, 22, 60, 41, 28, B.CONCRETE]
const NW := [3, 3, 16, 16, 27, B.STONE_BRICK]
const SE := [47, 47, 60, 60, 31, B.CONCRETE]
## Scaffold platforms over the empty north-east and south-west corners.
const PLATFORMS := [[50, 6, 56, 12, 24], [6, 50, 12, 56, 24]]
## Links: [low end, high end, low y, high y, ramp start (cells from the low
## end), steel]. Each runs along one axis and is three cells wide toward +X
## (north-south links) or +Z (east-west links).
const LINKS := [
	[Vector2i(30, 12), Vector2i(30, 26), 20, 24, 5, true],
	[Vector2i(31, 37), Vector2i(31, 51), 24, 26, 6, true],
	[Vector2i(12, 29), Vector2i(26, 29), 22, 24, 6, true],
	[Vector2i(37, 33), Vector2i(51, 33), 24, 28, 5, true],
	[Vector2i(24, 8), Vector2i(14, 8), 20, 27, 1, false],
	[Vector2i(7, 24), Vector2i(7, 14), 22, 27, 3, false],
	[Vector2i(53, 39), Vector2i(53, 49), 28, 31, 4, false],
	[Vector2i(39, 53), Vector2i(49, 53), 26, 31, 3, false],
	[Vector2i(39, 8), Vector2i(52, 8), 20, 24, 5, false],
	[Vector2i(52, 10), Vector2i(52, 24), 24, 28, 5, false],
	[Vector2i(8, 39), Vector2i(8, 52), 22, 24, 5, false],
	[Vector2i(10, 52), Vector2i(24, 52), 24, 26, 6, false],
]


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var hm := Kit.heightmap(g, STREET)
	_street(g, rng)
	for b: Array in [C, N, S, W, E, NW, SE]:
		_building(g, b)
		Kit.rect(g, hm, b[0], b[1], b[2], b[3], b[4])
	for p: Array in PLATFORMS:
		_platform(g, p)
		Kit.rect(g, hm, p[0], p[1], p[2], p[3], p[4])

	_props_c(g)
	_props_n(g)
	_props_s(g, rng)
	_props_w(g)
	_props_e(g)
	_props_nw(g)
	_props_se(g)
	for l: Array in LINKS:
		_link(g, l)

	for s: Vector2i in [
		Vector2i(27, 30), Vector2i(37, 25), Vector2i(26, 8), Vector2i(36, 6), Vector2i(25, 51),
		Vector2i(37, 58), Vector2i(6, 30), Vector2i(11, 37), Vector2i(55, 30), Vector2i(57, 38),
		Vector2i(6, 6), Vector2i(13, 12), Vector2i(50, 50), Vector2i(57, 57), Vector2i(54, 7),
		Vector2i(8, 54),
	]:
		Kit.spawn(g, hm, info, s.x, s.y)
	Kit.pickup(g, hm, info, "health", 31, 31)
	Kit.pickup(g, hm, info, "ammo", 33, 9)
	Kit.pickup(g, hm, info, "ammo", 32, 56)
	Kit.pickup(g, hm, info, "grenade", 52, 31)
	Kit.pickup(g, hm, info, "grenade", 9, 26)
	Kit.pickup(g, hm, info, "health", 9, 9)
	Kit.pickup(g, hm, info, "health", 54, 54)
	Kit.pickup(g, hm, info, "ammo", 55, 11)
	Kit.pickup(g, hm, info, "ammo", 10, 55)


## Asphalt with lane dashes, kerbs, parked cars and street lamps.
static func _street(g: VoxelGrid, rng: RandomNumberGenerator) -> void:
	g.fill(Vector3i(0, 0, 0), Vector3i(g.size.x - 1, 0, g.size.z - 1), B.GRAVEL)
	for k in range(0, g.size.x, 4):
		for p: Vector2i in [Vector2i(k, 19), Vector2i(k, 44), Vector2i(19, k), Vector2i(44, k)]:
			g.set_block(p.x, 0, p.y, B.YELLOW)
	for p: Vector2i in [Vector2i(20, 30), Vector2i(43, 10), Vector2i(17, 52), Vector2i(45, 33), Vector2i(30, 45)]:
		var along := Vector3i(1, 0, 0) if rng.randf() < 0.5 else Vector3i(0, 0, 1)
		var col: int = [B.RED, B.BLUE, B.WHITE, B.YELLOW][rng.randi_range(0, 3)]
		var base := Vector3i(p.x, 1, p.y)
		g.fill(base, base + along * 3 + Vector3i(1, 0, 1) - along, col)
		g.fill(base + along + Vector3i(0, 1, 0), base + along * 2 + Vector3i(1, 1, 1) - along, B.GLASS)
	for p: Vector2i in [Vector2i(18, 18), Vector2i(45, 18), Vector2i(18, 45), Vector2i(45, 45), Vector2i(31, 18), Vector2i(31, 46)]:
		g.fill(Vector3i(p.x, 1, p.y), Vector3i(p.x, 4, p.y), B.METAL)
		g.set_block(p.x, 5, p.y, B.LAMP)


## Solid tower with a sidewalk, window rows (lit or dark rooms behind the
## glass), a cornice and a broken parapet around the roof.
static func _building(g: VoxelGrid, b: Array) -> void:
	var x0: int = b[0]
	var z0: int = b[1]
	var x1: int = b[2]
	var z1: int = b[3]
	var roof: int = b[4]
	var wall: int = b[5]
	g.fill(Vector3i(x0 - 1, 1, z0 - 1), Vector3i(x1 + 1, 1, z1 + 1), B.CONCRETE)
	g.fill(Vector3i(x0, 1, z0), Vector3i(x1, roof - 1, z1), wall)
	var trim := B.STONE_BRICK if wall != B.STONE_BRICK else B.CONCRETE
	g.walls(Vector3i(x0, roof - 1, z0), Vector3i(x1, roof - 1, z1), trim)
	g.walls(Vector3i(x0, 2, z0), Vector3i(x1, 2, z1), trim)
	for y in range(4, roof - 2):
		if y % 4 != 0 and y % 4 != 1:
			continue
		for x in range(x0 + 1, x1):
			if x % 3 != 0:
				_window(g, x, y, z0, Vector3i(0, 0, 1))
				_window(g, x, y, z1, Vector3i(0, 0, -1))
		for z in range(z0 + 1, z1):
			if z % 3 != 0:
				_window(g, x0, y, z, Vector3i(1, 0, 0))
				_window(g, x1, y, z, Vector3i(-1, 0, 0))
	# Roof surface with a gravel membrane and a parapet with gaps.
	g.fill(Vector3i(x0 + 1, roof - 1, z0 + 1), Vector3i(x1 - 1, roof - 1, z1 - 1), B.GRAVEL)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var edge := x == x0 or x == x1 or z == z0 or z == z1
			if edge and G.hash01(x / 3, z / 3, SEED + roof) > 0.3:
				g.set_block(x, roof, z, trim)


static func _window(g: VoxelGrid, x: int, y: int, z: int, inward: Vector3i) -> void:
	g.set_block(x, y, z, B.GLASS)
	var lit := G.hash01(x * 3 + y, z * 5 + y, SEED + 1) > 0.78
	g.set_block(x + inward.x, y, z + inward.z, B.LAMP if lit else B.DARK_PLANKS)


## Steel deck on lattice legs standing in the street.
static func _platform(g: VoxelGrid, p: Array) -> void:
	var x0: int = p[0]
	var z0: int = p[1]
	var x1: int = p[2]
	var z1: int = p[3]
	var y: int = p[4]
	g.fill(Vector3i(x0, y - 1, z0), Vector3i(x1, y - 1, z1), B.GRATE)
	g.walls(Vector3i(x0, y - 1, z0), Vector3i(x1, y - 1, z1), B.METAL)
	for c: Vector2i in [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1)]:
		g.fill(Vector3i(c.x, 1, c.y), Vector3i(c.x, y - 2, c.y), B.METAL)
	for yy in range(4, y - 1, 5):
		g.walls(Vector3i(x0, yy, z0), Vector3i(x1, yy, z1), B.HAZARD)
	g.fill(Vector3i(x0 + 1, y, z0 + 1), Vector3i(x0 + 2, y, z0 + 1), B.CRATE)
	g.set_block(x0 + 1, y + 1, z0 + 1, B.CRATE)
	g.set_block(x1, y, z1, B.LAMP)


## Walkway from `l[0]` (low roof) to `l[1]` (high roof): flat at the low
## height, then a ramp flight from `l[4]` cells in, then flat at the high
## height. Steel links get grate decks and metal beams, others planks.
static func _link(g: VoxelGrid, l: Array) -> void:
	var a: Vector2i = l[0]
	var b: Vector2i = l[1]
	var low: int = l[2]
	var high: int = l[3]
	var ramp_at: int = l[4]
	var steel: bool = l[5]
	var deck := B.GRATE if steel else B.PLANKS
	var beam := B.METAL if steel else B.DARK_PLANKS
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var along_x := step.x != 0
	var side := Vector2i(0, 1) if along_x else Vector2i(1, 0)
	var facing: int
	if along_x:
		facing = G.RAMP_PX if step.x > 0 else G.RAMP_NX
	else:
		facing = G.RAMP_PZ if step.y > 0 else G.RAMP_NZ
	var n := high - low
	var len := absi(b.x - a.x) + absi(b.y - a.y)
	for k in len + 1:
		var j := k - ramp_at
		for w in 3:
			var p := a + step * k + side * w
			if j >= 0 and j < n:
				var y := low + j
				g.set_ramp(p.x, y, p.y, facing, deck)
				if g.is_air(p.x, y - 1, p.y):
					g.set_block(p.x, y - 1, p.y, beam)
				g.clear(Vector3i(p.x, y + 1, p.y), Vector3i(p.x, y + 3, p.y))
			else:
				var y := low if j < 0 else high
				g.set_block(p.x, y - 1, p.y, deck)
				g.clear(Vector3i(p.x, y, p.y), Vector3i(p.x, y + 2, p.y))
				if k % 3 == 1 and w != 1 and g.is_air(p.x, y - 2, p.y):
					g.set_block(p.x, y - 2, p.y, beam)
	# Lamps on the side rails of steel links, mid-span.
	if steel:
		var mid := a + step * (len / 2)
		var y := low if len / 2 < ramp_at else high
		for p: Vector2i in [mid - side, mid + side * 3]:
			if g.is_air(p.x, y - 1, p.y):
				g.set_block(p.x, y - 1, p.y, B.LAMP)


static func _ac_unit(g: VoxelGrid, x: int, y: int, z: int, w: int, d: int, h: int) -> void:
	g.fill(Vector3i(x, y, z), Vector3i(x + w - 1, y + h - 1, z + d - 1), B.METAL)
	g.fill(Vector3i(x, y + h - 1, z), Vector3i(x + w - 1, y + h - 1, z + d - 1), B.GRATE)


## Round water tank on four legs; its legs and underside are cover.
static func _water_tower(g: VoxelGrid, cx: int, y: int, cz: int) -> void:
	for d: Vector2i in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
		g.fill(Vector3i(cx + d.x, y, cz + d.y), Vector3i(cx + d.x, y + 3, cz + d.y), B.LOG)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dz * dz > 5:
				continue
			g.fill(Vector3i(cx + dx, y + 4, cz + dz), Vector3i(cx + dx, y + 8, cz + dz), B.PLANKS if (dx + 2) % 2 == 0 else B.DARK_PLANKS)
			g.set_block(cx + dx, y + 6, cz + dz, B.METAL)
	Kit.gable_roof(g, cx - 2, cz - 2, cx + 2, cz + 2, y + 9, true, B.ROOF, B.DARK_PLANKS)


## Solid stairwell block, three high, with a lamp over its corner.
static func _hut(g: VoxelGrid, x0: int, z0: int, x1: int, z1: int, y: int, wall: int) -> void:
	g.fill(Vector3i(x0, y, z0), Vector3i(x1, y + 2, z1), wall)
	g.fill(Vector3i(x0, y + 2, z0), Vector3i(x1, y + 2, z1), B.STONE_BRICK)
	g.set_block(x0, y + 1, z0, B.LAMP)


static func _props_c(g: VoxelGrid) -> void:
	var y: int = C[4]
	_hut(g, 26, 34, 29, 37, y, B.WHITE)
	g.ramp_run(Vector3i(32, y, 34), G.RAMP_NX, 3, 3, B.METAL, B.METAL)
	_water_tower(g, 35, y, 29)
	_ac_unit(g, 26, y, 26, 2, 2, 1)
	_ac_unit(g, 36, y, 36, 2, 2, 2)
	g.fill(Vector3i(27, y - 1, 30), Vector3i(28, y - 1, 32), B.GLASS)


static func _props_n(g: VoxelGrid) -> void:
	var y: int = N[4]
	for z: int in [5, 12]:
		for x0: int in [25, 34]:
			g.fill(Vector3i(x0, y, z), Vector3i(x0 + 3, y, z), B.BLUE)
	g.fill(Vector3i(40, y, 4), Vector3i(40, y + 9, 4), B.METAL)
	g.set_block(40, y + 10, 4, B.LAMP)
	_ac_unit(g, 36, y, 8, 2, 3, 2)


static func _props_s(g: VoxelGrid, rng: RandomNumberGenerator) -> void:
	var y: int = S[4]
	# Rooftop garden: lawn, planters and a greenhouse.
	g.fill(Vector3i(25, y - 1, 55), Vector3i(38, y - 1, 59), B.GRASS)
	for p: Vector2i in [Vector2i(26, 51), Vector2i(36, 51), Vector2i(28, 54), Vector2i(36, 55)]:
		g.fill(Vector3i(p.x, y, p.y), Vector3i(p.x + 2, y, p.y), B.DARK_PLANKS)
		for k in 3:
			if rng.randf() < 0.7:
				g.set_block(p.x + k, y + 1, p.y, B.LEAVES)
	g.walls(Vector3i(31, y, 57), Vector3i(35, y + 2, 59), B.GLASS)
	g.fill(Vector3i(31, y + 3, 57), Vector3i(35, y + 3, 59), B.GLASS)
	g.clear(Vector3i(33, y, 57), Vector3i(33, y + 1, 57))
	g.set_block(32, y, 58, B.LEAVES)
	g.set_block(34, y, 58, B.LEAVES)
	_ac_unit(g, 23, y, 57, 2, 2, 2)


static func _props_w(g: VoxelGrid) -> void:
	var y: int = W[4]
	_ac_unit(g, 5, y, 33, 2, 2, 2)
	_ac_unit(g, 10, y, 25, 2, 2, 1)
	_ac_unit(g, 11, y, 34, 2, 3, 1)
	# Billboard on the west edge.
	for z: int in [26, 36]:
		g.fill(Vector3i(3, y, z), Vector3i(3, y + 6, z), B.METAL)
	g.fill(Vector3i(3, y + 3, 26), Vector3i(3, y + 7, 36), B.RED)
	g.fill(Vector3i(3, y + 4, 28), Vector3i(3, y + 6, 34), B.WHITE)
	g.set_block(4, y + 7, 31, B.LAMP)


static func _props_e(g: VoxelGrid) -> void:
	var y: int = E[4]
	_ac_unit(g, 51, y, 27, 3, 2, 2)
	_ac_unit(g, 56, y, 34, 2, 2, 1)
	_ac_unit(g, 51, y, 37, 2, 2, 1)
	for z: int in [24, 39]:
		g.fill(Vector3i(60, y, z), Vector3i(60, y + 6, z), B.METAL)
	g.fill(Vector3i(60, y + 3, 24), Vector3i(60, y + 7, 39), B.YELLOW)
	g.fill(Vector3i(60, y + 4, 27), Vector3i(60, y + 6, 36), B.BLUE)


static func _props_nw(g: VoxelGrid) -> void:
	var y: int = NW[4]
	_hut(g, 5, 10, 8, 13, y, B.BRICK)
	g.ramp_run(Vector3i(11, y, 10), G.RAMP_NX, 3, 3, B.METAL, B.METAL)
	g.fill(Vector3i(5, y, 4), Vector3i(5, y + 12, 4), B.METAL)
	for k in range(y + 4, y + 13, 4):
		g.fill(Vector3i(4, k, 4), Vector3i(6, k, 4), B.METAL)
	g.set_block(5, y + 13, 4, B.LAMP)
	_ac_unit(g, 12, y, 5, 2, 2, 2)


static func _props_se(g: VoxelGrid) -> void:
	var y: int = SE[4]
	# Helipad.
	g.fill(Vector3i(50, y - 1, 50), Vector3i(57, y - 1, 57), B.HAZARD)
	g.fill(Vector3i(51, y - 1, 51), Vector3i(56, y - 1, 56), B.CONCRETE)
	g.fill(Vector3i(52, y - 1, 52), Vector3i(52, y - 1, 55), B.WHITE)
	g.fill(Vector3i(55, y - 1, 52), Vector3i(55, y - 1, 55), B.WHITE)
	g.fill(Vector3i(53, y - 1, 53), Vector3i(54, y - 1, 54), B.WHITE)
	for p: Vector2i in [Vector2i(49, 49), Vector2i(58, 49), Vector2i(49, 58), Vector2i(58, 58)]:
		g.set_block(p.x, y, p.y, B.LAMP)
	_ac_unit(g, 58, y, 52, 2, 3, 2)
