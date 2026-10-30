class_name Tactical
extends MatchMode
## Tactical mode (`Net.config.mode == "tactical"`): 25 v 25 in the Block HQ building, one life
## each, weapons found on the floor. World's MatchMode (child "Tactical") when the mode is on;
## besides the MatchMode hooks (teams via `Teams`, spawns, no respawns, friendly fire off, the
## end of the match) it owns the mode's own state and RPCs:
##   - teams (Player.info.team: 0 ALPHA west, 1 BRAVO east), set by the server at spawn;
##   - the phase: PLANNING (teams held behind barriers in their staging rooms) -> FIGHT -> OVER;
##   - weapon spots (map pickups of kind "weapon" plus guns dropped by the dead), each holding
##     one weapon id or "" when empty;
##   - team markers (ATTACK / HOLD points humans place on the floor plan);
##   - bot squads that follow routes through the building or their team's markers;
##   - spectating living teammates after death (client).
## Same naming as World: `_s_*` server -> peers, `_c_*` client -> server, `server_*` server only.

const Gen := preload("res://scripts/world/maps/building_map.gd")

const PLAYERS := 50
const TEAM_SIZE := 25
const PLANNING_TIME := 30.0
## Relative chance of each gun on a weapon spot (default 1): launchers and snipers are rare.
const WEAPON_WEIGHTS := {"rocket": 0.15, "sniper": 0.45, "lmg": 0.7, "dmr": 0.8}
## How much bots want each gun when deciding whether to swap what they carry for it.
const BOT_RATING := {
	"rifle": 6, "burst_rifle": 6, "lmg": 5, "smg": 5, "dmr": 4, "shotgun": 4, "sniper": 2, "rocket": 1,
	"machine_pistol": 4, "revolver": 3, "burst_pistol": 3, "sawed_off": 3, "suppressed": 2, "pistol": 2,
}
## Walking onto a spot takes its weapon into an empty slot; INTERACT_RADIUS is the reach of the
## "interact" key, which swaps it for the weapon already in that slot.
const PICKUP_RADIUS := 1.2
const INTERACT_RADIUS := 2.2
const PICKUP_CHECK := 0.1
const MARKER_KINDS: Array[String] = ["attack", "hold"]
const MAX_MARKERS_PER_PLAYER := 3
const SQUAD_SIZE := 5
const SQUAD_TICK := 0.5
## A squad moves on from a waypoint once this share of its ready members is within REACH of it,
## after holding there for HOLD_TIME seconds (longer after contact).
const SQUAD_GATHER := 0.6
const SQUAD_REACH := 6.0
const HOLD_TIME := Vector2(3.0, 6.0)
const CONTACT_HOLD := 4.0
## Seconds a squad waits at one waypoint at most before moving on regardless.
const SQUAD_STALL := 25.0
## Bots look for a gun for this long after the barriers drop before they join their squad
## unarmed (they still grab one they pass).
const LOOT_TIME := 35.0
## Squads stop following routes and hunt the survivors once this few enemies are left, or this
## long into the fight.
const HUNT_ENEMIES := 4
const HUNT_AFTER := 180.0
## Seconds of death cam before the view moves to a living teammate.
const SPECTATE_DELAY := 3.0

enum Phase { PLANNING, FIGHT, OVER }

class Squad:
	var team := 0
	var members: Array[int] = []
	var route: Array[Vector3] = []
	var route_name := ""
	var index := 0
	## World.now() when the hold at the current waypoint ends (0: not holding yet).
	var hold_until := 0.0
	## World.now() when the squad last moved on to a new waypoint.
	var moved_on := 0.0
	var last_contact := -100.0
	var marker_id := -1
	var hunting := false
	var order := Vector3.ZERO
	var holding := false

var phase := Phase.PLANNING
## World.now() when the planning phase ends (every peer counts down from the server's value).
var planning_ends := 0.0
## World.now() when the fight began.
var fight_started := 0.0
## Weapon spots: [{pos: Vector3, wid: String}]; the index is the spot id on every peer.
var spots: Array = []
var spot_nodes: Array[WeaponPickup] = []
## Markers this peer shows (its own team's): [{id, team, owner, kind, pos, name}].
var team_markers: Array = []
## Grid (0, 0, 0) corner in world space.
var origin := Vector3.ZERO
var overlay: TacticalOverlay
## Client: who the camera follows while this player is dead (null until spectating).
var spectating: Player

