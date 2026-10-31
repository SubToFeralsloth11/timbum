class_name KillCam
extends Node
## Kill cam replay: World's child "KillCam" on every peer.
##
## **Recording.** Every peer keeps a ring buffer (a Tape) of what it already has of every player:
## RATE frames a second for SECONDS, each with every player's feet position, eye position, yaw,
## pitch and state flags (Player.net_flags: stance, aim, sprint, slide, reload, held weapon, lean;
## plus alive, grappling and "remote"), the projectiles in flight, and the shots, knife swings,
## throws, rockets, explosions and hits it plays as effects. A remote player's entry is the
## interpolated pose this peer shows, which runs Player.INTERP_DELAY behind the events it
## receives, so the replay reads remote poses that much later and they line up with their shots.
## Nothing is sent over the network for it, and nothing is recorded in Tactical (no respawns:
## the dead spectate) or with the `killcam` setting off. The buffers are preallocated packed
## arrays, so recording allocates nothing per frame.
##
## **Replay.** When another player kills the local player (World._s_killed), the replay starts
## START_DELAY after the death. It shows the last moments up to TAIL past the kill from the
## killer's eyes: their recorded eye, aim and stance drive this node's own camera and a Viewmodel
## built with the killer's outfit, skin, charm and camos (gun, kick, muzzle flash, reload, knife,
## throw), their shots draw tracers and impacts, and everyone else is a ghost Avatar at their
## recorded pose (the local player's own ghost is labelled YOU). KillCamOverlay draws the KILLCAM
## banner, the skip key (`skip_killcam`) and progress. The replay ends END_MARGIN before the
## respawn at the latest: its length is the respawn delay minus START_DELAY and END_MARGIN, at
## most MAX_LEN, and none plays under MIN_LEN; a respawn, the end of the match or the skip key
## ends it at once. When it starts, the window is copied out of the ring into a second Tape, so
## recording carries on during the replay.
## The live match keeps running underneath: the replay only swaps the current camera, hides the
## live avatars, projectiles and the HUD's own cards (Hud.set_killcam) and the mode overlays
## (canvas layer 11), and reads no gameplay state back. A frozen offline match (pause) freezes it,
## since its clock is World.now().

const RATE := 30.0
const SECONDS := 5.0
## Ring size: SECONDS at RATE, plus slack for the copy window's edges.
const FRAMES := 152
## Players recorded; every mode with respawns has at most 12.
const SLOTS := 16
## Projectiles recorded per frame.
const PROJ := 8
## Effect events kept (shots of a full lobby over a few seconds).
const EVENTS := 512
const START_DELAY := 0.8
const END_MARGIN := 0.2
const MAX_LEN := 4.0
const MIN_LEN := 1.0
## The replay runs on this long past the kill (the victim falls).
const TAIL := 0.35
## A shotgun shell draws a tracer for every third pellet, like the live effects; at most this many.
const TRACERS_PER_SHOT := 3
## A player moving further than this between two frames teleported (respawn): no interpolation.
const SNAP_DIST := 4.0

## Bits added to Player.state_flags (which uses bits 0-20).
const BIT_ALIVE := 1 << 24
const BIT_REMOTE := 1 << 25
const BIT_GRAPPLE := 1 << 26
## Projectile and explosion kinds (index stored in the tape).
const KINDS: Array[String] = ["rocket", "grenade", "smoke", "flash", "bomber"]

enum Ev { SHOT, PELLET, SLASH, THROW, ROCKET, EXPLODE, HIT }


