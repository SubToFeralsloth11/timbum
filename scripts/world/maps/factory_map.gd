extends RefCounted
## Factory: two mirrored conveyor halls with catwalks, joined by an elevated
## grate bridge over the yard; a tank farm with a smokestack and a container
## yard with tight aisles. Enclosed by a brick perimeter wall.

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(64, 26, 64)
const KILL_Y := -10.0
const SEED := 3303
const ATMOSPHERE := {
	"sky_top": Color("5c7391"), "sky_horizon": Color("c9c2b4"), "ground_bottom": Color("57534c"),
	"sun_pitch": -42.0, "sun_yaw": 60.0, "sun_color": Color("ffdcb0"), "sun_energy": 1.25,
	"fog_color": Color("a9a397"), "fog_density": 0.007, "ambient": 0.8, "exposure": 1.05,
	"saturation": 0.95, "fog_sky": 0.45, "ambient_color": Color("b7b2a8"),
}
const F := 3


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var hm := Kit.heightmap(g, F)
	g.apply_heightmap(hm, B.CONCRETE, B.STONE, B.STONE)
	# Painted floor zones.
	Kit.paint_top(g, hm, 22, 2, 41, 61, B.GRAVEL)
	Kit.paint_top(g, hm, 29, 2, 34, 61, B.CONCRETE)
	g.walls(Vector3i(0, F, 0), Vector3i(63, F + 7, 63), B.BRICK)
	g.walls(Vector3i(1, F, 1), Vector3i(62, F + 7, 62), B.BRICK)
	g.walls(Vector3i(0, F + 7, 0), Vector3i(63, F + 7, 63), B.METAL)
	g.walls(Vector3i(0, F, 0), Vector3i(63, F, 63), B.HAZARD)
	for k in range(6, 60, 8):
		for p: Vector3i in [Vector3i(k, F + 5, 1), Vector3i(k, F + 5, 62), Vector3i(1, F + 5, k), Vector3i(62, F + 5, k)]:
			g.set_block(p.x, p.y, p.z, B.LAMP)

	_hall(g, Kit.XF_NONE, rng)
	_hall(g, Kit.XF_ROT180, rng)
	_bridge(g)
	_tanks(g)
	_containers(g)

	for s: Vector2i in [
		Vector2i(6, 17), Vector2i(12, 20), Vector2i(17, 6), Vector2i(57, 46), Vector2i(51, 43),
		Vector2i(46, 57), Vector2i(26, 8), Vector2i(37, 22), Vector2i(26, 41), Vector2i(37, 56),
		Vector2i(8, 59), Vector2i(14, 46), Vector2i(45, 24), Vector2i(59, 13), Vector2i(31, 4),
	]:
		Kit.spawn(g, hm, info, s.x, s.y)
	Kit.pickup(g, hm, info, "health", 31, 33, F + 4)
	Kit.pickup(g, hm, info, "ammo", 11, 3, F + 4)
	Kit.pickup(g, hm, info, "ammo", 52, 60, F + 4)
	Kit.pickup(g, hm, info, "grenade", 20, 46)
	Kit.pickup(g, hm, info, "health", 51, 17)
	Kit.pickup(g, hm, info, "ammo", 24, 26)
	Kit.pickup(g, hm, info, "grenade", 39, 38)
	Kit.pickup(g, hm, info, "health", 17, 52, F + 3)