# Server only.
var _markers: Array = []
var _next_marker_id := 1
var _squads: Array = []
var _squad_of := {}
## Spot index -> bot entity id heading for it.
var _claims := {}
var _loot_until := {}
var _spawn_next: Array[int] = [0, 0]
var _pickup_timer := 0.0
var _squad_timer := 0.0
var _rng := RandomNumberGenerator.new()

var _barriers: Array[Node3D] = []
var _spec_cam: Camera3D
var _dead_since := -1.0


func _init() -> void:
	name = "Tactical"


func _ready() -> void:
	origin = world.map_info.bounds.position
	_rng.randomize()
	for team in 2:
		_build_barrier(team)
	for pick: Dictionary in world.map_info.pickups:
		if pick.kind == "weapon":
			_add_spot(pick.pos, "")
	overlay = TacticalOverlay.new()
	overlay.name = "TacticalOverlay"
	overlay.setup(self)
	add_child(overlay)
	_spec_cam = Camera3D.new()
	_spec_cam.name = "SpectateCam"
	_spec_cam.near = 0.05
	_spec_cam.far = 400.0
	_spec_cam.top_level = true
	add_child(_spec_cam)
	if multiplayer.is_server():
		planning_ends = World.now() + PLANNING_TIME
		for i in spots.size():
			spots[i].wid = _roll_weapon()
			spot_nodes[i].set_weapon(spots[i].wid)


# ================================================================ queries (every peer)

static func is_active() -> bool:
	return str(Net.config.get("mode", "ffa")) == "tactical"


func is_planning() -> bool:
	return phase == Phase.PLANNING


func fighting() -> bool:
	return phase == Phase.FIGHT


func planning_left() -> float:
	return maxf(0.0, planning_ends - World.now()) if phase == Phase.PLANNING else 0.0


func clock_running() -> bool:
	return fighting()


func attacks_blocked() -> bool:
	return is_planning()


## One life: no respawns.
func respawn_delay() -> float:
	return -1.0


## Teams wait out the planning phase behind barriers instead.
func spawn_protection() -> bool:
	return false


## No next match on a timer: the results screen offers NEW GAME (request_new_game).
func has_next_match() -> bool:
	return false


func team_of(eid: int) -> int:
	return Teams.of(world.entities.get(eid))


func my_team() -> int:
	return team_of(world.my_id())


static func slot_of(wid: String) -> int:
	return 0 if str(Data.WEAPONS[wid].slot) == "primary" else 1


## Storey (0-2) a world position is on.
func floor_of(pos: Vector3) -> int:
	var y := pos.y - origin.y
	var f := 0
	for i in Gen.FLOORS.size():
		if y >= Gen.FLOORS[i] - 1.5:
			f = i
	return f


## World position of grid cell (x, storey, z) for `team` (team 1 sees the building mirrored).
func grid_to_world(c: Vector3i, team: int) -> Vector3:
	var x := c.x if team == 0 else Gen.SIZE.x - 1 - c.x
	return origin + Vector3(x + 0.5, Gen.FLOORS[c.y], c.z + 0.5)


