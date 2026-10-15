class_name Player
extends CharacterBody3D
## One combatant. The same node plays three roles:
##   LOCAL  - the human at this machine: reads input, simulates movement and shooting.
##   BOT    - server only: a BotBrain fills the intent fields, then it simulates like LOCAL.
##   REMOTE - a network proxy: interpolates snapshots received from the server.
## Health, kills and respawns are decided by the server (World) and pushed into every copy.

enum Mode { LOCAL, BOT, REMOTE }

const WALK_SPEED := 5.4
const SPRINT_SPEED := 7.6
const CROUCH_SPEED := 2.8
const ADS_SPEED := 3.4
const GROUND_ACCEL := 60.0
const AIR_ACCEL := 14.0
const GRAVITY := 21.0
const JUMP_VELOCITY := 7.2
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.4
const STAND_EYE := 1.6
## Avatar crouch lowers the body 0.35 m, so the eyes and hitboxes drop by the same amount.
const CROUCH_DROP := 0.35
const RADIUS := 0.4
const SWITCH_TIME := 0.32
const MELEE_TIME := 0.45
const GRENADE_COOLDOWN := 0.9
## A grenade pressed this close to the end of the throw cooldown is buffered and thrown when it
## ends; earlier presses are dropped so a stale throw never goes off mid-fight.
const GRENADE_BUFFER := 0.25
const HITSCAN_RANGE := 300.0
const MASK_WORLD := 1
const MASK_HITBOX := 4
const INTERP_DELAY := 0.1
const SEND_INTERVAL := 1.0 / 30.0
const MOUSE_SCALE := 0.0022
const MAX_PITCH := deg_to_rad(88.0)

const FLAG_CROUCH := 1
const FLAG_FLOOR := 2
const FLAG_AIM := 4
const FLAG_SPRINT := 8
const FLAG_RELOAD := 16
const FLAG_NEEDS_AMMO := 32

static var _weapon_ids: Array = []

var id := 0
var info := {}
var mode := Mode.REMOTE
var is_bot := false
var world: World
var health := Data.MAX_HEALTH
var alive := true
var grenades: int = Data.GRENADE.per_life
## Who last damaged us and when (World.now() seconds); bots use it to turn and fight back.
var last_attacker := 0
var last_hurt_time := -100.0
## World.now() until which spawn protection is shown (set by the server's _s_protection).
var protected_until := -100.0

var yaw := 0.0
var pitch := 0.0

# Intent: written by input (LOCAL) or BotBrain (BOT) each physics frame.
var in_move := Vector2.ZERO
var in_jump := false
var in_crouch := false
var in_sprint := false
var in_fire := false
var in_aim := false
var in_reload := false
var in_slot := -1
var in_grenade := false
var in_melee := false

var slots: Array[String] = []
var current_slot := 0
var previous_slot := 1
## weapon id -> Vector2i(magazine, reserve)
var ammo := {}
var fire_cooldown := 0.0
var switch_timer := 0.0
var reload_timer := 0.0
var reloading := false
var melee_timer := 0.0
var grenade_cooldown := 0.0
var bloom := 0.0
## Temporary camera kick in degrees; decays back to zero.
var recoil := 0.0
var aim_blend := 0.0
var crouch_blend := 0.0
var crouching := false
var sprinting := false
var anim_speed := 0.0
var on_floor_visual := true

var avatar: Avatar
var head: Node3D
var camera: Camera3D
var viewmodel: Viewmodel
var nametag: Label3D
var brain: BotBrain

var _shape: CapsuleShape3D
var _collider: CollisionShape3D
var _hit_head: Area3D
var _hit_body: Area3D
var _hit_head_col: CollisionShape3D
var _hit_body_col: CollisionShape3D
var _hit_body_shape: BoxShape3D
var _exclude: Array[RID] = []
var _trigger_down := false
var _step_timer := 0.0
var _was_on_floor := true
var _shown_weapon := ""
var _muzzle: Node3D
var _send_timer := 0.0
var _snapshots: Array = []
var _remote_flags := FLAG_FLOOR
var _last_visual_pos := Vector3.ZERO
var _applied_crouch := -1.0
var _fall_speed := 0.0
var _stand_query: PhysicsShapeQueryParameters3D
## Match mutator effects (see Data.MUTATORS), set once in _ready from Net.config.
var gravity_scale := 1.0
var speed_scale := 1.0
var _head_hit_y := 1.56
## REMOTE: seconds the reload flag has stayed on with no reload pose playing.
var _reload_gap := 0.0
## REMOTE: seconds left in which a reload flag still set in buffered snapshots is stale because
## the player fired (which cancels a shotgun's shell-by-shell reload); see remote_fired().
var _reload_hold := 0.0
## LOCAL, while dead: where the death cam settles and who it watches (null: look at the corpse).
var _death_cam_eye := Vector3.ZERO
var _death_cam_target: Player


