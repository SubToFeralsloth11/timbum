extends RefCounted
## Building blocks shared by the map generators. Everything is deterministic:
## randomness only comes from RandomNumberGenerator instances with fixed seeds
## or from VoxelGrid.hash01/noise2.

const B := preload("res://scripts/world/block_atlas.gd")
const G := preload("res://scripts/world/voxel_grid.gd")


## Height map of `g`'s footprint filled with `h`.
static func heightmap(g: VoxelGrid, h: int) -> PackedInt32Array:
	var hm := PackedInt32Array()
	hm.resize(g.size.x * g.size.z)
	hm.fill(h)
	return hm


static func rect(g: VoxelGrid, hm: PackedInt32Array, x0: int, z0: int, x1: int, z1: int, h: int) -> void:
	for z in range(maxi(z0, 0), mini(z1, g.size.z - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, g.size.x - 1) + 1):
			hm[z * g.size.x + x] = h


## Reshapes unlocked cells until no column differs from a neighbour by more
## than one, so every height change can become a ramp. First unlocked cells
## are lowered to at most one above each neighbour, then raised to at least
## one below each neighbour. Cells whose `lock` entry is non-zero (pads,
## ponds) keep their height.
static func limit_steps(g: VoxelGrid, hm: PackedInt32Array, lock := PackedByteArray()) -> void:
	_relax(g, hm, lock, -1)
	_relax(g, hm, lock, 1)


static func _relax(g: VoxelGrid, hm: PackedInt32Array, lock: PackedByteArray, dir: int) -> void:
	var sx := g.size.x
	var sz := g.size.z
	var changed := true
	while changed:
		changed = false
		for z in sz:
			for x in sx:
				var i := z * sx + x
				if not lock.is_empty() and lock[i] != 0:
					continue
				var m := hm[i]
				if dir > 0:
					if x > 0: m = maxi(m, hm[i - 1] - 1)
					if x < sx - 1: m = maxi(m, hm[i + 1] - 1)
					if z > 0: m = maxi(m, hm[i - sx] - 1)
					if z < sz - 1: m = maxi(m, hm[i + sx] - 1)
				else:
					if x > 0: m = mini(m, hm[i - 1] + 1)
					if x < sx - 1: m = mini(m, hm[i + 1] + 1)
					if z > 0: m = mini(m, hm[i - sx] + 1)
					if z < sz - 1: m = mini(m, hm[i + sx] + 1)
				if m != hm[i]:
					hm[i] = m
					changed = true


## Replaces the top block of every column in the rectangle (cubes and ramps).
static func paint_top(g: VoxelGrid, hm: PackedInt32Array, x0: int, z0: int, x1: int, z1: int, block: int) -> void:
	for z in range(maxi(z0, 0), mini(z1, g.size.z - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, g.size.x - 1) + 1):
			var h := hm[z * g.size.x + x]
			g.blocks[g.index(x, h - 1, z)] = block
			if g.get_shape(x, h, z) != G.CUBE:
				g.blocks[g.index(x, h, z)] = block


## Adds a spawn near (x, z): the nearest column within 5 cells whose terrain
## floor (`hm`, or explicit `y`) is standable with 3 cells of headroom.
static func spawn(g: VoxelGrid, hm: PackedInt32Array, info: MapInfo, x: int, z: int, y := -1) -> void:
	var p := _find_floor(g, hm, x, z, y)
	if p.x < 0:
		push_error("MapKit: no spawn floor near %d,%d" % [x, z])
		return
	info.spawns.append(Vector3(p.x + 0.5, p.y, p.z + 0.5))


static func pickup(g: VoxelGrid, hm: PackedInt32Array, info: MapInfo, kind: String, x: int, z: int, y := -1) -> void:
	var p := _find_floor(g, hm, x, z, y)
	if p.x < 0:
		push_error("MapKit: no pickup floor near %d,%d" % [x, z])
		return
	info.pickups.append({"kind": kind, "pos": Vector3(p.x + 0.5, p.y, p.z + 0.5)})


static func _find_floor(g: VoxelGrid, hm: PackedInt32Array, x: int, z: int, y: int) -> Vector3i:
	for r in 6:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var cx := x + dx
				var cz := z + dz
				if cx < 1 or cz < 1 or cx >= g.size.x - 1 or cz >= g.size.z - 1:
					continue
				var cy := y if y >= 0 else hm[cz * g.size.x + cx]
				if not g.standable(cx, cy, cz):
					continue
				# Keep a cell of clearance from walls so the capsule fits.
				var ok := true
				for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					if not g.is_air(cx + d.x, cy, cz + d.z) and g.get_shape(cx + d.x, cy, cz + d.z) == G.CUBE:
						ok = false
				if ok:
					return Vector3i(cx, cy, cz)
	return Vector3i(-1, -1, -1)


## Broad-leaf tree standing on floor height `y`.
static func oak(g: VoxelGrid, x: int, y: int, z: int, rng: RandomNumberGenerator) -> void:
	var trunk := rng.randi_range(5, 6)
	var top := y + trunk
	for dy in range(-2, 2):
		var r := 2 if dy < 0 else 1
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r and (dy >= 0 or rng.randf() < 0.6):
					continue
				if g.is_air(x + dx, top + dy, z + dz):
					g.set_block(x + dx, top + dy, z + dz, B.LEAVES)
	for dy in trunk:
		g.set_block(x, y + dy, z, B.LOG)


