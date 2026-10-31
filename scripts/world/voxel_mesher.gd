class_name VoxelMesher
extends RefCounted
## Turns a VoxelGrid into chunked MeshInstance3D nodes (opaque + glass
## surfaces, atlas layers in UV2.x, emission in UV2.y, ambient occlusion in
## vertex colours) and per-chunk trimesh StaticBody3D collision on layer 1.
## An `editable` build keeps the mesher (padded grid copy, chunk nodes and their collision
## triangles) so blocks can be removed later (Demolition): `clear_cells`, then
## `snapshot().mesh_chunks` on a worker thread, then `apply_chunk` on the main thread. Its
## collision is split into one body per SUB x SUB column of a chunk, and only the parts whose
## triangles changed are rebuilt (Jolt builds a trimesh at about 1 us per triangle on assignment).

const CHUNK := 16
## Editable builds: side (cells) of the collision parts a chunk is split into.
const SUB := 4
## Brightness for 0..3 unoccluded neighbours (classic voxel AO).
const AO_CURVE: Array[float] = [0.42, 0.63, 0.82, 1.0]

# Face directions: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z.
const _N: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const _T1: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 0)]
const _T2: Array[Vector3i] = [Vector3i(0, 1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(0, 1, 0)]
const _SIGNS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
## Ramp facing (1..4) -> face direction of its high (back) side.
const _FACING_FACE: Array[int] = [-1, 0, 1, 4, 5]
const _OPPOSITE_FACING: Array[int] = [0, 2, 1, 4, 3]
const _TRI: Array[int] = [0, 1, 2]
const _QUAD_A: Array[int] = [0, 1, 2, 0, 2, 3]
const _QUAD_B: Array[int] = [1, 2, 3, 1, 3, 0]


class Surface:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = normals
		a[Mesh.ARRAY_TEX_UV] = uvs
		a[Mesh.ARRAY_TEX_UV2] = uv2s
		a[Mesh.ARRAY_COLOR] = colors
		a[Mesh.ARRAY_INDEX] = indices
		return a


# Padded copies of the grid (one extra cell on each side) so neighbour
# lookups never need bounds checks. Padding is solid below and around, air above.
var _pb := PackedByteArray()
var _ps := PackedByteArray()
var _px := 0
var _pxz := 0
var _layers := PackedInt32Array()
var _noff := PackedInt32Array()
var _corner := PackedVector3Array()
var _uv := PackedVector2Array()
var _ao_off := PackedInt32Array()
var _rev: Array[bool] = []
var _opaque := Surface.new()
var _glass := Surface.new()
var _coll := PackedVector3Array()
## Where each SUB-column part's triangles start in _coll (plus the end), from _mesh_chunk.
var _sub_start := PackedInt32Array()
## Editable builds, by chunk key Vector2i(cx / CHUNK, cz / CHUNK): its MeshInstance3D, its
## collision triangles in chunk space (navmesh rebakes), and per collision part (SUB-column,
## row-major in z then x) the part's triangles and its CollisionShape3D (null when it has none).
var chunks := {}
var faces := {}
var part_faces := {}
var part_shapes := {}
var _grid: VoxelGrid
## Editable builds: apply_chunk also creates a chunk that had no node (the Map Editor, which adds
## blocks to empty chunks); Demolition only removes blocks and leaves it off.
var grow_chunks := false
var _parent: Node3D
var _origin := Vector3.ZERO


## Builds every chunk of `g` under `parent`, with grid cell (0,0,0) at
## `origin` (parent space). Collision faces are also added to `nav_source`
## using `nav_xform` (parent's global transform). A null `nav_source` builds meshes only (no
## collision bodies: the menu backdrop), and `keep_chunk(cx, cz)` (grid cells of the chunk's
## corner), when given, skips the chunks it returns false for. `editable` keeps what
## clear_cells / mesh_chunks / apply_chunk need (and `g` itself, which they change) and splits the
## collision into SUB-column parts; keep the returned mesher.
static func build(g: VoxelGrid, parent: Node3D, origin: Vector3, nav_source: NavigationMeshSourceGeometryData3D, nav_xform: Transform3D, keep_chunk := Callable(), editable := false) -> VoxelMesher:
	var m := VoxelMesher.new()
	m._prepare(g)
	for cz in range(0, g.size.z, CHUNK):
		for cx in range(0, g.size.x, CHUNK):
			if keep_chunk.is_valid() and not keep_chunk.call(cx, cz):
				continue
			m._mesh_chunk(g, cx, cz, SUB if editable else CHUNK)
			if m._coll.is_empty():
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx / CHUNK, cz / CHUNK]
			mi.mesh = _chunk_mesh(_arrays_of(m._opaque), _arrays_of(m._glass))
			mi.position = origin + Vector3(cx, 0, cz)
			parent.add_child(mi)
			if nav_source == null:
				continue
			nav_source.add_faces(m._coll, nav_xform * mi.transform)
			if not editable:
				_add_body(mi, m._coll)
				continue
			var key := Vector2i(cx / CHUNK, cz / CHUNK)
			m.chunks[key] = mi
			m.faces[key] = m._coll
			var parts := []
			var shapes := []
			for k in m._sub_start.size() - 1:
				var part := m._coll.slice(m._sub_start[k], m._sub_start[k + 1])
				parts.append(part)
				shapes.append(null if part.is_empty() else _add_body(mi, part))
			m.part_faces[key] = parts
			m.part_shapes[key] = shapes
	if editable:
		m._grid = g
		m._parent = parent
		m._origin = origin
	return m


