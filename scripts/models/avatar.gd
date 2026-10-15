class_name Avatar
extends Node3D
## Blocky Minecraft-proportioned character built by Models.build_avatar().
## Feet at the origin, facing -Z, 1.8 m tall (32 texels of 5.625 cm), eyes at about 1.6 m.
## Rig: Visual > Hips > {LegR/LegL > Knee, Torso > {Head > HatMount, ArmR, ArmL, GunMount}}.
## Call animate() every frame; set_look_pitch() whenever the view pitch changes.

const PX := Models.PX
const HIP_HEIGHT := 12 * PX
const LEG_SEGMENT := 6 * PX
const CROUCH_DROP := 0.35
const SHOULDER_X := 6 * PX
const SHOULDER_Y := 10 * PX
## Shoulder pivot to the grip held in the hand (metres).
const REACH := 0.5
## Metres walked per full stride cycle.
const STRIDE := 1.6
const FLASH_TIME := 0.12
const DEATH_TIME := 0.4
const HEAD_PITCH_LIMIT := 1.2

var outfit_id := ""
var hat_id := ""
var weapon_id := ""
var skin_id := ""

var _visual: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _hat_mount: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _leg_r: Node3D
var _leg_l: Node3D
var _knee_r: Node3D
var _knee_l: Node3D
var _gun_mount: Node3D
var _parts: Array[MeshInstance3D] = []
var _extras: Array[Node3D] = []
var _geoms: Array[GeometryInstance3D] = []
var _gun: Node3D
var _hat: Node3D
var _death_tween: Tween

var _pitch := 0.0
var _phase := 0.0
var _swing := 0.0
var _air := 0.0
var _crouch := 0.0
var _recoil := 0.0
var _flash := 0.0
var _dead := false
## Reload animation: seconds left / total; while > 0 the gun dips and rolls and the off hand
## drops to the hip and back (fetching a new magazine).
var _reload_left := 0.0
var _reload_len := 0.0
var _first_person := false
## Two-handed hold: grip position relative to the shoulder centre (aim space), torso twist,
## and the off-hand point in gun-mount space (null = off hand hangs free).
var _grip := Vector3(0.1, -0.2, -0.4)
var _twist_target := -0.1
var _twist := -0.1
var _support: Variant = null


## Builds the rig. Called by Models.build_avatar().
func setup(p_outfit_id: String, p_hat_id: String) -> void:
	name = "Avatar"
	_visual = _node(self, "Visual", Vector3.ZERO)
	_hips = _node(_visual, "Hips", Vector3(0, HIP_HEIGHT, 0))
	_leg_r = _node(_hips, "LegR", Vector3(2 * PX, 0, 0))
	_leg_l = _node(_hips, "LegL", Vector3(-2 * PX, 0, 0))
	_knee_r = _node(_leg_r, "KneeR", Vector3(0, -LEG_SEGMENT, 0))
	_knee_l = _node(_leg_l, "KneeL", Vector3(0, -LEG_SEGMENT, 0))
	_torso = _node(_hips, "Torso", Vector3.ZERO)
	_head = _node(_torso, "Head", Vector3(0, 12 * PX, 0))
	_hat_mount = _node(_head, "HatMount", Vector3(0, 8 * PX, 0))
	_arm_r = _node(_torso, "ArmR", Vector3(SHOULDER_X, SHOULDER_Y, 0))
	_arm_l = _node(_torso, "ArmL", Vector3(-SHOULDER_X, SHOULDER_Y, 0))
	_gun_mount = _node(_torso, "GunMount", Vector3.ZERO)
	_part(_leg_r, "thigh_r")
	_part(_knee_r, "shin_r")
	_part(_leg_l, "thigh_l")
	_part(_knee_l, "shin_l")
	_part(_torso, "torso")
	_part(_head, "head")
	_part(_arm_r, "arm_r")
	_part(_arm_l, "arm_l")
	set_process(false)
	set_outfit(p_outfit_id)
	set_hat(p_hat_id)
	_apply_pose()


