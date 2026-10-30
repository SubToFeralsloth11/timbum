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
## Prone (lying down): a short collider, eyes near the floor, a slow crawl, steadier aim. The
## body hitbox lies flat and reaches back along the legs; the head sits slightly forward.
const PRONE_HEIGHT := 0.8
const PRONE_EYE := 0.42
const PRONE_SPEED := 1.3
const PRONE_HEAD_Z := -0.1
const PRONE_BODY := Vector3(0.72, 0.42, 1.5)
const PRONE_BODY_Z := 0.6
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
const FLAG_SLIDE := 64
const FLAG_PRONE := 128
## Bits 8-15: weapon index. Bits 16-19: lean, quantised to -7..7 and stored + 8.
const FLAG_WEAPON_SHIFT := 8
const FLAG_LEAN_SHIFT := 16

## Sliding: crouch while sprinting. Entry needs this much ground speed; the slide starts at
## SLIDE_SPEED (or the current speed plus SLIDE_BOOST), bleeds SLIDE_FRICTION m/s per second
## (downhill slopes feed it) and ends below SLIDE_END_SPEED, after SLIDE_MAX_TIME, or when
## crouch is released.
const SLIDE_MIN_ENTRY := 5.8
const SLIDE_SPEED := 10.0
const SLIDE_BOOST := 2.0
const SLIDE_MAX_SPEED := 12.5
const SLIDE_FRICTION := 6.5
const SLIDE_END_SPEED := 3.8
const SLIDE_MAX_TIME := 1.15
const SLIDE_COOLDOWN := 0.45
## Radians per second the slide can be steered.
const SLIDE_STEER := 1.4
## Leaning (peeking): the eye moves LEAN_DIST sideways and LEAN_DROP down and the view rolls
## LEAN_ROLL, unless a wall is closer.
const LEAN_DIST := 0.48
const LEAN_DROP := 0.07
const LEAN_ROLL := deg_to_rad(12.0)
const LEAN_RATE := 6.5
## Grapple hook: fires at the world up to GRAPPLE_RANGE, then reels the player in.
const GRAPPLE_RANGE := 42.0
const GRAPPLE_PULL := 34.0
const GRAPPLE_MAX_SPEED := 18.0
const GRAPPLE_MAX_TIME := 2.6
const GRAPPLE_COOLDOWN := 3.5
## A shot that hits nothing only locks the hook this long.
const GRAPPLE_MISS_COOLDOWN := 0.4
const GRAPPLE_RELEASE_DIST := 1.7

static var _weapon_ids: Array = []

var id := 0
var info := {}
var mode := Mode.REMOTE
var is_bot := false
var world: World
var health := Data.MAX_HEALTH
## Overshield (killstreak reward, see Streaks): absorbs damage before health. The server sets it;
## every peer keeps it for the HUD and the death screen. Gone on death.
var shield := 0.0
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
## One-shot "prone" press (toggles lying down).
var in_prone := false
var in_sprint := false
var in_fire := false
var in_aim := false
var in_reload := false
var in_slot := -1
var in_grenade := false
var in_melee := false
var in_tactical := false
var in_grapple := false
## -1 peek left, 0 none, 1 peek right.
var in_lean := 0

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
var prone := false
var prone_blend := 0.0
var sprinting := false
var anim_speed := 0.0
var on_floor_visual := true
var sliding := false
## -1..1 current peek; left negative.
var lean := 0.0
var tacticals := Data.TACTICAL_PER_LIFE
## World.now() until which a flash grenade has this player blinded (bots lose sight of targets).
var flashed_until := -100.0
var grappling := false
var grapple_point := Vector3.ZERO
var grapple_cooldown := 0.0

var avatar: Avatar
var head: Node3D
var camera: Camera3D
var viewmodel: Viewmodel
var nametag: Label3D
var brain: BotBrain
## Laser Sight attachment beam (null without the upgrade).
var laser: LaserSight

var _shape: CapsuleShape3D
var _collider: CollisionShape3D
var _hit_head: Area3D
var _hit_body: Area3D
var _hit_head_col: CollisionShape3D
var _hit_body_col: CollisionShape3D
var _hit_body_shape: BoxShape3D
var _exclude: Array[RID] = []
var _trigger_down := false
var _fire_gated := false
var _aim_gated := false
## LOCAL: cooldown between knife swings so the server budget isn't silently exceeded.
var knife_cooldown := 0.0
var _step_timer := 0.0
var _was_on_floor := true
var _shown_weapon := ""
var _muzzle: Node3D
var _send_timer := 0.0
var _snapshots: Array = []
var _remote_flags := FLAG_FLOOR
var _last_visual_pos := Vector3.ZERO
var _applied_crouch := -1.0
var _applied_prone := -1.0
var _fall_speed := 0.0
var _stand_query: PhysicsShapeQueryParameters3D
## Match mutator effects (see Data.MUTATORS), set once in _ready from Net.config.
var gravity_scale := 1.0
## Movement speed multiplier: the Turbo mutator times the role's `info.speed` (Infected).
var speed_scale := 1.0
var _mutator_speed := 1.0
var _head_hit_y := 1.56
## REMOTE: seconds the reload flag has stayed on with no reload pose playing.
var _reload_gap := 0.0
## REMOTE: seconds left in which a reload flag still set in buffered snapshots is stale because
## the player fired (which cancels a shotgun's shell-by-shell reload); see remote_fired().
var _reload_hold := 0.0
## LOCAL, while dead: where the death cam settles and who it watches (null: look at the corpse).
var _death_cam_eye := Vector3.ZERO
var _death_cam_target: Player
var _slide_time := 0.0
var _slide_cooldown := 0.0
var _slide_speed := 0.0
var _slide_dir := Vector3.ZERO
var _crouch_was_held := false
var _jump_was_held := false
## True from the jump press that got us up off the floor until jump is released.
var _jump_spent := false
var _was_sprinting := false
## Fraction of LEAN_DIST the eye can move before touching a wall (local/bot); 1 for remotes.
var _lean_reach := 1.0
var _lean_query: PhysicsShapeQueryParameters3D
var _grapple_time := 0.0
var _rope: MeshInstance3D
## 0..1 how far the rope has shot out toward the hook (it flies out over a few frames).
var _rope_out := 0.0
## Shots still to come in the current burst (burst weapons).
var _burst_left := 0
## Attachment id -> stat multiplier, from info.mods (see mod()).
var _mods := {}