## Nearest spot holding a weapon within `radius` (horizontal, same storey), or -1.
func spot_near(pos: Vector3, radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in spots.size():
		if str(spots[i].wid).is_empty():
			continue
		var sp: Vector3 = spots[i].pos
		if absf(sp.y - pos.y) > 1.6:
			continue
		var d := Vector2(sp.x - pos.x, sp.z - pos.z).length()
		if d <= best_d:
			best_d = d
			best = i
	return best


# ================================================================ server: match flow (World hooks)

## The info a player spawns with in Tactical: on `team`, with empty weapon slots.
func prepare_info(info: Dictionary, team: int) -> Dictionary:
	var out := info.duplicate()
	out.team = team
	out.primary = ""
	out.secondary = ""
	return out


## [feet position, yaw] in `team`'s staging room, facing the enemy end.
func spawn_point(_eid: int, team: int) -> Array:
	var mine: Array[Vector3] = []
	var centre := world.map_info.bounds.get_center()
	for s: Vector3 in world.map_info.spawns:
		if (s.x < centre.x) == (team == 0):
			mine.append(s)
	var pick: Vector3 = mine[_spawn_next[team] % mine.size()]
	_spawn_next[team] += 1
	# Facing +X (team 0) is yaw -PI/2; facing -X is +PI/2.
	return [pick, -PI * 0.5 if team == 0 else PI * 0.5]


## Keeps each team at TEAM_SIZE: bots fill the slots humans don't. New bots only join during
## planning; later a human takes over a living bot instead (server_human_joined).
func server_balance() -> void:
	if world.match_over:
		return
	for team in 2:
		var bots: Array[int] = []
		var humans := 0
		for eid: int in world.entities:
			if team_of(eid) != team:
				continue
			if eid < 0:
				bots.append(eid)
			else:
				humans += 1
		var want := maxi(0, TEAM_SIZE - humans)
		while bots.size() > want:
			var eid: int = _bot_to_drop(bots)
			bots.erase(eid)
			world.server_remove_bot(eid)
		while bots.size() < want and phase == Phase.PLANNING:
			bots.append(world.server_add_bot(team))


## Dead bots first, then the most recently added.
func _bot_to_drop(bots: Array[int]) -> int:
	for eid in bots:
		if not world.entities[eid].alive:
			return eid
	var lowest: int = bots[0]
	for eid in bots:
		lowest = mini(lowest, eid)
	return lowest


## A human finished loading. During planning they join the smaller human side and a bot makes
## room; later they take over a living bot of that side (its position, health and weapons), or
## spectate if their side has no bots left.
func server_human_joined(pid: int) -> void:
	_sync_peer(pid)
	var team := server_team_for(false)
	if phase == Phase.PLANNING:
		world.server_add_human(pid, team, true)
		server_balance()
	else:
		var host := _living_bot(team)
		if host == null:
			world.server_add_human(pid, team, false)
		else:
			var pos := host.global_position
			var yaw := host.yaw
			var hp := host.health
			var held := host.slots.duplicate()
			world.server_remove_bot(host.id)
			world.server_add_human(pid, team, true)
			_take_over(pid, pos, yaw, hp, held)
	_send_markers()


## A human left mid-match: a bot takes their place if they were alive.
func server_human_left(pid: int) -> void:
	var p: Player = world.entities.get(pid)
	if p != null and p.alive and phase != Phase.OVER and not world.match_over:
		var pos := p.global_position
		var yaw := p.yaw
		var hp := p.health
		var held := p.slots.duplicate()
		var team := team_of(pid)
		world.server_remove_entity(pid)
		var bot := world.server_add_bot(team)
		_take_over(bot, pos, yaw, hp, held)
		var sq: Squad = _nearest_squad(team, pos)
		if sq != null:
			sq.members.append(bot)
			_squad_of[bot] = sq
	else:
		world.server_remove_entity(pid)
	_markers = _markers.filter(func(m: Dictionary) -> bool: return int(m.owner) != pid)
	_send_markers()
	server_check_end()


func _take_over(eid: int, pos: Vector3, yaw: float, hp: float, held: Array) -> void:
	world.server_place(eid, pos, yaw)
	for slot in 2:
		if not str(held[slot]).is_empty():
			_broadcast(&"_s_give", [eid, slot, str(held[slot])])
	world.server_set_health(eid, hp)


func _living_bot(team: int) -> Player:
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if eid < 0 and p.alive and team_of(eid) == team:
			return p
	return null


## After a kill: the victim drops their best gun where they fell, and a wiped-out team ends it.
func server_on_kill(victim_id: int, _killer_id: int, _wid: String) -> void:
	var victim: Player = world.entities.get(victim_id)
	if victim != null:
		var drop := victim.slots[0] if not victim.slots[0].is_empty() else victim.slots[1]
		if not drop.is_empty():
			_server_new_spot(victim.global_position + Vector3.UP * 0.05, drop)
	_release_claims(victim_id)
	server_check_end()


func server_check_end() -> void:
	if world.match_over or phase == Phase.OVER:
		return
	var counts := Teams.counts(world, true)
	if counts[0] == 0 or counts[1] == 0:
		world.server_end_match()


## 0 / 1 for the winning team, -1 for a draw: the side with players left (at the time limit, the
## side with more of them).
func server_winner() -> int:
	var counts := Teams.counts(world, true)
	if counts[0] == counts[1]:
		return -1
	return 0 if counts[0] > counts[1] else 1


## Rows carry each player's team, whether they survived and whether their team won; the winning
## team first, survivors before the fallen, then by kills. Returns {winner} (0, 1, -1 draw).
func server_finish(rows: Array) -> Dictionary:
	var winner := server_winner()
	phase = Phase.OVER
	annotate_rows(rows)
	for r: Dictionary in rows:
		r.won = winner >= 0 and int(r.team) == winner
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.team != b.team:
			return a.team == winner or (winner < 0 and a.team < b.team)
		if a.alive != b.alive:
			return a.alive
		return a.kills > b.kills)
	return {"winner": winner}


