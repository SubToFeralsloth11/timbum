class_name TagMode
extends MatchMode
## Tag (`Net.config.mode == "tag"`): free-for-all, no guns. START_DELAY s in, the server makes one
## random player IT; there is always exactly one. IT tags someone by swinging their melee weapon
## at them or running into them (within TOUCH_RANGE); the tagged player becomes IT and stands still
## for `swap_freeze()` seconds while everyone gets away, and can't tag the one who tagged them back
## for NO_TAGBACK s. Nobody else can attack (`can_attack`), and no hit ever hurts (`hit_damage` 0).
## Every second the clock runs with an unfrozen IT, everyone alive who isn't IT scores a point; a
## tag scores TAG_POINTS. The most points at the time limit wins. IT is tinted red and a little
## faster (IT_SPEED). Pickups, mutators and killstreaks are off (Net.sanitize_config).
## Subclass `HideAndSeek` adds a hiding phase, a blindfold, no nametags and seeing IT through walls.
## The server decides: `_s_seeker` (who is IT, until when frozen, who tagged), `_s_points`;
## joiners get `_s_state`.

const START_DELAY := 3.0
const IT_FREEZE := 3.0
const NO_TAGBACK := 4.0
const IT_SPEED := 1.08
const TAG_POINTS := 3
## A tag by touch: IT this close (flat metres, and within 1.6 m of height).
const TOUCH_RANGE := 1.0
## Runner bots keep this far from IT and scatter when it comes closer.
const FLEE_RANGE := 15.0

## Entity id of IT (0: nobody yet) and the match clock (`World.time_left`) at which IT may move.
var seeker := 0
var freeze_at := 0.0
## Entity id -> points / tags / whole seconds spent as IT (server values on every peer).
var points := {}
var tags := {}
var it_time := {}

# Server only.
## The new IT may not tag this one back until World.now() reaches the time: [eid, time].
var _tagback := [0, 0.0]
var _point_clock := 0.0
## Bots: entity id -> [flee goal, World.now() it was picked].
var _flee := {}
var _overlay: SeekOverlay
var _it_mat: StandardMaterial3D


func _init() -> void:
	name = "Tag"


func _ready() -> void:
	_overlay = SeekOverlay.new()
	_overlay.name = "SeekOverlay"
	_overlay.setup(self)
	add_child(_overlay)


## Seconds the match has run.
func elapsed() -> float:
	return float(Net.config.time_limit) - world.time_left


## Seconds IT still stands frozen (0 once free, or with no IT).
func frozen_left() -> float:
	return maxf(0.0, world.time_left - freeze_at) if seeker != 0 else 0.0


func is_seeker(p: Player) -> bool:
	return p != null and p.id == seeker and seeker != 0


## Freeze of the first IT and of each new one after a tag.
func first_freeze() -> float:
	return IT_FREEZE


func swap_freeze() -> float:
	return IT_FREEZE


## No guns for anyone: the melee weapon only (IT's swing tags), no grenades, IT a little faster.
func role_info(info: Dictionary, it: bool) -> Dictionary:
	var out := info.duplicate()
	out.primary = ""
	out.secondary = ""
	out.knife_only = true
	out.seeker = it
	out.speed = IT_SPEED if it else 1.0
	return out


# ================================================================ server

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or world.match_over:
		return
	if seeker == 0 or not world.entities.has(seeker):
		if elapsed() >= START_DELAY:
			_server_pick_seeker()
		return
	var it: Player = world.entities[seeker]
	if frozen_left() > 0.0:
		return
	# A tag by touch.
	if it.alive:
		for eid: int in world.entities:
			var o: Player = world.entities[eid]
			if o == it or not o.alive:
				continue
			var d := o.global_position - it.global_position
			if Vector2(d.x, d.z).length() <= TOUCH_RANGE and absf(d.y) < 1.6 and _may_tag(it.id, o.id):
				_server_tag(it.id, o.id)
				return
	_point_clock += delta
	if _point_clock < 1.0:
		return
	_point_clock -= 1.0
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if eid == seeker:
			it_time[eid] = int(it_time.get(eid, 0)) + 1
		elif p.alive and scores_points(p):
			points[eid] = int(points.get(eid, 0)) + 1
	_broadcast(&"_s_points", [points, tags, it_time])


## Whether `p` (not IT) earns the per-second point now.
func scores_points(_p: Player) -> bool:
	return true


## A random living player becomes IT (the first, or a new one when IT left).
func _server_pick_seeker() -> void:
	var pool: Array[int] = []
	for eid: int in world.entities:
		if world.entities[eid].alive:
			pool.append(eid)
	if pool.size() < 2:
		return
	var first := seeker == 0
	_broadcast(&"_s_seeker", [pool.pick_random(), world.time_left - (first_freeze() if first else swap_freeze()), 0])


## Points a tag (a catch) is worth.
func tag_points() -> int:
	return TAG_POINTS


