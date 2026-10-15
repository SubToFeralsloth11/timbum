class_name Viewmodel
extends Node3D
## First-person arms and gun, parented to the local camera.
## Materials are swapped for a shader that squashes depth toward the near plane,
## so the gun draws over walls instead of clipping into them, while still being lit by the scene.

const HIP_POS := Vector3(0.13, -0.15, -0.4)
const ADS_DEPTH := -0.24
const SPRINT_ROT := Vector3(-0.35, 0.7, 0.25)

const SHADER_CODE := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform bool use_vertex_color = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float metallic = 0.0;
uniform float roughness = 0.8;
void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Reversed-Z: pull depth almost onto the near plane, keeping the gun's own depth order.
	POSITION.z = mix(POSITION.w, POSITION.z, 0.04);
}
void fragment() {
	vec4 c = albedo;
	if (use_tex) { c *= texture(albedo_tex, UV); }
	if (use_vertex_color) { c *= COLOR; }
	ALBEDO = c.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = emission.rgb * emission_energy;
}
"""

const FLASH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.35, 1.0);
void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.w, POSITION.z, 0.03);
}
void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float star = clamp(1.0 - (min(d.x, d.y) * 4.0 + max(d.x, d.y) * 0.9), 0.0, 1.0);
	ALBEDO = tint.rgb * star * 3.0;
}
"""

static var _shader: Shader
static var _converted := {}

