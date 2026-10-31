class_name BotBrain
extends Node
## Server-side AI for a BOT Player. Fills the player's intent fields (in_move, in_fire, yaw...)
## each physics frame, so bots obey exactly the same movement and weapon rules as humans.
##
## Loop: perceive (throttled) -> pick a goal -> follow a navmesh path or fight -> aim -> shoot.

## Per-difficulty tuning: Easy, Normal, Hard.
## Tuned so an average player comfortably wins duels against Normal; Hard is a fair challenge.
const REACTION := [1.1, 0.75, 0.48]
const AIM_ERROR_DEG := [14.0, 9.0, 5.5]
## Fraction of the aim error that never goes away however long a bot tracks you.
const MIN_ERROR := [0.8, 0.62, 0.48]
const TURN_SPEED_DEG := [120.0, 180.0, 270.0]
const VIEW_DISTANCE := [30.0, 42.0, 58.0]
const VIEW_FOV_DEG := [85.0, 100.0, 115.0]
const HEADSHOT_CHANCE := [0.01, 0.04, 0.09]
const BURST_TIME := [0.25, 0.35, 0.5]
## Minimum seconds between semi-auto trigger pulls (human click speed).
const SEMI_INTERVAL := [0.6, 0.45, 0.32]
## Grenades: while a target is in throwing range a bot considers a throw every THROW_CHECK
## seconds and goes for it with this chance; after a throw it waits THROW_REST before the next.
const FRAG_CHANCE := [0.2, 0.35, 0.5]
const TACTICAL_CHANCE := [0.3, 0.5, 0.65]
const THROW_CHECK := Vector2(2.5, 5.0)
const THROW_REST := Vector2(8.0, 14.0)
## Frag range (m) to the target, or to where a target that ducked into cover was last seen.
const FRAG_RANGE := Vector2(7.0, 24.0)
const TACTICAL_RANGE := Vector2(6.0, 22.0)
## A target out of sight for this long (s) gets a frag lobbed at its last-seen spot.
const FLUSH_WINDOW := Vector2(0.4, 3.0)
## Bots smoke themselves cover at or below this health.
const SMOKE_HEALTH := 70.0
## Metres of open air a throw needs straight ahead of the eye.
const THROW_CLEARANCE := 3.0
## Seconds a bot must track a target through the scope before taking a sniper shot.
const SNIPER_SETTLE := [1.8, 1.3, 0.9]
## How fast (1/s, exponential) the aim error drifts toward its next goal: ~90% of the way in 0.33 s.
const AIM_DRIFT_RATE := 7.0
const DRIFT_ERROR_SCALE := 1.12
## Long guns (the Snipers Only / Rocket Party primaries) are for range: inside this distance (m)
## a bot switches to its secondary, the backup gun, and back once the target is this far plus
## LONG_GUN_SLACK away (so it doesn't flip-flop at the edge).
const LONG_GUN_CLOSE := {"sniper": 12.0, "crossbow": 12.0, "rocket": 9.0}
const LONG_GUN_SLACK := 3.0
## Flinch on taking damage: aim error jumps by FLINCH_PEAK (x2.1) and settles linearly over
## FLINCH_TIME, so the bot recovers its aim instead of snapping back.
const FLINCH_TIME := 0.5
const FLINCH_PEAK := 1.1
## Reading movement: a bot's sense of its target's velocity catches up at READ_RATE (1/s,
## exponential) to READ_ACCURACY of the real thing, and its aim trails the target by TRACK_LAG
## seconds of the unread part of their sideways motion. Steady strafing is mostly read within a
## second; changing direction resets it, so strafing helps a little, juking a lot, and standing
## still not at all.
const READ_RATE := [2.0, 2.8, 4.0]
const READ_ACCURACY := [0.55, 0.68, 0.78]
const TRACK_LAG := [0.16, 0.12, 0.09]
## Movement mechanics, per difficulty (Easy, Normal, Hard). Each is a chance per decision:
## - slide: on a sprint with a clear straight run ahead (checked every 0.8-1.6 s);
## - peek: lean out sideways for 0.8-1.8 s during a fight at range;
## - prone: lie down for a steadier aim when the target is past PRONE_MIN_DIST and the bot
##   has not just been hit; it gets up when the target closes in or the fight ends;
## - grapple: hook up to a ledge on its route that is GRAPPLE_MIN_RISE higher, across a gap the
##   navmesh cannot bridge, or (aggressive bots) toward a distant target.
const SLIDE_CHANCE := [0.15, 0.35, 0.5]
const PEEK_CHANCE := [0.15, 0.35, 0.5]
const PRONE_CHANCE := [0.1, 0.25, 0.4]
const PRONE_MIN_DIST := 20.0
const PRONE_UP_DIST := 12.0
const GRAPPLE_CHANCE := [0.25, 0.5, 0.75]
const GRAPPLE_MIN_RISE := 2.5
## Seconds the bot may spend turning onto a grapple point before giving up on it.
const GRAPPLE_AIM_TIME := 1.2
## Block Bomber warnings (Streaks): the chance a bot under one runs from it, per difficulty, and
## how long after the call it reacts (seconds of the 2 s warning).
const DODGE_CHANCE := [0.3, 0.55, 0.8]
const DODGE_REACTION := [1.1, 0.8, 0.5]

