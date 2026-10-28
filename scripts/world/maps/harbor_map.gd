extends RefCounted
## Harbor Docks: a concrete quay with water on the west and south, a dock
## basin with a moored trawler and a plank footbridge, two piers, a
## warehouse with a catwalk that leads out over a gantry crane walkway, and a
## container yard whose stacks are climbable by ramps. Falling into the
## water means death (kill_y).

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(64, 28, 64)
## Above the water surface (y = 2) and below the quay (y = 5).
const KILL_Y := 3.0
const SEED := 6606
const ATMOSPHERE := {
	"sky_top": Color("4f7fb3"), "sky_horizon": Color("d3e1e8"), "ground_bottom": Color("2f4a5a"),
	"sun_pitch": -36.0, "sun_yaw": -120.0, "sun_color": Color("fff0da"), "sun_energy": 1.3,
	"fog_color": Color("c3d4dd"), "fog_density": 0.005, "ambient": 0.85, "exposure": 1.0,
	"saturation": 1.0, "fog_sky": 0.25, "ambient_color": Color("bfcad1"),
}
const F := 5
const WATER_TOP := 2
const WAREHOUSE := [40, 4, 59, 19]
const COLORS := [B.CONTAINER_RED, B.CONTAINER_BLUE, B.CONTAINER_GREEN, B.CONTAINER_YELLOW]
## Container stacks: [x0, row, height]; row 0 spans z 27..33 (ramps from the
## north), row 1 spans z 39..45 (ramps from the south). Height 2 stacks get a
## double ramp to the upper container's roof.
const STACKS := [
	[23, 0, 1, true], [29, 0, 1, true], [35, 0, 2, true], [47, 0, 1, false], [53, 0, 1, true],
	[23, 1, 2, true], [35, 1, 1, true], [41, 1, 1, false], [47, 1, 2, true], [53, 1, 1, false],
]


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var sx := g.size.x
	var hm := Kit.heightmap(g, F)
	for z in g.size.z:
		for x in sx:
			if _is_water(x, z):
				hm[z * sx + x] = WATER_TOP
	g.apply_heightmap(hm, B.CONCRETE, B.STONE, B.STONE)
	for z in g.size.z:
		for x in sx:
			if _is_water(x, z):
				g.fill(Vector3i(x, 0, z), Vector3i(x, WATER_TOP - 1, z), B.WATER)
			elif _is_water(x - 1, z) or _is_water(x + 1, z) or _is_water(x, z - 1) or _is_water(x, z + 1):
				# Quay wall facing the water, with bollards along the edge.
				g.fill(Vector3i(x, 0, z), Vector3i(x, F - 2, z), B.STONE_BRICK)
				g.set_block(x, F - 1, z, B.HAZARD)
	Kit.paint_top(g, hm, 21, 23, 58, 49, B.GRAVEL)
	Kit.paint_top(g, hm, 40, 4, 59, 19, B.CONCRETE)

	_piers(g, hm)
	_boat(g, hm)
	_office(g)
	_warehouse(g, rng)
	_gantry(g)
	_containers(g)
	_props(g, rng)

	for s: Vector2i in [
		Vector2i(8, 16), Vector2i(20, 2), Vector2i(36, 2), Vector2i(62, 2), Vector2i(62, 30),
		Vector2i(57, 49), Vector2i(44, 59), Vector2i(15, 59), Vector2i(30, 49), Vector2i(8, 44),
		Vector2i(24, 19), Vector2i(50, 13), Vector2i(43, 36), Vector2i(17, 40), Vector2i(10, 30),
	]:
		Kit.spawn(g, hm, info, s.x, s.y)
	Kit.pickup(g, hm, info, "health", 49, 5, F + 4)
	Kit.pickup(g, hm, info, "ammo", 31, 8, F + 4)
	Kit.pickup(g, hm, info, "grenade", 36, 32, F + 6)
	Kit.pickup(g, hm, info, "health", 44, 61)
	Kit.pickup(g, hm, info, "ammo", 15, 61)
	Kit.pickup(g, hm, info, "grenade", 16, 32)
	Kit.pickup(g, hm, info, "health", 38, 36)
	Kit.pickup(g, hm, info, "ammo", 11, 14)
	Kit.pickup(g, hm, info, "ammo", 61, 40)