func setup(p_world: World, p_id: int, p_info: Dictionary, p_mode: Mode, p_is_bot: bool) -> void:
	world = p_world
	id = p_id
	info = p_info
	mode = p_mode
	is_bot = p_is_bot
	name = "P%d" % p_id
	slots = [str(info.primary), str(info.secondary), "knife"]
	# Tactical: slots start empty ("") until a weapon is picked up; hold the first one there is.
	current_slot = _first_armed_slot()
	_mods.clear()
	var levels: Variant = info.get("mods", {})
	for mid: String in Data.ATTACHMENTS:
		_mods[mid] = Data.attachment_mult(mid, int(levels.get(mid, 0)) if levels is Dictionary else 0)
	refill_ammo()
	_refill_equipment()
	health = max_health()


## Most health this player can have: `info.max_hp` (Infected have more), else Data.MAX_HEALTH.
func max_health() -> float:
	return float(info.get("max_hp", Data.MAX_HEALTH))


## Whether a player with `p_info` carries frags and a tactical: not when knife only (Infected)
## or `no_grenades` (Gun Game).
static func carries_grenades(p_info: Dictionary) -> bool:
	return not bool(p_info.get("knife_only", false)) and not bool(p_info.get("no_grenades", false))


func _refill_equipment() -> void:
	var armed := carries_grenades(info)
	grenades = int(Data.GRENADE.per_life) if armed else 0
	tacticals = int(Data.TACTICAL_PER_LIFE) if armed else 0


## Every peer, from the server: this player's info changed mid-match (a survivor turned
## Infected, a Gun Game step). Rebuilds the weapon slots, equipment and speed from it; health
## stays the server's to set. A reload or burst of the old gun ends.
func apply_info(p_info: Dictionary) -> void:
	info = p_info
	slots = [str(info.primary), str(info.secondary), "knife"]
	_cancel_reload()
	_burst_left = 0
	refill_ammo()
	if slots[current_slot].is_empty():
		current_slot = _first_armed_slot()
	if slots[previous_slot].is_empty():
		previous_slot = 2
	_refill_equipment()
	speed_scale = _mutator_speed * float(info.get("speed", 1.0))
	_refresh_weapon_visual()


## Multiplier this player's attachment upgrade `mid` applies to its stat (1.0 without it).
func mod(mid: String) -> float:
	return _mods.get(mid, 1.0)


## Magazine size of `wid` with the Extended Mag upgrade (guns holding fewer than 3 rounds keep theirs).
func mag_size(wid: String) -> int:
	var base := int(Data.WEAPONS[wid].mag)
	return roundi(base * mod("mag")) if base >= 3 else base


## Reload time of `wid` (per shell for shotguns) with the Speed Loader upgrade.
func reload_time(wid: String) -> float:
	return float(Data.WEAPONS[wid].reload) * mod("speed_loader")


## Weapon switch time with the Quick Holster upgrade; draw animations always fit inside it.
func switch_time() -> float:
	return SWITCH_TIME * mod("holster")


func grapple_cooldown_time() -> float:
	return GRAPPLE_COOLDOWN * mod("grapple_motor")


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
	avatar.charm_id = str(info.get("charm", "none"))
	add_child(avatar)
	if int((info.get("mods", {}) as Dictionary).get("laser", 0)) > 0:
		laser = LaserSight.new()
		add_child(laser)

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
			_mutator_speed = 1.3
		"big_heads":
			# Head pivots at the neck (1.35 m); scaling it 1.8x lifts its centre to ~1.75 m.
			head_box.size = Vector3.ONE * 0.52 * 1.8
			_head_hit_y = 1.35 + 0.225 * 1.8
			# Scale the head's children: the pivot's own basis is rewritten every pose update.
			for part: Node in avatar.get_head().get_children():
				if part is Node3D:
					(part as Node3D).scale *= 1.8
					(part as Node3D).position *= 1.8
	speed_scale = _mutator_speed * float(info.get("speed", 1.0))
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
	var lean_sphere := SphereShape3D.new()
	lean_sphere.radius = 0.2
	_lean_query = PhysicsShapeQueryParameters3D.new()
	_lean_query.shape = lean_sphere
	_lean_query.collision_mask = MASK_WORLD
	_rope = MeshInstance3D.new()
	_rope.name = "Rope"
	var rope_mesh := BoxMesh.new()
	rope_mesh.size = Vector3(0.025, 0.025, 1.0)
	rope_mesh.material = Models.flat_material(Color(0.25, 0.22, 0.18), 0.9)
	_rope.mesh = rope_mesh
	_rope.top_level = true
	_rope.visible = false
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rope)

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
		var camos: Variant = info.get("camos", [])
		viewmodel.setup(str(info.outfit), str(info.skin), str(info.get("charm", "none")), str(info.get("draw", "standard")),
			camos if typeof(camos) == TYPE_ARRAY else [])
		camera.add_child(viewmodel)
	else:
		nametag = Label3D.new()
		nametag.text = "%s  Lv %d" % [Data.badged_name(str(info.name), int(info.get("prestige", 0))), int(info.get("level", 1))]
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
		in_slot = _cycle_slot(1)
	elif event.is_action_pressed("prev_weapon"):
		in_slot = _cycle_slot(-1)
	elif event.is_action_pressed("quick_swap"):
		in_slot = previous_slot
	elif event.is_action_pressed("reload"):
		in_reload = true
	elif event.is_action_pressed("grenade"):
		in_grenade = true
	elif event.is_action_pressed("melee"):
		in_melee = true
	elif event.is_action_pressed("tactical"):
		in_tactical = true
	elif event.is_action_pressed("grapple"):
		in_grapple = true
	elif event.is_action_pressed("prone"):
		in_prone = true


