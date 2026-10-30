extends RefCounted
## Block HQ (Tactical mode): a three-storey office block, two teams' staging rooms at the west
## and east ends. Between them a lattice of rooms with doors and shooting windows, a central
## hallway, three stairwells per side (north and south switchbacks to the top floor, a centre
## flight on each storey) and a three-storey atrium in the middle with balconies. Alleys run
## round the outside for flanks. Everything east of the centre line mirrors the west half, so
## both teams get the same building.

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(112, 22, 64)
const KILL_Y := -10.0
const SEED := 7707
const ATMOSPHERE := {
	"sky_top": Color("4f6f9a"), "sky_horizon": Color("c8d2dc"), "ground_bottom": Color("4d4b47"),
	"sun_pitch": -48.0, "sun_yaw": 35.0, "sun_color": Color("fff0d8"), "sun_energy": 1.2,
	"fog_color": Color("b4bcc4"), "fog_density": 0.004, "ambient": 1.25, "exposure": 1.1,
	"saturation": 1.0, "fog_sky": 0.35, "ambient_color": Color("c9ccd2"),
}

## Walking height (grid y of the first air cell above the floor) of each storey.
const FLOORS: Array[int] = [1, 6, 11]
const FLOOR_NAMES: Array[String] = ["GROUND", "FLOOR 2", "FLOOR 3"]
## Team A's (west) staging room, inclusive grid box over two storeys; team B's mirrors it.
const SPAWN_ROOM: Array[Vector3i] = [Vector3i(5, 1, 7), Vector3i(14, 9, 56)]
## Openings out of team A's staging room, closed by the planning-phase barrier (inclusive boxes).
const BARRIERS: Array = [
	[Vector3i(15, 1, 9), Vector3i(15, 3, 11)],
	[Vector3i(15, 1, 30), Vector3i(15, 3, 33)],
	[Vector3i(15, 1, 52), Vector3i(15, 3, 54)],
	[Vector3i(15, 6, 16), Vector3i(15, 8, 18)],
	[Vector3i(15, 6, 45), Vector3i(15, 8, 47)],
	[Vector3i(9, 1, 6), Vector3i(11, 3, 6)],
	[Vector3i(9, 1, 57), Vector3i(11, 3, 57)],
]
## Squad routes as team A plays them: (x, storey, z) waypoints through the west half up to the
## centre. Tactical continues each one through the mirrored east half to the enemy staging room;
## team B plays the mirror image.
const ROUTES: Array = [
	[Vector3i(20, 0, 9), Vector3i(32, 0, 9), Vector3i(44, 0, 11), Vector3i(55, 0, 14)],
	[Vector3i(20, 0, 31), Vector3i(32, 0, 31), Vector3i(44, 0, 31), Vector3i(52, 0, 28)],
	[Vector3i(20, 0, 54), Vector3i(32, 0, 54), Vector3i(44, 0, 52), Vector3i(55, 0, 51)],
	[Vector3i(19, 1, 18), Vector3i(25, 1, 9), Vector3i(40, 1, 8), Vector3i(55, 1, 17)],
	[Vector3i(19, 1, 45), Vector3i(26, 1, 55), Vector3i(40, 1, 55), Vector3i(55, 1, 49)],
	[Vector3i(18, 0, 10), Vector3i(21, 2, 9), Vector3i(36, 2, 12), Vector3i(46, 2, 24), Vector3i(51, 2, 25)],
	[Vector3i(10, 0, 3), Vector3i(30, 0, 2), Vector3i(48, 0, 3), Vector3i(55, 0, 9)],
	[Vector3i(10, 0, 60), Vector3i(30, 0, 61), Vector3i(48, 0, 60), Vector3i(55, 0, 54)],
]