const PERCEIVE_INTERVAL := 0.15
const REPATH_INTERVAL := 0.9
const WAYPOINT_REACH := 0.7
## Tactical: how often a roaming bot rereads its squad's orders.
const ORDER_INTERVAL := 0.3
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
## Placeholder for "no position yet", far outside every map.
const NO_POS := Vector3(0.0, -100000.0, 0.0)

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
## Aim error: _aim_offset drifts toward _aim_offset_goal (re-rolled every 0.25-0.6 s) instead of
## jumping, so the crosshair wanders around the target rather than twitching between misses.
var _aim_offset := Vector3.ZERO
var _aim_offset_goal := Vector3.ZERO
var _aim_offset_timer := 0.0
var _aim_head := false
## 0 = chest, 1 = head; eases toward _aim_head so switching aim height is a glide, not a snap.
var _head_blend := 0.0
## Multiplier on aim error (and, halved, on reaction time) against the current target:
## < 1 when the target is running away with the match, > 1 when the target trails this bot.
var _pressure := 1.0
## Target velocity measured from its motion (works for interpolated humans too), and how much of
## it the bot has read so far; see READ_RATE.
var _target_vel := Vector3.ZERO
var _read_vel := Vector3.ZERO
var _last_target_pos := Vector3.ZERO
var _last_read_frame := -10

var _path := PackedVector3Array()
var _path_index := 0
var _goal := Vector3.ZERO
var _has_goal := false
## The pickup the current goal leads to (null if none), so a taken one is abandoned on the way.
var _goal_pickup: PickupNode
## Last-seen position already searched; _roam heads to a last-seen spot once per new sighting.
var _chase_pos := NO_POS
## Tactical: heading for _chase_pos (a fresh sighting) before returning to squad orders.
var _chasing := false
## Tactical: the squad order last read (Tactical.bot_order) and seconds until it is read again.
var _order := {}
var _order_timer := 0.0
var _repath_timer := 0.0
## True while the bot flies off a jump pad (Player.pad_flight); landing replans the route.
var _pad_flying := false
var _perceive_timer := 0.0

var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _burst_timer := 0.0
var _burst_pause := 0.0
var _semi_wait := 0.0
var _grenade_timer := 4.0
var _tactical_timer := 2.5
var _stuck_timer := 0.0
var _stuck_check_pos := Vector3.ZERO
var _crouch_timer := 0.0
var _jump_timer := 0.0
var _slide_hold := 0.0
var _slide_check := 0.0
## Peek side while leaning (-1, 0, 1) and seconds until the next peek decision.
var _peek_side := 0
var _peek_timer := 0.0
var _prone_timer := 0.0
## Minimum gap between prone toggles, so a press is never sent twice before it lands.
var _prone_cooldown := 0.0
## World point the bot is turning to fire its grapple at (NO_POS when none).
var _grapple_aim := NO_POS
var _grapple_aim_left := 0.0
var _grapple_timer := 2.0
## The last strike this bot rolled to dodge: {strike id: dodges}.
var _dodges := {}


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
	_grenade_timer = randf_range(2.0, 6.0)
	_tactical_timer = randf_range(1.0, 4.0)
	_goal_pickup = null
	_chase_pos = NO_POS
	_path_index = 0
	_repath_timer = 0.0
	_reaction_left = 0.0
	_tracking_time = 0.0
	_target_vel = Vector3.ZERO
	_read_vel = Vector3.ZERO
	_burst_timer = 0.0
	_burst_pause = 0.0
	_semi_wait = 0.0
	_stuck_timer = 0.0
	_stuck_check_pos = p.global_position
	_slide_hold = 0.0
	_peek_side = 0
	_prone_cooldown = 0.0
	_grapple_aim = NO_POS
	_grapple_timer = randf_range(1.0, 3.0)


func think(delta: float) -> void:
	_reset_intent()
	if p.world.match_over:
		return
	# A target that died, left (despawned, freed) or turned into a teammate (Infected) since the
	# last perception pass is dropped at once, so the bot neither shoots a corpse or a friend nor
	# touches a freed node until the next _perceive().
	if target != null and (not is_instance_valid(target) or not target.alive or not p.world.is_enemy(p, target)):
		if is_instance_valid(target) and target.alive:
			# Now a teammate: nothing to search for where it was last seen either.
			_last_seen_time = -100.0
		target = null
		_target_visible = false
	_perceive_timer -= delta
	if _perceive_timer <= 0.0:
		_perceive_timer = PERCEIVE_INTERVAL
		_perceive()
	_prone_cooldown -= delta
	_choose_weapon()
	if target != null and _target_visible:
		_tracking_time += delta
		_reaction_left -= delta
		# A held Block Bomber goes on a target far enough away (Streaks decides when).
		p.world.streaks.bot_consider(p, target)
		_fight(delta)
	else:
		_tracking_time = 0.0
		_peek_side = 0
		# Nothing to shoot at: get up and move.
		if p.prone:
			_press_prone()
		_roam(delta)
		_maybe_flush(delta)
	_dodge_strike()
	# Mid-air off a jump pad the arc does the travelling (JumpPad: its NavigationLink3D put the pad
	# on the route): no steering, jumping or crouching; once down, the route is planned again from
	# where the bot landed.
	if p.pad_flight:
		p.in_move = Vector2.ZERO
		p.in_jump = false
		p.in_crouch = false
		_pad_flying = true
		return
	if _pad_flying:
		_pad_flying = false
		_repath_timer = 0.0
	_check_stuck(delta)