func _read_input() -> void:
	# Input polling sees the click the HUD uses to recapture the mouse (and clicks on menus) even
	# though the GUI handles it, so fire/aim need a fresh press once the mouse is captured.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var fire_held := Input.is_action_pressed("fire")
	var aim_held := Input.is_action_pressed("aim")
	# Aiming a Block Bomber (Streaks.targeting) takes the fire button: no shot goes off with it,
	# and holding fire afterwards needs a fresh press.
	_fire_gated = (_fire_gated or not captured or world.streaks.targeting) and fire_held
	_aim_gated = (_aim_gated or not captured) and aim_held
	if world.input_blocked() or not alive:
		in_move = Vector2.ZERO
		in_jump = false
		in_fire = false
		in_aim = false
		in_sprint = false
		in_crouch = false
		in_lean = 0
		return
	in_move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	in_jump = Input.is_action_pressed("jump")
	in_crouch = Input.is_action_pressed("crouch")
	in_sprint = Input.is_action_pressed("sprint")
	in_lean = int(Input.is_action_pressed("lean_right")) - int(Input.is_action_pressed("lean_left"))
	in_fire = fire_held and not _fire_gated
	in_aim = aim_held and not _aim_gated


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
	var on_floor := is_on_floor()
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var crouch_pressed := in_crouch and not _crouch_was_held
	_crouch_was_held = in_crouch
	var jump_pressed := in_jump and not _jump_was_held
	_jump_was_held = in_jump
	_slide_cooldown -= delta
	grapple_cooldown -= delta
	if in_grapple:
		in_grapple = false
		if grappling:
			release_grapple()
		elif grapple_cooldown <= 0.0 and not world.match_over and not prone and world.tactical == null:
			_fire_grapple()
	if in_prone:
		in_prone = false
		if prone:
			_rise()
		elif on_floor and not grappling:
			# Diving out of a slide is allowed: the slide ends and the body drops flat.
			_end_slide()
			prone = true
	elif prone and (crouch_pressed or jump_pressed):
		_rise()
		# The press that got us up must not also jump; wait for jump to be released.
		_jump_spent = jump_pressed
	_jump_spent = _jump_spent and in_jump
	if not sliding and not grappling and not prone and crouch_pressed and on_floor and _was_sprinting and world.tactical == null \
			and horiz.length() > SLIDE_MIN_ENTRY * speed_scale and _slide_cooldown <= 0.0:
		_start_slide(horiz)

	var want_crouch := (in_crouch or sliding) and not prone
	if not want_crouch and crouching and not _has_headroom(STAND_HEIGHT):
		want_crouch = true
	crouching = want_crouch
	crouch_blend = move_toward(crouch_blend, 1.0 if crouching else 0.0, delta * (12.0 if sliding else 8.0))
	prone_blend = move_toward(prone_blend, 1.0 if prone else 0.0, delta * 4.0)
	_apply_crouch_shape()

	var can_aim := in_aim and switch_timer <= 0.0 and not reloading and weapon_id() != "knife" and melee_timer <= 0.0
	aim_blend = move_toward(aim_blend, 1.0 if can_aim else 0.0, delta / (0.16 * mod("optic")))

	sprinting = in_sprint and in_move.y > 0.3 and not crouching and not prone and aim_blend < 0.2 and not in_fire \
		and not reloading and not grappling
	var speed := WALK_SPEED
	if prone:
		speed = PRONE_SPEED
	elif crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	speed = lerpf(speed, minf(speed, ADS_SPEED * mod("stock")), aim_blend) * float(w.move_mult) * speed_scale

	var wish := Basis(Vector3.UP, yaw) * Vector3(in_move.x, 0.0, -in_move.y)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	if grappling:
		_pull_grapple(delta, wish, jump_pressed)
	elif sliding:
		horiz = _slide_step(delta, on_floor, wish)
		velocity.x = horiz.x
		velocity.z = horiz.z
	else:
		horiz = horiz.move_toward(wish * speed, (GROUND_ACCEL if on_floor else AIR_ACCEL) * delta)
		velocity.x = horiz.x
		velocity.z = horiz.z
	if on_floor and not grappling:
		if in_jump and not prone and not _jump_spent and (not crouching or sliding):
			if sliding:
				# Slide-jump: keep the slide's speed and stand up in the air.
				_end_slide()
				crouching = in_crouch or not _has_headroom(STAND_HEIGHT)
			velocity.y = JUMP_VELOCITY
			Sfx.play(&"jump", global_position, -6.0)
	elif not grappling:
		velocity.y -= GRAVITY * gravity_scale * delta
	_fall_speed = -velocity.y
	move_and_slide()
	_was_sprinting = sprinting
	var lean_target := float(in_lean) if not sprinting and not sliding and not grappling and not prone else 0.0
	lean = move_toward(lean, lean_target, delta * LEAN_RATE)
	_lean_reach = _measure_lean_reach() if not is_zero_approx(lean) else 1.0
	_apply_head_pose()
	_tick_weapon(delta)


func _start_slide(horiz: Vector3) -> void:
	sliding = true
	_slide_time = 0.0
	_slide_dir = horiz.normalized()
	_slide_speed = minf(maxf(SLIDE_SPEED * speed_scale, horiz.length() + SLIDE_BOOST), SLIDE_MAX_SPEED * speed_scale)
	_cancel_reload()
	Sfx.play(&"slide", null if mode == Mode.LOCAL else global_position, -4.0 if mode == Mode.LOCAL else 0.0)


func _end_slide() -> void:
	if not sliding:
		return
	sliding = false
	_slide_cooldown = SLIDE_COOLDOWN


## Gets up from prone into a crouch (which stands up on its own once crouch is released and
## there is room). Stays down when there is no room to crouch.
func _rise() -> void:
	if not _has_headroom(CROUCH_HEIGHT):
		return
	prone = false
	crouching = true


## One tick of a slide: friction, slopes (downhill speeds it up), a little steering. Returns the
## horizontal velocity; ends the slide when it runs out.
func _slide_step(delta: float, on_floor: bool, wish: Vector3) -> Vector3:
	_slide_time += delta
	var downhill := 0.0
	if on_floor:
		var n := get_floor_normal()
		downhill = Vector3(n.x, 0.0, n.z).dot(_slide_dir)
		_slide_speed += downhill * GRAVITY * 0.9 * delta - SLIDE_FRICTION * delta
	_slide_speed = minf(_slide_speed, SLIDE_MAX_SPEED * speed_scale)
	if wish.length_squared() > 0.01:
		var turn := _slide_dir.signed_angle_to(wish, Vector3.UP)
		_slide_dir = _slide_dir.rotated(Vector3.UP, clampf(turn, -SLIDE_STEER * delta, SLIDE_STEER * delta))
	var out := _slide_dir * _slide_speed
	var timed_out := _slide_time > SLIDE_MAX_TIME and downhill < 0.12
	if not in_crouch or _slide_speed < SLIDE_END_SPEED * speed_scale or timed_out or is_on_wall():
		_end_slide()
	return out