## Conveyor hall in the north-west corner (hall B is the same hall rotated
## 180 degrees into the south-east).
static func _hall(g: VoxelGrid, m: int, rng: RandomNumberGenerator) -> void:
	var top := F + 8
	Kit.box(g, m, 2, F, 2, 21, top, 2, B.BRICK)
	Kit.box(g, m, 2, F, 28, 21, top, 28, B.BRICK)
	Kit.box(g, m, 2, F, 2, 2, top, 28, B.BRICK)
	Kit.box(g, m, 21, F, 2, 21, top, 28, B.BRICK)
	Kit.box(g, m, 21, F, 2, 21, F, 28, B.CONCRETE)
	Kit.box(g, m, 2, F, 28, 21, F, 28, B.CONCRETE)
	# Windows high on the outer faces.
	for k in range(4, 20, 4):
		Kit.box(g, m, k, F + 5, 28, k + 1, F + 6, 28, B.GLASS)
	for k in range(4, 27, 4):
		if k < 13 or k > 17:
			Kit.box(g, m, 21, F + 5, k, 21, F + 6, k + 1, B.GLASS)
	# Roof with skylight strips and lamps.
	Kit.box(g, m, 2, top + 1, 2, 21, top + 1, 28, B.METAL)
	for z: int in [7, 12, 17, 22]:
		Kit.box(g, m, 4, top + 1, z, 19, top + 1, z + 1, B.GLASS)
	for p: Vector2i in [Vector2i(6, 10), Vector2i(16, 10), Vector2i(6, 20), Vector2i(16, 20), Vector2i(11, 15)]:
		Kit.put(g, m, p.x, top + 1, p.y, B.LAMP)
	# Doors: two east (into the yard), two south.
	Kit.box(g, m, 21, F, 7, 21, F + 2, 9, B.AIR)
	Kit.box(g, m, 21, F, 20, 21, F + 2, 22, B.AIR)
	Kit.box(g, m, 8, F, 28, 10, F + 2, 28, B.AIR)
	Kit.box(g, m, 15, F, 28, 17, F + 2, 28, B.AIR)
	# Catwalks (north, west stub, east) and the ramp up.
	Kit.box(g, m, 3, F + 3, 3, 20, F + 3, 4, B.GRATE)
	Kit.box(g, m, 3, F + 3, 3, 4, F + 3, 8, B.GRATE)
	Kit.box(g, m, 19, F + 3, 3, 20, F + 3, 27, B.GRATE)
	Kit.ramp(g, m, Vector3i(3, F, 12), G.RAMP_NZ, 4, 2, B.METAL, B.METAL)
	for z: int in [8, 15, 23]:
		Kit.put(g, m, 19, F + 2, z, B.METAL)
		Kit.put(g, m, 19, F + 1, z, B.METAL)
		Kit.put(g, m, 19, F, z, B.METAL)
	# Opening from the east catwalk onto the bridge.
	Kit.box(g, m, 21, F + 4, 14, 21, F + 6, 16, B.AIR)
	Kit.box(g, m, 21, F + 3, 14, 21, F + 3, 16, B.GRATE)
	# Conveyor lines with machines; gaps let players cross.
	for z in range(8, 25):
		if z < 13 or z > 15:
			Kit.box(g, m, 8, F, z, 9, F, z, B.CONVEYOR)
	for z in range(6, 23):
		if z < 17 or z > 19:
			Kit.box(g, m, 14, F, z, 15, F, z, B.CONVEYOR)
	_machine(g, m, 7, 5, 10, 7)
	_machine(g, m, 13, 23, 16, 25)
	# Crate stacks.
	for p: Vector3i in [Vector3i(5, 0, 22), Vector3i(11, 0, 9), Vector3i(17, 0, 13), Vector3i(4, 0, 26)]:
		Kit.box(g, m, p.x, F, p.z, p.x + 1, F, p.z, B.CRATE)
		if rng.randf() < 0.6:
			Kit.put(g, m, p.x, F + 1, p.z, B.CRATE)


static func _machine(g: VoxelGrid, m: int, x0: int, z0: int, x1: int, z1: int) -> void:
	Kit.box(g, m, x0, F, z0, x1, F + 2, z1, B.METAL)
	Kit.box(g, m, x0, F, z0, x1, F, z1, B.HAZARD)
	Kit.put(g, m, x0 + 1, F + 3, z0 + 1, B.LAMP)
	Kit.box(g, m, x0 + 2, F + 3, z0 + 1, x0 + 2, F + 4, z0 + 1, B.METAL)


