class_name BotBrain
extends Node
## Server-side AI for a BOT Player. Fills the player's intent fields (in_move, in_fire, yaw...)
## each physics frame, so bots obey exactly the same movement and weapon rules as humans.
##
## Loop: perceive (throttled) -> pick a goal -> follow a navmesh path or fight -> aim -> shoot.

## Per-difficulty tuning: Easy, Normal, Hard.
## Tuned so an average player wins most duels against Normal; Hard is a real challenge.
const REACTION := [0.9, 0.55, 0.32]
const AIM_ERROR_DEG := [11.0, 6.5, 3.5]
## Fraction of the aim error that never goes away however long a bot tracks you.
const MIN_ERROR := [0.7, 0.5, 0.35]
const TURN_SPEED_DEG := [140.0, 230.0, 360.0]
const VIEW_DISTANCE := [35.0, 50.0, 70.0]
const VIEW_FOV_DEG := [90.0, 110.0, 130.0]
const HEADSHOT_CHANCE := [0.02, 0.07, 0.15]
const BURST_TIME := [0.25, 0.4, 0.6]
## Minimum seconds between semi-auto trigger pulls (human click speed).
const SEMI_INTERVAL := [0.55, 0.38, 0.25]
const GRENADE_CHANCE := [0.0, 0.15, 0.3]
## Seconds a bot must track a target through the scope before taking a sniper shot.
const SNIPER_SETTLE := [1.5, 1.0, 0.65]

const PERCEIVE_INTERVAL := 0.15
const REPATH_INTERVAL := 0.9
const WAYPOINT_REACH := 0.7
const MEMORY_TIME := 4.0
const HEARING_DISTANCE := 7.0
## Catch-up pressure: per kill of score gap between the target and this bot, and per kill of the
## target's streak beyond 2, aim error and reaction time scale by this much (clamped below).
const PRESSURE_PER_KILL := 0.025
const PRESSURE_PER_STREAK := 0.04
const PRESSURE_RANGE := Vector2(0.8, 1.2)
## Target choice: a visible rival counts as this many metres closer per kill they lead this bot
## by (capped), so bots drift onto the leader; and this many metres further per other bot already
## fighting them, so the whole lobby never piles onto one player.
const LEADER_BIAS_PER_KILL := 1.5
const LEADER_BIAS_MAX := 7.5
const CROWD_PENALTY := 5.0

var p: Player
var difficulty := 1
## Personality: < 1 cautious (keeps distance, lurks near pickups), > 1 aggressive (pushes in,
## hunts players across the map). Rolled per bot so matches don't all play the same.
var aggression := 1.0

var target: Player
var _target_visible := false
var _last_seen_pos := Vector3.ZERO
var _last_seen_time := -100.0
var _reaction_left := 0.0
var _tracking_time := 0.0
var _aim_offset := Vector3.ZERO
var _aim_offset_timer := 0.0
var _aim_head := false
## Multiplier on aim error (and, halved, on reaction time) against the current target:
## < 1 when the target is running away with the match, > 1 when the target trails this bot.
var _pressure := 1.0

var _path := PackedVector3Array()
var _path_index := 0
var _goal := Vector3.ZERO
var _has_goal := false
var _repath_timer := 0.0
var _perceive_timer := 0.0

var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _burst_timer := 0.0
var _burst_pause := 0.0
var _semi_wait := 0.0
var _grenade_timer := 6.0
var _stuck_timer := 0.0
var _stuck_check_pos := Vector3.ZERO
var _crouch_timer := 0.0
var _jump_timer := 0.0


func _ready() -> void:
	p = get_parent() as Player
	difficulty = clampi(int(Net.config.difficulty), 0, 2)
	aggression = randf_range(0.6, 1.5)
	_perceive_timer = randf() * PERCEIVE_INTERVAL
	_stuck_check_pos = p.global_position


func on_respawn() -> void:
	target = null
	_target_visible = false
	_has_goal = false
	_path = PackedVector3Array()
	_last_seen_time = -100.0
	_grenade_timer = randf_range(4.0, 10.0)