## How much of the full lean the eye can make before a wall: a sphere swept sideways from the
## upright eye.
func _measure_lean_reach() -> float:
	var eye_y := STAND_EYE - _eye_drop()
	var base := global_position + Vector3.UP * eye_y
	var side := Basis(Vector3.UP, yaw) * Vector3(signf(lean) * LEAN_DIST, -LEAN_DROP, 0.0)
	_lean_query.transform = Transform3D(Basis.IDENTITY, base)
	_lean_query.motion = side
	_lean_query.exclude = _exclude
	var r := get_world_3d().direct_space_state.cast_motion(_lean_query)
	return r[0] if r.size() == 2 else 1.0


## How far crouching and lying down lower the eyes and head hitbox from standing.
func _eye_drop() -> float:
	return lerpf(CROUCH_DROP * crouch_blend, STAND_EYE - PRONE_EYE, prone_blend)


## Height above the feet to aim at or look for this player's body (bots, effects).
func body_center_height() -> float:
	return lerpf(1.25 - 0.25 * crouch_blend, 0.3, prone_blend)


## Eye, head hitbox and body hitbox follow crouching, lying down and leaning.
func _apply_head_pose() -> void:
	var drop := _eye_drop()
	var side := lean * LEAN_DIST * _lean_reach
	var lean_drop := absf(lean) * LEAN_DROP * _lean_reach
	var fwd := PRONE_HEAD_Z * prone_blend
	head.position = Vector3(side, STAND_EYE - drop - lean_drop, fwd)
	_hit_head_col.position = Vector3(side, _head_hit_y - drop - lean_drop, fwd)
	_hit_body_col.position.x = side * 0.35


## Whether a collider `height` tall fits here (a sphere where its top would be is clear).
func _has_headroom(height: float) -> bool:
	_stand_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (height - RADIUS + 0.02))
	return get_world_3d().direct_space_state.intersect_shape(_stand_query, 1).is_empty()


func _apply_crouch_shape() -> void:
	if is_equal_approx(_applied_crouch, crouch_blend) and is_equal_approx(_applied_prone, prone_blend):
		return
	_applied_crouch = crouch_blend
	_applied_prone = prone_blend
	var h := lerpf(lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_blend), PRONE_HEIGHT, prone_blend)
	_shape.height = h
	_collider.position.y = h * 0.5
	var body := Vector3(0.72, 1.35 - CROUCH_DROP * crouch_blend, 0.42).lerp(PRONE_BODY, prone_blend)
	_hit_body_shape.size = body
	_hit_body_col.position.y = body.y * 0.5
	_hit_body_col.position.z = PRONE_BODY_Z * prone_blend
	_apply_head_pose()


# ---------------------------------------------------------------- grapple hook

func _fire_grapple() -> void:
	var aim := aim_transform()
	var q := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * GRAPPLE_RANGE, MASK_WORLD, _exclude)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	# The invisible boundary walls (MapBuilder "Bounds") are not something to hook onto.
	var bad := r.is_empty() or (r.position as Vector3).distance_to(aim.origin) < GRAPPLE_RELEASE_DIST + 0.3 \
		or (r.collider as Node).name == &"Bounds"
	if bad:
		grapple_cooldown = GRAPPLE_MISS_COOLDOWN
		if mode == Mode.LOCAL:
			Sfx.play(&"dry_fire", null, -4.0, 0.7)
		return
	_end_slide()
	grappling = true
	grapple_point = r.position
	_grapple_time = 0.0
	_rope_out = 0.0
	if is_on_floor():
		velocity.y = maxf(velocity.y, 4.5)
	Sfx.play(&"grapple_fire", null if mode == Mode.LOCAL else global_position, -2.0)
	world.report_grapple(self, true, grapple_point)


## Lets go of the hook (and tells the other peers) and starts the cooldown.
func release_grapple() -> void:
	if not grappling:
		return
	grappling = false
	grapple_cooldown = grapple_cooldown_time()
	if mode != Mode.REMOTE:
		world.report_grapple(self, false, Vector3.ZERO)


## REMOTE proxies: another player's hook, relayed by the server.
func set_remote_grapple(active: bool, point: Vector3) -> void:
	if active and not grappling:
		_rope_out = 0.0
		Sfx.play(&"grapple_fire", global_position, -4.0)
	grappling = active
	grapple_point = point


## Reels toward the hook: strong pull along the rope, most sideways swing damped so the player
## flies to the point instead of orbiting it, a little steering, and reduced gravity.
func _pull_grapple(delta: float, wish: Vector3, jump_pressed: bool) -> void:
	_grapple_time += delta
	var from := global_position + Vector3.UP * 1.0
	var to := grapple_point - from
	var dist := to.length()
	var blocked := false
	if dist > GRAPPLE_RELEASE_DIST:
		var q := PhysicsRayQueryParameters3D.create(head.global_position, grapple_point, MASK_WORLD, _exclude)
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		blocked = not r.is_empty() and (r.position as Vector3).distance_to(grapple_point) > 0.4
	if dist <= GRAPPLE_RELEASE_DIST or _grapple_time > GRAPPLE_MAX_TIME or blocked or jump_pressed:
		release_grapple()
		if jump_pressed or dist <= GRAPPLE_RELEASE_DIST:
			velocity.y = maxf(velocity.y, JUMP_VELOCITY * 0.75)
		return
	var dir := to / dist
	velocity += dir * GRAPPLE_PULL * delta
	var along := velocity.dot(dir)
	var perp := velocity - dir * along
	velocity = dir * along + perp * (1.0 - minf(1.0, 2.5 * delta))
	velocity += wish * AIR_ACCEL * 0.5 * delta
	velocity.y -= GRAVITY * gravity_scale * 0.3 * delta
	velocity = velocity.limit_length(GRAPPLE_MAX_SPEED)


