class_name ParkourMode
extends MatchMode
## Parkour (`Net.config.mode == "parkour"`): a free-for-all race over the Parkour Run course
## (Data.PARKOUR_MAP, scripts/world/maps/parkour_map.gd). No guns, no hits, no grapple: the
## melee weapon only and nobody can attack. The course's `checkpoints` mark lists the start pad,
## a gold checkpoint after each of its 14 stages, and the finish last. Standing on a checkpoint
## further on than your own saves it; dropping more than FALL_DROP m under your checkpoint puts
## you straight back on it (a fall, no death). The first to the finish wins; FINISH_GRACE s
## later (or once everyone is home) the match ends. At the time limit the furthest checkpoint
## wins, the earlier arrival breaking a tie.
## The server decides: `_s_progress` (checkpoints, times, falls) and `_s_checkpoint` (a
## checkpoint or the finish reached, for the callouts); joiners get `_s_progress` too.

const FALL_DROP := 4.0
const FINISH_GRACE := 20.0
## Seconds after a reset before the same player can be reset again (the teleport travels).
const RESET_GAP := 0.6
## A checkpoint counts within this flat distance of its centre (the gold pad is 5x5).
const CHECKPOINT_REACH := 2.7

## Entity id -> checkpoint index / match second it was reached / finish time (s) / falls.
var progress := {}
var reached := {}
var finished := {}
var falls := {}

# Server only.
var _reset_at := {}
var _end_at := -1.0
## Bots: entity id -> index in the `course` mark of the platform they are on.
var _bot_wp := {}
var _bot_jump_wait := {}


func _init() -> void:
	name = "Parkour"


func checkpoints() -> Array:
	return world.map_info.marks.get("checkpoints", [])


func course() -> Array:
	return world.map_info.marks.get("course", [])


func last_checkpoint() -> int:
	return checkpoints().size() - 1


func elapsed() -> float:
	return float(Net.config.time_limit) - world.time_left


## No guns for anyone, no grenades: the melee weapon only, and it can't hit anyone.
func prepare_info(info: Dictionary, _team: int) -> Dictionary:
	var out := info.duplicate()
	out.primary = ""
	out.secondary = ""
	out.knife_only = true
	return out


func uses_loadout(_p: Player) -> bool:
	return false


func can_attack(_p: Player) -> bool:
	return false


func grapple_allowed(_p: Player) -> bool:
	return false


func hit_damage(_shooter: Player, _target: Player, _wid: String, _dmg: float) -> float:
	return 0.0


func spawn_protection() -> bool:
	return false


func has_pickup(_kind: String) -> bool:
	return false


func respawn_delay() -> float:
	return 1.0


## Back on your own checkpoint (the start pad's spawns before the first one).
func spawn_point(eid: int, team: int) -> Array:
	var cp := int(progress.get(eid, 0))
	if cp <= 0:
		return world.pick_spawn(eid, team)
	return _checkpoint_place(cp)


## [feet position, yaw facing on along the course] on checkpoint `cp`.
func _checkpoint_place(cp: int) -> Array:
	var c: Dictionary = checkpoints()[cp]
	var pos: Vector3 = c.pos
	var path := course()
	var ahead: Vector3 = path[mini(int(c.wp) + 1, path.size() - 1)].pos
	var d := ahead - pos
	return [pos, atan2(-d.x, -d.z) if Vector2(d.x, d.z).length() > 0.1 else 0.0]


# ================================================================ server

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or world.match_over or checkpoints().is_empty():
		return
	var now := World.now()
	if _end_at > 0.0 and now >= _end_at:
		world.server_end_match()
		return
	var cps := checkpoints()
	var changed := false
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if not p.alive or finished.has(eid):
			continue
		var cp := int(progress.get(eid, 0))
		var pos := p.global_position
		for k in range(cp + 1, cps.size()):
			var c: Vector3 = cps[k].pos
			if pos.y >= c.y - 0.5 and pos.y <= c.y + 2.5 and Vector2(pos.x - c.x, pos.z - c.z).length() <= CHECKPOINT_REACH:
				_server_reach(eid, k)
				changed = true
				cp = k
				break
		if pos.y < (cps[cp].pos as Vector3).y - FALL_DROP and now >= float(_reset_at.get(eid, 0.0)):
			_reset_at[eid] = now + RESET_GAP
			falls[eid] = int(falls.get(eid, 0)) + 1
			var place := _checkpoint_place(cp) if cp > 0 else world.pick_spawn(eid, -1)
			world.server_place(eid, place[0], place[1])
			_bot_wp[eid] = int(cps[cp].wp)
			changed = true
	if changed:
		_broadcast(&"_s_progress", [progress, reached, finished, falls])
	if _end_at < 0.0 and not finished.is_empty() and finished.size() >= world.entities.size():
		_end_at = now + 2.0


