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
const RESULTS_TIME := 12.0
const SPAWN_PROTECTION := 2.0
const REGEN_DELAY := 5.0
const REGEN_RATE := 12.0
const PICKUP_RESPAWN := 20.0
const PICKUP_RADIUS := 1.3
const HEALTH_PICKUP := 50.0
const MULTI_KILL_WINDOW := 3.5
const MAX_CHAT_LENGTH := 100

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

var _entities_root: Node3D
var _shake := 0.0
var _my_multi := 0
var _my_last_kill := -100.0
var _my_streak := 0

# Server-only state.
var _ready_peers := {}
var _respawn_at := {}
## Shooter key ("<entity>" for guns, "<entity>:knife") -> [debt seconds, time]; see _take_fire_token.
var _fire_tokens := {}
## Entity id -> time of last server respawn; client state is ignored briefly afterwards so stale
## pre-respawn positions can't drag the player back (or below kill_y again).
var _respawned_at := {}
var _spawned_at := {}
var _last_damage := {}
var _grenades := {}
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
	_entities_root = Node3D.new()
	_entities_root.name = "Entities"
	add_child(_entities_root)
	for pick: Dictionary in map_info.pickups:
		var node := PickupNode.new()
		node.setup(str(pick.kind))
		node.position = pick.pos
		add_child(node)
		pickup_nodes.append(node)
		_pickup_ready_at.append(0.0)
	hud = Hud.new()
	hud.name = "Hud"
	hud.setup(self)
	add_child(hud)
	time_left = float(Net.config.time_limit)
	Sfx.play_music(&"match")
	Sfx.play(&"match_start")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_server_add_entity(multiplayer.get_unique_id(), Net.players[multiplayer.get_unique_id()], false)
		_balance_bots()
	else:
		_c_ready.rpc_id(1)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func now() -> float:
	return Time.get_ticks_msec() * 0.001


func my_id() -> int:
	return multiplayer.get_unique_id()


func input_blocked() -> bool:
	return hud.is_blocking() or match_over


func display_name(entity_id: int) -> String:
	if scores.has(entity_id):
		return str(scores[entity_id].name)
	if entities.has(entity_id):
		return str(entities[entity_id].info.name)
	return "?"


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		if not match_over:
			time_left = maxf(0.0, time_left - delta)
		if not _welcomed:
			_ready_retry -= delta
			if _ready_retry <= 0.0:
				_ready_retry = 1.0
				_c_ready.rpc_id(1)
	if _shake > 0.0 and local_player != null and local_player.camera != null:
		_shake = move_toward(_shake, 0.0, delta * 2.5)
		local_player.camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.08
		local_player.camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.08


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
	if not match_over:
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
			if p.alive and p.health < Data.MAX_HEALTH and t - float(_last_damage.get(eid, -100.0)) > REGEN_DELAY:
				_broadcast(&"_s_health", [eid, minf(Data.MAX_HEALTH, p.health + REGEN_RATE * REGEN_INTERVAL)])


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

func _server_add_entity(eid: int, info: Dictionary, is_bot: bool) -> void:
	var spawn := _pick_spawn(eid)
	scores[eid] = {"name": str(info.name), "level": int(info.get("level", 1)), "kills": 0, "deaths": 0,
		"headshots": 0, "streak": 0, "best_streak": 0, "bot": is_bot}
	_spawned_at[eid] = now()
	_grenades[eid] = int(Data.GRENADE.per_life)
	_broadcast(&"_s_spawn_entity", [eid, _apply_loadout_mutator(info), is_bot, spawn[0], spawn[1], Data.MAX_HEALTH, true])
	_broadcast(&"_s_scores", [scores])


func _server_remove_entity(eid: int) -> void:
	scores.erase(eid)
	_respawn_at.erase(eid)
	_spawned_at.erase(eid)
	_grenades.erase(eid)
	_last_damage.erase(eid)
	_respawned_at.erase(eid)
	_broadcast(&"_s_despawn", [eid])
	_broadcast(&"_s_scores", [scores])