func on_match_over() -> void:
	phase = Phase.OVER


## Results-screen NEW GAME (server): a fresh Tactical match for everyone.
func request_new_game() -> void:
	if multiplayer.is_server():
		Net.next_match()


# ================================================================ server: frame

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or world.match_over:
		return
	if phase == Phase.PLANNING:
		if World.now() >= planning_ends:
			_server_go()
		return
	_pickup_timer -= delta
	if _pickup_timer <= 0.0:
		_pickup_timer = PICKUP_CHECK
		_server_pickups()
	_squad_timer -= delta
	if _squad_timer <= 0.0:
		_squad_timer = SQUAD_TICK
		_server_squads()


func _server_go() -> void:
	_build_squads()
	for eid: int in world.entities:
		if eid < 0:
			_loot_until[eid] = World.now() + LOOT_TIME
	_broadcast(&"_s_phase", [Phase.FIGHT, 0.0])


func _server_pickups() -> void:
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if not p.alive:
			continue
		var i := spot_near(p.global_position, PICKUP_RADIUS)
		if i < 0:
			continue
		var wid: String = spots[i].wid
		var held := p.slots[slot_of(wid)]
		if held.is_empty() or (p.is_bot and _bot_rating(wid) > _bot_rating(held)):
			_server_take(i, p)


func _server_take(i: int, p: Player) -> void:
	var wid: String = spots[i].wid
	var slot := slot_of(wid)
	var dropped := p.slots[slot]
	if dropped == wid:
		return
	_broadcast(&"_s_give", [p.id, slot, wid])
	_broadcast(&"_s_spot", [i, spots[i].pos, dropped])
	_claims.erase(i)


func _server_new_spot(pos: Vector3, wid: String) -> void:
	_broadcast(&"_s_spot", [spots.size(), pos, wid])


func _roll_weapon() -> String:
	var total := 0.0
	var ids: Array[String] = []
	for id: String in Data.WEAPONS:
		if id != "knife":
			ids.append(id)
			total += float(WEAPON_WEIGHTS.get(id, 1.0))
	var r := _rng.randf() * total
	for id in ids:
		r -= float(WEAPON_WEIGHTS.get(id, 1.0))
		if r <= 0.0:
			return id
	return ids[-1]


static func _bot_rating(wid: String) -> int:
	return int(BOT_RATING.get(wid, 0)) if not wid.is_empty() else -1


func _spot_list() -> Array:
	var out: Array = []
	for s: Dictionary in spots:
		out.append([s.pos, s.wid])
	return out


## A newly loaded peer gets the phase, the weapon spots and (once on a team) its markers.
func _sync_peer(pid: int) -> void:
	_s_phase.rpc_id(pid, phase, maxf(0.0, planning_ends - World.now()))
	_s_spots.rpc_id(pid, _spot_list())


# ================================================================ server: markers

func _server_marker(owner_id: int, kind: String, pos: Vector3) -> void:
	var team := team_of(owner_id)
	if team < 0 or not MARKER_KINDS.has(kind) or world.match_over:
		return
	var b := world.map_info.bounds
	pos = pos.clamp(b.position, b.end)
	var own := _markers.filter(func(m: Dictionary) -> bool: return int(m.owner) == owner_id)
	if own.size() >= MAX_MARKERS_PER_PLAYER:
		_markers.erase(own[0])
	_markers.append({"id": _next_marker_id, "team": team, "owner": owner_id, "kind": kind, "pos": pos,
		"name": world.display_name(owner_id)})
	_next_marker_id += 1
	_send_markers()


func _server_marker_remove(sender: int, id: int) -> void:
	var team := team_of(sender)
	_markers = _markers.filter(func(m: Dictionary) -> bool: return int(m.id) != id or int(m.team) != team)
	_send_markers()


## Each peer only hears its own team's markers.
func _send_markers() -> void:
	for pid: int in world.ready_peer_ids():
		var t := team_of(pid)
		if t >= 0:
			_s_markers.rpc_id(pid, _markers_for(t))
	team_markers = _markers_for(my_team())
	if overlay != null:
		overlay.markers_changed()


func _markers_for(team: int) -> Array:
	return _markers.filter(func(m: Dictionary) -> bool: return int(m.team) == team)


# ================================================================ server: bot squads

