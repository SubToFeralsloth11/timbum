class_name VoxelMesher
extends RefCounted
## Turns a VoxelGrid into chunked MeshInstance3D nodes (opaque + glass
## surfaces, atlas layers in UV2.x, emission in UV2.y, ambient occlusion in
## vertex colours) and per-chunk trimesh StaticBody3D collision on layer 1.

const CHUNK := 16
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

	func clear() -> void:
		verts.clear()
		normals.clear()
		uvs.clear()
		uv2s.clear()
		colors.clear()
		indices.clear()

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


## Builds every chunk of `g` under `parent`, with grid cell (0,0,0) at
## `origin` (parent space). Collision faces are also added to `nav_source`
## using `nav_xform` (parent's global transform).
static func build(g: VoxelGrid, parent: Node3D, origin: Vector3, nav_source: NavigationMeshSourceGeometryData3D, nav_xform: Transform3D) -> void:
	var m := VoxelMesher.new()
	m._prepare(g)
	var opaque_mat := BlockAtlas.material(false)
	var glass_mat := BlockAtlas.material(true)
	for cz in range(0, g.size.z, CHUNK):
		for cx in range(0, g.size.x, CHUNK):
			m._mesh_chunk(g, cx, cz)
			if m._coll.is_empty():
				continue
			var mesh := ArrayMesh.new()
			if not m._opaque.indices.is_empty():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m._opaque.arrays())
				mesh.surface_set_material(mesh.get_surface_count() - 1, opaque_mat)
			if not m._glass.indices.is_empty():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m._glass.arrays())
				mesh.surface_set_material(mesh.get_surface_count() - 1, glass_mat)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx / CHUNK, cz / CHUNK]
			mi.mesh = mesh
			mi.position = origin + Vector3(cx, 0, cz)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(m._coll)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			mi.add_child(body)
			parent.add_child(mi)
			nav_source.add_faces(m._coll, nav_xform * mi.transform)


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


func _mesh_chunk(g: VoxelGrid, cx: int, cz: int) -> void:
	_opaque.clear()
	_glass.clear()
	_coll.clear()
	var x1 := mini(cx + CHUNK, g.size.x)
	var z1 := mini(cz + CHUNK, g.size.z)
	for y in g.size.y:
		for z in range(cz, z1):
			var i := (y + 1) * _pxz + (z + 1) * _px + cx + 1
			for x in range(cx, x1):
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