## Reload props per weapon, in gun space: [magwell centre, prop size, prop x-tilt, colour,
## direction the new magazine/shell/rocket is pushed in from].
const MAGS := {
	"pistol": [Vector3(0, -0.06, 0.015), Vector3(0.024, 0.085, 0.03), -0.22, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"revolver": [Vector3(0.03, 0.012, 0.0), Vector3(0.036, 0.036, 0.03), 0.0, Color(0.85, 0.65, 0.25), Vector3.RIGHT],
	"smg": [Vector3(0, -0.065, -0.11), Vector3(0.028, 0.15, 0.034), 0.0, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"rifle": [Vector3(0, -0.07, -0.112), Vector3(0.03, 0.14, 0.05), 0.2, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"lmg": [Vector3(-0.01, -0.06, -0.1), Vector3(0.088, 0.108, 0.128), 0.0, Color(0.25, 0.28, 0.2), Vector3.DOWN],
	"sniper": [Vector3(0, -0.012, -0.1), Vector3(0.032, 0.048, 0.066), 0.0, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"shotgun": [Vector3(0, 0.0, -0.12), Vector3(0.02, 0.02, 0.055), 0.0, Color(0.75, 0.12, 0.1), Vector3.DOWN],
	"rocket": [Vector3(0, 0.1, 0.32), Vector3(0.08, 0.08, 0.22), 0.0, Color(0.7, 0.15, 0.12), Vector3.BACK],
}
## Where the left hand goes to fetch a new magazine (arms space; below the screen edge).
const HAND_OFFSCREEN := Vector3(-0.08, -0.4, 0.05)

var _pivot: Node3D
var _arms: ViewmodelArms
var _gun: Node3D
var _muzzle: Node3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _skin := "default"
var _weapon := ""
var _ads_pos := Vector3(0.0, -0.12, ADS_DEPTH)
var _scoped := false

var _sway := Vector2.ZERO
var _sway_smooth := Vector2.ZERO
var _bob_t := 0.0
var _kick := 0.0
var _reload_t := 0.0
var _reload_len := 0.0
var _draw_t := 0.0
var _melee_t := 0.0
var _flash_t := 0.0
var _sprint_blend := 0.0
var _mag_prop: MeshInstance3D
var _mag_box: BoxMesh
var _mag_weapon := ""


func setup(outfit_id: String, skin_id: String) -> void:
	_skin = skin_id
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_arms = Models.build_viewmodel_arms(outfit_id) as ViewmodelArms
	_pivot.add_child(_arms)
	_convert(_arms)

	_flash = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	_flash.mesh = quad
	var fmat := ShaderMaterial.new()
	var fsh := Shader.new()
	fsh.code = FLASH_SHADER
	fmat.shader = fsh
	_flash.material_override = fmat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.78, 0.4)
	_flash_light.omni_range = 5.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	add_child(_flash_light)


func set_weapon(wid: String) -> void:
	if wid == _weapon:
		return
	_weapon = wid
	_gun = Models.build_gun(wid, _skin)
	_arms.attach_gun(_gun)
	_convert(_gun)
	_muzzle = _gun.get_node_or_null(^"Muzzle") as Node3D
	_scoped = Data.WEAPONS[wid].get("scope", false)
	_ads_pos = _compute_ads_pos()
	play_draw()


## Places the pivot so the gun's rear sight sits just under the camera axis.
func _compute_ads_pos() -> Vector3:
	var sight := _gun.get_node_or_null(^"Sight") as Node3D
	if sight == null:
		return Vector3(0.0, -0.12, ADS_DEPTH)
	var local := _pivot.global_transform.affine_inverse() * sight.global_position
	# Keep the rear sight ~20 cm in front of the eye whatever the gun's length.
	return Vector3(-local.x, -local.y - 0.006, -0.2 - local.z)


func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle != null else global_position


func add_sway(rel: Vector2) -> void:
	_sway += rel


func play_fire(kick_deg: float) -> void:
	_kick = minf(_kick + 0.35 + kick_deg * 0.12, 1.4)
	_flash_t = 0.05
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.25)
	_flash_light.light_energy = 2.2


func play_reload(length: float) -> void:
	_reload_len = length if length > 0.0 else 0.4
	_reload_t = _reload_len


## Cancels a running reload animation (weapon switch).
func stop_reload() -> void:
	_reload_t = 0.0
	_arms.set_left_hand(Vector3.ZERO, 0.0)
	if _mag_prop != null:
		_mag_prop.visible = false


## Left hand leaves the gun, fetches a fresh magazine (shell / speedloader / rocket) from
## below the screen, pushes it into the gun and returns. `u` is reload progress 0..1.
func _animate_magazine(u: float) -> void:
	if not MAGS.has(_weapon):
		return
	var spec: Array = MAGS[_weapon]
	var size: Vector3 = spec[1]
	var push_dir: Vector3 = spec[4]
	if _mag_prop == null:
		_mag_box = BoxMesh.new()
		_mag_prop = MeshInstance3D.new()
		_mag_prop.mesh = _mag_box
		_mag_prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arms.add_child(_mag_prop)
	var gun_xf := _arms.get_gun_mount().transform * _gun.transform
	var seat_basis := gun_xf.basis * Basis(Vector3.RIGHT, float(spec[2]))
	var seated := gun_xf * (spec[0] as Vector3)
	# The hand holds the far end of the magazine, i.e. the end that goes in last.
	var grip_offset := seat_basis * (push_dir * absf(push_dir.dot(size)) * 0.5)
	var approach := seated + seat_basis * (push_dir * 0.2)
	var offscreen := HAND_OFFSCREEN
	if _weapon == "shotgun":
		offscreen = seated + Vector3(0.0, -0.18, 0.06)
	var w := 0.0
	var hand := offscreen
	var mag_pos := Vector3.ZERO
	var show_mag := false
	if u < 0.15:
		w = 0.0
	elif u < 0.3:
		w = smoothstep(0.15, 0.3, u)
	elif u < 0.45:
		w = 1.0
	elif u < 0.7:
		w = 1.0
		hand = offscreen.lerp(approach + grip_offset, smoothstep(0.45, 0.7, u))
		show_mag = true
	elif u < 0.8:
		w = 1.0
		hand = (approach + grip_offset).lerp(seated + grip_offset, smoothstep(0.7, 0.78, u))
		show_mag = true
	else:
		hand = seated + grip_offset
		w = 1.0 - smoothstep(0.8, 0.95, u)
	if show_mag:
		mag_pos = hand - grip_offset
		if _mag_weapon != _weapon:
			_mag_weapon = _weapon
			_mag_box.size = size
			_mag_prop.material_override = _converted_material(Models.flat_material(spec[3], 0.6))
		_mag_prop.transform = Transform3D(seat_basis, mag_pos)
	_mag_prop.visible = show_mag
	_arms.set_left_hand(hand, w)


func play_melee(_quick: bool) -> void:
	_melee_t = 0.32


func play_draw() -> void:
	_draw_t = 0.3


func update_pose(delta: float, p: Player) -> void:
	var ads := p.aim_blend
	_sway_smooth = _sway_smooth.lerp(_sway, minf(1.0, delta * 12.0))
	_sway = _sway.lerp(Vector2.ZERO, minf(1.0, delta * 10.0))
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_reload_t = maxf(0.0, _reload_t - delta)
	_draw_t = maxf(0.0, _draw_t - delta)
	_melee_t = maxf(0.0, _melee_t - delta)
	_sprint_blend = move_toward(_sprint_blend, 1.0 if p.sprinting else 0.0, delta * 6.0)
	if p.on_floor_visual:
		_bob_t += delta * p.anim_speed * 1.55
	var speed_k := clampf(p.anim_speed / Player.WALK_SPEED, 0.0, 1.5) * (1.0 if p.on_floor_visual else 0.3)

	var pos := HIP_POS.lerp(_ads_pos, ads)
	var rot := Vector3.ZERO
	var bob_amt := (1.0 - ads * 0.9) * speed_k
	pos += Vector3(sin(_bob_t) * 0.012, -absf(cos(_bob_t)) * 0.014, 0.0) * bob_amt
	var sway_amt := 1.0 - ads * 0.75
	pos += Vector3(-_sway_smooth.x, _sway_smooth.y, 0.0) * 0.00035 * sway_amt
	rot += Vector3(-_sway_smooth.y, -_sway_smooth.x, 0.0) * 0.0009 * sway_amt
	pos.z += _kick * 0.045
	rot.x += _kick * (0.05 if ads > 0.5 else 0.11)
	rot += SPRINT_ROT * _sprint_blend
	pos += Vector3(-0.04, -0.03, 0.02) * _sprint_blend
	if p.crouching:
		rot.z += 0.06 * (1.0 - ads)
	if _reload_t > 0.0:
		var u := 1.0 - _reload_t / _reload_len
		var e := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u))
		var tilt := 0.25 if _weapon == "rocket" else 1.0
		# Lift the gun toward the screen centre and cant it so the magwell faces the camera.
		rot.z += 0.4 * e * tilt
		rot.y += 0.3 * e * tilt
		rot.x += 0.25 * e
		pos += Vector3(-0.08, 0.08, 0.05) * e
		_animate_magazine(u)
	elif _mag_prop != null and _mag_prop.visible:
		stop_reload()
	if _draw_t > 0.0:
		var d := _draw_t / 0.3
		pos.y -= d * d * 0.28
		rot.x -= d * 0.6
	if _melee_t > 0.0:
		var m := sin((1.0 - _melee_t / 0.32) * PI)
		if _weapon == "knife":
			rot += Vector3(-0.5, 0.9, 0.7) * m
			pos += Vector3(-0.1, 0.03, -0.12) * m
		else:
			pos += Vector3(-0.06, 0.02, -0.16) * m
			rot.y += 0.5 * m
	_pivot.position = pos
	_pivot.rotation = rot
	_pivot.visible = not (_scoped and ads > 0.85)

	if _flash_t > 0.0:
		_flash_t -= delta
		if _muzzle != null:
			_flash.global_position = _muzzle.global_position
			_flash_light.global_position = _muzzle.global_position
		if _flash_t <= 0.0:
			_flash.visible = false
			_flash_light.light_energy = 0.0
	if _scoped and ads > 0.85:
		_flash.visible = false


