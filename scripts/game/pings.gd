class_name Pings
extends Node
## Quick ping: World's child "Pings" on every peer (`World.pings`), active in team modes only
## (`Teams.is_team_mode()`: Team Deathmatch, Infected, Tactical); in free-for-all modes the
## `ping` key does nothing. A player presses `ping` to mark what they aim at (up to RANGE m):
## an enemy (an enemy ping, at that enemy's position) or a spot. The server checks it (alive,
## in range, RATE limits) and relays it to the pinger's teammates only; each of them sees a
## marker with the distance and the pinger's name, a compass pip and a sound for LIFE seconds
## (a newer ping from the same player replaces the older one). Bots ping enemies they spot (at
## most every BOT_GAP seconds each, and not an enemy their team pinged in the last BOT_REPEAT
## seconds), and a teammate bot with nothing to fight goes to look at an enemy pinged near it.
## Pings last seconds, so a late joiner doesn't get the ones already up.

## Server, every relayed ping: who pinged, where, the enemy (0: a spot) and the peer ids it
## reached.
signal relayed(owner_id: int, pos: Vector3, target_id: int, recipients: Array)

const LIFE := 6.0
const RANGE := 150.0
## Rate limit per player: at least MIN_GAP seconds apart and at most BURST in BURST_WINDOW.
const MIN_GAP := 0.6
const BURST := 3
const BURST_WINDOW := 5.0
const BOT_GAP := 8.0
const BOT_REPEAT := 4.0
## A teammate bot without a target investigates an enemy ping this close (m).
const BOT_HEED_RANGE := 40.0
const ENEMY_COLOR := Color(1.0, 0.3, 0.2)
const SPOT_COLOR := Color(1.0, 0.85, 0.3)
## Ray mask: the world and hitboxes (Player.MASK_WORLD | Player.MASK_HITBOX).
const MASK := 1 | 4

var world: World
## Every peer: pings this player's team can see, each {owner, pos, target, until (World.now())}.
var pings: Array = []

var _overlay: PingOverlay
## Server: owner id -> World.now() of their recent accepted pings.
var _sent := {}
## Server: bot id -> World.now() before which it doesn't ping again.
var _bot_next := {}
## Server: "team:enemy id" -> World.now() of the last ping on that enemy by that team.
var _enemy_pinged := {}


func _init() -> void:
	name = "Pings"


static func active() -> bool:
	return Teams.is_team_mode()


func _ready() -> void:
	set_process(active())
	set_process_unhandled_input(active())
	if not active():
		return
	_overlay = PingOverlay.new()
	_overlay.name = "PingOverlay"
	_overlay.setup(self)
	add_child(_overlay)


# ================================================================ local

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ping"):
		return
	var p := world.local_player
	if p == null or not p.alive or world.input_blocked():
		return
	get_viewport().set_input_as_handled()
	ping_from_aim(p)


## Pings what `p` aims at: an enemy under the crosshair, else the spot the aim ray hits. Returns
## false when nothing is in range (or outside team modes).
func ping_from_aim(p: Player) -> bool:
	if not active():
		return false
	var aim := p.aim_transform()
	var q := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * RANGE, MASK, p.exclude_rids())
	q.collide_with_areas = true
	var r := world.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return false
	var hit: Object = r.collider
	var other: Player = hit.get_meta("player") if hit != null and hit.has_meta("player") else null
	if other != null and other.alive and world.is_enemy(p, other):
		request(p, other.global_position, other.id)
	else:
		request(p, r.position, 0)
	return true


## A LOCAL or BOT player pings `pos` (`target`: the enemy's entity id, 0 for a spot).
func request(p: Player, pos: Vector3, target: int) -> void:
	if multiplayer.is_server():
		_server_ping(p.id, pos, target)
	else:
		_c_ping.rpc_id(1, pos, target)


func _process(_delta: float) -> void:
	if pings.is_empty():
		return
	var t := World.now()
	pings = pings.filter(func(e: Dictionary) -> bool: return float(e.until) > t)


## Compass pips for the pings up: enemies red, spots gold.
func compass_pips(cam: Camera3D) -> Array:
	var out: Array = []
	for e: Dictionary in pings:
		var to: Vector3 = (e.pos as Vector3) - cam.global_position
		out.append([rad_to_deg(-atan2(-to.x, -to.z)), ENEMY_COLOR if int(e.target) != 0 else SPOT_COLOR])
	return out


func on_match_over() -> void:
	pings.clear()


# ================================================================ server

## Checks and relays a ping to the owner's team; returns whether it went out.
func _server_ping(owner_id: int, pos: Vector3, target: int) -> bool:
	var p: Player = world.entities.get(owner_id)
	if not active() or world.match_over or p == null or not p.alive:
		return false
	if pos.distance_to(p.global_position) > RANGE + 5.0:
		return false
	var t := World.now()
	var recent: Array = (_sent.get(owner_id, []) as Array).filter(func(at: float) -> bool: return t - at < BURST_WINDOW)
	if recent.size() >= BURST or (not recent.is_empty() and t - float(recent[-1]) < MIN_GAP):
		_sent[owner_id] = recent
		return false
	recent.append(t)
	_sent[owner_id] = recent
	var enemy: Player = world.entities.get(target) if target != 0 else null
	if enemy == null or not enemy.alive or not world.is_enemy(p, enemy):
		target = 0
	else:
		pos = enemy.global_position
		_enemy_pinged["%d:%d" % [Teams.of(p), target]] = t
	var recipients: Array = []
	var ready := world.ready_peer_ids()
	for eid: int in world.entities:
		var mate: Player = world.entities[eid]
		if not Teams.same(mate, p):
			continue
		if eid == world.my_id():
			_s_ping(owner_id, pos, target)
			recipients.append(eid)
		elif ready.has(eid):
			_s_ping.rpc_id(eid, owner_id, pos, target)
			recipients.append(eid)
		elif mate.brain != null and target != 0 and mate != p:
			mate.brain.heed_ping(pos)
	relayed.emit(owner_id, pos, target, recipients)
	return true


## Server, bots: `p` just spotted `enemy`.
func bot_spotted(p: Player, enemy: Player) -> void:
	if not active():
		return
	var t := World.now()
	if t < float(_bot_next.get(p.id, 0.0)):
		return
	if t - float(_enemy_pinged.get("%d:%d" % [Teams.of(p), enemy.id], -100.0)) < BOT_REPEAT:
		return
	if _server_ping(p.id, enemy.global_position, enemy.id):
		_bot_next[p.id] = t + BOT_GAP


# ================================================================ RPCs

@rpc("any_peer", "call_remote", "reliable")
func _c_ping(pos: Vector3, target: int) -> void:
	if multiplayer.is_server():
		_server_ping(multiplayer.get_remote_sender_id(), pos, target)


## A teammate's ping (only teammates receive it).
@rpc("authority", "call_remote", "reliable")
func _s_ping(owner_id: int, pos: Vector3, target: int) -> void:
	pings = pings.filter(func(e: Dictionary) -> bool: return int(e.owner) != owner_id)
	pings.append({"owner": owner_id, "pos": pos, "target": target, "until": World.now() + LIFE})
	Sfx.play(&"ping_enemy" if target != 0 else &"ping", null, -2.0)
