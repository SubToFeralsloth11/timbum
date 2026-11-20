class_name BedWars
extends MatchMode
## Bedwars (`Net.config.mode == "bedwars"`), always on Bed Islands (Data.BEDWARS_MAP,
## scripts/world/maps/bedwars_map.gd, built editable). Two teams, BLUE (0) and ORANGE (1), each with
## a bed on its island. While your bed stands you respawn RESPAWN seconds after a death; once it is
## broken your next death is a FINAL KILL and you are out. The last team with anyone left wins; at
## the time limit the team with its bed (then more players alive) wins.
##
## No guns: everyone holds a sword (melee slot), the block stack (`bw_blocks`, secondary slot) and,
## once bought, the bow (`bw_bow`, primary slot). Minecraft 1.9 combat: a sword hit deals full
## damage only when its attack cooldown (Data `cooldown`, 0.625 s) has refilled (ATTACK_MIN up to 1,
## squared), and a full-strength hit while falling is a crit (x`head_mult`). Hits knock the target
## back (harder while sprinting). Armour and the team's Protection cut damage taken.
##
## Blocks: right click (aim) places the current block kind on the face you look at within REACH
## (reload cycles the kind), left click (fire) held on a block players placed breaks it after its
## BREAK_TIME; only placed blocks and beds break. Crouching on the ground is a Minecraft sneak: you
## can't walk off an edge (edge_guard), so you can bridge backwards over the void. Placing is
## predicted on the placer's peer and confirmed (or undone) by the server (_c_place -> _s_cells).
##
## Resources: each team's forge piles up iron and gold, the diamond islands diamonds and the emerald
## island emeralds; standing at a pile collects it. A kill takes the victim's resources. The shop
## (interact at your island's shop stand) sells blocks, swords, armour, the bow, arrows and golden
## apples; the upgrades stand sells team Sharpness, Protection and Forge levels for diamonds.
## Every peer keeps `inv` (entity id -> INV fields), `beds`, `upgrades`, `piles` and `placed`; the
## server changes them and broadcasts.
## Bots: bot_drive runs them entirely (gear up, defend the bed with blocks, bridge over, break the
## bed, fight with timed sword hits and jump crits, shoot the bow at range).

const ARROW_GRAVITY := 20.0
const REACH := 4.5
const REACH_SLACK := 1.5
const PLACE_GAP := 0.2
const RESPAWN := 5.0
const ATTACK_MIN := 0.2
const KNOCKBACK := 6.5
const KNOCKBACK_SPRINT := 3.0
const KNOCK_UP := 5.0
const PICK_RADIUS := 1.7
## Highest grid row a block may go in (the islands' floor is row 30).
const TOP_CELL := 50
## Armour tiers: none, chainmail, iron, diamond; the share of damage each blocks.
const ARMOR_NAMES := ["None", "Chainmail", "Iron", "Diamond"]
const ARMOR_CUT := [0.0, 0.25, 0.4, 0.55]
const PROT_CUT := 0.07
const SHARP_MULT := 0.25
const FORGE_MULT := [1.0, 1.5, 2.0, 3.0]
const SWORDS := ["bw_wood_sword", "bw_stone_sword", "bw_iron_sword", "bw_diamond_sword"]
const BLOCK_KINDS := ["wool", "wood", "stone"]
const BREAK_TIME := {"wool": 0.3, "wood": 0.8, "stone": 1.6}
const BED_BREAK_TIME := 1.1
const RESOURCES := ["iron", "gold", "diamond", "emerald"]
const RES_COLORS := {"iron": Color(0.88, 0.88, 0.9), "gold": Color(1.0, 0.82, 0.2), "diamond": Color(0.35, 0.95, 1.0), "emerald": Color(0.2, 0.95, 0.4)}
## Generators: [mark kind, resource, seconds per item, pile cap].
const GENERATORS := [["forge", "iron", 0.55, 64], ["forge", "gold", 4.5, 16], ["diamond", "diamond", 30.0, 4], ["emerald", "emerald", 55.0, 2]]
## Shop items: id -> [name, resource, cost, what it gives].
const SHOP := {
	"wool": ["Wool x16", "iron", 4, {"wool": 16}],
	"wood": ["Planks x16", "gold", 4, {"wood": 16}],
	"stone": ["End Stone x12", "iron", 24, {"stone": 12}],
	"sword1": ["Stone Sword", "iron", 10, {"sword": 1}],
	"sword2": ["Iron Sword", "gold", 7, {"sword": 2}],
	"sword3": ["Diamond Sword", "emerald", 4, {"sword": 3}],
	"armor1": ["Chainmail Armour", "iron", 24, {"armor": 1}],
	"armor2": ["Iron Armour", "gold", 12, {"armor": 2}],
	"armor3": ["Diamond Armour", "emerald", 6, {"armor": 3}],
	"bow": ["Bow", "gold", 12, {"bow": 1}],
	"arrows": ["Arrows x8", "gold", 2, {"arrows": 8}],
	"apple": ["Golden Apple", "gold", 3, {"apple": 1}],
}
const SHOP_ORDER := ["wool", "wood", "stone", "sword1", "sword2", "sword3", "armor1", "armor2", "armor3", "bow", "arrows", "apple"]
## Team upgrades: id -> [name, max level, diamond cost per level].
const UPGRADES := {"sharp": ["Sharpened Swords", 1, [4]], "prot": ["Protection", 3, [2, 4, 8]], "forge": ["Forge", 3, [2, 4, 6]]}

## Every peer: entity id -> {iron, gold, diamond, emerald, wool, wood, stone, arrows, armor, sword, bow, block}.
var inv := {}
var beds := [true, true]
var upgrades := [{"sharp": 0, "prot": 0, "forge": 0}, {"sharp": 0, "prot": 0, "forge": 0}]
## [{pos, res, count}], one per generator (GENERATORS order per mark).
var piles: Array = []
## Grid indices of every block a player placed -> true.
var placed := {}
var finals := {}
var bed_breaks := {}
var out := {}

var _grid: VoxelGrid
var _origin := Vector3.ZERO
var _dirty := {}
var _bed_nodes: Array[Node3D] = []
var _pile_labels: Array[Label3D] = []
var _gen_t: Array[float] = []
var _last_swing := {}
var _place_cd := 0.0
var _break_cell := -1
var _break_t := 0.0
var _draw := 0.0
var _drawing := false
var _bot := {}
var _covered := [false, false]
var _overlay: CanvasLayer
var _hud_label: Label
var _res_label: Label
var _cool_bar: ProgressBar
var _break_bar: ProgressBar
var _prompt: Label
var _shop: Control
var _shop_grid: GridContainer
var _shop_info: Label
var _shop_upgrades := false


func _init() -> void:
	name = "BedWars"


static func is_active() -> bool:
	return str(Net.config.get("mode", "")) == "bedwars"


# ================================================================ setup

func _ready() -> void:
	_grid = world.map_info.grid
	_origin = world.map_info.bounds.position
	if world.map_info.mesher != null:
		world.map_info.mesher.grow_chunks = true
	for t in 2:
		var bed := _build_bed(t)
		world.add_child(bed)
		_bed_nodes.append(bed)
	for g: Array in GENERATORS:
		for pos: Vector3 in _gen_spots(str(g[0])):
			piles.append({"pos": pos, "res": str(g[1]), "count": 0, "every": float(g[2]), "cap": int(g[3])})
			_gen_t.append(0.0)
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = false
			l.font_size = 40
			l.outline_size = 10
			l.pixel_size = 0.006
			l.modulate = RES_COLORS[str(g[1])]
			l.position = pos + Vector3.UP * (1.6 if str(g[1]) != "gold" else 2.1)
			world.add_child(l)
			_pile_labels.append(l)
	_build_overlay()
	_refresh_piles()