## A static trimesh body on layer 1 under `mi` with the triangles `tris`; returns its shape node.
static func _add_body(mi: MeshInstance3D, tris: PackedVector3Array) -> CollisionShape3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(tris)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)
	return cs


## A chunk's ArrayMesh from its opaque and glass surface arrays (Surface.arrays(), or [] when the
## chunk has no such faces).
static func _chunk_mesh(opaque: Array, glass: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not opaque.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, opaque)
		mesh.surface_set_material(mesh.get_surface_count() - 1, BlockAtlas.material(false))
	if not glass.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass)
		mesh.surface_set_material(mesh.get_surface_count() - 1, BlockAtlas.material(true))
	return mesh


static func _arrays_of(s: Surface) -> Array:
	return [] if s.indices.is_empty() else s.arrays()


## Editable builds: turns the grid cells `cells` (VoxelGrid.index values) into air in the grid and
## the padded copy, and adds to `dirty` (as keys) every chunk whose mesh that changes: the cells'
## own chunks and, for cells on a chunk border, the neighbour whose faces and AO they touch.
func clear_cells(cells: PackedInt32Array, dirty: Dictionary) -> void:
	var air := PackedByteArray()
	air.resize(cells.size())
	set_cells(cells, air, dirty)


## Editable builds: like clear_cells, but cell `cells[k]` becomes a full cube of block `values[k]`
## (AIR removes it).
func set_cells(cells: PackedInt32Array, values: PackedByteArray, dirty: Dictionary) -> void:
	var sx := _grid.size.x
	var sxz := sx * _grid.size.z
	for k in cells.size():
		var i := cells[k]
		var x := i % sx
		var z := (i / sx) % _grid.size.z
		var y := i / sxz
		_grid.blocks[i] = values[k]
		_grid.shapes[i] = VoxelGrid.CUBE
		var p := (y + 1) * _pxz + (z + 1) * _px + x + 1
		_pb[p] = values[k]
		_ps[p] = 0
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var nz := z + dz
				if nx >= 0 and nz >= 0 and nx < sx and nz < _grid.size.z:
					dirty[Vector2i(nx / CHUNK, nz / CHUNK)] = true


## Editable builds: a mesher sharing this one's (read-only) tables with its own copy of the padded
## grid, so later clear_cells calls here don't reach it. `mesh_chunks` on the snapshot is safe on
## a worker thread while this mesher keeps changing.
func snapshot() -> VoxelMesher:
	var s := VoxelMesher.new()
	s._px = _px
	s._pxz = _pxz
	# Packed arrays are shared by reference in GDScript: the worker gets its own copies.
	s._pb = _pb.duplicate()
	s._ps = _ps.duplicate()
	s._layers = _layers
	s._noff = _noff
	s._corner = _corner
	s._uv = _uv
	s._ao_off = _ao_off
	s._rev = _rev
	s._grid = _grid
	return s