func setup(p_world: World, p_id: int, p_info: Dictionary, p_mode: Mode, p_is_bot: bool) -> void:
	world = p_world
	id = p_id
	info = p_info
	mode = p_mode
	is_bot = p_is_bot
	name = "P%d" % p_id
	slots = [str(info.primary), str(info.secondary), "knife"]
	refill_ammo()


static func weapon_index(weapon_id: String) -> int:
	if _weapon_ids.is_empty():
		_weapon_ids = Data.WEAPONS.keys()
	return _weapon_ids.find(weapon_id)


static func weapon_from_index(index: int) -> String:
	if _weapon_ids.is_empty():
		_weapon_ids = Data.WEAPONS.keys()
	return _weapon_ids[index] if index >= 0 and index < _weapon_ids.size() else "knife"


func _ready() -> void:
	collision_layer = 2
	collision_mask = MASK_WORLD
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	floor_constant_speed = true
	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = STAND_HEIGHT
	_collider = CollisionShape3D.new()
	_collider.shape = _shape
	_collider.position.y = STAND_HEIGHT * 0.5
	add_child(_collider)

	avatar = Models.build_avatar(str(info.outfit), str(info.hat))
	add_child(avatar)

	head = Node3D.new()
	head.name = "Head"
	head.position.y = STAND_EYE
	add_child(head)

	var head_box := BoxShape3D.new()
	head_box.size = Vector3(0.52, 0.52, 0.52)
	match str(Net.config.mutator):
		"low_gravity":
			gravity_scale = 0.42
		"speed":
			speed_scale = 1.3
		"big_heads":
			# Head pivots at the neck (1.35 m); scaling it 1.8x lifts its centre to ~1.75 m.
			head_box.size = Vector3.ONE * 0.52 * 1.8
			_head_hit_y = 1.35 + 0.225 * 1.8
			# Scale the head's children: the pivot's own basis is rewritten every pose update.
			for part: Node in avatar.get_head().get_children():
				if part is Node3D:
					(part as Node3D).scale *= 1.8
					(part as Node3D).position *= 1.8
	_hit_head = _make_hitbox("HitHead", "head", head_box)
	_hit_head_col = _hit_head.get_child(0)
	_hit_body_shape = BoxShape3D.new()
	_hit_body_shape.size = Vector3(0.72, 1.35, 0.42)
	_hit_body = _make_hitbox("HitBody", "body", _hit_body_shape)
	_hit_body_col = _hit_body.get_child(0)
	_exclude = [get_rid(), _hit_head.get_rid(), _hit_body.get_rid()]

	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS - 0.03
	_stand_query = PhysicsShapeQueryParameters3D.new()
	_stand_query.shape = sphere
	_stand_query.collision_mask = MASK_WORLD

	if mode == Mode.LOCAL:
		camera = Camera3D.new()
		camera.name = "Camera"
		camera.near = 0.05
		camera.far = 400.0
		camera.fov = float(Profile.get_setting("fov"))
		camera.current = true
		head.add_child(camera)
		avatar.set_first_person(true)
		viewmodel = Viewmodel.new()
		viewmodel.setup(str(info.outfit), str(info.skin))
		camera.add_child(viewmodel)
	else:
		nametag = Label3D.new()
		nametag.text = "%s  Lv %d" % [info.name, int(info.get("level", 1))]
		# Clears the tallest hat tip (2.27 m, or 2.99 m when Big Heads scales head and hat 1.8x).
		nametag.position.y = 2.45 + (0.72 if Net.config.mutator == "big_heads" else 0.0)
		nametag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nametag.pixel_size = 0.004
		nametag.font_size = 44
		nametag.outline_size = 12
		nametag.modulate = Color(1.0, 0.92, 0.85)
		add_child(nametag)

	if mode == Mode.BOT:
		brain = BotBrain.new()
		brain.name = "Brain"
		add_child(brain)

	_apply_crouch_shape()
	_refresh_weapon_visual()
	_last_visual_pos = global_position


func _make_hitbox(node_name: String, part: String, box: BoxShape3D) -> Area3D:
	var area := Area3D.new()
	area.name = node_name
	area.collision_layer = MASK_HITBOX
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.set_meta("player", self)
	area.set_meta("part", part)
	var col := CollisionShape3D.new()
	col.shape = box
	area.add_child(col)
	add_child(area)
	return area


# ---------------------------------------------------------------- frame loop