func _gen_spots(kind: String) -> Array:
	var outv: Array = []
	match kind:
		"forge":
			for t: Dictionary in world.map_info.marks.get("bw_teams", []):
				outv.append(t.forge)
		"diamond":
			for d: Dictionary in world.map_info.marks.get("bw_diamonds", []):
				outv.append(d.pos)
		"emerald":
			for e: Dictionary in world.map_info.marks.get("bw_emeralds", []):
				outv.append(e.pos)
	return outv


func team_mark(team: int) -> Dictionary:
	var teams: Array = world.map_info.marks.get("bw_teams", [])
	return teams[team] if team >= 0 and team < teams.size() else {}


## A bed: a white frame with a blanket and pillow in the team colour, two blocks long along its
## `bed_dir`, solid (players stand on it, rays hit it) with meta `bed_team`.
func _build_bed(team: int) -> Node3D:
	var m := team_mark(team)
	var root := StaticBody3D.new()
	root.name = "Bed%d" % team
	root.collision_layer = Player.MASK_WORLD
	root.collision_mask = 0
	root.set_meta(&"bed_team", team)
	var dir: Vector3 = m.get("bed_dir", Vector3.FORWARD)
	root.position = m.get("bed", Vector3.ZERO)
	root.rotation.y = atan2(dir.x, dir.z)
	var col := Teams.color(team)
	for part: Array in [[Vector3(0, 0.15, 0), Vector3(1.0, 0.3, 2.0), Color(0.55, 0.36, 0.2)],
			[Vector3(0, 0.42, -0.15), Vector3(0.98, 0.24, 1.7), col],
			[Vector3(0, 0.44, 0.75), Vector3(0.9, 0.2, 0.42), Color(0.95, 0.95, 0.92)]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[1]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = part[2]
		box.material = mat
		mi.mesh = box
		mi.position = part[0]
		root.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.56, 2.0)
	cs.shape = shape
	cs.position = Vector3(0, 0.28, 0)
	root.add_child(cs)
	return root


static func arrow_model() -> Node3D:
	var root := Node3D.new()
	var shaft := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.04, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.45, 0.28)
	box.material = mat
	shaft.mesh = box
	root.add_child(shaft)
	var tip := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.08, 0.08, 0.12)
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.75, 0.75, 0.8)
	tb.material = tm
	tip.mesh = tb
	tip.position = Vector3(0, 0, -0.38)
	root.add_child(tip)
	return root


func new_inv() -> Dictionary:
	return {"iron": 0, "gold": 0, "diamond": 0, "emerald": 0, "wool": 0, "wood": 0, "stone": 0,
		"arrows": 0, "armor": 0, "sword": 0, "bow": 0, "block": "wool"}


func inv_of(eid: int) -> Dictionary:
	if not inv.has(eid):
		inv[eid] = new_inv()
	return inv[eid]


# ================================================================ MatchMode hooks

func prepare_info(info: Dictionary, team: int) -> Dictionary:
	var o := info.duplicate()
	o.team = team
	o.primary = ""
	o.secondary = "bw_blocks"
	o.melee = SWORDS[0]
	o.no_grenades = true
	return o


func uses_loadout(_p: Player) -> bool:
	return false


func has_pickup(_kind: String) -> bool:
	return false


func grapple_allowed(_p: Player) -> bool:
	return false


func can_slide(_p: Player) -> bool:
	return false


func spawn_protection() -> bool:
	return false


func respawn_delay() -> float:
	return RESPAWN


func respawns(eid: int) -> bool:
	var p: Player = world.entities.get(eid)
	return p != null and beds[clampi(Teams.of(p), 0, 1)]


func no_respawn_note() -> String:
	return "YOUR BED IS GONE  ·  FINAL KILL"


func no_ammo_hint() -> String:
	return ""


func spawn_point(_eid: int, team: int) -> Array:
	var m := team_mark(team)
	if m.is_empty():
		return world.pick_spawn(_eid, team)
	var pos: Vector3 = m.spawn + Vector3(randf_range(-1.0, 1.0), 0.0, 0.0)
	var dir: Vector3 = m.bed_dir
	return [pos, atan2(-dir.x, -dir.z)]


func weapon_allowed(shooter: Player, wid: String) -> bool:
	return shooter.slots.has(wid)


func ui_blocking() -> bool:
	return _shop != null and _shop.visible


func on_local_death(_killer_id: int) -> void:
	_close_shop()
	var me := world.local_player
	if me != null and not beds[clampi(Teams.of(me), 0, 1)]:
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if is_instance_valid(world) and world.local_player != null and not world.local_player.alive and not world.match_over:
				world.spectator.begin_dead())


func spectate_candidates() -> Array[Player]:
	var outp: Array[Player] = []
	var mine := Teams.of(world.local_player)
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if p.alive and p != world.local_player and (mine < 0 or Teams.of(p) == mine or _team_out(mine)):
			outp.append(p)
	return outp


func _team_out(team: int) -> bool:
	return not beds[team] and Teams.counts(world, true)[team] == 0


## Sword swings: Minecraft 1.9 attack cooldown and falling crits.
func melee_strike(p: Player, wid: String) -> Array:
	var w: Dictionary = Data.WEAPONS[wid]
	if not w.has("cooldown"):
		return [float(w.damage), false]
	var charge := attack_charge(p)
	_last_swing[p.id] = World.now()
	var mult := ATTACK_MIN + (1.0 - ATTACK_MIN) * charge * charge
	var crit := charge > 0.9 and not p.is_on_floor() and p.velocity.y < -0.5
	if crit and p == world.local_player:
		world.hud.callout("CRIT!", "info", Color(1.0, 0.8, 0.2))
	return [float(w.damage) * mult, crit]


## How far the sword's attack cooldown has refilled for `p` (0..1).
func attack_charge(p: Player) -> float:
	var w: Dictionary = Data.WEAPONS.get(p.melee_id(), {})
	var cd := float(w.get("cooldown", 0.6))
	return clampf((World.now() - float(_last_swing.get(p.id, -100.0))) / cd, 0.0, 1.0)


## Server: sharpness, armour and knockback.
func hit_damage(shooter: Player, target: Player, wid: String, dmg: float) -> float:
	if Teams.same(shooter, target):
		return 0.0
	if Data.is_melee(wid):
		dmg *= 1.0 + SHARP_MULT * int(upgrades[clampi(Teams.of(shooter), 0, 1)].sharp)
		var dir := target.global_position - shooter.global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3(sin(shooter.yaw), 0, cos(shooter.yaw)) * -1.0
		var force := KNOCKBACK + (KNOCKBACK_SPRINT if shooter.sprinting else 0.0)
		_broadcast(&"_s_knock", [target.id, dir * force + Vector3.UP * KNOCK_UP])
	return dmg * _cut(target)


func _cut(target: Player) -> float:
	var t := clampi(Teams.of(target), 0, 1)
	var a := int(inv_of(target.id).armor)
	return maxf(0.2, 1.0 - ARMOR_CUT[clampi(a, 0, 3)] - PROT_CUT * int(upgrades[t].prot))


## Server: an arrow hit `target` (null: it stuck in a block).
func server_arrow_hit(proj: Projectile, target: Player) -> void:
	if target == null or not target.alive:
		return
	var shooter: Player = world.entities.get(proj.owner_id)
	if shooter == null or Teams.same(shooter, target):
		return
	var draw := clampf(proj.vel.length() / float(Data.WEAPONS.bw_bow.speed), 0.0, 1.0)
	var dmg := float(Data.WEAPONS.bw_bow.damage) * draw * draw * _cut(target)
	var dir := proj.vel
	dir.y = 0.0
	_broadcast(&"_s_knock", [target.id, dir.normalized() * 3.0 + Vector3.UP * 2.5])
	world._server_damage(target, dmg, shooter.id, "bw_bow", false, shooter.global_position)