## Keeps bots + humans at `bots_fill`. When a bot has to leave, it is the one whose exit
## disturbs the match least: dead bots first, then bots out of combat, then the lowest scorer.
func _balance_bots() -> void:
	if not multiplayer.is_server() or match_over:
		return
	var want := maxi(0, int(Net.config.bots_fill) - Net.players.size())
	var bots: Array[int] = []
	for eid: int in entities:
		if eid < 0:
			bots.append(eid)
	if bots.size() > want:
		bots.sort_custom(func(a: int, b: int) -> bool: return _bot_leave_cost(a) < _bot_leave_cost(b))
	while bots.size() > want:
		var eid: int = bots.pop_front()
		_bot_names_used.erase(entities[eid].info.name)
		_server_remove_entity(eid)
	while bots.size() < want:
		var eid := _next_bot_id
		_next_bot_id -= 1
		_server_add_entity(eid, _make_bot_info(), true)
		bots.append(eid)


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
	var bot_name: String = names.pick_random() if not names.is_empty() else "Bot %d" % (-_next_bot_id)
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
		"level": randi_range(1, 30),
	}


## Picks a spawn far from living enemies, strongly avoiding any spawn an enemy can see.
func _pick_spawn(for_id: int) -> Array:
	var space := get_world_3d().direct_space_state
	var ranked: Array = []
	for s: Vector3 in map_info.spawns:
		var nearest := 1e9
		var seen := false
		for eid: int in entities:
			var p: Player = entities[eid]
			if eid == for_id or not p.alive:
				continue
			var d := s.distance_squared_to(p.global_position)
			nearest = minf(nearest, d)
			if not seen and d < 70.0 * 70.0:
				var q := PhysicsRayQueryParameters3D.create(s + Vector3.UP * 1.6, p.global_position + Vector3.UP * 1.6, Player.MASK_WORLD)
				seen = space.intersect_ray(q).is_empty()
		# Visible spawns rank below every hidden one.
		ranked.append([nearest - (1e8 if seen else 0.0), s])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var pick: Vector3 = ranked[randi() % mini(3, ranked.size())][1]
	var to_center := map_info.bounds.get_center() - pick
	return [pick, atan2(-to_center.x, -to_center.z)]


func _server_respawn(eid: int) -> void:
	var spawn := _pick_spawn(eid)
	_spawned_at[eid] = now()
	_respawned_at[eid] = now()
	_grenades[eid] = int(Data.GRENADE.per_life)
	_broadcast(&"_s_respawn", [eid, spawn[0], spawn[1]])


func _on_peer_disconnected(pid: int) -> void:
	_ready_peers.erase(pid)
	if entities.has(pid):
		_server_chat_system("%s left the game" % display_name(pid))
		_server_remove_entity(pid)
	_balance_bots.call_deferred()


# ================================================================ server: combat

func _server_shot(shooter_id: int, wid: String, ends: PackedVector3Array, normals: PackedVector3Array, hit_list: Array) -> void:
	var shooter: Player = entities.get(shooter_id)
	if shooter == null or not shooter.alive or match_over or not Data.WEAPONS.has(wid):
		return
	if wid != "knife" and not shooter.slots.has(wid):
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
	_spawned_at[shooter_id] = -100.0
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
	if attacker_id != target.id and now() - float(_spawned_at.get(target.id, -100.0)) < SPAWN_PROTECTION:
		return
	if Net.config.mutator == "glass_cannon":
		amount *= 2.0
	var hp := maxf(0.0, target.health - amount)
	var dealt := target.health - hp
	_last_damage[target.id] = now()
	_broadcast(&"_s_damaged", [target.id, hp, attacker_id, from_pos])
	var killed := hp <= 0.0
	if attacker_id != target.id:
		var label_pos := target.global_position + Vector3.UP * 2.0
		if attacker_id == my_id():
			_s_hit_confirm(head, killed, dealt, label_pos)
		elif _ready_peers.has(attacker_id):
			_s_hit_confirm.rpc_id(attacker_id, head, killed, dealt, label_pos)
	if killed:
		_server_kill(target.id, attacker_id, wid, head)


func _server_force_kill(p: Player) -> void:
	_broadcast(&"_s_damaged", [p.id, 0.0, p.id, p.global_position])
	_server_kill(p.id, p.id, "fall", false)


