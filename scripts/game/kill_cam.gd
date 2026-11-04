class_name KillCam
extends Node
## Kill cam replay and the match recording behind it and behind clips: World's child "KillCam"
## on every peer.
##
## **Recording.** Every peer keeps a ring buffer (a Tape) of what it already has of every player:
## RATE frames a second for RING_SECONDS, each with every player's feet position, eye position,
## yaw, pitch and state flags (Player.net_flags: stance, aim, sprint, slide, reload, held weapon,
## lean; plus alive, grappling and "remote"), the projectiles in flight, and the shots, knife
## swings, throws, rockets, explosions, hits and deaths it plays as effects, and up to MARKS mode
## objectives (Capture the Flag's flags: MatchMode.replay_mark_count / replay_mark_state /
## _carrier / _pos, state, carrier and position). A remote player's entry is the interpolated
## pose this peer shows, which runs Player.INTERP_DELAY behind the events it receives, so a replay
## reads remote poses that much later and they line up with their shots. Nothing is sent over the
## network for it, and nothing is recorded in Tactical (no respawns: the dead spectate) or with
## both the `killcam` and the `clips` setting off. The buffers are preallocated packed arrays, so
## recording allocates nothing per frame. The ring is long enough for a clip (ClipRecorder:
## Clips.BEFORE before a kill, saved up to Clips.SAVE_WINDOW after it); `window(t_from, t_to)`
## copies a span of it out.
##
## **Replay.** When another player kills the local player (World._s_killed), the replay starts
## START_DELAY after the death. It shows the last moments up to TAIL past the kill from the
## killer's eyes through a ReplayView: their recorded eye, aim and stance drive its camera and a
## Viewmodel built with the killer's outfit, skin, charm and camos (gun, kick, muzzle flash,
## reload, knife, throw), their shots draw tracers and impacts, and everyone else is a ghost
## Avatar at their recorded pose (the local player's own ghost is labelled YOU). The mode draws
## its objectives at their recorded state through replay_mark_state / replay_mark_carrier /
## replay_mark_pos and replay_ghost (Capture the Flag puts a carried flag on the carrier's
## ghost). KillCamOverlay draws the KILLCAM banner, the skip key (`skip_killcam`) and progress.
## The replay ends END_MARGIN before the respawn at the latest: its length is the respawn delay
## minus START_DELAY and END_MARGIN, at most MAX_LEN, and none plays under MIN_LEN; a respawn, the
## end of the match or the skip key ends it at once. When it starts, the window is copied out of
## the ring into a second Tape, so recording carries on during the replay.
## The live match keeps running underneath: the replay only swaps the current camera, hides the
## live avatars, projectiles and the HUD's own cards (Hud.set_killcam) and the mode overlays
## (canvas layer 11), and reads no gameplay state back. A frozen offline match (pause) freezes it,
## since its clock is World.now().

const RATE := 30.0
## Seconds the ring holds: a clip's lead-in before a kill plus the time allowed to save it.
const RING_SECONDS := 22.0
## Ring size: RING_SECONDS at up to RATE / 0.9 frames a second (a frame is due 0.9 / RATE after
## the last), plus slack for a copy window's edges.
const FRAMES := 744
## The replay's copy: MAX_LEN at RATE plus slack.
const PLAY_FRAMES := 152
## Players recorded; every mode with respawns has at most 12.
const SLOTS := 16
## Projectiles recorded per frame.
const PROJ := 8
## Mode objectives recorded per frame (Capture the Flag's two flags).
const MARKS := 2
## Effect events kept (shots of a full lobby over the ring's span), and in the replay's copy.
const EVENTS := 2048
const PLAY_EVENTS := 512
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
## Projectile and explosion kinds (index stored in the tape; new kinds go at the end).
const KINDS: Array[String] = ["rocket", "grenade", "smoke", "flash", "bomber", "cube_lobber"]