## Server: arrows cost an arrow.
func server_take_shot(shooter: Player, wid: String) -> bool:
	if wid != "bw_bow":
		return true
	var d := inv_of(shooter.id)
	if int(d.arrows) <= 0:
		return false
	d.arrows = int(d.arrows) - 1
	_send_inv(shooter.id)
	return true


func server_sync(pid: int) -> void:
	var cells := PackedInt32Array()
	var vals := PackedByteArray()
	for c: int in placed:
		cells.append(c)
		vals.append(_grid.blocks[c])
	_s_state.rpc_id(pid, inv, beds, upgrades, finals, bed_breaks)
	if not cells.is_empty():
		_s_cells.rpc_id(pid, cells, vals)


func server_on_death(victim_id: int, killer_id: int, _wid: String) -> void:
	var v: Player = world.entities.get(victim_id)
	if v == null:
		return
	var d := inv_of(victim_id)
	var credit := killer_id
	if credit == victim_id and World.now() - v.last_hurt_time < 8.0:
		credit = v.last_attacker
	if credit != victim_id and world.entities.has(credit):
		var k := inv_of(credit)
		for r: String in RESOURCES:
			k[r] = int(k[r]) + int(d[r])
		_send_inv(credit)
	var team := clampi(Teams.of(v), 0, 1)
	_bot.erase(victim_id)
	if not beds[team]:
		out[victim_id] = true
		if credit != victim_id and world.entities.has(credit):
			finals[credit] = int(finals.get(credit, 0)) + 1
		_broadcast(&"_s_final", [victim_id, credit])
	for r: String in RESOURCES + ["wool", "wood", "stone", "arrows", "bow"]:
		d[r] = 0
	d.sword = 0
	_send_inv(victim_id)
	_broadcast(&"_s_kit", [victim_id, "", SWORDS[0]])


func server_on_kill(_victim_id: int, _killer_id: int, _wid: String) -> void:
	_server_check_end()


func server_human_left(pid: int) -> void:
	super.server_human_left(pid)
	_server_check_end.call_deferred()


func _server_check_end() -> void:
	if world.match_over:
		return
	var alive := Teams.counts(world, true)
	var standing := [beds[0] or alive[0] > 0, beds[1] or alive[1] > 0]
	# Players waiting to respawn count while their bed stands.
	if standing[0] and not standing[1]:
		world.server_end_match()
	elif standing[1] and not standing[0]:
		world.server_end_match()


func server_winner() -> int:
	var alive := Teams.counts(world, true)
	var s := [0, 0]
	for t in 2:
		s[t] = (1000 if beds[t] else 0) + alive[t] * 10 + (1 if beds[t] or alive[t] > 0 else 0)
	if s[0] == s[1]:
		return -1
	return 0 if s[0] > s[1] else 1


func server_finish(rows: Array) -> Dictionary:
	annotate_rows(rows)
	var winner := server_winner()
	for r: Dictionary in rows:
		r.won = winner >= 0 and int(r.team) == winner
		r.finals = int(finals.get(int(r.id), 0))
		r.beds = int(bed_breaks.get(int(r.id), 0))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.team != b.team:
			return a.team == winner or (winner < 0 and a.team < b.team)
		return int(a.finals) * 3 + int(a.kills) + int(a.beds) * 5 > int(b.finals) * 3 + int(b.kills) + int(b.beds) * 5)
	return {"winner": winner}


# ---------------------------------------------------------------- HUD and scoreboard

func score_columns() -> Array:
	return ["KILLS", "FINALS", "BEDS"]


func row_cells(r: Dictionary) -> Array:
	var eid := int(r.id)
	return [r.kills, int(r.get("finals", finals.get(eid, 0))), int(r.get("beds", bed_breaks.get(eid, 0)))]


func hud_bars() -> Array:
	var alive := Teams.counts(world, true)
	var total := Teams.counts(world)
	var outb: Array = []
	for t in 2:
		var frac := float(alive[t]) / maxf(1.0, float(total[t]))
		outb.append([frac, "%s  %s  %d" % [Teams.label(t), "BED ✓" if beds[t] else "BED ✗", alive[t]]])
	return outb


func hud_goal() -> String:
	return "Break the enemy bed, then finish them"


func hud_rank() -> String:
	var me := world.local_player
	if me == null:
		return ""
	return "Your bed: %s" % ("SAFE" if beds[clampi(Teams.of(me), 0, 1)] else "DESTROYED")


func row_tag(r: Dictionary) -> String:
	return "OUT" if out.has(int(r.id)) else ""


func row_dimmed(r: Dictionary) -> bool:
	return out.has(int(r.id))


# ================================================================ blocks

func cell_of(pos: Vector3) -> Vector3i:
	var c := pos - _origin
	return Vector3i(floori(c.x), floori(c.y), floori(c.z))


func cell_center(c: Vector3i) -> Vector3:
	return _origin + Vector3(c) + Vector3.ONE * 0.5


func solid(c: Vector3i) -> bool:
	return _grid != null and _grid.in_bounds(c.x, c.y, c.z) and not _grid.is_air(c.x, c.y, c.z)


func block_id(kind: String, team: int) -> int:
	match kind:
		"wood": return BlockAtlas.PLANKS
		"stone": return BlockAtlas.SANDSTONE
	return BlockAtlas.BLUE if team == 0 else BlockAtlas.ORANGE


func kind_of_block(b: int) -> String:
	match b:
		BlockAtlas.PLANKS: return "wood"
		BlockAtlas.SANDSTONE: return "stone"
	return "wool"


## Whether a block may go into cell `c` now: in the map, air, not too high, not inside anyone,
## not on a bed or a generator.
func can_place(c: Vector3i) -> bool:
	if _grid == null or not _grid.in_bounds(c.x, c.y, c.z) or not _grid.is_air(c.x, c.y, c.z):
		return false
	if c.y > TOP_CELL:
		return false
	var lo := _origin + Vector3(c)
	var box := AABB(lo, Vector3.ONE)
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if not p.alive:
			continue
		var pb := AABB(p.global_position - Vector3(0.38, 0.0, 0.38), Vector3(0.76, 1.75, 0.76))
		if pb.intersects(box):
			return false
	for t in 2:
		var m := team_mark(t)
		var bed: Vector3 = m.get("bed", Vector3.ZERO)
		if AABB(bed - Vector3(0.6, 0.0, 0.6) - (m.bed_dir as Vector3).abs() * 0.5, Vector3(1.2, 0.6, 1.2) + (m.bed_dir as Vector3).abs()).intersects(box):
			return false
	for pile: Dictionary in piles:
		if (pile.pos as Vector3).distance_to(lo + Vector3(0.5, 0.0, 0.5)) < 1.2:
			return false
	return true


func _apply_cells(cells: PackedInt32Array, vals: PackedByteArray) -> void:
	var mesher := world.map_info.mesher
	if mesher == null:
		return
	for k in cells.size():
		if vals[k] == BlockAtlas.AIR:
			placed.erase(cells[k])
		else:
			placed[cells[k]] = true
	mesher.set_cells(cells, vals, _dirty)


func _process(delta: float) -> void:
	if not _dirty.is_empty():
		var mesher := world.map_info.mesher
		var data := mesher.mesh_chunks(_dirty.keys())
		_dirty = {}
		for key: Vector2i in data:
			mesher.apply_chunk(key, data[key])
	_place_cd -= delta
	_update_overlay()


func _index(c: Vector3i) -> int:
	return _grid.index(c.x, c.y, c.z)


func _cell_from_index(i: int) -> Vector3i:
	var sx := _grid.size.x
	var sz := _grid.size.z
	return Vector3i(i % sx, i / (sx * sz), (i / sx) % sz)


