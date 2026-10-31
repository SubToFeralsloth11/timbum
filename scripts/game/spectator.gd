class_name Spectator
extends Node
## Spectating, World's child "Spectator" on every peer (`World.spectator`). Two users:
##   - a **spectator**: this peer's `Net.players` entry has `spectator` set (joined as one, or
##     switched from the pause menu / lobby; offline "Spectate bots"), so the server gave it no
##     entity (nothing to see, hit or collide with, no player slot: bots fill it). It gets the
##     FREE view (a FreeCam flown with the player's own bindings) and the FOLLOW view;
##   - a dead player in a mode without respawns (Tactical): the mode calls `begin_dead()` and the
##     view follows whom `MatchMode.spectate_candidates()` allows (Tactical: living teammates
##     first), FOLLOW only, until the player lives again or leaves.
## FOLLOW puts the camera at the followed player's eyes with their aim, lean and the FOV of their
## sights, hides their own body (shadows only, like a first-person player) and nametag, and shows
## a Viewmodel built from their outfit, skin, charm and camos posed from their state flags
## (weapon, aim, sprint, slide, crouch, reload; shots and throws from World's effects). `fire` /
## `next_weapon` follows the next living player, `aim` / `prev_weapon` the previous one,
## `spectate_view` switches between FREE and FOLLOW (spectators only); in FREE, `fire` follows the
## player nearest the middle of the view. A followed player who dies is watched for DEATH_HOLD s,
## then the next one. SpectatorOverlay shows who is watched (name, health, weapon, score).

enum View { OFF, FREE, FOLLOW }

## Seconds the view stays on a followed player who died before moving to the next.
const DEATH_HOLD := 2.0

var world: World
var view := View.OFF
## Who FOLLOW watches (null: nobody alive to follow).
var target: Player

var _cam: FreeCam
var _overlay: SpectatorOverlay
## Follow-only (a dead player); false for a spectator, who may also fly.
var _dead_mode := false
var _viewmodel: Viewmodel
var _vm_key := ""
var _vm_weapon := ""
var _ads := 0.0
var _ads_fov := 60.0
var _reloading := false
var _inspecting := false
var _target_dead_at := -1.0
var _last_pos := Vector3.ZERO
var _vel := Vector3.ZERO
## Photo mode is showing the scene from its own camera: no viewmodel, the followed body shows.
var _photo := false
## FREE only because nobody could be followed yet: FOLLOW starts once someone can be.
var _auto_follow := false
## The local player's last view, where a player who starts spectating begins (null: none yet).
var _last_view: Variant = null


func _init() -> void:
	name = "Spectator"


func _ready() -> void:
	_cam = FreeCam.new()
	_cam.name = "SpectatorCam"
	_cam.set_bounds(world.map_info.bounds)
	add_child(_cam)
	_overlay = SpectatorOverlay.new()
	_overlay.name = "SpectatorOverlay"
	_overlay.spectator = self
	add_child(_overlay)


## This peer watches without an entity (Net.players[me].spectator).
func is_spectator() -> bool:
	return Net.is_spectator(world.my_id()) and world.local_player == null


func is_active() -> bool:
	return view != View.OFF


## FOLLOW as a dead player (Tactical's after-death spectating).
func is_dead_follow() -> bool:
	return view != View.OFF and _dead_mode


func camera() -> Camera3D:
	return _cam


## A mode without respawns: the dead local player follows the players the mode allows.
func begin_dead() -> void:
	if view != View.OFF:
		return
	_start(true)


func _start(dead: bool) -> void:
	_dead_mode = dead
	var from := get_viewport().get_camera_3d()
	if dead and from != null:
		_cam.place(from.global_transform, float(Profile.get_setting("fov")))
	elif _last_view != null:
		_cam.place(_last_view, float(Profile.get_setting("fov")))
	else:
		var b := world.map_info.bounds
		_cam.place(Transform3D(Basis.from_euler(Vector3(-0.5, 0.0, 0.0)), b.get_center() + Vector3(0.0, b.size.y * 0.5 + 8.0, b.size.z * 0.4)), float(Profile.get_setting("fov")))
	_cam.make_current()
	world.hud.hide_death()
	target = null
	view = View.FOLLOW
	_cycle(1)
	# Nobody to follow yet (a joiner before the players arrive): fly until someone is there.
	_auto_follow = target == null
	if target == null and not _dead_mode:
		_set_view(View.FREE)


func _stop() -> void:
	_release_target()
	view = View.OFF
	_dead_mode = false
	_cam.active = false
	if _viewmodel != null:
		_viewmodel.visible = false
	_overlay.visible = false
	var me := world.local_player
	if _cam.current and me != null and me.camera != null:
		me.camera.make_current()


