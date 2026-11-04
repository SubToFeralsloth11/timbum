class_name ReplayView
extends Node3D
## Plays back a KillCam.Tape: every recorded player as a ghost Avatar at their recorded pose
## (gun, reload, slide, lean, death), the projectiles in flight and the effect events (shots with
## tracers and impacts, knife swings, throws, launches, explosions, blood) with their sounds.
## One player can be watched through their own eyes (`pov`): their recorded eye, aim and stance
## drive `camera` and a Viewmodel built with their look, and their ghost stays hidden. The kill cam
## (KillCam) and the clip editor (Studio) both use it.
##
## The owner calls `begin` (a tape, the moment to start at, the POV player), then `step` with the
## replayed moment every frame; `seek` jumps without firing the events in between. Who each
## recorded entity is comes from `info_of(eid) -> Dictionary` (the player info: outfit, hat, skin,
## charm, draw, camos; {} when unknown, and the entity is then not drawn) and the optional
## `look_of(eid, ghost)` dresses a ghost (team armbands, tint, Big Heads).

var fx: Fx
var tape: KillCam.Tape
var info_of: Callable
var look_of: Callable
## The entity labelled `tag_text` over its ghost (0: none).
var tag_eid := 0
var tag_text := "YOU"
## The camera the POV player's eyes drive (the owner makes it current).
var camera: Camera3D
## Whose eyes `camera` follows (0: nobody; every ghost shows).
var pov := 0
## Field of view the POV camera starts from (it narrows toward the gun's when aiming).
var base_fov := 90.0
## After each step: the POV gun is scoped and aimed in (the owner draws the scope).
var scoped := false
var scope_style := "sniper"
## The replayed moment of the last step or seek.
var replay_t := 0.0
var frames_played := 0

## Result of the last sample().
var s_pos := Vector3.ZERO
var s_eye := Vector3.ZERO
var s_yaw := 0.0
var s_pitch := 0.0
var s_flags := 0
var s_vel := Vector3.ZERO

var _ev_next := 0
var _viewmodel: Viewmodel
var _vm_key := ""
var _ads := 0.0
var _cam_weapon := ""
var _cam_reloading := false
## Seconds the POV player has been charging a charge weapon (Player.FLAG_CHARGE), for its glow.
var _cam_charge := 0.0
var _cam_ads_fov := 60.0
var _cam_scoped := false
var _tag: Label3D
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
## Recording slot of each entity id in `tape` (filled as entities are looked up).
var _slot_cache := {}


func _init() -> void:
	name = "Replay"
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.05
	camera.far = 400.0
	add_child(camera)
	_tag = Label3D.new()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.fixed_size = true
	_tag.pixel_size = 0.0012
	_tag.font_size = 40
	_tag.outline_size = 10
	_tag.modulate = Color(1.0, 0.35, 0.3)
	_tag.visible = false
	add_child(_tag)


## Starts playing `p_tape` at `t0` through `p_pov`'s eyes (0: nobody). Ghosts kept from an earlier
## replay are reused unless their entity is unknown now or changed its look.
func begin(p_tape: KillCam.Tape, t0: float, p_pov: int) -> void:
	tape = p_tape
	_slot_cache.clear()
	_fit_slots(tape.slots, tape.proj)
	for s in _ghosts.size():
		_g_alive[s] = true
		_g_seen_alive[s] = false
		_g_reload[s] = false
		if _ghosts[s] == null:
			continue
		var info: Dictionary = info_of.call(_g_eid[s])
		if info.is_empty() or look_key(info) != _g_look[s]:
			# Gone, or a new outfit or hat: rebuilt when needed.
			_ghosts[s].queue_free()
			_ghosts[s] = null
			_g_eid[s] = 0
			continue
		_ghosts[s].visible = false
		_ghosts[s].reset_pose()
		_g_info[s] = info
		if look_of.is_valid():
			look_of.call(_g_eid[s], _ghosts[s])
	set_pov(p_pov)
	seek(t0)


## Watches `eid` through their eyes (0: nobody, their ghost shows like everyone else's).
func set_pov(eid: int) -> void:
	pov = eid
	_ads = 0.0
	_cam_reloading = false
	_cam_charge = 0.0
	scoped = false
	if eid == 0:
		if _viewmodel != null:
			_viewmodel.visible = false
		return
	var info: Dictionary = info_of.call(eid)
	var camos: Variant = info.get("camos", [])
	var key := "%s|%s|%s|%s|%s" % [info.get("outfit", "classic"), info.get("skin", "default"), info.get("charm", "none"),
		info.get("draw", "standard"), str(camos)]
	if key != _vm_key or _viewmodel == null:
		if _viewmodel != null:
			_viewmodel.queue_free()
		_vm_key = key
		_viewmodel = Viewmodel.new()
		_viewmodel.setup(str(info.get("outfit", "classic")), str(info.get("skin", "default")), str(info.get("charm", "none")),
			str(info.get("draw", "standard")), camos if typeof(camos) == TYPE_ARRAY else [])
		camera.add_child(_viewmodel)
	_cam_weapon = ""
	_viewmodel.visible = true
	camera.fov = base_fov


