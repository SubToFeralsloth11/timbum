class_name World
extends Node3D
## The match scene. Builds the map, owns every entity, and carries all gameplay RPCs.
## Server (host) is authoritative for health, kills, score, respawns, pickups, bots, projectiles
## and the clock. Clients simulate their own movement and hit detection and report results.
##
## Naming: `_s_*` methods are server -> peers events (also called locally on the server through
## `_broadcast`). `_c_*` methods are client -> server requests. `_server_*` is server-only logic.

const SNAPSHOT_INTERVAL := 0.05
const CLOCK_INTERVAL := 1.0
const REGEN_INTERVAL := 0.25
## Seconds every camera watches the winner perform their win emote before the results screen.
const WIN_SHOW := 4.0
## Results screen length, counted from the end of the match (so it includes WIN_SHOW).
const RESULTS_TIME := 12.0 + WIN_SHOW
const SPAWN_PROTECTION := 2.0
const REGEN_DELAY := 5.0
const REGEN_RATE := 12.0
const PICKUP_RESPAWN := 20.0
const PICKUP_RADIUS := 1.3
const HEALTH_PICKUP := 50.0
const MULTI_KILL_WINDOW := 3.5
const MAX_CHAT_LENGTH := 100
## Mutator id -> the gun it hands everyone as their primary (`_apply_loadout_mutator`).
const LOADOUT_MUTATORS := {"rocket_party": "rocket", "snipers": "sniper"}

var map_info: MapInfo
## entity id -> Player. Humans use their peer id; bots use negative ids.
var entities := {}
var local_player: Player
var hud: Hud
var fx: Fx
## projectile id -> Projectile
var projectiles := {}
var pickup_nodes: Array[PickupNode] = []
var match_over := false
var time_left := 0.0
## entity id -> {name, kills, deaths, headshots, streak, best_streak, bot}
var scores := {}
var results: Array = []
## The next match the results screen announces: {map, mutator, time_of_day}.
var next_up: Dictionary = {}
## Active smoke clouds on every peer: [centre, radius, World.now() when it clears].
var smokes: Array = []
## The mode's rules (MatchMode subclass, child of World; plain Deathmatch for "ffa").
var rules: MatchMode
## Tactical's controller when the mode is Tactical (the same node as `rules`), else null.
var tactical: Tactical
## Killstreak rewards (child "Streaks"; idle when `Net.config.streaks` is off).
var streaks: Streaks
## Quick pings (child "Pings"; idle outside team modes).
var pings: Pings
## Kill cam replay (records on every peer; plays when another player kills the local player).
var killcam: KillCam

var _entities_root: Node3D
var _shake := 0.0
var _my_multi := 0
var _my_last_kill := -100.0
var _my_streak := 0
## Client: attacker id -> [hits, damage] dealt to the local player this life, for the death screen.
var _my_damage_taken := {}
## The local player's per-weapon numbers this match (see Profile.WEAPON_STAT_KEYS for what a shot
## and a hit are): id -> {kills, headshots, shots, hits, damage}. Counted on this peer: shots and
## hitscan/knife hits when the shot is fired, rocket hits, damage, kills and headshots from the
## server's hit confirms and kill events. Added to the profile at the match end.
var my_weapon_stats := {}
## Frame of the last rocket hit counted, so one blast hitting several players is one hit.
var _my_rocket_hit_frame := -1
## The local player's movement/range kill facts this match (MatchFacts), with the scoreboard row
## and my_weapon_stats the result challenges read. Counted on this peer.
var my_facts := MatchFacts.new()
## Keys of the feats (Profile.preview_feats) already toasted this match.
var _feats_toasted := {}
## Profile.record_match's answer for this match (rewards, accuracy, most-used weapon); {} before.
var match_rewards := {}
## End of match: the camera circling the winner while they emote (null otherwise).
var _win_cam: Camera3D
var _win_target: Player
var _win_t := 0.0

# Server-only state.
var _ready_peers := {}
## Peers who voted to skip the rest of the results screen.
var _skip_votes := {}
var _advancing := false
## World.now() bookkeeping: total milliseconds spent frozen, and when the current freeze began
## (-1 when running). Static because now() is static; frozen time only ever accumulates.
static var _frozen_total_ms := 0
static var _frozen_at_ms := -1
## When the results screen ends and the next match loads (World.now() seconds).
var _results_until := 0.0
var _respawn_at := {}
## Shooter key ("<entity>" for guns, "<entity>:knife") -> [debt seconds, time]; see _take_fire_token.
var _fire_tokens := {}
## Entity id -> time of last server respawn; client state is ignored briefly afterwards so stale
## pre-respawn positions can't drag the player back (or below kill_y again).
var _respawned_at := {}
var _spawned_at := {}
var _last_damage := {}
var _grenades := {}
var _tacticals := {}
var _pickup_ready_at: Array[float] = []
var _next_bot_id := -1
var _next_projectile_id := 1
var _snapshot_timer := 0.0
var _clock_timer := 0.0
var _regen_timer := 0.0
var _bot_names_used := {}
## Client: resend _c_ready until the server answers, in case it arrived while the host was
## still swapping scenes.
var _welcomed := false
var _ready_retry := 1.0


func _ready() -> void:
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	var map_root := Node3D.new()
	map_root.name = "Map"
	add_child(map_root)
	map_info = MapBuilder.build(Net.current_map, map_root, int(Profile.get_setting("quality")))
	_apply_time_of_day(map_root, str(Net.config.time_of_day))
	var post := PostProcess.new()
	post.name = "PostProcess"
	add_child(post)
	post.setup(str(Net.config.time_of_day))
	_entities_root = Node3D.new()
	_entities_root.name = "Entities"
	add_child(_entities_root)
	for pick: Dictionary in map_info.pickups:
		# Tactical weapon spots are Tactical's (WeaponPickup), not timed pickups.
		if pick.kind == "weapon":
			continue
		var node := PickupNode.new()
		node.setup(str(pick.kind))
		node.position = pick.pos
		add_child(node)
		pickup_nodes.append(node)
		_pickup_ready_at.append(0.0)
	# The rules exist before the Hud builds (its scoreboard asks them for columns); they join the
	# tree after it.
	rules = MatchMode.create(self)
	tactical = rules as Tactical
	hud = Hud.new()
	hud.name = "Hud"
	hud.setup(self)
	add_child(hud)
	add_child(rules)
	streaks = Streaks.new()
	streaks.world = self
	add_child(streaks)
	pings = Pings.new()
	pings.world = self
	add_child(pings)
	killcam = KillCam.new()
	killcam.name = "KillCam"
	killcam.world = self
	add_child(killcam)
	time_left = float(Net.config.time_limit)
	# Today's challenges exist before the first kill (live toasts compare against them).
	Profile.refresh_challenges()
	Sfx.play_music(&"match")
	Sfx.play(&"match_start")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		var me := multiplayer.get_unique_id()
		_server_add_entity(me, Net.players[me], false, rules.server_team_for(false))
		_balance_bots()
	else:
		_c_ready.rpc_id(1)