func _process(delta: float) -> void:
	var me := world.local_player
	if me != null and me.camera != null and me.camera.current:
		_last_view = me.camera.global_transform
	if is_spectator():
		if view == View.OFF or _dead_mode:
			_stop()
			_start(false)
	elif view != View.OFF and (not _dead_mode or world.local_player == null or world.local_player.alive):
		_stop()
	if view == View.OFF:
		return
	_cam.active = view == View.FREE and not world.input_blocked() and _cam.current
	# The winner's emote camera (match end) and photo mode take the view; leave them be.
	if not _cam.current:
		_overlay.visible = false
		return
	if view == View.FREE and _auto_follow and not world.rules.spectate_candidates().is_empty():
		_auto_follow = false
		_set_view(View.FOLLOW)
	if view == View.FOLLOW:
		_update_follow(delta)
	_overlay.visible = true
	_overlay.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if view == View.OFF or not _cam.current or world.input_blocked():
		return
	# A click on a freed mouse only recaptures it (the Hud does that).
	if event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		if view == View.FREE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_cam.look_mouse((event as InputEventMouseMotion).relative)
		return
	if event.is_action_pressed("spectate_view") and not _dead_mode:
		get_viewport().set_input_as_handled()
		_auto_follow = false
		_set_view(View.FREE if view == View.FOLLOW else View.FOLLOW)
	elif event.is_action_pressed("fire") or event.is_action_pressed("next_weapon"):
		get_viewport().set_input_as_handled()
		if view == View.FREE:
			_follow_nearest_to_view()
		else:
			_cycle(1)
	elif event.is_action_pressed("aim") or event.is_action_pressed("prev_weapon"):
		get_viewport().set_input_as_handled()
		if view == View.FOLLOW:
			_cycle(-1)


## Switches FREE <-> FOLLOW. FREE starts where the follow view was looking from.
func _set_view(v: View) -> void:
	if v == View.FREE and _dead_mode:
		return
	if v == View.FREE:
		_release_target()
		var t := _cam.global_transform
		_cam.place(t, float(Profile.get_setting("fov")))
		if _viewmodel != null:
			_viewmodel.visible = false
		view = View.FREE
		return
	view = View.FOLLOW
	if target == null:
		_cycle(1)
	if target == null and not _dead_mode:
		view = View.FREE


func _cycle(step: int) -> void:
	var list := world.rules.spectate_candidates()
	if list.is_empty():
		return
	var i := list.find(target)
	_set_target(list[posmod(i + step, list.size())] if i >= 0 else list[0])


## FREE: fire follows the living player closest to the middle of the view.
func _follow_nearest_to_view() -> void:
	var best: Player = null
	var best_dot := -2.0
	var fwd := -_cam.global_basis.z
	for p: Player in world.rules.spectate_candidates():
		var to := p.global_position + Vector3.UP * 1.2 - _cam.global_position
		var d := fwd.dot(to.normalized()) - to.length() * 0.0005
		if d > best_dot:
			best_dot = d
			best = p
	if best != null:
		view = View.FOLLOW
		_set_target(best)


## Follows `p`: their body hides like a first-person player's, the viewmodel takes their look.
func _set_target(p: Player) -> void:
	if p == target:
		return
	_release_target()
	target = p
	_target_dead_at = -1.0
	if p == null:
		return
	_last_pos = p.global_position
	_vel = Vector3.ZERO
	_apply_target_look()
	var info := p.info
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
	_vm_weapon = ""
	_reloading = false
	_inspecting = false
	_ads = 0.0


func _apply_target_look() -> void:
	if target == null or not is_instance_valid(target):
		return
	var hide := not _photo
	target.avatar.set_first_person(hide)
	if target.nametag != null:
		target.nametag.visible = not hide and target.alive


func _release_target() -> void:
	if target != null and is_instance_valid(target):
		target.avatar.set_first_person(false)
		if target.nametag != null:
			target.nametag.visible = target.alive
		target.laser_viewmodel = null
	target = null