func _physics_process(delta: float) -> void:
	match mode:
		Mode.LOCAL:
			_read_input()
			_simulate(delta)
			_send_timer -= delta
			if _send_timer <= 0.0 and alive:
				_send_timer = SEND_INTERVAL
				world.submit_local_state(self)
		Mode.BOT:
			if brain != null and alive:
				brain.think(delta)
			_simulate(delta)
		Mode.REMOTE:
			if alive:
				_interpolate()
			else:
				_fall_corpse(delta)
	_update_visuals(delta)


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.LOCAL or world.input_blocked():
		return
	if not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sens := MOUSE_SCALE * float(Profile.get_setting("mouse_sens"))
		sens *= lerpf(1.0, float(Profile.get_setting("ads_sens_mult")) * (camera.fov / float(Profile.get_setting("fov"))), aim_blend)
		var invert := -1.0 if Profile.get_setting("invert_y") else 1.0
		yaw = wrapf(yaw - motion.relative.x * sens, -PI, PI)
		pitch = clampf(pitch - motion.relative.y * sens * invert, -MAX_PITCH, MAX_PITCH)
		viewmodel.add_sway(motion.relative)
		return
	if event.is_action_pressed("weapon_1"):
		in_slot = 0
	elif event.is_action_pressed("weapon_2"):
		in_slot = 1
	elif event.is_action_pressed("weapon_3"):
		in_slot = 2
	elif event.is_action_pressed("next_weapon"):
		in_slot = (current_slot + 1) % slots.size()
	elif event.is_action_pressed("prev_weapon"):
		in_slot = (current_slot + slots.size() - 1) % slots.size()
	elif event.is_action_pressed("quick_swap"):
		in_slot = previous_slot
	elif event.is_action_pressed("reload"):
		in_reload = true
	elif event.is_action_pressed("grenade"):
		in_grenade = true
	elif event.is_action_pressed("melee"):
		in_melee = true


func _read_input() -> void:
	if world.input_blocked() or not alive:
		in_move = Vector2.ZERO
		in_jump = false
		in_fire = false
		in_aim = false
		in_sprint = false
		in_crouch = false
		return
	in_move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	in_jump = Input.is_action_pressed("jump")
	in_crouch = Input.is_action_pressed("crouch")
	in_sprint = Input.is_action_pressed("sprint")
	in_fire = Input.is_action_pressed("fire")
	in_aim = Input.is_action_pressed("aim")


# ---------------------------------------------------------------- simulation (LOCAL and BOT)

func weapon_id() -> String:
	return slots[current_slot]


func weapon_data() -> Dictionary:
	return Data.WEAPONS[weapon_id()]


func _simulate(delta: float) -> void:
	if not alive:
		_fall_corpse(delta)
		return
	var w := weapon_data()
	var want_crouch := in_crouch
	if not want_crouch and crouching and not _can_stand():
		want_crouch = true
	crouching = want_crouch
	crouch_blend = move_toward(crouch_blend, 1.0 if crouching else 0.0, delta * 8.0)
	_apply_crouch_shape()

	var can_aim := in_aim and switch_timer <= 0.0 and not reloading and weapon_id() != "knife" and melee_timer <= 0.0
	aim_blend = move_toward(aim_blend, 1.0 if can_aim else 0.0, delta / 0.16)

	var on_floor := is_on_floor()
	sprinting = in_sprint and in_move.y > 0.3 and not crouching and aim_blend < 0.2 and not in_fire and not reloading
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	speed = lerpf(speed, minf(speed, ADS_SPEED), aim_blend) * float(w.move_mult) * speed_scale

	var wish := Basis(Vector3.UP, yaw) * Vector3(in_move.x, 0.0, -in_move.y)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	horiz = horiz.move_toward(wish * speed, (GROUND_ACCEL if on_floor else AIR_ACCEL) * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if on_floor:
		if in_jump and not crouching:
			velocity.y = JUMP_VELOCITY
			Sfx.play(&"jump", global_position, -6.0)
	else:
		velocity.y -= GRAVITY * gravity_scale * delta
	_fall_speed = -velocity.y
	move_and_slide()
	_tick_weapon(delta)


func _can_stand() -> bool:
	_stand_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (STAND_HEIGHT - RADIUS + 0.02))
	return get_world_3d().direct_space_state.intersect_shape(_stand_query, 1).is_empty()


func _apply_crouch_shape() -> void:
	if is_equal_approx(_applied_crouch, crouch_blend):
		return
	_applied_crouch = crouch_blend
	var h := lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_blend)
	_shape.height = h
	_collider.position.y = h * 0.5
	var drop := CROUCH_DROP * crouch_blend
	head.position.y = STAND_EYE - drop
	_hit_head_col.position.y = _head_hit_y - drop
	var body_h := 1.35 - drop
	_hit_body_shape.size.y = body_h
	_hit_body_col.position.y = body_h * 0.5


# ---------------------------------------------------------------- weapons

func refill_ammo() -> void:
	ammo.clear()
	for wid in slots:
		ammo[wid] = Vector2i(int(Data.WEAPONS[wid].mag), _reserve(wid))