func _build_squads() -> void:
	_squads.clear()
	_squad_of.clear()
	for team in 2:
		var bots: Array[int] = []
		for eid: int in world.entities:
			if eid < 0 and team_of(eid) == team:
				bots.append(eid)
		bots.sort()
		var order := range(Gen.ROUTES.size())
		order.shuffle()
		var n := 0
		while n * SQUAD_SIZE < bots.size():
			var sq := Squad.new()
			sq.team = team
			for k in range(n * SQUAD_SIZE, mini((n + 1) * SQUAD_SIZE, bots.size())):
				sq.members.append(bots[k])
				_squad_of[bots[k]] = sq
			var route_idx: int = order[n % order.size()]
			sq.route = _route(route_idx, team)
			sq.route_name = "route %d" % route_idx
			sq.order = sq.route[0]
			sq.moved_on = World.now()
			_squads.append(sq)
			n += 1


## A route from Gen.ROUTES played by `team`: through its own half to the centre, on through the
## mirrored half and into the enemy staging room.
func _route(idx: int, team: int) -> Array[Vector3]:
	var pts: Array = Gen.ROUTES[idx]
	var cells: Array[Vector3i] = []
	for c: Vector3i in pts:
		cells.append(c)
	for k in range(pts.size() - 2, -1, -1):
		var c: Vector3i = pts[k]
		cells.append(Vector3i(Gen.SIZE.x - 1 - c.x, c.y, c.z))
	cells.append(Vector3i(Gen.SIZE.x - 1 - 10, 0, 31))
	var out: Array[Vector3] = []
	for c in cells:
		out.append(NavigationServer3D.map_get_closest_point(world.map_info.nav_map, grid_to_world(c, team)))
	return out


func _nearest_squad(team: int, pos: Vector3) -> Squad:
	var best: Squad = null
	var best_d := INF
	for sq: Squad in _squads:
		if sq.team != team:
			continue
		var d := sq.order.distance_to(pos)
		if d < best_d:
			best_d = d
			best = sq
	return best


func _server_squads() -> void:
	var now := World.now()
	var counts := Teams.counts(world, true)
	_assign_markers()
	for sq: Squad in _squads:
		var alive: Array[Player] = []
		for eid in sq.members:
			var p: Player = world.entities.get(eid)
			if p != null and p.alive:
				alive.append(p)
				if p.brain != null and p.brain.target != null and now - p.brain.last_seen_time() < 1.0:
					sq.last_contact = now
		if alive.is_empty():
			continue
		var marker := _marker_by_id(sq.marker_id)
		if marker.is_empty():
			sq.marker_id = -1
		else:
			sq.order = NavigationServer3D.map_get_closest_point(world.map_info.nav_map, marker.pos)
			sq.holding = str(marker.kind) == "hold"
			continue
		var enemies_left: int = counts[1 - sq.team]
		if not sq.hunting and (sq.index >= sq.route.size() or enemies_left <= HUNT_ENEMIES or now - fight_started > HUNT_AFTER):
			sq.hunting = true
		if sq.hunting:
			sq.holding = false
			var target := _nearest_enemy(sq.team, _centroid(alive))
			if target != null:
				sq.order = target.global_position
			continue
		var wp: Vector3 = sq.route[sq.index]
		var ready := alive.filter(func(p: Player) -> bool: return not _wants_loot(p))
		var near := ready.filter(func(p: Player) -> bool: return p.global_position.distance_to(wp) < SQUAD_REACH).size()
		var gathered := not ready.is_empty() and near >= ceili(ready.size() * SQUAD_GATHER)
		if gathered:
			if sq.hold_until <= 0.0:
				sq.hold_until = now + _rng.randf_range(HOLD_TIME.x, HOLD_TIME.y)
			if now - sq.last_contact < 3.0:
				sq.hold_until = maxf(sq.hold_until, now + CONTACT_HOLD * 0.5)
		# Stragglers (or a fight that never ends) don't pin the squad to one waypoint forever.
		if (gathered and now >= sq.hold_until) or now - sq.moved_on > SQUAD_STALL:
			sq.index += 1
			sq.hold_until = 0.0
			sq.moved_on = now
		sq.holding = sq.hold_until > 0.0
		sq.order = sq.route[mini(sq.index, sq.route.size() - 1)]