func _server_reach(eid: int, k: int) -> void:
	progress[eid] = k
	reached[eid] = elapsed()
	_bot_wp[eid] = int(checkpoints()[k].wp)
	var place := 0
	if k == last_checkpoint():
		finished[eid] = snappedf(elapsed(), 0.1)
		place = finished.size()
		if _end_at < 0.0:
			_end_at = World.now() + FINISH_GRACE
	_broadcast(&"_s_checkpoint", [eid, k, place])


func server_sync(pid: int) -> void:
	_s_progress.rpc_id(pid, progress, reached, finished, falls)


func server_human_left(pid: int) -> void:
	super(pid)
	for d: Dictionary in [progress, reached, finished, falls, _reset_at, _bot_wp]:
		d.erase(pid)


## Lava under the course (the backstop under the falls) counts for nothing.
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
func _s_progress(all_progress: Dictionary, all_reached: Dictionary, all_finished: Dictionary, all_falls: Dictionary) -> void:
	progress = all_progress
	reached = all_reached
	finished = all_finished
	falls = all_falls
	world.hud.refresh_scores()


@rpc("authority", "call_remote", "reliable")
func _s_checkpoint(eid: int, k: int, place: int) -> void:
	var mine := eid == world.my_id()
	if place > 0:
		var who := "YOU" if mine else world.display_name(eid).to_upper()
		world.hud.announce("%s FINISHED %s!" % [who, _ordinal(place)])
		Sfx.play(&"pickup_health" if not mine else &"flashbang", null, -6.0 if not mine else -10.0)
	elif mine:
		world.hud.announce("CHECKPOINT %d / %d" % [k, last_checkpoint()])
		Sfx.play(&"pickup_health", null, -2.0)


static func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


# ================================================================ HUD and results

func hud_goal() -> String:
	var me := world.my_id()
	var cps := checkpoints()
	if cps.is_empty():
		return ""
	if finished.has(me):
		return "Finished in %s  ·  %d falls" % [_time_text(float(finished[me])), int(falls.get(me, 0))]
	var cp := int(progress.get(me, 0))
	var next: String = cps[mini(cp + 1, cps.size() - 1)].name
	var line := "Stage %d / %d: %s  ·  falls %d" % [cp + 1, cps.size() - 1, next, int(falls.get(me, 0))]
	if _end_at > 0.0 or not finished.is_empty():
		line += "  ·  someone finished, hurry!"
	return line