## Grate bridge: arms from each hall's catwalk exit to a spine across the
## yard, with ramps up from the yard in the middle and low cover on top.
static func _bridge(g: VoxelGrid) -> void:
	var y := F + 3
	g.fill(Vector3i(22, y, 14), Vector3i(29, y, 16), B.GRATE)
	g.fill(Vector3i(34, y, 47), Vector3i(41, y, 49), B.GRATE)
	g.fill(Vector3i(30, y, 14), Vector3i(33, y, 49), B.GRATE)
	g.walls(Vector3i(30, y, 14), Vector3i(33, y, 49), B.METAL)
	g.fill(Vector3i(30, y, 14), Vector3i(30, y, 16), B.GRATE)
	g.fill(Vector3i(33, y, 47), Vector3i(33, y, 49), B.GRATE)
	for z in range(18, 48, 7):
		for x: int in [30, 33]:
			g.fill(Vector3i(x, F, z), Vector3i(x, y - 1, z), B.METAL)
	for x: int in [25]:
		g.fill(Vector3i(x, F, 15), Vector3i(x, y - 1, 15), B.METAL)
		g.fill(Vector3i(63 - x, F, 48), Vector3i(63 - x, y - 1, 48), B.METAL)
	for p: Vector2i in [Vector2i(30, 22), Vector2i(33, 28), Vector2i(30, 37), Vector2i(33, 42)]:
		g.set_block(p.x, y + 1, p.y, B.METAL)
	g.set_block(31, y + 1, 30, B.HAZARD)
	g.ramp_run(Vector3i(26, F, 30), G.RAMP_PX, 4, 3, B.METAL, B.METAL)
	g.ramp_run(Vector3i(37, F, 31), G.RAMP_NX, 4, 3, B.METAL, B.METAL)
	# Hanging lamps under the spine.
	for z in range(21, 48, 7):
		g.set_block(31, y, z, B.LAMP)


## Tank farm in the north-east: two storage tanks, a pipe and a smokestack.
static func _tanks(g: VoxelGrid) -> void:
	for t: Vector4i in [Vector4i(49, 10, 4, 7), Vector4i(55, 21, 3, 6)]:
		var r := t.z
		for z in range(t.y - r, t.y + r + 1):
			for x in range(t.x - r, t.x + r + 1):
				var d := Vector2(x - t.x, z - t.y).length()
				if d > r + 0.4:
					continue
				g.fill(Vector3i(x, F, z), Vector3i(x, F + t.w - 1, z), B.METAL)
				if d > r - 0.6:
					g.set_block(x, F + 1, z, B.HAZARD)
				if d <= r - 0.6:
					g.set_block(x, F + t.w, z, B.METAL)
		g.set_block(t.x, F + t.w + 1, t.y, B.LAMP)
	g.fill(Vector3i(49, F + 5, 14), Vector3i(49, F + 5, 21), B.METAL)
	g.fill(Vector3i(49, F + 5, 21), Vector3i(52, F + 5, 21), B.METAL)
	# Smokestack.
	g.fill(Vector3i(57, F, 4), Vector3i(59, F + 19, 6), B.BRICK)
	for y: int in [F + 6, F + 12, F + 18]:
		g.fill(Vector3i(57, y, 4), Vector3i(59, y, 6), B.HAZARD)
	g.clear(Vector3i(58, F + 17, 5), Vector3i(58, F + 19, 5))
	# Jersey barriers.
	for p: Vector3i in [Vector3i(44, 0, 18), Vector3i(52, 0, 26), Vector3i(58, 0, 14)]:
		g.fill(Vector3i(p.x, F, p.z), Vector3i(p.x + 2, F, p.z), B.CONCRETE)


## Shipping containers in the south-west with 3-wide aisles; one stack has
## a ramp so its roof becomes a lookout.
static func _containers(g: VoxelGrid) -> void:
	var cols := [B.CONTAINER_RED, B.CONTAINER_BLUE]
	var i := 0
	for z0: int in [37, 48]:
		for x0: int in [4, 10, 16]:
			var z1 := z0 + 6 if not (x0 == 16 and z0 == 48) else z0 + 7
			var h := 3 if (i % 3 != 1) else 6
			g.fill(Vector3i(x0, F, z0), Vector3i(x0 + 2, F + 2, z1), cols[i % 2])
			if h == 6:
				g.fill(Vector3i(x0, F + 3, z0 + 1), Vector3i(x0 + 2, F + 5, z1 - 1), cols[(i + 1) % 2])
			i += 1
	g.ramp_run(Vector3i(16, F, 58), G.RAMP_NZ, 3, 3, B.METAL, B.METAL)
	for p: Vector3i in [Vector3i(8, 0, 45), Vector3i(13, 0, 57), Vector3i(4, 0, 58)]:
		g.fill(Vector3i(p.x, F, p.z), Vector3i(p.x + 1, F, p.z), B.CRATE)
		g.set_block(p.x, F + 1, p.z, B.CRATE)
