class_name WeaponPickup
extends Node3D
## A Tactical weapon spot: the gun lying there turns slowly over a small team-neutral pad, with
## its name above it up close. Empty spots ("") show nothing. The server decides who takes it
## (Tactical._server_pickups / interact).

## Past this distance the gun and its label are not drawn (60+ of them fill the building).
const DRAW_DISTANCE := 32.0
const LABEL_DISTANCE := 9.0

var wid := ""
var _gun: Node3D
var _label: Label3D
var _pad: MeshInstance3D
var _t := 0.0

static var _pad_mesh: CylinderMesh


func _ready() -> void:
	_t = randf() * TAU
	if _pad_mesh == null:
		_pad_mesh = CylinderMesh.new()
		_pad_mesh.top_radius = 0.45
		_pad_mesh.bottom_radius = 0.5
		_pad_mesh.height = 0.04
		_pad_mesh.radial_segments = 8
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.17, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(0.85, 0.85, 0.6)
		mat.emission_energy_multiplier = 0.35
		_pad_mesh.material = mat
	_pad = MeshInstance3D.new()
	_pad.mesh = _pad_mesh
	_pad.position.y = 0.02
	_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pad.visibility_range_end = DRAW_DISTANCE
	add_child(_pad)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.outline_size = 10
	_label.pixel_size = 0.005
	_label.modulate = Color(1.0, 0.92, 0.6)
	_label.position.y = 1.0
	_label.visibility_range_end = LABEL_DISTANCE
	add_child(_label)
	_apply()


func set_weapon(p_wid: String) -> void:
	if p_wid == wid and (_gun != null or wid.is_empty()):
		return
	wid = p_wid
	if is_node_ready():
		_apply()


func _apply() -> void:
	if _gun != null:
		_gun.queue_free()
		_gun = null
	visible = not wid.is_empty()
	set_process(visible)
	if wid.is_empty():
		return
	_gun = Models.build_gun(wid, "default")
	_gun.position.y = 0.35
	_gun.rotation.z = deg_to_rad(8.0)
	for g: GeometryInstance3D in _gun.find_children("*", "GeometryInstance3D", true, false):
		g.visibility_range_end = DRAW_DISTANCE
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_gun)
	_label.text = str(Data.WEAPONS[wid].name).to_upper()


func _process(delta: float) -> void:
	_t += delta
	_gun.rotation.y = _t * 0.9
	_gun.position.y = 0.35 + sin(_t * 1.8) * 0.05