## Effect event kinds (stored in saved clips: new kinds go at the end).
enum Ev { SHOT, PELLET, SLASH, THROW, ROCKET, EXPLODE, HIT, DEATH }


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
	## Per frame and mode objective: its state (-1: none), carrier entity id and position.
	var mark_state := PackedInt32Array()
	var mark_carrier := PackedInt32Array()
	var mark_pos := PackedVector3Array()
	var ev_cap := 0
	var ev_count := 0
	var ev_head := 0
	var ev_time := PackedFloat64Array()
	var ev_kind := PackedInt32Array()
	var ev_eid := PackedInt32Array()
	var ev_arg := PackedInt32Array()
	var ev_a := PackedVector3Array()
	var ev_b := PackedVector3Array()
	## Result of the last sample_slot.
	var s_pos := Vector3.ZERO
	var s_eye := Vector3.ZERO
	var s_yaw := 0.0
	var s_pitch := 0.0
	var s_flags := 0
	var s_vel := Vector3.ZERO

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
		mark_state.resize(cap * MARKS)
		mark_carrier.resize(cap * MARKS)
		mark_pos.resize(cap * MARKS)
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

	## Ring index of logical event `i` (0 the oldest).
	func ev_at(i: int) -> int:
		return (ev_head + i) % ev_cap

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
		for k in MARKS:
			mark_state[f * MARKS + k] = -1
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

	## Time of the first and last frame ([0, 0] when empty).
	func span() -> Vector2:
		if count == 0:
			return Vector2.ZERO
		return Vector2(times[at(0)], times[at(count - 1)])

	## The slot `eid` was recorded in (-1: never).
	func slot_of(eid: int) -> int:
		for i in count:
			var base := at(i) * slots
			for s in slots:
				if ids[base + s] == eid:
					return s
		return -1

	## Every entity id recorded.
	func entity_ids() -> PackedInt32Array:
		var seen := {}
		for i in count:
			var base := at(i) * slots
			for s in slots:
				if ids[base + s] != 0:
					seen[ids[base + s]] = true
		return PackedInt32Array(seen.keys())

	## Interpolated state of slot `slot` (entity `eid`) at `t` into the s_* fields; false when the
	## tape has no entry for it there. A remote player's entry is read Player.INTERP_DELAY later.
	func sample_slot(slot: int, eid: int, t: float) -> bool:
		if slot < 0 or not _sample_at(slot, eid, t):
			return false
		if (s_flags & BIT_REMOTE) != 0:
			_sample_at(slot, eid, t + Player.INTERP_DELAY)
		return true

	func _sample_at(slot: int, eid: int, t: float) -> bool:
		var i := find(t)
		if i < 0:
			return false
		var j := mini(i + 1, count - 1)
		var fa := at(i)
		var fb := at(j)
		var a := fa * slots + slot
		var b := fb * slots + slot
		var ok_a := ids[a] == eid
		var ok_b := ids[b] == eid
		if not ok_a and not ok_b:
			return false
		if not ok_a:
			a = b
		elif not ok_b:
			b = a
		var k := 0.0
		s_vel = Vector3.ZERO
		if a != b:
			var dt := times[fb] - times[fa]
			k = clampf((t - times[fa]) / dt, 0.0, 1.0) if dt > 0.0001 else 1.0
			var step := pos[b] - pos[a]
			if step.length() > SNAP_DIST:
				k = 0.0 if k < 0.5 else 1.0
			elif dt > 0.0001:
				s_vel = step / dt
		s_pos = pos[a].lerp(pos[b], k)
		s_eye = eye[a].lerp(eye[b], k)
		s_yaw = lerp_angle(yaw[a], yaw[b], k)
		s_pitch = lerpf(pitch[a], pitch[b], k)
		s_flags = flags[a] if k < 1.0 else flags[b]
		return true

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
			for k in MARKS:
				mark_state[f * MARKS + k] = src.mark_state[sf * MARKS + k]
				mark_carrier[f * MARKS + k] = src.mark_carrier[sf * MARKS + k]
				mark_pos[f * MARKS + k] = src.mark_pos[sf * MARKS + k]
			if src.times[sf] > t_to:
				break
		for j in src.ev_count:
			var e := src.ev_at(j)
			var t := src.ev_time[e]
			if t >= t_from and t <= t_to:
				add_event(t, src.ev_kind[e], src.ev_eid[e], src.ev_arg[e], src.ev_a[e], src.ev_b[e])

	## The frames and events in logical order as packed arrays (a saved clip, Clips).
	func to_dict() -> Dictionary:
		var out := Tape.new(maxi(count, 1), slots, proj, maxi(ev_count, 1))
		out.copy_from(self, -INF, INF)
		return {"slots": slots, "proj": proj, "count": count, "times": out.times.slice(0, count),
			"ids": out.ids.slice(0, count * slots), "pos": out.pos.slice(0, count * slots),
			"eye": out.eye.slice(0, count * slots), "yaw": out.yaw.slice(0, count * slots),
			"pitch": out.pitch.slice(0, count * slots), "flags": out.flags.slice(0, count * slots),
			"proj_id": out.proj_id.slice(0, count * proj), "proj_kind": out.proj_kind.slice(0, count * proj),
			"proj_pos": out.proj_pos.slice(0, count * proj),
			"ev_count": ev_count, "ev_time": out.ev_time.slice(0, ev_count), "ev_kind": out.ev_kind.slice(0, ev_count),
			"ev_eid": out.ev_eid.slice(0, ev_count), "ev_arg": out.ev_arg.slice(0, ev_count),
			"ev_a": out.ev_a.slice(0, ev_count), "ev_b": out.ev_b.slice(0, ev_count)}

	## A tape from to_dict()'s output; null when it is malformed (a damaged or foreign file).
	static func from_dict(d: Dictionary) -> Tape:
		var n := int(d.get("count", 0))
		var s := int(d.get("slots", 0))
		var p := int(d.get("proj", 0))
		var ne := int(d.get("ev_count", 0))
		if n < 1 or s < 1 or s > 64 or p < 0 or p > 64 or ne < 0:
			return null
		var typed := {"times": TYPE_PACKED_FLOAT64_ARRAY, "ids": TYPE_PACKED_INT32_ARRAY, "pos": TYPE_PACKED_VECTOR3_ARRAY,
			"eye": TYPE_PACKED_VECTOR3_ARRAY, "yaw": TYPE_PACKED_FLOAT32_ARRAY, "pitch": TYPE_PACKED_FLOAT32_ARRAY,
			"flags": TYPE_PACKED_INT32_ARRAY, "proj_id": TYPE_PACKED_INT32_ARRAY, "proj_kind": TYPE_PACKED_INT32_ARRAY,
			"proj_pos": TYPE_PACKED_VECTOR3_ARRAY, "ev_time": TYPE_PACKED_FLOAT64_ARRAY, "ev_kind": TYPE_PACKED_INT32_ARRAY,
			"ev_eid": TYPE_PACKED_INT32_ARRAY, "ev_arg": TYPE_PACKED_INT32_ARRAY, "ev_a": TYPE_PACKED_VECTOR3_ARRAY,
			"ev_b": TYPE_PACKED_VECTOR3_ARRAY}
		var sizes := {"times": n, "ids": n * s, "pos": n * s, "eye": n * s, "yaw": n * s, "pitch": n * s, "flags": n * s,
			"proj_id": n * p, "proj_kind": n * p, "proj_pos": n * p, "ev_time": ne, "ev_kind": ne, "ev_eid": ne,
			"ev_arg": ne, "ev_a": ne, "ev_b": ne}
		for key: String in typed:
			if typeof(d.get(key)) != typed[key] or (d[key] as Variant).size() != sizes[key]:
				return null
		var t := Tape.new(n, s, p, maxi(ne, 1))
		t.count = n
		for key: String in typed:
			t.set(key, d[key].duplicate())
		t.times.resize(n)
		t.ev_count = ne
		for key: String in ["ev_time", "ev_kind", "ev_eid", "ev_arg", "ev_a", "ev_b"]:
			(t.get(key) as Variant).resize(maxi(ne, 1))
		return t