## Weapon spots in the west half as (x, storey, z); the east half mirrors them.
const WEAPON_SPOTS: Array[Vector3i] = [
	Vector3i(23, 0, 9), Vector3i(31, 0, 13), Vector3i(44, 0, 14), Vector3i(21, 0, 25), Vector3i(28, 0, 26),
	Vector3i(44, 0, 24), Vector3i(22, 0, 39), Vector3i(31, 0, 39), Vector3i(44, 0, 38), Vector3i(23, 0, 54),
	Vector3i(32, 0, 50), Vector3i(44, 0, 50), Vector3i(40, 0, 32),
	Vector3i(34, 1, 8), Vector3i(24, 1, 19), Vector3i(34, 1, 16), Vector3i(45, 1, 16), Vector3i(20, 1, 30),
	Vector3i(44, 1, 34), Vector3i(25, 1, 50), Vector3i(34, 1, 47), Vector3i(45, 1, 47), Vector3i(34, 1, 55),
	Vector3i(18, 2, 8), Vector3i(36, 2, 9), Vector3i(24, 2, 20), Vector3i(37, 2, 26), Vector3i(46, 2, 30),
	Vector3i(20, 2, 36), Vector3i(37, 2, 40), Vector3i(45, 2, 48), Vector3i(36, 2, 54),
	Vector3i(53, 0, 14), Vector3i(51, 0, 31), Vector3i(53, 0, 49), Vector3i(54, 1, 18), Vector3i(54, 2, 46),
]
const AMMO_SPOTS: Array[Vector3i] = [
	Vector3i(24, 0, 32), Vector3i(36, 0, 22), Vector3i(36, 0, 46), Vector3i(30, 1, 9), Vector3i(30, 1, 55),
	Vector3i(30, 1, 37), Vector3i(26, 2, 27), Vector3i(44, 2, 52), Vector3i(51, 1, 25), Vector3i(40, 0, 3),
]
const HEALTH_SPOTS: Array[Vector3i] = [
	Vector3i(33, 0, 31), Vector3i(20, 1, 26), Vector3i(40, 2, 36), Vector3i(53, 0, 25),
]
const GRENADE_SPOTS: Array[Vector3i] = [Vector3i(44, 0, 20), Vector3i(28, 2, 50)]

const WALL := B.WHITE


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var rng := RandomNumberGenerator.new()
	g.fill(Vector3i(0, 0, 0), Vector3i(SIZE.x - 1, 0, SIZE.z - 1), B.GRAVEL)
	g.fill(Vector3i(4, 0, 6), Vector3i(107, 0, 57), B.CONCRETE)
	g.walls(Vector3i(4, 1, 6), Vector3i(107, 15, 57), B.BRICK)
	g.fill(Vector3i(5, 5, 7), Vector3i(106, 5, 56), B.DARK_PLANKS)
	g.fill(Vector3i(5, 10, 7), Vector3i(106, 10, 56), B.PLANKS)
	g.fill(Vector3i(4, 15, 6), Vector3i(107, 15, 57), B.CONCRETE)
	for y: int in [5, 10, 15]:
		g.walls(Vector3i(4, y, 6), Vector3i(107, y, 57), B.STONE_BRICK)
	g.walls(Vector3i(4, 16, 6), Vector3i(107, 16, 57), B.STONE_BRICK)
	_centre(g)
	for m: int in [Kit.XF_NONE, Kit.XF_MIRROR_X]:
		# Same seed for both halves keeps the building symmetric.
		rng.seed = SEED
		_half(g, m, B.BLUE if m == Kit.XF_NONE else B.RED, rng)
	_alleys(g)

	var hm := Kit.heightmap(g, 1)
	# 25 spawns per team: team A's (west) first, then team B's.
	for m: int in [Kit.XF_NONE, Kit.XF_MIRROR_X]:
		var placed := 0
		for z: int in [9, 14, 19, 24, 34, 39, 44, 49, 54]:
			for x: int in [7, 10, 13]:
				if placed == 25 or (z == 24 and x == 7):
					continue
				var p := Kit.xf(g, m, x, 1, z)
				Kit.spawn(g, hm, info, p.x, p.z, 1)
				placed += 1
	for m: int in [Kit.XF_NONE, Kit.XF_MIRROR_X]:
		for s: Vector3i in WEAPON_SPOTS:
			_pickup(g, hm, info, m, "weapon", s)
		for s: Vector3i in AMMO_SPOTS:
			_pickup(g, hm, info, m, "ammo", s)
		for s: Vector3i in HEALTH_SPOTS:
			_pickup(g, hm, info, m, "health", s)
		for s: Vector3i in GRENADE_SPOTS:
			_pickup(g, hm, info, m, "grenade", s)