func _server_kill(victim_id: int, killer_id: int, wid: String, head: bool) -> void:
	if scores.has(victim_id):
		var v: Dictionary = scores[victim_id]
		v.deaths += 1
		v.streak = 0
		if killer_id == victim_id:
			v.kills = maxi(0, int(v.kills) - 1)
	if killer_id != victim_id and scores.has(killer_id):
		var k: Dictionary = scores[killer_id]
		k.kills += 1
		k.streak += 1
		k.best_streak = maxi(int(k.best_streak), int(k.streak))
		if head:
			k.headshots += 1
		if Net.config.mutator == "vampire" and entities.has(killer_id) and entities[killer_id].alive:
			_broadcast(&"_s_health", [killer_id, Data.MAX_HEALTH])
	_respawn_at[victim_id] = now() + Data.RESPAWN_TIME
	_broadcast(&"_s_killed", [victim_id, killer_id, wid, head])
	_broadcast(&"_s_scores", [scores])
	if scores.has(killer_id) and int(scores[killer_id].kills) >= int(Net.config.kill_limit):
		_server_end_match()


func _server_projectile(owner_id: int, kind: String, origin: Vector3, vel: Vector3) -> void:
	var shooter: Player = entities.get(owner_id)
	if shooter == null or not shooter.alive or match_over:
		return
	if origin.distance_to(shooter.global_position + Vector3.UP * 1.4) > 3.0:
		return
	if kind == "rocket":
		var w: Dictionary = Data.WEAPONS.rocket
		if not shooter.slots.has("rocket") or not _take_fire_token(owner_id, "rocket"):
			return
		vel = vel.limit_length(float(w.speed))
	elif kind == "grenade":
		if int(_grenades.get(owner_id, 0)) <= 0:
			return
		_grenades[owner_id] -= 1
		vel = vel.limit_length(float(Data.GRENADE.throw_speed) + 12.0)
	else:
		return
	_spawned_at[owner_id] = -100.0
	var pid := _next_projectile_id
	_next_projectile_id += 1
	_broadcast(&"_s_spawn_projectile", [pid, kind, owner_id, origin, vel])


## Called by a Projectile on the server when it detonates.
func server_explode(proj: Projectile, pos: Vector3) -> void:
	if not projectiles.has(proj.pid):
		return
	_broadcast(&"_s_explode", [proj.pid, pos])
	if match_over:
		return
	var radius: float
	var max_dmg: float
	if proj.kind == "rocket":
		radius = float(Data.WEAPONS.rocket.splash_radius)
		max_dmg = float(Data.WEAPONS.rocket.damage)
	else:
		radius = float(Data.GRENADE.radius)
		max_dmg = float(Data.GRENADE.damage)
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
		if eid == proj.owner_id:
			dmg *= 0.5
		_server_damage(p, dmg, proj.owner_id, proj.kind, false, pos)


func _server_pickups(t: float) -> void:
	for i in pickup_nodes.size():
		var node := pickup_nodes[i]
		if not node.active:
			if t >= _pickup_ready_at[i]:
				_broadcast(&"_s_pickup_state", [i, true])
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
					if p.health >= Data.MAX_HEALTH:
						continue
					_broadcast(&"_s_health", [eid, minf(Data.MAX_HEALTH, p.health + HEALTH_PICKUP)])
				"ammo":
					if not p.needs_ammo():
						continue
				"grenade":
					if int(_grenades.get(eid, 0)) >= int(Data.GRENADE.per_life):
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
			"headshots": s.headshots, "best_streak": s.best_streak, "bot": s.bot, "level": s.level})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.kills > b.kills if a.kills != b.kills else a.deaths < b.deaths)
	_broadcast(&"_s_match_end", [rows])
	get_tree().create_timer(RESULTS_TIME).timeout.connect(_on_results_timeout)


func _on_results_timeout() -> void:
	if is_inside_tree() and multiplayer.is_server():
		Net.next_match()


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
	for tid: int in hits:
		hit_list.append([tid, hits[tid][0], hits[tid][1]])
	if multiplayer.is_server():
		_server_shot(p.id, wid, ends, normals, hit_list)
	else:
		_c_shot.rpc_id(1, wid, ends, normals, hit_list)