static func _time_text(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


func annotate_rows(rows: Array) -> void:
	for r: Dictionary in rows:
		var id := int(r.id)
		r.cp = int(progress.get(id, 0))
		r.reached = float(reached.get(id, 0.0))
		r.finish = float(finished.get(id, -1.0))
		r.falls = int(falls.get(id, 0))


## Finishers first by time, then the furthest checkpoint, the earlier arrival, fewer falls.
func sort_rows(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var fa := float(a.get("finish", -1.0))
		var fb := float(b.get("finish", -1.0))
		if (fa >= 0.0) != (fb >= 0.0):
			return fa >= 0.0
		if fa >= 0.0 and fa != fb:
			return fa < fb
		if int(a.get("cp", 0)) != int(b.get("cp", 0)):
			return int(a.get("cp", 0)) > int(b.get("cp", 0))
		if float(a.get("reached", 0.0)) != float(b.get("reached", 0.0)):
			return float(a.get("reached", 0.0)) < float(b.get("reached", 0.0))
		return int(a.get("falls", 0)) < int(b.get("falls", 0)))


func score_columns() -> Array:
	return ["CHECKPOINT", "TIME", "FALLS"]


func row_cells(r: Dictionary) -> Array:
	var f := float(r.get("finish", -1.0))
	return ["%d / %d" % [int(r.get("cp", 0)), last_checkpoint()], _time_text(f) if f >= 0.0 else "-", int(r.get("falls", 0))]


func row_tag(r: Dictionary) -> String:
	return "DONE" if float(r.get("finish", -1.0)) >= 0.0 else ""


func race_value(r: Dictionary) -> int:
	return int(r.get("cp", 0))


func race_limit() -> int:
	return maxi(1, last_checkpoint())


func race_text(value: int) -> String:
	return "checkpoint %d" % value


func hides_award(_stat: String) -> bool:
	return true


func extra_highlights(rows: Array) -> Array:
	var out: Array = []
	if rows.is_empty():
		return out
	var top: Dictionary = rows[0]
	if float(top.get("finish", -1.0)) >= 0.0:
		out.append(["Fastest run:  %s  (%s)" % [top.name, _time_text(float(top.finish))], int(top.id) == world.my_id(), "parkour_champ"])
	var best: Dictionary = {}
	for r: Dictionary in rows:
		if int(r.get("cp", 0)) < 3:
			continue
		if best.is_empty() or int(r.falls) < int(best.falls) or (int(r.falls) == int(best.falls) and int(r.cp) > int(best.cp)):
			best = r
	if not best.is_empty():
		out.append(["Sure Feet:  %s  (%d fall%s)" % [best.name, int(best.falls), "" if int(best.falls) == 1 else "s"], int(best.id) == world.my_id(), "sure_feet"])
	return out


# ================================================================ bots

func bot_notices(_p: Player, _other: Player) -> bool:
	return false


## Bots run the course platform by platform (the `course` mark): head for the next platform,
## sprint, and jump at the edge or at a step up. Off a jump pad the arc flies them. They miss
## jumps now and then (easier bots more often) and land back on their checkpoint like anyone.
func bot_drive(p: Player, brain: BotBrain, delta: float) -> bool:
	var path := course()
	if path.is_empty() or finished.has(p.id):
		p.in_move = Vector2.ZERO
		p.in_jump = false
		p.in_sprint = false
		return true
	var idx := int(_bot_wp.get(p.id, 0))
	if p.pad_flight:
		p.in_jump = false
		return true
	if idx + 1 >= path.size():
		p.in_move = Vector2.ZERO
		return true
	var pos := p.global_position
	var on_floor := p.is_on_floor()
	if on_floor:
		# Standing on one of the next few platforms (a jump pad carried the bot past the pad, a
		# jump went long): carry on from there.
		for k in range(mini(3, path.size() - 1 - idx), 0, -1):
			var wp: Vector3 = path[idx + k].pos
			if Vector2(wp.x - pos.x, wp.z - pos.z).length() < 1.0 and absf(pos.y - wp.y) < 0.6:
				_bot_wp[p.id] = idx + k
				return true
	var target: Vector3 = path[idx + 1].pos
	var flat := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var dir := flat.normalized() if flat.length() > 0.05 else Vector3.ZERO
	var local := Basis(Vector3.UP, -p.yaw) * dir
	# Cells of open air between this platform and the next (each entry's `half`: its half length
	# along the run).
	var gap := Vector2(target.x - (path[idx].pos as Vector3).x, target.z - (path[idx].pos as Vector3).z).length() \
			- float(path[idx].half) - float(path[idx + 1].half) - 1.0
	if on_floor:
		# Sprint only for the long jumps: a sprinting jump overshoots a small stone.
		p.in_move = Vector2(local.x, -local.z).limit_length(1.0)
		p.in_sprint = gap >= 2.5 and flat.length() > 1.0
	else:
		# In the air, ease off near the target so the landing sticks (air control brakes).
		p.in_move = Vector2(local.x, -local.z).limit_length(1.0) * clampf(flat.length() / 1.6, 0.15, 1.0)
	brain.look_toward(target + Vector3.UP * 1.4, delta, 1.2)
	p.in_jump = false
	if not on_floor:
		return true
	var wait := float(_bot_jump_wait.get(p.id, 0.0)) - delta
	_bot_jump_wait[p.id] = wait
	var edge := not _ground_at(p, pos + dir * 0.4)
	var step_up := target.y > pos.y + 0.5 and flat.length() < 2.8
	var hurdle := _blocked_ahead(p, pos, dir)
	if (edge or step_up or hurdle) and flat.length() > 0.8 and wait <= 0.0:
		# A clumsy bot sometimes jumps a moment late or short.
		var miss := [0.25, 0.12, 0.05][clampi(brain.difficulty, 0, 2)] as float
		if randf() < miss:
			p.in_move *= 0.55
		p.in_jump = true
		_bot_jump_wait[p.id] = 0.25
	return true


func _ground_at(p: Player, at: Vector3) -> bool:
	var from := at + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.2, Player.MASK_WORLD)
	return not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## A knee-high block just ahead (Hurdles): jump it.
func _blocked_ahead(p: Player, pos: Vector3, dir: Vector3) -> bool:
	var from := pos + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 0.9, Player.MASK_WORLD)
	return not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