func _exit_tree() -> void:
	set_frozen(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Match clock in seconds. Stops while an offline match is frozen (see set_frozen), so
## respawns, pickups, smoke and spawn protection resume where they left off.
static func now() -> float:
	var t := _frozen_at_ms if _frozen_at_ms >= 0 else Time.get_ticks_msec()
	return (t - _frozen_total_ms) * 0.001


## Freezes the whole match (scene tree, physics and World.now()). Only offline matches may
## freeze: a networked host must keep simulating for its clients.
func set_frozen(on: bool) -> void:
	if on and not Net.offline:
		return
	if on == (_frozen_at_ms >= 0):
		return
	if on:
		_frozen_at_ms = Time.get_ticks_msec()
	else:
		_frozen_total_ms += Time.get_ticks_msec() - _frozen_at_ms
		_frozen_at_ms = -1
	get_tree().paused = on


func is_frozen() -> bool:
	return _frozen_at_ms >= 0


func my_id() -> int:
	return multiplayer.get_unique_id()


func input_blocked() -> bool:
	return hud.is_blocking() or match_over


## Nobody can shoot, knife or throw yet (Tactical's planning phase).
func attacks_blocked() -> bool:
	return rules.attacks_blocked()


## Whether `a` may fight `b`: anyone else, except a teammate in team modes.
func is_enemy(a: Player, b: Player) -> bool:
	return a != b and not Teams.same(a, b)


## Peers that have loaded this world (server), for modules sending their own RPCs.
func ready_peer_ids() -> Array:
	return _ready_peers.keys()


func display_name(entity_id: int) -> String:
	if scores.has(entity_id):
		return str(scores[entity_id].name)
	if entities.has(entity_id):
		return str(entities[entity_id].info.name)
	return "?"


## display_name with the player's prestige badge in front (kill feed).
func tagged_name(entity_id: int) -> String:
	var rank := 0
	if scores.has(entity_id):
		rank = int(scores[entity_id].get("prestige", 0))
	elif entities.has(entity_id):
		rank = int(entities[entity_id].info.get("prestige", 0))
	return Data.badged_name(display_name(entity_id), rank)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		if not match_over and rules.clock_running():
			time_left = maxf(0.0, time_left - delta)
		if not _welcomed:
			_ready_retry -= delta
			if _ready_retry <= 0.0:
				_ready_retry = 1.0
				_c_ready.rpc_id(1)
	if _win_cam != null:
		_update_win_cam(delta)
	if _shake > 0.0 and local_player != null and local_player.camera != null:
		_shake = move_toward(_shake, 0.0, delta * 2.5)
		local_player.camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.08
		local_player.camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.08
	if not smokes.is_empty():
		var t := now()
		smokes = smokes.filter(func(s: Array) -> bool: return float(s[2]) > t)
	if local_player != null and not match_over:
		my_facts.track(local_player, now())


func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.5)


## Sends an RPC to every peer that has loaded this world, then runs it here too.
func _broadcast(method: StringName, args: Array) -> void:
	for pid: int in _ready_peers:
		callv(&"rpc_id", [pid, method] + args)
	callv(method, args)


# ================================================================ server: frame

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var t := now()
	if not match_over and rules.clock_running():
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_server_end_match()
	_clock_timer -= delta
	if _clock_timer <= 0.0:
		_clock_timer = CLOCK_INTERVAL
		for pid: int in _ready_peers:
			_s_clock.rpc_id(pid, time_left)
	_snapshot_timer -= delta
	if _snapshot_timer <= 0.0:
		_snapshot_timer = SNAPSHOT_INTERVAL
		_server_send_snapshots()
	for eid: int in _respawn_at.keys():
		if t >= _respawn_at[eid]:
			_respawn_at.erase(eid)
			if entities.has(eid) and not match_over:
				_server_respawn(eid)
	if match_over:
		return
	for eid: int in entities:
		var p: Player = entities[eid]
		if p.alive and p.global_position.y < map_info.kill_y:
			_server_force_kill(p)
	_server_pickups(t)
	_regen_timer -= delta
	if _regen_timer <= 0.0:
		_regen_timer = REGEN_INTERVAL
		for eid: int in entities:
			var p: Player = entities[eid]
			if p.alive and p.health < p.max_health() and t - float(_last_damage.get(eid, -100.0)) > REGEN_DELAY:
				_broadcast(&"_s_health", [eid, minf(p.max_health(), p.health + REGEN_RATE * REGEN_INTERVAL)])


func _server_send_snapshots() -> void:
	if _ready_peers.is_empty():
		return
	var snap := []
	for eid: int in entities:
		var p: Player = entities[eid]
		snap.append([eid, p.global_position, p.yaw, p.pitch, p.net_flags()])
	for pid: int in _ready_peers:
		_s_snapshot.rpc_id(pid, snap)


# ================================================================ server: entities

## `team` (team modes) puts the player on that side; the mode's rules shape the info and spawn.
func _server_add_entity(eid: int, info: Dictionary, is_bot: bool, team := -1, is_alive := true) -> void:
	var spawn := rules.spawn_point(eid, team)
	info = _apply_loadout_mutator(rules.prepare_info(info, team))
	scores[eid] = {"name": str(info.name), "level": int(info.get("level", 1)), "prestige": int(info.get("prestige", 0)),
		"kills": 0, "deaths": 0, "headshots": 0, "streak": 0, "best_streak": 0, "bot": is_bot}
	_refill_equipment(eid, info)
	_broadcast(&"_s_spawn_entity", [eid, info, is_bot, spawn[0], spawn[1], float(info.get("max_hp", Data.MAX_HEALTH)), is_alive])
	# Tactical teams wait out the planning phase behind barriers instead.
	if rules.spawn_protection():
		_server_protect(eid)
	_broadcast(&"_s_scores", [scores])


## Grenades and tacticals for a new life; none for a knife-only player (Infected) or in Gun Game.
func _refill_equipment(eid: int, info: Dictionary) -> void:
	var armed := Player.carries_grenades(info)
	_grenades[eid] = int(Data.GRENADE.per_life) if armed else 0
	_tacticals[eid] = Data.TACTICAL_PER_LIFE if armed else 0


## A bot joins `team` (-1 in free-for-all); returns its entity id.
func server_add_bot(team: int) -> int:
	var eid := _next_bot_id
	_next_bot_id -= 1
	_server_add_entity(eid, _make_bot_info(), true, team)
	return eid


## A human (peer `pid`) joins `team`, alive or (joining too late in Tactical) as a spectator.
func server_add_human(pid: int, team: int, is_alive: bool) -> void:
	_server_add_entity(pid, Net.players[pid], false, team, is_alive)


func server_remove_bot(eid: int) -> void:
	_bot_names_used.erase(entities[eid].info.name)
	_server_remove_entity(eid)


func server_remove_entity(eid: int) -> void:
	_server_remove_entity(eid)


## Moves `eid` to `pos` (a Tactical takeover); like a respawn, stale client state is ignored briefly.
func server_place(eid: int, pos: Vector3, p_yaw: float) -> void:
	_respawned_at[eid] = now()
	_broadcast(&"_s_respawn", [eid, pos, p_yaw])


func server_set_health(eid: int, hp: float) -> void:
	_broadcast(&"_s_health", [eid, hp])


func server_end_match() -> void:
	_server_end_match()


func _server_remove_entity(eid: int) -> void:
	scores.erase(eid)
	_respawn_at.erase(eid)
	_spawned_at.erase(eid)
	_grenades.erase(eid)
	_tacticals.erase(eid)
	_last_damage.erase(eid)
	_respawned_at.erase(eid)
	_broadcast(&"_s_despawn", [eid])
	_broadcast(&"_s_scores", [scores])


func _balance_bots() -> void:
	if not multiplayer.is_server() or match_over:
		return
	rules.server_balance()


## The standard bot balance (MatchMode.server_balance): keeps bots + humans at `bots_fill`.
## When a bot has to leave, it comes from the mode's `bot_drop_team()` (team modes: the bigger
## team) and is the one whose exit disturbs the match least: dead bots first, then bots out of
## combat, then the lowest scorer. New bots join the team the mode picks.
func server_balance_bots() -> void:
	var want := maxi(0, int(Net.config.bots_fill) - Net.players.size())
	var bots: Array[int] = []
	for eid: int in entities:
		if eid < 0:
			bots.append(eid)
	while bots.size() > want:
		var team := rules.bot_drop_team()
		var pool := bots.filter(func(e: int) -> bool: return Teams.of(entities[e]) == team)
		if team < 0 or pool.is_empty():
			pool = bots.duplicate()
		pool.sort_custom(func(a: int, b: int) -> bool: return _bot_leave_cost(a) < _bot_leave_cost(b))
		var eid: int = pool[0]
		bots.erase(eid)
		server_remove_bot(eid)
	while bots.size() < want:
		bots.append(server_add_bot(rules.server_team_for(true)))


