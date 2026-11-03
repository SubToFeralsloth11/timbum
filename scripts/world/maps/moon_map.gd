extends RefCounted
## Moon Base: a slab of grey regolith floating in space under a black, starry sky with the Earth
## hanging over the launch pad. A glass-banded command dome sits in the middle (a raised deck
## inside, four doors), joined by glass tubes to each team's yard; each side has a habitat module
## with a roof deck, a hangar with a rover and a launch tower whose platform links over a catwalk
## ring around the rocket on its pad to the other side's tower. South of the dome: a comms tower
## with a dish, and a crater on each flank. The west half mirrors the east (XF_MIRROR_X), so both
## Capture the Flag teams get the same base. The edge of the slab drops into space: falling below
## KILL_Y kills (cause "fall": Gravity).

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(64, 34, 64)
## Ground floor (feet height) and the kill height: below the crater floors (F - 3), above the
## slab's underside, so a fall off the edge kills within a few metres.
const F := 8
const KILL_Y := 4.0
const SEED := 8808
const ATMOSPHERE := {
	"sky": "space", "earth_dir": Vector3(0.55, 0.38, -0.74), "earth_radius": 0.095, "stars": 1.0,
	"sky_top": Color("010207"), "sky_horizon": Color("0b0d16"), "ground_bottom": Color("020203"),
	"sun_pitch": -38.0, "sun_yaw": -60.0, "sun_color": Color("fff8ec"), "sun_energy": 1.55,
	"fog_color": Color("0c0e16"), "fog_density": 0.0012, "ambient": 0.5, "exposure": 1.0,
	"saturation": 0.95, "fog_sky": 0.0, "ambient_color": Color("9aa3b8"),
	## World._apply_time_of_day: the sky stays black (no air); the sun drops to the horizon, and
	## at night the light is earthshine from the full Earth (the sun is behind the moon).
	"times": {
		"sunset": {"sun_pitch": -9.0, "sun_yaw": -75.0, "sun_color": Color("ffe2c2"), "sun_energy": 1.25,
			"ambient": 0.42, "ambient_color": Color("9a96a8"), "sky_horizon": Color("14121a")},
		"night": {"sun_pitch": -22.3, "sun_yaw": 143.4, "sun_color": Color("a9c2ff"), "sun_energy": 0.5,
			"sun_disc": 0.0, "space_sun_dir": Vector3(-0.5, 0.15, 0.85), "ambient": 0.36,
			"ambient_color": Color("6f86c4"), "exposure": 1.1},
	},
}
## Rocket and launch pad centre (between cells, so the x mirror maps it onto itself).
const PAD := Vector2(32.0, 13.0)
const PAD_R := 6.5
const DOME := Vector2(32.0, 32.0)
const DOME_R := 8.4
## Craters: [centre x, centre z, radius, depth] (cell centres), west side; mirrored east.
const CRATERS := [[21.5, 52.5, 5.0, 3]]
## Jump pads (MapKit.jump_pads): from each habitat's roof deck over to its launch tower's
## platform, and from the lane south of the dome up onto the comms tower platform.
const JUMP_PADS := [
	[Vector3i(12, F + 5, 12), Vector3i(19, F + 7, 12), 1.5],
	[Vector3i(51, F + 5, 12), Vector3i(44, F + 7, 12), 1.5],
	[Vector3i(29, F, 42), Vector3i(30, F + 4, 47), 1.5],
]
## Capture the Flag stands (MapKit.flag_stands): the middle of each team's yard.
const FLAG_STANDS := [Vector3i(10, F, 32), Vector3i(53, F, 32)]


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var sx := g.size.x
	var sz := g.size.z
	var hm := Kit.heightmap(g, F)
	var lock := PackedByteArray()
	lock.resize(sx * sz)
	var void_cells := PackedByteArray()
	void_cells.resize(sx * sz)
	for z in sz:
		for x in sx:
			var i := z * sx + x
			if _depth_in(x, z) < 0:
				void_cells[i] = 1
				lock[i] = 1
				continue
			var n := G.noise2(mini(x, sx - 1 - x) / 6.0, z / 6.0, SEED + 1)
			hm[i] = F + (1 if n > 0.74 else (-1 if n < 0.24 else 0))
	# Flat ground under every structure, yard and lane.
	for r: Array in [[2, 6, 17, 57], [17, 4, 32, 22], [20, 20, 32, 44], [25, 43, 32, 58], [14, 21, 25, 30]]:
		for side in 2:
			var a := Kit.xf(g, Kit.XF_MIRROR_X if side == 1 else Kit.XF_NONE, r[0], 0, r[1])
			var b := Kit.xf(g, Kit.XF_MIRROR_X if side == 1 else Kit.XF_NONE, r[2], 0, r[3])
			for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
				for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
					var i := z * sx + x
					if void_cells[i] == 0:
						hm[i] = F
						lock[i] = 1
	for c: Array in CRATERS:
		if c[2] > 0.0:
			_crater(g, hm, lock, c[0], c[1], c[2], c[3])
			_crater(g, hm, lock, sx - c[0], c[1], c[2], c[3])
	Kit.limit_steps(g, hm, lock)
	for i in hm.size():
		if void_cells[i] == 1:
			hm[i] = 0
	g.apply_heightmap(hm, B.REGOLITH, B.REGOLITH, B.MOON_ROCK, 2)
	# The slab's underside tapers toward the edge, so it hangs in space like a broken-off plate.
	for z in sz:
		for x in sx:
			var h := hm[z * sx + x]
			if h <= 0:
				continue
			var d := _depth_in(x, z)
			var bottom := mini(F - 1 - d * 2 - int(G.hash01(mini(x, sx - 1 - x), z, SEED + 2) * 2.0), h - 1)
			if bottom > 0:
				g.clear(Vector3i(x, 0, z), Vector3i(x, bottom - 1, z))
	g.auto_ramps(hm, B.REGOLITH)

	_dome(g, hm)
	_launch_pad(g)
	for side in 2:
		var m := Kit.XF_MIRROR_X if side == 1 else Kit.XF_NONE
		_tube(g, m)
		_hab(g, m)
		_hangar(g, m)
		_tower(g, m)
		_yard(g, m)
		_solar(g, m)
		_props(g, m)
	_comms(g)

	for s: Vector2i in [
		Vector2i(6, 16), Vector2i(11, 12), Vector2i(5, 27), Vector2i(11, 47), Vector2i(16, 18), Vector2i(16, 42),
		Vector2i(57, 16), Vector2i(52, 12), Vector2i(58, 27), Vector2i(52, 47), Vector2i(47, 18), Vector2i(47, 42),
		Vector2i(25, 44), Vector2i(38, 44), Vector2i(26, 21), Vector2i(37, 21),
	]:
		Kit.spawn(g, hm, info, s.x, s.y)
	Kit.pickup(g, hm, info, "health", 30, 30, F + 2)
	Kit.pickup(g, hm, info, "ammo", 32, 23)
	Kit.pickup(g, hm, info, "grenade", 34, 17, F + 2)
	Kit.pickup(g, hm, info, "health", 14, 36)
	Kit.pickup(g, hm, info, "health", 49, 36)
	Kit.pickup(g, hm, info, "ammo", 9, 50)
	Kit.pickup(g, hm, info, "ammo", 54, 50)
	Kit.pickup(g, hm, info, "grenade", 30, 48, F + 4)
	Kit.pickup(g, hm, info, "ammo", 21, 52)
	Kit.pickup(g, hm, info, "grenade", 42, 52)
	Kit.jump_pads(g, info, JUMP_PADS)
	Kit.flag_stands(g, info, FLAG_STANDS)