func add_ammo_pickup() -> void:
	for wid in slots:
		var a: Vector2i = ammo[wid]
		a.y = mini(a.y + int(Data.WEAPONS[wid].mag) * 2 * _ammo_scale(wid), _reserve(wid) * 2)
		ammo[wid] = a


## True when an ammo crate would add anything (reserve below its cap on some gun).
func needs_ammo() -> bool:
	if mode == Mode.REMOTE:
		return (_remote_flags & FLAG_NEEDS_AMMO) != 0
	for wid in slots:
		if int(Data.WEAPONS[wid].mag) > 0 and (ammo[wid] as Vector2i).y < _reserve(wid) * 2:
			return true
	return false


## Rocket Party is built around the Boom Block, so it carries (and crates refill) twice the usual
## rockets; otherwise a good life ran dry after eight shots.
func _ammo_scale(wid: String) -> int:
	return 2 if wid == "rocket" and Net.config.mutator == "rocket_party" else 1


## Starting reserve for `wid` this match; ammo crates top it up to twice this.
func _reserve(wid: String) -> int:
	return int(Data.WEAPONS[wid].reserve) * _ammo_scale(wid)


func _tick_weapon(delta: float) -> void:
	fire_cooldown -= delta
	switch_timer -= delta
	melee_timer -= delta
	grenade_cooldown -= delta
	bloom = move_toward(bloom, 0.0, delta * 7.0)
	recoil = move_toward(recoil, 0.0, delta * (6.0 + recoil * 5.0))
	if not in_fire:
		_trigger_down = false
	if world.match_over:
		in_reload = false
		in_grenade = false
		in_melee = false
		in_slot = -1
		return

	if in_slot >= 0:
		var wanted := in_slot
		in_slot = -1
		if wanted != current_slot and wanted < slots.size():
			switch_to(wanted)
	if in_grenade and grenades > 0 and grenade_cooldown > GRENADE_BUFFER:
		in_grenade = false
	if switch_timer > 0.0 or melee_timer > 0.0:
		return
	# Pressing with no grenades left says so instead of doing nothing.
	if in_grenade:
		if grenades <= 0:
			in_grenade = false
			if mode == Mode.LOCAL:
				Sfx.play(&"dry_fire", null, -6.0)
				world.hud.pickup_message("no_grenades")
		elif grenade_cooldown <= 0.0:
			in_grenade = false
			_throw_grenade()
			return
	if in_melee:
		in_melee = false
		_melee_attack(true)
		return

	var wid := weapon_id()
	var w := weapon_data()
	if reloading:
		_tick_reload(delta, wid, w)
	if in_reload:
		in_reload = false
		start_reload()
	if in_fire:
		_try_fire(wid, w)


func switch_to(slot: int) -> void:
	previous_slot = current_slot
	current_slot = slot
	switch_timer = SWITCH_TIME
	_cancel_reload()
	_trigger_down = true
	if mode == Mode.LOCAL:
		Sfx.play(&"weapon_switch", null, -8.0)
	_refresh_weapon_visual()


func start_reload() -> void:
	var wid := weapon_id()
	var w := weapon_data()
	var a: Vector2i = ammo[wid]
	if reloading or int(w.mag) == 0 or a.x >= int(w.mag) or a.y <= 0:
		return
	reloading = true
	reload_timer = float(w.reload)
	# Shotguns replay the animation per shell in _tick_reload.
	_play_reload_anim(float(w.reload))
	if mode == Mode.LOCAL:
		Sfx.play(&"reload", null, -4.0)
	else:
		Sfx.play(&"reload", global_position, -8.0)


func _play_reload_anim(duration: float) -> void:
	avatar.play_reload(duration)
	if viewmodel != null:
		viewmodel.play_reload(duration)


func _cancel_reload() -> void:
	reloading = false
	avatar.stop_reload()
	if viewmodel != null:
		viewmodel.stop_reload()


