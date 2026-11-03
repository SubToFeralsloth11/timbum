extends RefCounted
## Volcano Forge: dark basalt ground around a lava lake with a forge-anvil island in the middle
## (a bridge from each side), lava channels running north and south from the lake (crossed by a
## bridge under the great crucible's deck, the crucible deck itself, a bridge on the north ridge
## and two in the south quarry). Each side has a great forge hall (furnace, anvils, a catwalk
## with shooting slits), a foundry shed with casting moulds and a yard between them; the north is
## a basalt ridge with spires, the south a quarry of basalt pillars and smelter chimneys. The west
## half mirrors the east (XF_MIRROR_X). Lava (BlockAtlas.LAVA, glowing) fills the lake and
## channels below KILL_Y, so falling in kills like water: the kill feed says "Lava"
## (KILL_CAUSE). Ember particles and orange lights over the lava come from the ATMOSPHERE's
## `embers` and the `glow_lights` mark (MapBuilder._add_effects).

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")

const SIZE := Vector3i(64, 30, 64)
const F := 6
## Lava surface (top of the lava blocks), two blocks under the ground so the lake glows in plain
## view; KILL_Y sits just above it and below every floor.
const LAVA_TOP := 4
const KILL_Y := 5.0
const KILL_CAUSE := "lava"
const SEED := 9909
const ATMOSPHERE := {
	"sky_top": Color("3a1c15"), "sky_horizon": Color("b4542c"), "ground_bottom": Color("1c100d"),
	"sun_pitch": -34.0, "sun_yaw": 35.0, "sun_color": Color("ffb27c"), "sun_energy": 1.05,
	"fog_color": Color("7a3a24"), "fog_density": 0.008, "ambient": 1.0, "exposure": 1.1,
	"saturation": 1.05, "fog_sky": 0.55, "ambient_color": Color("c98a6e"), "sky_energy": 0.9,
	"embers": true, "ember_floor": 4.0,
	## World._apply_time_of_day: the smoke stays lit from below by the lava at night.
	"times": {
		"sunset": {"sky_top": Color("2a0f12"), "sky_horizon": Color("e0602a"), "sun_pitch": -12.0,
			"sun_color": Color("ff7a3a"), "sun_energy": 0.95, "fog_color": Color("8c3a1e"),
			"ambient_color": Color("d07858"), "ambient": 0.9},
		"night": {"sky_top": Color("0b0506"), "sky_horizon": Color("4a1a10"), "ground_bottom": Color("0a0505"),
			"sun_pitch": -48.0, "sun_color": Color("ff9a6a"), "sun_energy": 0.32, "fog_color": Color("3c160d"),
			"fog_density": 0.009, "ambient": 0.8, "ambient_color": Color("b4664c"), "exposure": 1.15, "sky_energy": 1.0},
	},
}
## Island in the lava lake (centre between cells, so the x mirror maps it onto itself).
const LAKE := Vector2(32.0, 32.0)
const ISLAND_R := 4.6
## North and south lava channels run along x 30..33.
const CHANNEL := [30, 33]
## Jump pads (MapKit.jump_pads): from each lake shore up onto that side's foundry roof, with a
## drop back to the yard.
const JUMP_PADS := [
	[Vector3i(22, F, 42), Vector3i(12, F + 6, 46), 1.5, Vector3(12.5, F + 6, 43.5), Vector3(12.5, F, 42.5)],
	[Vector3i(41, F, 42), Vector3i(51, F + 6, 46), 1.5, Vector3(51.5, F + 6, 43.5), Vector3(51.5, F, 42.5)],
]
## Capture the Flag stands (MapKit.flag_stands): the middle of each team's yard.
const FLAG_STANDS := [Vector3i(10, F, 32), Vector3i(53, F, 32)]


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var sx := g.size.x
	var sz := g.size.z
	var hm := Kit.heightmap(g, F)
	var lock := PackedByteArray()
	lock.resize(sx * sz)
	for z in sz:
		for x in sx:
			var mx := mini(x, sx - 1 - x)
			var i := z * sx + x
			if z < 10 and mx >= 18:
				# The ridge on the volcano's flank, rising to the north edge.
				hm[i] = F + clampi(roundi((10 - z) * 0.45 + (G.noise2(mx / 4.0, z / 4.0, SEED) - 0.5) * 1.6), 0, 4)
			elif z > 44 and mx >= 17:
				hm[i] = F + (1 if G.noise2(mx / 5.0, z / 5.0, SEED + 1) > 0.66 else 0)
	for r: Array in [[1, 6, 17, 57], [18, 9, 31, 17], [18, 18, 31, 44], [26, 44, 29, 50]]:
		for side in 2:
			var a := Kit.xf(g, Kit.XF_MIRROR_X if side == 1 else Kit.XF_NONE, r[0], 0, r[1])
			var b := Kit.xf(g, Kit.XF_MIRROR_X if side == 1 else Kit.XF_NONE, r[2], 0, r[3])
			for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
				for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
					hm[z * sx + x] = F
					lock[z * sx + x] = 1
	for z in sz:
		for x in sx:
			if _is_lava(x, z):
				lock[z * sx + x] = 1
	Kit.limit_steps(g, hm, lock)
	for z in sz:
		for x in sx:
			if _is_lava(x, z):
				hm[z * sx + x] = LAVA_TOP
	g.apply_heightmap(hm, B.BASALT, B.BASALT, B.BASALT)
	g.auto_ramps(hm, B.BASALT)
	for z in sz:
		for x in sx:
			if _is_lava(x, z):
				g.fill(Vector3i(x, 0, z), Vector3i(x, LAVA_TOP - 1, z), B.LAVA)
			elif _is_lava(x - 1, z) or _is_lava(x + 1, z) or _is_lava(x, z - 1) or _is_lava(x, z + 1):
				# Banks with glowing cracks down to the lava.
				for y in range(LAVA_TOP, hm[z * sx + x] - 1):
					if G.hash01(mini(x, sx - 1 - x) * 7 + y, z, SEED + 3) > 0.62:
						g.set_block(x, y, z, B.MAGMA)

	_island(g)
	_crossings(g, hm)
	_crucible(g)
	_lavafall(g, hm)
	for side in 2:
		var m := Kit.XF_MIRROR_X if side == 1 else Kit.XF_NONE
		_forge(g, m)
		_foundry(g, m)
		_yard(g, m)
		_quarry(g, m)
		_ridge(g, m)

	for s: Vector2i in [
		Vector2i(6, 12), Vector2i(14, 19), Vector2i(5, 27), Vector2i(11, 47), Vector2i(17, 24), Vector2i(18, 41),
		Vector2i(24, 6), Vector2i(21, 57),
		Vector2i(57, 12), Vector2i(49, 19), Vector2i(58, 27), Vector2i(52, 47), Vector2i(46, 24), Vector2i(45, 41),
		Vector2i(39, 6), Vector2i(42, 57),
	]:
		Kit.spawn(g, hm, info, s.x, s.y)
	Kit.pickup(g, hm, info, "health", 30, 34)
	Kit.pickup(g, hm, info, "grenade", 31, 16, F + 4)
	Kit.pickup(g, hm, info, "health", 14, 36)
	Kit.pickup(g, hm, info, "health", 49, 36)
	Kit.pickup(g, hm, info, "ammo", 13, 18)
	Kit.pickup(g, hm, info, "ammo", 50, 18)
	Kit.pickup(g, hm, info, "grenade", 9, 48)
	Kit.pickup(g, hm, info, "grenade", 54, 48)
	Kit.pickup(g, hm, info, "ammo", 31, 48, F)
	info.marks["glow_lights"] = [
		{"pos": Vector3(32.0, LAVA_TOP + 2.5, 32.0), "color": Color("ff7a2a"), "range": 15.0, "energy": 2.2},
		{"pos": Vector3(32.0, LAVA_TOP + 2.0, 18.0), "color": Color("ff6a20"), "range": 9.0, "energy": 1.6},
		{"pos": Vector3(32.0, LAVA_TOP + 2.0, 53.0), "color": Color("ff6a20"), "range": 9.0, "energy": 1.6},
		{"pos": Vector3(11.0, F + 2.0, 17.5), "color": Color("ff8a3a"), "range": 8.0, "energy": 1.4},
		{"pos": Vector3(53.0, F + 2.0, 17.5), "color": Color("ff8a3a"), "range": 8.0, "energy": 1.4},
	]
	Kit.jump_pads(g, info, JUMP_PADS)
	Kit.flag_stands(g, info, FLAG_STANDS)