## How many cells column (x, z) lies inside the slab's ragged edge (negative: space). The rim is
## 1-3 cells deep on the west and east sides and 2-6 on the north and south, mirrored in x.
static func _depth_in(x: int, z: int) -> int:
	var mx := mini(x, SIZE.x - 1 - x)
	var n := G.noise2(mx / 5.0, z / 5.0, SEED)
	var dz := mini(z, SIZE.z - 1 - z)
	var rim := (1 + int(n * 3.0)) if mx <= dz else (2 + int(n * 5.0))
	return mini(mx, dz) - rim


## A bowl `depth` cells deep with a one-block rim, carved into the height map.
static func _crater(g: VoxelGrid, hm: PackedInt32Array, lock: PackedByteArray, cx: float, cz: float, r: float, depth: int) -> void:
	for z in range(floori(cz - r - 2.0), ceili(cz + r + 2.0)):
		for x in range(floori(cx - r - 2.0), ceili(cx + r + 2.0)):
			if x < 0 or z < 0 or x >= g.size.x or z >= g.size.z:
				continue
			var i := z * g.size.x + x
			if hm[i] <= 0 or lock[i] != 0:
				continue
			var d := Vector2(x + 0.5 - cx, z + 0.5 - cz).length()
			if d < r:
				hm[i] = F - ceili(depth * (1.0 - (d / r) * (d / r)) - 0.15)
			elif d < r + 1.4:
				hm[i] = F + 1