func request_projectile(p: Player, kind: String, origin: Vector3, vel: Vector3) -> void:
	if p.mode == Player.Mode.LOCAL:
		Sfx.play(&"shot_rocket" if kind == "rocket" else &"grenade_throw", null, -2.0)
	if multiplayer.is_server():
		_server_projectile(p.id, kind, origin, vel)
	else:
		_c_projectile.rpc_id(1, kind, origin, vel)


func send_chat(text: String) -> void:
	if multiplayer.is_server():
		_server_chat(my_id(), text)
	else:
		_c_chat.rpc_id(1, text)


func _server_chat(sender: int, text: String) -> void:
	text = text.strip_edges().replace("[", "(").replace("]", ")").substr(0, MAX_CHAT_LENGTH)
	if text.is_empty() or not Net.players.has(sender):
		return
	_broadcast(&"_s_chat", [str(Net.players[sender].name), text])


func _play_shot_fx(p: Player, wid: String, ends: PackedVector3Array, normals: PackedVector3Array) -> void:
	var w: Dictionary = Data.WEAPONS[wid]
	var muzzle := p.muzzle_position()
	var is_local := p == local_player
	if wid == "knife":
		Sfx.play(&"knife_swing", null if is_local else p.global_position, -4.0)
		if normals.size() > 0 and normals[0] != Vector3.ZERO:
			Sfx.play(&"bullet_impact", ends[0], -6.0)
			fx.impact(ends[0], normals[0])
		return
	Sfx.play(StringName(w.sound), null if is_local else muzzle, -3.0 if is_local else 0.0)
	if not is_local:
		fx.muzzle_flash(muzzle)
	var tracer_every := 3 if int(w.pellets) > 1 else 1
	for i in ends.size():
		if i % tracer_every == 0:
			fx.tracer(muzzle, ends[i])
		if normals[i] != Vector3.ZERO:
			fx.impact(ends[i], normals[i])
	if not is_local and local_player != null and local_player.alive and ends.size() > 0:
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
	_s_scores.rpc_id(pid, scores)
	_s_clock.rpc_id(pid, time_left)
	for i in pickup_nodes.size():
		if not pickup_nodes[i].active:
			_s_pickup_state.rpc_id(pid, i, false)
	if match_over:
		_s_match_end.rpc_id(pid, results)
		return
	_server_add_entity(pid, Net.players[pid], false)
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


@rpc("authority", "call_remote", "reliable")
func _s_despawn(eid: int) -> void:
	var p: Player = entities.get(eid)
	if p == null:
		return
	entities.erase(eid)
	if p == local_player:
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


@rpc("authority", "call_remote", "unreliable")
func _s_shot_fx(shooter_id: int, wid: String, ends: PackedVector3Array, normals: PackedVector3Array) -> void:
	var p: Player = entities.get(shooter_id)
	if p != null and Data.WEAPONS.has(wid):
		_play_shot_fx(p, wid, ends, normals)


@rpc("authority", "call_remote", "reliable")
func _s_damaged(eid: int, hp: float, attacker_id: int, from_pos: Vector3) -> void:
	var p: Player = entities.get(eid)
	if p == null:
		return
	p.on_damaged(hp, attacker_id)
	if attacker_id != eid:
		fx.blood(p.global_position + Vector3.UP * 1.1)
	if p == local_player:
		hud.show_damage(from_pos)
		Sfx.play(&"hurt", null, -3.0)
		shake(0.25)


@rpc("authority", "call_remote", "reliable")
func _s_health(eid: int, hp: float) -> void:
	var p: Player = entities.get(eid)
	if p != null:
		p.health = hp


@rpc("authority", "call_remote", "reliable")
func _s_hit_confirm(head: bool, killed: bool, amount: float, pos: Vector3) -> void:
	hud.show_hitmarker(head, killed)
	hud.damage_number(pos, amount, head)
	Sfx.play(&"headshot" if head else &"hit_marker", null, -2.0)


