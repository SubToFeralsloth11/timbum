class_name Streaks
extends Node
## Killstreak rewards: World's child "Streaks" on every peer (`World.streaks`), active when
## `Net.config.streaks` is on (match setup's KILLSTREAKS row; `default_for(mode)`).
## The server counts the streak in `World.scores[eid].streak` (kills without dying; a kill by a
## reward, weapon id WEAPON, counts as a kill but never extends it) and grants:
##   - RADAR_AT kills: Radar Sweep. For RADAR_TIME seconds every living enemy shows on the
##     compass and as a marker on screen; in team modes for the whole team.
##   - SHIELD_AT kills: Overshield. `Player.shield` = SHIELD, soaked up by damage before health
##     (World._server_damage), shown on the health card.
##   - BOMBER_AT kills: Block Bomber, held until used. The `streak_reward` key opens targeting (the
##     strike line previewed on the ground), fire or the key again calls it on the aim point (aim
##     cancels). Every peer sees a BOMBER_DELAY ground warning, then BOMBER_BLASTS explosions
##     walk along the line, credited to the caller with WEAPON (World.server_blast; the caller is
##     never hurt by their own strike). Blasts overlap (BOMBER_SPACING < BOMBER_RADIUS), but each
##     victim takes at most one blast's damage per strike, the strongest: a later blast only adds
##     what it deals beyond the most an earlier blast of the same strike dealt them (the strike's
##     `hit` Dictionary, server only), so nobody takes more than BOMBER_DAMAGE from one strike.
## Death clears a player's radar, shield and unused bomber; the end of the match clears all.
## Naming as in World: `server_*` / `_server_*` on the server, `_s_*` server -> peers, `_c_*`
## client -> server.

signal rewarded(eid: int, kind: String, streak: int)

## Weapon id of a Block Bomber kill (kill feed, death screen, scores).
const WEAPON := "bomber"
const RADAR_AT := 3
const SHIELD_AT := 5
const BOMBER_AT := 7
const RADAR_TIME := 8.0
const SHIELD := 50.0
## Farthest aim point (m) a bomber can be called on.
const BOMBER_RANGE := 120.0
## Seconds of ground warning before the first blast, then one blast every BOMBER_INTERVAL.
const BOMBER_DELAY := 2.0
const BOMBER_INTERVAL := 0.16
const BOMBER_BLASTS := 5
## Metres between blasts along the line (from the caller toward the aim point, centred on it).
const BOMBER_SPACING := 4.0
const BOMBER_RADIUS := 5.0
const BOMBER_DAMAGE := 140.0
## Modes with killstreaks on unless match setup says otherwise.
const DEFAULT_MODES: Array[String] = ["ffa", "tdm", "koth"]
const REWARDS := {
	"radar": {"name": "RADAR SWEEP", "at": RADAR_AT, "color": Color(0.45, 1.0, 0.55),
		"desc": "Enemies on your compass for 8 s"},
	"shield": {"name": "OVERSHIELD", "at": SHIELD_AT, "color": Color(0.45, 0.85, 1.0),
		"desc": "+50 shield, soaks up damage first"},
	"bomber": {"name": "BLOCK BOMBER", "at": BOMBER_AT, "color": Color(1.0, 0.6, 0.25),
		"desc": "Airstrike ready"},
}
## The Block Bomber's targeting preview on the ground (strike warnings and radar contacts use
## Palette's "warning" and "radar" colours, which follow the colour mode).
const PREVIEW_COLOR := Color(1.0, 0.85, 0.2)
## Bots call their bomber on a target at least this far away (m).
const BOT_MIN_RANGE := 14.0

var world: World
## Every peer: entity id -> World.now() when its Radar Sweep ends.
var radar_until := {}
## Every peer: entity ids holding an unused Block Bomber.
var bomber_ready := {}
## Every peer: called strikes still landing, each {id, caller, points: PackedVector3Array,
## land_at (World.now() of the first blast), next (blasts done), marks: Array[Node3D], mat}.
var strikes: Array = []
## Local: aiming a Block Bomber (fire or the key calls it in, aim cancels).
var targeting := false

var _overlay: StreakOverlay
var _preview: Array[Node3D] = []
var _preview_mat: StandardMaterial3D
var _next_strike := 1
## Server: bot id -> World.now() from when it may call its bomber (a beat after earning it).
var _bot_call_at := {}