## Command dome: a hemisphere of hull panels with a glass band and lamps, four 3-wide doors, and a
## raised deck in the middle reached by ramps from the north and south.
static func _dome(g: VoxelGrid, hm: PackedInt32Array) -> void:
	for z in range(22, 42):
		for x in range(22, 42):
			var dx := x + 0.5 - DOME.x
			var dz := z + 0.5 - DOME.y
			if dx * dx + dz * dz < DOME_R * DOME_R:
				g.set_block(x, F - 1, z, B.PANEL if (x + z) % 7 != 0 else B.METAL)
			for y in range(F, F + 10):
				var dy := y - F + 0.5
				var d := sqrt(dx * dx + dy * dy + dz * dz)
				if d >= DOME_R - 1.2 and d < DOME_R:
					var band := y == F + 2 or y == F + 3
					var lamp := y == F + 4 and (absi(roundi(dx)) <= 0 or absi(roundi(dz)) <= 0)
					g.set_block(x, y, z, B.LAMP if lamp else (B.GLASS if band else B.PANEL))
	# Doors (3 wide, 3 high) at the four points of the compass, framed in hazard stripes.
	for d: Array in [[22, 31, 25, 33], [38, 31, 41, 33], [31, 22, 33, 25], [31, 38, 33, 41]]:
		g.clear(Vector3i(d[0], F, d[1]), Vector3i(d[2], F + 2, d[3]))
	# Raised deck with a console in the middle.
	g.fill(Vector3i(29, F, 29), Vector3i(34, F + 1, 34), B.METAL)
	g.fill(Vector3i(29, F + 1, 29), Vector3i(34, F + 1, 34), B.PANEL)
	g.ramp_run(Vector3i(31, F, 36), G.RAMP_NZ, 2, 2, B.METAL, B.METAL)
	g.ramp_run(Vector3i(31, F, 27), G.RAMP_PZ, 2, 2, B.METAL, B.METAL)
	g.fill(Vector3i(31, F + 2, 31), Vector3i(32, F + 2, 32), B.BLUE)
	g.fill(Vector3i(31, F + 3, 31), Vector3i(32, F + 3, 32), B.LAMP)
	# Supply crates against the deck facing the west and east doors (cover on the lower floor).
	for p: Vector2i in [Vector2i(28, 31), Vector2i(35, 31)]:
		g.fill(Vector3i(p.x, F, p.y), Vector3i(p.x, F, p.y + 1), B.CRATE)
	g.set_block(28, F + 1, 31, B.CRATE)
	g.set_block(35, F + 1, 32, B.CRATE)


