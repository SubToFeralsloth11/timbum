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
uniform sampler2D emission_tex : source_color, filter_nearest_mipmap, repeat_enable;
// StandardMaterial3D's emission texture: 0 none, 1 added to the emission colour, 2 multiplies it.
uniform int emission_tex_mode = 0;
uniform float metallic = 0.0;
uniform float roughness = 0.8;
uniform float specular = 0.5;
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
	SPECULAR = specular;
	vec3 e = emission.rgb;
	if (emission_tex_mode == 1) { e += texture(emission_tex, UV).rgb; }
	if (emission_tex_mode == 2) { e *= texture(emission_tex, UV).rgb; }
	EMISSION = e * emission_energy;
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
	"machine_pistol": [Vector3(0, -0.1, 0.022), Vector3(0.026, 0.14, 0.034), -0.18, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"burst_pistol": [Vector3(0, -0.062, 0.016), Vector3(0.026, 0.09, 0.032), -0.2, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"suppressed": [Vector3(0, -0.058, 0.015), Vector3(0.022, 0.08, 0.028), -0.22, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"sawed_off": [Vector3(0, 0.05, -0.02), Vector3(0.045, 0.022, 0.05), 0.0, Color(0.75, 0.12, 0.1), Vector3.BACK],
	"dmr": [Vector3(0, -0.04, -0.11), Vector3(0.03, 0.08, 0.06), 0.0, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"burst_rifle": [Vector3(0, -0.035, 0.09), Vector3(0.03, 0.09, 0.05), 0.15, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"crossbow": [Vector3(0, 0.066, -0.27), Vector3(0.008, 0.008, 0.42), 0.0, Color(0.3, 0.31, 0.34), Vector3.BACK],
	"drum_shotgun": [Vector3(0, -0.07, -0.1), Vector3(0.07, 0.09, 0.09), 0.0, Color(0.1, 0.1, 0.11), Vector3.DOWN],
	"carbine": [Vector3(0, -0.07, -0.09), Vector3(0.03, 0.14, 0.05), 0.2, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"burst_smg": [Vector3(0, -0.065, -0.08), Vector3(0.028, 0.15, 0.034), 0.0, Color(0.36, 0.38, 0.42), Vector3.DOWN],
	"minigun": [Vector3(-0.085, -0.04, -0.05), Vector3(0.07, 0.11, 0.14), 0.0, Color(0.1, 0.1, 0.11), Vector3.DOWN],
}
## Where the left hand goes to fetch a new magazine (arms space; below the screen edge).
const HAND_OFFSCREEN := Vector3(-0.08, -0.4, 0.05)
## Melee swing timing (fraction of the swing): wind-up, then the fast strike, then recovery. A
## swing lasts SWING_SHARE of the weapon's refire time, between SWING_MIN and SWING_MAX seconds
## (the knife: 0.42 s; the hammer's slow chop: the maximum).
const SLASH_TIME := 0.42
const SWING_SHARE := 0.77
const SWING_MIN := 0.32
const SWING_MAX := 0.75
const SLASH_WINDUP := 0.22
const SLASH_STRIKE := 0.5
const BASH_TIME := 0.4
const THROW_TIME := 0.5
## Swing keyframes per Data `swing` style: [start pivot offset, start rotation, end offset, end
## rotation]. "slash" is a forehand from the upper right to the lower left (backhands mirror it),
## "chop" comes down from overhead, "sweep" goes wide and flat across the view.
const SWINGS := {
	"slash": [Vector3(0.07, 0.07, 0.05), Vector3(0.35, -0.55, -0.55), Vector3(-0.2, -0.1, -0.1), Vector3(-0.5, 0.8, 0.75)],
	"chop": [Vector3(0.02, 0.16, 0.08), Vector3(1.0, -0.1, -0.15), Vector3(-0.04, -0.2, -0.16), Vector3(-1.05, 0.15, 0.1)],
	"sweep": [Vector3(0.16, 0.0, 0.04), Vector3(0.1, -1.0, -0.25), Vector3(-0.28, -0.04, -0.12), Vector3(-0.05, 1.15, 0.2)],
}
const TRAIL_POINTS := 7
## Weapon inspect (Player.inspect_left): INSPECT_TIME seconds. A gun is raised and turned to show
## its left side (skin, charm), rolled over to show the top and the other side, then brought back
## to ready; the knife does a flourish instead (two flips over the hand, a spin, then the blade
## turned to the camera). Keyframes are [progress, pivot offset, pivot rotation], eased between
## neighbours (inspect_pose).
const INSPECT_TIME := 3.0
const INSPECT_GUN_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.17, Vector3(-0.1, 0.06, 0.06), Vector3(0.12, 1.0, 0.3)],
	[0.42, Vector3(-0.11, 0.07, 0.05), Vector3(0.2, 1.12, 0.38)],
	[0.6, Vector3(-0.08, 0.08, 0.03), Vector3(0.5, -0.45, -0.95)],
	[0.83, Vector3(-0.07, 0.09, 0.03), Vector3(0.58, -0.55, -1.05)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]
const INSPECT_KNIFE_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.12, Vector3(-0.09, 0.07, 0.02), Vector3(0.25, 0.3, 0.2)],
	[0.6, Vector3(-0.1, 0.08, 0.02), Vector3(0.3, 0.35, 0.25)],
	[0.72, Vector3(-0.12, 0.08, 0.04), Vector3(0.2, 1.2, 0.5)],
	[0.88, Vector3(-0.12, 0.08, 0.04), Vector3(0.25, 1.3, 0.55)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

const TRAIL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.w, POSITION.z, 0.03);
}
void fragment() {
	ALBEDO = vec3(0.7, 0.85, 1.0) * COLOR.a * 0.45;
}
"""

var _pivot: Node3D
var _arms: ViewmodelArms
var _gun: Node3D
var _muzzle: Node3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _skin := "default"
## Weapon ids that wear their mastery camo instead of _skin (peer_info `camos`).
var _camos: Array = []
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
## Length of the current draw (the player's switch time) and its style (Data.DRAWS id).
var _draw_len := 0.3
var _draw_style := "standard"
var _charm := "none"
var _melee_t := 0.0
var _melee_len := SLASH_TIME
## Holding a melee weapon when the swing started (a gun bashes instead), and its SWINGS style.
var _melee_blade := true
var _swing := "slash"
## +1 forehand, -1 backhand; knife slashes alternate.
var _slash_side := 1.0
var _throw_t := 0.0
var _land_kick := 0.0
var _air_vy := 0.0
var _was_floor := true
var _breath_t := 0.0
var _strafe := 0.0
var _kick_roll := 0.0
var _slide_blend := 0.0
var _grapple_blend := 0.0
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
## Recent blade tip and base positions (viewmodel space) while a slash is cutting.
var _trail_tips: Array[Vector3] = []
var _trail_bases: Array[Vector3] = []
## True while a throw or the grapple has moved the left hand off the gun.
var _off_hand_used := false
var _flash_t := 0.0
var _sprint_blend := 0.0
var _mag_prop: MeshInstance3D
var _mag_box: BoxMesh
var _mag_weapon := ""
## True while a reload animation has the left hand off its support point.
var _hand_busy := false
var _inspect_t := 0.0


func setup(outfit_id: String, skin_id: String, charm_id := "none", draw_style := "standard", camos: Array = []) -> void:
	_skin = skin_id
	_camos = camos
	_charm = charm_id
	_draw_style = draw_style if Data.DRAWS.has(draw_style) else "standard"
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

	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.name = "SlashTrail"
	_trail.mesh = _trail_mesh
	var tmat := ShaderMaterial.new()
	var tsh := Shader.new()
	tsh.code = TRAIL_SHADER
	tmat.shader = tsh
	_trail.material_override = tmat
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)


func set_weapon(wid: String, draw_len := 0.3) -> void:
	if wid == _weapon:
		return
	_weapon = wid
	_gun = Models.build_gun(wid, Data.mastery_skin(wid) if _camos.has(wid) else _skin, _charm)
	_arms.attach_gun(_gun)
	_convert(_gun)
	_muzzle = _gun.get_node_or_null(^"Muzzle") as Node3D
	_scoped = Data.WEAPONS[wid].get("scope", false)
	_ads_pos = _compute_ads_pos()
	play_draw(draw_len)


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


## The muzzle's world transform (-Z along the barrel), for the laser during an inspect.
func muzzle_transform() -> Transform3D:
	return _muzzle.global_transform if _muzzle != null else global_transform


func add_sway(rel: Vector2) -> void:
	_sway += rel


func play_fire(kick_deg: float) -> void:
	_kick = minf(_kick + 0.35 + kick_deg * 0.12, 1.4)
	_kick_roll = clampf(_kick_roll + randf_range(-0.06, 0.06) * (1.0 + kick_deg * 0.2), -0.18, 0.18)
	_flash_t = 0.05
	# A suppressor swallows the flash.
	var suppressed: bool = Data.WEAPONS[_weapon].get("suppressed", false)
	_flash.visible = not suppressed
	_flash.rotation.z = randf() * TAU
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.25)
	_flash_light.light_energy = 0.3 if suppressed else 2.2


func play_reload(length: float) -> void:
	_reload_len = length if length > 0.0 else 0.4
	_reload_t = _reload_len


## Cancels a running reload animation (weapon switch).
func stop_reload() -> void:
	_reload_t = 0.0
	_hand_busy = false
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
	_hand_busy = true


## Melee weapon: its swing (slash alternating fore/backhand, overhead chop or wide sweep) with a
## trail behind the head or edge, timed from its swing rate. Anything else: a short stock bash.
func play_melee(_quick: bool) -> void:
	_melee_blade = Data.is_melee(_weapon)
	var w: Dictionary = Data.WEAPONS.get(_weapon, {})
	_swing = str(w.get("swing", "slash")) if SWINGS.has(str(w.get("swing", ""))) else "slash"
	_melee_len = clampf(60.0 / float(w.rpm) * SWING_SHARE, SWING_MIN, SWING_MAX) if _melee_blade else BASH_TIME
	_melee_t = _melee_len
	_slash_side = -_slash_side
	_trail_tips.clear()
	_trail_bases.clear()


func play_throw() -> void:
	_throw_t = THROW_TIME


## Starts the INSPECT_TIME weapon inspect (Player.start_inspect).
func play_inspect() -> void:
	_inspect_t = INSPECT_TIME


## Ends an inspect at once (fire, aim, reload, switch, sprint, melee, a throw cancel it).
func stop_inspect() -> void:
	_inspect_t = 0.0


func is_inspecting() -> bool:
	return _inspect_t > 0.0


## Takes the gun out over `length` seconds (the switch time) in the equipped draw style. Every
## style ends exactly at `length`, so none of them delays the first shot.
func play_draw(length := 0.3) -> void:
	_draw_len = maxf(length, 0.05)
	_draw_t = _draw_len


func update_pose(delta: float, p: Player) -> void:
	pose(delta, p.aim_blend, p.sprinting, p.sliding, p.grappling,
		Basis(Vector3.UP, p.yaw).inverse() * p.velocity, p.on_floor_visual, p.anim_speed, p.crouching)


## The pose from explicit movement state, for the local player (update_pose) and the kill cam's
## replay of another player's view (KillCam). `local_vel` is the velocity in the yaw frame.
func pose(delta: float, ads: float, sprinting: bool, sliding: bool, grappling: bool, local_vel: Vector3,
		on_floor: bool, anim_speed: float, crouching: bool) -> void:
	_sway_smooth = _sway_smooth.lerp(_sway, minf(1.0, delta * 12.0))
	_sway = _sway.lerp(Vector2.ZERO, minf(1.0, delta * 10.0))
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_kick_roll = move_toward(_kick_roll, 0.0, delta * 1.5)
	_reload_t = maxf(0.0, _reload_t - delta)
	_draw_t = maxf(0.0, _draw_t - delta)
	_melee_t = maxf(0.0, _melee_t - delta)
	_throw_t = maxf(0.0, _throw_t - delta)
	_inspect_t = maxf(0.0, _inspect_t - delta)
	_land_kick = move_toward(_land_kick, 0.0, delta * 4.0)
	_breath_t += delta
	_sprint_blend = move_toward(_sprint_blend, 1.0 if sprinting else 0.0, delta * 6.0)
	_slide_blend = move_toward(_slide_blend, 1.0 if sliding else 0.0, delta * 7.0)
	_grapple_blend = move_toward(_grapple_blend, 1.0 if grappling else 0.0, delta * 8.0)
	_strafe = lerpf(_strafe, clampf(local_vel.x / Player.SPRINT_SPEED, -1.0, 1.0), minf(1.0, delta * 8.0))
	# Landing dips the gun in proportion to how hard the player came down.
	if on_floor and not _was_floor:
		_land_kick = clampf(-_air_vy / 14.0, 0.0, 1.0)
	if not on_floor:
		_air_vy = local_vel.y
	_was_floor = on_floor
	if on_floor and not sliding:
		_bob_t += delta * anim_speed * 1.55
	var speed_k := clampf(anim_speed / Player.WALK_SPEED, 0.0, 1.5) * (1.0 if on_floor and not sliding else 0.3)

	var pos := HIP_POS.lerp(_ads_pos, ads)
	var rot := Vector3.ZERO
	# Walk bob traces a figure eight; sprinting swings it wider and rolls the gun with each step.
	var bob_amt := (1.0 - ads * 0.9) * speed_k * (1.0 + 0.8 * _sprint_blend)
	pos += Vector3(sin(_bob_t) * 0.012, -absf(cos(_bob_t)) * 0.014, 0.0) * bob_amt
	rot.z += sin(_bob_t) * 0.025 * bob_amt * _sprint_blend
	rot.x += absf(cos(_bob_t)) * 0.02 * bob_amt * _sprint_blend
	# Idle breathing, mostly hidden when aiming.
	var breath := (1.0 - ads * 0.85) * (1.0 - minf(speed_k, 1.0))
	pos.y += sin(_breath_t * 1.7) * 0.003 * breath
	rot.x += sin(_breath_t * 1.7 + 0.6) * 0.006 * breath
	var sway_amt := 1.0 - ads * 0.75
	pos += Vector3(-_sway_smooth.x, _sway_smooth.y, 0.0) * 0.00035 * sway_amt
	rot += Vector3(-_sway_smooth.y, -_sway_smooth.x, 0.0) * 0.0009 * sway_amt
	# Strafing leans the gun into the direction of travel.
	rot.z -= _strafe * 0.07 * (1.0 - ads * 0.7)
	pos.x -= _strafe * 0.008 * (1.0 - ads)
	pos.z += _kick * 0.045
	rot.x += _kick * (0.05 if ads > 0.5 else 0.11)
	rot.z += _kick_roll * _kick
	rot += SPRINT_ROT * _sprint_blend
	pos += Vector3(-0.04, -0.03, 0.02) * _sprint_blend
	# Sliding: gun tucked and canted; grappling: gun lowered while the off hand holds the line.
	rot += Vector3(0.12, 0.25, 0.45) * _slide_blend * (1.0 - ads)
	pos += Vector3(-0.03, -0.025, 0.02) * _slide_blend * (1.0 - ads)
	rot += Vector3(-0.25, 0.1, -0.15) * _grapple_blend
	pos += Vector3(0.02, -0.06, 0.04) * _grapple_blend
	pos.y -= _land_kick * 0.045
	rot.x -= _land_kick * 0.09
	if crouching and not sliding:
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
	elif _hand_busy:
		stop_reload()
	if _draw_t > 0.0:
		var dpose := draw_pose(_draw_style, _draw_t / _draw_len)
		pos += dpose[0]
		rot += dpose[1]
		if _gun != null:
			_gun.transform = dpose[2]
	elif _inspect_t > 0.0:
		# Only the knife is light enough to flip end over end; longer melee weapons turn like guns.
		var ipose := inspect_pose(_weapon == "knife", 1.0 - _inspect_t / INSPECT_TIME)
		pos += ipose[0]
		rot += ipose[1]
		if _gun != null:
			_gun.transform = ipose[2]
	elif _gun != null and _gun.transform != Transform3D.IDENTITY:
		_gun.transform = Transform3D.IDENTITY
	if _melee_t > 0.0:
		var u := 1.0 - _melee_t / _melee_len
		if _melee_blade:
			var pose := _slash_pose(u)
			pos += pose[0]
			rot += pose[1]
		else:
			# Stock bash: pull back and cant, then a hard jab forward and back.
			var back := smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.25, 0.4, u))
			var jab := smoothstep(0.25, 0.4, u) * (1.0 - smoothstep(0.55, 1.0, u))
			pos += Vector3(0.03, 0.0, 0.06) * back + Vector3(-0.08, 0.04, -0.2) * jab
			rot += Vector3(0.15, -0.3, 0.3) * back + Vector3(-0.1, 0.55, -0.4) * jab
	if _throw_t > 0.0:
		# Gun drops out of the way while the off hand throws.
		var u := 1.0 - _throw_t / THROW_TIME
		var e := smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.7, 1.0, u))
		pos += Vector3(0.06, -0.14, 0.06) * e
		rot += Vector3(-0.5, -0.2, -0.3) * e
	_pivot.position = pos
	_pivot.rotation = rot
	_pivot.visible = not (_scoped and ads > 0.85)
	_animate_off_hand()
	_update_trail()

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


## Draw animation `style` at `d` (1 = just started, 0 = done): [pivot offset, pivot rotation,
## gun transform under the hand]. Styles that spin the gun in the hand use the last one.
static func draw_pose(style: String, d: float) -> Array:
	var u := 1.0 - d
	var ease_out := 1.0 - pow(d, 3.0)
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	var gun := Transform3D.IDENTITY
	match style:
		"twirl":
			# One full turn around the trigger finger while rising.
			pos.y -= d * d * 0.16
			rot.x -= d * 0.25
			gun = Transform3D(Basis(Vector3.RIGHT, TAU * (1.0 - ease_out)), Vector3(0.0, -0.03, 0.0) * sin(u * PI))
		"flip":
			# Rolled a full turn around the barrel on the way up.
			pos.y -= d * d * 0.24
			gun = Transform3D(Basis(Vector3.BACK, TAU * (1.0 - ease_out)), Vector3.ZERO)
		"slam":
			# Falls in from above and bounces into place.
			var drop := d * d
			var bounce := sin(u * PI * 2.0) * 0.025 * d if u > 0.55 else 0.0
			pos.y += drop * 0.3 - bounce
			rot.x += drop * 0.5
		"sidewinder":
			pos.x += d * d * 0.38
			pos.y -= d * 0.05
			rot.y += d * d * 1.3
			rot.z -= d * 0.4
		"toss":
			# Thrown up from the hand end over end, then caught.
			var arc := sin(u * PI) * 0.12
			pos.y -= d * d * 0.12
			gun = Transform3D(Basis(Vector3.RIGHT, -TAU * (1.0 - ease_out)), Vector3(0.0, arc, 0.0))
		_:
			# Swings up from below with a twist.
			pos.y -= d * d * 0.28
			rot.x -= d * 0.6
			rot.z += d * d * 0.5
	return [pos, rot, gun]


## Inspect at progress `u` (0..1): [pivot offset, pivot rotation, gun transform under the hand].
## Guns turn with the whole hold (both hands stay on); the knife also flips and spins in the hand.
static func inspect_pose(knife: bool, u: float) -> Array:
	var keys: Array = INSPECT_KNIFE_KEYS if knife else INSPECT_GUN_KEYS
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	for i in range(1, keys.size()):
		if u <= float(keys[i][0]) or i == keys.size() - 1:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var t := smoothstep(float(a[0]), float(b[0]), u)
			pos = (a[1] as Vector3).lerp(b[1], t)
			rot = (a[2] as Vector3).lerp(b[2], t)
			break
	var gun := Transform3D.IDENTITY
	if knife:
		# Two flips end over end with a little toss, then one spin around the blade.
		var flips := smoothstep(0.14, 0.48, u)
		var spin := smoothstep(0.5, 0.68, u)
		var toss := sin(flips * PI) * 0.07
		gun = Transform3D(Basis(Vector3.RIGHT, -TAU * 2.0 * flips) * Basis(Vector3.FORWARD, TAU * spin), Vector3(0.0, toss, 0.0))
	return [pos, rot, gun]


## Knife slash at progress `u` (0..1): [pivot offset, pivot rotation]. Eases up to the wind-up
## pose, whips through to the follow-through pose fast, then settles back to rest.
func _slash_pose(u: float) -> Array:
	var mirror := Vector3(_slash_side, 1.0, 1.0)
	var rot_mirror := Vector3(1.0, _slash_side, _slash_side)
	var keys: Array = SWINGS[_swing]
	var start_pos: Vector3 = keys[0] * mirror
	var start_rot: Vector3 = keys[1] * rot_mirror
	var end_pos: Vector3 = keys[2] * mirror
	var end_rot: Vector3 = keys[3] * rot_mirror
	if u < SLASH_WINDUP:
		var t := smoothstep(0.0, SLASH_WINDUP, u)
		return [start_pos * t, start_rot * t]
	if u < SLASH_STRIKE:
		var t := (u - SLASH_WINDUP) / (SLASH_STRIKE - SLASH_WINDUP)
		t = 1.0 - pow(1.0 - t, 3.0)
		return [start_pos.lerp(end_pos, t), start_rot.lerp(end_rot, t)]
	var r := 1.0 - smoothstep(SLASH_STRIKE, 1.0, u)
	return [end_pos * r, end_rot * r]


## Off-hand moves that aren't reloads: the throw (hand cocks back, then flings forward) and
## holding the grapple line.
func _animate_off_hand() -> void:
	if _hand_busy:
		return
	var hand := Vector3.ZERO
	var w := 0.0
	if _throw_t > 0.0:
		var u := 1.0 - _throw_t / THROW_TIME
		var cocked := Vector3(-0.2, 0.06, 0.12)
		var flung := Vector3(-0.06, 0.02, -0.5)
		if u < 0.35:
			hand = cocked
			w = smoothstep(0.0, 0.25, u)
		elif u < 0.6:
			hand = cocked.lerp(flung, smoothstep(0.35, 0.55, u))
			w = 1.0
		else:
			hand = flung
			w = 1.0 - smoothstep(0.6, 1.0, u)
	elif _grapple_blend > 0.0:
		hand = Vector3(-0.2, -0.04, -0.38)
		w = _grapple_blend
	elif _draw_t > 0.0 and _draw_style in ["twirl", "flip", "toss"]:
		# The off hand lets go while the gun spins in the right hand.
		var u := 1.0 - _draw_t / _draw_len
		hand = Vector3(-0.22, -0.2, -0.25)
		w = 1.0 - smoothstep(0.65, 0.95, u)
	if w > 0.0:
		_arms.set_left_hand(hand, w)
		_off_hand_used = true
	elif _off_hand_used:
		_arms.set_left_hand(Vector3.ZERO, 0.0)
		_off_hand_used = false


## Draws a fading ribbon behind the knife's edge while a slash is cutting.
func _update_trail() -> void:
	_trail_mesh.clear_surfaces()
	var cutting := _melee_t > 0.0 and _melee_blade and _muzzle != null
	if cutting:
		var u := 1.0 - _melee_t / _melee_len
		cutting = u > SLASH_WINDUP - 0.02 and u < SLASH_STRIKE + 0.12
	if cutting:
		var inv := global_transform.affine_inverse()
		var tip := inv * _muzzle.global_position
		# The ribbon spans the outer 40 % of the weapon (blade edge, bat or hammer head).
		var base := inv * _gun.global_transform * (_muzzle.position * 0.6)
		_trail_tips.append(tip)
		_trail_bases.append(base)
		if _trail_tips.size() > TRAIL_POINTS:
			_trail_tips.pop_front()
			_trail_bases.pop_front()
	elif not _trail_tips.is_empty():
		# Let the ribbon shrink away over a few frames after the cut.
		_trail_tips.pop_front()
		_trail_bases.pop_front()
	var n := _trail_tips.size()
	if n < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var a := float(i + 1) / float(n)
		_trail_mesh.surface_set_color(Color(1, 1, 1, a * a))
		_trail_mesh.surface_add_vertex(_trail_tips[i])
		_trail_mesh.surface_set_color(Color(1, 1, 1, a * a * 0.2))
		_trail_mesh.surface_add_vertex(_trail_bases[i])
	_trail_mesh.surface_end()


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


## The viewmodel copy of a material: StandardMaterial3D parameters (emission texture and operator
## included) go into SHADER_CODE; an animated skin (Models.anim_skin_shader) gets the shader's
## depth-squashing variant with every parameter copied. Other ShaderMaterials stay as they are.
static func _converted_material(m: Material) -> Material:
	if _converted.has(m):
		return _converted[m]
	if m is ShaderMaterial and (m as ShaderMaterial).shader == Models.anim_skin_shader():
		var anim_src := m as ShaderMaterial
		var vm := ShaderMaterial.new()
		vm.shader = Models.anim_skin_shader(true)
		for u: Dictionary in anim_src.shader.get_shader_uniform_list():
			vm.set_shader_parameter(u.name, anim_src.get_shader_parameter(u.name))
		_converted[m] = vm
		return vm
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
	sm.set_shader_parameter("specular", src.metallic_specular)
	if src.emission_enabled:
		sm.set_shader_parameter("emission", src.emission)
		sm.set_shader_parameter("emission_energy", src.emission_energy_multiplier)
		if src.emission_texture != null:
			sm.set_shader_parameter("emission_tex", src.emission_texture)
			sm.set_shader_parameter("emission_tex_mode", 2 if src.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY else 1)
	_converted[m] = sm
	return sm
