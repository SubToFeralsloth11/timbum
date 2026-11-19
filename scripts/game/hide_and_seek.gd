class_name HideAndSeek
extends TagMode
## Hide and Seek (`Net.config.mode == "hideseek"`): Tag's rules (TagMode) with hiding. There is
## always exactly one seeker. The first is picked START_DELAY s in and stands blindfolded for
## HIDE_TIME s while everyone hides; a seeker who catches a hider (a melee swing or running into
## them) swaps roles with them, and the new seeker is blindfolded for SWAP_FREEZE s. No nametags,
## and hiders see the seeker through walls (a red x-ray silhouette, `_xray_material`). Hiders score
## a point a second while the seeker is out looking; a catch scores CATCH_POINTS.
## Bots: hiders (`bot_drive`) pick a covered spot away from the seeker, crouch there watching the
## seeker through the walls, and run for a new spot when the seeker sees them or comes close;
## the seeker searches spots it hasn't checked lately (`bot_roam_goal`), hears hiders running
## nearby and only spots a hider it can make out (`bot_notices`, Hiding): movement, how much shows
## past cover, stance, light, and the hider's outfit colour against what's behind them.

const HIDE_TIME := 20.0
const SWAP_FREEZE := 6.0
const CATCH_POINTS := 10
## A seeker bot hears a hider sprinting (or sliding) this close, through walls.
const HEAR_RUN := 14.0
## Hider bots run for a new spot when the seeker sees them this close, or comes this close at all.
const SPOTTED_RANGE := 22.0
const PANIC_RANGE := 7.0
## Seeker bots' search: cells of this size (m), each skipped for SEARCH_MEMORY s after a visit.
const SEARCH_CELL := 9.0
const SEARCH_MEMORY := 50.0

var _watch := Hiding.Watch.new()
var _xray_mat: StandardMaterial3D
# Server only, bots.
## Hider entity id -> {spot, since, flee_until}.
var _hide := {}
## Seeker entity id -> current search point; and visited search cells: Vector2i -> World.now().
var _search := {}
var _visited := {}


func _init() -> void:
	name = "HideAndSeek"


func first_freeze() -> float:
	return HIDE_TIME


func swap_freeze() -> float:
	return SWAP_FREEZE


func tag_points() -> int:
	return CATCH_POINTS


func shows_nametags() -> bool:
	return false


func _server_tag(from: int, to: int) -> void:
	_watch.forget(to)
	_hide.erase(to)
	_search.erase(from)
	super(from, to)


func _announce_seeker(eid: int, by: int) -> void:
	var me := world.my_id()
	if eid == me:
		world.hud.announce("YOU'RE THE SEEKER" if by == 0 else "CAUGHT! NOW YOU SEEK")
		Sfx.play(&"flashbang", null, -10.0)
	elif by == me:
		world.hud.announce("FOUND %s!" % world.display_name(eid).to_upper())
		Sfx.play(&"hit_marker", null, -4.0)
	elif by != 0:
		world.hud.announce("SOMEONE WAS FOUND  ·  NEW SEEKER")
	else:
		world.hud.announce("HIDE! THE SEEKER COUNTS TO %d" % int(HIDE_TIME))


## Hiders see the seeker through walls; for the seeker and spectators the seeker is just red.
func _apply_look(p: Player) -> void:
	if not is_seeker(p):
		p.avatar.set_tint(null)
		return
	var me := world.local_player
	p.avatar.set_tint(_xray_material() if me != null and not is_seeker(me) else _it_material())


func _xray_material() -> StandardMaterial3D:
	if _xray_mat == null:
		_xray_mat = StandardMaterial3D.new()
		_xray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_xray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_xray_mat.no_depth_test = true
		_xray_mat.render_priority = 10
		_xray_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.42)
	return _xray_mat


func overlay_state() -> Dictionary:
	var me := world.local_player
	if seeker == 0:
		return {"title": "HIDE AND SEEK", "color": Color.WHITE,
			"lines": ["The seeker is picked in %d" % ceili(maxf(0.0, START_DELAY - elapsed()))]}
	var f := frozen_left()
	if is_seeker(me):
		var out := {"title": "YOU'RE THE SEEKER", "color": Color(1.0, 0.4, 0.35),
			"lines": ["Find a hider and swing at them (or run into them)", "+%d a catch, then you swap" % CATCH_POINTS]}
		if f > 0.0:
			out.blind = "%d" % ceili(f)
			out.blind_sub = "YOU'RE THE SEEKER  ·  THE OTHERS ARE HIDING"
		return out
	var lines: Array = ["You can see the seeker through walls (red)", "+1 point a second while they search"]
	if f > 0.0:
		lines.push_front("Seeker looks in %d - HIDE!" % ceili(f))
	return {"title": "HIDER", "color": Color(0.5, 0.9, 1.0), "lines": lines}


func hud_goal() -> String:
	if seeker == 0:
		return "Seeker picked in %d" % ceili(maxf(0.0, START_DELAY - elapsed()))
	var f := frozen_left()
	if is_seeker(world.local_player):
		return "Counting... %d" % ceili(f) if f > 0.0 else "You seek  ·  find someone!"
	return "Seeker looks in %d" % ceili(f) if f > 0.0 else "Stay hidden"