func _init() -> void:
	name = "Streaks"


static func enabled() -> bool:
	return bool(Net.config.get("streaks", false))


## Whether `mode` plays with killstreaks unless match setup turns them off (on) or on (off).
static func default_for(mode: String) -> bool:
	return DEFAULT_MODES.has(mode)


func _ready() -> void:
	set_process(enabled())
	set_physics_process(enabled() and multiplayer.is_server())
	set_process_unhandled_input(enabled())
	if not enabled():
		return
	_overlay = StreakOverlay.new()
	_overlay.name = "StreakOverlay"
	_overlay.setup(self)
	add_child(_overlay)


## Sends an RPC of this node to every peer that has loaded the world, then runs it here too.
func _broadcast(method: StringName, args: Array) -> void:
	for pid: int in world.ready_peer_ids():
		callv(&"rpc_id", [pid, method] + args)
	callv(method, args)


# ================================================================ queries (every peer)

## Seconds of Radar Sweep `viewer` sees by (their own, or a teammate's in team modes); 0: none.
func radar_left(viewer: Player) -> float:
	return _radar_left(viewer, true)


## Seconds an enemy's Radar Sweep still shows `viewer` to them; 0: none.
func enemy_radar_left(viewer: Player) -> float:
	return _radar_left(viewer, false)


## Screen y of the top of the streak status card (INF while hidden): the Hud's chat stays above it.
func card_top() -> float:
	return _overlay.card_top() if _overlay != null else INF


func _radar_left(viewer: Player, friendly: bool) -> float:
	if viewer == null or radar_until.is_empty():
		return 0.0
	var t := World.now()
	var best := 0.0
	for eid: int in radar_until:
		var left := float(radar_until[eid]) - t
		if left <= 0.0:
			continue
		var owner: Player = world.entities.get(eid)
		var mine := eid == viewer.id or (owner != null and Teams.same(owner, viewer))
		if mine == friendly and (friendly or owner == null or world.is_enemy(owner, viewer)):
			best = maxf(best, left)
	return best


func has_bomber(eid: int) -> bool:
	return bomber_ready.has(eid)


## Enemies the local player's radar shows (empty without a radar).
func radar_targets() -> Array[Player]:
	var out: Array[Player] = []
	var me := world.local_player
	if radar_left(me) <= 0.0:
		return out
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if p.alive and world.is_enemy(me, p):
			out.append(p)
	return out


## Compass pips: enemies under a Radar Sweep, and every strike still to land (the palette keeps
## the two colours apart in every colour mode, see Palette.GROUPS).
func compass_pips(cam: Camera3D) -> Array:
	var out: Array = []
	for p: Player in radar_targets():
		out.append([_heading(cam, p.global_position), Palette.color("radar")])
	for s: Dictionary in strikes:
		out.append([_heading(cam, strike_center(s)), Palette.color("warning")])
	return out


static func _heading(cam: Camera3D, pos: Vector3) -> float:
	var to := pos - cam.global_position
	return rad_to_deg(-atan2(-to.x, -to.z))


static func strike_center(s: Dictionary) -> Vector3:
	var pts: PackedVector3Array = s.points
	return pts[pts.size() / 2]


## The strike point still to land nearest within reach of `pos`: {pos, id (the strike), since
## (seconds since it was called)}, or {} when `pos` is safe. Bots run from it.
func danger_near(pos: Vector3) -> Dictionary:
	var t := World.now()
	for s: Dictionary in strikes:
		var pts: PackedVector3Array = s.points
		for i in range(int(s.next), pts.size()):
			var d := pts[i] - pos
			if Vector2(d.x, d.z).length() < BOMBER_RADIUS + 1.5 and absf(d.y) < 4.0:
				return {"pos": pts[i], "id": int(s.id), "since": t - (float(s.land_at) - BOMBER_DELAY)}
	return {}