## Local player or bot (server) asks to place `kind` at `c`.
func request_place(p: Player, c: Vector3i) -> bool:
	var d := inv_of(p.id)
	var kind := str(d.block)
	if int(d.get(kind, 0)) <= 0:
		kind = _any_block(d)
		if kind.is_empty():
			return false
		d.block = kind
	if not can_place(c):
		return false
	var i := _index(c)
	if multiplayer.is_server():
		_server_place(p.id, i, kind)
	else:
		d[kind] = int(d[kind]) - 1
		_apply_cells(PackedInt32Array([i]), PackedByteArray([block_id(kind, Teams.of(p))]))
		_c_place.rpc_id(1, i, kind)
	Sfx.play(&"footstep", cell_center(c), -2.0)
	return true


func _any_block(d: Dictionary) -> String:
	for k: String in BLOCK_KINDS:
		if int(d.get(k, 0)) > 0:
			return k
	return ""


func block_count(eid: int) -> int:
	var d := inv_of(eid)
	return int(d.wool) + int(d.wood) + int(d.stone)


func _server_place(eid: int, i: int, kind: String) -> bool:
	var p: Player = world.entities.get(eid)
	var d := inv_of(eid)
	var c := _cell_from_index(i) if i >= 0 and i < _grid.blocks.size() else Vector3i(-1, -1, -1)
	var ok := p != null and p.alive and kind in BLOCK_KINDS and int(d.get(kind, 0)) > 0 and c.x >= 0 \
		and (cell_center(c).distance_to(p.head.global_position) <= REACH + REACH_SLACK) and (can_place(c) or placed.has(i))
	if not ok or (placed.has(i) and _grid.blocks[i] != BlockAtlas.AIR):
		if eid > 0 and eid != world.my_id() and i >= 0 and i < _grid.blocks.size():
			_s_cells.rpc_id(eid, PackedInt32Array([i]), PackedByteArray([_grid.blocks[i]]))
			_send_inv(eid)
		return false
	d[kind] = int(d[kind]) - 1
	_broadcast(&"_s_cells", [PackedInt32Array([i]), PackedByteArray([block_id(kind, Teams.of(p))])])
	_send_inv(eid)
	return true


func _server_break(eid: int, i: int) -> bool:
	var p: Player = world.entities.get(eid)
	if p == null or not p.alive or not placed.has(i):
		return false
	if cell_center(_cell_from_index(i)).distance_to(p.head.global_position) > REACH + REACH_SLACK:
		return false
	_broadcast(&"_s_cells", [PackedInt32Array([i]), PackedByteArray([BlockAtlas.AIR])])
	return true


func _server_break_bed(eid: int, team: int) -> bool:
	var p: Player = world.entities.get(eid)
	if p == null or not p.alive or team < 0 or team > 1 or not beds[team] or Teams.of(p) == team:
		return false
	var bed: Vector3 = team_mark(team).bed
	if bed.distance_to(p.head.global_position) > REACH + REACH_SLACK + 1.0:
		return false
	bed_breaks[eid] = int(bed_breaks.get(eid, 0)) + 1
	_broadcast(&"_s_bed", [team, eid])
	_server_check_end()
	return true


# ================================================================ local item use

## Fire / aim with the blocks or the bow (and breaking with anything), for the local player.
func item_tick(p: Player, delta: float) -> bool:
	var wid := p.weapon_id()
	if p.mode != Player.Mode.LOCAL:
		# Bots: BedWars drives their blocks and bow itself; only the sword swings normally.
		return wid != "" and not Data.is_melee(wid)
	var d := inv_of(p.id)
	if p.in_reload:
		p.in_reload = false
		if wid == "bw_blocks":
			var k := BLOCK_KINDS.find(str(d.block))
			for n in BLOCK_KINDS.size():
				k = (k + 1) % BLOCK_KINDS.size()
				if int(d[BLOCK_KINDS[k]]) > 0:
					break
			d.block = BLOCK_KINDS[k]
	var hit := _look_hit(p)
	# Breaking (left click held on a placed block or the enemy bed; not with the bow).
	if p.in_fire and wid != "bw_bow" and not hit.is_empty():
		var key := -1
		var need := 0.0
		if hit.has("bed"):
			if int(hit.bed) != Teams.of(p) and beds[int(hit.bed)]:
				key = -2 - int(hit.bed)
				need = BED_BREAK_TIME
		else:
			var i := _index(hit.cell)
			if placed.has(i):
				key = i
				need = float(BREAK_TIME[kind_of_block(_grid.blocks[i])])
		if key != -1:
			if key != _break_cell:
				_break_cell = key
				_break_t = 0.0
			_break_t += delta
			if _break_t >= need:
				_break_t = 0.0
				_break_cell = -1
				if key <= -2:
					var team := -2 - key
					if multiplayer.is_server():
						_server_break_bed(p.id, team)
					else:
						_c_bed.rpc_id(1, team)
				else:
					if multiplayer.is_server():
						_server_break(p.id, key)
					else:
						_c_break.rpc_id(1, key)
			if wid == "bw_blocks":
				return true
		else:
			_break_cell = -1
	else:
		_break_cell = -1
		_break_t = 0.0
	if wid == "bw_blocks":
		if p.in_aim and _place_cd <= 0.0 and not hit.is_empty() and not hit.has("bed"):
			var c: Vector3i = hit.cell + hit.normal
			if request_place(p, c):
				_place_cd = PLACE_GAP
		return true
	if wid == "bw_bow":
		if p.in_fire and int(d.arrows) > 0:
			_drawing = true
			_draw = minf(_draw + delta, 1.0)
		elif _drawing:
			_drawing = false
			if _draw > 0.15:
				_shoot_arrow(p, p.aim_transform(), _draw)
			_draw = 0.0
		return true
	return false


func _shoot_arrow(p: Player, aim: Transform3D, draw: float) -> void:
	var dir := -aim.basis.z
	var speed := float(Data.WEAPONS.bw_bow.speed) * clampf(draw, 0.2, 1.0)
	world.request_projectile(p, "bw_bow", aim.origin + dir * 0.6, dir * speed)
	var d := inv_of(p.id)
	if not multiplayer.is_server():
		d.arrows = maxi(0, int(d.arrows) - 1)


## What the local player looks at within REACH: {cell, normal} of a block or {bed: team}, or {}.
func _look_hit(p: Player) -> Dictionary:
	var aim := p.aim_transform()
	var q := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * REACH, Player.MASK_WORLD, p.exclude_rids())
	var r := p.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return {}
	if r.collider is Node and (r.collider as Node).has_meta(&"bed_team"):
		return {"bed": int((r.collider as Node).get_meta(&"bed_team"))}
	var n: Vector3 = r.normal
	var inside: Vector3 = (r.position as Vector3) - n * 0.05
	return {"cell": cell_of(inside), "normal": Vector3i(roundi(n.x), roundi(n.y), roundi(n.z))}


## Sneaking (crouched on the ground) never walks off an edge.
func edge_guard(p: Player, delta: float) -> void:
	if not p.crouching or not p.is_on_floor():
		return
	var pos := p.global_position
	var step := Vector3(p.velocity.x * delta, 0.0, 0.0)
	if not _supported(pos + step):
		p.velocity.x = 0.0
		step.x = 0.0
	if not _supported(pos + step + Vector3(0.0, 0.0, p.velocity.z * delta)):
		p.velocity.z = 0.0