## Fixed-size recording: `cap` frames of `slots` players and `proj` projectiles in a ring
## (logical frame 0 is the oldest), plus a ring of `ev_cap` effect events.
class Tape:
	var cap := 0
	var slots := 0
	var proj := 0
	var count := 0
	var head := 0
	var times := PackedFloat64Array()
	var ids := PackedInt32Array()
	var pos := PackedVector3Array()
	var eye := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var pitch := PackedFloat32Array()
	var flags := PackedInt32Array()
	var proj_id := PackedInt32Array()
	var proj_kind := PackedInt32Array()
	var proj_pos := PackedVector3Array()
	var ev_cap := 0
	var ev_count := 0
	var ev_head := 0
	var ev_time := PackedFloat64Array()
	var ev_kind := PackedInt32Array()
	var ev_eid := PackedInt32Array()
	var ev_arg := PackedInt32Array()
	var ev_a := PackedVector3Array()
	var ev_b := PackedVector3Array()

	func _init(p_frames: int, p_slots: int, p_proj: int, p_events: int) -> void:
		cap = p_frames
		slots = p_slots
		proj = p_proj
		ev_cap = p_events
		times.resize(cap)
		var n := cap * slots
		ids.resize(n)
		pos.resize(n)
		eye.resize(n)
		yaw.resize(n)
		pitch.resize(n)
		flags.resize(n)
		var m := cap * proj
		proj_id.resize(m)
		proj_kind.resize(m)
		proj_pos.resize(m)
		ev_time.resize(ev_cap)
		ev_kind.resize(ev_cap)
		ev_eid.resize(ev_cap)
		ev_arg.resize(ev_cap)
		ev_a.resize(ev_cap)
		ev_b.resize(ev_cap)

	func clear() -> void:
		count = 0
		head = 0
		ev_count = 0
		ev_head = 0

	## Ring index of logical frame `i`.
	func at(i: int) -> int:
		return (head + i) % cap

	## Starts a frame at time `t` (overwriting the oldest when full) and returns its ring index,
	## with its player and projectile entries emptied.
	func begin_frame(t: float) -> int:
		var f: int
		if count < cap:
			f = (head + count) % cap
			count += 1
		else:
			f = head
			head = (head + 1) % cap
		times[f] = t
		var base := f * slots
		for s in slots:
			ids[base + s] = 0
		var pb := f * proj
		for k in proj:
			proj_id[pb + k] = 0
		return f

	func add_event(t: float, kind: int, eid: int, arg: int, a: Vector3, b: Vector3) -> void:
		var e: int
		if ev_count < ev_cap:
			e = (ev_head + ev_count) % ev_cap
			ev_count += 1
		else:
			e = ev_head
			ev_head = (ev_head + 1) % ev_cap
		ev_time[e] = t
		ev_kind[e] = kind
		ev_eid[e] = eid
		ev_arg[e] = arg
		ev_a[e] = a
		ev_b[e] = b

	## Logical index of the last frame at or before `t` (0 when `t` is before the first; -1 empty).
	func find(t: float) -> int:
		if count == 0:
			return -1
		var lo := 0
		var hi := count - 1
		while lo < hi:
			var mid := (lo + hi + 1) >> 1
			if times[at(mid)] <= t:
				lo = mid
			else:
				hi = mid - 1
		return lo

	## Replaces this tape with `src`'s frames covering `t_from`..`t_to` (one frame either side) and
	## its events in that span.
	func copy_from(src: Tape, t_from: float, t_to: float) -> void:
		clear()
		if src.count == 0:
			return
		for i in range(src.find(t_from), src.count):
			var sf := src.at(i)
			if count >= cap:
				break
			var f := begin_frame(src.times[sf])
			var d := f * slots
			var o := sf * slots
			for s in slots:
				ids[d + s] = src.ids[o + s]
				pos[d + s] = src.pos[o + s]
				eye[d + s] = src.eye[o + s]
				yaw[d + s] = src.yaw[o + s]
				pitch[d + s] = src.pitch[o + s]
				flags[d + s] = src.flags[o + s]
			var dp := f * proj
			var op := sf * proj
			for k in proj:
				proj_id[dp + k] = src.proj_id[op + k]
				proj_kind[dp + k] = src.proj_kind[op + k]
				proj_pos[dp + k] = src.proj_pos[op + k]
			if src.times[sf] > t_to:
				break
		for j in src.ev_count:
			var e := (src.ev_head + j) % src.ev_cap
			var t := src.ev_time[e]
			if t >= t_from and t <= t_to:
				add_event(t, src.ev_kind[e], src.ev_eid[e], src.ev_arg[e], src.ev_a[e], src.ev_b[e])


var world: World
## The last replay, for checks: {death_t, start_t, end_t, reason, len, frames, killer, wid}
## (World.now() times).
var last := {}
## Replays played this match.
var replays := 0

var _tape := Tape.new(FRAMES, SLOTS, PROJ, EVENTS)
var _play := Tape.new(FRAMES, SLOTS, PROJ, EVENTS)
var _recording := false
var _last_record := -100.0
## Recording slot of each entity id, and the entity (0: free) and last record time of each slot.
## A slot is reused only after its entity has been gone longer than the ring.
var _slot_of := {}
var _slot_eid := PackedInt32Array()
var _slot_seen := PackedFloat64Array()

var _pending_at := -1.0
var _playing := false
var _killer := 0
var _killer_slot := -1
var _wid := ""
var _kill_t := 0.0
var _len := 0.0
## Recorded time the replay starts at, and World.now() when it started.
var _t0 := 0.0
var _started_at := 0.0
var _ev_next := 0
var _frames_played := 0