## A Block Bomber's ground warning under the bot: once it notices (DODGE_REACTION after the call,
## and only with DODGE_CHANCE per strike, decided once) it sprints out, whatever else it was doing.
func _dodge_strike() -> void:
	var danger := p.world.streaks.danger_near(p.global_position)
	if danger.is_empty():
		return
	var id := int(danger.id)
	if not _dodges.has(id):
		_dodges = {id: randf() < DODGE_CHANCE[difficulty]}
	if not _dodges[id] or float(danger.since) < DODGE_REACTION[difficulty]:
		return
	var away := p.global_position - (danger.pos as Vector3)
	away.y = 0.0
	if away.length() < 0.3:
		away = -Basis(Vector3.UP, p.yaw).z
	if p.prone:
		_press_prone()
	_set_move_world(away.normalized())
	p.in_sprint = true
	p.in_aim = false


func _reset_intent() -> void:
	p.in_move = Vector2.ZERO
	p.in_fire = false
	p.in_aim = false
	p.in_jump = false
	p.in_sprint = false
	p.in_crouch = false
	p.in_lean = 0
	# A melee or tactical press blocked by a weapon switch must not go off later, aimed elsewhere.
	p.in_melee = false
	p.in_tactical = false


# ---------------------------------------------------------------- perception

func _eye() -> Vector3:
	return p.head.global_position


func _can_see(other: Player, require_fov: bool) -> bool:
	# A flashed bot is blind until it wears off.
	if World.now() < p.flashed_until:
		return false
	var eye := _eye()
	var to := other.global_position + Vector3.UP * other.body_center_height()
	var d := eye.distance_to(to)
	if d > VIEW_DISTANCE[difficulty]:
		return false
	if require_fov and d > HEARING_DISTANCE:
		var fwd := -Basis(Vector3.UP, p.yaw).z
		var flat := Vector3(to.x - eye.x, 0.0, to.z - eye.z).normalized()
		if rad_to_deg(fwd.angle_to(flat)) > VIEW_FOV_DEG[difficulty] * 0.5:
			return false
	if p.world.smoke_blocks(eye, to):
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, to, Player.MASK_WORLD)
	return p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _perceive() -> void:
	var now := World.now()
	var best: Player = null
	var best_score := INF
	for eid: int in p.world.entities:
		var other: Player = p.world.entities[eid]
		if not p.world.is_enemy(p, other) or not other.alive:
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
			_new_aim_offset(true)
			_last_target_pos = best.global_position
			_target_vel = Vector3.ZERO
			_read_vel = Vector3.ZERO
			# Team modes: call the new contact out to the team (Pings rate-limits it).
			p.world.pings.bot_spotted(p, best)
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
			if attacker.alive and p.world.is_enemy(p, attacker):
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
	# Tactical slots can be empty (""): no ammo to speak of, so the bot falls through to the knife.
	var pa: Vector2i = p.ammo.get(primary, Vector2i.ZERO)
	var sa: Vector2i = p.ammo.get(secondary, Vector2i.ZERO)
	var dist := INF
	if target != null:
		dist = p.global_position.distance_to(target.global_position)
	var want := 0
	if pa.x + pa.y == 0:
		want = 1
	if want == 1 and sa.x + sa.y == 0:
		want = 2
	var close: float = LONG_GUN_CLOSE.get(primary, -1.0)
	if want == 0 and close > 0.0:
		if p.current_slot == 1:
			close += LONG_GUN_SLACK
		# A backup that is itself a long gun (a rocket behind the sniper) is no better up close.
		if dist < close and sa.x + sa.y > 0 and not LONG_GUN_CLOSE.has(secondary):
			want = 1
		elif dist < 6.0 and primary == "rocket":
			want = 2
	var reacted := target != null and _target_visible and _reaction_left <= 0.0
	if reacted and dist < 2.2 and difficulty > 0 and p.current_slot != 2 and target.protection_left() <= 0.0:
		p.in_melee = p.melee_timer <= 0.0 and randf() < 0.06
	if want != p.current_slot and p.switch_timer <= 0.0:
		p.in_slot = want
	if target == null and not p.reloading:
		var cur: Vector2i = p.ammo[p.weapon_id()]
		var mag := p.mag_size(p.weapon_id())
		if mag > 0 and cur.x < mag * 0.6 and cur.y > 0:
			p.in_reload = true