static func _is_water(x: int, z: int) -> bool:
	return x <= 5 or z >= 51 or (x <= 19 and z >= 22 and z <= 36)


## Two plank piers out over the south water and a footbridge across the dock
## basin, all flush with the quay and standing on log pilings.
static func _piers(g: VoxelGrid, hm: PackedInt32Array) -> void:
	for r: Array in [[13, 51, 17, 61], [42, 51, 46, 61], [9, 22, 11, 36]]:
		for z in range(r[1], r[3] + 1):
			for x in range(r[0], r[2] + 1):
				g.set_block(x, F - 1, z, B.PLANKS if (x + z) % 5 != 0 else B.DARK_PLANKS)
				hm[z * g.size.x + x] = F
		for z in range(r[1], r[3] + 1, 3):
			for x: int in [r[0], r[2]]:
				g.fill(Vector3i(x, 0, z), Vector3i(x, F - 2, z), B.LOG)
	# Pier furniture: bollards, crates and a lamp at each end.
	for p: Vector2i in [Vector2i(13, 61), Vector2i(17, 58), Vector2i(42, 58), Vector2i(46, 61)]:
		g.set_block(p.x, F, p.y, B.LOG)
	for p: Vector2i in [Vector2i(15, 55), Vector2i(43, 54)]:
		g.fill(Vector3i(p.x, F, p.y), Vector3i(p.x + 1, F, p.y), B.CRATE)
		g.set_block(p.x, F + 1, p.y, B.CRATE)
	for p: Vector2i in [Vector2i(17, 61), Vector2i(42, 61)]:
		g.fill(Vector3i(p.x, F, p.y), Vector3i(p.x, F + 2, p.y), B.METAL)
		g.set_block(p.x, F + 3, p.y, B.LAMP)


## Trawler moored in the basin, its deck flush with the quay and joined to it
## by a gangplank; a wheelhouse amidships gives cover.
static func _boat(g: VoxelGrid, hm: PackedInt32Array) -> void:
	for z in range(24, 35):
		var w := 2 if z >= 27 else (1 if z >= 25 else 0)
		for x in range(16 - w, 17 + w):
			g.fill(Vector3i(x, 1, z), Vector3i(x, F - 2, z), B.WHITE)
			g.set_block(x, 2, z, B.RED)
			g.set_block(x, F - 1, z, B.DARK_PLANKS)
			hm[z * g.size.x + x] = F
			var edge := x == 16 - w or x == 16 + w or z == 34
			if edge and z != 30 and z != 31:
				g.set_block(x, F, z, B.WHITE)
	g.fill(Vector3i(19, F - 1, 30), Vector3i(19, F - 1, 31), B.PLANKS)
	g.clear(Vector3i(18, F, 30), Vector3i(18, F, 31))
	g.clear(Vector3i(16, F, 34), Vector3i(16, F, 34))
	# Wheelhouse with windows and an open back.
	g.walls(Vector3i(15, F, 26), Vector3i(17, F + 2, 28), B.WHITE)
	g.fill(Vector3i(15, F + 1, 26), Vector3i(17, F + 1, 26), B.GLASS)
	g.clear(Vector3i(16, F, 28), Vector3i(16, F + 1, 28))
	g.fill(Vector3i(15, F + 3, 26), Vector3i(17, F + 3, 28), B.BLUE)
	g.fill(Vector3i(16, F + 4, 27), Vector3i(16, F + 6, 27), B.METAL)
	g.set_block(16, F + 7, 27, B.LAMP)
	g.fill(Vector3i(15, F, 32), Vector3i(16, F, 32), B.CRATE)


