class_name Sprays
extends Node
## Sprays: World's child "Sprays" on every peer (`World.sprays`). A living player presses `spray`
## (Y) to paint their equipped spray (`peer_info.spray`, a Data.SPRAYS id; art in SprayArt) on
## the world surface they aim at within RANGE m. The server checks it (alive, match running, in
## reach, COOLDOWN since that player's last spray), picks the spray from the player's own info
## (never from the request) and sends it to every peer; each player has one spray up at a time,
## so a new one replaces their old one. Late joiners get every spray that is up (server_sync).
## Sprays belong to the match: the next match builds a new World, so they start clean. Bots don't
## spray. Purely cosmetic: a spray blocks nothing.

## Server, every spray it accepted or refused ("" reason when accepted), for checks.
signal judged(owner_id: int, reason: String)

const RANGE := 4.0
const COOLDOWN := 10.0
## Decal width and height (m) and projection depth (half in front of the wall, half behind).
const SIZE := 1.1
const DEPTH := 0.5
## Emission the decal gets at night / sunset, so a spray still reads in the dark.
const GLOW := {"day": 0.0, "sunset": 0.15, "night": 0.45}

var world: World
## Every peer: owner id -> {id, pos, normal, up} of the sprays up.
var sprays := {}
## Local player: World.now() before which the server would refuse a new spray (for the HUD).
var ready_at := 0.0

var _decals := {}
## Server: owner id -> World.now() of their last accepted spray.
var _last := {}


func _init() -> void:
	name = "Sprays"


# ================================================================ local

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("spray"):
		return
	var p := world.local_player
	if p == null or not p.alive or world.input_blocked():
		return
	get_viewport().set_input_as_handled()
	spray_from_aim(p)


## Sprays where the local player `p` aims. Returns false (with a HUD note) when nothing is in
## reach or the cooldown is still running.
func spray_from_aim(p: Player) -> bool:
	var left := ready_at - World.now()
	if left > 0.0:
		world.hud.small_message("SPRAY READY IN %d S" % ceili(left), false)
		Sfx.play(&"ui_error", null, -8.0)
		return false
	var aim := p.aim_transform()
	var q := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * RANGE, Player.MASK_WORLD, p.exclude_rids())
	var r := world.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		world.hud.small_message("NOTHING TO SPRAY ON", false)
		return false
	ready_at = World.now() + COOLDOWN
	if multiplayer.is_server():
		_server_spray(p.id, r.position, r.normal)
	else:
		_c_spray.rpc_id(1, r.position, r.normal)
	return true


# ================================================================ server

## Checks a spray and sends it to everyone; returns "" or why it was refused.
func _server_spray(owner_id: int, pos: Vector3, normal: Vector3) -> String:
	var reason := _check(owner_id, pos, normal)
	judged.emit(owner_id, reason)
	if not reason.is_empty():
		return reason
	var p: Player = world.entities[owner_id]
	var t := World.now()
	_last[owner_id] = t
	normal = normal.normalized()
	# The picture's top: up the wall, or away from the sprayer on a floor or ceiling.
	var up := Vector3.UP - normal * normal.dot(Vector3.UP)
	if absf(normal.y) > 0.7:
		var away := pos - p.global_position
		up = away - normal * normal.dot(away)
	up = up.normalized() if up.length() > 0.01 else Vector3.FORWARD
	var sid := str(p.info.get("spray", "gg"))
	for pid: int in world.ready_peer_ids():
		_s_spray.rpc_id(pid, owner_id, sid, pos, normal, up)
	_s_spray(owner_id, sid, pos, normal, up)
	return ""


func _check(owner_id: int, pos: Vector3, normal: Vector3) -> String:
	var p: Player = world.entities.get(owner_id)
	if p == null or not p.alive:
		return "not alive"
	if world.match_over:
		return "match over"
	if not Data.SPRAYS.has(str(p.info.get("spray", ""))):
		return "no spray"
	if not is_finite(normal.length()) or normal.length() < 0.5 or not pos.is_finite():
		return "bad surface"
	# Reach from the eye, with slack for the eye moving (crouch, lean) and lag.
	if pos.distance_to(p.global_position + Vector3.UP * 1.6) > RANGE + 1.0:
		return "too far"
	if World.now() - float(_last.get(owner_id, -1000.0)) < COOLDOWN - 0.25:
		return "cooldown"
	return ""


## A peer that just loaded the match gets every spray that is up.
func server_sync(pid: int) -> void:
	for owner_id: int in sprays:
		var s: Dictionary = sprays[owner_id]
		_s_spray.rpc_id(pid, owner_id, s.id, s.pos, s.normal, s.up)


# ================================================================ RPCs

@rpc("any_peer", "call_remote", "reliable")
func _c_spray(pos: Vector3, normal: Vector3) -> void:
	if multiplayer.is_server():
		_server_spray(multiplayer.get_remote_sender_id(), pos, normal)


## A spray went up: it replaces the owner's previous one.
@rpc("authority", "call_remote", "reliable")
func _s_spray(owner_id: int, sid: String, pos: Vector3, normal: Vector3, up: Vector3) -> void:
	if not Data.SPRAYS.has(sid):
		sid = "gg"
	sprays[owner_id] = {"id": sid, "pos": pos, "normal": normal, "up": up}
	var d: Decal = _decals.get(owner_id)
	if d == null:
		d = Decal.new()
		d.size = Vector3(SIZE, DEPTH, SIZE)
		d.cull_mask = 1
		d.upper_fade = 0.0
		d.lower_fade = 0.0
		# Faces turned away from the spray (the sides of a block at a corner) fade out.
		d.normal_fade = 0.5
		d.emission_energy = float(GLOW.get(str(Net.config.get("time_of_day", "day")), 0.0))
		add_child(d)
		_decals[owner_id] = d
	var tex := SprayArt.texture(sid)
	d.texture_albedo = tex
	d.texture_emission = tex
	# The decal projects along its -Y; the texture's top is its -Z.
	var y := normal.normalized()
	var z := -up
	d.global_transform = Transform3D(Basis(y.cross(z), y, z).orthonormalized(), pos)
	if multiplayer.get_unique_id() == owner_id:
		ready_at = World.now() + COOLDOWN
	Sfx.play(&"spray", pos, -4.0)