func set_outfit(p_outfit_id: String) -> void:
	outfit_id = p_outfit_id
	var mat := Models.outfit_material(outfit_id)
	for p in _parts:
		p.material_override = mat
	for e in _extras:
		_discard(e)
	_extras.clear()
	_add_extra(_head, "head")
	_add_extra(_torso, "torso")
	_add_extra(_arm_r, "arm")
	_add_extra(_arm_l, "arm")
	_update_antenna()
	_refresh_geoms()


func set_hat(p_hat_id: String) -> void:
	hat_id = p_hat_id
	if _hat:
		_discard(_hat)
	_hat = Models.build_hat(hat_id)
	_hat_mount.add_child(_hat)
	_update_antenna()
	_refresh_geoms()


## Look pitch in radians (positive = up). Rotates the head and swings arms + gun around the shoulders.
func set_look_pitch(rad: float) -> void:
	_pitch = clampf(rad, -PI * 0.5, PI * 0.5)
	if not _dead:
		_apply_pose()


## Advances locomotion: `speed` = horizontal speed in m/s.
func animate(delta: float, speed: float, on_floor: bool, crouching: bool) -> void:
	if _dead:
		return
	var k := 1.0 - exp(-14.0 * delta)
	_crouch = move_toward(_crouch, 1.0 if crouching else 0.0, delta * 7.0)
	_swing = lerpf(_swing, clampf(speed / 4.5, 0.0, 1.2) if on_floor else 0.0, k)
	_air = lerpf(_air, 0.0 if on_floor else 1.0, k)
	_twist = lerpf(_twist, _twist_target, k)
	if on_floor and speed > 0.05:
		_phase = fposmod(_phase + delta * speed * TAU / STRIDE, TAU)
	elif _swing < 0.05:
		_phase = lerpf(_phase, 0.0 if _phase < PI * 0.5 or _phase > PI * 1.5 else PI, k)
	_apply_pose()


## Equips the third-person gun in the right hand ("" = empty hands).
func hold_weapon(p_weapon_id: String, p_skin_id: String) -> void:
	if p_weapon_id == weapon_id and p_skin_id == skin_id and (_gun != null or weapon_id == ""):
		return
	weapon_id = p_weapon_id
	skin_id = p_skin_id
	if _gun:
		_discard(_gun)
		_gun = null
	_support = null
	if weapon_id == "":
		_grip = Vector3(0.1, -0.25, -0.35)
		_twist_target = 0.0
	else:
		_gun = Models.build_gun(weapon_id, skin_id)
		_gun.scale = Vector3.ONE * Models.THIRD_PERSON_GUN_SCALE
		_gun_mount.add_child(_gun)
		var support := _gun.get_node_or_null(^"Support") as Node3D
		if support:
			_support = support.position * Models.THIRD_PERSON_GUN_SCALE
		_solve_hold(-0.06 if weapon_id == "rocket" else -0.2)
	_twist = _twist_target
	_refresh_geoms()
	if not _dead:
		_apply_pose()


## Small recoil kick on the arms and gun.
func play_shoot() -> void:
	if _dead:
		return
	_recoil = 1.0
	set_process(true)