## Human markers pull squads off their routes: an ATTACK marker takes the two nearest free
## squads, a HOLD marker one.
func _assign_markers() -> void:
	for sq: Squad in _squads:
		if sq.marker_id >= 0 and _marker_by_id(sq.marker_id).is_empty():
			sq.marker_id = -1
	for m: Dictionary in _markers:
		var want := 2 if str(m.kind) == "attack" else 1
		var have := 0
		for sq: Squad in _squads:
			if sq.marker_id == int(m.id):
				have += 1
		while have < want:
			var best: Squad = null
			var best_d := INF
			for sq: Squad in _squads:
				if sq.team != int(m.team) or sq.marker_id >= 0 or not _squad_alive(sq):
					continue
				var d := sq.order.distance_to(m.pos)
				if d < best_d:
					best_d = d
					best = sq
			if best == null:
				break
			best.marker_id = int(m.id)
			best.hunting = false
			have += 1


func _squad_alive(sq: Squad) -> bool:
	for eid in sq.members:
		var p: Player = world.entities.get(eid)
		if p != null and p.alive:
			return true
	return false


func _marker_by_id(id: int) -> Dictionary:
	if id < 0:
		return {}
	for m: Dictionary in _markers:
		if int(m.id) == id:
			return m
	return {}


static func _centroid(players: Array[Player]) -> Vector3:
	var c := Vector3.ZERO
	for p in players:
		c += p.global_position
	return c / maxf(1.0, players.size())


func _nearest_enemy(team: int, from: Vector3) -> Player:
	var best: Player = null
	var best_d := INF
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if not p.alive or team_of(eid) == team or team_of(eid) < 0:
			continue
		var d := p.global_position.distance_squared_to(from) + absf(p.global_position.y - from.y) * 40.0
		if d < best_d:
			best_d = d
			best = p
	return best


func _wants_loot(p: Player) -> bool:
	if not p.slots[0].is_empty():
		return false
	return World.now() < float(_loot_until.get(p.id, 0.0))


## Nearest free weapon spot this bot could use (primary first), claimed for it; -1 if none.
func _claim_spot(p: Player) -> int:
	for i: int in _claims.keys():
		if _claims[i] == p.id:
			if i < spots.size() and not str(spots[i].wid).is_empty():
				return i
			_claims.erase(i)
	var best := -1
	var best_d := INF
	for i in spots.size():
		var wid: String = spots[i].wid
		if wid.is_empty() or (_claims.has(i) and _claims[i] != p.id):
			continue
		var held := p.slots[slot_of(wid)]
		if not held.is_empty() and _bot_rating(wid) <= _bot_rating(held):
			continue
		var sp: Vector3 = spots[i].pos
		var d := sp.distance_to(p.global_position) + absf(sp.y - p.global_position.y) * 6.0
		if slot_of(wid) == 1:
			d += 15.0
		if d < best_d:
			best_d = d
			best = i
	if best >= 0 and best_d < 70.0:
		_claims[best] = p.id
		return best
	return -1


func _release_claims(eid: int) -> void:
	for i: int in _claims.keys():
		if _claims[i] == eid:
			_claims.erase(i)


## What a roaming bot should do now: {pos, hold (crouch and watch on arrival), sprint, look}.
func bot_order(p: Player) -> Dictionary:
	var here := p.global_position
	var forward := here + Vector3(1.0 if Teams.of(p) == 0 else -1.0, 0.0, 0.0) * 10.0 + Vector3.UP * 1.5
	if phase == Phase.PLANNING:
		return {"pos": here, "hold": false, "sprint": false, "look": forward}
	if _wants_loot(p) or (p.slots[0].is_empty() and spot_near(here, 14.0) >= 0):
		var i := _claim_spot(p)
		if i >= 0:
			return {"pos": spots[i].pos, "hold": false, "sprint": true, "look": forward}
	var sq: Squad = _squad_of.get(p.id)
	if sq == null:
		var enemy := _nearest_enemy(Teams.of(p), here)
		return {"pos": enemy.global_position if enemy != null else here, "hold": false, "sprint": false, "look": forward}
	# Formation: members spread across the objective so they don't stack in one doorway.
	var k := sq.members.find(p.id)
	var side := Vector3(0.0, 0.0, 1.0) * ((k % SQUAD_SIZE) - 2) * 1.4
	var pos := NavigationServer3D.map_get_closest_point(world.map_info.nav_map, sq.order + side)
	if pos.distance_to(sq.order) > 3.0:
		pos = sq.order
	var look := forward
	if not sq.hunting and sq.marker_id < 0 and sq.index + 1 < sq.route.size():
		look = sq.route[sq.index + 1] + Vector3.UP * 1.5
	var marker := _marker_by_id(sq.marker_id)
	var rushing := sq.hunting or (not marker.is_empty() and str(marker.kind) == "attack")
	return {"pos": pos, "hold": sq.holding, "sprint": rushing, "look": look}