## Harbour master's office north of the basin with doors on three sides.
static func _office(g: VoxelGrid) -> void:
	var x0 := 8
	var z0 := 5
	var x1 := 15
	var z1 := 12
	g.walls(Vector3i(x0, F, z0), Vector3i(x1, F + 3, z1), B.WHITE)
	g.walls(Vector3i(x0, F, z0), Vector3i(x1, F, z1), B.BRICK)
	for p: Vector2i in [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1)]:
		g.fill(Vector3i(p.x, F, p.y), Vector3i(p.x, F + 3, p.y), B.BRICK)
	g.fill(Vector3i(x0 + 2, F + 1, z0), Vector3i(x0 + 5, F + 2, z0), B.GLASS)
	g.fill(Vector3i(x1, F + 1, z0 + 2), Vector3i(x1, F + 2, z0 + 3), B.GLASS)
	g.clear(Vector3i(x0 + 3, F, z1), Vector3i(x0 + 4, F + 2, z1))
	g.clear(Vector3i(x1, F, z0 + 5), Vector3i(x1, F + 2, z0 + 6))
	g.clear(Vector3i(x0, F, z0 + 3), Vector3i(x0, F + 2, z0 + 4))
	g.fill(Vector3i(x0 + 1, F, z0 + 1), Vector3i(x0 + 2, F, z0 + 1), B.DARK_PLANKS)
	g.set_block(x1 - 1, F, z1 - 1, B.CRATE)
	g.set_block(x0 + 4, F + 2, z0 + 1, B.LAMP)
	Kit.gable_roof(g, x0 - 1, z0 - 1, x1 + 1, z1 + 1, F + 4, true, B.ROOF, B.WHITE)


## Warehouse with a catwalk along the north and west walls, reached by an
## interior ramp, exiting west onto the crane walkway.
static func _warehouse(g: VoxelGrid, rng: RandomNumberGenerator) -> void:
	var x0: int = WAREHOUSE[0]
	var z0: int = WAREHOUSE[1]
	var x1: int = WAREHOUSE[2]
	var z1: int = WAREHOUSE[3]
	var top := F + 7
	g.walls(Vector3i(x0, F, z0), Vector3i(x1, top, z1), B.BRICK)
	for x in range(x0, x1 + 1, 5):
		g.fill(Vector3i(x, F, z0), Vector3i(x, top, z0), B.CONCRETE)
		g.fill(Vector3i(x, F, z1), Vector3i(x, top, z1), B.CONCRETE)
	g.fill(Vector3i(x0, top + 1, z0), Vector3i(x1, top + 1, z1), B.METAL)
	for x in range(x0 + 3, x1 - 2, 5):
		g.fill(Vector3i(x, top + 1, z0 + 3), Vector3i(x + 1, top + 1, z1 - 3), B.GLASS)
	for p: Vector2i in [Vector2i(45, 11), Vector2i(54, 11), Vector2i(50, 16)]:
		g.set_block(p.x, top + 1, p.y, B.LAMP)
	# High windows.
	for x in range(x0 + 2, x1 - 1, 5):
		g.fill(Vector3i(x, F + 5, z1), Vector3i(x + 1, F + 6, z1), B.GLASS)
	# Doors: a wide loading door south, west, east and north.
	g.clear(Vector3i(46, F, z1), Vector3i(50, F + 3, z1))
	g.fill(Vector3i(46, F + 4, z1), Vector3i(50, F + 4, z1), B.HAZARD)
	g.clear(Vector3i(x0, F, 14), Vector3i(x0, F + 2, 16))
	g.clear(Vector3i(x1, F, 15), Vector3i(x1, F + 2, 17))
	g.clear(Vector3i(52, F, z0), Vector3i(54, F + 2, z0))
	# Catwalks and the ramp up along the east wall.
	var c := F + 3
	g.fill(Vector3i(x0 + 1, c, z0 + 1), Vector3i(x1 - 1, c, z0 + 3), B.GRATE)
	g.fill(Vector3i(x0 + 1, c, z0 + 1), Vector3i(x0 + 3, c, z1 - 1), B.GRATE)
	g.fill(Vector3i(x1 - 2, c, z0 + 1), Vector3i(x1 - 1, c, z0 + 4), B.GRATE)
	g.ramp_run(Vector3i(x1 - 2, F, z0 + 8), G.RAMP_NZ, 4, 2, B.METAL, B.METAL)
	for p: Vector2i in [Vector2i(47, z0 + 1), Vector2i(53, z0 + 1), Vector2i(x0 + 1, 13)]:
		g.set_block(p.x, c + 1, p.y, B.METAL)
	# Catwalk exit onto the gantry walkway.
	g.clear(Vector3i(x0, c + 1, 7), Vector3i(x0, c + 3, 9))
	g.fill(Vector3i(x0, c, 7), Vector3i(x0, c, 9), B.GRATE)
	# Cover on the floor: pallets of crates and a parked container.
	for p: Vector2i in [Vector2i(46, 9), Vector2i(52, 13), Vector2i(48, 16), Vector2i(55, 8)]:
		g.fill(Vector3i(p.x, F, p.y), Vector3i(p.x + 1, F, p.y + 1), B.CRATE)
		if rng.randf() < 0.6:
			g.fill(Vector3i(p.x, F + 1, p.y), Vector3i(p.x, F + 1, p.y + 1), B.CRATE)
	g.fill(Vector3i(50, F, 7), Vector3i(52, F + 2, 10), B.CONTAINER_GREEN)