## Meshes the chunks `keys` (Vector2i) from this mesher's padded grid: key -> [opaque surface
## arrays, glass surface arrays, collision triangles, where each SUB-column part's triangles start
## (plus the end)] for apply_chunk. Touches no nodes or servers.
func mesh_chunks(keys: Array) -> Dictionary:
	var out := {}
	for key: Vector2i in keys:
		_mesh_chunk(_grid, key.x * CHUNK, key.y * CHUNK, SUB)
		out[key] = [_arrays_of(_opaque), _arrays_of(_glass), _coll, _sub_start]
	return out


## Editable builds, main thread: swaps in chunk `key`'s new mesh from mesh_chunks' `data` and
## rebuilds the collision parts whose triangles changed (a chunk left with no faces is freed).
## Returns how many parts it rebuilt. Chunks that never had a node stay empty unless
## `grow_chunks` is set: removing blocks only takes faces away from, or exposes faces inside,
## built chunks.
func apply_chunk(key: Vector2i, data: Array) -> int:
	var mi: MeshInstance3D = chunks.get(key)
	var coll: PackedVector3Array = data[2]
	if mi == null:
		if not grow_chunks or coll.is_empty():
			return 0
		mi = MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [key.x, key.y]
		mi.position = _origin + Vector3(key.x * CHUNK, 0, key.y * CHUNK)
		_parent.add_child(mi)
		chunks[key] = mi
		var empty_parts := []
		var no_shapes := []
		for k in (data[3] as PackedInt32Array).size() - 1:
			empty_parts.append(PackedVector3Array())
			no_shapes.append(null)
		part_faces[key] = empty_parts
		part_shapes[key] = no_shapes
	if coll.is_empty():
		chunks.erase(key)
		faces.erase(key)
		part_faces.erase(key)
		part_shapes.erase(key)
		mi.queue_free()
		return 0
	mi.mesh = _chunk_mesh(data[0], data[1])
	faces[key] = coll
	var starts: PackedInt32Array = data[3]
	var parts: Array = part_faces[key]
	var shapes: Array = part_shapes[key]
	var rebuilt := 0
	for k in parts.size():
		var part := coll.slice(starts[k], starts[k + 1])
		if part == parts[k]:
			continue
		parts[k] = part
		rebuilt += 1
		var cs: CollisionShape3D = shapes[k]
		if part.is_empty():
			if cs != null:
				cs.get_parent().queue_free()
				shapes[k] = null
		elif cs == null:
			shapes[k] = _add_body(mi, part)
		else:
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(part)
			cs.shape = shape
	return rebuilt