func _preferred_range() -> Vector2:
	var wid := p.weapon_id()
	if Data.is_melee(wid):
		return Vector2(0.0, float(Data.WEAPONS[wid].range) * 0.65)
	match wid:
		"shotgun", "sawed_off": return Vector2(2.0, 7.0)
		"drum_shotgun": return Vector2(3.0, 9.0)
		"smg", "machine_pistol": return Vector2(4.0, 14.0)
		"burst_smg": return Vector2(5.0, 16.0)
		"pistol", "revolver", "burst_pistol", "suppressed": return Vector2(6.0, 20.0)
		"carbine": return Vector2(8.0, 25.0)
		"rifle", "burst_rifle", "minigun": return Vector2(8.0, 30.0)
		"dmr": return Vector2(14.0, 45.0)
		"sniper": return Vector2(18.0, 60.0)
		"crossbow": return Vector2(16.0, 55.0)
		"rocket": return Vector2(9.0, 30.0)
	return Vector2(8.0, 30.0)


# ---------------------------------------------------------------- combat

func _fight(delta: float) -> void:
	var dist := p.global_position.distance_to(target.global_position)
	var w := p.weapon_data()
	var wid := p.weapon_id()

	# Aim point: chest by default, sometimes the head, feet for rockets.
	_aim_offset_timer -= delta
	if _aim_offset_timer <= 0.0:
		_new_aim_offset()
	_aim_offset = _aim_offset.lerp(_aim_offset_goal, 1.0 - exp(-AIM_DRIFT_RATE * delta))
	_head_blend = move_toward(_head_blend, 1.0 if _aim_head else 0.0, delta * 3.0)
	var aim_point := target.global_position + Vector3.UP * target.body_center_height()
	if wid == "rocket":
		aim_point = target.global_position + Vector3.UP * 0.2 + _target_velocity() * (dist / float(w.speed))
	elif _head_blend > 0.0:
		aim_point = aim_point.lerp(target.head.global_position, _head_blend)
	var error_scale := maxf(MIN_ERROR[difficulty], 1.0 - _tracking_time * 0.25)
	# Getting shot throws the bot's aim off, like a flinch, which settles back over FLINCH_TIME.
	var since_hurt := World.now() - p.last_hurt_time
	if since_hurt < FLINCH_TIME:
		error_scale *= 1.0 + FLINCH_PEAK * (1.0 - since_hurt / FLINCH_TIME)
	aim_point += _aim_offset * dist * error_scale
	aim_point -= _unread_motion(delta) * TRACK_LAG[difficulty]

	var thrown := _reaction_left <= 0.0 and (_maybe_grenade(delta, dist) or _maybe_tactical(delta, dist))
	# Aggressive bots far outside their range hook toward the target instead of walking.
	var hooking := false
	if not thrown and aggression > 1.1 and dist > maxf(_preferred_range().y / aggression, 20.0):
		hooking = _maybe_grapple(delta, target.global_position)
	if not thrown and not hooking:
		_turn_toward(aim_point, delta)

	# Movement: hold preferred range and strafe.
	var range_pref := _preferred_range() / aggression
	# The mode may want more room (Infected: survivors back off from the Infected).
	range_pref.x = maxf(range_pref.x, p.world.rules.bot_min_range(p, target))
	var to_target := target.global_position - p.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z).normalized()
	var right := flat.cross(Vector3.UP)
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.5, 1.4)
		_strafe_dir = -_strafe_dir if randf() < 0.7 else _strafe_dir
	var move := right * _strafe_dir * (0.4 if difficulty == 0 else 0.85)
	# A mode area to hold (King of the Block's zone): fight on the way into it, and once inside
	# only close in on targets that are in it too.
	var hold := p.world.rules.bot_hold_area(p)
	var outside := not hold.is_empty() and _flat_dist(p.global_position, hold[0]) > float(hold[1]) * 0.8
	var may_chase := hold.is_empty() or _flat_dist(target.global_position, hold[0]) <= float(hold[1])
	if outside:
		_go_toward(hold[0], delta)
		move = Vector3.ZERO
		p.in_sprint = difficulty > 0 and dist > range_pref.y + 6.0 and not p.prone
	elif dist > range_pref.y and may_chase:
		_go_toward(target.global_position, delta)
		move = Vector3.ZERO
		p.in_sprint = difficulty > 0 and dist > range_pref.y + 6.0 and not p.prone
		_maybe_slide(delta)
	elif dist < range_pref.x:
		move -= flat * 0.8
	_decide_peek(delta, dist)
	_decide_prone(delta, dist, wid)
	if _peek_side != 0 or p.prone:
		# Holding a peek or lying down: barely drift, keep the sights steady.
		move *= 0.3
	if move != Vector3.ZERO:
		if not _ground_ahead(move.normalized()):
			_strafe_dir = -_strafe_dir
			move = right * _strafe_dir * 0.6
			if not _ground_ahead(move.normalized()):
				move = Vector3.ZERO
		_set_move_world(move)
	p.in_lean = _peek_side

	_jump_timer -= delta
	if difficulty > 0 and _jump_timer <= 0.0:
		_jump_timer = randf_range(2.5, 6.0)
		p.in_jump = randf() < 0.35 and dist < 20.0 and not p.prone and _peek_side == 0
	_crouch_timer -= delta
	if difficulty == 2 and dist > 18.0 and _crouch_timer > 0.0 and not p.prone:
		p.in_crouch = true
	elif _crouch_timer <= -3.0:
		_crouch_timer = randf_range(1.0, 2.5)

	# Fire control.
	var want_aim := not Data.is_melee(wid) and wid not in ["shotgun", "sawed_off", "drum_shotgun"] \
		and (dist > 14.0 or wid in ["sniper", "crossbow", "minigun"])
	p.in_aim = want_aim and (difficulty > 0 or wid == "sniper")
	# The server ignores damage to a spawn-protected player, and firing would end the bot's own
	# protection, so hold fire (keep tracking) until the shimmer is gone.
	if _reaction_left > 0.0 or thrown or target.protection_left() > 0.0:
		return
	if wid in ["sniper", "crossbow", "minigun"] and (p.aim_blend < 0.95 or _tracking_time < SNIPER_SETTLE[difficulty]):
		return
	var aim_dir := -Basis.from_euler(Vector3(p.pitch, p.yaw, 0.0)).z
	var needed := (aim_point - p.head.global_position).normalized()
	var tolerance := rad_to_deg(atan2(0.55, maxf(dist, 0.5))) + 1.0
	if rad_to_deg(aim_dir.angle_to(needed)) > tolerance:
		return
	if Data.is_melee(wid):
		p.in_fire = dist < float(w.range) + 0.2
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