## Gantry crane over the walkway from the warehouse catwalk to a ramp down
## near the basin.
static func _gantry(g: VoxelGrid) -> void:
	var c := F + 3
	g.fill(Vector3i(24, c, 7), Vector3i(39, c, 9), B.GRATE)
	g.ramp_run(Vector3i(20, F, 7), G.RAMP_PX, 4, 3, B.METAL, B.METAL)
	for x: int in [26, 32, 38]:
		g.fill(Vector3i(x, F, 8), Vector3i(x, c - 1, 8), B.METAL)
	for p: Vector2i in [Vector2i(29, 7), Vector2i(35, 9)]:
		g.set_block(p.x, c + 1, p.y, B.METAL)
	g.set_block(32, c + 1, 9, B.HAZARD)
	var top := F + 12
	for lx: int in [27, 36]:
		for lz: int in [2, 13]:
			g.fill(Vector3i(lx, F, lz), Vector3i(lx + 1, top, lz + 1), B.YELLOW)
			for y: int in [F, F + 6]:
				g.fill(Vector3i(lx, y, lz), Vector3i(lx + 1, y, lz + 1), B.HAZARD)
		g.fill(Vector3i(lx, top, 2), Vector3i(lx + 1, top, 14), B.YELLOW)
	for lz: int in [2, 13]:
		g.fill(Vector3i(27, top, lz), Vector3i(37, top, lz + 1), B.YELLOW)
	# Boom reaching out over the basin, a cab and a hanging container.
	g.fill(Vector3i(14, top, 8), Vector3i(37, top, 8), B.METAL)
	g.fill(Vector3i(30, F + 9, 6), Vector3i(33, F + 11, 10), B.YELLOW)
	g.fill(Vector3i(29, F + 10, 6), Vector3i(29, F + 10, 10), B.GLASS)
	g.set_block(14, top - 1, 8, B.LAMP)
	g.fill(Vector3i(31, F + 9, 15), Vector3i(31, top - 1, 15), B.METAL)
	g.fill(Vector3i(30, F + 6, 12), Vector3i(32, F + 8, 18), B.CONTAINER_RED)