func think(delta: float) -> void:
	_reset_intent()
	if p.world.match_over:
		return
	_perceive_timer -= delta
	if _perceive_timer <= 0.0:
		_perceive_timer = PERCEIVE_INTERVAL
		_perceive()
	_choose_weapon()
	if target != null and _target_visible:
		_tracking_time += delta
		_reaction_left -= delta
		_fight(delta)
	else:
		_tracking_time = 0.0
		_roam(delta)
	_check_stuck(delta)


func _reset_intent() -> void:
	p.in_move = Vector2.ZERO
	p.in_fire = false
	p.in_aim = false
	p.in_jump = false
	p.in_sprint = false
	p.in_crouch = false


# ---------------------------------------------------------------- perception

func _eye() -> Vector3:
	return p.head.global_position


func _can_see(other: Player, require_fov: bool) -> bool:
	var eye := _eye()
	var to := other.global_position + Vector3.UP * 1.2
	var d := eye.distance_to(to)
	if d > VIEW_DISTANCE[difficulty]:
		return false
	if require_fov and d > HEARING_DISTANCE:
		var fwd := -Basis(Vector3.UP, p.yaw).z
		var flat := Vector3(to.x - eye.x, 0.0, to.z - eye.z).normalized()
		if rad_to_deg(fwd.angle_to(flat)) > VIEW_FOV_DEG[difficulty] * 0.5:
			return false
	var q := PhysicsRayQueryParameters3D.create(eye, to, Player.MASK_WORLD)
	return p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _perceive() -> void:
	var now := World.now()
	var best: Player = null
	var best_score := INF
	for eid: int in p.world.entities:
		var other: Player = p.world.entities[eid]
		if other == p or not other.alive:
			continue
		var d := p.global_position.distance_to(other.global_position)
		if d > VIEW_DISTANCE[difficulty]:
			continue
		var was_attacker := other.id == p.last_attacker and now - p.last_hurt_time < 2.5
		if not _can_see(other, not was_attacker and other != target):
			continue
		# Prefer close, weak, and whoever is already shooting us; lean toward whoever is ahead on
		# kills, away from players other bots are already busy with.
		var score := d + other.health * 0.08 - (15.0 if was_attacker else 0.0) - (6.0 if other == target else 0.0)
		score += _crowd_against(other) * CROWD_PENALTY - _lead_of(other) * LEADER_BIAS_PER_KILL
		if score < best_score:
			best_score = score
			best = other
	if best != null:
		_pressure = _pressure_against(best)
		if best != target:
			target = best
			_reaction_left = REACTION[difficulty] * randf_range(0.8, 1.3) * (0.5 + 0.5 * _pressure)
			_tracking_time = 0.0
			_new_aim_offset()
		_target_visible = true
		_last_seen_pos = best.global_position
		_last_seen_time = now
	else:
		_target_visible = false
		if target != null and (not target.alive or now - _last_seen_time > MEMORY_TIME):
			target = null
		# Turn toward whoever hurt us even if we can't see them yet.
		if target == null and now - p.last_hurt_time < 1.0 and p.world.entities.has(p.last_attacker):
			var attacker: Player = p.world.entities[p.last_attacker]
			if attacker.alive and attacker != p:
				_last_seen_pos = attacker.global_position
				_last_seen_time = now
				_has_goal = false


## Kills `other` is ahead of this bot by (0 when level or behind), capped for target choice.
func _lead_of(other: Player) -> float:
	var scores: Dictionary = p.world.scores
	var gap := int(scores.get(other.id, {}).get("kills", 0)) - int(scores.get(p.id, {}).get("kills", 0))
	return minf(maxf(0.0, gap), LEADER_BIAS_MAX / LEADER_BIAS_PER_KILL)


## How many other bots currently have `other` as their target.
func _crowd_against(other: Player) -> int:
	var n := 0
	for eid: int in p.world.entities:
		var e: Player = p.world.entities[eid]
		if e != p and e.brain != null and e.alive and e.brain.target == other:
			n += 1
	return n