## Launch pad: a raised concrete disc with a hazard ring and ramps on three sides, the rocket in
## the middle (fins at the four points as cover), lamp posts, and a grate ring around the rocket at
## tower height that both towers' catwalks reach.
static func _launch_pad(g: VoxelGrid) -> void:
	for z in range(4, 23):
		for x in range(22, 42):
			var d := Vector2(x + 0.5 - PAD.x, z + 0.5 - PAD.y).length()
			if d <= PAD_R:
				g.fill(Vector3i(x, F, z), Vector3i(x, F, z), B.CONCRETE)
				g.set_block(x, F + 1, z, B.HAZARD if d > PAD_R - 0.9 else B.CONCRETE)
				for y in range(F - 3, F):
					if g.is_air(x, y, z):
						g.set_block(x, y, z, B.CONCRETE)
	g.ramp_run(Vector3i(30, F, 20), G.RAMP_NZ, 2, 4, B.CONCRETE, B.CONCRETE)
	g.ramp_run(Vector3i(24, F, 11), G.RAMP_PX, 2, 4, B.CONCRETE, B.CONCRETE)
	g.ramp_run(Vector3i(39, F, 11), G.RAMP_NX, 2, 4, B.CONCRETE, B.CONCRETE)
	var top := F + 16
	for z in range(8, 19):
		for x in range(26, 38):
			var d2 := Vector2(x + 0.5 - PAD.x, z + 0.5 - PAD.y).length_squared()
			if d2 <= 2.6 * 2.6:
				for y in range(F + 2, top):
					var c := B.WHITE
					if y == F + 6 or y == F + 12:
						c = B.RED
					elif y == F + 2:
						c = B.METAL
					g.set_block(x, y, z, c)
			if d2 <= 1.6 * 1.6:
				g.fill(Vector3i(x, top, z), Vector3i(x, top + 1, z), B.WHITE)
			if d2 <= 0.8:
				g.fill(Vector3i(x, top + 2, z), Vector3i(x, top + 2, z), B.RED)
	g.fill(Vector3i(31, F + 13, 15), Vector3i(32, F + 13, 15), B.BLUE)
	# Fins.
	for f: Array in [[35, 12, 36, 13], [27, 12, 28, 13], [31, 16, 32, 17], [31, 8, 32, 9]]:
		g.fill(Vector3i(f[0], F + 2, f[1]), Vector3i(f[2], F + 4, f[3]), B.RED)
	for f: Array in [[36, 12, 36, 13], [27, 12, 27, 13], [31, 17, 32, 17], [31, 8, 32, 8]]:
		g.clear(Vector3i(f[0], F + 4, f[1]), Vector3i(f[2], F + 4, f[3]))
	# Grate ring around the rocket at y F + 6 (feet F + 7).
	for z in range(6, 21):
		for x in range(24, 40):
			var d := Vector2(x + 0.5 - PAD.x, z + 0.5 - PAD.y).length()
			if d > 2.7 and d <= 4.6:
				g.set_block(x, F + 6, z, B.GRATE)
	for p: Vector2i in [Vector2i(27, 8), Vector2i(36, 8), Vector2i(27, 17), Vector2i(36, 17)]:
		g.fill(Vector3i(p.x, F + 2, p.y), Vector3i(p.x, F + 5, p.y), B.METAL)
	for p: Vector2i in [Vector2i(26, 7), Vector2i(37, 7), Vector2i(26, 18), Vector2i(37, 18)]:
		g.set_block(p.x, F + 2, p.y, B.METAL)
		g.set_block(p.x, F + 3, p.y, B.LAMP)


## Launch tower west of the pad (mirrored east): a grate platform on four legs at y F + 6, a ramp
## up from the south and a catwalk east to the ring around the rocket.
static func _tower(g: VoxelGrid, m: int) -> void:
	var y := F + 6
	Kit.box(g, m, 18, y, 7, 22, y, 13, B.GRATE)
	for p: Vector2i in [Vector2i(18, 7), Vector2i(22, 7), Vector2i(18, 13), Vector2i(22, 13)]:
		Kit.box(g, m, p.x, F, p.y, p.x, y - 1, p.y, B.METAL)
	Kit.box(g, m, 18, y + 1, 7, 22, y + 1, 7, B.METAL)
	Kit.box(g, m, 18, y + 1, 7, 18, y + 1, 10, B.METAL)
	Kit.put(g, m, 18, y + 2, 7, B.LAMP)
	Kit.ramp(g, m, Vector3i(19, F, 20), G.RAMP_NZ, 7, 2, B.METAL, B.METAL)
	Kit.box(g, m, 23, y, 12, 28, y, 13, B.GRATE)