## Jumps to `t` without playing the effects before it (those at `t` play on the next step); a
## ghost already dead there stays hidden until it is alive again.
func seek(t: float) -> void:
	replay_t = t
	_ev_next = 0
	while _ev_next < tape.ev_count and tape.ev_time[tape.ev_at(_ev_next)] < t:
		_ev_next += 1
	for s in _g_alive.size():
		_g_alive[s] = true
		_g_seen_alive[s] = false
		_g_reload[s] = false
		if _ghosts[s] != null:
			_ghosts[s].reset_pose()
			_g_wid[s] = ""
	_cam_reloading = false
	if _viewmodel != null:
		_viewmodel.stop_reload()


## Poses everything at the replayed moment `t` and plays the effects recorded up to it.
func step(t: float, delta: float) -> void:
	replay_t = t
	frames_played += 1
	_pose_pov(t, delta)
	_pose_ghosts(t, delta)
	_pose_projectiles(t)
	while _ev_next < tape.ev_count and tape.ev_time[tape.ev_at(_ev_next)] <= t:
		_fire_event(tape.ev_at(_ev_next))
		_ev_next += 1


## Hides every ghost and projectile (the owner shows the live scene again).
func hide_all() -> void:
	for g in _ghosts:
		if g != null:
			g.visible = false
	for n in _proj_nodes:
		if n != null:
			n.visible = false
	_tag.visible = false


## The ghost standing in for `eid` now (null for the POV player and anyone not shown).
func ghost_of(eid: int) -> Avatar:
	if eid == 0 or eid == pov:
		return null
	for s in _ghosts.size():
		if _g_eid[s] == eid and _ghosts[s] != null and _ghosts[s].visible:
			return _ghosts[s]
	return null


## Recording slot of `eid` in the tape (-1: never recorded).
func slot_of(eid: int) -> int:
	if not _slot_cache.has(eid):
		_slot_cache[eid] = tape.slot_of(eid)
	return _slot_cache[eid]


## Interpolated state of `eid` at `t` into the s_* fields (KillCam.Tape.sample_slot); false when
## the tape has no entry for it there.
func sample(eid: int, t: float) -> bool:
	return sample_slot(slot_of(eid), eid, t)


func sample_slot(slot: int, eid: int, t: float) -> bool:
	if not tape.sample_slot(slot, eid, t):
		return false
	s_pos = tape.s_pos
	s_eye = tape.s_eye
	s_yaw = tape.s_yaw
	s_pitch = tape.s_pitch
	s_flags = tape.s_flags
	s_vel = tape.s_vel
	return true


func _fit_slots(slots: int, proj: int) -> void:
	while _ghosts.size() < slots:
		_ghosts.append(null)
		_g_eid.append(0)
		_g_look.append("")
		_g_wid.append("")
		_g_info.append({})
		_g_alive.append(true)
		_g_seen_alive.append(false)
		_g_reload.append(false)
	while _proj_nodes.size() < proj:
		_proj_nodes.append(null)
		_proj_node_kind.append(-1)


func _pose_pov(t: float, delta: float) -> void:
	scoped = false
	if pov == 0 or _viewmodel == null or not sample(pov, t):
		return
	var fl := s_flags
	var wid := Player.flags_weapon(fl)
	if wid != _cam_weapon:
		var w: Dictionary = Data.WEAPONS[wid]
		_viewmodel.set_weapon(wid, 0.05 if _cam_weapon.is_empty() else Player.SWITCH_TIME)
		_cam_weapon = wid
		_cam_ads_fov = float(w.ads_fov)
		_cam_scoped = w.get("scope", false)
		scope_style = str(w.get("scope_style", "sniper"))
	_ads = move_toward(_ads, 1.0 if (fl & Player.FLAG_AIM) != 0 else 0.0, delta * 6.0)
	var sliding := (fl & Player.FLAG_SLIDE) != 0
	var roll := -Player.flags_lean(fl) * Player.LEAN_ROLL + (deg_to_rad(-4.0) if sliding else 0.0)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(s_pitch, s_yaw, roll)), s_eye)
	camera.fov = lerpf(base_fov, minf(_cam_ads_fov, base_fov), _ads)
	var reloading := (fl & Player.FLAG_RELOAD) != 0
	if reloading and not _cam_reloading:
		_viewmodel.play_reload(float(Data.WEAPONS[wid].reload))
	elif _cam_reloading and not reloading:
		_viewmodel.stop_reload()
	_cam_reloading = reloading
	var charge_time := float(Data.WEAPONS[wid].get("charge_time", 0.0))
	_cam_charge = minf(_cam_charge + delta, charge_time) if charge_time > 0.0 and (fl & Player.FLAG_CHARGE) != 0 else 0.0
	_viewmodel.set_charge(_cam_charge / charge_time if charge_time > 0.0 else 0.0)
	var alive := (fl & KillCam.BIT_ALIVE) != 0
	_viewmodel.visible = alive
	var local_vel := Basis(Vector3.UP, s_yaw).inverse() * s_vel
	_viewmodel.pose(delta, _ads, (fl & Player.FLAG_SPRINT) != 0, sliding, (fl & KillCam.BIT_GRAPPLE) != 0, local_vel,
		(fl & Player.FLAG_FLOOR) != 0, Vector2(s_vel.x, s_vel.z).length(), (fl & Player.FLAG_CROUCH) != 0)
	scoped = alive and _cam_scoped and _ads > 0.85