## Where the rope leaves the player: the off hand (lower left of the view in first person).
func _rope_origin() -> Vector3:
	if mode == Mode.LOCAL and camera != null and alive and not camera.top_level:
		return camera.global_transform * Vector3(-0.22, -0.2, -0.35)
	return global_position + Basis(Vector3.UP, yaw) * Vector3(-0.32, maxf(0.3, 1.3 - _eye_drop()), -0.25)


func _update_rope(delta: float) -> void:
	_rope.visible = grappling and alive
	if not _rope.visible:
		return
	_rope_out = minf(1.0, _rope_out + delta * 9.0)
	var from := _rope_origin()
	var to := from.lerp(grapple_point, _rope_out)
	var d := to - from
	var length := d.length()
	if length < 0.01:
		_rope.visible = false
		return
	var up := Vector3.UP if absf(d.y / length) < 0.98 else Vector3.RIGHT
	_rope.global_transform = Transform3D(Basis.looking_at(d / length, up) * Basis.from_scale(Vector3(1.0, 1.0, length)), (from + to) * 0.5)


# ---------------------------------------------------------------- weapons

func refill_ammo() -> void:
	ammo.clear()
	for wid in slots:
		if not wid.is_empty():
			ammo[wid] = Vector2i(mag_size(wid), _reserve(wid))


func add_ammo_pickup() -> void:
	for wid in slots:
		if wid.is_empty():
			continue
		var a: Vector2i = ammo[wid]
		a.y = mini(a.y + mag_size(wid) * 2 * _ammo_scale(wid), _reserve(wid) * 2)
		ammo[wid] = a


## True when an ammo crate would add anything (reserve below its cap on some gun).
func needs_ammo() -> bool:
	if mode == Mode.REMOTE:
		return (_remote_flags & FLAG_NEEDS_AMMO) != 0
	for wid in slots:
		if not wid.is_empty() and mag_size(wid) > 0 and (ammo[wid] as Vector2i).y < _reserve(wid) * 2:
			return true
	return false


## Tactical weapon pickups (every peer, from the server's event): puts `wid` in `slot` with a
## full magazine and the standard reserve, replacing whatever was there ("" empties the slot).
## A player holding the knife (or the replaced gun) draws the new weapon.
func give_weapon(slot: int, wid: String) -> void:
	var old := slots[slot]
	slots[slot] = wid
	info[["primary", "secondary"][slot]] = wid
	if not old.is_empty() and not slots.has(old):
		ammo.erase(old)
	if not wid.is_empty():
		ammo[wid] = Vector2i(mag_size(wid), _reserve(wid))
	if wid.is_empty() and current_slot == slot:
		current_slot = _first_armed_slot()
		_cancel_reload()
		_refresh_weapon_visual()
	elif mode != Mode.REMOTE and not wid.is_empty() and (current_slot == slot or weapon_id() == "knife"):
		switch_to(slot)
		# switch_to set the replaced gun as the "last weapon"; X should go back to the knife.
		if previous_slot == slot:
			previous_slot = 2


## Lowest slot holding a weapon (the knife slot always does).
func _first_armed_slot() -> int:
	for i in slots.size():
		if not slots[i].is_empty():
			return i
	return slots.size() - 1


## Next (step 1) or previous (-1) slot holding a weapon, for the mouse wheel.
func _cycle_slot(step: int) -> int:
	var i := current_slot
	for n in slots.size():
		i = posmod(i + step, slots.size())
		if not slots[i].is_empty():
			return i
	return current_slot


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
	grenade_cooldown -= delta
	melee_timer = maxf(0.0, melee_timer - delta)
	knife_cooldown = maxf(0.0, knife_cooldown - delta)
	bloom = move_toward(bloom, 0.0, delta * 7.0)
	recoil = move_toward(recoil, 0.0, delta * (6.0 + recoil * 5.0))
	if not in_fire:
		_trigger_down = false
	if world.match_over or world.attacks_blocked():
		in_reload = false
		in_grenade = false
		in_tactical = false
		in_melee = false
		in_slot = -1
		_burst_left = 0
		return

	if in_slot >= 0:
		var wanted := in_slot
		in_slot = -1
		if wanted != current_slot and wanted < slots.size() and not slots[wanted].is_empty():
			switch_to(wanted)
	if in_grenade and grenades > 0 and grenade_cooldown > GRENADE_BUFFER:
		in_grenade = false
	if in_tactical and tacticals > 0 and grenade_cooldown > GRENADE_BUFFER:
		in_tactical = false
	if switch_timer > 0.0 or melee_timer > 0.0:
		return
	# Pressing with none left says so instead of doing nothing.
	if in_grenade:
		if grenades <= 0:
			in_grenade = false
			if mode == Mode.LOCAL:
				Sfx.play(&"dry_fire", null, -6.0)
				world.hud.pickup_message("no_grenades")
		elif grenade_cooldown <= 0.0:
			in_grenade = false
			_throw_grenade("grenade")
			return
	if in_tactical:
		if tacticals <= 0:
			in_tactical = false
			if mode == Mode.LOCAL:
				Sfx.play(&"dry_fire", null, -6.0)
				world.hud.pickup_message("no_tactical")
		elif grenade_cooldown <= 0.0:
			in_tactical = false
			_throw_grenade(tactical_id())
			return
	if in_melee:
		in_melee = false
		_burst_left = 0
		_melee_attack(true)
		return

	var wid := weapon_id()
	var w := weapon_data()
	if reloading:
		_tick_reload(delta, wid, w)
	if in_reload:
		in_reload = false
		start_reload()
	if _burst_left > 0:
		_continue_burst(wid, w)
	elif in_fire:
		_try_fire(wid, w)


func switch_to(slot: int) -> void:
	previous_slot = current_slot
	current_slot = slot
	switch_timer = switch_time()
	_burst_left = 0
	_cancel_reload()
	_trigger_down = true
	if mode == Mode.LOCAL:
		Sfx.play(&"weapon_switch", null, -8.0)
	_refresh_weapon_visual()