var _root3d: Node3D
var _cam: Camera3D
var _viewmodel: Viewmodel
var _vm_key := ""
var _ads := 0.0
var _cam_weapon := ""
var _cam_reloading := false
var _cam_ads_fov := 60.0
var _cam_scoped := false
var _cam_scope_style := "sniper"
var _you_tag: Label3D
var _overlay: KillCamOverlay
var _entities_root: Node3D
var _hidden_layers: Array[CanvasLayer] = []

## Ghost avatars per recording slot (null until needed) and their replay state.
var _ghosts: Array[Avatar] = []
var _g_eid := PackedInt32Array()
var _g_look: Array[String] = []
var _g_wid: Array[String] = []
var _g_info: Array[Dictionary] = []
var _g_alive: Array[bool] = []
var _g_seen_alive: Array[bool] = []
var _g_reload: Array[bool] = []
var _proj_nodes: Array[Node3D] = []
var _proj_node_kind := PackedInt32Array()

## Result of the last _sample.
var _s_pos := Vector3.ZERO
var _s_eye := Vector3.ZERO
var _s_yaw := 0.0
var _s_pitch := 0.0
var _s_flags := 0
var _s_vel := Vector3.ZERO


func _ready() -> void:
	_slot_eid.resize(SLOTS)
	_slot_seen.resize(SLOTS)
	_g_eid.resize(SLOTS)
	for s in SLOTS:
		_ghosts.append(null)
		_g_look.append("")
		_g_wid.append("")
		_g_info.append({})
		_g_alive.append(true)
		_g_seen_alive.append(false)
		_g_reload.append(false)
	_proj_node_kind.resize(PROJ)
	for k in PROJ:
		_proj_nodes.append(null)
		_proj_node_kind[k] = -1
	_root3d = Node3D.new()
	_root3d.name = "Replay"
	_root3d.visible = false
	add_child(_root3d)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.near = 0.05
	_cam.far = 400.0
	_root3d.add_child(_cam)
	_you_tag = Label3D.new()
	_you_tag.text = "YOU"
	_you_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_you_tag.no_depth_test = true
	_you_tag.fixed_size = true
	_you_tag.pixel_size = 0.0012
	_you_tag.font_size = 40
	_you_tag.outline_size = 10
	_you_tag.modulate = Color(1.0, 0.35, 0.3)
	_root3d.add_child(_you_tag)
	_overlay = KillCamOverlay.new()
	_overlay.name = "KillCamOverlay"
	add_child(_overlay)
	_entities_root = world.get_node(^"Entities")


# ================================================================ recording

func _physics_process(_delta: float) -> void:
	var on := bool(Profile.get_setting("killcam")) and not world.match_over and world.local_player != null \
		and world.rules.respawn_delay() >= 0.0
	if on != _recording:
		_recording = on
		if on:
			# A gap in the recording would be interpolated across; start afresh.
			_tape.clear()
	if not _recording:
		return
	var t := World.now()
	if t - _last_record < 0.9 / RATE:
		return
	_last_record = t
	_record(t)


func _record(t: float) -> void:
	var f := _tape.begin_frame(t)
	var base := f * SLOTS
	for eid: int in world.entities:
		var s := _slot(eid, t)
		if s < 0:
			continue
		var p: Player = world.entities[eid]
		var i := base + s
		_tape.ids[i] = eid
		_tape.pos[i] = p.global_position
		_tape.eye[i] = p.head.global_position
		_tape.yaw[i] = p.yaw
		_tape.pitch[i] = p.pitch
		var fl := p.net_flags()
		if p.alive:
			fl |= BIT_ALIVE
		if p.mode == Player.Mode.REMOTE:
			fl |= BIT_REMOTE
		if p.grappling:
			fl |= BIT_GRAPPLE
		_tape.flags[i] = fl
	var n := 0
	var pb := f * PROJ
	for pid: int in world.projectiles:
		if n >= PROJ:
			break
		var proj: Projectile = world.projectiles[pid]
		if not proj.in_flight():
			continue
		_tape.proj_id[pb + n] = pid
		_tape.proj_kind[pb + n] = KINDS.find(proj.kind)
		_tape.proj_pos[pb + n] = proj.global_position
		n += 1


func _slot(eid: int, t: float) -> int:
	var s: int = _slot_of.get(eid, -1)
	if s >= 0:
		_slot_seen[s] = t
		return s
	for i in SLOTS:
		if _slot_eid[i] == 0 or t - _slot_seen[i] > SECONDS + 1.0:
			if _slot_eid[i] != 0:
				_slot_of.erase(_slot_eid[i])
			_slot_eid[i] = eid
			_slot_of[eid] = i
			_slot_seen[i] = t
			return i
	return -1