## Updates the bot's read of its target's movement and returns the sideways (across the line of
## sight) part of the target's velocity the bot hasn't caught up with yet.
func _unread_motion(delta: float) -> Vector3:
	var pos := target.global_position
	var moved := pos - _last_target_pos
	_last_target_pos = pos
	# A gap in sampling (the target was out of sight) or a teleport (respawn) is not motion.
	var frame := Engine.get_physics_frames()
	var contiguous := frame - _last_read_frame == 1
	_last_read_frame = frame
	if not contiguous or delta <= 0.0 or moved.length() > 3.0:
		return Vector3.ZERO
	_target_vel = _target_vel.lerp(moved / delta, 1.0 - exp(-15.0 * delta))
	_read_vel = _read_vel.lerp(_target_vel * READ_ACCURACY[difficulty], 1.0 - exp(-READ_RATE[difficulty] * delta))
	var unread := _target_vel - _read_vel
	var los := (pos - p.global_position).normalized()
	return unread - los * unread.dot(los)


func _target_velocity() -> Vector3:
	if target.mode == Player.Mode.BOT:
		return target.velocity
	return Vector3.ZERO


## Rolls a new aim-error goal (and head-or-chest choice). `snap` jumps straight to it, for a fresh
## target, where the reaction delay and the turn toward them hide the change.
func _new_aim_offset(snap := false) -> void:
	# DRIFT_ERROR_SCALE: drifting between goals cuts corners, so goals sit a little wider to keep
	# the average miss at AIM_ERROR_DEG's tuning.
	var err := tan(deg_to_rad(AIM_ERROR_DEG[difficulty])) * _pressure * DRIFT_ERROR_SCALE
	_aim_offset_goal = Vector3(randf_range(-1, 1), randf_range(-0.6, 1.0), randf_range(-1, 1)).normalized() * err * randf_range(0.3, 1.0)
	_aim_offset_timer = randf_range(0.25, 0.6)
	_aim_head = randf() < HEADSHOT_CHANCE[difficulty]
	if snap:
		_aim_offset = _aim_offset_goal
		_head_blend = 1.0 if _aim_head else 0.0


func _maybe_grenade(delta: float, dist: float) -> bool:
	_grenade_timer -= delta
	if _grenade_timer > 0.0 or dist < FRAG_RANGE.x or dist > FRAG_RANGE.y or target.protection_left() > 0.0:
		return false
	return _try_throw("grenade", target.global_position)


## A target that just ducked out of sight behind cover gets a frag lobbed where it was last seen.
func _maybe_flush(delta: float) -> void:
	if target == null or not target.alive:
		return
	var gone := World.now() - _last_seen_time
	if gone < FLUSH_WINDOW.x or gone > FLUSH_WINDOW.y:
		return
	_grenade_timer -= delta
	var dist := p.global_position.distance_to(_last_seen_pos)
	if _grenade_timer > 0.0 or dist < FRAG_RANGE.x or dist > FRAG_RANGE.y:
		return
	if _try_throw("grenade", _last_seen_pos):
		# Stop to throw: the move intent was set for the old facing.
		p.in_move = Vector2.ZERO


## Now and then a bot throws its tactical: a flash at a target in mid range, or a smoke on it
## when the bot is hurt and wants cover.
func _maybe_tactical(delta: float, dist: float) -> bool:
	_tactical_timer -= delta
	if _tactical_timer > 0.0 or dist < TACTICAL_RANGE.x or dist > TACTICAL_RANGE.y:
		return false
	if p.tactical_id() == "smoke" and p.health > SMOKE_HEALTH:
		return false
	return _try_throw(p.tactical_id(), target.global_position)


