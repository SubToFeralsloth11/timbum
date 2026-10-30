class_name KingOfTheBlock
extends MatchMode
## King of the Block (`Net.config.mode == "koth"`), free-for-all on the deathmatch maps with
## respawns. A glowing zone (RADIUS m round, HEIGHT_BELOW..HEIGHT_ABOVE m about its floor) sits on
## one of the map's zone spots (`zone_spots`: its health/ammo/grenade pickup spots, at least
## MIN_SPACING m apart, all reachable on the navmesh). One living player alone in it holds it and
## scores a point for every full second held; two or more contest it and nobody scores (the
## holder's progress toward the next point restarts whenever the holder changes). Every
## MOVE_INTERVAL s of match clock the zone moves to another spot, announced (with the next spot
## shown) WARNING s before. The first to `Net.config.kill_limit` points (default
## DEFAULT_SCORE_LIMIT) wins, otherwise the most points at the time limit (then kills).
## The server decides everything: `_s_zone` (spot, next spot, move time), `_s_hold` (holder,
## contested, progress) and `_s_point` (a point scored); joiners get it all from `_s_state`.

const DEFAULT_SCORE_LIMIT := 120
## Score limits offered in match setup.
const LIMITS: Array[int] = [60, 90, 120, 150, 200]
const RADIUS := 4.0
const HEIGHT_BELOW := 1.0
const HEIGHT_ABOVE := 3.5
const MIN_SPACING := 10.0
const MOVE_INTERVAL := 60.0
const WARNING := 10.0

## Feet positions the zone can sit on (every peer builds the same list from the map).
var spots: Array[Vector3] = []
## Current and next spot index (-1 until the server says), and the match clock (`World.time_left`)
## at which the zone moves to `next_zone`.
var zone := -1
var next_zone := -1
var move_at := 0.0
## Entity id -> points (server values on every peer).
var points := {}
## The player alone in the zone (0: nobody), whether two or more are in it, and the holder's
## progress (0..1) toward the next point.
var holder := 0
var contested := false
var progress := 0.0

# Server only.
## Seconds the current holder has held without a break, and each player's longest hold.
var _hold_run := 0.0
var _best_hold := {}

# Every peer: the zone's look.
var _zone_node: Node3D
var _next_node: Node3D
var _zone_mats: Array[StandardMaterial3D] = []
var _next_mats: Array[StandardMaterial3D] = []
var _warned := false
var _overlay: ZoneOverlay


func _init() -> void:
	name = "KingOfTheBlock"


func _ready() -> void:
	spots = zone_spots(world.map_info)
	_zone_node = _build_zone(_zone_mats)
	_next_node = _build_zone(_next_mats)
	_zone_node.visible = false
	_next_node.visible = false
	_overlay = ZoneOverlay.new()
	_overlay.name = "ZoneOverlay"
	_overlay.setup(self)
	add_child(_overlay)
	if multiplayer.is_server() and spots.size() >= 2:
		var first := randi() % spots.size()
		_s_zone(first, _pick_other(first), float(Net.config.time_limit) - MOVE_INTERVAL)


## The map's zone spots: its pickup spots (not Tactical's weapon spots) in map order, skipping
## any closer than MIN_SPACING to one already taken.
static func zone_spots(info: MapInfo) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for pick: Dictionary in info.pickups:
		if str(pick.kind) == "weapon":
			continue
		var pos: Vector3 = pick.pos
		var near := false
		for s: Vector3 in out:
			if s.distance_to(pos) < MIN_SPACING:
				near = true
				break
		if not near:
			out.append(pos)
	return out


func zone_pos() -> Vector3:
	return spots[zone] if zone >= 0 and zone < spots.size() else Vector3.ZERO


func next_pos() -> Vector3:
	return spots[next_zone] if next_zone >= 0 and next_zone < spots.size() else Vector3.ZERO


## Whether feet at `pos` stand in the zone.
func in_zone(pos: Vector3) -> bool:
	if zone < 0:
		return false
	var c := zone_pos()
	var dy := pos.y - c.y
	return Vector2(pos.x - c.x, pos.z - c.z).length() <= RADIUS and dy >= -HEIGHT_BELOW and dy <= HEIGHT_ABOVE


## Seconds of match clock until the zone moves.
func move_in() -> float:
	return maxf(0.0, world.time_left - move_at)