## World._play_shot_fx: a hitscan shot or melee swing of `p` (every peer plays these).
func record_shot(p: Player, wid: String, ends: PackedVector3Array, normals: PackedVector3Array) -> void:
	if not _recording:
		return
	var t := World.now()
	var wi := Player.weapon_index(wid)
	if Data.is_melee(wid):
		var hit := ends.size() > 0 and normals[0] != Vector3.ZERO
		_tape.add_event(t, Ev.SLASH, p.id, wi, ends[0] if hit else Vector3.ZERO, normals[0] if hit else Vector3.ZERO)
		return
	var every := 3 if int(Data.WEAPONS[wid].pellets) > 1 else 1
	var n := 0
	var i := 0
	while i < ends.size() and n < TRACERS_PER_SHOT:
		_tape.add_event(t, Ev.SHOT if n == 0 else Ev.PELLET, p.id, wi, ends[i], normals[i])
		n += 1
		i += every
	if n == 0:
		_tape.add_event(t, Ev.SHOT, p.id, wi, p.head.global_position, Vector3.ZERO)


## World._s_spawn_projectile: `owner_id` fired a rocket or threw a grenade.
func record_launch(owner_id: int, kind: String) -> void:
	if _recording:
		_tape.add_event(World.now(), Ev.ROCKET if kind == "rocket" else Ev.THROW, owner_id, KINDS.find(kind), Vector3.ZERO, Vector3.ZERO)


## World._s_explode and Streaks' Block Bomber blasts (`kind` "bomber").
func record_explosion(pos: Vector3, kind: String) -> void:
	if _recording:
		_tape.add_event(World.now(), Ev.EXPLODE, 0, KINDS.find(kind), pos, Vector3.ZERO)


## World._s_damaged: another player hurt `p` (blood in the replay).
func record_hit(p: Player) -> void:
	if _recording:
		_tape.add_event(World.now(), Ev.HIT, p.id, 0, p.global_position + Vector3.UP * (p.body_center_height() - 0.15), Vector3.ZERO)


## Checks: what the ring holds now.
func buffer_info() -> Dictionary:
	return {"frames": _tape.count, "frame_cap": _tape.cap, "events": _tape.ev_count, "event_cap": _tape.ev_cap,
		"span": _tape.times[_tape.at(_tape.count - 1)] - _tape.times[_tape.at(0)] if _tape.count > 0 else 0.0,
		"slots": _slot_of.size(), "ghosts": _ghosts.filter(func(g: Avatar) -> bool: return g != null).size()}


## Checks: the pose this peer recorded for `eid` at World.now() time `t`, as the replay reads it
## (a remote player's interpolated pose INTERP_DELAY later); {} when not recorded.
func recorded_pose(eid: int, t: float) -> Dictionary:
	var s: int = _slot_of.get(eid, -1)
	if s < 0 or not _sample(_tape, s, eid, t):
		return {}
	return {"pos": _s_pos, "eye": _s_eye, "yaw": _s_yaw, "pitch": _s_pitch,
		"weapon": Player.flags_weapon(_s_flags), "alive": (_s_flags & BIT_ALIVE) != 0}


## Interpolated state of slot `slot` (entity `eid`) at `t` into the _s_* fields; false when the
## tape has no entry for it there. A remote player's entry is read INTERP_DELAY later.
func _sample(tape: Tape, slot: int, eid: int, t: float) -> bool:
	if not _sample_at(tape, slot, eid, t):
		return false
	if (_s_flags & BIT_REMOTE) != 0:
		_sample_at(tape, slot, eid, t + Player.INTERP_DELAY)
	return true


func _sample_at(tape: Tape, slot: int, eid: int, t: float) -> bool:
	var i := tape.find(t)
	if i < 0:
		return false
	var j := mini(i + 1, tape.count - 1)
	var fa := tape.at(i)
	var fb := tape.at(j)
	var a := fa * SLOTS + slot
	var b := fb * SLOTS + slot
	var ok_a := tape.ids[a] == eid
	var ok_b := tape.ids[b] == eid
	if not ok_a and not ok_b:
		return false
	if not ok_a:
		a = b
	elif not ok_b:
		b = a
	var k := 0.0
	_s_vel = Vector3.ZERO
	if a != b:
		var span := tape.times[fb] - tape.times[fa]
		k = clampf((t - tape.times[fa]) / span, 0.0, 1.0) if span > 0.0001 else 1.0
		var step := tape.pos[b] - tape.pos[a]
		if step.length() > SNAP_DIST:
			k = 0.0 if k < 0.5 else 1.0
		elif span > 0.0001:
			_s_vel = step / span
	_s_pos = tape.pos[a].lerp(tape.pos[b], k)
	_s_eye = tape.eye[a].lerp(tape.eye[b], k)
	_s_yaw = lerp_angle(tape.yaw[a], tape.yaw[b], k)
	_s_pitch = lerpf(tape.pitch[a], tape.pitch[b], k)
	_s_flags = tape.flags[a] if k < 1.0 else tape.flags[b]
	return true


