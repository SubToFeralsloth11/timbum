class_name LaserSight
extends Node3D
## Visible beam and dot of the Laser Sight attachment. Lives in world space (top level): each
## frame the owner calls aim() with where the beam leaves the gun and the aim direction, and
## the beam runs to whatever the aim ray hits (or RANGE), with a glowing dot there.

const RANGE := 80.0
## Hits the world and hitboxes, like a shot.
const MASK := 1 | 4

static var _beam_mat: StandardMaterial3D
static var _dot_mat: StandardMaterial3D

var _beam: MeshInstance3D
var _dot: MeshInstance3D


func _init() -> void:
	top_level = true
	name = "LaserSight"
	if _beam_mat == null:
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.albedo_color = Color(1.0, 0.12, 0.08, 0.35)
		_beam_mat.disable_receive_shadows = true
		_dot_mat = StandardMaterial3D.new()
		_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dot_mat.albedo_color = Color(1.0, 0.2, 0.15)
		_dot_mat.emission_enabled = true
		_dot_mat.emission = Color(1.0, 0.15, 0.1)
		_dot_mat.emission_energy_multiplier = 3.0
		_dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_beam = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.006, 0.006, 1.0)
	_beam.mesh = box
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_dot = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	_dot.mesh = quad
	_dot.material_override = _dot_mat
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dot)


## `from`: where the beam leaves the gun; the beam ends where the ray from `eye` along `dir`
## hits, so it meets the crosshair. `show_beam` false leaves only the dot (scoped in).
func aim(from: Vector3, eye: Vector3, dir: Vector3, exclude: Array[RID], show_beam := true) -> void:
	visible = true
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * RANGE, MASK, exclude)
	q.collide_with_areas = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = r.position if not r.is_empty() else eye + dir * RANGE
	_dot.visible = not r.is_empty()
	if _dot.visible:
		_dot.global_position = end - dir * 0.03
	var span := end - from
	var length := span.length()
	_beam.visible = show_beam and length > 0.05
	if _beam.visible:
		var mid := from + span * 0.5
		var fwd := span / length
		var up := Vector3.RIGHT if absf(fwd.y) > 0.99 else Vector3.UP
		_beam.global_transform = Transform3D(Basis.looking_at(fwd, up).scaled(Vector3(1.0, 1.0, length)), mid)