## Rolls for a throw of `kind` ("grenade" or the tactical) at `point` and, on success, aims and
## presses it. The press must go off this frame: the aim is set for this frame only, and a press
## queued behind a weapon switch, melee or the throw cooldown would leave later at whatever aim then.
func _try_throw(kind: String, point: Vector3) -> bool:
	var frag := kind == "grenade"
	if (p.grenades if frag else p.tacticals) <= 0:
		return false
	if p.in_slot >= 0 or p.switch_timer > 0.0 or p.melee_timer > 0.0 or p.grenade_cooldown > 0.0:
		return false
	var wait := randf_range(THROW_CHECK.x, THROW_CHECK.y)
	if frag:
		_grenade_timer = wait
	else:
		_tactical_timer = wait
	var chance: float = FRAG_CHANCE[difficulty] if frag else TACTICAL_CHANCE[difficulty]
	if randf() >= chance:
		return false
	var aim := _throw_aim(point + Vector3.UP * 0.3)
	# A wall or low ceiling right in front would bounce a frag back onto the bot.
	var dir := -Basis.from_euler(Vector3(aim.y, aim.x, 0.0)).z
	var q := PhysicsRayQueryParameters3D.create(p.head.global_position, p.head.global_position + dir * THROW_CLEARANCE, Player.MASK_WORLD)
	if not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return false
	p.yaw = aim.x
	# aim_transform adds the weapon's recoil kick on top of pitch.
	p.pitch = clampf(aim.y - deg_to_rad(p.recoil), -Player.MAX_PITCH, Player.MAX_PITCH)
	if frag:
		_grenade_timer = randf_range(THROW_REST.x, THROW_REST.y)
		p.in_grenade = true
	else:
		_tactical_timer = randf_range(THROW_REST.x, THROW_REST.y)
		p.in_tactical = true
	return true


## (yaw, pitch) of the low lob that lands a throw on `point`, matching Player._throw_grenade:
## launched at throw_speed along the aim plus 3 m/s up, from half a metre ahead of the eye.
func _throw_aim(point: Vector3) -> Vector2:
	var to := point - p.head.global_position
	var flat_d := maxf(0.5, Vector2(to.x, to.z).length() - 0.5)
	var v := float(Data.GRENADE.throw_speed)
	var g := Projectile.GRENADE_GRAVITY
	# Lowest pitch whose arc reaches the point's height at its distance; out of reach, the
	# longest throw (best range sits near 45 degrees).
	var pitch := 0.75
	var a := -0.6
	while a < 0.75:
		var t := flat_d / (v * cos(a))
		if (v * sin(a) + 3.0) * t - 0.5 * g * t * t >= to.y:
			pitch = a
			break
		a += 0.01
	return Vector2(atan2(-to.x, -to.z), pitch)


func _turn_toward(point: Vector3, delta: float) -> void:
	var to := point - p.head.global_position
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var step := deg_to_rad(TURN_SPEED_DEG[difficulty]) * delta
	p.yaw = p.yaw + clampf(wrapf(want_yaw - p.yaw, -PI, PI), -step, step)
	p.pitch = clampf(p.pitch + clampf(want_pitch - p.pitch, -step, step), -Player.MAX_PITCH, Player.MAX_PITCH)


# ---------------------------------------------------------------- roaming

func _roam(delta: float) -> void:
	if p.world.tactical != null:
		_roam_tactical(delta)
		return
	var now := World.now()
	# A pickup we were heading for got taken: pick something else instead of visiting the empty pad.
	if _goal_pickup != null and not _goal_pickup.active:
		_goal_pickup = null
		_has_goal = false
	# Search where the target was last seen, once per sighting: after reaching it (or the nearest
	# reachable point) carry on roaming instead of re-pathing to the same spot every frame. A bot
	# holding an area (King of the Block's zone) only searches inside it.
	var hold := p.world.rules.bot_hold_area(p)
	var search := now - _last_seen_time < MEMORY_TIME and _last_seen_pos.distance_to(_chase_pos) > 3.0
	if search and not hold.is_empty() and _flat_dist(_last_seen_pos, hold[0]) > float(hold[1]):
		search = false
	if search:
		_chase_pos = _last_seen_pos
		_goal_pickup = null
		_set_goal(_last_seen_pos)
	else:
		# The mode can send the bot somewhere (Infected hunt the nearest survivor); a goal that
		# moved more than a few metres is re-routed.
		var push: Variant = p.world.rules.bot_roam_goal(p)
		# A Radar Sweep (Streaks) shows where the nearest enemy is: hunt them.
		if push == null:
			push = p.world.streaks.bot_radar_goal(p)
		if push != null:
			if not _has_goal or _goal.distance_to(push) > 4.0:
				_goal_pickup = null
				_set_goal(push)
		elif not _has_goal:
			_set_goal(_pick_roam_goal())
	_go_toward(_goal, delta)
	p.in_sprint = difficulty > 0 and now - _last_seen_time > 1.5
	_maybe_slide(delta)
	var hooking := _maybe_grapple(delta, NO_POS)
	# Route finished (or there is none): the goal is reached, or as close as the navmesh gets.
	# A goal still being hooked toward is kept until the grapple is done.
	if _path_index >= _path.size() and not hooking and not p.grappling:
		_has_goal = false


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _pick_roam_goal() -> Vector3:
	if p.world.tactical != null:
		return p.world.tactical.bot_order(p).pos
	_goal_pickup = null
	var info := p.world.map_info
	var needs_health := p.health < p.max_health() * 0.6
	# An empty primary slot (Infected, knife only) needs no ammo.
	var needs_ammo := false
	if not p.slots[0].is_empty():
		var cur: Vector2i = p.ammo[p.slots[0]]
		needs_ammo = cur.x + cur.y < p.mag_size(p.slots[0])
	if needs_health or needs_ammo:
		var best: PickupNode = null
		var best_d := INF
		for i in p.world.pickup_nodes.size():
			var node := p.world.pickup_nodes[i]
			if not node.active:
				continue
			if (needs_health and node.kind == "health") or (needs_ammo and node.kind == "ammo"):
				var d := p.global_position.distance_to(node.position)
				if d < best_d:
					best_d = d
					best = node
		if best != null:
			_goal_pickup = best
			return best.position
	if aggression > 1.1 and randf() < 0.6:
		var prey: Array = p.world.entities.values().filter(func(o: Player) -> bool: return o.alive and p.world.is_enemy(p, o))
		if not prey.is_empty():
			return (prey.pick_random() as Player).global_position
	if randf() < 0.35 / aggression:
		var pads := p.world.pickup_nodes.filter(func(n: PickupNode) -> bool: return n.active)
		if not pads.is_empty():
			_goal_pickup = pads.pick_random()
			return _goal_pickup.position
	return info.spawns.pick_random()