# ================================================================ replay

## World._s_killed: `killer_id` killed the local player with `wid`. Schedules the replay when it
## can play: someone else killed us, the setting is on, the mode respawns, and the respawn delay
## leaves room for at least MIN_LEN.
func on_local_death(killer_id: int, wid: String) -> void:
	stop("death")
	if not _recording or killer_id == world.my_id() or world.match_over or not world.entities.has(killer_id):
		return
	var delay := world.rules.respawn_delay()
	var length := minf(MAX_LEN, delay - START_DELAY - END_MARGIN)
	if length < MIN_LEN:
		return
	_killer = killer_id
	_wid = wid
	_kill_t = World.now()
	_len = length
	_pending_at = _kill_t + START_DELAY
	last = {"death_t": _kill_t, "start_t": -1.0, "end_t": -1.0, "reason": "pending", "len": length,
		"frames": 0, "killer": killer_id, "wid": wid}


## Ends the replay now (or cancels one about to start): the respawn, the end of the match, the
## local player leaving.
func stop(reason: String) -> void:
	_pending_at = -1.0
	if _playing:
		_finish(reason)
	elif last.get("reason", "") == "pending":
		last.reason = "cancelled: " + reason


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if _pending_at >= 0.0 and World.now() >= _pending_at:
		_begin()
	if _playing:
		_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _playing and event.is_action_pressed("skip_killcam") and not world.hud.is_blocking():
		get_viewport().set_input_as_handled()
		_finish("skip")


func _begin() -> void:
	_pending_at = -1.0
	var me := world.local_player
	if me == null or me.alive or world.match_over or not world.entities.has(_killer):
		last.reason = "cancelled"
		return
	var end_t := _kill_t + TAIL
	_t0 = end_t - _len
	_play.copy_from(_tape, _t0 - 2.0 / RATE, end_t + Player.INTERP_DELAY + 2.0 / RATE)
	_killer_slot = _slot_of.get(_killer, -1)
	# The killer may have spawned or joined inside the window: start at their first frame.
	var first := -1.0
	if _killer_slot >= 0:
		for i in _play.count:
			if _play.ids[_play.at(i) * SLOTS + _killer_slot] == _killer:
				first = _play.times[_play.at(i)]
				break
	if first < 0.0 or end_t - maxf(_t0, first) < MIN_LEN * 0.5:
		last.reason = "no data"
		return
	_t0 = maxf(_t0, first)
	_len = end_t - _t0
	_ev_next = 0
	while _ev_next < _play.ev_count and _play.ev_time[_ev_next] < _t0:
		_ev_next += 1
	_frames_played = 0
	_ads = 0.0
	_cam_reloading = false
	_build_view(world.entities[_killer])
	_playing = true
	_started_at = World.now()
	replays += 1
	last.start_t = _started_at
	last.len = _len
	last.reason = "playing"
	_step(0.0)


func _build_view(killer: Player) -> void:
	var info := killer.info
	var camos: Variant = info.get("camos", [])
	var key := "%s|%s|%s|%s|%s" % [info.outfit, info.skin, info.get("charm", "none"), info.get("draw", "standard"), str(camos)]
	if key != _vm_key or _viewmodel == null:
		if _viewmodel != null:
			_viewmodel.queue_free()
		_vm_key = key
		_viewmodel = Viewmodel.new()
		_viewmodel.setup(str(info.outfit), str(info.skin), str(info.get("charm", "none")), str(info.get("draw", "standard")),
			camos if typeof(camos) == TYPE_ARRAY else [])
		_cam.add_child(_viewmodel)
		_cam_weapon = ""
	for s in SLOTS:
		_g_alive[s] = true
		_g_seen_alive[s] = false
		_g_reload[s] = false
		if _ghosts[s] == null:
			continue
		var p: Player = world.entities.get(_g_eid[s])
		if p == null or _look_key(p.info) != _g_look[s]:
			# Gone, or a new outfit or hat: rebuilt when needed.
			_ghosts[s].queue_free()
			_ghosts[s] = null
			_g_eid[s] = 0
			continue
		_ghosts[s].visible = false
		_ghosts[s].reset_pose()
		_g_info[s] = p.info
		_copy_look(p, _ghosts[s])
	_root3d.visible = true
	_cam.fov = float(Profile.get_setting("fov"))
	_cam.make_current()
	_entities_root.visible = false
	_hide_live_projectiles()
	for node: Node in world.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.layer == 11 and layer.visible:
			layer.visible = false
			_hidden_layers.append(layer)
	world.hud.set_killcam(true)
	var team := Teams.of(killer)
	_overlay.show_for(world.tagged_name(_killer) if team < 0 else Teams.tagged(team, world.tagged_name(_killer)),
		Teams.color(team) if team >= 0 else Palette.color("feed_killer"), World.weapon_label(_wid))