static func _pickup(g: VoxelGrid, hm: PackedInt32Array, info: MapInfo, m: int, kind: String, s: Vector3i) -> void:
	var p := Kit.xf(g, m, s.x, FLOORS[s.y], s.z)
	Kit.pickup(g, hm, info, kind, p.x, p.z, p.y)


## Wall along z at `x` from z0 to z1 for the storey walking at `y` (four blocks up to the slab),
## with door openings (3 high) and shooting windows (1 high at chest height), each Vector2i(z0, z1).
static func _wall_x(g: VoxelGrid, m: int, x: int, z0: int, z1: int, y: int, doors: Array = [], windows: Array = []) -> void:
	Kit.box(g, m, x, y, z0, x, y + 3, z1, WALL)
	for d: Vector2i in doors:
		Kit.box(g, m, x, y, d.x, x, y + 2, d.y, B.AIR)
	for w: Vector2i in windows:
		Kit.box(g, m, x, y + 1, w.x, x, y + 1, w.y, B.AIR)


static func _wall_z(g: VoxelGrid, m: int, z: int, x0: int, x1: int, y: int, doors: Array = [], windows: Array = []) -> void:
	Kit.box(g, m, x0, y, z, x1, y + 3, z, WALL)
	for d: Vector2i in doors:
		Kit.box(g, m, d.x, y, z, d.y, y + 2, z, B.AIR)
	for w: Vector2i in windows:
		Kit.box(g, m, w.x, y + 1, z, w.y, y + 1, z, B.AIR)