## The lava lake (a ragged ring around the island, mirrored in x) and the two channels.
static func _is_lava(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= SIZE.x or z >= SIZE.z:
		return false
	var dx := x + 0.5 - LAKE.x
	var dz := z + 0.5 - LAKE.y
	var d := sqrt(dx * dx + dz * dz)
	var r := 10.0 + (G.noise2(absf(dx) / 3.5, dz / 3.5, SEED + 5) - 0.5) * 3.0
	if d > ISLAND_R and d < r:
		return true
	return x >= CHANNEL[0] and x <= CHANNEL[1] and (z < 26 or z > 38)


## The forge-anvil island: a basalt-brick plaza with a giant anvil and a brazier.
static func _island(g: VoxelGrid) -> void:
	for z in range(26, 38):
		for x in range(26, 38):
			if Vector2(x + 0.5 - LAKE.x, z + 0.5 - LAKE.y).length() <= ISLAND_R:
				g.set_block(x, F - 1, z, B.BASALT_BRICK)
	g.fill(Vector3i(31, F, 31), Vector3i(32, F, 32), B.BASALT)
	g.fill(Vector3i(30, F + 1, 31), Vector3i(33, F + 1, 32), B.METAL)
	# A brazier on the south edge.
	g.fill(Vector3i(31, F, 35), Vector3i(32, F, 35), B.BASALT_BRICK)
	g.fill(Vector3i(31, F + 1, 35), Vector3i(32, F + 1, 35), B.MAGMA)


## Bridges: west and east onto the island; over the north channel a stone bridge under the
## crucible deck and one on the ridge; over the south channel a wide stone bridge and a grate
## catwalk. Island bridges have low parapets.
static func _crossings(g: VoxelGrid, hm: PackedInt32Array) -> void:
	for side in 2:
		var m := Kit.XF_MIRROR_X if side == 1 else Kit.XF_NONE
		Kit.box(g, m, 20, F - 1, 31, 28, F - 1, 33, B.BASALT_BRICK)
		Kit.box(g, m, 20, F, 30, 26, F, 30, B.BASALT_BRICK)
		Kit.box(g, m, 20, F, 34, 26, F, 34, B.BASALT_BRICK)
		Kit.box(g, m, 23, F - 1, 30, 28, F - 1, 34, B.BASALT_BRICK)
		for x: int in [24, 27]:
			Kit.box(g, m, x, LAVA_TOP, 32, x, F - 2, 32, B.BASALT_BRICK)
		Kit.put(g, m, 24, F + 1, 30, B.LAMP)
	_span(g, hm, 12, 14, B.BASALT_BRICK)
	_span(g, hm, 3, 4, B.BASALT_BRICK)
	_span(g, hm, 47, 49, B.BASALT_BRICK)
	_span(g, hm, 56, 57, B.GRATE)


## A flat bridge across a channel over rows z0..z1, level with the bank west of it.
static func _span(g: VoxelGrid, hm: PackedInt32Array, z0: int, z1: int, block: int) -> void:
	for z in range(z0, z1 + 1):
		var top := hm[z * g.size.x + CHANNEL[0] - 1]
		g.fill(Vector3i(CHANNEL[0], top - 1, z), Vector3i(CHANNEL[1], top - 1, z), block)
		g.clear(Vector3i(CHANNEL[0] - 1, top, z), Vector3i(CHANNEL[1] + 1, top + 2, z))
	if block != B.GRATE:
		var top := hm[z0 * g.size.x + CHANNEL[0] - 1]
		g.fill(Vector3i(CHANNEL[0], LAVA_TOP, z0), Vector3i(CHANNEL[0], top - 2, z1), B.BASALT_BRICK)
		g.fill(Vector3i(CHANNEL[1], LAVA_TOP, z0), Vector3i(CHANNEL[1], top - 2, z1), B.BASALT_BRICK)


## The great crucible: a metal deck at y F + 3 over the north channel (ramps up from the west and
## east), on basalt-brick piers, with a crucible of glowing magma in the middle.
static func _crucible(g: VoxelGrid) -> void:
	var y := F + 3
	g.fill(Vector3i(24, y, 9), Vector3i(39, y, 16), B.METAL)
	g.fill(Vector3i(26, y, 10), Vector3i(37, y, 15), B.GRATE)
	for p: Vector2i in [Vector2i(24, 9), Vector2i(24, 15), Vector2i(29, 9), Vector2i(29, 15)]:
		for side in 2:
			var m := Kit.XF_MIRROR_X if side == 1 else Kit.XF_NONE
			Kit.box(g, m, p.x, F, p.y, p.x, y - 1, p.y, B.BASALT_BRICK)
	for side in 2:
		var m := Kit.XF_MIRROR_X if side == 1 else Kit.XF_NONE
		Kit.ramp(g, m, Vector3i(20, F, 11), G.RAMP_PX, 4, 3, B.METAL, B.BASALT_BRICK)
		Kit.box(g, m, 24, y + 1, 9, 27, y + 1, 9, B.METAL)
	for z in range(9, 16):
		for x in range(28, 36):
			var d := Vector2(x + 0.5 - 32.0, z + 0.5 - 12.0).length()
			if d <= 2.6:
				g.set_block(x, y + 1, z, B.MAGMA if d <= 1.7 else B.METAL)
				if d > 1.7:
					g.set_block(x, y + 2, z, B.METAL)


## A lava fall where the north channel meets the map's edge under the ridge, capped with basalt
## (the cap is level with the ridge, so no lava is ever above KILL_Y within reach).
static func _lavafall(g: VoxelGrid, hm: PackedInt32Array) -> void:
	var top := hm[CHANNEL[0] - 1]
	g.fill(Vector3i(CHANNEL[0], LAVA_TOP, 0), Vector3i(CHANNEL[1], top - 2, 0), B.LAVA)
	g.fill(Vector3i(CHANNEL[0], top - 1, 0), Vector3i(CHANNEL[1], top - 1, 0), B.BASALT)


## Great forge hall in the north-west (mirrored north-east): a furnace with a chimney, anvils,
## a catwalk along the west and north walls with shooting slits, doors east and south.
static func _forge(g: VoxelGrid, m: int) -> void:
	var x0 := 3
	var z0 := 8
	var x1 := 16
	var z1 := 21
	var top := F + 6
	for w: Array in [[x0, z0, x1, z0], [x0, z1, x1, z1], [x0, z0, x0, z1], [x1, z0, x1, z1]]:
		Kit.box(g, m, w[0], F, w[1], w[2], top, w[3], B.BASALT_BRICK)
	Kit.box(g, m, x0, top + 1, z0, x1, top + 1, z1, B.BASALT)
	Kit.box(g, m, x0 + 1, F - 1, z0 + 1, x1 - 1, F - 1, z1 - 1, B.BASALT_BRICK)
	for x: int in [x0, x1]:
		for z: int in [z0, z1]:
			Kit.box(g, m, x, F, z, x, top + 1, z, B.BASALT)
	# Doors.
	Kit.box(g, m, x1, F, 13, x1, F + 3, 15, B.AIR)
	Kit.box(g, m, 13, F, z1, 15, F + 3, z1, B.AIR)
	# Catwalk at y F + 3 (feet F + 4) and the ramp up to it along the south wall.
	var c := F + 3
	Kit.box(g, m, x0 + 1, c, z0 + 1, x0 + 3, c, z1 - 1, B.GRATE)
	Kit.box(g, m, x0 + 1, c, z0 + 1, x1 - 1, c, z0 + 3, B.GRATE)
	Kit.box(g, m, x0 + 1, c, z1 - 2, 8, c, z1 - 1, B.GRATE)
	Kit.ramp(g, m, Vector3i(12, F, 19), G.RAMP_NX, 4, 2, B.METAL, B.METAL)
	# Shooting slits at eye height from the catwalk: south over the yard, east over the crucible.
	Kit.box(g, m, x0 + 1, c + 2, z1, x0 + 4, c + 2, z1, B.AIR)
	Kit.box(g, m, x1, c + 2, z0 + 1, x1, c + 2, z0 + 3, B.AIR)
	# Furnace with a glowing mouth and a chimney through the roof.
	Kit.box(g, m, 9, F, 13, 12, F + 4, 16, B.BASALT_BRICK)
	Kit.box(g, m, 10, F, 16, 11, F + 1, 16, B.MAGMA)
	Kit.box(g, m, 10, F + 5, 14, 11, top + 4, 15, B.BASALT_BRICK)
	Kit.box(g, m, 10, top + 5, 14, 11, top + 5, 15, B.MAGMA)
	# Anvils and quench tanks.
	for p: Vector2i in [Vector2i(6, 15), Vector2i(11, 10)]:
		Kit.put(g, m, p.x, F, p.y, B.BASALT)
		Kit.box(g, m, p.x - 1, F + 1, p.y, p.x + 1, F + 1, p.y, B.METAL)
	Kit.box(g, m, 6, F, 19, 7, F, 19, B.METAL)
	for p: Vector2i in [Vector2i(8, z0), Vector2i(x1, 18), Vector2i(x0, 13)]:
		Kit.put(g, m, p.x, F + 5, p.y, B.LAMP)


## Foundry shed in the south-west (mirrored south-east): a metal roof on basalt pillars, open to
## the east and south, with casting moulds, a crucible and stacked ingots.
static func _foundry(g: VoxelGrid, m: int) -> void:
	var x0 := 3
	var z0 := 43
	var x1 := 14
	var z1 := 56
	Kit.box(g, m, x0, F + 5, z0, x1, F + 5, z1, B.METAL)
	Kit.box(g, m, x0, F, z0, x0, F + 4, z1, B.BASALT_BRICK)
	Kit.box(g, m, x0, F, z0, 8, F + 4, z0, B.BASALT_BRICK)
	for p: Vector2i in [Vector2i(x1, z0), Vector2i(x1, z1), Vector2i(x0, z1), Vector2i(x1, 49), Vector2i(8, z1)]:
		Kit.box(g, m, p.x, F, p.y, p.x, F + 4, p.y, B.BASALT_BRICK)
	Kit.box(g, m, x0 + 1, F - 1, z0 + 1, x1 - 1, F - 1, z1 - 1, B.BASALT_BRICK)
	# Casting moulds: basalt frames holding gold ingots.
	for z: int in [46, 52]:
		Kit.box(g, m, 5, F, z, 7, F, z + 1, B.BASALT)
		Kit.box(g, m, 6, F, z, 6, F, z + 1, B.GOLD)
	# Crucible on a stand.
	Kit.box(g, m, 10, F, 51, 12, F, 53, B.BASALT_BRICK)
	Kit.box(g, m, 10, F + 1, 51, 12, F + 1, 53, B.METAL)
	Kit.put(g, m, 11, F + 1, 52, B.MAGMA)
	Kit.box(g, m, 11, F, 45, 12, F + 1, 45, B.CRATE)
	Kit.put(g, m, 7, F + 4, 50, B.LAMP)


## The yard between forge and foundry: ore carts, ingot crates, basalt boulders, lamp posts.
static func _yard(g: VoxelGrid, m: int) -> void:
	for p: Vector2i in [Vector2i(5, 24), Vector2i(14, 39)]:
		Kit.box(g, m, p.x, F, p.y, p.x + 1, F, p.y + 2, B.METAL)
		Kit.box(g, m, p.x, F + 1, p.y, p.x + 1, F + 1, p.y + 2, B.GOLD)
	Kit.box(g, m, 15, F, 26, 16, F, 27, B.CRATE)
	Kit.put(g, m, 15, F + 1, 26, B.CRATE)
	Kit.box(g, m, 6, F, 37, 7, F + 1, 38, B.BASALT)
	for p: Vector2i in [Vector2i(3, 30), Vector2i(17, 34)]:
		Kit.box(g, m, p.x, F, p.y, p.x, F + 2, p.y, B.BASALT_BRICK)
		Kit.put(g, m, p.x, F + 3, p.y, B.LAMP)


## The south quarry (mirrored): basalt pillars of several heights, a smelter chimney with a
## glowing top, and slag rocks.
static func _quarry(g: VoxelGrid, m: int) -> void:
	for r: Array in [[20, 46, 3], [26, 51, 2], [19, 52, 1], [25, 58, 4], [28, 44, 1]]:
		var p := Kit.xf(g, m, r[0], 0, r[1])
		var y := g.surface(p.x, p.z, 1)
		if y < 0:
			continue
		Kit.box(g, m, r[0], y, r[1], r[0] + 1, y + r[2] - 1, r[1] + 1, B.BASALT)
	Kit.box(g, m, 22, F, 54, 23, F + 11, 55, B.BASALT_BRICK)
	Kit.box(g, m, 22, F + 12, 54, 23, F + 12, 55, B.MAGMA)
	Kit.box(g, m, 22, F + 3, 54, 23, F + 3, 55, B.METAL)


## Basalt spires and boulders on the north ridge (mirrored).
static func _ridge(g: VoxelGrid, m: int) -> void:
	for r: Array in [[21, 3, 5], [27, 1, 3], [19, 7, 2], [28, 6, 1]]:
		var p := Kit.xf(g, m, r[0], 0, r[1])
		var y := g.surface(p.x, p.z, 1)
		if y < 0:
			continue
		Kit.box(g, m, r[0], y, r[1], r[0], y + r[2] - 1, r[1], B.BASALT)
		if r[2] >= 3:
			Kit.put(g, m, r[0], y + r[2], r[1], B.MAGMA)