static func _containers(g: VoxelGrid) -> void:
	var i := 0
	for s: Array in STACKS:
		var x0: int = s[0]
		var row: int = s[1]
		var h: int = s[2]
		var col: int = COLORS[(i * 3 + row) % COLORS.size()]
		var col2: int = COLORS[(i * 3 + row + 1) % COLORS.size()]
		i += 1
		var z0 := 27 if row == 0 else 39
		var z1 := z0 + 6
		g.fill(Vector3i(x0, F, z0), Vector3i(x0 + 2, F + 2, z1), col)
		g.fill(Vector3i(x0, F, z0 if row == 1 else z1), Vector3i(x0 + 2, F + 2, z0 if row == 1 else z1), B.METAL)
		if not s[3]:
			continue
		if row == 0:
			g.ramp_run(Vector3i(x0, F, z0 - 3), G.RAMP_PZ, 3, 3, B.METAL, B.METAL)
		else:
			g.ramp_run(Vector3i(x0, F, z1 + 3), G.RAMP_NZ, 3, 3, B.METAL, B.METAL)
		if h == 2:
			if row == 0:
				g.fill(Vector3i(x0, F + 3, z0 + 3), Vector3i(x0 + 2, F + 5, z1), col2)
				g.ramp_run(Vector3i(x0, F + 3, z0), G.RAMP_PZ, 3, 3, B.METAL, col)
			else:
				g.fill(Vector3i(x0, F + 3, z0), Vector3i(x0 + 2, F + 5, z1 - 3), col2)
				g.ramp_run(Vector3i(x0, F + 3, z1), G.RAMP_NZ, 3, 3, B.METAL, col)
	# Plank bridges between neighbouring single stacks.
	for b: Vector2i in [Vector2i(26, 29), Vector2i(50, 29), Vector2i(38, 41)]:
		g.fill(Vector3i(b.x, F + 2, b.y), Vector3i(b.x + 2, F + 2, b.y + 2), B.PLANKS)


## Lamp posts, oil drums, crates and a forklift for cover on the quay.
static func _props(g: VoxelGrid, rng: RandomNumberGenerator) -> void:
	for p: Vector2i in [
		Vector2i(7, 20), Vector2i(21, 21), Vector2i(21, 49), Vector2i(39, 49), Vector2i(59, 24),
		Vector2i(7, 38), Vector2i(19, 13), Vector2i(61, 46), Vector2i(38, 22),
	]:
		g.fill(Vector3i(p.x, F, p.y), Vector3i(p.x, F + 2, p.y), B.METAL)
		g.set_block(p.x, F + 3, p.y, B.LAMP)
	for p: Vector2i in [Vector2i(12, 40), Vector2i(13, 41), Vector2i(29, 48), Vector2i(61, 34), Vector2i(60, 35)]:
		g.fill(Vector3i(p.x, F, p.y), Vector3i(p.x, F + 1, p.y), B.ORANGE if rng.randf() < 0.5 else B.RED)
	for p: Vector2i in [
		Vector2i(16, 45), Vector2i(34, 37), Vector2i(44, 47), Vector2i(61, 21), Vector2i(58, 38),
		Vector2i(24, 15), Vector2i(7, 46), Vector2i(44, 25), Vector2i(61, 10), Vector2i(17, 2),
	]:
		g.fill(Vector3i(p.x, F, p.y), Vector3i(p.x + 1, F, p.y), B.CRATE)
		if rng.randf() < 0.5:
			g.set_block(p.x, F + 1, p.y, B.CRATE)
	# Forklift.
	g.fill(Vector3i(42, F, 21), Vector3i(43, F, 23), B.YELLOW)
	g.fill(Vector3i(42, F + 1, 23), Vector3i(43, F + 1, 23), B.YELLOW)
	g.fill(Vector3i(42, F, 20), Vector3i(43, F, 20), B.METAL)
	# Container stack on the east alley.
	g.fill(Vector3i(61, F, 50), Vector3i(63, F + 2, 50), B.CONTAINER_BLUE)