var world: World
## The last replay, for checks: {death_t, start_t, end_t, reason, len, frames, killer, wid}
## (World.now() times).
var last := {}
## Replays played this match.
var replays := 0

var _tape := Tape.new(FRAMES, SLOTS, PROJ, EVENTS)
var _play := Tape.new(PLAY_FRAMES, SLOTS, PROJ, PLAY_EVENTS)
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
var _wid := ""
var _kill_t := 0.0
var _len := 0.0
## Recorded time the replay starts at, and World.now() when it started.
var _t0 := 0.0
var _started_at := 0.0

var _view: ReplayView
var _overlay: KillCamOverlay
var _entities_root: Node3D
var _hidden_layers: Array[CanvasLayer] = []


func _ready() -> void:
	_slot_eid.resize(SLOTS)
	_slot_seen.resize(SLOTS)
	_view = ReplayView.new()
	_view.visible = false
	_view.fx = world.fx
	_view.info_of = _live_info
	_view.look_of = _copy_look
	add_child(_view)
	_overlay = KillCamOverlay.new()
	_overlay.name = "KillCamOverlay"
	add_child(_overlay)
	_entities_root = world.get_node(^"Entities")


# ================================================================ recording

## Whether the match is being recorded now (kill cam or clips on, a mode with respawns).
func is_recording() -> bool:
	return _recording


func _physics_process(_delta: float) -> void:
	var wanted := bool(Profile.get_setting("killcam")) or bool(Profile.get_setting("clips"))
	var on := wanted and not world.match_over and world.local_player != null and world.rules.respawn_delay() >= 0.0
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
	_record(_tape, t)