func score_columns() -> Array:
	return ["POINTS", "CATCHES", "SEEKING (S)"]


func row_tag(r: Dictionary) -> String:
	return "SEEKER" if int(r.id) == seeker and seeker != 0 else ""


func extra_highlights(rows: Array) -> Array:
	var best: Dictionary = {}
	for r: Dictionary in rows:
		if int(r.get("tags", 0)) > 0 and (best.is_empty() or int(r.tags) > int(best.tags)):
			best = r
	if best.is_empty():
		return []
	var n := int(best.tags)
	return [["Most catches:  %s  (%d)" % [best.name, n], int(best.id) == world.my_id(), "top_seeker"]]


# ================================================================ bots

## The seeker spots a hider only once it has made them out (Hiding.Watch).
func bot_notices(p: Player, other: Player) -> bool:
	if not is_seeker(p):
		return false
	var eye := p.head.global_position
	var center := other.global_position + Vector3.UP * other.body_center_height()
	var d := eye.distance_to(center)
	if d < Hiding.BUMP_RANGE:
		return true
	var moving := Hiding.speed_of(other) > Hiding.MOVING
	var shown := Hiding.exposure(world, eye, other)
	var c := Hiding.contrast(Hiding.outfit_color(other), Hiding.backdrop(world, eye, center)[0])
	var stance := 0.45 if other.prone else (0.7 if other.crouching else 1.0)
	var near := clampf(1.0 - d / 45.0, 0.1, 1.0)
	var rate := (3.0 if moving else 0.35 + 1.6 * c) * shown * stance * Hiding.light() * near * 2.2 \
		* float(Hiding.SKILL[p.brain.difficulty if p.brain != null else 1])
	return _watch.see(p, other, rate)


## The seeker searches: the next spot is a well-covered place in a cell it hasn't checked lately;
## a hider running within earshot pulls it there instead.
func bot_roam_goal(p: Player) -> Variant:
	if not is_seeker(p):
		return null
	var now := World.now()
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if o != p and o.alive and (o.sprinting or o.sliding) and o.global_position.distance_to(p.global_position) < HEAR_RUN:
			p.brain.investigate(o.global_position)
	var goal: Variant = _search.get(p.id)
	if goal != null and p.global_position.distance_to(goal) > 2.5:
		return goal
	if goal != null:
		_visited[_cell(goal)] = now
	var best: Variant = null
	var best_s := -INF
	for s: Array in Hiding.spots(world, p, [], []):
		var pos: Vector3 = s[1]
		var seen_at := float(_visited.get(_cell(pos), -INF))
		var score := float(s[0]) - (30.0 if now - seen_at < SEARCH_MEMORY else 0.0) - pos.distance_to(p.global_position) * 0.08
		if score > best_s:
			best_s = score
			best = pos
	_search[p.id] = best
	return best


func _cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / SEARCH_CELL), floori(pos.z / SEARCH_CELL))


func bot_drive(p: Player, brain: BotBrain, delta: float) -> bool:
	if is_seeker(p):
		if frozen_left() > 0.0:
			_look_at_seeker_spin(p, brain, delta)
			return true
		return false
	return _drive_hider(p, brain, delta)


## A hider bot: to its spot, then still and crouched watching the seeker through the walls; seen
## or cornered, it runs for another spot.
func _drive_hider(p: Player, brain: BotBrain, delta: float) -> bool:
	var it: Player = world.entities.get(seeker)
	var threat := it.global_position if it != null else p.global_position
	var now := World.now()
	var plan: Dictionary = _hide.get(p.id, {})
	var hunting := it != null and it.alive and frozen_left() <= 0.0
	var d := p.global_position.distance_to(threat)
	var exposed := hunting and d < SPOTTED_RANGE and Hiding.exposure(world, it.head.global_position, p) > 0.3
	var panic := hunting and (d < PANIC_RANGE or exposed)
	if plan.is_empty() or (panic and now > float(plan.get("flee_until", 0.0))):
		plan = {"spot": _pick_spot(p, threat), "since": now, "flee_until": now + 2.5 if panic else 0.0}
		_hide[p.id] = plan
		brain.drop_route()
	var spot: Vector3 = plan.spot
	var far := p.global_position.distance_to(spot) > 1.2
	if far:
		# Hurry while the seeker counts or is close; otherwise sneak (walking is quieter).
		brain.move_to(spot, delta, panic or frozen_left() > 0.0)
	else:
		p.in_crouch = true
		brain.look_toward(threat + Vector3.UP * 1.5, delta, 0.25)
	return true


## The best hiding spot for `p` away from the seeker, not one another hider bot already took.
func _pick_spot(p: Player, threat: Vector3) -> Vector3:
	var taken: Array[Vector3] = []
	for eid: int in _hide:
		if eid != p.id:
			taken.append(_hide[eid].spot)
	var ranked := Hiding.spots(world, p, [threat], [])
	for s: Array in ranked.slice(0, 6):
		var ok := true
		for t in taken:
			if t.distance_to(s[1]) < 4.0:
				ok = false
				break
		if ok:
			return s[1]
	return ranked[0][1] if not ranked.is_empty() else p.global_position