## Topples backwards over DEATH_TIME seconds. Further calls while dead are ignored.
func play_death() -> void:
	if _dead:
		return
	_dead = true
	_recoil = 0.0
	if _death_tween:
		_death_tween.kill()
	if not is_inside_tree():
		_visual.rotation.x = PI * 0.5
		_visual.position.y = 0.12
		return
	_death_tween = create_tween().set_parallel()
	_death_tween.tween_property(_visual, ^"rotation:x", PI * 0.5, DEATH_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(_visual, ^"position:y", 0.12, DEATH_TIME)


## Restores the standing pose (after death or teleport).
func reset_pose() -> void:
	if _death_tween:
		_death_tween.kill()
		_death_tween = null
	_dead = false
	_visual.transform = Transform3D.IDENTITY
	_phase = 0.0
	_swing = 0.0
	_air = 0.0
	_crouch = 0.0
	_recoil = 0.0
	_reload_left = 0.0
	_reload_len = 0.0
	_twist = _twist_target
	_set_flash(false)
	_apply_pose()

## Aborts a reload animation (weapon switch, death).
func stop_reload() -> void:
	if _reload_len <= 0.0:
		return
	_reload_left = 0.0
	set_process(true)



## Local player's own body: true = shadows only (invisible, still casts a shadow).
func set_first_person(enabled: bool) -> void:
	_first_person = enabled
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for g in _geoms:
		g.cast_shadow = mode


## Briefly tints the whole avatar red (shared overlay material, no allocation).
func flash_hit() -> void:
	_set_flash(true)
	set_process(true)


## Right-hand gun mount (child of the torso). The held gun is its only child.
func get_gun_mount() -> Node3D:
	return _gun_mount


## The currently held gun node (null when empty-handed).
func get_gun() -> Node3D:
	return _gun


## Head pivot (neck joint); its children follow head pitch.
func get_head() -> Node3D:
	return _head


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_set_flash(false)
	if _recoil > 0.0:
		_recoil = move_toward(_recoil, 0.0, delta * 7.0)
	# _reload_len stays > 0 for one extra frame so the final pose is applied at zero.
	var reload_active := _reload_len > 0.0
	if _reload_left > 0.0:
		_reload_left = maxf(0.0, _reload_left - delta)
	elif reload_active:
		_reload_len = 0.0
	if (_recoil > 0.0 or reload_active) and not _dead:
		_apply_pose()
	if _flash <= 0.0 and _recoil <= 0.0 and _reload_len <= 0.0:
		set_process(false)


func _set_flash(on: bool) -> void:
	_flash = FLASH_TIME if on else 0.0
	var overlay: Material = Models.hit_overlay_material() if on else null
	for g in _geoms:
		g.material_overlay = overlay


## Picks the torso twist and grip position so both hands reach the gun: the grip sits REACH
## from the right shoulder, the twist brings the left shoulder within REACH of the support.
func _solve_hold(grip_y: float) -> void:
	const GRIP_X := 0.1
	var best_err := INF
	_twist_target = -0.1
	_grip = Vector3(GRIP_X, grip_y, -0.4)
	for i in 21:
		var t := -0.8 * i / 20.0
		var rs := Vector3(SHOULDER_X * cos(t), 0.0, -SHOULDER_X * sin(t))
		var d2 := REACH * REACH - pow(GRIP_X - rs.x, 2) - grip_y * grip_y
		if d2 <= 0.0:
			continue
		var grip := Vector3(GRIP_X, grip_y, rs.z - sqrt(d2))
		var err := 0.0
		if _support != null:
			err = absf((grip + (_support as Vector3) + rs).length() - REACH)
		else:
			err = absf(t + 0.1)
		if err < best_err - 0.004:
			best_err = err
			_twist_target = t
			_grip = grip


func _apply_pose() -> void:
	var swing := sin(_phase) * _swing
	var stride := swing * 0.7 * (1.0 - 0.45 * _crouch)
	var hip_y := HIP_HEIGHT - CROUCH_DROP * _crouch
	var bend := acos(clampf(hip_y / (2.0 * LEG_SEGMENT), -1.0, 1.0))
	_hips.position.y = hip_y - absf(sin(_phase)) * 0.03 * _swing
	var c := cos(_phase) * _swing
	_leg_r.rotation.x = bend + stride + 0.6 * _air
	_leg_l.rotation.x = bend - stride - 0.25 * _air
	_knee_r.rotation.x = -2.0 * bend - maxf(0.0, c) * 0.8 - 1.0 * _air
	_knee_l.rotation.x = -2.0 * bend - maxf(0.0, -c) * 0.8 - 0.3 * _air

	var lean := -0.32 * _crouch - 0.06 * minf(_swing, 1.0)
	var torso_basis := Basis.from_euler(Vector3(lean, _twist, 0.0))
	_torso.basis = torso_basis
	var inv := torso_basis.inverse()
	_head.basis = inv * Basis(Vector3.RIGHT, clampf(_pitch, -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT))

	var aim := Basis(Vector3.RIGHT, _pitch)
	var center := torso_basis * Vector3(0.0, SHOULDER_Y, 0.0)
	var bob := Vector3(0.0, -absf(sin(_phase)) * 0.02 * _swing + 0.015 * _recoil, 0.07 * _recoil)
	var r := _reload_envelope()
	var reload_tilt := Basis(Vector3.RIGHT, -0.55 * r) * Basis(Vector3.BACK, 0.6 * r)
	var mount := Transform3D(inv * aim * Basis(Vector3.RIGHT, 0.2 * _recoil) * reload_tilt,
		inv * (center + aim * (_grip + bob + Vector3(-0.05, -0.08, 0.1) * r)))
	_gun_mount.transform = mount
	if _gun == null:
		_arm_r.basis = inv * Basis(Vector3.RIGHT, swing * 0.8 + 0.1 * _air)
	else:
		_arm_r.basis = _point_down_to(mount.origin - _arm_r.position)
	var fetching := _reload_fetch()
	if _support != null and fetching <= 0.0:
		_arm_l.basis = _point_down_to(mount * (_support as Vector3) - _arm_l.position)
	elif _support != null:
		# Off hand swings down to the belt for a fresh magazine, then back to the gun.
		var hold := _point_down_to(mount * (_support as Vector3) - _arm_l.position)
		_arm_l.basis = hold.slerp(inv * Basis(Vector3.RIGHT, 0.25), fetching)
	else:
		_arm_l.basis = inv * Basis(Vector3.RIGHT, -swing * 0.8 - 0.4 * _air) * Basis(Vector3.BACK, -0.08)


## 0..1 weight of the reload pose: eases in over the first 15%, out over the last 15%.
func _reload_envelope() -> float:
	if _reload_left <= 0.0 or _reload_len <= 0.0:
		return 0.0
	var u := 1.0 - _reload_left / _reload_len
	return smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u))