## Subtle rubber-banding so the leader feels hunted and stragglers get breathing room: a bot
## tightens up (at most 20% less aim error, 10% quicker reactions) against someone far ahead of
## it or on a streak, and loosens up by the same amount against someone trailing it.
func _pressure_against(other: Player) -> float:
	var scores: Dictionary = p.world.scores
	var mine: Dictionary = scores.get(p.id, {})
	var theirs: Dictionary = scores.get(other.id, {})
	var gap := int(theirs.get("kills", 0)) - int(mine.get("kills", 0))
	var streak := maxi(0, int(theirs.get("streak", 0)) - 2)
	return clampf(1.0 - PRESSURE_PER_KILL * gap - PRESSURE_PER_STREAK * streak, PRESSURE_RANGE.x, PRESSURE_RANGE.y)


# ---------------------------------------------------------------- weapons

func _choose_weapon() -> void:
	var primary := p.slots[0]
	var secondary := p.slots[1]
	var pa: Vector2i = p.ammo[primary]
	var sa: Vector2i = p.ammo[secondary]
	var dist := INF
	if target != null:
		dist = p.global_position.distance_to(target.global_position)
	var want := 0
	if pa.x + pa.y == 0:
		want = 1
	if want == 1 and sa.x + sa.y == 0:
		want = 2
	if primary == "rocket" and dist < 6.0:
		want = 1 if sa.x + sa.y > 0 else 2
	var reacted := target != null and _target_visible and _reaction_left <= 0.0
	if reacted and dist < 2.2 and difficulty > 0 and p.current_slot != 2:
		p.in_melee = p.melee_timer <= 0.0 and randf() < 0.06
	if want != p.current_slot and p.switch_timer <= 0.0:
		p.in_slot = want
	if target == null and not p.reloading:
		var cur: Vector2i = p.ammo[p.weapon_id()]
		var mag := int(p.weapon_data().mag)
		if mag > 0 and cur.x < mag * 0.6 and cur.y > 0:
			p.in_reload = true


func _preferred_range() -> Vector2:
	match p.weapon_id():
		"knife": return Vector2(0.0, 1.6)
		"shotgun": return Vector2(2.0, 7.0)
		"smg": return Vector2(4.0, 14.0)
		"pistol", "revolver": return Vector2(6.0, 20.0)
		"sniper": return Vector2(18.0, 60.0)
		"rocket": return Vector2(9.0, 30.0)
	return Vector2(8.0, 30.0)


# ---------------------------------------------------------------- combat