func _may_tag(from: int, to: int) -> bool:
	return not (int(_tagback[0]) == to and World.now() < float(_tagback[1]) and from == seeker)


func _server_tag(from: int, to: int) -> void:
	tags[from] = int(tags.get(from, 0)) + 1
	points[from] = int(points.get(from, 0)) + tag_points()
	_tagback = [from, World.now() + NO_TAGBACK]
	_flee.clear()
	_broadcast(&"_s_seeker", [to, world.time_left - swap_freeze(), from])
	_broadcast(&"_s_points", [points, tags, it_time])


## A swing by IT tags instead of hurting; nobody else's hit counts. No hit ever deals damage.
func hit_damage(shooter: Player, target: Player, wid: String, _dmg: float) -> float:
	if is_seeker(shooter) and Data.is_melee(wid) and frozen_left() <= 0.0 and target.alive \
			and _may_tag(shooter.id, target.id) and not world.match_over:
		_server_tag(shooter.id, target.id)
	return 0.0


func prepare_info(info: Dictionary, _team: int) -> Dictionary:
	return role_info(info, false)


func uses_loadout(_p: Player) -> bool:
	return false


func spawn_protection() -> bool:
	return false


func has_pickup(_kind: String) -> bool:
	return false


func server_sync(pid: int) -> void:
	_s_state.rpc_id(pid, seeker, freeze_at, points, tags, it_time)


func server_human_left(pid: int) -> void:
	super(pid)
	points.erase(pid)
	if pid == seeker:
		seeker = 0


## Falling off the map counts for nothing here.
func server_on_kill(_victim_id: int, _killer_id: int, _wid: String) -> void:
	pass


func server_finish(rows: Array) -> Dictionary:
	annotate_rows(rows)
	sort_rows(rows)
	for i in rows.size():
		rows[i].won = i == 0
	return {}


# ================================================================ every peer

@rpc("authority", "call_remote", "reliable")
func _s_seeker(eid: int, at: float, by: int) -> void:
	var old := seeker
	seeker = eid
	freeze_at = at
	for id: int in [old, eid]:
		var p: Player = world.entities.get(id)
		if p != null:
			p.apply_info(role_info(p.info, id == eid))
	_refresh_looks()
	_announce_seeker(eid, by)
	world.hud.refresh_scores()


func _announce_seeker(eid: int, by: int) -> void:
	var me := world.my_id()
	if eid == me:
		world.hud.announce("YOU'RE IT!" if by != 0 else "YOU'RE IT FIRST!")
		Sfx.play(&"flashbang", null, -10.0)
	elif by == me:
		world.hud.announce("TAGGED %s" % world.display_name(eid).to_upper())
		Sfx.play(&"hit_marker", null, -4.0)
	else:
		world.hud.announce("%s IS IT" % world.display_name(eid).to_upper())


@rpc("authority", "call_remote", "reliable")
func _s_points(all_points: Dictionary, all_tags: Dictionary, all_it: Dictionary) -> void:
	points = all_points
	tags = all_tags
	it_time = all_it
	world.hud.refresh_scores()


@rpc("authority", "call_remote", "reliable")
func _s_state(eid: int, at: float, all_points: Dictionary, all_tags: Dictionary, all_it: Dictionary) -> void:
	seeker = eid
	freeze_at = at
	_s_points(all_points, all_tags, all_it)
	_refresh_looks()


func on_player_added(p: Player) -> void:
	super(p)
	_apply_look(p)


func _refresh_looks() -> void:
	for eid: int in world.entities:
		_apply_look(world.entities[eid])


## IT glows red; everyone else looks as usual.
func _apply_look(p: Player) -> void:
	p.avatar.set_tint(_it_material() if is_seeker(p) else null)


func _it_material() -> StandardMaterial3D:
	if _it_mat == null:
		_it_mat = StandardMaterial3D.new()
		_it_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_it_mat.albedo_color = Color(1.0, 0.2, 0.15, 0.5)
		_it_mat.emission_enabled = true
		_it_mat.emission = Color(0.9, 0.1, 0.05)
		_it_mat.emission_energy_multiplier = 0.6
	return _it_mat


func can_attack(p: Player) -> bool:
	return is_seeker(p) and frozen_left() <= 0.0


func move_mult(p: Player) -> float:
	return 0.0 if is_seeker(p) and frozen_left() > 0.0 else 1.0


func grapple_allowed(p: Player) -> bool:
	return not (is_seeker(p) and frozen_left() > 0.0)


# ================================================================ HUD and results

## The role card (SeekOverlay): who is IT and what to do.
func overlay_state() -> Dictionary:
	var me := world.local_player
	if seeker == 0:
		return {"title": "TAG", "lines": ["Someone is IT in %d" % ceili(maxf(0.0, START_DELAY - elapsed()))], "color": Color.WHITE}
	if is_seeker(me):
		var f := frozen_left()
		return {"title": "YOU'RE IT!", "color": Color(1.0, 0.4, 0.35),
			"lines": ["Wait %d..." % ceili(f) if f > 0.0 else "Swing or run into someone to tag them"]}
	return {"title": "RUN!", "color": Color(0.5, 0.9, 1.0),
		"lines": ["%s is IT" % world.display_name(seeker), "+1 point a second while you're not IT"]}