func start_reload() -> void:
	var wid := weapon_id()
	var w := weapon_data()
	var a: Vector2i = ammo[wid]
	if reloading or mag_size(wid) == 0 or a.x >= mag_size(wid) or a.y <= 0:
		return
	reloading = true
	reload_timer = reload_time(wid)
	# Shotguns replay the animation per shell in _tick_reload.
	_play_reload_anim(reload_time(wid))
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
		if a.y > 0 and a.x < mag_size(wid):
			a.x += 1
			a.y -= 1
			if mode == Mode.LOCAL:
				Sfx.play(&"reload", null, -10.0, 1.3)
			if a.y > 0 and a.x < mag_size(wid):
				_play_reload_anim(reload_time(wid))
		ammo[wid] = a
		if a.y > 0 and a.x < mag_size(wid):
			reload_timer = reload_time(wid)
		else:
			reloading = false
		return
	var take := mini(mag_size(wid) - a.x, a.y)
	ammo[wid] = Vector2i(a.x + take, a.y - take)
	reloading = false


func _try_fire(wid: String, w: Dictionary) -> void:
	if reloading:
		# Shotguns can interrupt a shell-by-shell reload with a fresh trigger pull. A pull while the
		# pump is still cycling waits (held) for the shot instead of throwing the reload away.
		if w.get("reload_per_shell", false) and (ammo[wid] as Vector2i).x > 0 and not _trigger_down and fire_cooldown <= 0.0:
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
	# Carry the part of a tick the cooldown overshot when the trigger is held, so automatic fire
	# keeps its rated rpm instead of rounding every shot up to whole physics ticks.
	var overshoot := fire_cooldown if fire_cooldown > -get_physics_process_delta_time() else 0.0
	var burst := int(w.get("burst", 1))
	if burst > 1:
		_burst_left = burst - 1
		fire_cooldown = 60.0 / float(w.burst_rpm)
	else:
		fire_cooldown = 60.0 / float(w.rpm) + minf(overshoot, 0.0)
	_shoot(wid, w)


## Burst weapons: the rest of the burst fires on its own at `burst_rpm`; the last shot's cooldown
## pads the cycle so the average rate stays at `rpm` (what the server's fire-rate check expects).
func _continue_burst(wid: String, w: Dictionary) -> void:
	if fire_cooldown > 0.0:
		return
	if reloading or (ammo[wid] as Vector2i).x <= 0:
		_burst_left = 0
		return
	_burst_left -= 1
	var burst := int(w.burst)
	if _burst_left > 0:
		fire_cooldown = 60.0 / float(w.burst_rpm)
	else:
		fire_cooldown = burst * 60.0 / float(w.rpm) - (burst - 1) * 60.0 / float(w.burst_rpm)
	_shoot(wid, w)


## Spends a round and fires it (hitscan or rocket), with recoil and an automatic reload when the
## magazine runs dry.
func _shoot(wid: String, w: Dictionary) -> void:
	var a: Vector2i = ammo[wid]
	a.x -= 1
	ammo[wid] = a
	var aim := aim_transform()
	if w.get("projectile", false):
		var spread := lerpf(float(w.spread_hip) * mod("laser"), float(w.spread_ads), aim_blend)
		var dir := _spread_dir(aim.basis, spread)
		world.request_projectile(self, "rocket", _launch_origin(aim.origin, dir, 0.6), dir * float(w.speed))
	else:
		_fire_hitscan(wid, w, aim)
	_apply_kick(w)
	if a.x == 0 and a.y > 0:
		_burst_left = 0
		start_reload()


## Eye position and look basis including temporary recoil.
func aim_transform() -> Transform3D:
	var b := Basis.from_euler(Vector3(pitch + deg_to_rad(recoil), yaw, 0.0))
	return Transform3D(b, head.global_position)


func current_spread() -> float:
	var w := weapon_data()
	var s := lerpf(float(w.spread_hip) * mod("laser"), float(w.spread_ads), aim_blend) + bloom
	var hspeed := Vector2(velocity.x, velocity.z).length()
	s += clampf(hspeed / WALK_SPEED, 0.0, 1.4) * float(w.spread_hip) * 0.35 * (1.0 - aim_blend * 0.6)
	if not is_on_floor():
		s += float(w.spread_hip) * 0.6 + 1.5
	if prone:
		s *= 0.6
	elif crouching:
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
			var dmg := damage_at(w, dist, mod("barrel")) * (float(w.head_mult) if is_head else 1.0)
			var entry: Array = hits.get(target.id, [0.0, false])
			entry[0] += dmg
			entry[1] = entry[1] or is_head
			hits[target.id] = entry
		else:
			normals.append(r.normal)
	bloom = minf(bloom + (float(w.spread_hip) * 0.22 + 0.25) * mod("stabilizer"), float(w.spread_hip) * 1.6)
	world.report_shot(self, wid, ends, normals, hits)


## `range_mult` stretches the falloff distances (Long Barrel upgrade).
static func damage_at(w: Dictionary, dist: float, range_mult := 1.0) -> float:
	var start := float(w.falloff_start) * range_mult
	var stop := float(w.falloff_end) * range_mult
	var t := clampf((dist - start) / maxf(stop - start, 0.001), 0.0, 1.0)
	return float(w.damage) * lerpf(1.0, float(w.min_mult), t)


func _apply_kick(w: Dictionary) -> void:
	var kick := float(w.recoil) * mod("grip") * lerpf(1.0, 0.6, aim_blend) * (0.65 if prone else (0.8 if crouching else 1.0))
	if mode == Mode.LOCAL:
		pitch = clampf(pitch + deg_to_rad(kick * 0.55), -MAX_PITCH, MAX_PITCH)
		yaw += deg_to_rad(randf_range(-0.35, 0.35) * kick * 0.4)
		recoil += kick * 0.45
		viewmodel.play_fire(kick)
	avatar.play_shoot()


func _melee_attack(quick: bool) -> void:
	var w: Dictionary = Data.WEAPONS.knife
	var interval := 60.0 / float(w.rpm)
	if knife_cooldown > 0.0:
		return
	melee_timer = MELEE_TIME if quick else 0.0
	knife_cooldown = interval
	# Never shortens a gun's refire time: the server keeps one fire-rate budget per shooter.
	fire_cooldown = maxf(fire_cooldown, interval)
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
	avatar.play_slash()
	world.report_shot(self, "knife", PackedVector3Array([end]), PackedVector3Array([normal]), hits)


## The loadout's tactical grenade ("smoke" or "flash").
func tactical_id() -> String:
	var t := str(info.get("tactical", "smoke"))
	return t if Data.TACTICALS.has(t) else "smoke"