func _pose_ghosts(t: float, delta: float) -> void:
	_tag.visible = false
	var i := maxi(0, tape.find(t))
	var fa := tape.at(i) * tape.slots
	var fb := tape.at(mini(i + 1, tape.count - 1)) * tape.slots
	for s in tape.slots:
		var eid := tape.ids[fa + s]
		if eid == 0:
			eid = tape.ids[fb + s]
		var g := _ghosts[s]
		if eid == 0 or eid == pov or not sample_slot(s, eid, t):
			if g != null:
				g.visible = false
			continue
		g = _ghost(s, eid)
		if g == null:
			continue
		var fl := s_flags
		var alive := (fl & KillCam.BIT_ALIVE) != 0
		g.position = s_pos
		g.rotation.y = s_yaw
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
		var local_vel := Basis(Vector3.UP, s_yaw).inverse() * s_vel
		g.set_motion((fl & Player.FLAG_SLIDE) != 0, Player.flags_lean(fl), Vector2(local_vel.x, -local_vel.z), (fl & KillCam.BIT_GRAPPLE) != 0)
		g.set_look_pitch(s_pitch)
		g.animate(delta, Vector2(s_vel.x, s_vel.z).length(), (fl & Player.FLAG_FLOOR) != 0,
			(fl & Player.FLAG_CROUCH) != 0, (fl & Player.FLAG_PRONE) != 0)
		if eid == tag_eid:
			_tag.text = tag_text
			_tag.visible = true
			_tag.position = s_pos + Vector3.UP * 2.35


## The ghost avatar of `eid` in slot `s`, built (or rebuilt for another entity or a new look) on
## first use and kept for later replays; null when the entity is unknown.
func _ghost(s: int, eid: int) -> Avatar:
	var g := _ghosts[s]
	if g != null and _g_eid[s] == eid:
		return g
	var info: Dictionary = info_of.call(eid)
	if info.is_empty():
		if g != null:
			g.visible = false
		return null
	if g != null:
		g.queue_free()
	g = Models.build_avatar(str(info.get("outfit", "classic")), str(info.get("hat", "none")))
	g.charm_id = str(info.get("charm", "none"))
	g.name = "Ghost%d" % s
	add_child(g)
	if look_of.is_valid():
		look_of.call(eid, g)
	_ghosts[s] = g
	_g_eid[s] = eid
	_g_look[s] = look_key(info)
	_g_info[s] = info
	_g_wid[s] = ""
	_g_alive[s] = true
	return g


static func look_key(info: Dictionary) -> String:
	return "%s|%s|%s" % [info.get("outfit", ""), info.get("hat", ""), info.get("charm", "none")]


func _pose_projectiles(t: float) -> void:
	var i := maxi(0, tape.find(t))
	var j := mini(i + 1, tape.count - 1)
	var fa := tape.at(i)
	var fb := tape.at(j)
	var span := tape.times[fb] - tape.times[fa]
	var k := clampf((t - tape.times[fa]) / span, 0.0, 1.0) if span > 0.0001 else 0.0
	var np := tape.proj
	for n in np:
		var pid := tape.proj_id[fa * np + n]
		var node := _proj_nodes[n]
		if pid == 0:
			if node != null:
				node.visible = false
			continue
		var kind := tape.proj_kind[fa * np + n]
		var from := tape.proj_pos[fa * np + n]
		var to := from
		for m in np:
			if tape.proj_id[fb * np + m] == pid:
				to = tape.proj_pos[fb * np + m]
				break
		if node == null or _proj_node_kind[n] != kind:
			if node != null:
				node.queue_free()
			match KillCam.KINDS[clampi(kind, 0, KillCam.KINDS.size() - 1)]:
				"rocket": node = Models.build_rocket()
				"grenade": node = Models.build_grenade()
				"cube_lobber": node = Models.build_lobber_shell()
				var tactical: node = Models.build_tactical(tactical)
			add_child(node)
			_proj_nodes[n] = node
			_proj_node_kind[n] = kind
		node.visible = true
		node.position = from.lerp(to, k)
		var dir := to - from
		if kind == 0 and dir.length_squared() > 0.0001:
			dir = dir.normalized()
			node.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)


