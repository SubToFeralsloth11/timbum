class_name PickupNode
extends Node3D
## Visual for a health/ammo/grenade pickup. The server decides who takes it (World._server_pickups).
## While taken, a faint ghost of the item grows back on the pad under a seconds countdown, so
## players can see when it returns.

var kind := "health"
var active := true
var _model: Node3D
var _ghost: Node3D
var _label: Label3D
var _light: OmniLight3D
var _pad_mat: StandardMaterial3D
var _t := 0.0
var _pop := 1.0
var _respawn_total := 1.0
var _respawn_left := 0.0


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
	_pad_mat = StandardMaterial3D.new()
	_pad_mat.albedo_color = _color().darkened(0.4)
	_pad_mat.emission_enabled = true
	_pad_mat.emission = _color()
	_pad_mat.emission_energy_multiplier = 0.6
	pad_mesh.material = _pad_mat
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
	_ghost = Models.build_pickup(kind)
	for mesh: MeshInstance3D in _ghost.find_children("*", "MeshInstance3D", true, false):
		mesh.transparency = 0.75
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 64
	_label.outline_size = 14
	_label.pixel_size = 0.006
	_label.modulate = _color().lightened(0.35)
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.position.y = 1.05
	_label.visible = false
	add_child(_label)


func _color() -> Color:
	match kind:
		"health": return Color(0.95, 0.25, 0.25)
		"ammo": return Color(0.95, 0.8, 0.25)
	return Color(0.4, 0.9, 0.35)


func _process(delta: float) -> void:
	_t += delta
	if not active:
		_respawn_left = maxf(0.0, _respawn_left - delta)
		var progress := clampf(1.0 - _respawn_left / _respawn_total, 0.0, 1.0)
		_ghost.position.y = 0.2
		_ghost.rotation.y = _t * 0.6
		_ghost.scale = Vector3.ONE * lerpf(0.35, 0.9, progress)
		_label.text = str(maxi(1, ceili(_respawn_left)))
		# The last 3 seconds pulse so a player waiting on it knows to step in.
		var pulse := 1.0 + (0.18 * maxf(0.0, sin(_t * 12.0)) if _respawn_left < 3.0 else 0.0)
		_label.scale = Vector3.ONE * pulse
		return
	_pop = move_toward(_pop, 1.0, delta * 4.0)
	_model.position.y = 0.25 + sin(_t * 2.0) * 0.08
	_model.rotation.y = _t * 1.2
	_model.scale = Vector3.ONE * maxf(0.05, ease(_pop, 0.4))


## `respawn_in` is how long (seconds) until the server brings a taken pickup back.
func set_active(value: bool, respawn_in := 0.0) -> void:
	if not value:
		_respawn_left = maxf(0.0, respawn_in)
		_label.text = str(maxi(1, ceili(_respawn_left)))
		_respawn_total = World.PICKUP_RESPAWN
	if value == active:
		return
	active = value
	_model.visible = value
	_light.visible = value
	_ghost.visible = not value
	_label.visible = not value
	_pad_mat.emission_energy_multiplier = 0.6 if value else 0.15
	if value:
		_pop = 0.0