## The line of blasts for a strike called from `from` on `at`: BOMBER_BLASTS points
## BOMBER_SPACING apart along the direction from the caller, centred on `at`, each dropped onto
## whatever is below it (a roof shelters the floor under it).
static func strike_points(space: PhysicsDirectSpaceState3D, from: Vector3, at: Vector3) -> PackedVector3Array:
	var dir := Vector3(at.x - from.x, 0.0, at.z - from.z)
	dir = dir.normalized() if dir.length() > 0.5 else Vector3.FORWARD
	var out := PackedVector3Array()
	for i in BOMBER_BLASTS:
		var p := at + dir * (i - (BOMBER_BLASTS - 1) * 0.5) * BOMBER_SPACING
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 12.0, p + Vector3.DOWN * 20.0, Player.MASK_WORLD)
		var r := space.intersect_ray(q)
		out.append((r.position as Vector3) + Vector3.UP * 0.3 if not r.is_empty() else p)
	return out


## Where `p` is aiming, up to BOMBER_RANGE (null: nothing in range).
func aim_point(p: Player) -> Variant:
	var aim := p.aim_transform()
	var q := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * BOMBER_RANGE, Player.MASK_WORLD, p.exclude_rids())
	var r := world.get_world_3d().direct_space_state.intersect_ray(q)
	return null if r.is_empty() else r.position


# ================================================================ every peer: events from World

## `eid` died or left: their radar, shield and unused bomber are gone (a called strike still lands).
func on_death(eid: int) -> void:
	radar_until.erase(eid)
	bomber_ready.erase(eid)
	_bot_call_at.erase(eid)
	if eid == world.my_id():
		targeting = false


func on_match_over() -> void:
	radar_until.clear()
	bomber_ready.clear()
	_bot_call_at.clear()
	targeting = false
	for p: Player in world.entities.values():
		p.shield = 0.0
	for s: Dictionary in strikes:
		_free_marks(s)
	strikes.clear()


# ================================================================ server

## After World counted a kill: grants the reward the killer's streak just reached.
func server_on_kill(victim_id: int, killer_id: int, wid: String) -> void:
	if not enabled() or world.match_over or killer_id == victim_id or wid == WEAPON:
		return
	var killer: Player = world.entities.get(killer_id)
	var s: Dictionary = world.scores.get(killer_id, {})
	if killer == null or not killer.alive or s.is_empty():
		return
	for kind: String in REWARDS:
		if int(s.streak) == int(REWARDS[kind].at):
			_broadcast(&"_s_reward", [killer_id, kind, int(s.streak)])


## A late joiner gets the radars, shields, bombers and strikes in progress.
func server_sync(pid: int) -> void:
	if not enabled():
		return
	var t := World.now()
	var radar := {}
	for eid: int in radar_until:
		if float(radar_until[eid]) > t:
			radar[eid] = float(radar_until[eid]) - t
	var shields := {}
	for eid: int in world.entities:
		if world.entities[eid].shield > 0.0:
			shields[eid] = world.entities[eid].shield
	var list: Array = []
	for s: Dictionary in strikes:
		list.append([s.id, s.caller, s.points, float(s.land_at) - t, s.next])
	_s_state.rpc_id(pid, radar, shields, bomber_ready.keys(), list)


## A LOCAL or BOT player calls in their Block Bomber on `point`.
func request_bomber(p: Player, point: Vector3) -> void:
	if multiplayer.is_server():
		_server_call(p.id, point)
	else:
		_c_call.rpc_id(1, point)


func _server_call(eid: int, point: Vector3) -> void:
	var p: Player = world.entities.get(eid)
	if not enabled() or p == null or not p.alive or world.match_over or world.attacks_blocked() or not bomber_ready.has(eid):
		return
	if point.distance_to(p.global_position) > BOMBER_RANGE + 5.0:
		return
	var points := strike_points(world.get_world_3d().direct_space_state, p.global_position, point)
	var id := _next_strike
	_next_strike += 1
	_broadcast(&"_s_strike", [id, eid, points, BOMBER_DELAY, 0])


## Server: blasts whose time has come.
func _physics_process(_delta: float) -> void:
	if world.match_over or strikes.is_empty():
		return
	var t := World.now()
	for s: Dictionary in strikes.duplicate():
		var pts: PackedVector3Array = s.points
		while int(s.next) < pts.size() and t >= float(s.land_at) + int(s.next) * BOMBER_INTERVAL:
			var i := int(s.next)
			_broadcast(&"_s_blast", [int(s.id), i, pts[i]])
			world.server_blast(pts[i], BOMBER_RADIUS, BOMBER_DAMAGE, int(s.caller), WEAPON, 0.0, s.hit)
			if world.match_over:
				return