func _fight(delta: float) -> void:
	var dist := p.global_position.distance_to(target.global_position)
	var w := p.weapon_data()
	var wid := p.weapon_id()

	# Aim point: chest by default, sometimes the head, feet for rockets.
	var aim_point := target.global_position + Vector3.UP * (1.0 if target.crouching else 1.25)
	if wid == "rocket":
		aim_point = target.global_position + Vector3.UP * 0.2 + _target_velocity() * (dist / float(w.speed))
	elif _aim_head:
		aim_point = target.head.global_position
	_aim_offset_timer -= delta
	if _aim_offset_timer <= 0.0:
		_new_aim_offset()
	var error_scale := maxf(MIN_ERROR[difficulty], 1.0 - _tracking_time * 0.35)
	# Getting shot throws the bot's aim off, like a flinch.
	if World.now() - p.last_hurt_time < 0.35:
		error_scale *= 1.8
	aim_point += _aim_offset * dist * error_scale

	var thrown := _reaction_left <= 0.0 and _maybe_grenade(delta, dist)
	if not thrown:
		_turn_toward(aim_point, delta)

	# Movement: hold preferred range and strafe.
	var range_pref := _preferred_range() / aggression
	var to_target := target.global_position - p.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z).normalized()
	var right := flat.cross(Vector3.UP)
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.5, 1.4)
		_strafe_dir = -_strafe_dir if randf() < 0.7 else _strafe_dir
	var move := right * _strafe_dir * (0.4 if difficulty == 0 else 0.85)
	if dist > range_pref.y:
		_go_toward(target.global_position, delta)
		move = Vector3.ZERO
	elif dist < range_pref.x:
		move -= flat * 0.8
	if move != Vector3.ZERO:
		if not _ground_ahead(move.normalized()):
			_strafe_dir = -_strafe_dir
			move = right * _strafe_dir * 0.6
			if not _ground_ahead(move.normalized()):
				move = Vector3.ZERO
		_set_move_world(move)

	_jump_timer -= delta
	if difficulty > 0 and _jump_timer <= 0.0:
		_jump_timer = randf_range(2.5, 6.0)
		p.in_jump = randf() < 0.35 and dist < 20.0
	_crouch_timer -= delta
	if difficulty == 2 and dist > 18.0 and _crouch_timer > 0.0:
		p.in_crouch = true
	elif _crouch_timer <= -3.0:
		_crouch_timer = randf_range(1.0, 2.5)

	# Fire control.
	var want_aim := wid != "knife" and wid != "shotgun" and (dist > 14.0 or wid == "sniper")
	p.in_aim = want_aim and (difficulty > 0 or wid == "sniper")
	if _reaction_left > 0.0 or thrown:
		return
	if wid == "sniper" and (p.aim_blend < 0.95 or _tracking_time < SNIPER_SETTLE[difficulty]):
		return
	var aim_dir := -Basis.from_euler(Vector3(p.pitch, p.yaw, 0.0)).z
	var needed := (aim_point - p.head.global_position).normalized()
	var tolerance := rad_to_deg(atan2(0.55, maxf(dist, 0.5))) + 1.0
	if rad_to_deg(aim_dir.angle_to(needed)) > tolerance:
		return
	if wid == "knife":
		p.in_fire = dist < 2.6
		return
	if w.auto:
		_burst_timer -= delta
		if _burst_timer > 0.0:
			p.in_fire = true
		else:
			_burst_pause -= delta
			if _burst_pause <= 0.0:
				_burst_timer = BURST_TIME[difficulty] * randf_range(0.7, 1.4) * (1.4 if dist < 10.0 else 1.0)
				_burst_pause = randf_range(0.25, 0.55) * (1.5 if dist > 25.0 else 1.0)
	else:
		_semi_wait -= delta
		if _semi_wait <= 0.0 and p.fire_cooldown <= 0.0:
			p.in_fire = true
			_semi_wait = SEMI_INTERVAL[difficulty] * randf_range(0.8, 1.4)


func _target_velocity() -> Vector3:
	if target.mode == Player.Mode.BOT:
		return target.velocity
	return Vector3.ZERO


func _new_aim_offset() -> void:
	var err := tan(deg_to_rad(AIM_ERROR_DEG[difficulty])) * _pressure
	_aim_offset = Vector3(randf_range(-1, 1), randf_range(-0.6, 1.0), randf_range(-1, 1)).normalized() * err * randf_range(0.3, 1.0)
	_aim_offset_timer = randf_range(0.25, 0.6)
	_aim_head = randf() < HEADSHOT_CHANCE[difficulty]


func _maybe_grenade(delta: float, dist: float) -> bool:
	_grenade_timer -= delta
	if _grenade_timer > 0.0 or p.grenades <= 0 or dist < 7.0 or dist > 24.0:
		return false
	_grenade_timer = randf_range(8.0, 16.0)
	if randf() > GRENADE_CHANCE[difficulty]:
		return false
	var to := target.global_position - p.head.global_position
	var flat_d := Vector2(to.x, to.z).length()
	var v := float(Data.GRENADE.throw_speed)
	var s := clampf(Projectile.GRENADE_GRAVITY * flat_d / (v * v), 0.0, 1.0)
	p.yaw = atan2(-to.x, -to.z)
	p.pitch = clampf(0.5 * asin(s) - 0.12 + atan2(to.y, flat_d) * 0.5, -0.3, 0.8)
	p.in_grenade = true
	return true


func _turn_toward(point: Vector3, delta: float) -> void:
	var to := point - p.head.global_position
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var step := deg_to_rad(TURN_SPEED_DEG[difficulty]) * delta
	p.yaw = p.yaw + clampf(wrapf(want_yaw - p.yaw, -PI, PI), -step, step)
	p.pitch = clampf(p.pitch + clampf(want_pitch - p.pitch, -step, step), -Player.MAX_PITCH, Player.MAX_PITCH)