func _supported(pos: Vector3) -> bool:
	for ox: float in [-0.3, 0.3]:
		for oz: float in [-0.3, 0.3]:
			if solid(cell_of(pos + Vector3(ox, -0.08, oz))):
				return true
	# The beds hold you too.
	for t in 2:
		var bed: Vector3 = team_mark(t).get("bed", Vector3(0, -999, 0))
		if absf(pos.y - bed.y - 0.56) < 0.2 and Vector2(pos.x - bed.x, pos.z - bed.z).length() < 1.3:
			return true
	return false


# ================================================================ shop

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not world.input_blocked():
		var where := _near_stand()
		if where != "":
			get_viewport().set_input_as_handled()
			_open_shop(where == "upgrades")


func _near_stand() -> String:
	var p := world.local_player
	if p == null or not p.alive:
		return ""
	var m := team_mark(Teams.of(p))
	if m.is_empty():
		return ""
	if p.global_position.distance_to(m.shop) < 2.6:
		return "shop"
	if p.global_position.distance_to(m.upgrades) < 2.6:
		return "upgrades"
	return ""


func request_buy(item: String) -> void:
	if multiplayer.is_server():
		_server_buy(world.my_id(), item)
	else:
		_c_buy.rpc_id(1, item)


## Server: `eid` buys shop item or team upgrade `item`.
func _server_buy(eid: int, item: String) -> bool:
	var p: Player = world.entities.get(eid)
	if p == null or not p.alive:
		return false
	var d := inv_of(eid)
	var team := clampi(Teams.of(p), 0, 1)
	if UPGRADES.has(item):
		var u: Array = UPGRADES[item]
		var lvl := int(upgrades[team][item])
		if lvl >= int(u[1]) or int(d.diamond) < int(u[2][lvl]):
			return false
		d.diamond = int(d.diamond) - int(u[2][lvl])
		upgrades[team][item] = lvl + 1
		_send_inv(eid)
		_broadcast(&"_s_upgrades", [upgrades, team, "%s %s" % [str(u[0]), _roman(lvl + 1)]])
		return true
	if not SHOP.has(item):
		return false
	var s: Array = SHOP[item]
	var give: Dictionary = s[3]
	if give.has("sword") and int(d.sword) >= int(give.sword):
		return false
	if give.has("armor") and int(d.armor) >= int(give.armor):
		return false
	if give.has("bow") and int(d.bow) > 0:
		return false
	if int(d[str(s[1])]) < int(s[2]):
		return false
	d[str(s[1])] = int(d[str(s[1])]) - int(s[2])
	for k: String in give:
		match k:
			"sword", "armor":
				d[k] = int(give[k])
			"bow":
				d.bow = 1
			"apple":
				world.server_set_health(eid, p.max_health())
			_:
				d[k] = int(d.get(k, 0)) + int(give[k])
				if k in BLOCK_KINDS and block_count(eid) == int(give[k]):
					d.block = k
	_send_inv(eid)
	if give.has("sword") or give.has("bow"):
		_broadcast(&"_s_kit", [eid, "bw_bow" if int(d.bow) > 0 else "", SWORDS[int(d.sword)]])
	return true


static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV"][clampi(n, 0, 4)]


func _open_shop(ups: bool) -> void:
	_shop_upgrades = ups
	_shop.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fill_shop()


func _close_shop() -> void:
	if _shop != null and _shop.visible:
		_shop.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if _shop != null and _shop.visible and (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"interact")):
		get_viewport().set_input_as_handled()
		_close_shop()


func _fill_shop() -> void:
	for c in _shop_grid.get_children():
		c.queue_free()
	var me := world.local_player
	if me == null:
		return
	var d := inv_of(me.id)
	var team := clampi(Teams.of(me), 0, 1)
	_shop_info.text = "IRON %d   GOLD %d   DIAMOND %d   EMERALD %d" % [int(d.iron), int(d.gold), int(d.diamond), int(d.emerald)]
	if _shop_upgrades:
		for id: String in UPGRADES:
			var u: Array = UPGRADES[id]
			var lvl := int(upgrades[team][id])
			var maxed := lvl >= int(u[1])
			var b := UIKit.button("%s %s\n%s" % [u[0], _roman(lvl + 1) if not maxed else "MAX", "" if maxed else "%d diamond" % int(u[2][lvl])])
			b.custom_minimum_size = Vector2(220, 64)
			b.disabled = maxed or int(d.diamond) < int(u[2][lvl]) if not maxed else true
			b.pressed.connect(func() -> void:
				request_buy(id)
				get_tree().create_timer(0.15).timeout.connect(_fill_shop))
			_shop_grid.add_child(b)
		return
	for id: String in SHOP_ORDER:
		var s: Array = SHOP[id]
		var b := UIKit.button("%s\n%d %s" % [s[0], int(s[2]), s[1]])
		b.custom_minimum_size = Vector2(200, 60)
		b.add_theme_color_override("font_color", RES_COLORS[str(s[1])])
		b.disabled = int(d[str(s[1])]) < int(s[2])
		b.pressed.connect(func() -> void:
			Sfx.play(&"ui_click")
			request_buy(id)
			get_tree().create_timer(0.15).timeout.connect(_fill_shop))
		_shop_grid.add_child(b)