## Dead bodies drop to the ground (someone killed mid-jump) and otherwise stay put.
func _fall_corpse(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if is_on_floor():
		velocity.y = 0.0
		return
	velocity.y -= GRAVITY * gravity_scale * delta
	move_and_slide()


func _tick_reload(delta: float, wid: String, w: Dictionary) -> void:
	reload_timer -= delta
	if reload_timer > 0.0:
		return
	var a: Vector2i = ammo[wid]
	if w.get("reload_per_shell", false):
		if a.y > 0 and a.x < int(w.mag):
			a.x += 1
			a.y -= 1
			if mode == Mode.LOCAL:
				Sfx.play(&"reload", null, -10.0, 1.3)
			if a.y > 0 and a.x < int(w.mag):
				_play_reload_anim(float(w.reload))
		ammo[wid] = a
		if a.y > 0 and a.x < int(w.mag):
			reload_timer = float(w.reload)
		else:
			reloading = false
		return
	var take := mini(int(w.mag) - a.x, a.y)
	ammo[wid] = Vector2i(a.x + take, a.y - take)
	reloading = false


func _try_fire(wid: String, w: Dictionary) -> void:
	if reloading:
		# Shotguns can interrupt a shell-by-shell reload with a fresh trigger pull.
		if w.get("reload_per_shell", false) and (ammo[wid] as Vector2i).x > 0 and not _trigger_down:
			_cancel_reload()
		else:
			return
	if fire_cooldown > 0.0 or (_trigger_down and not w.auto):
		return
	if wid == "knife":
		_trigger_down = true
		_melee_attack(false)
		return
	var a: Vector2i = ammo[wid]
	if a.x <= 0:
		if not _trigger_down:
			if mode == Mode.LOCAL:
				Sfx.play(&"dry_fire", null, -4.0)
			start_reload()
		_trigger_down = true
		return
	_trigger_down = true
	fire_cooldown = 60.0 / float(w.rpm)
	a.x -= 1
	ammo[wid] = a
	var aim := aim_transform()
	if w.get("projectile", false):
		var spread := lerpf(float(w.spread_hip), float(w.spread_ads), aim_blend)
		var dir := _spread_dir(aim.basis, spread)
		world.request_projectile(self, "rocket", aim.origin + dir * 0.6, dir * float(w.speed))
	else:
		_fire_hitscan(wid, w, aim)
	_apply_kick(w)
	if a.x == 0 and a.y > 0:
		start_reload()


## Eye position and look basis including temporary recoil.
func aim_transform() -> Transform3D:
	var b := Basis.from_euler(Vector3(pitch + deg_to_rad(recoil), yaw, 0.0))
	return Transform3D(b, head.global_position)


func current_spread() -> float:
	var w := weapon_data()
	var s := lerpf(float(w.spread_hip), float(w.spread_ads), aim_blend) + bloom
	var hspeed := Vector2(velocity.x, velocity.z).length()
	s += clampf(hspeed / WALK_SPEED, 0.0, 1.4) * float(w.spread_hip) * 0.35 * (1.0 - aim_blend * 0.6)
	if not is_on_floor():
		s += float(w.spread_hip) * 0.6 + 1.5
	if crouching:
		s *= 0.8
	return s


func _spread_dir(b: Basis, spread_deg: float) -> Vector3:
	var r := sqrt(randf()) * deg_to_rad(spread_deg)
	var t := randf() * TAU
	return (b * Vector3(tan(r) * cos(t), tan(r) * sin(t), -1.0)).normalized()


func _fire_hitscan(wid: String, w: Dictionary, aim: Transform3D) -> void:
	var spread := current_spread()
	var space := get_world_3d().direct_space_state
	var ends := PackedVector3Array()
	var normals := PackedVector3Array()
	var hits := {}
	for i in int(w.pellets):
		var dir := _spread_dir(aim.basis, spread)
		var q := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin + dir * HITSCAN_RANGE, MASK_WORLD | MASK_HITBOX, _exclude)
		q.collide_with_areas = true
		var r := space.intersect_ray(q)
		if r.is_empty():
			ends.append(aim.origin + dir * HITSCAN_RANGE)
			normals.append(Vector3.ZERO)
			continue
		ends.append(r.position)
		var col: Object = r.collider
		if col is Area3D and col.has_meta("player"):
			normals.append(Vector3.ZERO)
			var target: Player = col.get_meta("player")
			if target == self or not target.alive:
				continue
			var is_head: bool = col.get_meta("part") == "head"
			var dist: float = aim.origin.distance_to(r.position)
			var dmg := damage_at(w, dist) * (float(w.head_mult) if is_head else 1.0)
			var entry: Array = hits.get(target.id, [0.0, false])
			entry[0] += dmg
			entry[1] = entry[1] or is_head
			hits[target.id] = entry
		else:
			normals.append(r.normal)
	bloom = minf(bloom + float(w.spread_hip) * 0.22 + 0.25, float(w.spread_hip) * 1.6)
	world.report_shot(self, wid, ends, normals, hits)


static func damage_at(w: Dictionary, dist: float) -> float:
	var start := float(w.falloff_start)
	var stop := float(w.falloff_end)
	var t := clampf((dist - start) / maxf(stop - start, 0.001), 0.0, 1.0)
	return float(w.damage) * lerpf(1.0, float(w.min_mult), t)