func _pick_other(current: int) -> int:
	var pool: Array[int] = []
	for i in spots.size():
		if i != current:
			pool.append(i)
	return pool.pick_random() if not pool.is_empty() else current


# ================================================================ server

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or world.match_over or zone < 0:
		return
	if world.time_left <= move_at:
		_broadcast(&"_s_zone", [next_zone, _pick_other(next_zone), move_at - MOVE_INTERVAL])
		_broadcast(&"_s_hold", [0, false, 0.0])
		_hold_run = 0.0
		return
	var inside: Array[int] = []
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if p.alive and in_zone(p.global_position):
			inside.append(eid)
	var new_holder := inside[0] if inside.size() == 1 else 0
	var new_contested := inside.size() >= 2
	if new_holder != holder:
		progress = 0.0
		_hold_run = 0.0
	if new_holder != holder or new_contested != contested:
		_broadcast(&"_s_hold", [new_holder, new_contested, progress])
	if new_holder == 0:
		return
	progress += delta
	_hold_run += delta
	_best_hold[new_holder] = maxf(float(_best_hold.get(new_holder, 0.0)), _hold_run)
	if progress >= 1.0:
		progress -= 1.0
		var total := int(points.get(new_holder, 0)) + 1
		_broadcast(&"_s_point", [new_holder, total, progress])
		if total >= int(Net.config.kill_limit):
			world.server_end_match()


func server_human_joined(pid: int) -> void:
	_s_state.rpc_id(pid, zone, next_zone, move_at, points, holder, contested, progress)
	super(pid)


func server_human_left(pid: int) -> void:
	points.erase(pid)
	super(pid)


## Kills only matter for tie-breaks here; the score limit is on points.
func server_on_kill(_victim_id: int, _killer_id: int, _wid: String) -> void:
	pass


func server_finish(rows: Array) -> Dictionary:
	annotate_rows(rows)
	sort_rows(rows)
	for i in rows.size():
		var r: Dictionary = rows[i]
		r.won = i == 0
		r.best_hold = int(_best_hold.get(int(r.id), 0.0))
	return {}


# ================================================================ every peer

## The zone sits on `index`; it moves to `next` when the match clock reaches `at`.
@rpc("authority", "call_remote", "reliable")
func _s_zone(index: int, next: int, at: float) -> void:
	var moved := zone >= 0 and index != zone
	zone = index
	next_zone = next
	move_at = at
	_warned = false
	_zone_node.position = zone_pos()
	_next_node.position = next_pos()
	_next_node.visible = false
	_zone_node.visible = zone >= 0
	if moved and not world.match_over:
		world.hud.announce("THE ZONE HAS MOVED")
		Sfx.play(&"spawn", null, -4.0)


@rpc("authority", "call_remote", "reliable")
func _s_hold(who: int, is_contested: bool, p_progress: float) -> void:
	var was_mine := holder == world.my_id() and holder != 0
	holder = who
	contested = is_contested
	progress = p_progress
	if who == world.my_id() and not was_mine and not world.match_over:
		Sfx.play(&"pickup_ammo", null, -6.0)


@rpc("authority", "call_remote", "reliable")
func _s_point(eid: int, total: int, p_progress: float) -> void:
	points[eid] = total
	holder = eid
	progress = p_progress
	if eid == world.my_id():
		Sfx.play(&"hit_marker", null, -12.0, 1.6)
	world.hud.refresh_scores()


## Everything a joiner needs.
@rpc("authority", "call_remote", "reliable")
func _s_state(index: int, next: int, at: float, all_points: Dictionary, who: int, is_contested: bool, p_progress: float) -> void:
	points = all_points
	_s_zone(index, next, at)
	_s_hold(who, is_contested, p_progress)
	world.hud.refresh_scores()


func _process(delta: float) -> void:
	if zone < 0:
		return
	# Between the server's messages the holder's progress runs on locally.
	if holder != 0 and not multiplayer.is_server() and not world.match_over:
		progress = minf(progress + delta, 0.99)
	var warning := move_in() <= WARNING and move_at > 0.0 and not world.match_over
	if warning and not _warned:
		_warned = true
		world.hud.announce("ZONE MOVES IN %d" % ceili(move_in()))
		Sfx.play(&"countdown", null, -4.0)
	_next_node.visible = warning
	var pulse := 0.5 + 0.5 * sin(World.now() * 6.0)
	var col := zone_color()
	var alpha := 1.0 if not contested else 0.6 + 0.4 * pulse
	_tint(_zone_mats, col, alpha)
	if warning:
		_tint(_next_mats, Palette.color("zone_next"), 0.35 + 0.35 * pulse)