## One team's half: staging room, room lattice on three storeys, stairwells, cover.
static func _half(g: VoxelGrid, m: int, team: int, rng: RandomNumberGenerator) -> void:
	var l0 := FLOORS[0]
	var l1 := FLOORS[1]
	var l2 := FLOORS[2]
	# Staging room (ground and first floor), team-coloured floors.
	Kit.box(g, m, 5, 0, 7, 14, 0, 56, team)
	Kit.box(g, m, 5, 5, 7, 14, 5, 56, team)
	_wall_x(g, m, 15, 7, 56, l0, [Vector2i(9, 11), Vector2i(30, 33), Vector2i(52, 54)])
	_wall_x(g, m, 15, 7, 56, l1, [Vector2i(16, 18), Vector2i(45, 47)])
	_wall_x(g, m, 15, 7, 56, l2)
	Kit.box(g, m, 9, l0, 6, 11, l0 + 2, 6, B.AIR)
	Kit.box(g, m, 9, l0, 57, 11, l0 + 2, 57, B.AIR)
	for z in range(8, 56, 4):
		Kit.box(g, m, 5, l0, z, 5, l0 + 2, z + 1, B.METAL)
		Kit.box(g, m, 5, l1, z, 5, l1 + 1, z + 1, B.METAL)
	for z: int in [12, 31, 50]:
		Kit.box(g, m, 5, l0 + 3, z, 5, l0 + 3, z + 1, team)

	# Ground floor: north band | rooms | central hallway | rooms | south band.
	_wall_x(g, m, 26, 7, 28, l0, [Vector2i(12, 14), Vector2i(22, 24)], [Vector2i(16, 17)])
	_wall_x(g, m, 26, 35, 56, l0, [Vector2i(39, 41), Vector2i(49, 51)])
	_wall_x(g, m, 38, 7, 28, l0, [Vector2i(9, 11), Vector2i(25, 27)])
	_wall_x(g, m, 38, 35, 56, l0, [Vector2i(36, 38), Vector2i(52, 54)], [Vector2i(46, 48)])
	_wall_z(g, m, 19, 16, 48, l0, [Vector2i(20, 22), Vector2i(30, 31), Vector2i(42, 44)], [Vector2i(34, 36)])
	_wall_z(g, m, 44, 16, 48, l0, [Vector2i(20, 22), Vector2i(29, 31), Vector2i(44, 46)])
	_wall_z(g, m, 29, 16, 48, l0, [Vector2i(21, 23), Vector2i(29, 31), Vector2i(44, 46)], [Vector2i(34, 36)])
	_wall_z(g, m, 34, 16, 48, l0, [Vector2i(17, 19), Vector2i(30, 32), Vector2i(41, 43)], [Vector2i(35, 37)])
	_wall_x(g, m, 49, 7, 56, l0, [Vector2i(10, 12), Vector2i(30, 33), Vector2i(51, 53)], [Vector2i(16, 18), Vector2i(45, 47)])

	# First floor: north corridor | rooms | open office | rooms | south corridor.
	_wall_z(g, m, 11, 16, 48, l1, [Vector2i(24, 26), Vector2i(36, 38), Vector2i(45, 47)], [Vector2i(30, 32)])
	_wall_z(g, m, 22, 16, 48, l1, [Vector2i(24, 26), Vector2i(35, 37), Vector2i(44, 46)])
	_wall_x(g, m, 28, 12, 21, l1, [Vector2i(14, 16)], [Vector2i(19, 20)])
	_wall_x(g, m, 40, 12, 21, l1, [Vector2i(17, 19)])
	_wall_z(g, m, 41, 16, 48, l1, [Vector2i(23, 25), Vector2i(33, 35), Vector2i(44, 46)], [Vector2i(29, 31)])
	_wall_x(g, m, 28, 42, 52, l1, [Vector2i(47, 49)])
	_wall_x(g, m, 40, 42, 52, l1, [Vector2i(44, 46)], [Vector2i(49, 50)])
	_wall_z(g, m, 53, 16, 48, l1, [Vector2i(25, 27), Vector2i(36, 38), Vector2i(45, 47)], [Vector2i(31, 33)])
	_wall_x(g, m, 49, 7, 56, l1, [Vector2i(8, 10), Vector2i(16, 18), Vector2i(24, 25), Vector2i(38, 39), Vector2i(46, 48), Vector2i(54, 56)], [Vector2i(30, 33)])
	for p: Vector2i in [Vector2i(20, 27), Vector2i(44, 27), Vector2i(26, 36), Vector2i(38, 37)]:
		Kit.box(g, m, p.x, l1, p.y, p.x + 1, l1 + 3, p.y + 1, B.STONE_BRICK)

	# Top floor: open plan, a few walls to break the sightlines, cubicle partitions.
	_wall_x(g, m, 30, 7, 20, l2, [Vector2i(14, 16)], [Vector2i(9, 10)])
	_wall_x(g, m, 30, 43, 56, l2, [Vector2i(47, 49)], [Vector2i(53, 54)])
	_wall_x(g, m, 42, 18, 45, l2, [Vector2i(24, 26), Vector2i(37, 39)], [Vector2i(30, 33)])
	_wall_x(g, m, 49, 7, 56, l2, [Vector2i(9, 11), Vector2i(24, 25), Vector2i(38, 39), Vector2i(52, 54)], [Vector2i(17, 19), Vector2i(45, 47)])
	for p: Vector2i in [Vector2i(17, 24), Vector2i(17, 40), Vector2i(23, 32), Vector2i(35, 20), Vector2i(35, 44),
			Vector2i(44, 9), Vector2i(44, 54), Vector2i(25, 15), Vector2i(25, 48)]:
		Kit.box(g, m, p.x, l2, p.y, p.x + 3, l2 + 1, p.y, WALL)

	# Stairwells: north and south switchbacks to the top floor, a centre flight per storey.
	Kit.ramp(g, m, Vector3i(6, l0, 24), G.RAMP_PZ, 5, 3, B.METAL, B.METAL)
	Kit.ramp(g, m, Vector3i(17, l0, 12), G.RAMP_PZ, 5, 3, B.METAL, B.METAL)
	Kit.ramp(g, m, Vector3i(20, l1, 16), G.RAMP_NZ, 5, 3, B.METAL, B.METAL)
	Kit.ramp(g, m, Vector3i(17, l0, 51), G.RAMP_NZ, 5, 3, B.METAL, B.METAL)
	Kit.ramp(g, m, Vector3i(20, l1, 47), G.RAMP_PZ, 5, 3, B.METAL, B.METAL)
	Kit.ramp(g, m, Vector3i(32, l0, 21), G.RAMP_PZ, 5, 3, B.METAL, B.METAL)
	Kit.ramp(g, m, Vector3i(32, l1, 34), G.RAMP_NZ, 5, 3, B.METAL, B.METAL)

	# Cover: desks and crates in the ground-floor rooms and the hallway.
	for p: Vector2i in [Vector2i(30, 9), Vector2i(42, 16), Vector2i(20, 22), Vector2i(43, 26), Vector2i(29, 37),
			Vector2i(43, 41), Vector2i(29, 52), Vector2i(42, 54), Vector2i(27, 31), Vector2i(36, 32)]:
		Kit.box(g, m, p.x, l0, p.y, p.x + 1, l0, p.y, B.CRATE)
		if rng.randf() < 0.5:
			Kit.put(g, m, p.x, l0 + 1, p.y, B.CRATE)
	for p: Vector2i in [Vector2i(33, 14), Vector2i(45, 13), Vector2i(33, 48), Vector2i(44, 50), Vector2i(24, 14)]:
		Kit.box(g, m, p.x, l1, p.y, p.x + 2, l1, p.y, B.DARK_PLANKS)
	# Ceiling lights.
	for p: Vector2i in [Vector2i(21, 10), Vector2i(33, 10), Vector2i(44, 10), Vector2i(21, 24), Vector2i(44, 24),
			Vector2i(22, 31), Vector2i(36, 31), Vector2i(21, 39), Vector2i(44, 39), Vector2i(21, 53), Vector2i(33, 53),
			Vector2i(44, 53), Vector2i(10, 15), Vector2i(10, 31), Vector2i(10, 48)]:
		for y: int in [5, 10, 15]:
			Kit.put(g, m, p.x, y, p.y, B.LAMP)
	# Windows in the facade: open on the first floor (overlooking the alleys), glass above.
	for x in range(20, 48, 7):
		for z: int in [6, 57]:
			Kit.box(g, m, x, l1 + 1, z, x + 1, l1 + 1, z, B.AIR)
			Kit.box(g, m, x, l2 + 1, z, x + 2, l2 + 2, z, B.GLASS)
			Kit.box(g, m, x + 3, l0 + 1, z, x + 4, l0 + 2, z, B.GLASS)