func _apply_kick(w: Dictionary) -> void:
	var kick := float(w.recoil) * lerpf(1.0, 0.6, aim_blend) * (0.8 if crouching else 1.0)
	if mode == Mode.LOCAL:
		pitch = clampf(pitch + deg_to_rad(kick * 0.55), -MAX_PITCH, MAX_PITCH)
		yaw += deg_to_rad(randf_range(-0.35, 0.35) * kick * 0.4)
		recoil += kick * 0.45
		viewmodel.play_fire(kick)
	avatar.play_shoot()


func _melee_attack(quick: bool) -> void:
	var w: Dictionary = Data.WEAPONS.knife
	melee_timer = MELEE_TIME if quick else 0.0
	# Never shortens a gun's refire time: the server keeps one fire-rate budget per shooter.
	fire_cooldown = maxf(fire_cooldown, 60.0 / float(w.rpm))
	_cancel_reload()
	var aim := aim_transform()
	var reach := float(w.range)
	var space := get_world_3d().direct_space_state
	var end := aim.origin - aim.basis.z * reach
	var normal := Vector3.ZERO
	var q := PhysicsRayQueryParameters3D.create(aim.origin, end, MASK_WORLD | MASK_HITBOX, _exclude)
	q.collide_with_areas = true
	var r := space.intersect_ray(q)
	var target: Player = null
	if not r.is_empty():
		end = r.position
		if r.collider is Area3D and r.collider.has_meta("player"):
			target = r.collider.get_meta("player")
		else:
			normal = r.normal
	if target == null and r.is_empty():
		# Forgiving sweep so slashes connect without pixel-perfect aim (never through walls).
		var params := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.55
		params.shape = sphere
		params.collide_with_areas = true
		params.collide_with_bodies = false
		params.collision_mask = MASK_HITBOX
		params.exclude = _exclude
		params.transform = Transform3D(Basis.IDENTITY, aim.origin - aim.basis.z * (reach * 0.6))
		for hit in space.intersect_shape(params, 8):
			var area: Object = hit.collider
			if area.has_meta("player") and (area.get_meta("player") as Player).alive:
				target = area.get_meta("player")
				break
	var hits := {}
	if target != null and target.alive and target != self:
		hits[target.id] = [float(w.damage), false]
		normal = Vector3.ZERO
	if mode == Mode.LOCAL:
		viewmodel.play_melee(quick)
	avatar.play_shoot()
	world.report_shot(self, "knife", PackedVector3Array([end]), PackedVector3Array([normal]), hits)


func _throw_grenade() -> void:
	grenades -= 1
	grenade_cooldown = GRENADE_COOLDOWN
	var aim := aim_transform()
	var dir := -aim.basis.z
	var vel := dir * float(Data.GRENADE.throw_speed) + Vector3.UP * 3.0 + Vector3(velocity.x, 0.0, velocity.z) * 0.4
	if mode == Mode.LOCAL:
		viewmodel.play_melee(true)
	world.request_projectile(self, "grenade", aim.origin + dir * 0.5, vel)


func muzzle_position() -> Vector3:
	if mode == Mode.LOCAL and viewmodel != null and alive:
		return viewmodel.muzzle_position()
	if _muzzle != null and is_instance_valid(_muzzle):
		return _muzzle.global_position
	return head.global_position


# ---------------------------------------------------------------- network state

func state_flags() -> int:
	var f := 0
	if crouching:
		f |= FLAG_CROUCH
	if is_on_floor():
		f |= FLAG_FLOOR
	if aim_blend > 0.5:
		f |= FLAG_AIM
	if sprinting:
		f |= FLAG_SPRINT
	if reloading:
		f |= FLAG_RELOAD
	if needs_ammo():
		f |= FLAG_NEEDS_AMMO
	f |= weapon_index(weapon_id()) << 8
	return f


## Flags the server relays to everyone: our own simulated state, or the last state a client reported.
func net_flags() -> int:
	return _remote_flags if mode == Mode.REMOTE else state_flags()


func exclude_rids() -> Array[RID]:
	return _exclude


## REMOTE only: queue a server-relayed state sample for interpolation.
func push_snapshot(pos: Vector3, p_yaw: float, p_pitch: float, flags: int) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if not _snapshots.is_empty() and (_snapshots[-1][1] as Vector3).distance_to(pos) > 8.0:
		_snapshots.clear()
	_snapshots.append([now, pos, p_yaw, p_pitch, flags])
	if _snapshots.size() > 24:
		_snapshots.pop_front()


## REMOTE: the player just fired or swung. Shots arrive ahead of the interpolated state, so a
## reload pose (a shotgun reload that firing interrupts, or any reload a knife swing cancels)
## stops now, and the stale reload flag still in the snapshot buffer may not restart it.
func remote_fired() -> void:
	if (_remote_flags & FLAG_RELOAD) == 0:
		return
	avatar.stop_reload()
	_reload_hold = INTERP_DELAY + 0.1