@rpc("authority", "call_remote", "reliable")
func _s_killed(victim_id: int, killer_id: int, wid: String, head: bool) -> void:
	var victim: Player = entities.get(victim_id)
	if victim != null:
		fx.death_burst(victim.global_position + Vector3.UP * 0.9, Color(info_color(victim)))
		Sfx.play(&"death", victim.global_position)
		victim.die()
	hud.add_killfeed(display_name(killer_id), weapon_label(wid), display_name(victim_id), head, killer_id == victim_id)
	var me := my_id()
	if killer_id == me and victim_id != me:
		Sfx.play(&"kill_confirm", null, -1.0)
		var t := now()
		_my_multi = _my_multi + 1 if t - _my_last_kill < MULTI_KILL_WINDOW else 1
		_my_last_kill = t
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
		hud.show_death(display_name(killer_id) if killer_id != me else "", weapon_label(wid), Data.RESPAWN_TIME)


@rpc("authority", "call_remote", "reliable")
func _s_respawn(eid: int, pos: Vector3, p_yaw: float) -> void:
	var p: Player = entities.get(eid)
	if p == null:
		return
	p.respawn(pos, p_yaw)
	if p == local_player:
		hud.hide_death()
		Sfx.play(&"spawn", null, -6.0)


@rpc("authority", "call_remote", "reliable")
func _s_spawn_projectile(pid: int, kind: String, owner_id: int, origin: Vector3, vel: Vector3) -> void:
	var proj := Projectile.new()
	proj.setup(self, pid, kind, owner_id, origin, vel)
	add_child(proj)
	projectiles[pid] = proj
	if owner_id != my_id():
		Sfx.play(&"shot_rocket" if kind == "rocket" else &"grenade_throw", origin)


@rpc("authority", "call_remote", "reliable")
func _s_explode(pid: int, pos: Vector3) -> void:
	var proj: Projectile = projectiles.get(pid)
	if proj != null:
		projectiles.erase(pid)
		proj.queue_free()
	fx.explosion(pos)
	Sfx.play(&"explosion", pos, 2.0)
	if local_player != null:
		var d := local_player.global_position.distance_to(pos)
		shake(clampf(1.4 - d / 10.0, 0.0, 1.2))


@rpc("authority", "call_remote", "reliable")
func _s_pickup_state(index: int, is_active: bool) -> void:
	if index >= 0 and index < pickup_nodes.size():
		pickup_nodes[index].set_active(is_active)


@rpc("authority", "call_remote", "reliable")
func _s_pickup_taken(index: int, eid: int) -> void:
	if index < 0 or index >= pickup_nodes.size():
		return
	var node := pickup_nodes[index]
	node.set_active(false)
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
func _s_match_end(rows: Array) -> void:
	match_over = true
	results = rows
	var me := my_id()
	var placement := 0
	var mine: Dictionary = {}
	for i in rows.size():
		if int(rows[i].id) == me:
			placement = i + 1
			mine = rows[i]
	var rewards := {}
	if not mine.is_empty():
		rewards = Profile.record_match({
			"kills": mine.kills, "deaths": mine.deaths, "headshots": mine.headshots,
			"placement": placement, "players": rows.size(), "won": placement == 1,
			"best_streak": mine.best_streak,
		})
	Sfx.play(&"match_end")
	Sfx.play_music(&"results")
	hud.show_results(rows, placement, rewards, RESULTS_TIME)


# ================================================================ helpers

## Rocket Party / Snipers Only swap everyone's primary for this match.
static func _apply_loadout_mutator(info: Dictionary) -> Dictionary:
	var forced := ""
	match str(Net.config.mutator):
		"rocket_party": forced = "rocket"
		"snipers": forced = "sniper"
	if forced.is_empty():
		return info
	var out := info.duplicate()
	out.primary = forced
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
		env.glow_enabled = true


static func weapon_label(wid: String) -> String:
	match wid:
		"grenade": return "Grenade"
		"fall": return "Gravity"
	return str(Data.WEAPONS[wid].name) if Data.WEAPONS.has(wid) else wid


static func info_color(p: Player) -> Color:
	var outfit: Dictionary = Data.OUTFITS.get(str(p.info.outfit), Data.OUTFITS.classic)
	return outfit.shirt