## The shared middle column (x 50-61, symmetric by construction): a server room north, a
## three-storey atrium with balconies in the centre and a cafeteria south.
static func _centre(g: VoxelGrid) -> void:
	for y: int in FLOORS:
		g.fill(Vector3i(50, y, 23), Vector3i(61, y + 3, 23), WALL)
		g.fill(Vector3i(50, y, 40), Vector3i(61, y + 3, 40), WALL)
	g.clear(Vector3i(54, 1, 23), Vector3i(57, 3, 23))
	g.clear(Vector3i(54, 1, 40), Vector3i(57, 3, 40))
	for y: int in [FLOORS[1], FLOORS[2]]:
		g.clear(Vector3i(55, y, 23), Vector3i(56, y + 2, 23))
		g.clear(Vector3i(55, y, 40), Vector3i(56, y + 2, 40))
	# Atrium void with a railing round each balcony, under a glass roof.
	for y: int in [5, 10]:
		g.clear(Vector3i(53, y, 27), Vector3i(58, y, 36))
	for y: int in [FLOORS[1], FLOORS[2]]:
		g.fill(Vector3i(52, y, 26), Vector3i(59, y, 26), B.METAL)
		g.fill(Vector3i(52, y, 37), Vector3i(59, y, 37), B.METAL)
		g.fill(Vector3i(52, y, 27), Vector3i(52, y, 36), B.METAL)
		g.fill(Vector3i(59, y, 27), Vector3i(59, y, 36), B.METAL)
	g.fill(Vector3i(53, 15, 27), Vector3i(58, 15, 36), B.GLASS)
	# Fountain and planters on the atrium floor.
	g.walls(Vector3i(54, 1, 30), Vector3i(57, 1, 33), B.STONE_BRICK)
	g.fill(Vector3i(55, 1, 31), Vector3i(56, 2, 32), B.LEAVES)
	for p: Vector2i in [Vector2i(51, 25), Vector2i(59, 25), Vector2i(51, 37), Vector2i(59, 37)]:
		g.fill(Vector3i(p.x, 1, p.y), Vector3i(p.x + 1, 1, p.y + 1), B.LEAVES)
	# Server racks (north) and cafeteria tables (south) on the ground floor.
	for z: int in [11, 17]:
		g.fill(Vector3i(52, 1, z), Vector3i(54, 3, z), B.METAL)
		g.fill(Vector3i(57, 1, z), Vector3i(59, 3, z), B.METAL)
	for p: Vector2i in [Vector2i(52, 45), Vector2i(58, 45), Vector2i(52, 52), Vector2i(58, 52), Vector2i(55, 48)]:
		g.fill(Vector3i(p.x, 1, p.y), Vector3i(p.x + 1, 1, p.y + 1), B.DARK_PLANKS)
	# Doors from the alleys into the centre blocks.
	g.clear(Vector3i(54, 1, 6), Vector3i(57, 3, 6))
	g.clear(Vector3i(54, 1, 57), Vector3i(57, 3, 57))
	# Upper floors: a meeting table and a reception desk for cover.
	g.fill(Vector3i(54, 6, 12), Vector3i(57, 6, 14), B.DARK_PLANKS)
	g.fill(Vector3i(53, 6, 50), Vector3i(58, 6, 50), B.DARK_PLANKS)
	g.fill(Vector3i(53, 11, 14), Vector3i(58, 12, 14), WALL)
	g.fill(Vector3i(53, 11, 49), Vector3i(58, 12, 49), WALL)
	for p: Vector2i in [Vector2i(55, 12), Vector2i(56, 18), Vector2i(55, 46), Vector2i(56, 52)]:
		for y: int in [5, 10, 15]:
			g.set_block(p.x, y, p.y, B.LAMP)


## Alleys round the building: dumpsters and crates for cover on the flanking routes.
static func _alleys(g: VoxelGrid) -> void:
	for m: int in [Kit.XF_NONE, Kit.XF_MIRROR_X]:
		for z: int in [1, 60]:
			Kit.box(g, m, 22, 1, z, 24, 2, z + 2, B.CONTAINER_GREEN)
			Kit.box(g, m, 40, 1, z + 1, 41, 1, z + 2, B.CRATE)
			Kit.put(g, m, 40, 2, z + 1, B.CRATE)
		for z: int in [2, 61]:
			Kit.box(g, m, 33, 1, z, 34, 1, z, B.CONCRETE)
			Kit.box(g, m, 16, 1, z, 17, 1, z, B.CONCRETE)