## Server, bots: a bot holding a bomber calls it on `target` once it has held it a moment and the
## target is far enough away (and, in team modes, no teammate stands in the blast).
func bot_consider(p: Player, target: Player) -> void:
	if not bomber_ready.has(p.id) or World.now() < float(_bot_call_at.get(p.id, 0.0)):
		return
	var at := target.global_position
	var d := p.global_position.distance_to(at)
	if d < BOT_MIN_RANGE or d > BOMBER_RANGE:
		return
	for eid: int in world.entities:
		var mate: Player = world.entities[eid]
		if mate != p and mate.alive and Teams.same(mate, p) and mate.global_position.distance_to(at) < BOMBER_RADIUS + BOMBER_SPACING * 2.0:
			return
	_server_call(p.id, at)


## Bots: where a bot with a Radar Sweep should hunt (the nearest enemy it shows), else null.
func bot_radar_goal(p: Player) -> Variant:
	if radar_left(p) <= 0.0:
		return null
	var best: Player = null
	var best_d := INF
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if o.alive and world.is_enemy(p, o):
			var d := p.global_position.distance_squared_to(o.global_position)
			if d < best_d:
				best_d = d
				best = o
	return best.global_position if best != null else null


# ================================================================ local input and visuals

func _unhandled_input(event: InputEvent) -> void:
	var p := world.local_player
	if targeting:
		if event.is_action_pressed("fire") or event.is_action_pressed("streak_reward"):
			get_viewport().set_input_as_handled()
			call_bomber()
		elif event.is_action_pressed("aim"):
			targeting = false
		return
	if event.is_action_pressed("streak_reward") and can_target(p):
		get_viewport().set_input_as_handled()
		targeting = true
		Sfx.play(&"ui_click")


## Whether the local player `p` can start aiming a Block Bomber now.
func can_target(p: Player) -> bool:
	return p != null and p.alive and bomber_ready.has(p.id) and not world.input_blocked() and not world.attacks_blocked()


## Local: calls the bomber on the aim point (stays in targeting when nothing is in range).
func call_bomber() -> void:
	var p := world.local_player
	var point: Variant = aim_point(p) if p != null else null
	if point == null:
		Sfx.play(&"ui_error")
		return
	targeting = false
	request_bomber(p, point)


func _process(_delta: float) -> void:
	var p := world.local_player
	if targeting and not can_target(p):
		targeting = false
	var point: Variant = aim_point(p) if targeting else null
	_show_preview(p, point)
	var t := World.now()
	var pulse := 0.5 + 0.5 * sin(t * 14.0)
	for s: Dictionary in strikes.duplicate():
		# Clients drop a strike whose blasts never arrived (a dropped connection, a match end).
		var end := float(s.land_at) + BOMBER_BLASTS * BOMBER_INTERVAL + 3.0
		if t > end:
			_free_marks(s)
			strikes.erase(s)
			continue
		var mat: StandardMaterial3D = s.mat
		var urgency := clampf(1.0 - (float(s.land_at) - t) / BOMBER_DELAY, 0.0, 1.0)
		mat.albedo_color.a = 0.25 + 0.55 * pulse * (0.5 + 0.5 * urgency)


func _show_preview(p: Player, point: Variant) -> void:
	if point == null:
		for n in _preview:
			n.visible = false
		return
	if _preview.is_empty():
		_preview_mat = _warning_material(PREVIEW_COLOR)
		for i in BOMBER_BLASTS:
			var n := _make_mark(_preview_mat, false)
			_preview.append(n)
	var pts := strike_points(world.get_world_3d().direct_space_state, p.global_position, point)
	_preview_mat.albedo_color.a = 0.35 + 0.25 * sin(World.now() * 8.0)
	for i in pts.size():
		_preview[i].global_position = pts[i]
		_preview[i].visible = true


