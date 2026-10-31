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
const SLASH_TIME := 0.4
const THROW_TIME := 0.5
## Hips height while sliding (the body lies back on one bent leg).
const SLIDE_HIP := 0.3
## Prone: the whole body tips forward flat (face down), lifted off the floor by its thickness and
## shifted back so the head ends up over the player's origin, where the eyes are.
const PRONE_LIFT := 0.14
const PRONE_BACK := 1.25

var outfit_id := ""
var hat_id := ""
var weapon_id := ""
var skin_id := ""
## Charm hung on held guns (Data.CHARMS id); set before hold_weapon().
var charm_id := "none"
## Win emote being performed (Data.EMOTES id, "" for none) and its running time.
var emote := ""
var _emote_t := 0.0

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
var _prone := 0.0
var _recoil := 0.0
var _flash := 0.0
var _dead := false
var _protected := false
var _tint: Material
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
## Locomotion extras fed by set_motion(): slide and grapple blends, smoothed lean, and the
## direction of travel in body space (x right, y forward; zero when standing).
var _slide := 0.0
var _sliding := false
var _lean := 0.0
var _lean_target := 0.0
var _move_dir := Vector2.ZERO
var _grapple := 0.0
var _grappling := false
var _sprint := 0.0
## One-shot actions: seconds left of a knife slash / grenade throw.
var _slash_left := 0.0
var _slash_side := 1.0
var _throw_left := 0.0
## Weapon inspect (Player.FLAG_INSPECT, set_inspect): `_inspect` blends the gun up in front of the
## chest and turns it side to side over `_inspect_t` seconds; switched off it eases back.
var _inspect_on := false
var _inspect := 0.0
var _inspect_t := 0.0


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


## Movement state beyond speed: sliding, lean (-1..1, left negative), velocity in body space
## (x right, y forward, m/s) and whether a grapple line is out. Call before animate().
func set_motion(sliding: bool, lean: float, local_velocity: Vector2, grappling: bool) -> void:
	_sliding = sliding
	_lean_target = lean
	_grappling = grappling
	var spd := local_velocity.length()
	_move_dir = local_velocity / spd if spd > 0.3 else Vector2.ZERO


## Advances locomotion: `speed` = horizontal speed in m/s.
func animate(delta: float, speed: float, on_floor: bool, crouching: bool, prone: bool) -> void:
	if _dead or not emote.is_empty():
		return
	var k := 1.0 - exp(-14.0 * delta)
	_crouch = move_toward(_crouch, 1.0 if crouching else 0.0, delta * 7.0)
	_prone = move_toward(_prone, 1.0 if prone else 0.0, delta * 4.0)
	_slide = move_toward(_slide, 1.0 if _sliding else 0.0, delta * 9.0)
	_grapple = move_toward(_grapple, 1.0 if _grappling else 0.0, delta * 8.0)
	_lean = lerpf(_lean, _lean_target, k)
	_sprint = lerpf(_sprint, clampf((speed - 6.0) / 1.5, 0.0, 1.0) if on_floor and not _sliding else 0.0, k)
	_swing = lerpf(_swing, clampf(speed / 4.5, 0.0, 1.2) if on_floor and not _sliding else 0.0, k)
	_air = lerpf(_air, 0.0 if on_floor or _sliding else 1.0, k)
	_twist = lerpf(_twist, _twist_target, k)
	if on_floor and speed > 0.05 and not _sliding:
		# Walking backwards plays the stride in reverse.
		var dir := -1.0 if _move_dir.y < -0.3 else 1.0
		_phase = fposmod(_phase + dir * delta * speed * TAU / STRIDE, TAU)
	elif _swing < 0.05:
		_phase = lerpf(_phase, 0.0 if _phase < PI * 0.5 or _phase > PI * 1.5 else PI, k)
	if _slash_left > 0.0:
		_slash_left = maxf(0.0, _slash_left - delta)
	if _throw_left > 0.0:
		_throw_left = maxf(0.0, _throw_left - delta)
	_inspect = move_toward(_inspect, 1.0 if _inspect_on else 0.0, delta * 4.0)
	if _inspect > 0.0:
		_inspect_t += delta
	_apply_pose()