func _interpolate() -> void:
	if _snapshots.is_empty():
		return
	var render_t := Time.get_ticks_msec() * 0.001 - INTERP_DELAY
	var a: Array = _snapshots[0]
	var b: Array = _snapshots[-1]
	for i in range(_snapshots.size() - 1, -1, -1):
		if _snapshots[i][0] <= render_t:
			a = _snapshots[i]
			b = _snapshots[mini(i + 1, _snapshots.size() - 1)]
			break
	var span: float = b[0] - a[0]
	var t := 1.0 if span <= 0.0001 else clampf((render_t - a[0]) / span, 0.0, 1.0)
	global_position = (a[1] as Vector3).lerp(b[1], t)
	yaw = lerp_angle(a[2], b[2], t)
	pitch = lerpf(a[3], b[3], t)
	var was_reloading := (_remote_flags & FLAG_RELOAD) != 0
	var prev_weapon := _remote_flags >> 8
	_remote_flags = b[4]
	var now_reloading := (_remote_flags & FLAG_RELOAD) != 0
	var reload_w: Dictionary = Data.WEAPONS[weapon_from_index(_remote_flags >> 8)]
	var per_shell: bool = reload_w.get("reload_per_shell", false)
	# Shotguns replay the pose per shell, with a short gap so shells read as separate motions.
	if now_reloading and not avatar.is_reloading():
		_reload_gap += get_physics_process_delta_time()
	else:
		_reload_gap = 0.0
	_reload_hold -= get_physics_process_delta_time()
	if now_reloading and (not was_reloading or (per_shell and _reload_gap > 0.15 and _reload_hold <= 0.0)):
		_reload_gap = 0.0
		avatar.play_reload(float(reload_w.reload))
	elif was_reloading and not now_reloading and (prev_weapon != _remote_flags >> 8 or not per_shell):
		# A finished shotgun reload lets its last shell's pose ease out instead of snapping.
		avatar.stop_reload()
	crouching = (_remote_flags & FLAG_CROUCH) != 0
	sprinting = (_remote_flags & FLAG_SPRINT) != 0
	aim_blend = 1.0 if (_remote_flags & FLAG_AIM) != 0 else 0.0
	crouch_blend = move_toward(crouch_blend, 1.0 if crouching else 0.0, get_physics_process_delta_time() * 8.0)
	_apply_crouch_shape()
	var slot := slots.find(weapon_from_index(_remote_flags >> 8))
	if slot >= 0 and slot != current_slot:
		current_slot = slot
		_refresh_weapon_visual()


# ---------------------------------------------------------------- visuals

func _update_visuals(delta: float) -> void:
	rotation.y = yaw
	var pos := global_position
	var moved := Vector2(pos.x - _last_visual_pos.x, pos.z - _last_visual_pos.z).length()
	_last_visual_pos = pos
	if mode == Mode.REMOTE:
		anim_speed = lerpf(anim_speed, moved / maxf(delta, 0.0001), 0.3)
		on_floor_visual = (_remote_flags & FLAG_FLOOR) != 0
	else:
		anim_speed = Vector2(velocity.x, velocity.z).length()
		on_floor_visual = is_on_floor()
	if protected_until > 0.0 and World.now() >= protected_until:
		set_protection(0.0)
	if alive:
		avatar.set_look_pitch(pitch)
		avatar.animate(delta, anim_speed, on_floor_visual, crouching)
		_footsteps(delta)
	if camera != null and not alive and camera.top_level:
		_update_death_cam(delta)
	elif camera != null and alive:
		camera.rotation.x = pitch + deg_to_rad(recoil)
		var base_fov := float(Profile.get_setting("fov"))
		var target_fov := lerpf(base_fov, minf(float(weapon_data().ads_fov), base_fov), aim_blend)
		if sprinting:
			target_fov += 4.0
		camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 18.0))
		viewmodel.update_pose(delta, self)


func _footsteps(delta: float) -> void:
	if on_floor_visual and not _was_on_floor and mode != Mode.REMOTE and _fall_speed > 4.0:
		Sfx.play(&"land", global_position, -6.0)
	_was_on_floor = on_floor_visual
	if not on_floor_visual or anim_speed < 1.5:
		_step_timer = 0.15
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = clampf(2.1 / anim_speed, 0.26, 0.55)
		var vol := -14.0 if crouching else (-6.0 if sprinting else -9.0)
		if mode == Mode.LOCAL:
			Sfx.play(&"footstep", null, vol - 4.0)
		else:
			Sfx.play(&"footstep", global_position, vol)


func _refresh_weapon_visual() -> void:
	var wid := weapon_id()
	if wid == _shown_weapon:
		return
	_shown_weapon = wid
	avatar.hold_weapon(wid, str(info.skin))
	_muzzle = avatar.find_child("Muzzle", true, false) as Node3D
	if viewmodel != null:
		viewmodel.set_weapon(wid)