# ================================================================ overlay

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 11
	add_child(_overlay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	_overlay.add_child(root)
	_res_label = _label(18)
	_res_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_res_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_res_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_res_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_res_label.offset_right = -24
	_res_label.offset_bottom = -150
	root.add_child(_res_label)
	_hud_label = _label(16)
	_hud_label.position = Vector2(20, 150)
	root.add_child(_hud_label)
	_cool_bar = _bar(Color(1, 1, 1, 0.9))
	_cool_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_cool_bar.position += Vector2(-16, 22)
	root.add_child(_cool_bar)
	_break_bar = _bar(Color(1, 0.6, 0.2, 0.95))
	_break_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_break_bar.position += Vector2(-16, 30)
	root.add_child(_break_bar)
	_prompt = _label(20)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position.y += 70
	root.add_child(_prompt)
	_shop = Control.new()
	_shop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shop.mouse_filter = Control.MOUSE_FILTER_STOP
	_shop.visible = false
	root.add_child(_shop)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shop.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shop.add_child(center)
	var panel := UIKit.panel()
	center.add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)
	v.add_child(UIKit.label("BEDWARS SHOP", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	_shop_info = UIKit.label("", &"SubheaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_shop_info)
	_shop_grid = GridContainer.new()
	_shop_grid.columns = 4
	_shop_grid.add_theme_constant_override("h_separation", 8)
	_shop_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(_shop_grid)
	var close := UIKit.button("CLOSE (Esc)")
	close.pressed.connect(_close_shop)
	v.add_child(close)


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(32, 4)
	b.size = Vector2(32, 4)
	b.show_percentage = false
	b.max_value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	return b


func _update_overlay() -> void:
	var me := world.local_player
	if me == null or _res_label == null:
		return
	var d := inv_of(me.id)
	var team := clampi(Teams.of(me), 0, 1)
	var u: Dictionary = upgrades[team]
	_res_label.text = "IRON %d   GOLD %d\nDIAMOND %d   EMERALD %d\n%s x%d  (R: next kind)   ARROWS %d\nARMOUR %s   SHARP %s  PROT %s  FORGE %s" % [
		int(d.iron), int(d.gold), int(d.diamond), int(d.emerald), str(d.block).to_upper(), int(d.get(str(d.block), 0)),
		int(d.arrows), ARMOR_NAMES[clampi(int(d.armor), 0, 3)], _roman(int(u.sharp)) if int(u.sharp) > 0 else "-",
		_roman(int(u.prot)) if int(u.prot) > 0 else "-", _roman(int(u.forge)) if int(u.forge) > 0 else "-"]
	var held := me.weapon_id() if me.alive else ""
	_cool_bar.visible = me.alive and Data.WEAPONS.get(held, {}).has("cooldown")
	if _cool_bar.visible:
		_cool_bar.value = attack_charge(me)
	_break_bar.visible = _break_cell != -1 and _break_t > 0.0
	if _break_bar.visible:
		var need := BED_BREAK_TIME if _break_cell <= -2 else float(BREAK_TIME[kind_of_block(_grid.blocks[_break_cell])])
		_break_bar.value = _break_t / need
	if held == "bw_bow":
		_cool_bar.visible = true
		_cool_bar.value = _draw
	var where := _near_stand()
	_prompt.text = "" if where == "" or _shop.visible else "%s: %s" % [Profile.key_text("interact"), "TEAM UPGRADES" if where == "upgrades" else "SHOP"]
	_hud_label.text = ""


func _refresh_piles() -> void:
	for k in piles.size():
		var pile: Dictionary = piles[k]
		_pile_labels[k].text = "%s x%d" % [str(pile.res).to_upper(), int(pile.count)] if int(pile.count) > 0 else str(pile.res).to_upper()


# ================================================================ server tick: generators

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or world.match_over:
		return
	var changed := false
	for k in piles.size():
		var pile: Dictionary = piles[k]
		var rate := 1.0
		if str(pile.res) in ["iron", "gold"]:
			var team := _forge_team(pile.pos)
			if team >= 0:
				rate = FORGE_MULT[int(upgrades[team].forge)]
		_gen_t[k] += delta * rate
		if _gen_t[k] >= float(pile.every):
			_gen_t[k] = 0.0
			if int(pile.count) < int(pile.cap):
				pile.count = int(pile.count) + 1
				changed = true
		if int(pile.count) <= 0:
			continue
		var best: Player = null
		var best_d := PICK_RADIUS
		for eid: int in world.entities:
			var p: Player = world.entities[eid]
			if not p.alive:
				continue
			var dist := Vector2(p.global_position.x - pile.pos.x, p.global_position.z - pile.pos.z).length()
			if dist < best_d and absf(p.global_position.y - pile.pos.y) < 2.0:
				best = p
				best_d = dist
		if best != null:
			var d := inv_of(best.id)
			d[pile.res] = int(d[pile.res]) + int(pile.count)
			pile.count = 0
			changed = true
			_send_inv(best.id)
	if changed:
		var counts := PackedInt32Array()
		for pile: Dictionary in piles:
			counts.append(int(pile.count))
		_broadcast(&"_s_piles", [counts])


func _forge_team(pos: Vector3) -> int:
	for t in 2:
		if (team_mark(t).forge as Vector3).distance_to(pos) < 1.0:
			return t
	return -1


func _send_inv(eid: int) -> void:
	_broadcast(&"_s_inv", [eid, inv_of(eid)])


# ================================================================ RPCs

@rpc("any_peer", "call_remote", "reliable")
func _c_place(i: int, kind: String) -> void:
	_server_place(multiplayer.get_remote_sender_id(), i, kind)


@rpc("any_peer", "call_remote", "reliable")
func _c_break(i: int) -> void:
	_server_break(multiplayer.get_remote_sender_id(), i)


@rpc("any_peer", "call_remote", "reliable")
func _c_bed(team: int) -> void:
	_server_break_bed(multiplayer.get_remote_sender_id(), team)


@rpc("any_peer", "call_remote", "reliable")
func _c_buy(item: String) -> void:
	_server_buy(multiplayer.get_remote_sender_id(), item)


@rpc("authority", "call_remote", "reliable")
func _s_cells(cells: PackedInt32Array, vals: PackedByteArray) -> void:
	_apply_cells(cells, vals)


@rpc("authority", "call_remote", "reliable")
func _s_inv(eid: int, d: Dictionary) -> void:
	var cur := inv_of(eid)
	for k: String in d:
		cur[k] = d[k]
	if _shop != null and _shop.visible and eid == world.my_id():
		_fill_shop()


@rpc("authority", "call_remote", "reliable")
func _s_piles(counts: PackedInt32Array) -> void:
	for k in mini(counts.size(), piles.size()):
		piles[k].count = counts[k]
	_refresh_piles()


@rpc("authority", "call_remote", "reliable")
func _s_kit(eid: int, primary: String, melee: String) -> void:
	var p: Player = world.entities.get(eid)
	if p == null:
		return
	if p.slots[0] != primary:
		p.give_weapon(0, primary)
	if p.slots[2] != melee:
		p.give_weapon(2, melee)


@rpc("authority", "call_remote", "reliable")
func _s_knock(eid: int, vel: Vector3) -> void:
	var p: Player = world.entities.get(eid)
	if p == null or p.mode == Player.Mode.REMOTE or not p.alive:
		return
	p.velocity.x = vel.x
	p.velocity.z = vel.z
	p.velocity.y = maxf(p.velocity.y, vel.y)


@rpc("authority", "call_remote", "reliable")
func _s_bed(team: int, by: int) -> void:
	beds[team] = false
	bed_breaks[by] = int(bed_breaks.get(by, 0)) + (0 if multiplayer.is_server() else 1)
	if team < _bed_nodes.size():
		_bed_nodes[team].queue_free()
	Sfx.play(&"explosion", team_mark(team).bed, 0.0)
	var mine := Teams.of(world.local_player)
	if team == mine:
		world.hud.announce("YOUR BED WAS DESTROYED BY %s!" % world.display_name(by))
	else:
		world.hud.announce("%s BED DESTROYED BY %s" % [Teams.label(team), world.display_name(by)])
	world.hud.refresh_scores()


@rpc("authority", "call_remote", "reliable")
func _s_final(victim: int, by: int) -> void:
	out[victim] = true
	if victim != by:
		finals[by] = int(finals.get(by, 0)) + (0 if multiplayer.is_server() else 1)
	world.hud.callout("FINAL KILL: %s" % world.display_name(victim), "info", Color(1.0, 0.35, 0.3))
	world.hud.refresh_scores()


@rpc("authority", "call_remote", "reliable")
func _s_upgrades(all: Array, team: int, what: String) -> void:
	upgrades = all
	if team == Teams.of(world.local_player):
		world.hud.callout("TEAM UPGRADE: %s" % what, "info", Teams.color(team))


@rpc("authority", "call_remote", "reliable")
func _s_state(all_inv: Dictionary, all_beds: Array, all_up: Array, all_finals: Dictionary, all_breaks: Dictionary) -> void:
	inv = all_inv
	upgrades = all_up
	finals = all_finals
	bed_breaks = all_breaks
	for t in 2:
		if beds[t] and not bool(all_beds[t]) and t < _bed_nodes.size():
			_bed_nodes[t].queue_free()
		beds[t] = bool(all_beds[t])


# ================================================================ bots

## Bot roles: 0 defender (covers the bed, guards home, gears up), 1 attacker (gears up, bridges
## over, breaks the bed, hunts). Phases: "gear", "defend", "bridge", "raid", "hunt".
func bot_drive(p: Player, brain: BotBrain, delta: float) -> bool:
	var st: Dictionary = _bot.get(p.id, {})
	if st.is_empty():
		st = _bot_init(p)
		_bot[p.id] = st
	st.t = float(st.t) + delta
	st.cd = float(st.cd) - delta
	var team := clampi(Teams.of(p), 0, 1)
	var foe := 1 - team
	var d := inv_of(p.id)
	var diff := brain.difficulty
	p.in_slot = 2
	# 1. Fight anyone close.
	var enemy := _bot_enemy(p, brain, 14.0 if st.phase != "bridge" else 7.0)
	if enemy != null and float(st.t) >= float(st.get("ignore_until", 0.0)):
		_bot_fight(p, brain, enemy, delta, st)
		return true
	# 2. Shopping on the home island.
	var m := team_mark(team)
	var home := _on_island(p.global_position, m.spawn, 8.0)
	if home and _bot_wants(p, st):
		if _goto(p, brain, m.shop, delta, st, false) < 1.6:
			_bot_shop(p, st)
		return true
	match str(st.phase):
		"gear":
			# Collect at the forge until there's enough for blocks (and armour for defenders).
			var want := 12 if int(st.role) == 1 else 24
			if block_count(p.id) >= 24 and (int(st.role) == 1 or int(d.armor) > 0 or st.t > 50.0):
				st.phase = "defend" if int(st.role) == 0 and beds[team] and not bool(st.covered) else "bridge"
				st.wp = 0
			elif home:
				if int(d.iron) < want or block_count(p.id) >= 24:
					_goto(p, brain, m.forge, delta, st, false)
				else:
					st.shop_now = true
			else:
				_bot_go_home(p, brain, delta, st)
		"defend":
			if not beds[team] or not home:
				st.phase = "bridge"
				return true
			if _bot_cover_bed(p, brain, delta, st):
				st.covered = true
				_covered[team] = true
				st.phase = "guard"
		"guard":
			# Hold near the bed, nip to the forge, and go raiding once geared.
			if st.t > 75.0 and diff > 0 and block_count(p.id) >= 24 or not beds[team]:
				st.phase = "bridge"
				st.wp = 0
			elif block_count(p.id) < 24 or int(d.iron) < 24:
				_goto(p, brain, m.forge, delta, st, false)
			else:
				_goto(p, brain, m.bed + (m.bed_dir as Vector3) * 2.5, delta, st, false)
		"bridge":
			if block_count(p.id) == 0 and not _on_island(p.global_position, team_mark(foe).spawn, 8.0):
				st.phase = "gear"
				return true
			var route := _route(team)
			var wp := int(st.wp)
			if wp >= route.size():
				st.phase = "raid" if beds[foe] else "hunt"
				return true
			var goal: Vector3 = route[wp]
			if _goto(p, brain, goal, delta, st, true) < 0.9:
				st.wp = wp + 1
		"raid":
			if not beds[foe]:
				st.phase = "hunt"
				return true
			_bot_raid(p, brain, delta, st, foe)
		"hunt":
			var target := _nearest_enemy(p)
			if target == null:
				_goto(p, brain, team_mark(foe).spawn, delta, st, true)
			else:
				_goto(p, brain, target.global_position, delta, st, true)
	return true


func _bot_init(p: Player) -> Dictionary:
	var team := clampi(Teams.of(p), 0, 1)
	var mates: Array = []
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if Teams.of(o) == team:
			mates.append(eid)
	mates.sort()
	var role := 1
	if mates.size() >= 2 and mates.find(p.id) == mates.size() - 1:
		role = 0
	if mates.size() == 1:
		role = 1
	return {"t": 0.0, "cd": 0.0, "role": role, "phase": "gear", "wp": 0,
		"covered": bool(_covered[team]) and beds[team], "stuck": 0.0, "last_pos": p.global_position,
		"break": -1, "break_t": 0.0, "shop_now": false, "jump_t": 0.0, "strafe": 1.0 if randf() < 0.5 else -1.0, "bow_t": 1.0}


func _on_island(pos: Vector3, center: Vector3, half: float) -> bool:
	return absf(pos.x - center.x) < half and absf(pos.z - center.z) < half and absf(pos.y - center.y) < 3.0


func _nearest_enemy(p: Player) -> Player:
	var best: Player = null
	var bd := INF
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if not o.alive or not world.is_enemy(p, o):
			continue
		var dd := o.global_position.distance_to(p.global_position)
		if dd < bd:
			bd = dd
			best = o
	return best


func _bot_enemy(p: Player, brain: BotBrain, radius: float) -> Player:
	var o := _nearest_enemy(p)
	if o == null:
		return null
	var dist := o.global_position.distance_to(p.global_position)
	if dist < 4.0 or (dist < radius and brain.can_see(o, false)):
		return o
	# The bow reaches further.
	if int(inv_of(p.id).bow) > 0 and int(inv_of(p.id).arrows) > 0 and dist < 32.0 and brain.can_see(o, true):
		return o
	return null


## Sword fight, Minecraft style: close in sprinting, swing only once the cooldown is (mostly)
## back, jump for crits on Normal/Hard, circle-strafe; the bow at range.
func _bot_fight(p: Player, brain: BotBrain, e: Player, delta: float, st: Dictionary) -> void:
	var diff := brain.difficulty
	var dist := e.global_position.distance_to(p.global_position)
	var d := inv_of(p.id)
	if dist > 9.0 and int(d.bow) > 0 and int(d.arrows) > 0:
		p.in_slot = 0
		var lead := e.global_position + Vector3.UP * 1.2 + e.velocity * (dist / 48.0)
		lead.y += 0.5 * ARROW_GRAVITY * pow(dist / 48.0, 2.0)
		brain.look_toward(lead, delta, 1.0)
		st.bow_t = float(st.bow_t) - delta
		if float(st.bow_t) <= 0.0:
			st.bow_t = [1.8, 1.3, 1.0][diff]
			var aim := p.aim_transform()
			var err: float = [0.06, 0.035, 0.018][diff]
			aim.basis = aim.basis.rotated(Vector3.UP, randf_range(-err, err)).rotated(aim.basis.x, randf_range(-err, err))
			_shoot_arrow(p, aim, 1.0)
		_safe_move(p, Vector3.ZERO)
		return
	p.in_slot = 2
	# Can't get closer (a gap, no blocks): give up on this fight for a while.
	if dist > 3.1:
		var best := float(st.get("fight_best", INF))
		if dist < best - 0.3:
			st.fight_best = dist
			st.stall = 0.0
		else:
			st.stall = float(st.get("stall", 0.0)) + delta
			if float(st.stall) > 4.0:
				st.ignore_until = float(st.t) + 8.0
				st.stall = 0.0
				st.fight_best = INF
	else:
		st.fight_best = dist
		st.stall = 0.0
	var to := e.global_position - p.global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.01 else Vector3.ZERO
	var side := dir.cross(Vector3.UP) * float(st.strafe)
	var move := dir
	if dist < 2.6:
		move = (side * 0.8 + dir * 0.3) if diff > 0 else dir * 0.2
		if randf() < delta * 0.6:
			st.strafe = -float(st.strafe)
	if dist > 2.8:
		# Close in, bridging over any gap.
		_goto(p, brain, e.global_position, delta, st, true)
	else:
		p.in_sprint = dist > 2.0
		_safe_move(p, move)
	brain.look_toward(e.head.global_position - Vector3.UP * 0.4, delta, [0.8, 1.2, 1.8][diff])
	var charge := attack_charge(p)
	var need: float = [0.55, 0.85, 0.93][diff]
	if dist < 3.4 and diff >= 1 and p.is_on_floor() and charge > 0.6 and float(st.jump_t) <= 0.0 and randf() < 0.5:
		p.in_jump = true
		st.jump_t = 0.9
	st.jump_t = float(st.jump_t) - delta
	var falling := not p.is_on_floor() and p.velocity.y < 0.0
	if dist < 3.1 and charge >= need and (falling or p.is_on_floor() or diff < 2):
		p.in_fire = true


## Move along world direction `move` (sprinting as set), sneaking whenever the next step has no
## floor, so bots never walk off into the void.
func _safe_move(p: Player, move: Vector3) -> void:
	if move.length_squared() < 0.0001:
		p.in_move = Vector2.ZERO
		return
	var local := Basis(Vector3.UP, -p.yaw) * move.normalized()
	p.in_move = Vector2(local.x, -local.z).limit_length(1.0)
	if not _supported(p.global_position + move.normalized() * 0.7):
		p.in_crouch = true
		p.in_sprint = false


## Walks (bridging when `bridge`) toward `goal`; returns the flat distance left.
func _goto(p: Player, brain: BotBrain, goal: Vector3, delta: float, st: Dictionary, bridge: bool) -> float:
	var to := goal - p.global_position
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.5:
		p.in_move = Vector2.ZERO
		return flat
	var dir := Vector3(to.x, 0.0, to.z).normalized()
	brain.look_toward(p.head.global_position + dir * 5.0 + Vector3.UP * (-3.0 if bridge else -0.5), delta, 1.2)
	var ahead := p.global_position + dir * 0.75
	var floor_ahead := _supported(ahead)
	if not floor_ahead and bridge and p.is_on_floor():
		p.in_crouch = true
		p.in_sprint = false
		var local := Basis(Vector3.UP, -p.yaw) * dir
		p.in_move = Vector2(local.x, -local.z).limit_length(1.0)
		if float(st.cd) <= 0.0 and block_count(p.id) > 0:
			var c := cell_of(p.global_position + dir * 0.9 + Vector3.DOWN * 0.5)
			var feet := cell_of(p.global_position + Vector3.DOWN * 0.5)
			c.y = feet.y
			if not solid(c) and _server_place_bot(p, c):
				st.cd = [0.5, 0.32, 0.22][brain.difficulty]
		return flat
	p.in_sprint = flat > 4.0 and floor_ahead
	_safe_move(p, dir)
	# A one-block step: jump it.
	var front := cell_of(p.global_position + dir * 0.6 + Vector3.UP * 0.5)
	if solid(front) and p.is_on_floor():
		p.in_jump = true
	# Stuck: hop.
	if p.global_position.distance_to(st.last_pos) < 0.02 and p.is_on_floor():
		st.stuck = float(st.stuck) + delta
		if float(st.stuck) > 0.6:
			p.in_jump = true
			st.stuck = 0.0
	else:
		st.stuck = 0.0
	st.last_pos = p.global_position
	return flat


func _server_place_bot(p: Player, c: Vector3i) -> bool:
	var d := inv_of(p.id)
	if int(d.get(str(d.block), 0)) <= 0:
		d.block = _any_block(d)
	if str(d.block).is_empty() or not can_place(c):
		return false
	return _server_place(p.id, _index(c), str(d.block))


## Route from `team`'s island to the enemy's: out the side, along the flank (clear of the
## emerald island), and in to the enemy's spawn.
func _route(team: int) -> Array:
	var me := team_mark(team)
	var foe := team_mark(1 - team)
	var lane := (me.spawn as Vector3).x - 12.0 if team == 0 else (me.spawn as Vector3).x + 12.0
	var y: float = (me.spawn as Vector3).y
	return [Vector3((me.spawn as Vector3).x, y, (me.spawn as Vector3).z), Vector3(lane, y, (me.spawn as Vector3).z),
		Vector3(lane, y, (foe.spawn as Vector3).z), Vector3((foe.spawn as Vector3).x, y, (foe.spawn as Vector3).z)]


func _bot_go_home(p: Player, brain: BotBrain, delta: float, st: Dictionary) -> void:
	var team := clampi(Teams.of(p), 0, 1)
	var route := _route(team)
	# Walk back along the route (bridging any gap left by broken blocks).
	var best := 0
	var bd := INF
	for i in route.size():
		var dd := (route[i] as Vector3).distance_to(p.global_position)
		if dd < bd:
			bd = dd
			best = i
	var goal: Vector3 = route[maxi(best - 1, 0)] if bd < 1.5 else route[best]
	_goto(p, brain, goal, delta, st, true)


## Covers the bed in a shell of blocks (a layer around it and over it). True when done.
func _bot_cover_bed(p: Player, brain: BotBrain, delta: float, st: Dictionary) -> bool:
	var m := team_mark(clampi(Teams.of(p), 0, 1))
	var bed: Vector3 = m.bed
	var dir: Vector3 = m.bed_dir
	var a := cell_of(bed - dir * 0.5 + Vector3.UP * 0.2)
	var b := cell_of(bed + dir * 0.5 + Vector3.UP * 0.2)
	var cells: Array[Vector3i] = []
	for c: Vector3i in [a, b]:
		cells.append(c + Vector3i.UP)
		for off: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n := c + off
			if n != a and n != b:
				cells.append(n)
	if _goto(p, brain, bed + dir * 2.2, delta, st, false) > 1.2:
		return false
	brain.look_toward(bed, delta, 1.0)
	if float(st.cd) > 0.0:
		return false
	for c in cells:
		if not solid(c):
			if block_count(p.id) == 0:
				return true
			if _server_place_bot(p, c):
				st.cd = 0.25
				return false
	return true


func _bot_raid(p: Player, brain: BotBrain, delta: float, st: Dictionary, foe: int) -> void:
	var m := team_mark(foe)
	var bed: Vector3 = m.bed
	var dist := _goto(p, brain, bed - (m.bed_dir as Vector3) * 1.6, delta, st, true)
	if dist > 3.0:
		return
	p.in_move = Vector2.ZERO
	brain.look_toward(bed + Vector3.UP * 0.3, delta, 1.5)
	# Dig through the cover first: the first placed block between our eyes and the bed.
	var eye := p.head.global_position
	var q := PhysicsRayQueryParameters3D.create(eye, bed + Vector3.UP * 0.3, Player.MASK_WORLD, p.exclude_rids())
	var r := p.get_world_3d().direct_space_state.intersect_ray(q)
	var key := -2 - foe
	var need := BED_BREAK_TIME
	if not r.is_empty() and not (r.collider is Node and (r.collider as Node).has_meta(&"bed_team")):
		var c := cell_of((r.position as Vector3) - (r.normal as Vector3) * 0.05)
		var i := _index(c)
		if not placed.has(i):
			# Map block in the way: step round to the bed's other side.
			_goto(p, brain, bed + (m.bed_dir as Vector3) * 2.0, delta, st, true)
			return
		key = i
		need = float(BREAK_TIME[kind_of_block(_grid.blocks[i])])
	if int(st.break) != key:
		st.break = key
		st.break_t = 0.0
	st.break_t = float(st.break_t) + delta
	p.in_fire = randf() < 0.3
	if float(st.break_t) >= need:
		st.break_t = 0.0
		if key <= -2:
			_server_break_bed(p.id, foe)
		else:
			_server_break(p.id, key)


func _bot_wants(p: Player, st: Dictionary) -> bool:
	if bool(st.shop_now):
		return true
	var d := inv_of(p.id)
	return (int(d.iron) >= 24 and int(d.armor) < 1) or (int(d.gold) >= 7 and int(d.sword) < 2) \
		or (int(d.emerald) >= 4 and int(d.sword) < 3) or (int(d.iron) >= 10 and int(d.sword) < 1) \
		or (int(d.diamond) >= 2 and str(st.phase) != "bridge")


func _bot_shop(p: Player, st: Dictionary) -> void:
	st.shop_now = false
	var d := inv_of(p.id)
	var tries := 0
	while block_count(p.id) < 32 and int(d.iron) >= 4 and tries < 4:
		_server_buy(p.id, "wool")
		tries += 1
	for item: String in ["sword3", "armor3", "sword2", "armor2", "sword1", "armor1"]:
		_server_buy(p.id, item)
	for up: String in ["sharp", "prot", "forge", "prot"]:
		_server_buy(p.id, up)
	tries = 0
	while block_count(p.id) < 48 and int(d.iron) >= 4 and tries < 6:
		_server_buy(p.id, "wool")
		tries += 1
	if int(d.gold) >= 14 and int(d.bow) == 0:
		_server_buy(p.id, "bow")
	tries = 0
	while int(d.bow) > 0 and int(d.arrows) < 16 and int(d.gold) >= 2 and tries < 4:
		_server_buy(p.id, "arrows")
		tries += 1