## Throws a frag ("grenade") or this player's tactical grenade.
func _throw_grenade(kind: String) -> void:
	if kind == "grenade":
		grenades -= 1
	else:
		tacticals -= 1
	grenade_cooldown = GRENADE_COOLDOWN
	_burst_left = 0
	var aim := aim_transform()
	var dir := -aim.basis.z
	var vel := dir * float(Data.GRENADE.throw_speed) + Vector3.UP * 3.0 + Vector3(velocity.x, 0.0, velocity.z) * 0.4
	if mode == Mode.LOCAL:
		viewmodel.play_throw()
	avatar.play_throw()
	world.request_projectile(self, kind, _launch_origin(aim.origin, dir, 0.5), vel)


## Where a rocket or grenade starts: `ahead` metres along `dir` from the eye, pulled back in front
## of a wall or hitbox in between. A projectile spawned inside a block (eye 0.4 m from a wall) or
## a point-blank hitbox would never register that hit and fly through it.
func _launch_origin(eye: Vector3, dir: Vector3, ahead: float) -> Vector3:
	var to := eye + dir * ahead
	var q := PhysicsRayQueryParameters3D.create(eye, to, MASK_WORLD | MASK_HITBOX, _exclude)
	q.collide_with_areas = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return to
	return eye + dir * maxf(0.0, eye.distance_to(r.position) - 0.1)


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
	if sliding:
		f |= FLAG_SLIDE
	if prone:
		f |= FLAG_PRONE
	f |= weapon_index(weapon_id()) << FLAG_WEAPON_SHIFT
	f |= (roundi(lean * _lean_reach * 7.0) + 8) << FLAG_LEAN_SHIFT
	return f


static func flags_weapon(f: int) -> String:
	return weapon_from_index((f >> FLAG_WEAPON_SHIFT) & 0xFF)


## Lean encoded in state flags, -1..1 (0 when the field is absent).
static func flags_lean(f: int) -> float:
	var q := (f >> FLAG_LEAN_SHIFT) & 0xF
	return 0.0 if q == 0 else clampf((q - 8) / 7.0, -1.0, 1.0)


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
	var prev_weapon := flags_weapon(_remote_flags)
	_remote_flags = b[4]
	var now_weapon := flags_weapon(_remote_flags)
	var now_reloading := (_remote_flags & FLAG_RELOAD) != 0
	var reload_w: Dictionary = Data.WEAPONS[now_weapon]
	var per_shell: bool = reload_w.get("reload_per_shell", false)
	# Shotguns replay the pose per shell, with a short gap so shells read as separate motions.
	if now_reloading and not avatar.is_reloading():
		_reload_gap += get_physics_process_delta_time()
	else:
		_reload_gap = 0.0
	_reload_hold -= get_physics_process_delta_time()
	if now_reloading and (not was_reloading or (per_shell and _reload_gap > 0.15 and _reload_hold <= 0.0)):
		_reload_gap = 0.0
		avatar.play_reload(reload_time(now_weapon))
	elif was_reloading and not now_reloading and (prev_weapon != now_weapon or not per_shell):
		# A finished shotgun reload lets its last shell's pose ease out instead of snapping.
		avatar.stop_reload()
	var dt := get_physics_process_delta_time()
	crouching = (_remote_flags & FLAG_CROUCH) != 0
	prone = (_remote_flags & FLAG_PRONE) != 0
	sprinting = (_remote_flags & FLAG_SPRINT) != 0
	var was_sliding := sliding
	sliding = (_remote_flags & FLAG_SLIDE) != 0
	if sliding and not was_sliding:
		Sfx.play(&"slide", global_position, -2.0)
	aim_blend = 1.0 if (_remote_flags & FLAG_AIM) != 0 else 0.0
	crouch_blend = move_toward(crouch_blend, 1.0 if crouching else 0.0, dt * 8.0)
	prone_blend = move_toward(prone_blend, 1.0 if prone else 0.0, dt * 4.0)
	lean = move_toward(lean, flags_lean(_remote_flags), dt * LEAN_RATE * 1.5)
	_apply_crouch_shape()
	_apply_head_pose()
	var slot := slots.find(now_weapon)
	if slot >= 0 and slot != current_slot:
		current_slot = slot
		_refresh_weapon_visual()


# ---------------------------------------------------------------- visuals

func _update_visuals(delta: float) -> void:
	rotation.y = yaw
	var pos := global_position
	var step := Vector3(pos.x - _last_visual_pos.x, 0.0, pos.z - _last_visual_pos.z)
	_last_visual_pos = pos
	var world_vel := Vector3(velocity.x, 0.0, velocity.z)
	if mode == Mode.REMOTE:
		anim_speed = lerpf(anim_speed, step.length() / maxf(delta, 0.0001), 0.3)
		on_floor_visual = (_remote_flags & FLAG_FLOOR) != 0
		world_vel = step / maxf(delta, 0.0001)
	else:
		anim_speed = world_vel.length()
		on_floor_visual = is_on_floor()
	if protected_until > 0.0 and World.now() >= protected_until:
		set_protection(0.0)
	if alive:
		var local_vel := Basis(Vector3.UP, yaw).inverse() * world_vel
		avatar.set_motion(sliding, lean * _lean_reach, Vector2(local_vel.x, -local_vel.z), grappling)
		avatar.set_look_pitch(pitch)
		avatar.animate(delta, anim_speed, on_floor_visual, crouching, prone)
		_footsteps(delta)
	_update_rope(delta)
	if camera != null and not alive and camera.top_level:
		_update_death_cam(delta)
	elif camera != null and alive:
		camera.rotation.x = pitch + deg_to_rad(recoil)
		# Peeking rolls the view toward the lean; sliding tilts it a little.
		var roll := -lean * _lean_reach * LEAN_ROLL + (deg_to_rad(-4.0) if sliding else 0.0)
		camera.rotation.z = lerpf(camera.rotation.z, roll, minf(1.0, delta * 12.0))
		var base_fov := float(Profile.get_setting("fov"))
		var target_fov := lerpf(base_fov, minf(float(weapon_data().ads_fov), base_fov), aim_blend)
		if sprinting:
			target_fov += 4.0
		elif sliding:
			target_fov += 7.0
		elif grappling:
			target_fov += 9.0
		camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 12.0))
		viewmodel.update_pose(delta, self)
	_update_laser()


