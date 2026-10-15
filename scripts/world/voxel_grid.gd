class_name VoxelGrid
extends RefCounted
## Dense block volume. Cell (x, y, z) spans [x, x+1] x [y, y+1] x [z, z+1]
## in grid space. Every cell has a block id (BlockAtlas constants) and a
## shape: a full cube or a 45 degree ramp rising toward one of four facings.
## Also hosts the deterministic building helpers the map generators share.

const CUBE := 0
const RAMP_PX := 1 ## rises toward +X
const RAMP_NX := 2 ## rises toward -X
const RAMP_PZ := 3 ## rises toward +Z
const RAMP_NZ := 4 ## rises toward -Z
const FACING_DIR: Array[Vector3i] = [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
## Facing whose rise direction is perpendicular-positive (for ramp widths).
const FACING_SIDE: Array[Vector3i] = [Vector3i.ZERO, Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0)]

var size: Vector3i
var blocks := PackedByteArray()
var shapes := PackedByteArray()


func _init(grid_size: Vector3i) -> void:
	size = grid_size
	blocks.resize(size.x * size.y * size.z)
	shapes.resize(blocks.size())


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < size.x and y < size.y and z < size.z


func index(x: int, y: int, z: int) -> int:
	return (y * size.z + z) * size.x + x


func get_block(x: int, y: int, z: int) -> int:
	return blocks[index(x, y, z)] if in_bounds(x, y, z) else BlockAtlas.AIR


func get_shape(x: int, y: int, z: int) -> int:
	return shapes[index(x, y, z)] if in_bounds(x, y, z) else CUBE


func is_air(x: int, y: int, z: int) -> bool:
	return get_block(x, y, z) == BlockAtlas.AIR


## Full solid cube (something you can stand on flat).
func is_cube(x: int, y: int, z: int) -> bool:
	return get_block(x, y, z) != BlockAtlas.AIR and get_shape(x, y, z) == CUBE


func set_block(x: int, y: int, z: int, block: int) -> void:
	if in_bounds(x, y, z):
		var i := index(x, y, z)
		blocks[i] = block
		shapes[i] = CUBE


func set_ramp(x: int, y: int, z: int, facing: int, block: int) -> void:
	if in_bounds(x, y, z):
		var i := index(x, y, z)
		blocks[i] = block
		shapes[i] = facing


## Fills the inclusive box between `a` and `b` (any corner order).
func fill(a: Vector3i, b: Vector3i, block: int) -> void:
	var lo := Vector3i(maxi(mini(a.x, b.x), 0), maxi(mini(a.y, b.y), 0), maxi(mini(a.z, b.z), 0))
	var hi := Vector3i(mini(maxi(a.x, b.x), size.x - 1), mini(maxi(a.y, b.y), size.y - 1), mini(maxi(a.z, b.z), size.z - 1))
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			var i := index(lo.x, y, z)
			for x in range(lo.x, hi.x + 1):
				blocks[i] = block
				shapes[i] = CUBE
				i += 1


func clear(a: Vector3i, b: Vector3i) -> void:
	fill(a, b, BlockAtlas.AIR)


## The four side walls of the inclusive box (no floor or ceiling).
func walls(a: Vector3i, b: Vector3i, block: int) -> void:
	fill(Vector3i(a.x, a.y, a.z), Vector3i(b.x, b.y, a.z), block)
	fill(Vector3i(a.x, a.y, b.z), Vector3i(b.x, b.y, b.z), block)
	fill(Vector3i(a.x, a.y, a.z), Vector3i(a.x, b.y, b.z), block)
	fill(Vector3i(b.x, a.y, a.z), Vector3i(b.x, b.y, b.z), block)


## A straight ramp flight. `start` is the lowest ramp cell (its floor height is
## start.y); each step moves one cell along `facing` and one up. `width` cells
## extend along FACING_SIDE. Cells under each ramp are filled with `support`
## down to `start.y`, and two cells of headroom above are cleared.
func ramp_run(start: Vector3i, facing: int, length: int, width: int, block: int, support: int) -> void:
	var dir := FACING_DIR[facing]
	var side := FACING_SIDE[facing]
	for i in length:
		for w in width:
			var p := start + dir * i + side * w + Vector3i(0, i, 0)
			set_ramp(p.x, p.y, p.z, facing, block)
			for y in range(start.y, p.y):
				set_block(p.x, y, p.z, support)
			for h in range(1, 4):
				if get_shape(p.x, p.y + h, p.z) == CUBE:
					set_block(p.x, p.y + h, p.z, BlockAtlas.AIR)


## Highest y whose cell is air with a full cube below and `headroom` air cells
## (including itself), or -1.
func surface(x: int, z: int, headroom := 3) -> int:
	for y in range(size.y - 1, 0, -1):
		if is_cube(x, y - 1, z) and standable(x, y, z, headroom):
			return y
	return -1


func standable(x: int, y: int, z: int, headroom := 3) -> bool:
	if not is_cube(x, y - 1, z):
		return false
	for h in headroom:
		if not is_air(x, y + h, z):
			return false
	return true


## Lays out a terrain from a height map (`hm[z * size.x + x]` = number of
## solid cells in that column): `top` on the surface, `sub` for `sub_depth`
## cells beneath, `deep` below.
func apply_heightmap(hm: PackedInt32Array, top: int, sub: int, deep: int, sub_depth := 3) -> void:
	for z in size.z:
		for x in size.x:
			var h := hm[z * size.x + x]
			for y in mini(h, size.y):
				var b := deep
				if y == h - 1:
					b = top
				elif y >= h - 1 - sub_depth:
					b = sub
				var i := index(x, y, z)
				blocks[i] = b
				shapes[i] = CUBE


## Turns every one-block terrain step into a walkable ramp: a column that is
## exactly one lower than a neighbour gets a ramp facing that neighbour.
func auto_ramps(hm: PackedInt32Array, block: int) -> void:
	for z in size.z:
		for x in size.x:
			var h := hm[z * size.x + x]
			if h <= 0 or h >= size.y - 3 or not is_air(x, h, z):
				continue
			for facing in range(1, 5):
				var d := FACING_DIR[facing]
				var nx := x + d.x
				var nz := z + d.z
				if nx < 0 or nz < 0 or nx >= size.x or nz >= size.z:
					continue
				if hm[nz * size.x + nx] == h + 1:
					set_ramp(x, h, z, facing, block)
					break


## Deterministic integer hash in [0, 1).
static func hash01(x: int, z: int, seed: int) -> float:
	var h := (x * 374761393 + z * 668265263 + seed * 2147483647) & 0xffffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / 16777216.0


## Smooth value noise in [0, 1), deterministic across platforms.
static func noise2(x: float, z: float, seed: int) -> float:
	var x0 := floori(x)
	var z0 := floori(z)
	var fx := x - x0
	var fz := z - z0
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := lerpf(hash01(x0, z0, seed), hash01(x0 + 1, z0, seed), fx)
	var b := lerpf(hash01(x0, z0 + 1, seed), hash01(x0 + 1, z0 + 1, seed), fx)
	return lerpf(a, b, fz)