## Replaces each StandardMaterial3D in a subtree with the depth-squashing viewmodel shader.
func _convert(root: Node) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	for node in root.find_children("*", "GeometryInstance3D", true, false) + ([root] if root is GeometryInstance3D else []):
		var gi := node as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if gi.material_override != null:
			gi.material_override = _converted_material(gi.material_override)
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.get_surface_override_material(s)
				if m == null:
					m = mi.mesh.surface_get_material(s)
				if m != null:
					mi.set_surface_override_material(s, _converted_material(m))


static func _converted_material(m: Material) -> Material:
	if _converted.has(m):
		return _converted[m]
	if not (m is StandardMaterial3D):
		return m
	var src := m as StandardMaterial3D
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	sm.set_shader_parameter("albedo", src.albedo_color)
	if src.albedo_texture != null:
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		sm.set_shader_parameter("use_tex", true)
	sm.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
	sm.set_shader_parameter("uv_scale", src.uv1_scale)
	sm.set_shader_parameter("uv_offset", src.uv1_offset)
	sm.set_shader_parameter("metallic", src.metallic)
	sm.set_shader_parameter("roughness", src.roughness)
	if src.emission_enabled:
		sm.set_shader_parameter("emission", src.emission)
		sm.set_shader_parameter("emission_energy", src.emission_energy_multiplier)
	_converted[m] = sm
	return sm