# ---------------------------------------------------------------- roaming

func _roam(delta: float) -> void:
	var now := World.now()
	if now - _last_seen_time < MEMORY_TIME:
		if not _has_goal or _goal.distance_to(_last_seen_pos) > 3.0:
			_set_goal(_last_seen_pos)
	elif not _has_goal:
		_set_goal(_pick_roam_goal())
	_go_toward(_goal, delta)
	p.in_sprint = difficulty > 0 and now - _last_seen_time > 1.5
	if _path_index >= _path.size() and p.global_position.distance_to(_goal) < 2.0:
		_has_goal = false


func _pick_roam_goal() -> Vector3:
	var info := p.world.map_info
	var needs_health := p.health < 60.0
	var cur: Vector2i = p.ammo[p.slots[0]]
	var needs_ammo := cur.x + cur.y < int(Data.WEAPONS[p.slots[0]].mag)
	if needs_health or needs_ammo:
		var best := Vector3.ZERO
		var best_d := INF
		for i in p.world.pickup_nodes.size():
			var node := p.world.pickup_nodes[i]
			if not node.active:
				continue
			if (needs_health and node.kind == "health") or (needs_ammo and node.kind == "ammo"):
				var d := p.global_position.distance_to(node.position)
				if d < best_d:
					best_d = d
					best = node.position
		if best_d < INF:
			return best
	if aggression > 1.1 and randf() < 0.6:
		var prey: Array = p.world.entities.values().filter(func(o: Player) -> bool: return o != p and o.alive)
		if not prey.is_empty():
			return (prey.pick_random() as Player).global_position
	if randf() < 0.35 / aggression and not p.world.pickup_nodes.is_empty():
		return p.world.pickup_nodes.pick_random().position
	return info.spawns.pick_random()


func _set_goal(point: Vector3) -> void:
	_goal = point
	_has_goal = true
	_repath_timer = 0.0


func _go_toward(point: Vector3, delta: float) -> void:
	_repath_timer -= delta
	if _repath_timer <= 0.0 or _goal.distance_to(point) > 2.0:
		_repath_timer = REPATH_INTERVAL
		_goal = point
		_has_goal = true
		_path = NavigationServer3D.map_get_path(p.world.map_info.nav_map, p.global_position, point, true)
		_path_index = 0
	while _path_index < _path.size():
		var wp := _path[_path_index]
		var flat := Vector2(wp.x - p.global_position.x, wp.z - p.global_position.z)
		if flat.length() > WAYPOINT_REACH:
			break
		_path_index += 1
	var dest := point if _path_index >= _path.size() else _path[_path_index]
	var dir := Vector3(dest.x - p.global_position.x, 0.0, dest.z - p.global_position.z)
	if dir.length() < 0.3:
		return
	_set_move_world(dir.normalized())
	if target == null or not _target_visible:
		var look := dest + Vector3.UP * 1.5
		if _path_index + 1 < _path.size():
			look = _path[_path_index + 1] + Vector3.UP * 1.5
		_turn_toward(look, delta * 0.6)


func _set_move_world(dir: Vector3) -> void:
	var local := Basis(Vector3.UP, -p.yaw) * dir
	p.in_move = Vector2(local.x, -local.z).limit_length(1.0)


## True when there is floor about a metre ahead (stops strafing off ledges and islands).
func _ground_ahead(dir: Vector3) -> bool:
	var from := p.global_position + dir * 1.0 + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, Player.MASK_WORLD)
	return not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < 1.0:
		return
	var moved := Vector2(p.global_position.x - _stuck_check_pos.x, p.global_position.z - _stuck_check_pos.z).length()
	var trying := p.in_move.length() > 0.5
	_stuck_timer = 0.0
	_stuck_check_pos = p.global_position
	if trying and moved < 0.4:
		p.in_jump = true
		_repath_timer = 0.0
		if randf() < 0.4:
			_has_goal = false
			_set_goal(_pick_roam_goal())