# ---------------------------------------------------------------- server-driven events (every peer)

func on_damaged(new_health: float, attacker_id: int) -> void:
	health = new_health
	last_attacker = attacker_id
	last_hurt_time = World.now()
	avatar.flash_hit()


## Spawn protection: `seconds` > 0 starts the shimmer, 0 ends it (expiry, or firing ended it).
func set_protection(seconds: float) -> void:
	protected_until = World.now() + seconds if seconds > 0.0 else -100.0
	avatar.set_protected(seconds > 0.0)


func protection_left() -> float:
	return maxf(0.0, protected_until - World.now())


## `killer` (optional) is who the local player's death cam turns to watch.
func die(killer: Player = null) -> void:
	alive = false
	health = 0.0
	set_protection(0.0)
	_cancel_reload()
	_clear_intent()
	aim_blend = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	_hit_head.collision_layer = 0
	_hit_body.collision_layer = 0
	avatar.play_death()
	if nametag != null:
		nametag.visible = false
	if mode == Mode.LOCAL:
		avatar.set_first_person(false)
		viewmodel.visible = false
		_start_death_cam(killer)


func respawn(pos: Vector3, p_yaw: float) -> void:
	global_position = pos
	_last_visual_pos = pos
	velocity = Vector3.ZERO
	yaw = p_yaw
	pitch = 0.0
	recoil = 0.0
	bloom = 0.0
	health = Data.MAX_HEALTH
	alive = true
	grenades = Data.GRENADE.per_life
	_clear_intent()
	_cancel_reload()
	_remote_flags = FLAG_FLOOR
	fire_cooldown = 0.0
	switch_timer = SWITCH_TIME
	_snapshots.clear()
	refill_ammo()
	if current_slot != 0:
		previous_slot = current_slot
		current_slot = 0
	_refresh_weapon_visual()
	collision_layer = 2
	_hit_head.collision_layer = MASK_HITBOX
	_hit_body.collision_layer = MASK_HITBOX
	avatar.reset_pose()
	if nametag != null:
		nametag.visible = true
	if mode == Mode.LOCAL:
		avatar.set_first_person(true)
		viewmodel.visible = true
		viewmodel.play_draw()
		_end_death_cam()
	if brain != null:
		brain.on_respawn()


## Drops every queued action so nothing pressed while dead fires on respawn.
func _clear_intent() -> void:
	in_move = Vector2.ZERO
	in_fire = false
	in_aim = false
	in_jump = false
	in_crouch = false
	in_sprint = false
	in_reload = false
	in_grenade = false
	in_melee = false
	in_slot = -1


## The camera rises behind the corpse, on the side away from the killer, and turns to keep the
## killer in frame (zooming in when they are far away) until respawn. Without a killer it
## looks down at the corpse.
func _start_death_cam(killer: Player) -> void:
	var start := camera.global_transform
	camera.top_level = true
	camera.global_transform = start
	camera.fov = float(Profile.get_setting("fov"))
	_death_cam_target = killer if killer != null and killer != self else null
	var back := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 1.0)
	if _death_cam_target != null:
		var away := global_position - _death_cam_target.global_position
		away.y = 0.0
		if away.length() > 0.5:
			back = away.normalized()
	var eye := global_position + Vector3.UP * 2.6 + back * 3.2
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.2, eye, MASK_WORLD)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		eye = (r.position as Vector3).lerp(global_position + Vector3.UP * 1.2, 0.15)
	_death_cam_eye = eye


func _update_death_cam(delta: float) -> void:
	var k := minf(1.0, delta * 6.0)
	var pos := camera.global_position.lerp(_death_cam_eye, k)
	var focus := global_position + Vector3.UP * 0.6
	var base_fov := float(Profile.get_setting("fov"))
	var target_fov := base_fov
	if _death_cam_target != null and is_instance_valid(_death_cam_target):
		focus = _death_cam_target.global_position + Vector3.UP * 1.1
		# Frame about 7 m around the killer vertically, so a distant one is still recognisable.
		target_fov = clampf(rad_to_deg(2.0 * atan(3.5 / maxf(0.1, pos.distance_to(focus)))), 24.0, base_fov)
	if pos.distance_squared_to(focus) < 0.01:
		return
	var look := Transform3D(Basis.IDENTITY, pos).looking_at(focus, Vector3.UP)
	var rot := camera.global_basis.get_rotation_quaternion().slerp(look.basis.get_rotation_quaternion(), k)
	camera.global_transform = Transform3D(Basis(rot), pos)
	camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 3.0))


func _end_death_cam() -> void:
	_death_cam_target = null
	camera.top_level = false
	camera.transform = Transform3D.IDENTITY