## Lower = better candidate to remove. Dead bots rank first; alive bots hurt within REGEN_DELAY
## (someone is fighting them, so removing them would steal a kill) rank last; ties go to the
## fewest kills.
func _bot_leave_cost(eid: int) -> int:
	var cost := int(scores.get(eid, {}).get("kills", 0))
	if entities[eid].alive:
		cost += 10000
		if now() - float(_last_damage.get(eid, -100.0)) < REGEN_DELAY:
			cost += 1000
	return cost


func _make_bot_info() -> Dictionary:
	var names := Data.BOT_NAMES.filter(func(n: String) -> bool: return not _bot_names_used.has(n))
	var bot_name: String = names.pick_random() if not names.is_empty() else ""
	# More bots than names (Tactical's 49): numbered copies, still unique.
	var n := 2
	while bot_name.is_empty() or _bot_names_used.has(bot_name):
		bot_name = "%s %d" % [Data.BOT_NAMES.pick_random(), n]
		n += 1
	_bot_names_used[bot_name] = true
	var primaries := Data.weapon_ids_for_slot("primary")
	var secondaries := Data.weapon_ids_for_slot("secondary")
	return {
		"name": bot_name,
		"outfit": Data.OUTFITS.keys().pick_random(),
		"hat": Data.HATS.keys().pick_random(),
		"skin": Data.SKINS.keys().pick_random(),
		"primary": primaries.pick_random(),
		"secondary": secondaries.pick_random(),
		"tactical": Data.TACTICALS.keys().pick_random(),
		"charm": Data.CHARMS.keys().pick_random(),
		"emote": Data.EMOTES.keys().pick_random(),
		"draw": "standard",
		"mods": {},
		"level": randi_range(1, 30),
	}


## Picks a spawn far from living enemies (players not on `team`; everyone else in free-for-all),
## strongly avoiding any spawn an enemy can see.
func pick_spawn(for_id: int, team := -1) -> Array:
	var space := get_world_3d().direct_space_state
	var ranked: Array = []
	for s: Vector3 in map_info.spawns:
		var nearest := 1e9
		var seen := false
		for eid: int in entities:
			var p: Player = entities[eid]
			if eid == for_id or not p.alive or (team >= 0 and Teams.of(p) == team):
				continue
			var d := s.distance_squared_to(p.global_position)
			nearest = minf(nearest, d)
			if not seen and d < 70.0 * 70.0:
				var q := PhysicsRayQueryParameters3D.create(s + Vector3.UP * 1.6, p.global_position + Vector3.UP * 1.6, Player.MASK_WORLD)
				seen = space.intersect_ray(q).is_empty()
		# Visible spawns rank below every hidden one.
		ranked.append([nearest - (1e8 if seen else 0.0), s, seen, nearest])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	# Vary among the best three, but never trade the best spawn for one an enemy can see (when the
	# best is hidden) or one within 5 m of a living player.
	var pool := 1
	while pool < mini(3, ranked.size()) and ranked[pool][2] == ranked[0][2] and float(ranked[pool][3]) >= 25.0:
		pool += 1
	var pick: Vector3 = ranked[randi() % pool][1]
	var to_center := map_info.bounds.get_center() - pick
	return [pick, atan2(-to_center.x, -to_center.z)]


func _server_respawn(eid: int) -> void:
	var p: Player = entities[eid]
	var spawn := rules.spawn_point(eid, Teams.of(p))
	_respawned_at[eid] = now()
	_refill_equipment(eid, p.info)
	_broadcast(&"_s_respawn", [eid, spawn[0], spawn[1]])
	if rules.spawn_protection():
		_server_protect(eid)


## Starts `eid`'s SPAWN_PROTECTION window and shows it on every peer.
func _server_protect(eid: int) -> void:
	_spawned_at[eid] = now()
	_broadcast(&"_s_protection", [eid, SPAWN_PROTECTION])


## Firing (a shot, rocket or grenade) ends the shooter's own spawn protection early.
func _server_unprotect(eid: int) -> void:
	if _protection_left(eid) > 0.0:
		_broadcast(&"_s_protection", [eid, 0.0])
	_spawned_at[eid] = -100.0


func _protection_left(eid: int) -> float:
	return maxf(0.0, SPAWN_PROTECTION - (now() - float(_spawned_at.get(eid, -100.0))))


func _on_peer_disconnected(pid: int) -> void:
	_ready_peers.erase(pid)
	if entities.has(pid):
		_server_chat_system("%s left the game" % display_name(pid))
		rules.server_human_left(pid)
	_balance_bots.call_deferred()
	# A leaver lowers the majority needed on the results screen (Net already dropped them).
	_skip_votes.erase(pid)
	if match_over and not _advancing:
		_server_tally_skip()


# ================================================================ server: combat

func _server_shot(shooter_id: int, wid: String, ends: PackedVector3Array, normals: PackedVector3Array, hit_list: Array) -> void:
	var shooter: Player = entities.get(shooter_id)
	if shooter == null or not shooter.alive or match_over or not Data.WEAPONS.has(wid) or attacks_blocked():
		return
	if not rules.weapon_allowed(shooter, wid):
		return
	# Projectile weapons only fire through _server_projectile; a hitscan report for one is forged.
	if Data.WEAPONS[wid].get("projectile", false):
		return
	if ends.size() > 16 or normals.size() != ends.size() or hit_list.size() > 16:
		return
	var w: Dictionary = Data.WEAPONS[wid]
	var rate_ok := _take_fire_token(shooter_id, wid)
	for pid: int in _ready_peers:
		if pid != shooter_id:
			_s_shot_fx.rpc_id(pid, shooter_id, wid, ends, normals)
	if shooter.mode == Player.Mode.REMOTE:
		_s_shot_fx(shooter_id, wid, ends, normals)
	if not rate_ok:
		return
	_server_unprotect(shooter_id)
	# One shot can never deal more to a single target than every pellet landing as a headshot.
	var max_dmg := float(w.damage) * float(w.head_mult) * float(w.pellets) + 0.01
	var per_target := {}
	var head_hit := {}
	for h: Variant in hit_list:
		if typeof(h) != TYPE_ARRAY or (h as Array).size() != 3:
			continue
		var tid := int(h[0])
		per_target[tid] = minf(float(per_target.get(tid, 0.0)) + clampf(float(h[1]), 0.0, max_dmg), max_dmg)
		head_hit[tid] = bool(head_hit.get(tid, false)) or bool(h[2])
	for tid: int in per_target:
		var target: Player = entities.get(tid)
		if target == null or not target.alive or tid == shooter_id:
			continue
		var dist := shooter.global_position.distance_to(target.global_position)
		if wid == "knife" and dist > 4.5:
			continue
		_server_damage(target, per_target[tid], shooter_id, wid, head_hit[tid], shooter.global_position)


## Fire-rate check, mirroring the client's single `fire_cooldown`: every shot puts its weapon's
## refire interval (60 / rpm) on a per-shooter debt that drains in real time, and a shot is
## accepted while the debt is at most two of its own intervals. That allows a burst of 3 bunched
## shots after lag, but alternating weapons can't add their rates together. All guns share one
## budget; the knife has its own, like the client's quick melee.
func _take_fire_token(shooter_id: int, wid: String) -> bool:
	const BURST := 3.0
	var key := "%d:knife" % shooter_id if wid == "knife" else str(shooter_id)
	var interval := 60.0 / float(Data.WEAPONS[wid].rpm)
	var t := now()
	var bucket: Array = _fire_tokens.get(key, [0.0, t])
	var debt := maxf(0.0, float(bucket[0]) - (t - float(bucket[1])))
	if debt > (BURST - 1.0) * interval + 0.0001:
		_fire_tokens[key] = [debt, t]
		return false
	_fire_tokens[key] = [debt + interval, t]
	return true