func _prepare(g: VoxelGrid) -> void:
	_px = g.size.x + 2
	var pz := g.size.z + 2
	_pxz = _px * pz
	var solid_row := PackedByteArray()
	solid_row.resize(_px)
	solid_row.fill(BlockAtlas.STONE)
	var solid_layer := PackedByteArray()
	solid_layer.resize(_pxz)
	solid_layer.fill(BlockAtlas.STONE)
	var zero_row := PackedByteArray()
	zero_row.resize(_px)
	var zero_layer := PackedByteArray()
	zero_layer.resize(_pxz)
	var stone := PackedByteArray([BlockAtlas.STONE])
	var zero := PackedByteArray([0])
	_pb = solid_layer.duplicate()
	_ps = zero_layer.duplicate()
	for y in g.size.y:
		_pb.append_array(solid_row)
		_ps.append_array(zero_row)
		for z in g.size.z:
			var i := g.index(0, y, z)
			_pb.append_array(stone)
			_pb.append_array(g.blocks.slice(i, i + g.size.x))
			_pb.append_array(stone)
			_ps.append_array(zero)
			_ps.append_array(g.shapes.slice(i, i + g.size.x))
			_ps.append_array(zero)
		_pb.append_array(solid_row)
		_ps.append_array(zero_row)
	_pb.append_array(zero_layer)
	_ps.append_array(zero_layer)

	_layers = BlockAtlas.face_layers()
	_noff.resize(6)
	_corner.resize(24)
	_uv.resize(24)
	_ao_off.resize(72)
	_rev.resize(6)
	for d in 6:
		var n := _N[d]
		var t1 := _T1[d]
		var t2 := _T2[d]
		_noff[d] = _offset(n)
		for k in 4:
			var s := _SIGNS[k]
			var p := Vector3(0.5, 0.5, 0.5) + Vector3(n) * 0.5 + Vector3(t1) * (0.5 * s.x) + Vector3(t2) * (0.5 * s.y)
			_corner[d * 4 + k] = p
			var uv: Vector2
			match d:
				0: uv = Vector2(1.0 - p.z, 1.0 - p.y)
				1: uv = Vector2(p.z, 1.0 - p.y)
				4: uv = Vector2(p.x, 1.0 - p.y)
				5: uv = Vector2(1.0 - p.x, 1.0 - p.y)
				_: uv = Vector2(p.x, p.z)
			_uv[d * 4 + k] = uv
			_ao_off[(d * 4 + k) * 3] = _offset(t1 * s.x)
			_ao_off[(d * 4 + k) * 3 + 1] = _offset(t2 * s.y)
			_ao_off[(d * 4 + k) * 3 + 2] = _offset(t1 * s.x + t2 * s.y)
		# Godot treats clockwise triangles (seen from the front) as front faces.
		var c0 := _corner[d * 4]
		var cr := (_corner[d * 4 + 1] - c0).cross(_corner[d * 4 + 2] - c0)
		_rev[d] = cr.dot(Vector3(n)) > 0.0


func _offset(v: Vector3i) -> int:
	return v.x + v.z * _px + v.y * _pxz


## Meshes the chunk at grid cells (cx, cz) into _opaque, _glass and _coll, one `sub` x `sub`
## column at a time (z rows, then x), recording where each column's triangles start in _sub_start.
## Each call starts fresh buffers (packed arrays are shared by reference, and callers keep the
## previous chunk's).
func _mesh_chunk(g: VoxelGrid, cx: int, cz: int, sub: int) -> void:
	_opaque = Surface.new()
	_glass = Surface.new()
	_coll = PackedVector3Array()
	_sub_start = PackedInt32Array()
	var x1 := mini(cx + CHUNK, g.size.x)
	var z1 := mini(cz + CHUNK, g.size.z)
	for sz in range(cz, z1, sub):
		for sx in range(cx, x1, sub):
			_sub_start.append(_coll.size())
			var sx1 := mini(sx + sub, x1)
			var sz1 := mini(sz + sub, z1)
			for y in g.size.y:
				for z in range(sz, sz1):
					var i := (y + 1) * _pxz + (z + 1) * _px + sx + 1
					for x in range(sx, sx1):
						var b := _pb[i]
						if b != 0:
							var cell := Vector3(x - cx, y, z - cz)
							var shape := _ps[i]
							if shape == VoxelGrid.CUBE:
								var surf := _glass if b == BlockAtlas.GLASS else _opaque
								for d in 6:
									if _cube_face_visible(b, i + _noff[d], d):
										_face(surf, i, d, b, cell, -1, 0)
							else:
								_ramp(i, b, shape, cell)
						i += 1
	_sub_start.append(_coll.size())


func _cube_face_visible(b: int, j: int, d: int) -> bool:
	var nb := _pb[j]
	if nb == 0:
		return true
	if nb == BlockAtlas.GLASS:
		return b != BlockAtlas.GLASS
	var ns := _ps[j]
	if ns == VoxelGrid.CUBE:
		return false
	# A neighbouring ramp covers this face with its bottom or its back.
	return not (d == 2 or _FACING_FACE[ns] == (d ^ 1))


func _is_opaque_cube(j: int) -> bool:
	var q := _pb[j]
	return q != 0 and q != BlockAtlas.GLASS and _ps[j] == VoxelGrid.CUBE