## Tactical: the squad's orders (Tactical.bot_order) instead of free roaming. A target that just
## ducked out of sight close by is still chased; otherwise the bot walks to its spot in the squad
## formation (sprinting only when told to rush or loot) and, once there, holds: crouched while
## its squad holds a position, watching where the squad goes next.
func _roam_tactical(delta: float) -> void:
	var now := World.now()
	if now - _last_seen_time < MEMORY_TIME and _last_seen_pos.distance_to(p.global_position) < 18.0 \
			and _last_seen_pos.distance_to(_chase_pos) > 3.0:
		_chase_pos = _last_seen_pos
		_chasing = true
	if _chasing:
		_go_toward(_chase_pos, delta)
		if _path_index >= _path.size():
			_chasing = false
		return
	_order_timer -= delta
	if _order_timer <= 0.0 or _order.is_empty():
		_order_timer = ORDER_INTERVAL
		_order = p.world.tactical.bot_order(p)
	var order := _order
	var pos: Vector3 = order.pos
	var off := pos - p.global_position
	if Vector2(off.x, off.z).length() < 1.2 and absf(off.y) < 2.0:
		p.in_crouch = bool(order.hold)
		_turn_toward(order.look, delta * 0.5)
		return
	_go_toward(pos, delta)
	p.in_sprint = bool(order.sprint) and difficulty > 0


## World.now() when the current target was last seen (Tactical squads track contact).
func last_seen_time() -> float:
	return _last_seen_time


## A teammate pinged an enemy at `pos` (Pings, server): a bot with no target and the ping within
## Pings.BOT_HEED_RANGE goes and looks there, like a fresh sighting.
func heed_ping(pos: Vector3) -> void:
	if target != null:
		return
	if p.global_position.distance_to(pos) > Pings.BOT_HEED_RANGE:
		return
	_last_seen_pos = pos
	_last_seen_time = World.now()
	_has_goal = false


func _set_goal(point: Vector3) -> void:
	_goal = point
	_has_goal = true
	_repath_timer = 0.0


func _go_toward(point: Vector3, delta: float) -> void:
	_repath_timer -= delta
	if _goal.distance_to(point) > 2.0:
		_goal_pickup = null
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
	# Without a route (unreachable goal, off the navmesh) stay put rather than walk straight at the
	# point, and once the route is used up stop at its end: a goal across a gap (another Sky
	# Island, a player mid-jump) leaves the path ending at the ledge, and pressing on falls off.
	if _path.is_empty():
		_repath_timer = minf(_repath_timer, 0.3)
		return
	var dest := _path[mini(_path_index, _path.size() - 1)]
	var dir := Vector3(dest.x - p.global_position.x, 0.0, dest.z - p.global_position.z)
	if dir.length() < 0.3:
		return
	_set_move_world(dir.normalized())
	if (target == null or not _target_visible) and _grapple_aim == NO_POS:
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


# ---------------------------------------------------------------- movement mechanics

## One prone toggle press (lie down / get up), at most every 0.6 s.
func _press_prone() -> void:
	if _prone_cooldown > 0.0:
		return
	p.in_prone = true
	_prone_cooldown = 0.6


## Lies down to snipe at long range; gets up when the target closes in or lands hits.
func _decide_prone(delta: float, dist: float, wid: String) -> void:
	var hurt := World.now() - p.last_hurt_time < 1.2
	if p.prone:
		if dist < PRONE_UP_DIST or (hurt and p.health < 50.0):
			_press_prone()
		return
	_prone_timer -= delta
	if _prone_timer > 0.0:
		return
	_prone_timer = randf_range(1.5, 3.0)
	var long_gun := not Data.is_melee(wid) and wid not in ["shotgun", "sawed_off", "drum_shotgun", "rocket"]
	if long_gun and dist > PRONE_MIN_DIST and not hurt and p.is_on_floor() and not p.grappling \
			and randf() < PRONE_CHANCE[difficulty]:
		_press_prone()