func _server_damage(target: Player, amount: float, attacker_id: int, wid: String, head: bool, from_pos: Vector3) -> void:
	if match_over or not target.alive or amount <= 0.0:
		return
	if attacker_id != target.id and _protection_left(target.id) > 0.0:
		return
	# Team modes: no friendly fire (your own grenade still hurts you).
	if attacker_id != target.id and Teams.same(entities.get(attacker_id), target):
		return
	if Net.config.mutator == "glass_cannon":
		amount *= 2.0
	# An Overshield (Streaks) soaks up damage first; health takes the rest.
	var absorbed := minf(target.shield, amount)
	var shield_left := target.shield - absorbed
	var hp := maxf(0.0, target.health - (amount - absorbed))
	var dealt := absorbed + target.health - hp
	_last_damage[target.id] = now()
	_broadcast(&"_s_damaged", [target.id, hp, attacker_id, from_pos, shield_left])
	var killed := hp <= 0.0
	if attacker_id != target.id:
		var label_pos := target.global_position + Vector3.UP * 2.0
		if attacker_id == my_id():
			_s_hit_confirm(head, killed, dealt, label_pos, wid)
		elif _ready_peers.has(attacker_id):
			_s_hit_confirm.rpc_id(attacker_id, head, killed, dealt, label_pos, wid)
	if killed:
		_server_kill(target.id, attacker_id, wid, head)


func _server_force_kill(p: Player) -> void:
	_broadcast(&"_s_damaged", [p.id, 0.0, p.id, p.global_position, 0.0])
	_server_kill(p.id, p.id, "fall", false)


func _server_kill(victim_id: int, killer_id: int, wid: String, head: bool) -> void:
	# The death screen's numbers come from here, before Vampire refills the killer, so every peer
	# shows the server's values rather than its own interpolated positions.
	var killer: Player = entities.get(killer_id) if killer_id != victim_id else null
	var victim: Player = entities.get(victim_id)
	var killer_hp := killer.health if killer != null and killer.alive else -1.0
	var killer_dist := killer.global_position.distance_to(victim.global_position) if killer != null and victim != null else -1.0
	if scores.has(victim_id):
		var v: Dictionary = scores[victim_id]
		v.deaths += 1
		v.streak = 0
		if killer_id == victim_id:
			v.kills = maxi(0, int(v.kills) - 1)
	if killer_id != victim_id and scores.has(killer_id):
		var k: Dictionary = scores[killer_id]
		k.kills += 1
		# A kill by a killstreak reward counts as a kill but doesn't extend the streak.
		if wid != Streaks.WEAPON:
			k.streak += 1
			k.best_streak = maxi(int(k.best_streak), int(k.streak))
		if head:
			k.headshots += 1
		if Net.config.mutator == "vampire" and entities.has(killer_id) and entities[killer_id].alive:
			_broadcast(&"_s_health", [killer_id, entities[killer_id].max_health()])
	if rules.respawn_delay() >= 0.0:
		_respawn_at[victim_id] = now() + rules.respawn_delay()
	_broadcast(&"_s_killed", [victim_id, killer_id, wid, head, killer_hp, killer_dist])
	_broadcast(&"_s_scores", [scores])
	rules.server_on_kill(victim_id, killer_id, wid)
	streaks.server_on_kill(victim_id, killer_id, wid)


func _server_projectile(owner_id: int, kind: String, origin: Vector3, vel: Vector3) -> void:
	var shooter: Player = entities.get(owner_id)
	if shooter == null or not shooter.alive or match_over or attacks_blocked():
		return
	if origin.distance_to(shooter.global_position + Vector3.UP * 1.4) > 3.0:
		return
	if kind == "rocket":
		var w: Dictionary = Data.WEAPONS.rocket
		if not rules.weapon_allowed(shooter, "rocket") or not _take_fire_token(owner_id, "rocket"):
			return
		vel = vel.limit_length(float(w.speed))
	elif kind == "grenade":
		if int(_grenades.get(owner_id, 0)) <= 0:
			return
		_grenades[owner_id] -= 1
		vel = vel.limit_length(float(Data.GRENADE.throw_speed) + 12.0)
	elif Data.TACTICALS.has(kind):
		if kind != shooter.tactical_id() or int(_tacticals.get(owner_id, 0)) <= 0:
			return
		_tacticals[owner_id] -= 1
		vel = vel.limit_length(float(Data.GRENADE.throw_speed) + 12.0)
	else:
		return
	_server_unprotect(owner_id)
	var pid := _next_projectile_id
	_next_projectile_id += 1
	_broadcast(&"_s_spawn_projectile", [pid, kind, owner_id, origin, vel])


## Called by a Projectile on the server when it detonates.
func server_explode(proj: Projectile, pos: Vector3) -> void:
	if not projectiles.has(proj.pid):
		return
	_broadcast(&"_s_explode", [proj.pid, pos, proj.kind])
	# Smoke and flash do no damage; every peer applies them in _s_explode.
	if match_over or Data.TACTICALS.has(proj.kind):
		return
	if proj.kind == "rocket":
		server_blast(pos, float(Data.WEAPONS.rocket.splash_radius), float(Data.WEAPONS.rocket.damage), proj.owner_id, proj.kind)
	else:
		server_blast(pos, float(Data.GRENADE.radius), float(Data.GRENADE.damage), proj.owner_id, proj.kind)


## Server: an explosion at `pos` (a rocket, a frag, a Block Bomber blast) hurts every living player
## within `radius` that a wall doesn't shield, `max_dmg` falling off with distance, credited to
## `owner_id` with weapon `wid`. The owner takes `self_scale` of it (rockets and frags: half).
func server_blast(pos: Vector3, radius: float, max_dmg: float, owner_id: int, wid: String, self_scale := 0.5) -> void:
	if match_over:
		return
	var space := get_world_3d().direct_space_state
	for eid: int in entities.keys():
		var p: Player = entities.get(eid)
		if p == null or not p.alive:
			continue
		var center := p.global_position + Vector3.UP * 0.9
		var d := pos.distance_to(center)
		if d > radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos, center, Player.MASK_WORLD)
		var r := space.intersect_ray(q)
		if not r.is_empty() and (r.position as Vector3).distance_to(center) > 0.6:
			continue
		var dmg := max_dmg * pow(1.0 - clampf((d - 0.5) / radius, 0.0, 1.0), 0.8)
		if eid == owner_id:
			dmg *= self_scale
		_server_damage(p, dmg, owner_id, wid, false, pos)


func _server_pickups(t: float) -> void:
	for i in pickup_nodes.size():
		var node := pickup_nodes[i]
		if not node.active:
			if t >= _pickup_ready_at[i]:
				_broadcast(&"_s_pickup_state", [i, true, 0.0])
			continue
		for eid: int in entities:
			var p: Player = entities[eid]
			if not p.alive:
				continue
			var d := p.global_position - node.position
			if Vector2(d.x, d.z).length() > PICKUP_RADIUS or absf(d.y) > 1.6:
				continue
			match node.kind:
				"health":
					if p.health >= p.max_health():
						continue
					_broadcast(&"_s_health", [eid, minf(p.max_health(), p.health + HEALTH_PICKUP)])
				"ammo":
					if not p.needs_ammo():
						continue
				"grenade":
					if not Player.carries_grenades(p.info) or int(_grenades.get(eid, 0)) >= int(Data.GRENADE.per_life):
						continue
					_grenades[eid] += 1
			_pickup_ready_at[i] = t + PICKUP_RESPAWN
			_broadcast(&"_s_pickup_taken", [i, eid])
			break