## Records the scene at `t` as a new frame of `tape`.
func _record(tape: Tape, t: float) -> void:
	var f := tape.begin_frame(t)
	var base := f * tape.slots
	for eid: int in world.entities:
		var s := _slot(eid, t) if tape == _tape else _free_slot(tape, f, eid)
		if s < 0:
			continue
		var p: Player = world.entities[eid]
		var i := base + s
		tape.ids[i] = eid
		tape.pos[i] = p.global_position
		tape.eye[i] = p.head.global_position
		tape.yaw[i] = p.yaw
		tape.pitch[i] = p.pitch
		var fl := p.net_flags()
		if p.alive:
			fl |= BIT_ALIVE
		if p.mode == Player.Mode.REMOTE:
			fl |= BIT_REMOTE
		if p.grappling:
			fl |= BIT_GRAPPLE
		tape.flags[i] = fl
	var n := 0
	var pb := f * tape.proj
	for pid: int in world.projectiles:
		if n >= tape.proj:
			break
		var proj: Projectile = world.projectiles[pid]
		if not proj.in_flight():
			continue
		tape.proj_id[pb + n] = pid
		tape.proj_kind[pb + n] = KINDS.find(proj.kind)
		tape.proj_pos[pb + n] = proj.global_position
		n += 1
	var rules := world.rules
	for k in mini(rules.replay_mark_count(), MARKS):
		tape.mark_state[f * MARKS + k] = rules.replay_mark_state(k)
		tape.mark_carrier[f * MARKS + k] = rules.replay_mark_carrier(k)
		tape.mark_pos[f * MARKS + k] = rules.replay_mark_pos(k)


func _slot(eid: int, t: float) -> int:
	var s: int = _slot_of.get(eid, -1)
	if s >= 0:
		_slot_seen[s] = t
		return s
	for i in SLOTS:
		if _slot_eid[i] == 0 or t - _slot_seen[i] > RING_SECONDS + 1.0:
			if _slot_eid[i] != 0:
				_slot_of.erase(_slot_eid[i])
			_slot_eid[i] = eid
			_slot_of[eid] = i
			_slot_seen[i] = t
			return i
	return -1


## A snapshot's slot: the first empty one of frame `f` (-1 when full).
static func _free_slot(tape: Tape, f: int, _eid: int) -> int:
	for s in tape.slots:
		if tape.ids[f * tape.slots + s] == 0:
			return s
	return -1


## The scene right now as a one-frame tape (a photo's scene, PhotoMode), with up to Data.MAX_PLAYERS
## players whatever the mode.
func snapshot() -> Tape:
	var tape := Tape.new(1, maxi(world.entities.size(), 1), PROJ, 1)
	_record(tape, World.now())
	return tape


## A copy of the ring's frames and events from `t_from` to `t_to` (a clip, ClipRecorder). Frames
## come up to 1 / 0.9 times RATE (see _physics_process), so the copy has room for that many.
func window(t_from: float, t_to: float) -> Tape:
	var tape := Tape.new(ceili((t_to - t_from) * RATE / 0.9) + 8, SLOTS, PROJ, EVENTS)
	tape.copy_from(_tape, t_from, t_to)
	return tape


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


## World._s_spawn_projectile: `owner_id` fired a launcher (rocket, Cube Lobber) or threw a grenade.
func record_launch(owner_id: int, kind: String) -> void:
	if _recording:
		_tape.add_event(World.now(), Ev.ROCKET if Data.WEAPONS.has(kind) else Ev.THROW, owner_id, KINDS.find(kind), Vector3.ZERO, Vector3.ZERO)


## World._s_explode and Streaks' Block Bomber blasts (`kind` "bomber").
func record_explosion(pos: Vector3, kind: String) -> void:
	if _recording:
		_tape.add_event(World.now(), Ev.EXPLODE, 0, KINDS.find(kind), pos, Vector3.ZERO)


## World._s_damaged: another player hurt `p` (blood in the replay).
func record_hit(p: Player) -> void:
	if _recording:
		_tape.add_event(World.now(), Ev.HIT, p.id, 0, p.global_position + Vector3.UP * (p.body_center_height() - 0.15), Vector3.ZERO)


## World._s_killed: `p` died (the death burst and sound in a clip).
func record_death(p: Player) -> void:
	if _recording:
		_tape.add_event(World.now(), Ev.DEATH, p.id, 0, p.global_position + Vector3.UP * 0.9, Vector3.ZERO)


## Checks: what the ring holds now.
func buffer_info() -> Dictionary:
	var s := _tape.span()
	return {"frames": _tape.count, "frame_cap": _tape.cap, "events": _tape.ev_count, "event_cap": _tape.ev_cap,
		"span": s.y - s.x, "slots": _slot_of.size(), "ghosts": _view.get_children().filter(func(c: Node) -> bool: return c is Avatar).size()}