## The zone's colour for the local player (Palette roles, so it follows the colour mode): free,
## held by them, by someone else, or contested.
func zone_color() -> Color:
	if contested:
		return Palette.color("zone_contested")
	if holder == 0:
		return Palette.color("zone_free")
	return Palette.color("zone_mine" if holder == world.my_id() else "zone_other")


## Ring wall, floor disc and a tall beam that shows the zone from anywhere on the map.
func _build_zone(mats: Array[StandardMaterial3D]) -> Node3D:
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	# [mesh, local y, base alpha]
	var ring := CylinderMesh.new()
	ring.top_radius = RADIUS
	ring.bottom_radius = RADIUS
	ring.height = 2.2
	ring.cap_top = false
	ring.cap_bottom = false
	ring.radial_segments = 40
	ring.rings = 1
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS
	disc.height = 0.04
	disc.radial_segments = 40
	disc.rings = 1
	var beam := CylinderMesh.new()
	beam.top_radius = 0.18
	beam.bottom_radius = 0.35
	beam.height = 36.0
	beam.radial_segments = 10
	beam.rings = 1
	for part: Array in [[ring, 1.1, 0.32], [disc, 0.06, 0.2], [beam, 18.0, 0.28]]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.position.y = float(part[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
		m.set_meta(&"alpha", float(part[2]))
		mi.material_override = m
		mats.append(m)
		root.add_child(mi)
	return root


func _tint(mats: Array[StandardMaterial3D], col: Color, alpha: float) -> void:
	for m in mats:
		m.albedo_color = Color(col, float(m.get_meta(&"alpha")) * alpha)


# ================================================================ HUD and results

func annotate_rows(rows: Array) -> void:
	for r: Dictionary in rows:
		if not r.has("points"):
			r.points = int(points.get(int(r.id), 0))


## Most points first, then kills, then fewest deaths.
func sort_rows(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.points) != int(b.points):
			return int(a.points) > int(b.points)
		return a.kills > b.kills if a.kills != b.kills else a.deaths < b.deaths)


func score_columns() -> Array:
	return ["POINTS", "KILLS", "DEATHS"]


func row_cells(r: Dictionary) -> Array:
	return [int(r.get("points", 0)), r.kills, r.deaths]


func race_value(r: Dictionary) -> int:
	return int(r.get("points", 0))


func race_text(value: int) -> String:
	return "%d point%s" % [value, "" if value == 1 else "s"]


func compass_pips(cam: Camera3D) -> Array:
	if zone < 0:
		return []
	var out: Array = []
	if _next_node.visible:
		out.append([_heading(cam, next_pos()), Palette.color("zone_next").darkened(0.2)])
	out.append([_heading(cam, zone_pos()), zone_color()])
	return out


static func _heading(cam: Camera3D, pos: Vector3) -> float:
	var to := pos - cam.global_position
	return rad_to_deg(-atan2(-to.x, -to.z))


func extra_highlights(rows: Array) -> Array:
	var best: Dictionary = {}
	for r: Dictionary in rows:
		if int(r.get("best_hold", 0)) > 0 and (best.is_empty() or int(r.best_hold) > int(best.best_hold)):
			best = r
	if best.is_empty():
		return []
	return [["Longest hold:  %s  (%d s)" % [best.name, int(best.best_hold)], int(best.id) == world.my_id(), "longest_hold"]]


# ================================================================ bots

## Bots head for the zone, each to its own spot inside it (slowly circling, so they spread out).
func bot_roam_goal(p: Player) -> Variant:
	if zone < 0:
		return null
	var ang := float(p.id) * 2.4 + World.now() * 0.15
	return zone_pos() + Vector3(cos(ang), 0.0, sin(ang)) * RADIUS * 0.55


func bot_hold_area(_p: Player) -> Array:
	return [] if zone < 0 else [zone_pos(), RADIUS]