## Laser Sight attachment: beam from the gun to where the shot would go, hidden while the gun
## is down (switching, reloading, sprinting, knife) and the beam (not the dot) when scoped.
func _update_laser() -> void:
	if laser == null:
		return
	var down := not alive or weapon_id() == "knife" or switch_timer > 0.0 or reloading or sprinting
	if mode == Mode.REMOTE:
		down = not alive or weapon_id() == "knife" or (_remote_flags & (FLAG_RELOAD | FLAG_SPRINT)) != 0
	if down or world.match_over:
		laser.visible = false
		return
	var aim := aim_transform()
	var from := aim.origin
	if viewmodel != null:
		from = viewmodel.muzzle_position()
	elif _muzzle != null:
		from = _muzzle.global_position
	var scoped: bool = weapon_data().get("scope", false) and aim_blend > 0.85
	laser.aim(from, aim.origin, -aim.basis.z, _exclude, not scoped)


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
		var vol := -14.0 if crouching or prone else (-6.0 if sprinting else -9.0)
		if mode == Mode.LOCAL:
			Sfx.play(&"footstep", null, vol - 4.0)
		else:
			Sfx.play(&"footstep", global_position, vol)


func _refresh_weapon_visual() -> void:
	var wid := weapon_id()
	if wid == _shown_weapon:
		return
	_shown_weapon = wid
	avatar.hold_weapon(wid, Data.gun_skin_for(info, wid))
	_muzzle = avatar.find_child("Muzzle", true, false) as Node3D
	if viewmodel != null:
		viewmodel.set_weapon(wid, switch_time())


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
	shield = 0.0
	set_protection(0.0)
	_cancel_reload()
	_clear_intent()
	aim_blend = 0.0
	sprinting = false
	crouching = false
	crouch_blend = 0.0
	melee_timer = 0.0
	grenade_cooldown = 0.0
	knife_cooldown = 0.0
	_applied_crouch = -1.0
	_applied_prone = -1.0
	_reset_movement_state()
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


## Clears sliding, leaning and the grapple (death and respawn; no network message: every peer
## runs these itself).
func _reset_movement_state() -> void:
	sliding = false
	prone = false
	prone_blend = 0.0
	_slide_cooldown = 0.0
	_burst_left = 0
	lean = 0.0
	_lean_reach = 1.0
	grappling = false
	grapple_cooldown = 0.0
	_crouch_was_held = false
	_jump_was_held = false
	_was_sprinting = false
	_rope.visible = false
	flashed_until = -100.0
	if camera != null:
		camera.rotation.z = 0.0


func respawn(pos: Vector3, p_yaw: float) -> void:
	global_position = pos
	_last_visual_pos = pos
	velocity = Vector3.ZERO
	yaw = p_yaw
	pitch = 0.0
	recoil = 0.0
	bloom = 0.0
	health = max_health()
	shield = 0.0
	alive = true
	_refill_equipment()
	_reset_movement_state()
	_clear_intent()
	_cancel_reload()
	_remote_flags = FLAG_FLOOR
	fire_cooldown = 0.0
	switch_timer = switch_time()
	melee_timer = 0.0
	grenade_cooldown = 0.0
	knife_cooldown = 0.0
	crouching = false
	crouch_blend = 0.0
	sprinting = false
	aim_blend = 0.0
	_trigger_down = false
	_applied_crouch = -1.0
	_applied_prone = -1.0
	_snapshots.clear()
	refill_ammo()
	if current_slot != 0:
		previous_slot = current_slot
		current_slot = _first_armed_slot()
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
		viewmodel.play_draw(switch_time())
		_end_death_cam()
	if brain != null:
		brain.on_respawn()
	_apply_crouch_shape()


## Drops every queued action so nothing pressed while dead fires on respawn.
func _clear_intent() -> void:
	in_move = Vector2.ZERO
	in_fire = false
	in_aim = false
	in_jump = false
	in_crouch = false
	in_prone = false
	in_sprint = false
	in_reload = false
	in_grenade = false
	in_melee = false
	in_tactical = false
	in_grapple = false
	in_lean = 0
	in_slot = -1


## The camera rises behind the corpse, on the side away from the killer, and turns to keep the
## killer in frame (zooming in when they are far away) until respawn. Without a killer it
## looks down at the corpse; so does it whenever a wall stands between the camera itself and the
## killer (checked every frame from where the camera is, also while it moves between the raised
## eye and the corpse's head), cutting away at once, so the killer is never framed through scenery.
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
	var eye := _death_cam_eye
	var focus := global_position + Vector3.UP * 0.6
	var base_fov := float(Profile.get_setting("fov"))
	var target_fov := base_fov
	var has_killer := _death_cam_target != null and is_instance_valid(_death_cam_target)
	var killer_pos := Vector3.ZERO
	if has_killer:
		killer_pos = _death_cam_target.global_position + Vector3.UP * 1.1
		# Settle at the raised eye if it sees the killer, else where the player fell if that does.
		var fell_eye := global_position + Vector3.UP * 1.6
		if not _clear_line(eye, killer_pos) and _clear_line(fell_eye, killer_pos):
			eye = fell_eye
	var pos := camera.global_position.lerp(eye, k)
	# The camera may be on its way between the two spots, so the line is checked from where it is.
	var watching := has_killer and _clear_line(pos, killer_pos)
	if watching:
		focus = killer_pos
		# Frame about 7 m around the killer vertically, so a distant one is still recognisable.
		target_fov = clampf(rad_to_deg(2.0 * atan(3.5 / maxf(0.1, pos.distance_to(focus)))), 24.0, base_fov)
	# A killer out of sight: look straight at the corpse instead of turning away through the wall.
	var turn := k if watching or not has_killer else 1.0
	if pos.distance_squared_to(focus) < 0.01:
		return
	var look := Transform3D(Basis.IDENTITY, pos).looking_at(focus, Vector3.UP)
	var rot := camera.global_basis.get_rotation_quaternion().slerp(look.basis.get_rotation_quaternion(), turn)
	camera.global_transform = Transform3D(Basis(rot), pos)
	camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 3.0))


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _end_death_cam() -> void:
	_death_cam_target = null
	camera.top_level = false
	camera.transform = Transform3D.IDENTITY