## Third-person weapon inspect on / off (remote players: their FLAG_INSPECT state flag).
func set_inspect(on: bool) -> void:
	if on and not _inspect_on and _inspect <= 0.0:
		_inspect_t = 0.0
	_inspect_on = on


## Third-person knife slash (or quick melee): the right arm sweeps across the body,
## alternating sides.
func play_slash() -> void:
	if _dead:
		return
	_slash_left = SLASH_TIME
	_slash_side = -_slash_side


## Third-person grenade throw: the off hand winds up behind the head and flings forward.
func play_throw() -> void:
	if _dead:
		return
	_throw_left = THROW_TIME


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
		_gun = Models.build_gun(weapon_id, skin_id, charm_id)
		_gun.scale = Vector3.ONE * Models.THIRD_PERSON_GUN_SCALE
		_gun_mount.add_child(_gun)
		_gun.visible = emote.is_empty()
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


## Crumples and topples over DEATH_TIME seconds, backwards, forwards or to a side (random), with
## the knees buckling first. Further calls while dead are ignored.
func play_death() -> void:
	if _dead:
		return
	_dead = true
	emote = ""
	_recoil = 0.0
	_slash_left = 0.0
	_throw_left = 0.0
	if _death_tween:
		_death_tween.kill()
	var falls := [[^"rotation:x", PI * 0.5], [^"rotation:x", -PI * 0.5], [^"rotation:z", PI * 0.5], [^"rotation:z", -PI * 0.5]]
	var fall: Array = falls[randi() % falls.size()] if is_inside_tree() else falls[0]
	# Arms go limp and out to the sides.
	_arm_r.basis = Basis(Vector3.BACK, 0.9) * Basis(Vector3.RIGHT, 0.4)
	_arm_l.basis = Basis(Vector3.BACK, -0.9) * Basis(Vector3.RIGHT, 0.4)
	if not is_inside_tree():
		_visual.set_indexed(fall[0], fall[1])
		_visual.position.y = 0.12
		return
	_death_tween = create_tween()
	# Knees give way, then the body falls.
	_death_tween.tween_property(_knee_r, ^"rotation:x", -1.2, DEATH_TIME * 0.35)
	_death_tween.parallel().tween_property(_knee_l, ^"rotation:x", -1.0, DEATH_TIME * 0.35)
	_death_tween.parallel().tween_property(_hips, ^"position:y", HIP_HEIGHT * 0.7, DEATH_TIME * 0.35)
	_death_tween.tween_property(_visual, fall[0], fall[1], DEATH_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.parallel().tween_property(_visual, ^"position:y", 0.12, DEATH_TIME)
	_death_tween.tween_property(_visual, ^"position:y", 0.2, 0.08).set_ease(Tween.EASE_OUT)
	_death_tween.tween_property(_visual, ^"position:y", 0.12, 0.1).set_ease(Tween.EASE_IN)


## Restores the standing pose (after death or teleport).
func reset_pose() -> void:
	if _death_tween:
		_death_tween.kill()
		_death_tween = null
	_dead = false
	emote = ""
	if _gun:
		_gun.visible = true
	_visual.transform = Transform3D.IDENTITY
	_phase = 0.0
	_swing = 0.0
	_air = 0.0
	_crouch = 0.0
	_prone = 0.0
	_recoil = 0.0
	_reload_left = 0.0
	_reload_len = 0.0
	_slide = 0.0
	_sliding = false
	_lean = 0.0
	_lean_target = 0.0
	_grapple = 0.0
	_grappling = false
	_sprint = 0.0
	_slash_left = 0.0
	_throw_left = 0.0
	_inspect_on = false
	_inspect = 0.0
	_twist = _twist_target
	_set_flash(false)
	_apply_pose()


func is_reloading() -> bool:
	return _reload_left > 0.0


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


## Plays win emote `id` (Data.EMOTES) on a loop until reset_pose() or stop_emote(). A dead
## body gets back up first. The gun is put away while dancing.
func play_emote(id: String) -> void:
	if not Models.CATALOG.EMOTES.has(id):
		id = "wave"
	if _dead:
		reset_pose()
	emote = id
	_emote_t = 0.0
	_visual.transform = Transform3D.IDENTITY
	if _gun:
		_gun.visible = false
	set_process(true)


func stop_emote() -> void:
	if emote.is_empty():
		return
	emote = ""
	if _gun:
		_gun.visible = true
	_visual.transform = Transform3D.IDENTITY
	_apply_pose()


## Shop icons: strikes emote `id` as it looks `t` seconds in.
func pose_emote(id: String, t: float) -> void:
	play_emote(id)
	_emote_t = t
	_apply_emote(t)


func _process(delta: float) -> void:
	if not emote.is_empty():
		_emote_t += delta
		_apply_emote(_emote_t)
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
	if (_recoil > 0.0 or reload_active) and not _dead and emote.is_empty():
		_apply_pose()
	if _flash <= 0.0 and _recoil <= 0.0 and _reload_len <= 0.0 and emote.is_empty():
		set_process(false)


## Full-body pose of the current emote at `t` seconds. Arm directions are in body space (x
## right, y up, -z forward), from the shoulder to the hand.
func _apply_emote(t: float) -> void:
	var hips := Vector3(0, HIP_HEIGHT, 0)
	var torso := Basis.IDENTITY
	var head := Basis.IDENTITY
	var arm_r := Vector3.DOWN
	var arm_l := Vector3.DOWN
	var leg := Vector4.ZERO # leg_r x, leg_r z, leg_l x, leg_l z
	var knee := Vector2.ZERO
	var visual := Transform3D.IDENTITY
	match emote:
		"wave":
			arm_r = Vector3(0.45 + 0.3 * sin(t * 9.0), 0.9, -0.15)
			head = Basis(Vector3.BACK, 0.12 * sin(t * 4.5))
		"flex":
			var p := 0.5 + 0.5 * sin(t * 5.0)
			arm_r = Vector3(0.9, 0.2 + 0.5 * p, 0.0)
			arm_l = Vector3(-0.9, 0.2 + 0.5 * p, 0.0)
			torso = Basis(Vector3.RIGHT, 0.12 * p)
			hips.y -= 0.03 * p
			knee = Vector2(-0.2, -0.2) * p
			leg = Vector4(0.1, 0.0, 0.1, 0.0) * p
		"dance":
			var s := sin(t * 7.0)
			hips.x = 0.07 * s
			hips.y -= absf(cos(t * 7.0)) * 0.04
			torso = Basis(Vector3.BACK, -0.18 * s)
			head = Basis(Vector3.BACK, 0.22 * s)
			arm_r = Vector3(0.6 + 0.3 * s, 0.3, -0.5)
			arm_l = Vector3(-0.6 + 0.3 * s, 0.3, -0.5)
			leg = Vector4(maxf(0.0, s) * 0.7, 0.0, maxf(0.0, -s) * 0.7, 0.0)
			knee = Vector2(-maxf(0.0, s) * 1.1, -maxf(0.0, -s) * 1.1)
		"salute":
			var up := smoothstep(0.0, 0.35, t)
			arm_r = Vector3.DOWN.lerp(Vector3(-0.25, 0.55, -0.8), up)
			head = Basis(Vector3.RIGHT, 0.08 * up)
		"dab":
			var cyc := fmod(t, 1.6)
			var on := smoothstep(0.0, 0.18, cyc) * (1.0 - smoothstep(1.1, 1.35, cyc))
			arm_r = Vector3.DOWN.lerp(Vector3(0.75, 0.62, -0.15), on)
			arm_l = Vector3.DOWN.lerp(Vector3(0.55, 0.45, -0.7), on)
			head = Basis(Vector3.RIGHT, -0.5 * on) * Basis(Vector3.UP, 0.4 * on)
			torso = Basis(Vector3.BACK, -0.15 * on)
		"spin":
			visual = Transform3D(Basis(Vector3.UP, t * 9.0), Vector3.ZERO)
			arm_r = Vector3(1.0, 0.1, 0.0)
			arm_l = Vector3(-1.0, 0.1, 0.0)
			head = Basis(Vector3.RIGHT, -0.2)
		"jumps":
			var s := 0.5 - 0.5 * cos(t * 8.0)
			var a := s * 2.7
			arm_r = Vector3(sin(a), -cos(a), 0.0)
			arm_l = Vector3(-sin(a), -cos(a), 0.0)
			leg = Vector4(0.0, 0.32 * s, 0.0, -0.32 * s)
			visual = Transform3D(Basis.IDENTITY, Vector3(0, 0.12 * sin(s * PI), 0))
		"backflip":
			var cyc := fmod(t, 1.8)
			var crouch := smoothstep(0.0, 0.25, cyc) * (1.0 - smoothstep(0.25, 0.35, cyc)) \
				+ smoothstep(1.2, 1.3, cyc) * (1.0 - smoothstep(1.4, 1.7, cyc))
			hips.y -= 0.22 * crouch
			knee = Vector2(-1.2, -1.2) * crouch
			leg = Vector4(0.6, 0.0, 0.6, 0.0) * crouch
			var air := clampf((cyc - 0.35) / 0.85, 0.0, 1.0)
			if air > 0.0 and air < 1.0:
				var ang := -TAU * smoothstep(0.0, 1.0, air)
				var center := Vector3(0, 1.0, 0)
				var lift := Vector3(0, 1.1 * sin(air * PI), 0)
				var rot := Basis(Vector3.RIGHT, -ang)
				visual = Transform3D(rot, center + lift - rot * center)
				knee = Vector2(-1.6, -1.6)
				leg = Vector4(1.3, 0.0, 1.3, 0.0)
				arm_r = Vector3(0.3, 0.2, -0.9)
				arm_l = Vector3(-0.3, 0.2, -0.9)
			else:
				arm_r = Vector3(0.5, 0.85, 0.0)
				arm_l = Vector3(-0.5, 0.85, 0.0)
		"chicken":
			var f := sin(t * 14.0)
			arm_r = Vector3(0.55 + 0.35 * f, -0.55, 0.15)
			arm_l = Vector3(-0.55 - 0.35 * f, -0.55, 0.15)
			head = Basis(Vector3.RIGHT, 0.25 * sin(t * 7.0))
			hips.y -= 0.12 + 0.03 * absf(f)
			knee = Vector2(-0.7, -0.7)
			leg = Vector4(0.35, 0.15, 0.35, -0.15)
	_visual.transform = visual
	_hips.position = hips
	_torso.basis = torso
	var inv := torso.inverse()
	_head.basis = head
	_arm_r.basis = inv * _point_down_to(arm_r)
	_arm_l.basis = inv * _point_down_to(arm_l)
	_leg_r.rotation = Vector3(leg.x, 0.0, leg.y)
	_leg_l.rotation = Vector3(leg.z, 0.0, leg.w)
	_knee_r.rotation.x = knee.x
	_knee_l.rotation.x = knee.y


func _set_flash(on: bool) -> void:
	_flash = FLASH_TIME if on else 0.0
	_apply_overlay()


## Spawn protection shimmer; a hit flash shows over it while active.
func set_protected(on: bool) -> void:
	if on == _protected:
		return
	_protected = on
	_apply_overlay()


## A lasting tint over the whole avatar (an Infected's green; null clears it). The hit flash
## and spawn shimmer show over it while active.
func set_tint(mat: Material) -> void:
	_tint = mat
	_apply_overlay()


func get_tint() -> Material:
	return _tint


func _apply_overlay() -> void:
	var overlay: Material = _tint
	if _flash > 0.0:
		overlay = Models.hit_overlay_material()
	elif _protected:
		overlay = Models.shield_overlay_material()
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
	if not emote.is_empty():
		_apply_emote(_emote_t)
		return
	var swing := sin(_phase) * _swing
	var stride := swing * 0.7 * (1.0 - 0.45 * _crouch)
	# Strafing swings the legs sideways instead of forward.
	var fwd_share := 1.0 if _move_dir == Vector2.ZERO else absf(_move_dir.y)
	var side_share := _move_dir.x
	var hip_y := lerpf(HIP_HEIGHT - CROUCH_DROP * _crouch, SLIDE_HIP, _slide)
	var bend := acos(clampf((HIP_HEIGHT - CROUCH_DROP * _crouch) / (2.0 * LEG_SEGMENT), -1.0, 1.0))
	_hips.position = Vector3(_lean * 0.1, hip_y - absf(sin(_phase)) * 0.03 * _swing, 0.0)
	var c := cos(_phase) * _swing
	var leg_r := bend + stride * fwd_share + 0.6 * _air
	var leg_l := bend - stride * fwd_share - 0.25 * _air
	var knee_r := -2.0 * bend - maxf(0.0, c) * 0.8 - 1.0 * _air
	var knee_l := -2.0 * bend - maxf(0.0, -c) * 0.8 - 0.3 * _air
	# Slide: leading leg out straight, the other folded under.
	leg_r = lerpf(leg_r, 1.45, _slide)
	leg_l = lerpf(leg_l, 0.55, _slide)
	knee_r = lerpf(knee_r, -0.1, _slide)
	knee_l = lerpf(knee_l, -2.1, _slide)
	# Prone: legs out straight behind; crawling kicks them out sideways in turn.
	var crawl := swing * 0.5
	_leg_r.rotation = Vector3(lerpf(leg_r, 0.0, _prone), 0.0, lerpf(stride * side_share * 0.6, 0.12 + crawl, _prone))
	_leg_l.rotation = Vector3(lerpf(leg_l, 0.0, _prone), 0.0, lerpf(-stride * side_share * 0.6, -0.12 + crawl, _prone))
	_knee_r.rotation.x = lerpf(knee_r, -maxf(0.0, crawl) * 1.2, _prone)
	_knee_l.rotation.x = lerpf(knee_l, -maxf(0.0, -crawl) * 1.2, _prone)
	_visual.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 * _prone), Vector3(0.0, PRONE_LIFT, PRONE_BACK) * _prone)

	# Lean forward when crouching/sprinting, back when sliding; peeking rolls the upper body.
	var lean := -0.32 * _crouch - 0.06 * minf(_swing, 1.0) - 0.16 * _sprint
	lean = lerpf(lerpf(lean, 0.5, _slide), 0.0, _prone)
	var torso_basis := Basis.from_euler(Vector3(lean, _twist, -_lean * 0.55))
	_torso.basis = torso_basis
	var inv := torso_basis.inverse()
	# Lying face down, the head and the aim tilt back up by the body's quarter turn.
	var lift := PI * 0.5 * _prone
	_head.basis = inv * Basis(Vector3.RIGHT, clampf(_pitch, -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT) + lift)

	# Sprinting carries the gun low across the chest (muzzle down).
	var aim_pitch := lerpf(_pitch, -0.55, _sprint * 0.8) + lift
	var aim := Basis(Vector3.RIGHT, aim_pitch)
	var center := torso_basis * Vector3(0.0, SHOULDER_Y, 0.0)
	var bob := Vector3(0.0, -absf(sin(_phase)) * 0.02 * _swing + 0.015 * _recoil, 0.07 * _recoil)
	var r := _reload_envelope()
	var reload_tilt := Basis(Vector3.RIGHT, -0.55 * r) * Basis(Vector3.BACK, 0.6 * r)
	# Inspect: the gun comes up in front of the chest, its side turned toward the face, and swings
	# slowly from one side to the other.
	var ins := _inspect * _inspect * (3.0 - 2.0 * _inspect)
	var ins_turn := Basis(Vector3.UP, (0.9 + 0.6 * sin(_inspect_t * 2.1)) * ins) * Basis(Vector3.BACK, 0.45 * ins) \
		* Basis(Vector3.RIGHT, 0.3 * ins)
	var mount := Transform3D(inv * aim * Basis(Vector3.RIGHT, 0.2 * _recoil) * reload_tilt * ins_turn,
		inv * (center + aim * (_grip + bob + Vector3(-0.05, -0.08, 0.1) * r + Vector3(-0.12, 0.12, 0.14) * ins)))
	var slash := _slash_amount()
	if slash.x != 0.0 or slash.y != 0.0:
		# Swing the whole hold around the right shoulder: across the body and downward.
		var pivot := inv * center
		var turn := Basis(Vector3.UP, slash.x) * Basis(Vector3.RIGHT, slash.y)
		mount = Transform3D(turn, pivot - turn * pivot) * mount
	_gun_mount.transform = mount
	if _gun == null:
		_arm_r.basis = inv * Basis(Vector3.RIGHT, swing * 0.8 + 0.1 * _air)
	else:
		_arm_r.basis = _point_down_to(mount.origin - _arm_r.position)
	var fetching := _reload_fetch()
	var off_hand: Variant = _off_hand_pose(inv)
	if off_hand != null:
		_arm_l.basis = off_hand
	elif _support != null and fetching <= 0.0:
		_arm_l.basis = _point_down_to(mount * (_support as Vector3) - _arm_l.position)
	elif _support != null:
		# Off hand swings down to the belt for a fresh magazine, then back to the gun.
		var hold := _point_down_to(mount * (_support as Vector3) - _arm_l.position)
		_arm_l.basis = hold.slerp(inv * Basis(Vector3.RIGHT, 0.25), fetching)
	else:
		_arm_l.basis = inv * Basis(Vector3.RIGHT, -swing * 0.8 - 0.4 * _air) * Basis(Vector3.BACK, -0.08)