func _finish(reason: String) -> void:
	_playing = false
	_root3d.visible = false
	_overlay.visible = false
	_overlay.set_scope(false, "sniper")
	var me := world.local_player
	if me != null and me.camera != null:
		me.camera.make_current()
	_entities_root.visible = true
	for pid: int in world.projectiles:
		var proj: Projectile = world.projectiles[pid]
		proj.visible = proj.in_flight()
	for layer in _hidden_layers:
		if is_instance_valid(layer):
			layer.visible = true
	_hidden_layers.clear()
	world.hud.set_killcam(false)
	last.end_t = World.now()
	last.reason = reason
	last.frames = _frames_played


func _hide_live_projectiles() -> void:
	for pid: int in world.projectiles:
		(world.projectiles[pid] as Node3D).visible = false


func _step(delta: float) -> void:
	var r := World.now() - _started_at
	if r >= _len:
		_finish("end")
		return
	var t := _t0 + r
	_frames_played += 1
	_overlay.set_progress(r / _len)
	_hide_live_projectiles()
	_pose_killer(t, delta)
	_pose_ghosts(t, delta)
	_pose_projectiles(t)
	_play_events(t)


func _pose_killer(t: float, delta: float) -> void:
	if _killer_slot < 0 or not _sample(_play, _killer_slot, _killer, t):
		return
	var fl := _s_flags
	var wid := Player.flags_weapon(fl)
	if wid != _cam_weapon:
		var w: Dictionary = Data.WEAPONS[wid]
		_viewmodel.set_weapon(wid, 0.05 if _cam_weapon.is_empty() else Player.SWITCH_TIME)
		_cam_weapon = wid
		_cam_ads_fov = float(w.ads_fov)
		_cam_scoped = w.get("scope", false)
		_cam_scope_style = str(w.get("scope_style", "sniper"))
	_ads = move_toward(_ads, 1.0 if (fl & Player.FLAG_AIM) != 0 else 0.0, delta * 6.0)
	var sliding := (fl & Player.FLAG_SLIDE) != 0
	var roll := -Player.flags_lean(fl) * Player.LEAN_ROLL + (deg_to_rad(-4.0) if sliding else 0.0)
	_cam.global_transform = Transform3D(Basis.from_euler(Vector3(_s_pitch, _s_yaw, roll)), _s_eye)
	var base_fov := float(Profile.get_setting("fov"))
	_cam.fov = lerpf(base_fov, minf(_cam_ads_fov, base_fov), _ads)
	var reloading := (fl & Player.FLAG_RELOAD) != 0
	if reloading and not _cam_reloading:
		_viewmodel.play_reload(float(Data.WEAPONS[wid].reload))
	elif _cam_reloading and not reloading:
		_viewmodel.stop_reload()
	_cam_reloading = reloading
	var alive := (fl & BIT_ALIVE) != 0
	_viewmodel.visible = alive
	var local_vel := Basis(Vector3.UP, _s_yaw).inverse() * _s_vel
	_viewmodel.pose(delta, _ads, (fl & Player.FLAG_SPRINT) != 0, sliding, (fl & BIT_GRAPPLE) != 0, local_vel,
		(fl & Player.FLAG_FLOOR) != 0, Vector2(_s_vel.x, _s_vel.z).length(), (fl & Player.FLAG_CROUCH) != 0)
	_overlay.set_scope(alive and _cam_scoped and _ads > 0.85, _cam_scope_style)