func hud_goal() -> String:
	if seeker == 0:
		return "IT is picked in %d" % ceili(maxf(0.0, START_DELAY - elapsed()))
	return "%s is IT" % world.display_name(seeker) if not is_seeker(world.local_player) else "You're IT  ·  tag someone!"


func annotate_rows(rows: Array) -> void:
	for r: Dictionary in rows:
		r.points = int(points.get(int(r.id), 0))
		r.tags = int(tags.get(int(r.id), 0))
		r.it_time = int(it_time.get(int(r.id), 0))


func sort_rows(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("points", 0)) != int(b.get("points", 0)):
			return int(a.get("points", 0)) > int(b.get("points", 0))
		return int(a.get("it_time", 0)) < int(b.get("it_time", 0)))


func score_columns() -> Array:
	return ["POINTS", "TAGS", "IT (S)"]


func row_cells(r: Dictionary) -> Array:
	return [int(r.get("points", 0)), int(r.get("tags", 0)), int(r.get("it_time", 0))]


func row_tag(r: Dictionary) -> String:
	return "IT" if int(r.id) == seeker and seeker != 0 else ""


func race_value(r: Dictionary) -> int:
	return int(r.get("points", 0))


## Points can't run past one a second.
func race_limit() -> int:
	return int(Net.config.time_limit)


func race_text(value: int) -> String:
	return "%d point%s" % [value, "" if value == 1 else "s"]


## Kills, headshots and deaths mean nothing here.
func hides_award(_stat: String) -> bool:
	return true


func extra_highlights(rows: Array) -> Array:
	var best: Dictionary = {}
	for r: Dictionary in rows:
		if int(r.get("tags", 0)) > 0 and (best.is_empty() or int(r.tags) > int(best.tags)):
			best = r
	if best.is_empty():
		return []
	var n := int(best.tags)
	return [["Most tags:  %s  (%d)" % [best.name, n], int(best.id) == world.my_id(), "top_tagger"]]


# ================================================================ bots

## IT chases (the default fight, melee only); runners never fight, they keep away from IT.
func bot_notices(p: Player, _other: Player) -> bool:
	return is_seeker(p)


func bot_pursues(p: Player) -> bool:
	return is_seeker(p)


## IT always knows where the nearest runner is (except the one it may not tag back).
func bot_roam_goal(p: Player) -> Variant:
	if not is_seeker(p):
		return null
	var best: Player = null
	var best_d := INF
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if o == p or not o.alive or not _may_tag(p.id, o.id):
			continue
		var d := p.global_position.distance_squared_to(o.global_position)
		if d < best_d:
			best_d = d
			best = o
	return best.global_position if best != null else null


func bot_drive(p: Player, brain: BotBrain, delta: float) -> bool:
	if is_seeker(p):
		if frozen_left() > 0.0:
			_look_at_seeker_spin(p, brain, delta)
			return true
		return false
	return _drive_runner(p, brain, delta)


## A frozen IT turns slowly on the spot.
func _look_at_seeker_spin(p: Player, brain: BotBrain, delta: float) -> void:
	var ahead := p.global_position + Basis(Vector3.UP, p.yaw + 0.6) * Vector3.FORWARD * 5.0 + Vector3.UP * 1.5
	brain.look_toward(ahead, delta, 0.3)


## Runners: far from IT they wander; close, they run for the spot that puts the most distance
## (by navmesh sample) between them and IT, sprinting.
func _drive_runner(p: Player, brain: BotBrain, delta: float) -> bool:
	var it: Player = world.entities.get(seeker)
	var danger := it != null and it.alive and p.global_position.distance_to(it.global_position) < FLEE_RANGE
	var plan: Array = _flee.get(p.id, [])
	var now := World.now()
	if plan.is_empty() or now - float(plan[1]) > (2.5 if danger else 8.0) \
			or (p.global_position.distance_to(plan[0]) < 1.5):
		plan = [_flee_point(p, it.global_position if it != null else p.global_position, danger), now]
		_flee[p.id] = plan
	brain.move_to(plan[0], delta, danger)
	return true


## A navmesh point away from `from`: the farthest of a few samples on the far side.
func _flee_point(p: Player, from: Vector3, far: bool) -> Vector3:
	var best := p.global_position
	var best_s := -INF
	for i in 8:
		var pos := NavigationServer3D.map_get_random_point(world.map_info.nav_map, 1, false)
		var away := (pos - p.global_position).normalized().dot((p.global_position - from).normalized())
		var s := pos.distance_to(from) - pos.distance_to(p.global_position) * (0.4 if far else 1.0) + away * 10.0
		if s > best_s and pos.y > world.map_info.kill_y + 1.0:
			best_s = s
			best = pos
	return best