## Checks: the pose this peer recorded for `eid` at World.now() time `t`, as a replay reads it
## (a remote player's interpolated pose INTERP_DELAY later); {} when not recorded.
func recorded_pose(eid: int, t: float) -> Dictionary:
	var s: int = _slot_of.get(eid, -1)
	if not _tape.sample_slot(s, eid, t):
		return {}
	return {"pos": _tape.s_pos, "eye": _tape.s_eye, "yaw": _tape.s_yaw, "pitch": _tape.s_pitch,
		"weapon": Player.flags_weapon(_tape.s_flags), "alive": (_tape.s_flags & BIT_ALIVE) != 0}


# ================================================================ replay

## World._s_killed: `killer_id` killed the local player with `wid`. Schedules the replay when it
## can play: someone else killed us, the setting is on, the mode respawns, and the respawn delay
## leaves room for at least MIN_LEN.
func on_local_death(killer_id: int, wid: String) -> void:
	stop("death")
	if not _recording or not bool(Profile.get_setting("killcam")) or killer_id == world.my_id() \
			or world.match_over or not world.entities.has(killer_id):
		return
	# A death the player doesn't come back from (One in the Chamber's last life) has no replay.
	var delay := world.rules.respawn_delay() if world.rules.respawns(world.my_id()) else -1.0
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
	var killer_slot: int = _slot_of.get(_killer, -1)
	# The killer may have spawned or joined inside the window: start at their first frame.
	var first := -1.0
	if killer_slot >= 0:
		for i in _play.count:
			if _play.ids[_play.at(i) * SLOTS + killer_slot] == _killer:
				first = _play.times[_play.at(i)]
				break
	if first < 0.0 or end_t - maxf(_t0, first) < MIN_LEN * 0.5:
		last.reason = "no data"
		return
	_t0 = maxf(_t0, first)
	_len = end_t - _t0
	_view.tag_eid = world.my_id()
	_view.base_fov = float(Profile.get_setting("fov"))
	_view.frames_played = 0
	_view.begin(_play, _t0, _killer)
	_show_view(world.entities[_killer])
	_playing = true
	_started_at = World.now()
	replays += 1
	last.start_t = _started_at
	last.len = _len
	last.reason = "playing"
	_step(0.0)


func _show_view(killer: Player) -> void:
	_view.visible = true
	_view.camera.make_current()
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
	_view.visible = false
	_view.hide_all()
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
	last.frames = _view.frames_played


func _hide_live_projectiles() -> void:
	for pid: int in world.projectiles:
		(world.projectiles[pid] as Node3D).visible = false


## A live entity's info for the replay's ghosts ({} once it has left).
func _live_info(eid: int) -> Dictionary:
	var p: Player = world.entities.get(eid)
	return p.info if p != null else {}


## While a replay plays: the recorded state of mode objective `k` at the replayed moment (-1: none
## recorded), its carrier's entity id and its position (MatchMode.replay_mark_*).
func replay_mark_state(k: int) -> int:
	return _play.mark_state[_mark_frame() * MARKS + k] if _playing and k < MARKS and _play.count > 0 else -1


func replay_mark_carrier(k: int) -> int:
	return _play.mark_carrier[_mark_frame() * MARKS + k] if _playing and k < MARKS and _play.count > 0 else 0


func replay_mark_pos(k: int) -> Vector3:
	return _play.mark_pos[_mark_frame() * MARKS + k] if _playing and k < MARKS and _play.count > 0 else Vector3.ZERO


## Ring index of the replay frame at or before the replayed moment.
func _mark_frame() -> int:
	return _play.at(maxi(0, _play.find(_view.replay_t)))


## While a replay plays: the ghost avatar standing in for `eid` (null for the killer, whose eyes the
## replay looks through, and for anyone not shown).
func replay_ghost(eid: int) -> Avatar:
	return _view.ghost_of(eid) if _playing else null


func _step(delta: float) -> void:
	var r := World.now() - _started_at
	if r >= _len:
		_finish("end")
		return
	_overlay.set_progress(r / _len)
	_hide_live_projectiles()
	_view.step(_t0 + r, delta)
	_overlay.set_scope(_view.scoped, _view.scope_style)


## Team armbands, a tint (Infected) and Big Heads' scaled head, copied from the live avatar.
func _copy_look(eid: int, g: Avatar) -> void:
	var p: Player = world.entities.get(eid)
	if p == null:
		return
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