func _pose_ghosts(t: float, delta: float) -> void:
	var me := world.my_id()
	_you_tag.visible = false
	var i := maxi(0, _play.find(t))
	var fa := _play.at(i) * SLOTS
	var fb := _play.at(mini(i + 1, _play.count - 1)) * SLOTS
	for s in SLOTS:
		var eid := _play.ids[fa + s]
		if eid == 0:
			eid = _play.ids[fb + s]
		var g := _ghosts[s]
		if eid == 0 or eid == _killer or not _sample(_play, s, eid, t):
			if g != null:
				g.visible = false
			continue
		g = _ghost(s, eid)
		if g == null:
			continue
		var fl := _s_flags
		var alive := (fl & BIT_ALIVE) != 0
		g.position = _s_pos
		g.rotation.y = _s_yaw
		if not alive:
			if _g_alive[s]:
				_g_alive[s] = false
				g.play_death()
			g.visible = _g_seen_alive[s]
			continue
		if not _g_alive[s]:
			_g_alive[s] = true
			g.reset_pose()
		_g_seen_alive[s] = true
		g.visible = true
		var wid := Player.flags_weapon(fl)
		if wid != _g_wid[s]:
			_g_wid[s] = wid
			g.hold_weapon(wid, Data.gun_skin_for(_g_info[s], wid))
		var reloading := (fl & Player.FLAG_RELOAD) != 0
		if reloading and not _g_reload[s]:
			g.play_reload(float(Data.WEAPONS[wid].reload))
		elif _g_reload[s] and not reloading:
			g.stop_reload()
		_g_reload[s] = reloading
		var local_vel := Basis(Vector3.UP, _s_yaw).inverse() * _s_vel
		g.set_motion((fl & Player.FLAG_SLIDE) != 0, Player.flags_lean(fl), Vector2(local_vel.x, -local_vel.z), (fl & BIT_GRAPPLE) != 0)
		g.set_look_pitch(_s_pitch)
		g.animate(delta, Vector2(_s_vel.x, _s_vel.z).length(), (fl & Player.FLAG_FLOOR) != 0,
			(fl & Player.FLAG_CROUCH) != 0, (fl & Player.FLAG_PRONE) != 0)
		if eid == me:
			_you_tag.visible = true
			_you_tag.position = _s_pos + Vector3.UP * 2.35


## The ghost avatar of `eid` in slot `s`, built (or rebuilt for another entity or a new look) on
## first use and kept for later replays; null when the entity has left.
func _ghost(s: int, eid: int) -> Avatar:
	var g := _ghosts[s]
	if g != null and _g_eid[s] == eid:
		return g
	var p: Player = world.entities.get(eid)
	if p == null:
		if g != null:
			g.visible = false
		return null
	var look := _look_key(p.info)
	if g != null:
		g.queue_free()
	g = Models.build_avatar(str(p.info.outfit), str(p.info.hat))
	g.charm_id = str(p.info.get("charm", "none"))
	g.name = "Ghost%d" % s
	_root3d.add_child(g)
	_copy_look(p, g)
	_ghosts[s] = g
	_g_eid[s] = eid
	_g_look[s] = look
	_g_info[s] = p.info
	_g_wid[s] = ""
	_g_alive[s] = true
	return g


static func _look_key(info: Dictionary) -> String:
	return "%s|%s|%s" % [info.outfit, info.hat, info.get("charm", "none")]


## Team armbands, a tint (Infected) and Big Heads' scaled head, copied from the live avatar.
func _copy_look(p: Player, g: Avatar) -> void:
	var live := p.avatar
	g.set_tint(live.get_tint())
	for arm: String in ["ArmL", "ArmR"]:
		var src := live.find_child(arm, true, false) as Node3D
		var dst := g.find_child(arm, true, false) as Node3D
		if src == null or dst == null:
			continue
		var band := src.get_node_or_null(^"Armband") as MeshInstance3D
		var mine := dst.get_node_or_null(^"Armband") as MeshInstance3D
		if band == null:
			if mine != null:
				mine.queue_free()
			continue
		if mine == null:
			mine = MeshInstance3D.new()
			mine.name = "Armband"
			mine.position = band.position
			dst.add_child(mine)
		mine.mesh = band.mesh
	if Net.config.get("mutator", "") == "big_heads":
		var lh := live.get_head().get_children()
		var gh := g.get_head().get_children()
		for i in mini(lh.size(), gh.size()):
			if lh[i] is Node3D and gh[i] is Node3D:
				(gh[i] as Node3D).scale = (lh[i] as Node3D).scale
				(gh[i] as Node3D).position = (lh[i] as Node3D).position


