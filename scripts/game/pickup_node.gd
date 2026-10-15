class_name PickupNode
extends Node3D
## Visual for a health/ammo/grenade pickup. The server decides who takes it (World._server_pickups).

var kind := "health"
var active := true
var _model: Node3D
var _light: OmniLight3D
var _t := 0.0
var _pop := 1.0


func setup(p_kind: String) -> void:
	kind = p_kind
	name = "Pickup_%s" % kind


func _ready() -> void:
	_t = randf() * TAU
	var pad := MeshInstance3D.new()
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.55
	pad_mesh.bottom_radius = 0.6
	pad_mesh.height = 0.06
	pad_mesh.radial_segments = 8
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = _color().darkened(0.4)
	pad_mat.emission_enabled = true
	pad_mat.emission = _color()
	pad_mat.emission_energy_multiplier = 0.6
	pad_mesh.material = pad_mat
	pad.mesh = pad_mesh
	pad.position.y = 0.03
	add_child(pad)
	_model = Models.build_pickup(kind)
	add_child(_model)
	_light = OmniLight3D.new()
	_light.light_color = _color()
	_light.omni_range = 2.5
	_light.light_energy = 0.8
	_light.position.y = 0.6
	add_child(_light)


func _color() -> Color:
	match kind:
		"health": return Color(0.95, 0.25, 0.25)
		"ammo": return Color(0.95, 0.8, 0.25)
	return Color(0.4, 0.9, 0.35)


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	_pop = move_toward(_pop, 1.0, delta * 4.0)
	_model.position.y = 0.25 + sin(_t * 2.0) * 0.08
	_model.rotation.y = _t * 1.2
	_model.scale = Vector3.ONE * maxf(0.05, ease(_pop, 0.4))


func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	_model.visible = value
	_light.visible = value
	if value:
		_pop = 0.0