## Debug/inspection: [route name, waypoint index, route length, hunting, marker] per squad.
func squad_summary() -> Array:
	var out: Array = []
	for sq: Squad in _squads:
		out.append([sq.team, sq.route_name, sq.index, sq.route.size(), sq.hunting, sq.marker_id, sq.members.size()])
	return out


# ================================================================ local requests

## Interact key: swap the weapon on the nearest spot for the one in that slot.
func request_interact() -> void:
	if multiplayer.is_server():
		_server_interact(world.my_id())
	else:
		_c_interact.rpc_id(1)


func request_marker(kind: String, pos: Vector3) -> void:
	if multiplayer.is_server():
		_server_marker(world.my_id(), kind, pos)
	else:
		_c_marker.rpc_id(1, kind, pos)


func request_marker_remove(id: int) -> void:
	if multiplayer.is_server():
		_server_marker_remove(world.my_id(), id)
	else:
		_c_marker_remove.rpc_id(1, id)


func _server_interact(eid: int) -> void:
	var p: Player = world.entities.get(eid)
	if p == null or not p.alive or world.match_over:
		return
	var i := spot_near(p.global_position, INTERACT_RADIUS)
	if i >= 0:
		_server_take(i, p)


# ================================================================ RPC: client -> server

@rpc("any_peer", "call_remote", "reliable")
func _c_interact() -> void:
	if multiplayer.is_server():
		_server_interact(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _c_marker(kind: String, pos: Vector3) -> void:
	if multiplayer.is_server():
		_server_marker(multiplayer.get_remote_sender_id(), kind, pos)


@rpc("any_peer", "call_remote", "reliable")
func _c_marker_remove(id: int) -> void:
	if multiplayer.is_server():
		_server_marker_remove(multiplayer.get_remote_sender_id(), id)


# ================================================================ RPC: server -> peers

@rpc("authority", "call_remote", "reliable")
func _s_phase(p: int, left: float) -> void:
	phase = p as Phase
	planning_ends = World.now() + left
	if phase != Phase.PLANNING:
		fight_started = World.now()
		for b in _barriers:
			b.queue_free()
		_barriers.clear()
		if phase == Phase.FIGHT:
			Sfx.play(&"match_start")
			world.hud.announce("GO GO GO")
	if overlay != null:
		overlay.phase_changed()


@rpc("authority", "call_remote", "reliable")
func _s_spots(list: Array) -> void:
	for i in list.size():
		_s_spot(i, list[i][0], str(list[i][1]))


@rpc("authority", "call_remote", "reliable")
func _s_spot(index: int, pos: Vector3, wid: String) -> void:
	if not wid.is_empty() and not Data.WEAPONS.has(wid):
		return
	while spots.size() <= index:
		_add_spot(pos, "")
	spots[index].pos = pos
	spots[index].wid = wid
	spot_nodes[index].position = pos
	spot_nodes[index].set_weapon(wid)


@rpc("authority", "call_remote", "reliable")
func _s_give(eid: int, slot: int, wid: String) -> void:
	var p: Player = world.entities.get(eid)
	if p == null or slot < 0 or slot > 1 or not Data.WEAPONS.has(wid):
		return
	p.give_weapon(slot, wid)
	if p == world.local_player:
		Sfx.play(&"weapon_switch", null, -2.0)
		overlay.toast("PICKED UP %s" % str(Data.WEAPONS[wid].name).to_upper())
	else:
		Sfx.play(&"pickup_ammo", p.global_position, -10.0)


@rpc("authority", "call_remote", "reliable")
func _s_markers(list: Array) -> void:
	team_markers = list
	if overlay != null:
		overlay.markers_changed()


# ================================================================ visuals and spectating (every peer)

func _add_spot(pos: Vector3, wid: String) -> void:
	spots.append({"pos": pos, "wid": wid})
	var node := WeaponPickup.new()
	node.position = pos
	add_child(node)
	node.set_weapon(wid)
	spot_nodes.append(node)


## Glowing walls across the staging room exits; gone when planning ends.
func _build_barrier(team: int) -> void:
	var body := StaticBody3D.new()
	body.name = "Barrier%d" % team
	body.collision_layer = 1
	body.collision_mask = 0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(Teams.color(team), 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for box: Array in Gen.BARRIERS:
		var a: Vector3i = box[0]
		var b: Vector3i = box[1]
		var lo := Vector3(a)
		var hi := Vector3(b) + Vector3.ONE
		if team == 1:
			lo.x = Gen.SIZE.x - 1 - b.x
			hi.x = Gen.SIZE.x - a.x
		var shape := BoxShape3D.new()
		shape.size = hi - lo
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = origin + (lo + hi) * 0.5
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = shape.size * Vector3(1.0, 1.0, 1.0) - Vector3(0.0, 0.02, 0.0)
		mesh.material = mat
		mi.mesh = mesh
		mi.position = cs.position
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
	add_child(body)
	_barriers.append(body)


## Team look (MatchMode/Teams); Tactical nametags show just the name (no level), since 50
## players crowd the building.
func on_player_added(p: Player) -> void:
	super(p)
	if p.nametag != null:
		p.nametag.text = str(p.info.name)


## Client: the local player died; after a short death cam the camera follows teammates.
func on_local_death(_killer_id: int) -> void:
	_dead_since = World.now()


## Living players per team against the full team.
func hud_bars() -> Array:
	var counts := Teams.counts(world, true)
	return [[float(counts[0]) / TEAM_SIZE, str(counts[0])], [float(counts[1]) / TEAM_SIZE, str(counts[1])]]


func hud_goal() -> String:
	var team := my_team()
	return "" if team < 0 else "Your team: %s  ·  last team standing wins" % Teams.name_of(team)


func row_tag(r: Dictionary) -> String:
	return "" if bool(r.get("alive", true)) else "KIA"


func row_dimmed(r: Dictionary) -> bool:
	return not bool(r.get("alive", true))


func _process(delta: float) -> void:
	var me := world.local_player
	if me == null or me.alive or _dead_since < 0.0:
		return
	# The winner's emote camera owns the view at the end of the match.
	if world.match_over and not _spec_cam.current:
		return
	if World.now() - _dead_since < SPECTATE_DELAY:
		return
	if spectating == null or not is_instance_valid(spectating) or not spectating.alive:
		_cycle_spectate(1)
	if spectating == null:
		return
	if not _spec_cam.current:
		_spec_cam.make_current()
		_spec_cam.fov = float(Profile.get_setting("fov"))
		world.hud.hide_death()
	_follow(spectating, delta)


## Living teammates first; anyone alive once the team is wiped out.
func _spectate_candidates() -> Array[Player]:
	var mine := my_team()
	var out: Array[Player] = []
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if p.alive and p != world.local_player and Teams.of(p) == mine:
			out.append(p)
	if out.is_empty():
		for eid: int in world.entities:
			var p: Player = world.entities[eid]
			if p.alive and p != world.local_player:
				out.append(p)
	out.sort_custom(func(a: Player, b: Player) -> bool: return a.id < b.id)
	return out


func _cycle_spectate(step: int) -> void:
	var list := _spectate_candidates()
	if list.is_empty():
		spectating = null
		return
	var i := list.find(spectating)
	spectating = list[posmod(i + step, list.size())] if i >= 0 else list[0]
	if overlay != null:
		overlay.spectate_changed()


func is_spectating() -> bool:
	return spectating != null and _spec_cam != null and _spec_cam.current


## Over-the-shoulder view along the target's aim, pulled in front of walls.
func _follow(p: Player, delta: float) -> void:
	var basis := Basis.from_euler(Vector3(p.pitch * 0.8, p.yaw, 0.0))
	var pivot := p.global_position + Vector3.UP * (p.body_center_height() + 0.55)
	var want := pivot + basis * Vector3(0.55, 0.3, 2.6)
	var q := PhysicsRayQueryParameters3D.create(pivot, want, Player.MASK_WORLD)
	var r := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		want = (r.position as Vector3).lerp(pivot, 0.12)
	var k := minf(1.0, delta * 10.0)
	_spec_cam.global_position = _spec_cam.global_position.lerp(want, k) if _spec_cam.global_position.distance_to(want) < 6.0 else want
	var look := pivot - basis.z * 30.0
	if _spec_cam.global_position.distance_squared_to(look) > 0.01:
		_spec_cam.look_at(look, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not is_spectating() or world.input_blocked():
		return
	if event.is_action_pressed("fire") or event.is_action_pressed("next_weapon"):
		_cycle_spectate(1)
	elif event.is_action_pressed("aim") or event.is_action_pressed("prev_weapon"):
		_cycle_spectate(-1)