func _server_end_match() -> void:
	if match_over:
		return
	var rows: Array = []
	for eid: int in scores:
		var s: Dictionary = scores[eid]
		rows.append({"id": eid, "name": s.name, "kills": s.kills, "deaths": s.deaths,
			"headshots": s.headshots, "best_streak": s.best_streak, "bot": s.bot, "level": s.level,
			"prestige": int(s.get("prestige", 0))})
	var extra := rules.server_finish(rows)
	if not rules.has_next_match():
		# Tactical: `wait` only times the winner's emote (WIN_SHOW); the results screen waits for
		# NEW GAME (Tactical.request_new_game).
		_broadcast(&"_s_match_end", [rows, extra, WIN_SHOW + 2.0])
		return
	var next := Net.plan_next_match().duplicate()
	next.merge(extra)
	_results_until = now() + RESULTS_TIME
	_broadcast(&"_s_match_end", [rows, next, RESULTS_TIME])
	get_tree().create_timer(RESULTS_TIME).timeout.connect(_server_advance)


## Moves everyone to the next match, once: when the results delay runs out or a skip vote passes.
func _server_advance() -> void:
	if is_inside_tree() and multiplayer.is_server() and not _advancing:
		_advancing = true
		Net.next_match()


## Skip-vote threshold: a majority of the humans in the session.
static func skip_votes_needed(humans: int) -> int:
	return humans / 2 + 1


func _server_vote_skip(pid: int) -> void:
	if not match_over or not Net.players.has(pid):
		return
	_skip_votes[pid] = true
	_server_tally_skip()


## Tells everyone the skip-vote count (players can join mid-results, raising the bar) and
## advances once a majority agrees.
func _server_tally_skip() -> void:
	var votes := 0
	for id: int in _skip_votes:
		if Net.players.has(id):
			votes += 1
	var needed := skip_votes_needed(Net.players.size())
	_broadcast(&"_s_skip_votes", [votes])
	if votes >= needed:
		_server_advance()


func _server_chat_system(text: String) -> void:
	_broadcast(&"_s_chat", ["", text])


# ================================================================ local entry points

## Called by the local player's controller at the network send rate.
func submit_local_state(p: Player) -> void:
	if not multiplayer.is_server():
		_c_state.rpc_id(1, p.global_position, p.yaw, p.pitch, p.state_flags())


## Called by a LOCAL or BOT player after it fires. Plays effects now and reports to the server.
func report_shot(p: Player, wid: String, ends: PackedVector3Array, normals: PackedVector3Array, hits: Dictionary) -> void:
	_play_shot_fx(p, wid, ends, normals)
	var hit_list: Array = []
	var hit_enemy := false
	for tid: int in hits:
		hit_list.append([tid, hits[tid][0], hits[tid][1]])
		hit_enemy = hit_enemy or not Teams.same(p, entities.get(tid))
	if p == local_player:
		_count_my_shot(wid, hit_enemy)
	if multiplayer.is_server():
		_server_shot(p.id, wid, ends, normals, hit_list)
	else:
		_c_shot.rpc_id(1, wid, ends, normals, hit_list)


## Per-weapon numbers of the local player this match (my_weapon_stats), created on first use.
func _my_stats(wid: String) -> Dictionary:
	if not my_weapon_stats.has(wid):
		my_weapon_stats[wid] = {"kills": 0, "headshots": 0, "shots": 0, "hits": 0, "damage": 0.0}
	return my_weapon_stats[wid]


## One shot of the local player: a hitscan pellet group, a burst round, a knife swing or a rocket
## (whose hit is counted when its blast is confirmed, see _s_hit_confirm).
func _count_my_shot(wid: String, hit: bool) -> void:
	if match_over or not Data.WEAPONS.has(wid):
		return
	var s := _my_stats(wid)
	s.shots += 1
	if hit:
		s.hits += 1


func request_projectile(p: Player, kind: String, origin: Vector3, vel: Vector3) -> void:
	if p.mode == Player.Mode.LOCAL:
		Sfx.play(&"shot_rocket" if kind == "rocket" else &"grenade_throw", null, -2.0)
		if kind == "rocket":
			_count_my_shot("rocket", false)
	if multiplayer.is_server():
		_server_projectile(p.id, kind, origin, vel)
	else:
		_c_projectile.rpc_id(1, kind, origin, vel)


func send_chat(text: String) -> void:
	if multiplayer.is_server():
		_server_chat(my_id(), text)
	else:
		_c_chat.rpc_id(1, text)


## Results screen: this player votes to start the next match now.
func vote_skip() -> void:
	if multiplayer.is_server():
		_server_vote_skip(my_id())
	else:
		_c_vote_skip.rpc_id(1)


func _server_chat(sender: int, text: String) -> void:
	text = text.strip_edges().replace("[", "(").replace("]", ")").substr(0, MAX_CHAT_LENGTH)
	if text.is_empty() or not Net.players.has(sender):
		return
	_broadcast(&"_s_chat", [str(Net.players[sender].name), text])


func _play_shot_fx(p: Player, wid: String, ends: PackedVector3Array, normals: PackedVector3Array) -> void:
	killcam.record_shot(p, wid, ends, normals)
	var w: Dictionary = Data.WEAPONS[wid]
	var muzzle := p.muzzle_position()
	var is_local := p == local_player
	if p.mode == Player.Mode.REMOTE:
		p.remote_fired()
		if wid == "knife":
			p.avatar.play_slash()
		else:
			p.avatar.play_shoot()
	if wid == "knife":
		Sfx.play(&"knife_swing", null if is_local else p.global_position, -4.0)
		if normals.size() > 0 and normals[0] != Vector3.ZERO:
			Sfx.play(&"bullet_impact", ends[0], -6.0)
			fx.impact(ends[0], normals[0])
		return
	var suppressed: bool = w.get("suppressed", false)
	Sfx.play(StringName(w.sound), null if is_local else muzzle, -3.0 if is_local else 0.0, float(w.get("pitch", 1.0)))
	# A suppressed gun gives nothing away to anyone else: no flash, no tracer, no flyby.
	if not is_local and not suppressed:
		fx.muzzle_flash(muzzle)
	var tracer_every := 3 if int(w.pellets) > 1 else 1
	for i in ends.size():
		if i % tracer_every == 0 and (is_local or not suppressed):
			fx.tracer(muzzle, ends[i])
		if normals[i] != Vector3.ZERO:
			fx.impact(ends[i], normals[i])
	if not is_local and not suppressed and local_player != null and local_player.alive and ends.size() > 0:
		var ear := local_player.head.global_position
		var closest := Geometry3D.get_closest_point_to_segment(ear, muzzle, ends[0])
		if closest.distance_to(ear) < 1.6 and closest.distance_to(muzzle) > 3.0:
			Sfx.play(&"whizz", closest, -4.0)


# ================================================================ RPC: client -> server