## Habitat module in the north-west corner (mirrored north-east): two rooms with bunks and lockers,
## doors south and east, a window north, and a roof deck reached by a ramp from the yard.
static func _hab(g: VoxelGrid, m: int) -> void:
	var x0 := 4
	var z0 := 9
	var x1 := 13
	var z1 := 19
	for w: Array in [[x0, z0, x1, z0], [x0, z1, x1, z1], [x0, z0, x0, z1], [x1, z0, x1, z1]]:
		Kit.box(g, m, w[0], F, w[1], w[2], F + 3, w[3], B.PANEL)
	Kit.box(g, m, x0, F + 4, z0, x1, F + 4, z1, B.PANEL)
	Kit.box(g, m, x0 + 1, F - 1, z0 + 1, x1 - 1, F - 1, z1 - 1, B.METAL)
	# Railing on the roof's outer edges.
	Kit.box(g, m, x0, F + 5, z0, x1, F + 5, z0, B.METAL)
	Kit.box(g, m, x0, F + 5, z0, x0, F + 5, z1, B.METAL)
	Kit.box(g, m, x0 + 2, F + 1, z0, x1 - 2, F + 2, z0, B.GLASS)
	Kit.box(g, m, x0 + 2, F, z1, x0 + 3, F + 2, z1, B.AIR)
	Kit.box(g, m, x1, F, z0 + 4, x1, F + 2, z0 + 6, B.AIR)
	Kit.box(g, m, x1, F + 1, z1 - 3, x1, F + 2, z1 - 2, B.GLASS)
	# Partition with a doorway.
	Kit.box(g, m, 9, F, z0 + 1, 9, F + 3, z1 - 1, B.WHITE)
	Kit.box(g, m, 9, F, 12, 9, F + 2, 14, B.AIR)
	# Bunks, lockers and a lamp in each room.
	Kit.box(g, m, x0 + 1, F, z0 + 1, x0 + 2, F, z0 + 3, B.BLUE)
	Kit.box(g, m, x0 + 1, F, z1 - 4, x0 + 2, F, z1 - 2, B.BLUE)
	Kit.box(g, m, 12, F, z0 + 1, 12, F + 1, z0 + 2, B.METAL)
	Kit.box(g, m, 10, F, z1 - 1, 11, F, z1 - 1, B.CRATE)
	Kit.put(g, m, 6, F + 3, 14, B.LAMP)
	Kit.put(g, m, 11, F + 3, 14, B.LAMP)
	Kit.ramp(g, m, Vector3i(11, F, 24), G.RAMP_NZ, 5, 2, B.PANEL, B.PANEL)


## Hangar in the south-west corner (mirrored south-east): a big door east onto the yard lane, a
## small one north, a rover and supply crates inside.
static func _hangar(g: VoxelGrid, m: int) -> void:
	var x0 := 4
	var z0 := 44
	var x1 := 13
	var z1 := 54
	for w: Array in [[x0, z0, x1, z0], [x0, z1, x1, z1], [x0, z0, x0, z1], [x1, z0, x1, z1]]:
		Kit.box(g, m, w[0], F, w[1], w[2], F + 4, w[3], B.PANEL)
	Kit.box(g, m, x0, F + 5, z0, x1, F + 5, z1, B.METAL)
	Kit.box(g, m, x0 + 1, F - 1, z0 + 1, x1 - 1, F - 1, z1 - 1, B.CONCRETE)
	Kit.box(g, m, x1, F, z0 + 2, x1, F + 3, z1 - 2, B.AIR)
	Kit.box(g, m, x1, F + 4, z0 + 2, x1, F + 4, z1 - 2, B.HAZARD)
	Kit.box(g, m, x0 + 3, F, z0, x0 + 5, F + 2, z0, B.AIR)
	# Rover: a white body on metal wheels with a blue cab.
	Kit.box(g, m, 6, F, 47, 8, F, 52, B.METAL)
	Kit.box(g, m, 6, F + 1, 47, 8, F + 1, 52, B.WHITE)
	Kit.box(g, m, 6, F + 2, 47, 8, F + 2, 48, B.BLUE)
	Kit.box(g, m, 7, F + 2, 51, 7, F + 3, 51, B.METAL)
	Kit.put(g, m, 7, F + 4, 51, B.LAMP)
	Kit.box(g, m, 11, F, 52, 12, F + 1, 53, B.CRATE)
	Kit.box(g, m, 5, F, 45, 5, F + 1, 45, B.ORANGE)
	Kit.put(g, m, 9, F + 4, 49, B.LAMP)


## Glass tube from the yard to the dome's west door (mirrored east).
static func _tube(g: VoxelGrid, m: int) -> void:
	Kit.box(g, m, 17, F - 1, 31, 23, F - 1, 33, B.PANEL)
	Kit.box(g, m, 17, F, 30, 23, F + 2, 30, B.GLASS)
	Kit.box(g, m, 17, F, 34, 23, F + 2, 34, B.GLASS)
	for x: int in [17, 20, 23]:
		Kit.box(g, m, x, F, 30, x, F + 2, 30, B.PANEL)
		Kit.box(g, m, x, F, 34, x, F + 2, 34, B.PANEL)
	Kit.box(g, m, 17, F + 3, 30, 23, F + 3, 34, B.PANEL)
	Kit.put(g, m, 20, F + 2, 32, B.LAMP)