func _update_follow(delta: float) -> void:
	if target != null and not is_instance_valid(target):
		target = null
	if target == null:
		_cycle(1)
		if target == null:
			if not _dead_mode:
				_set_view(View.FREE)
			return
	var p := target
	if not p.alive:
		if _target_dead_at < 0.0:
			_target_dead_at = World.now()
			_viewmodel.visible = false
		if World.now() - _target_dead_at >= DEATH_HOLD:
			var before := target
			_cycle(1)
			if target == before:
				_target_dead_at = World.now()
		return
	if _target_dead_at >= 0.0:
		# Back from a respawn: the body hides again (respawn shows the nametag).
		_target_dead_at = -1.0
		_apply_target_look()
	if p.nametag != null and p.nametag.visible:
		p.nametag.visible = false
	var fl := p.net_flags()
	var wid := Player.flags_weapon(fl)
	if wid != _vm_weapon:
		_viewmodel.set_weapon(wid, 0.05 if _vm_weapon.is_empty() else Player.SWITCH_TIME)
		_vm_weapon = wid
		_ads_fov = float(Data.WEAPONS[wid].ads_fov)
	_ads = move_toward(_ads, 1.0 if (fl & Player.FLAG_AIM) != 0 else 0.0, delta * 6.0)
	var sliding := (fl & Player.FLAG_SLIDE) != 0
	var roll := -Player.flags_lean(fl) * Player.LEAN_ROLL + (deg_to_rad(-4.0) if sliding else 0.0)
	_cam.global_transform = Transform3D(Basis.from_euler(Vector3(p.pitch, p.yaw, roll)), p.head.global_position)
	var base_fov := float(Profile.get_setting("fov"))
	_cam.fov = lerpf(base_fov, minf(_ads_fov, base_fov), _ads)
	var reloading := (fl & Player.FLAG_RELOAD) != 0
	if reloading and not _reloading:
		_viewmodel.play_reload(float(Data.WEAPONS[wid].reload))
	elif _reloading and not reloading:
		_viewmodel.stop_reload()
	_reloading = reloading
	# The followed player's weapon inspect plays in their viewmodel as it starts and stops.
	var inspecting := (fl & Player.FLAG_INSPECT) != 0
	if inspecting and not _inspecting:
		_viewmodel.play_inspect()
	elif _inspecting and not inspecting:
		_viewmodel.stop_inspect()
	_inspecting = inspecting
	if delta > 0.0:
		_vel = _vel.lerp((p.global_position - _last_pos) / delta, minf(1.0, delta * 10.0))
	_last_pos = p.global_position
	_viewmodel.visible = not _photo
	_viewmodel.pose(delta, _ads, (fl & Player.FLAG_SPRINT) != 0, sliding, p.grappling, Basis(Vector3.UP, p.yaw).inverse() * _vel,
		(fl & Player.FLAG_FLOOR) != 0, Vector2(_vel.x, _vel.z).length(), (fl & Player.FLAG_CROUCH) != 0)
	# Their Laser Sight beam leaves this viewmodel's muzzle (the body's while photo mode shows it).
	p.laser_viewmodel = _viewmodel
	p.update_laser(delta)


## World._play_shot_fx: the followed player's gun kicks or their melee weapon swings in the viewmodel.
func on_shot(p: Player, wid: String) -> void:
	if view != View.FOLLOW or p != target or _viewmodel == null:
		return
	if Data.is_melee(wid):
		_viewmodel.play_melee(false)
	else:
		_viewmodel.play_fire(float(Data.WEAPONS[wid].recoil))


## World._s_spawn_projectile: the followed player fired a rocket or threw a grenade.
func on_launch(owner_id: int, kind: String) -> void:
	if view != View.FOLLOW or target == null or owner_id != target.id or _viewmodel == null:
		return
	if kind == "rocket":
		_viewmodel.play_fire(float(Data.WEAPONS.rocket.recoil))
	else:
		_viewmodel.play_throw()


## Photo mode takes over the view: the followed body shows and the viewmodel hides meanwhile.
func set_photo(on: bool) -> void:
	_photo = on
	if view == View.FOLLOW:
		_apply_target_look()
	if _viewmodel != null:
		_viewmodel.visible = not on and view == View.FOLLOW and target != null and target.alive


## What the overlay shows: {view, name, team, health, max_hp, shield, weapon, score, alive, dead_mode}.
func watched() -> Dictionary:
	var out := {"view": view, "dead_mode": _dead_mode}
	if view != View.FOLLOW or target == null or not is_instance_valid(target):
		return out
	var p := target
	out.id = p.id
	out.name = world.tagged_name(p.id)
	out.team = Teams.of(p)
	out.alive = p.alive
	out.health = p.health
	out.max_hp = p.max_health()
	out.shield = p.shield
	out.weapon = str(Data.WEAPONS[Player.flags_weapon(p.net_flags())].name)
	out.score = score_line(p.id)
	return out


## "12 kills  ·  3 deaths" (the mode's race value: Gun Game level, King of the Block points).
func score_line(eid: int) -> String:
	var s: Dictionary = world.scores.get(eid, {})
	if s.is_empty():
		return ""
	var row := {"id": eid, "name": s.name, "level": s.get("level", 1), "prestige": s.get("prestige", 0),
		"kills": s.kills, "deaths": s.deaths, "headshots": s.headshots, "bot": s.bot}
	world.rules.annotate_rows([row])
	var line := world.rules.race_text(world.rules.race_value(row))
	if world.rules.race_text(int(row.kills)) != line:
		line += "  ·  %d kill%s" % [int(row.kills), "" if int(row.kills) == 1 else "s"]
	return "%s  ·  %d death%s" % [line, int(row.deaths), "" if int(row.deaths) == 1 else "s"]