## Slash swing as (yaw, pitch) offsets around the shoulder: wind up, cut fast, recover. The held
## melee weapon's `swing` shapes it: a slash cuts across the body (alternating sides), a chop
## comes down from overhead, a sweep goes wide and flat. A quick melee with a gun slashes.
func _slash_amount() -> Vector2:
	if _slash_left <= 0.0:
		return Vector2.ZERO
	var u := 1.0 - _slash_left / SLASH_TIME
	var w: Dictionary = Models.CATALOG.WEAPONS.get(weapon_id, {})
	var start := Vector2(-0.9 * _slash_side, 0.35)
	var finish := Vector2(0.8 * _slash_side, -0.45)
	match str(w.get("swing", "slash")):
		"chop":
			start = Vector2(0.15 * _slash_side, 1.15)
			finish = Vector2(-0.05 * _slash_side, -0.6)
		"sweep":
			start = Vector2(-1.25 * _slash_side, 0.05)
			finish = Vector2(1.15 * _slash_side, -0.1)
	if u < 0.25:
		return start * smoothstep(0.0, 0.25, u)
	if u < 0.5:
		var t := 1.0 - pow(1.0 - (u - 0.25) / 0.25, 3.0)
		return start.lerp(finish, t)
	return finish * (1.0 - smoothstep(0.5, 1.0, u))


## Left arm override for a throw or a held grapple line (torso space), or null.
func _off_hand_pose(inv: Basis) -> Variant:
	if _throw_left > 0.0:
		var u := 1.0 - _throw_left / THROW_TIME
		var back := inv * Basis(Vector3.RIGHT, PI * 0.95) * Basis(Vector3.BACK, 0.3)
		var forward := inv * Basis(Vector3.RIGHT, PI * 0.45)
		if u < 0.35:
			return Basis.IDENTITY.slerp(back, smoothstep(0.0, 0.3, u)) if _support == null else back
		if u < 0.6:
			return back.slerp(forward, smoothstep(0.35, 0.55, u))
		return forward
	if _grapple > 0.01:
		# Arm up and forward along the line.
		return inv * Basis(Vector3.RIGHT, lerpf(0.4, 2.3, _grapple)) * Basis(Vector3.BACK, -0.15)
	return null


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
	_apply_overlay()