## The team yard between hab, tube and hangar: fuel tanks, crates, a mast with a beacon.
static func _yard(g: VoxelGrid, m: int) -> void:
	for p: Vector2i in [Vector2i(5, 23), Vector2i(5, 40)]:
		Kit.box(g, m, p.x, F, p.y, p.x + 1, F + 2, p.y + 1, B.ORANGE)
		Kit.box(g, m, p.x, F + 3, p.y, p.x + 1, F + 3, p.y + 1, B.WHITE)
	for p: Vector2i in [Vector2i(14, 26), Vector2i(15, 38), Vector2i(8, 28)]:
		Kit.box(g, m, p.x, F, p.y, p.x + 1, F, p.y, B.CRATE)
		Kit.put(g, m, p.x, F + 1, p.y, B.CRATE)
	Kit.box(g, m, 4, F, 33, 4, F + 5, 33, B.METAL)
	Kit.put(g, m, 4, F + 6, 33, B.LAMP)
	Kit.box(g, m, 16, F, 29, 16, F + 2, 29, B.METAL)
	Kit.put(g, m, 16, F + 3, 29, B.LAMP)


## Two rows of solar panels on posts between the tower and the tube (mirrored): waist-high walls
## you can shoot under but not walk under.
static func _solar(g: VoxelGrid, m: int) -> void:
	for z: int in [23, 27]:
		Kit.box(g, m, 16, F + 1, z, 23, F + 1, z + 1, B.SOLAR)
		for x: int in [16, 19, 22]:
			Kit.box(g, m, x, F, z, x, F, z + 1, B.METAL)


## Comms tower south of the dome: a grate platform at y F + 3 on four legs, reached by a ramp from
## the south, with a mast and a dish on top.
static func _comms(g: VoxelGrid) -> void:
	var y := F + 3
	g.fill(Vector3i(29, y, 46), Vector3i(34, y, 52), B.GRATE)
	for p: Vector2i in [Vector2i(29, 46), Vector2i(34, 46), Vector2i(29, 52), Vector2i(34, 52)]:
		g.fill(Vector3i(p.x, F, p.y), Vector3i(p.x, y - 1, p.y), B.METAL)
	g.ramp_run(Vector3i(38, F, 48), G.RAMP_NX, 4, 2, B.METAL, B.METAL)
	g.fill(Vector3i(31, y + 1, 50), Vector3i(32, y + 3, 51), B.METAL)
	for z in range(46, 54):
		for x in range(28, 36):
			var d := Vector2(x + 0.5 - 32.0, z + 0.5 - 50.0).length()
			if d <= 3.1:
				g.set_block(x, y + 4 + (1 if d > 1.8 and z < 50 else 0), z, B.WHITE)
	g.fill(Vector3i(31, y + 5, 50), Vector3i(32, y + 5, 50), B.LAMP)
	# A parked rover and crates on either side of the lane.
	for side in 2:
		var m := Kit.XF_MIRROR_X if side == 1 else Kit.XF_NONE
		Kit.box(g, m, 23, F, 40, 25, F, 42, B.METAL)
		Kit.box(g, m, 23, F + 1, 40, 25, F + 1, 42, B.WHITE)
		Kit.box(g, m, 24, F + 2, 40, 25, F + 2, 40, B.BLUE)
		Kit.box(g, m, 27, F, 54, 28, F + 1, 54, B.CRATE)


## Boulders of moon rock on the open flanks (mirrored).
static func _props(g: VoxelGrid, m: int) -> void:
	for r: Array in [[25, 5, 2], [14, 3, 1], [3, 58, 1], [10, 58, 2], [18, 37, 1], [26, 47, 1], [17, 58, 1]]:
		var p := Kit.xf(g, m, r[0], 0, r[1])
		var top := g.surface(p.x, p.z, 1)
		if top < 0:
			continue
		Kit.box(g, m, r[0], top, r[1], r[0] + r[2] - 1, top + r[2] - 1, r[1] + r[2] - 1, B.MOON_ROCK)