## Conical pine of `height` logs; snowy pines get snow-capped needles.
static func pine(g: VoxelGrid, x: int, y: int, z: int, height: int, snowy: bool) -> void:
	var top := y + height
	for layer in range(height - 2):
		var ly := top - layer
		var r := mini((layer + 1) / 2, 3)
		if layer >= 2 and layer % 2 == 0:
			r = maxi(r - 1, 1)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) + absi(dz) > r + (1 if r >= 2 else 0):
					continue
				if g.is_air(x + dx, ly, z + dz):
					g.set_block(x + dx, ly, z + dz, B.PINE_SNOW if snowy else B.PINE)
	g.set_block(x, top + 1, z, B.PINE_SNOW if snowy else B.PINE)
	for dy in height:
		g.set_block(x, y + dy, z, B.LOG)


## Pitched roof of ramps over the inclusive footprint, ridge along X when
## `along_x`, starting at height `y`, with gable walls of `gable`.
static func gable_roof(g: VoxelGrid, x0: int, z0: int, x1: int, z1: int, y: int, along_x: bool, roof: int, gable: int) -> void:
	var span := (z1 - z0 + 1) if along_x else (x1 - x0 + 1)
	var half := span / 2
	for k in half:
		var ry := y + k
		if along_x:
			for x in range(x0, x1 + 1):
				g.set_ramp(x, ry, z0 + k, G.RAMP_PZ, roof)
				g.set_ramp(x, ry, z1 - k, G.RAMP_NZ, roof)
			g.fill(Vector3i(x0 + 1, ry, z0 + k + 1), Vector3i(x0 + 1, ry, z1 - k - 1), gable)
			g.fill(Vector3i(x1 - 1, ry, z0 + k + 1), Vector3i(x1 - 1, ry, z1 - k - 1), gable)
		else:
			for z in range(z0, z1 + 1):
				g.set_ramp(x0 + k, ry, z, G.RAMP_PX, roof)
				g.set_ramp(x1 - k, ry, z, G.RAMP_NX, roof)
			g.fill(Vector3i(x0 + k + 1, ry, z0 + 1), Vector3i(x1 - k - 1, ry, z0 + 1), gable)
			g.fill(Vector3i(x0 + k + 1, ry, z1 - 1), Vector3i(x1 - k - 1, ry, z1 - 1), gable)
	if span % 2 == 1:
		if along_x:
			g.fill(Vector3i(x0, y + half, z0 + half), Vector3i(x1, y + half, z0 + half), roof)
		else:
			g.fill(Vector3i(x0 + half, y + half, z0), Vector3i(x0 + half, y + half, z1), roof)


## Clears an opening (door/window) in a wall.
static func opening(g: VoxelGrid, a: Vector3i, b: Vector3i, block := B.AIR) -> void:
	g.fill(a, b, block)


## Low wall of `block` along a line (cover), from `a` to `b` inclusive at floor y.
static func low_wall(g: VoxelGrid, a: Vector3i, b: Vector3i, height: int, block: int) -> void:
	g.fill(a, b + Vector3i(0, height - 1, 0), block)


# --- symmetric placement ------------------------------------------------------

const XF_NONE := 0
const XF_ROT180 := 1 ## rotate 180 degrees about the grid centre
const XF_MIRROR_X := 2 ## mirror across the grid's centre line x = size.x / 2


static func xf(g: VoxelGrid, mode: int, x: int, y: int, z: int) -> Vector3i:
	match mode:
		XF_ROT180: return Vector3i(g.size.x - 1 - x, y, g.size.z - 1 - z)
		XF_MIRROR_X: return Vector3i(g.size.x - 1 - x, y, z)
	return Vector3i(x, y, z)


static func xf_facing(mode: int, facing: int) -> int:
	const SWAP_X: Array[int] = [0, 2, 1, 3, 4]
	const SWAP_XZ: Array[int] = [0, 2, 1, 4, 3]
	match mode:
		XF_ROT180: return SWAP_XZ[facing]
		XF_MIRROR_X: return SWAP_X[facing]
	return facing


static func box(g: VoxelGrid, mode: int, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, block: int) -> void:
	g.fill(xf(g, mode, x0, y0, z0), xf(g, mode, x1, y1, z1), block)


static func put(g: VoxelGrid, mode: int, x: int, y: int, z: int, block: int) -> void:
	var p := xf(g, mode, x, y, z)
	g.set_block(p.x, p.y, p.z, block)


## VoxelGrid.ramp_run through a placement transform.
static func ramp(g: VoxelGrid, mode: int, start: Vector3i, facing: int, length: int, width: int, block: int, support: int) -> void:
	var dir := G.FACING_DIR[facing]
	var side := G.FACING_SIDE[facing]
	var f := xf_facing(mode, facing)
	for i in length:
		for w in width:
			var c := start + dir * i + side * w + Vector3i(0, i, 0)
			var p := xf(g, mode, c.x, c.y, c.z)
			g.set_ramp(p.x, p.y, p.z, f, block)
			if i > 0:
				g.fill(Vector3i(p.x, start.y, p.z), Vector3i(p.x, p.y - 1, p.z), support)
			for h in range(1, 4):
				if g.get_shape(p.x, p.y + h, p.z) == G.CUBE:
					g.set_block(p.x, p.y + h, p.z, B.AIR)