@rpc("any_peer", "call_remote", "reliable")
func _c_ready() -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if not Net.players.has(pid) or _ready_peers.has(pid):
		return
	_ready_peers[pid] = true
	for eid: int in entities:
		var p: Player = entities[eid]
		_s_spawn_entity.rpc_id(pid, eid, p.info, p.is_bot, p.global_position, p.yaw, p.health, p.alive)
		if _protection_left(eid) > 0.0:
			_s_protection.rpc_id(pid, eid, _protection_left(eid))
	_s_scores.rpc_id(pid, scores)
	_s_clock.rpc_id(pid, time_left)
	for i in pickup_nodes.size():
		if not pickup_nodes[i].active:
			_s_pickup_state.rpc_id(pid, i, false, _pickup_ready_at[i] - now())
	if match_over:
		_s_match_end.rpc_id(pid, results, next_up, maxf(0.0, _results_until - now()))
		_server_tally_skip()
		return
	streaks.server_sync(pid)
	rules.server_human_joined(pid)
	_server_chat_system("%s joined the game" % Net.players[pid].name)
	_balance_bots()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _c_state(pos: Vector3, p_yaw: float, p_pitch: float, flags: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var p: Player = entities.get(sender)
	if p == null or p.mode != Player.Mode.REMOTE or not p.alive:
		return
	# Packets sent before the client learned it respawned would teleport it back to its corpse.
	if now() - float(_respawned_at.get(sender, -100.0)) < 0.4:
		return
	p.push_snapshot(pos, p_yaw, p_pitch, flags)


@rpc("any_peer", "call_remote", "reliable")
func _c_shot(wid: String, ends: PackedVector3Array, normals: PackedVector3Array, hit_list: Array) -> void:
	if multiplayer.is_server():
		_server_shot(multiplayer.get_remote_sender_id(), wid, ends, normals, hit_list)


@rpc("any_peer", "call_remote", "reliable")
func _c_projectile(kind: String, origin: Vector3, vel: Vector3) -> void:
	if multiplayer.is_server():
		_server_projectile(multiplayer.get_remote_sender_id(), kind, origin, vel)


@rpc("any_peer", "call_remote", "reliable")
func _c_chat(text: String) -> void:
	if multiplayer.is_server():
		_server_chat(multiplayer.get_remote_sender_id(), text)


@rpc("any_peer", "call_remote", "reliable")
func _c_vote_skip() -> void:
	if multiplayer.is_server():
		_server_vote_skip(multiplayer.get_remote_sender_id())


# ================================================================ RPC: server -> peers

@rpc("authority", "call_remote", "reliable")
func _s_spawn_entity(eid: int, info: Dictionary, is_bot: bool, pos: Vector3, p_yaw: float, hp: float, is_alive: bool) -> void:
	if entities.has(eid):
		return
	var mode := Player.Mode.REMOTE
	if eid == my_id():
		mode = Player.Mode.LOCAL
	elif is_bot and multiplayer.is_server():
		mode = Player.Mode.BOT
	var p := Player.new()
	p.setup(self, eid, info, mode, is_bot)
	p.position = pos
	p.yaw = p_yaw
	_entities_root.add_child(p)
	p.health = hp
	entities[eid] = p
	if mode == Player.Mode.LOCAL:
		local_player = p
	if not is_alive:
		p.die()
	rules.on_player_added(p)


@rpc("authority", "call_remote", "reliable")
func _s_despawn(eid: int) -> void:
	var p: Player = entities.get(eid)
	if p == null:
		return
	entities.erase(eid)
	streaks.on_death(eid)
	if p == local_player:
		killcam.stop("left")
		local_player = null
	p.queue_free()


@rpc("authority", "call_remote", "unreliable_ordered")
func _s_snapshot(snap: Array) -> void:
	var me := my_id()
	for entry: Array in snap:
		var eid: int = entry[0]
		if eid == me:
			continue
		var p: Player = entities.get(eid)
		if p != null and p.mode == Player.Mode.REMOTE:
			p.push_snapshot(entry[1], entry[2], entry[3], entry[4])


@rpc("authority", "call_remote", "unreliable_ordered")
func _s_clock(t: float) -> void:
	time_left = t


@rpc("authority", "call_remote", "reliable")
func _s_scores(all: Dictionary) -> void:
	scores = all
	_welcomed = true
	hud.refresh_scores()
	# Every kill ends with a scores update (after its _s_killed): see whether it completed anything.
	if not match_over and scores.has(my_id()):
		_toast_feats(Profile.preview_feats(my_facts.result(scores[my_id()], my_weapon_stats, 0, scores.size(), false)))


## Toasts each feat ([key, title, text]) not toasted yet this match.
func _toast_feats(feats: Array) -> void:
	for f: Array in feats:
		if _feats_toasted.has(f[0]):
			continue
		_feats_toasted[f[0]] = true
		hud.feat_toast(str(f[1]), str(f[2]))


@rpc("authority", "call_remote", "unreliable")
func _s_shot_fx(shooter_id: int, wid: String, ends: PackedVector3Array, normals: PackedVector3Array) -> void:
	var p: Player = entities.get(shooter_id)
	if p != null and Data.WEAPONS.has(wid):
		_play_shot_fx(p, wid, ends, normals)


## `shield` is the target's Overshield left after the hit (Streaks); health and shield together
## make up what a hit took, for the death screen.
@rpc("authority", "call_remote", "reliable")
func _s_damaged(eid: int, hp: float, attacker_id: int, from_pos: Vector3, shield: float) -> void:
	var p: Player = entities.get(eid)
	if p == null:
		return
	var before := p.health + p.shield
	var had_shield := p.shield
	p.shield = shield
	p.on_damaged(hp, attacker_id)
	if attacker_id != eid:
		fx.blood(p.global_position + Vector3.UP * (p.body_center_height() - 0.15))
		killcam.record_hit(p)
	if had_shield > shield:
		var sound := &"shield_break" if shield <= 0.0 else &"shield_hit"
		Sfx.play(sound, null if p == local_player else p.global_position, -2.0 if p == local_player else -6.0)
	if p == local_player:
		if p.alive:
			var taken: Array = _my_damage_taken.get(attacker_id, [0, 0.0])
			_my_damage_taken[attacker_id] = [int(taken[0]) + 1, float(taken[1]) + maxf(0.0, before - hp - shield)]
		hud.show_damage(from_pos)
		Sfx.play(&"hurt", null, -3.0)
		shake(0.25)


@rpc("authority", "call_remote", "reliable")
func _s_health(eid: int, hp: float) -> void:
	var p: Player = entities.get(eid)
	if p != null:
		p.health = hp


## `wid` is the weapon or source that dealt the hit: per-weapon damage, and a rocket's blast
## counts its shot as a hit (once per blast, see my_weapon_stats).
@rpc("authority", "call_remote", "reliable")
func _s_hit_confirm(head: bool, killed: bool, amount: float, pos: Vector3, wid: String) -> void:
	hud.show_hitmarker(head, killed)
	hud.damage_number(pos, amount, head)
	Sfx.play(&"headshot" if head else &"hit_marker", null, -2.0)
	if match_over or not (Data.WEAPONS.has(wid) or Data.STAT_EXTRA_SOURCES.has(wid)):
		return
	var s := _my_stats(wid)
	s.damage += amount
	if wid == "rocket" and Engine.get_process_frames() != _my_rocket_hit_frame:
		_my_rocket_hit_frame = Engine.get_process_frames()
		s.hits = mini(s.hits + 1, s.shots)


@rpc("authority", "call_remote", "reliable")
func _s_killed(victim_id: int, killer_id: int, wid: String, head: bool, killer_hp: float, killer_dist: float) -> void:
	var victim: Player = entities.get(victim_id)
	if victim != null:
		fx.death_burst(victim.global_position + Vector3.UP * 0.9, Color(info_color(victim)))
		Sfx.play(&"death", victim.global_position)
		victim.die(entities.get(killer_id) if victim == local_player else null)
	streaks.on_death(victim_id)
	var teams := [Teams.of(entities.get(killer_id)), Teams.of(victim)]
	hud.add_killfeed(tagged_name(killer_id), weapon_label(wid), tagged_name(victim_id), head, killer_id == victim_id, teams[0], teams[1], wid)
	var me := my_id()
	if killer_id == me and victim_id != me:
		# Per-weapon kills go to the source that killed: the gun, the grenade or the Block Bomber.
		if not match_over and (Data.WEAPONS.has(wid) or Data.STAT_EXTRA_SOURCES.has(wid)):
			var s := _my_stats(wid)
			s.kills += 1
			if head:
				s.headshots += 1
		Sfx.play(&"kill_confirm", null, -1.0)
		var t := now()
		_my_multi = _my_multi + 1 if t - _my_last_kill < MULTI_KILL_WINDOW else 1
		_my_last_kill = t
		if not match_over:
			my_facts.on_kill(local_player, wid, killer_dist, _my_multi, t)
		# Like the server's streak: a killstreak reward's kills don't extend it.
		if wid != Streaks.WEAPON:
			_my_streak += 1
		hud.show_kill(display_name(victim_id), head)
		var announce := ""
		match _my_streak:
			3: announce = "KILLING SPREE"
			5: announce = "RAMPAGE"
			7: announce = "UNSTOPPABLE"
			10: announce = "GODLIKE"
			15: announce = "LEGENDARY"
		if _my_multi >= 2:
			announce = ["DOUBLE KILL", "TRIPLE KILL", "MULTI KILL", "MEGA KILL"][mini(_my_multi - 2, 3)]
		if not announce.is_empty():
			hud.announce(announce)
	if victim_id == me:
		_my_streak = 0
		_my_multi = 0
		hud.show_death(display_name(killer_id) if killer_id != me else "", weapon_label(wid), rules.respawn_delay(), _death_detail(killer_id, killer_hp, killer_dist))
		rules.on_local_death(killer_id)
		killcam.on_local_death(killer_id, wid)
		_my_damage_taken.clear()


## One line for the death screen: how far away the killer was, how many of their hits it took
## and how much health they had left, so a death says what to do differently. `killer_hp` and
## `killer_dist` are the server's values at the kill (negative: unknown or not applicable).
func _death_detail(killer_id: int, killer_hp: float, killer_dist: float) -> String:
	if killer_id == my_id():
		return ""
	var parts: Array[String] = []
	if killer_dist >= 0.0:
		parts.append("From %d m" % roundi(killer_dist))
	var taken: Array = _my_damage_taken.get(killer_id, [0, 0.0])
	if int(taken[0]) > 0:
		parts.append("%d hit%s, %d damage" % [int(taken[0]), "" if int(taken[0]) == 1 else "s", roundi(float(taken[1]))])
	if killer_hp > 0.0:
		# The killer's Overshield (Streaks) at the kill, as this peer has it from the server.
		var killer: Player = entities.get(killer_id)
		var shield := killer.shield if killer != null and killer.alive else 0.0
		parts.append("they had %d HP%s left" % [ceili(killer_hp), " + %d shield" % ceili(shield) if shield > 0.0 else ""])
	return "  ·  ".join(parts)


@rpc("authority", "call_remote", "reliable")
func _s_respawn(eid: int, pos: Vector3, p_yaw: float) -> void:
	var p: Player = entities.get(eid)
	if p == null:
		return
	if p == local_player:
		killcam.stop("respawn")
	p.respawn(pos, p_yaw)
	if p == local_player:
		hud.hide_death()
		Sfx.play(&"spawn", null, -6.0)


@rpc("authority", "call_remote", "reliable")
func _s_protection(eid: int, seconds: float) -> void:
	var p: Player = entities.get(eid)
	if p != null:
		p.set_protection(seconds)


@rpc("authority", "call_remote", "reliable")
func _s_spawn_projectile(pid: int, kind: String, owner_id: int, origin: Vector3, vel: Vector3) -> void:
	var proj := Projectile.new()
	proj.setup(self, pid, kind, owner_id, origin, vel)
	add_child(proj)
	projectiles[pid] = proj
	killcam.record_launch(owner_id, kind)
	if owner_id != my_id():
		Sfx.play(&"shot_rocket" if kind == "rocket" else &"grenade_throw", origin)
	var thrower: Player = entities.get(owner_id)
	if thrower != null and thrower.mode == Player.Mode.REMOTE:
		if kind == "rocket":
			thrower.avatar.play_shoot()
		else:
			thrower.avatar.play_throw()


@rpc("authority", "call_remote", "reliable")
func _s_explode(pid: int, pos: Vector3, kind: String) -> void:
	var proj: Projectile = projectiles.get(pid)
	killcam.record_explosion(pos, kind)
	if proj != null:
		projectiles.erase(pid)
		proj.queue_free()
	match kind:
		"smoke":
			var smoke: Dictionary = Data.TACTICALS.smoke
			smokes.append([pos, float(smoke.radius), now() + float(smoke.duration)])
			fx.smoke_cloud(pos, float(smoke.radius), float(smoke.duration))
			Sfx.play(&"smoke_pop", pos)
		"flash":
			fx.flash_burst(pos)
			Sfx.play(&"flashbang", pos, 2.0)
			var flash: Dictionary = Data.TACTICALS.flash
			for eid: int in entities:
				var p: Player = entities[eid]
				if p == local_player or p.mode == Player.Mode.BOT:
					var amount := flash_amount(p, pos)
					if amount <= 0.0:
						continue
					p.flashed_until = maxf(p.flashed_until, now() + amount * float(flash.duration))
					if p == local_player:
						hud.flash(amount, amount * float(flash.duration))
		_:
			fx.explosion(pos)
			Sfx.play(&"explosion", pos, 2.0)
			if local_player != null:
				var d := local_player.global_position.distance_to(pos)
				shake(clampf(1.4 - d / 10.0, 0.0, 1.2))


## How hard a flash at `pos` blinds `p` (0..1): nothing through walls or past the flash radius;
## strongest up close and when looking straight at it.
func flash_amount(p: Player, pos: Vector3) -> float:
	if not p.alive:
		return 0.0
	var eye := p.head.global_position
	var to := pos - eye
	var d := to.length()
	var radius := float(Data.TACTICALS.flash.radius)
	if d > radius:
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(eye, pos, Player.MASK_WORLD)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty() and (r.position as Vector3).distance_to(pos) > 0.4:
		return 0.0
	var look := -Basis.from_euler(Vector3(p.pitch, p.yaw, 0.0)).z
	var facing := look.dot(to / maxf(d, 0.001))
	return pow(1.0 - d / radius, 0.6) * (0.25 + 0.75 * smoothstep(-0.2, 0.7, facing))


## True while an active smoke cloud covers the line from `from` to `to` (bots can't see through).
func smoke_blocks(from: Vector3, to: Vector3) -> bool:
	var t := now()
	for s: Array in smokes:
		# The cloud is still building for its first second and thinning for its last.
		if t > float(s[2]) - 1.0 or t < float(s[2]) - float(Data.TACTICALS.smoke.duration) + 0.8:
			continue
		var c: Vector3 = s[0]
		if Geometry3D.get_closest_point_to_segment(c, from, to).distance_to(c) < float(s[1]) * 0.85:
			return true
	return false


## A player's grapple hook took hold (`active`) or let go; shown to every other peer.
func report_grapple(p: Player, active: bool, point: Vector3) -> void:
	if multiplayer.is_server():
		_server_grapple(p.id, active, point)
	elif p == local_player:
		_c_grapple.rpc_id(1, active, point)


func _server_grapple(eid: int, active: bool, point: Vector3) -> void:
	var p: Player = entities.get(eid)
	if p == null or (active and (not p.alive or point.distance_to(p.global_position) > Player.GRAPPLE_RANGE + 6.0)):
		return
	if p.mode == Player.Mode.REMOTE:
		p.set_remote_grapple(active, point)
	for pid: int in _ready_peers:
		if pid != eid:
			_s_grapple.rpc_id(pid, eid, active, point)


@rpc("any_peer", "call_remote", "reliable")
func _c_grapple(active: bool, point: Vector3) -> void:
	if multiplayer.is_server():
		_server_grapple(multiplayer.get_remote_sender_id(), active, point)


@rpc("authority", "call_remote", "reliable")
func _s_grapple(eid: int, active: bool, point: Vector3) -> void:
	var p: Player = entities.get(eid)
	if p != null and p.mode == Player.Mode.REMOTE:
		p.set_remote_grapple(active, point)


## `respawn_in` (seconds) drives the countdown an inactive pickup shows.
@rpc("authority", "call_remote", "reliable")
func _s_pickup_state(index: int, is_active: bool, respawn_in: float) -> void:
	if index >= 0 and index < pickup_nodes.size():
		pickup_nodes[index].set_active(is_active, respawn_in)


@rpc("authority", "call_remote", "reliable")
func _s_pickup_taken(index: int, eid: int) -> void:
	if index < 0 or index >= pickup_nodes.size():
		return
	var node := pickup_nodes[index]
	node.set_active(false, PICKUP_RESPAWN)
	var p: Player = entities.get(eid)
	if p == null:
		return
	if p.mode != Player.Mode.REMOTE:
		match node.kind:
			"ammo":
				p.add_ammo_pickup()
			"grenade":
				p.grenades = mini(p.grenades + 1, int(Data.GRENADE.per_life))
	var sound := &"pickup_health" if node.kind == "health" else &"pickup_ammo"
	if p == local_player:
		Sfx.play(sound, null, -2.0)
		hud.pickup_message(node.kind)
	else:
		Sfx.play(sound, node.position, -8.0)


@rpc("authority", "call_remote", "reliable")
func _s_chat(sender_name: String, text: String) -> void:
	hud.add_chat(sender_name, text)


@rpc("authority", "call_remote", "reliable")
func _s_match_end(rows: Array, next: Dictionary, wait: float) -> void:
	killcam.stop("match_end")
	match_over = true
	results = rows
	next_up = next
	var me := my_id()
	var placement := 0
	var mine: Dictionary = {}
	for i in rows.size():
		if int(rows[i].id) == me:
			placement = i + 1
			mine = rows[i]
	# Team modes: the server marks each row `won` (a team win counts for every member; Infected:
	# the side that won). A win pays like first place, a draw like second.
	var won := bool(mine.get("won", placement == 1))
	var reward_place := placement
	if next.has("winner"):
		reward_place = 1 if won else (2 if int(next.winner) < 0 else 0)
	rules.on_match_over()
	streaks.on_match_over()
	pings.on_match_over()
	var rewards := {}
	if not mine.is_empty():
		# The highlights this player earned are their medals.
		var medals: Array = []
		for h: Array in rules.highlights(rows):
			if h[1]:
				medals.append(h[2])
		rewards = Profile.record_match(my_facts.result(mine, my_weapon_stats, reward_place, rows.size(), won, medals))
		_toast_feats(rewards.get("feats", []))
	my_weapon_stats = {}
	my_facts = MatchFacts.new()
	_feats_toasted = {}
	match_rewards = rewards
	Sfx.play(&"match_end")
	Sfx.play_music(&"results")
	var winner: Player = entities.get(int(rows[0].id)) if not rows.is_empty() else null
	var banner := "YOU WIN!" if winner != null and winner == local_player else ("%s WINS!" % str(rows[0].name).to_upper() if not rows.is_empty() else "")
	if next.has("winner"):
		# Team result: the winning side's top player performs the emote (rows put them first); a
		# draw or a winner already gone skips straight to the results.
		if winner != null and (int(next.winner) < 0 or not winner.alive or not bool(rows[0].get("won", false))):
			winner = null
		banner = rules.win_banner(next)
	var show := minf(WIN_SHOW, wait - 2.0)
	if winner == null or show < 0.5:
		hud.show_results(rows, placement, rewards, wait, next)
		return
	_start_win_cam(winner)
	hud.show_winner(banner)
	get_tree().create_timer(show).timeout.connect(func() -> void:
		if match_over:
			hud.show_results(rows, placement, rewards, wait - show, next))


## Every peer's view cuts to the winner, who performs their equipped win emote.
func _start_win_cam(winner: Player) -> void:
	_win_target = winner
	winner.avatar.play_emote(str(winner.info.get("emote", "wave")))
	if winner == local_player:
		winner.avatar.set_first_person(false)
		if winner.viewmodel != null:
			winner.viewmodel.visible = false
	if winner.laser != null:
		winner.laser.visible = false
	_win_cam = Camera3D.new()
	_win_cam.name = "WinCam"
	_win_cam.fov = 55.0
	_win_cam.top_level = true
	add_child(_win_cam)
	_win_t = 0.0
	_update_win_cam(0.0)
	_win_cam.make_current()


## Slowly swings the camera around the front of the winner, kept out of walls.
func _update_win_cam(delta: float) -> void:
	if not is_instance_valid(_win_target):
		return
	_win_t += delta
	var center := _win_target.global_position + Vector3.UP * 1.05
	var ang := _win_target.yaw + sin(_win_t * 0.45) * 0.55
	var dir := Vector3(-sin(ang), 0.18, -cos(ang)).normalized()
	var want := center + dir * 3.4
	var q := PhysicsRayQueryParameters3D.create(center, want, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var pos: Vector3 = want if hit.is_empty() else center + (hit.position - center) * 0.85
	_win_cam.global_position = pos
	if pos.distance_squared_to(center) > 0.01:
		_win_cam.look_at(center, Vector3.UP)


@rpc("authority", "call_remote", "reliable")
func _s_skip_votes(votes: int) -> void:
	hud.set_skip_votes(votes)


# ================================================================ helpers

## Loadout mutators hand everyone the mutator's gun as the primary and keep their own primary as
## the backup in place of the sidearm, so the gun they bought still matters (a player whose own
## primary already is that gun keeps their sidearm). Rocket Party: the Boom Block; Snipers Only:
## the Voxel Longshot.
static func _apply_loadout_mutator(info: Dictionary) -> Dictionary:
	var gun: String = LOADOUT_MUTATORS.get(str(Net.config.mutator), "")
	if gun.is_empty():
		return info
	var out := info.duplicate()
	out.primary = gun
	if str(info.primary) != gun:
		out.secondary = info.primary
	return out


## Re-lights the built map for sunset or night. Every peer gets the same value from Net.config.
static func _apply_time_of_day(map_root: Node3D, time_of_day: String) -> void:
	if time_of_day == "day":
		return
	var sun := map_root.find_children("*", "DirectionalLight3D", true, false)
	var envs := map_root.find_children("*", "WorldEnvironment", true, false)
	if sun.is_empty() or envs.is_empty():
		return
	var light := sun[0] as DirectionalLight3D
	var env := (envs[0] as WorldEnvironment).environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	if time_of_day == "sunset":
		light.rotation_degrees.x = -12.0
		light.light_color = Color(1.0, 0.62, 0.38)
		light.light_energy *= 0.85
		sky.sky_top_color = Color(0.26, 0.3, 0.55)
		sky.sky_horizon_color = Color(1.0, 0.6, 0.38)
		env.fog_light_color = Color(0.95, 0.6, 0.45)
		env.ambient_light_color = Color(0.95, 0.72, 0.6)
	else:
		# Night: cool moonlight bright enough to fight in; lamp blocks and muzzle flashes pop.
		light.rotation_degrees.x = -40.0
		light.light_color = Color(0.6, 0.7, 1.0)
		light.light_energy *= 0.32
		sky.sky_top_color = Color(0.02, 0.03, 0.08)
		sky.sky_horizon_color = Color(0.1, 0.13, 0.25)
		sky.ground_horizon_color = Color(0.08, 0.1, 0.18)
		env.fog_light_color = Color(0.1, 0.12, 0.22)
		env.ambient_light_color = Color(0.45, 0.52, 0.8)
		env.ambient_light_energy *= 0.55


static func weapon_label(wid: String) -> String:
	match wid:
		"grenade": return "Grenade"
		"fall": return "Gravity"
		Streaks.WEAPON: return "Block Bomber"
	return str(Data.WEAPONS[wid].name) if Data.WEAPONS.has(wid) else wid


static func info_color(p: Player) -> Color:
	var outfit: Dictionary = Data.OUTFITS.get(str(p.info.outfit), Data.OUTFITS.classic)
	return outfit.shirt