## 0..1 how far the off hand is away fetching a magazine (peaks mid-reload).
func _reload_fetch() -> float:
	if _reload_left <= 0.0 or _reload_len <= 0.0:
		return 0.0
	var u := 1.0 - _reload_left / _reload_len
	return smoothstep(0.2, 0.4, u) * (1.0 - smoothstep(0.6, 0.8, u))


## Third-person reload over `duration` seconds. Ignored while dead.
func play_reload(duration: float) -> void:
	if _dead or duration <= 0.0:
		return
	_reload_len = duration
	_reload_left = duration
	set_process(true)


## Basis whose -Y axis (an arm hanging from its shoulder) points along `dir`.
static func _point_down_to(dir: Vector3) -> Basis:
	return Basis(Quaternion(Vector3.DOWN, dir.normalized()))


func _node(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


func _part(parent: Node3D, part: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = Models.avatar_part_mesh(part)
	parent.add_child(mi)
	_parts.append(mi)


func _add_extra(parent: Node3D, mount: String) -> void:
	var e := Models.build_outfit_extra(outfit_id, mount)
	if e:
		parent.add_child(e)
		_extras.append(e)


## The robot antenna would poke through hats, so it only shows bareheaded.
func _update_antenna() -> void:
	if outfit_id != "robot":
		return
	for e in _extras:
		if e.get_parent() == _head:
			e.visible = hat_id == "none" or hat_id == ""


## Detaches immediately (so _refresh_geoms no longer sees it) and frees at frame end.
static func _discard(n: Node) -> void:
	n.get_parent().remove_child(n)
	n.queue_free()


func _refresh_geoms() -> void:
	_geoms.clear()
	for g in find_children("*", "GeometryInstance3D", true, false):
		_geoms.append(g)
	set_first_person(_first_person)
	if _flash > 0.0:
		_set_flash(true)
