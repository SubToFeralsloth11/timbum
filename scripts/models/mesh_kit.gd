class_name MeshKit
extends RefCounted
## Accumulates boxes into one ArrayMesh with one surface per integer material slot.
## Boxes get either planar UVs (metres / UV_TILE, so tiling pixel textures keep a constant
## texel density across parts) or explicit pixel rectangles of a texture atlas.
## Build-time only: results are meant to be cached and shared.

const UV_TILE := 0.32

## Per face: outward normal, then corner signs TL, TR, BR, BL as seen from outside the box,
## then the image-right and image-up axes. Order: front (-Z), back (+Z), right (+X),
## left (-X), top (+Y, image top = -Z), bottom (-Y, image top = +Z).
const FACES := [
	[Vector3(0, 0, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, -1, 1), Vector3(-1, -1, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(1, 0, 0), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)],
]


class _Surface:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()


var _surfaces: Dictionary = {}


## Adds a box in `slot`. `rot` is Euler radians (YXZ) around the box centre.
func box(slot: int, center: Vector3, size: Vector3, rot := Vector3.ZERO) -> MeshKit:
	var basis := Basis.from_euler(rot)
	var half := size * 0.5
	var corners: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var uv: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	for face: Array in FACES:
		var right: Vector3 = face[5]
		var up: Vector3 = face[6]
		for c in 4:
			var local: Vector3 = (face[1 + c] as Vector3) * half
			var p := center + local
			uv[c] = Vector2(p.dot(right), -p.dot(up)) / UV_TILE
			corners[c] = center + basis * local
		_quad(slot, corners, basis * (face[0] as Vector3), uv)
	return self


## Adds an axis-aligned box whose six faces map to pixel rectangles of an atlas
## (`rects` in MeshKit.FACES order, image left/top as seen from outside).
func atlas_box(slot: int, center: Vector3, size: Vector3, rects: Array[Rect2], atlas_size: Vector2) -> MeshKit:
	var half := size * 0.5
	var corners: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for f in 6:
		var face: Array = FACES[f]
		for c in 4:
			corners[c] = center + (face[1 + c] as Vector3) * half
		var r := rects[f]
		var uv: Array[Vector2] = [
			r.position / atlas_size,
			Vector2(r.end.x, r.position.y) / atlas_size,
			r.end / atlas_size,
			Vector2(r.position.x, r.end.y) / atlas_size,
		]
		_quad(slot, corners, face[0], uv)
	return self


## Builds the mesh. `materials[slot]` (when present and non-null) becomes the surface material.
## Surfaces are emitted in ascending slot order, so slot 0 (if used) is surface 0.
func build(materials: Array = []) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var slots := _surfaces.keys()
	slots.sort()
	for slot: int in slots:
		var s: _Surface = _surfaces[slot]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if slot < materials.size() and materials[slot] != null:
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[slot])
	return mesh


# Godot treats clockwise triangles (as seen by the viewer) as front faces.
func _quad(slot: int, c: Array[Vector3], n: Vector3, uv: Array[Vector2]) -> void:
	var s: _Surface = _surfaces.get(slot)
	if s == null:
		s = _Surface.new()
		_surfaces[slot] = s
	for i: int in [0, 1, 2, 0, 2, 3]:
		s.verts.append(c[i])
		s.normals.append(n)
		s.uvs.append(uv[i])