func _ao(j: int, o: int) -> int:
	var q1 := _pb[j + _ao_off[o]]
	var q2 := _pb[j + _ao_off[o + 1]]
	var q3 := _pb[j + _ao_off[o + 2]]
	var s1 := 1 if q1 != 0 and q1 != BlockAtlas.GLASS else 0
	var s2 := 1 if q2 != 0 and q2 != BlockAtlas.GLASS else 0
	if s1 + s2 == 2:
		return 0
	var c := 1 if q3 != 0 and q3 != BlockAtlas.GLASS else 0
	return 3 - s1 - s2 - c


## Emits face `d` of cell `i`. `skip` drops one corner (ramp side triangles);
## `facing` > 0 bends the top face into a ramp slope rising toward that facing.
func _face(s: Surface, i: int, d: int, b: int, cell: Vector3, skip: int, facing: int) -> void:
	var tile := 0 if d == 2 else (2 if d == 3 else 1)
	var uv2 := Vector2(_layers[b * 3 + tile], BlockAtlas.emission(b))
	var normal := Vector3(_N[d])
	var rise := Vector3.ZERO
	if facing > 0:
		rise = Vector3(VoxelGrid.FACING_DIR[facing])
		normal = (Vector3.UP - rise).normalized()
	var j := i + _noff[d]
	var base := s.verts.size()
	var ao_diag := 0
	for k in 4:
		if k == skip:
			continue
		var ci := d * 4 + k
		var p := _corner[ci]
		var a: int
		if facing > 0 and (p - Vector3(0.5, 0.5, 0.5)).dot(rise) < 0.0:
			p.y = 0.0
			a = _ao(i, ci * 3)
		else:
			a = _ao(j, ci * 3)
		ao_diag += a if k % 2 == 0 else -a
		s.verts.append(cell + p)
		s.normals.append(normal)
		s.uvs.append(_uv[ci])
		s.uv2s.append(uv2)
		var l := AO_CURVE[a]
		s.colors.append(Color(l, l, l))
	# Split quads along the brighter diagonal so AO interpolates evenly.
	var tris := _TRI if skip >= 0 else (_QUAD_A if ao_diag >= 0 else _QUAD_B)
	var rev := _rev[d]
	for t in range(0, tris.size(), 3):
		var a0 := base + tris[t]
		var a1 := base + tris[t + 1]
		var a2 := base + tris[t + 2]
		if rev:
			var tmp := a1
			a1 = a2
			a2 = tmp
		s.indices.append(a0)
		s.indices.append(a1)
		s.indices.append(a2)
		_coll.append(s.verts[a0])
		_coll.append(s.verts[a1])
		_coll.append(s.verts[a2])


func _ramp(i: int, b: int, facing: int, cell: Vector3) -> void:
	var back := _FACING_FACE[facing]
	var rise := Vector3(VoxelGrid.FACING_DIR[facing])
	# Sloped top: the +Y face with its low edge dropped to the floor.
	_face(_opaque, i, 2, b, cell, -1, facing)
	if not _is_opaque_cube(i + _noff[3]):
		_face(_opaque, i, 3, b, cell, -1, 0)
	var j := i + _noff[back]
	if not (_is_opaque_cube(j) or (_pb[j] != 0 and _ps[j] == _OPPOSITE_FACING[facing])):
		_face(_opaque, i, back, b, cell, -1, 0)
	for d in 6:
		if d == 2 or d == 3 or d == back or d == (back ^ 1):
			continue
		j = i + _noff[d]
		if _is_opaque_cube(j) or (_pb[j] != 0 and _pb[j] != BlockAtlas.GLASS and _ps[j] == facing):
			continue
		# Side triangle: drop the corner that is high on the low side.
		var skip := 0
		for k in 4:
			var p := _corner[d * 4 + k]
			if p.y > 0.5 and (p - Vector3(0.5, 0.5, 0.5)).dot(rise) < 0.0:
				skip = k
		_face(_opaque, i, d, b, cell, skip, 0)