## One ground mark: a flat ring the size of the blast with a faint fill, and (warnings) a light
## beam into the sky so it reads from afar.
func _make_mark(mat: StandardMaterial3D, beam: bool) -> Node3D:
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = BOMBER_RADIUS - 0.35
	torus.outer_radius = BOMBER_RADIUS
	torus.rings = 32
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = mat
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var fill := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = BOMBER_RADIUS - 0.3
	disc.bottom_radius = BOMBER_RADIUS - 0.3
	disc.height = 0.04
	disc.radial_segments = 24
	disc.rings = 1
	fill.mesh = disc
	var fill_mat := mat.duplicate() as StandardMaterial3D
	fill_mat.albedo_color.a = 0.14
	fill.material_override = fill_mat
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill)
	if beam:
		var b := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.25
		cyl.height = 24.0
		cyl.radial_segments = 8
		cyl.rings = 1
		b.mesh = cyl
		b.position.y = 12.0
		b.material_override = mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(b)
	return root


static func _warning_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color, 0.6)
	m.emission_enabled = true
	m.emission = color
	return m


func _free_marks(s: Dictionary) -> void:
	for n: Node3D in s.marks:
		if is_instance_valid(n):
			n.queue_free()
	s.marks = []


# ================================================================ RPCs

@rpc("any_peer", "call_remote", "reliable")
func _c_call(point: Vector3) -> void:
	if multiplayer.is_server():
		_server_call(multiplayer.get_remote_sender_id(), point)


@rpc("authority", "call_remote", "reliable")
func _s_reward(eid: int, kind: String, streak: int) -> void:
	var p: Player = world.entities.get(eid)
	match kind:
		"radar":
			radar_until[eid] = World.now() + RADAR_TIME
		"shield":
			if p != null:
				p.shield = SHIELD
		"bomber":
			bomber_ready[eid] = true
			if multiplayer.is_server() and p != null and p.is_bot:
				_bot_call_at[eid] = World.now() + randf_range(0.8, 2.5)
	var me := world.local_player
	if p == me:
		Sfx.play(&"streak_reward", null, -1.0)
	if kind == "radar" and me != null and (p == me or (p != null and Teams.same(p, me))):
		Sfx.play(&"radar_sweep", null, -2.0)
	rewarded.emit(eid, kind, streak)


## Every peer: a Block Bomber was called by `caller`: the ground warning goes up for `land_in`
## seconds; `done` blasts already went off (a late joiner's copy).
@rpc("authority", "call_remote", "reliable")
func _s_strike(id: int, caller: int, points: PackedVector3Array, land_in: float, done: int) -> void:
	bomber_ready.erase(caller)
	var mat := _warning_material(Palette.color("warning"))
	var marks: Array[Node3D] = []
	for i in points.size():
		var n := _make_mark(mat, true)
		n.global_position = points[i]
		n.visible = i >= done
		marks.append(n)
	strikes.append({"id": id, "caller": caller, "points": points, "land_at": World.now() + land_in,
		"next": done, "marks": marks, "mat": mat, "hit": {}})
	if done == 0:
		Sfx.play(&"bomber_warning", points[points.size() / 2], 0.0)
		if caller == world.my_id():
			Sfx.play(&"bomber_warning", null, -8.0)


@rpc("authority", "call_remote", "reliable")
func _s_blast(id: int, index: int, pos: Vector3) -> void:
	world.fx.explosion(pos)
	world.killcam.record_explosion(pos, "bomber")
	Sfx.play(&"explosion", pos, 2.0)
	if world.local_player != null:
		world.shake(clampf(1.4 - world.local_player.global_position.distance_to(pos) / 10.0, 0.0, 1.2))
	for s: Dictionary in strikes:
		if int(s.id) != id:
			continue
		s.next = maxi(int(s.next), index + 1)
		if index < s.marks.size() and is_instance_valid(s.marks[index]):
			s.marks[index].visible = false
		if int(s.next) >= (s.points as PackedVector3Array).size():
			_free_marks(s)
			strikes.erase(s)
		return


## A late joiner's copy of the rewards in progress: radar seconds left, shields, bomber holders
## and strikes ([id, caller, points, seconds to the first blast, blasts done]).
@rpc("authority", "call_remote", "reliable")
func _s_state(radar: Dictionary, shields: Dictionary, bombers: Array, list: Array) -> void:
	var t := World.now()
	for eid: int in radar:
		radar_until[eid] = t + float(radar[eid])
	for eid: int in shields:
		var p: Player = world.entities.get(eid)
		if p != null:
			p.shield = float(shields[eid])
	for eid: int in bombers:
		bomber_ready[eid] = true
	for s: Array in list:
		_s_strike(int(s[0]), int(s[1]), s[2], float(s[3]), int(s[4]))