## Plays event `e` (a ring index into the tape's events).
func _fire_event(e: int) -> void:
	var kind := tape.ev_kind[e]
	var eid := tape.ev_eid[e]
	var a := tape.ev_a[e]
	var b := tape.ev_b[e]
	var mine := eid == pov and pov != 0
	var g := ghost_of(eid)
	match kind:
		KillCam.Ev.SHOT, KillCam.Ev.PELLET:
			var wid := Player.weapon_from_index(tape.ev_arg[e])
			var w: Dictionary = Data.WEAPONS[wid]
			var suppressed: bool = w.get("suppressed", false)
			var muzzle := _muzzle(g, mine)
			if kind == KillCam.Ev.SHOT:
				if mine:
					_viewmodel.play_fire(float(w.recoil))
					Sfx.play(StringName(w.sound), null, -3.0, float(w.get("pitch", 1.0)))
				elif g != null:
					g.play_shoot()
					Sfx.play(StringName(w.sound), muzzle, 0.0, float(w.get("pitch", 1.0)))
					if not suppressed:
						fx.muzzle_flash(muzzle)
			if w.get("beam", false):
				fx.rail_beam(muzzle, a)
			elif mine or (g != null and not suppressed):
				fx.tracer(muzzle, a)
			if b != Vector3.ZERO:
				fx.impact(a, b)
		KillCam.Ev.SLASH:
			var mw: Dictionary = Data.WEAPONS[Player.weapon_from_index(tape.ev_arg[e])]
			var swing := StringName(mw.sound)
			if mine:
				_viewmodel.play_melee(false)
				Sfx.play(swing, null, -4.0, float(mw.get("pitch", 1.0)))
			elif g != null:
				g.play_slash()
				Sfx.play(swing, g.global_position, -4.0, float(mw.get("pitch", 1.0)))
			if b != Vector3.ZERO:
				fx.impact(a, b)
		KillCam.Ev.THROW, KillCam.Ev.ROCKET:
			var rocket := kind == KillCam.Ev.ROCKET
			var launcher: String = KillCam.KINDS[clampi(tape.ev_arg[e], 0, KillCam.KINDS.size() - 1)]
			var sound := World.launch_sound(launcher) if rocket else &"grenade_throw"
			if mine:
				if rocket:
					_viewmodel.play_fire(float(Data.WEAPONS[launcher].recoil))
				else:
					_viewmodel.play_throw()
				Sfx.play(sound, null, -2.0)
			elif g != null:
				if rocket:
					g.play_shoot()
				else:
					g.play_throw()
				Sfx.play(sound, g.global_position)
		KillCam.Ev.EXPLODE:
			match KillCam.KINDS[clampi(tape.ev_arg[e], 0, KillCam.KINDS.size() - 1)]:
				"smoke":
					Sfx.play(&"smoke_pop", a)
				"flash":
					fx.flash_burst(a)
					Sfx.play(&"flashbang", a, 2.0)
				_:
					fx.explosion(a)
					Sfx.play(&"explosion", a, 2.0)
		KillCam.Ev.HIT:
			fx.blood(a)
		KillCam.Ev.DEATH:
			fx.death_burst(a, _shirt(eid))
			Sfx.play(&"death", a)


## Where a shot comes from: the POV first-person gun, a ghost's gun muzzle.
func _muzzle(g: Avatar, mine: bool) -> Vector3:
	if mine:
		return _viewmodel.muzzle_position()
	if g == null:
		return camera.global_position
	var gun := g.get_gun()
	var m := gun.get_node_or_null(^"Muzzle") as Node3D if gun != null else null
	return m.global_position if m != null else g.global_position + Vector3.UP * 1.4


## The shirt colour of `eid`'s outfit (the death burst's cubes, like World._s_killed).
func _shirt(eid: int) -> Color:
	var info: Dictionary = info_of.call(eid)
	var outfit: Dictionary = Data.OUTFITS.get(str(info.get("outfit", "classic")), Data.OUTFITS.classic)
	return outfit.shirt