func _pose_projectiles(t: float) -> void:
	var i := maxi(0, _play.find(t))
	var j := mini(i + 1, _play.count - 1)
	var fa := _play.at(i)
	var fb := _play.at(j)
	var span := _play.times[fb] - _play.times[fa]
	var k := clampf((t - _play.times[fa]) / span, 0.0, 1.0) if span > 0.0001 else 0.0
	for n in PROJ:
		var pid := _play.proj_id[fa * PROJ + n]
		var node := _proj_nodes[n]
		if pid == 0:
			if node != null:
				node.visible = false
			continue
		var kind := _play.proj_kind[fa * PROJ + n]
		var from := _play.proj_pos[fa * PROJ + n]
		var to := from
		for m in PROJ:
			if _play.proj_id[fb * PROJ + m] == pid:
				to = _play.proj_pos[fb * PROJ + m]
				break
		if node == null or _proj_node_kind[n] != kind:
			if node != null:
				node.queue_free()
			match kind:
				0: node = Models.build_rocket()
				1: node = Models.build_grenade()
				_: node = Models.build_tactical(KINDS[clampi(kind, 2, 3)])
			_root3d.add_child(node)
			_proj_nodes[n] = node
			_proj_node_kind[n] = kind
		node.visible = true
		node.position = from.lerp(to, k)
		var dir := to - from
		if kind == 0 and dir.length_squared() > 0.0001:
			dir = dir.normalized()
			node.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)


func _play_events(t: float) -> void:
	while _ev_next < _play.ev_count and _play.ev_time[_ev_next] <= t:
		_fire_event(_ev_next)
		_ev_next += 1


func _fire_event(e: int) -> void:
	var kind := _play.ev_kind[e]
	var eid := _play.ev_eid[e]
	var a := _play.ev_a[e]
	var b := _play.ev_b[e]
	var mine := eid == _killer
	var s: int = _slot_of.get(eid, -1)
	var g: Avatar = _ghosts[s] if s >= 0 and _g_eid[s] == eid and _ghosts[s] != null and _ghosts[s].visible else null
	var fx := world.fx
	match kind:
		Ev.SHOT, Ev.PELLET:
			var wid := Player.weapon_from_index(_play.ev_arg[e])
			var w: Dictionary = Data.WEAPONS[wid]
			var suppressed: bool = w.get("suppressed", false)
			var muzzle := _muzzle(g, mine)
			if kind == Ev.SHOT:
				if mine:
					_viewmodel.play_fire(float(w.recoil))
					Sfx.play(StringName(w.sound), null, -3.0, float(w.get("pitch", 1.0)))
				elif g != null:
					g.play_shoot()
					Sfx.play(StringName(w.sound), muzzle, 0.0, float(w.get("pitch", 1.0)))
					if not suppressed:
						fx.muzzle_flash(muzzle)
			if mine or (g != null and not suppressed):
				fx.tracer(muzzle, a)
			if b != Vector3.ZERO:
				fx.impact(a, b)
		Ev.SLASH:
			var mw: Dictionary = Data.WEAPONS[Player.weapon_from_index(_play.ev_arg[e])]
			var swing := StringName(mw.sound)
			if mine:
				_viewmodel.play_melee(false)
				Sfx.play(swing, null, -4.0, float(mw.get("pitch", 1.0)))
			elif g != null:
				g.play_slash()
				Sfx.play(swing, g.global_position, -4.0, float(mw.get("pitch", 1.0)))
			if b != Vector3.ZERO:
				fx.impact(a, b)
		Ev.THROW, Ev.ROCKET:
			var rocket := kind == Ev.ROCKET
			if mine:
				if rocket:
					_viewmodel.play_fire(float(Data.WEAPONS.rocket.recoil))
				else:
					_viewmodel.play_throw()
				Sfx.play(&"shot_rocket" if rocket else &"grenade_throw", null, -2.0)
			elif g != null:
				if rocket:
					g.play_shoot()
				else:
					g.play_throw()
				Sfx.play(&"shot_rocket" if rocket else &"grenade_throw", g.global_position)
		Ev.EXPLODE:
			match KINDS[clampi(_play.ev_arg[e], 0, KINDS.size() - 1)]:
				"smoke":
					Sfx.play(&"smoke_pop", a)
				"flash":
					fx.flash_burst(a)
					Sfx.play(&"flashbang", a, 2.0)
				_:
					fx.explosion(a)
					Sfx.play(&"explosion", a, 2.0)
		Ev.HIT:
			fx.blood(a)


## Where a shot in the replay comes from: the killer's first-person gun, a ghost's gun muzzle.
func _muzzle(g: Avatar, mine: bool) -> Vector3:
	if mine:
		return _viewmodel.muzzle_position()
	if g == null:
		return _cam.global_position
	var gun := g.get_gun()
	var m := gun.get_node_or_null(^"Muzzle") as Node3D if gun != null else null
	return m.global_position if m != null else g.global_position + Vector3.UP * 1.4