## Peeks (leans) out to one side for a moment during a ranged fight, then straightens up.
func _decide_peek(delta: float, dist: float) -> void:
	_peek_timer -= delta
	if p.prone or p.sliding or p.grappling:
		_peek_side = 0
		return
	if _peek_timer > 0.0:
		return
	if _peek_side != 0:
		_peek_side = 0
		_peek_timer = randf_range(1.5, 4.0)
	elif dist > 8.0 and randf() < PEEK_CHANCE[difficulty]:
		_peek_side = 1 if randf() < 0.5 else -1
		_peek_timer = randf_range(0.8, 1.8)
	else:
		_peek_timer = randf_range(1.0, 2.5)


## While sprinting with a clear straight run ahead, sometimes crouches into a slide (holding
## crouch for the slide's length).
func _maybe_slide(delta: float) -> void:
	# Tactical has no sliding (Player ignores it there).
	if p.world.tactical != null:
		return
	if _slide_hold > 0.0:
		_slide_hold -= delta
		p.in_crouch = true
		return
	_slide_check -= delta
	if _slide_check > 0.0:
		return
	_slide_check = randf_range(0.8, 1.6)
	if not p.sprinting or not p.is_on_floor() or randf() >= SLIDE_CHANCE[difficulty]:
		return
	var run := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if run.length() < Player.SLIDE_MIN_ENTRY * p.speed_scale:
		return
	run = run.normalized()
	# Floor under the whole slide and nothing in the way at knee height.
	for d: float in [2.0, 4.0, 6.0]:
		if not _ground_ahead(run * d):
			return
	var knee := p.global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(knee, knee + run * 6.0, Player.MASK_WORLD)
	if not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return
	_slide_hold = randf_range(0.5, 0.9)
	p.in_crouch = true


## Grapple use. With `toward` = NO_POS it looks at the current route: a ledge on it at least
## GRAPPLE_MIN_RISE up, or the goal when the route stops short of it (a gap); otherwise it hooks
## toward `toward`. Once a point is chosen the bot turns onto it and fires when lined up.
## Returns true while it is turning onto a grapple point (the caller should not steer the view).
func _maybe_grapple(delta: float, toward: Vector3) -> bool:
	if p.world.tactical != null:
		return false
	if p.grappling:
		_grapple_aim = NO_POS
		return false
	if _grapple_aim != NO_POS:
		_grapple_aim_left -= delta
		_turn_toward(_grapple_aim, delta * 1.5)
		var aim_dir := -Basis.from_euler(Vector3(p.pitch, p.yaw, 0.0)).z
		var need := (_grapple_aim - p.head.global_position).normalized()
		if aim_dir.angle_to(need) < deg_to_rad(2.5):
			p.in_grapple = true
			_grapple_aim = NO_POS
			_grapple_timer = randf_range(3.0, 6.0)
		elif _grapple_aim_left <= 0.0:
			_grapple_aim = NO_POS
		return true
	_grapple_timer -= delta
	if _grapple_timer > 0.0 or p.grapple_cooldown > 0.0 or p.prone or not p.is_on_floor():
		return false
	_grapple_timer = randf_range(1.0, 2.0)
	if randf() >= GRAPPLE_CHANCE[difficulty]:
		return false
	var point := _hook_point(toward) if toward != NO_POS else _route_hook_point()
	if point == NO_POS:
		return false
	_grapple_aim = point
	_grapple_aim_left = GRAPPLE_AIM_TIME
	return true


func _route_hook_point() -> Vector3:
	if _path.is_empty():
		return NO_POS
	# The route ends short of the goal: hook across the gap to the goal itself.
	if _has_goal and _goal.distance_to(_path[_path.size() - 1]) > 4.0:
		var across := _hook_point(_goal)
		if across != NO_POS:
			return across
	var y := p.global_position.y
	for i in range(_path_index, mini(_path_index + 8, _path.size())):
		# A jump pad on the way takes the bot up; no hook needed past it.
		if JumpPad.find(p.world.map_info.jump_pads, _path[i]) != null:
			break
		if _path[i].y - y >= GRAPPLE_MIN_RISE:
			return _hook_point(_path[i])
	return NO_POS


## Where the hook would catch when fired at `point` (a little above it): the world surface hit
## near it, or NO_POS if it is out of range, the line is blocked well short of it, or the catch
## is more than a metre below the bot (no use reeling downhill).
func _hook_point(point: Vector3) -> Vector3:
	var eye := p.head.global_position
	var at := point + Vector3.UP * 0.4
	var d := eye.distance_to(at)
	if d < 6.0 or d > Player.GRAPPLE_RANGE - 2.0:
		return NO_POS
	var dir := (at - eye) / d
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * (d + 1.5), Player.MASK_WORLD, p.exclude_rids())
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return NO_POS
	var pos: Vector3 = hit.position
	if pos.distance_to(at) > 2.0 or pos.y < p.global_position.y - 1.0:
		return NO_POS
	return pos
