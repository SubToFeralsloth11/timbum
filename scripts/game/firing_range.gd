class_name FiringRange
extends MatchMode
## The Firing Range (`Net.config.session` "range", offline only, map Data.RANGE_MAP): practice
## against target dummies with any gun. It is World's mode controller, so World and the Hud run no
## match rules here: no clock, kill limit, race, scoreboard, results or spectating
## (`is_practice()`), and nothing counts: the session never ends, so Profile.record_match never
## runs, and World skips the live challenge / achievement toasts.
##
## Dummies are bot entities with `info.dummy` (Player builds no BotBrain for them): they take
## damage through the normal hit path (World._server_shot / _server_damage, damage numbers and
## hitmarkers included), and respawn on their post RESPAWN seconds after a kill. This node drives
## their inputs: static ones stand, strafing ones walk side to side, the peeking one crouches and
## leans behind the cover wall. The map's MapInfo.marks give the posts, signs, console and ledge.
##
## The readout (RangeOverlay) follows the local player's shots (on_local_shot / on_local_hit):
## the last hit's damage and distance, DPS over the last burst, shots-to-kill and TTK for the held
## gun at that distance (Player.damage_at with falloff and the player's Long Barrel), and the
## session's hit % and headshots. The weapon console (interact key, near the counter behind the
## line) equips any gun or melee weapon, owned or not, with the player's own attachment levels,
## plus frags, either tactical and a ready grapple. Reserves and grenades refill on their own.

const RESPAWN := 1.0
## A strafing dummy walks this far either side of its post, at this fraction of walking speed.
const STRAFE_SPAN := 2.5
const STRAFE_SPEED := 0.45
## The peeking dummy's loop: [pose, seconds].
const PEEK_CYCLE: Array = [["stand", 1.6], ["crouch", 1.4], ["lean_left", 1.2], ["stand", 0.8], ["lean_right", 1.2]]
const DUMMY_OUTFIT := "robot"
## How close (horizontally) the player must stand to use the weapon console.
const CONSOLE_REACH := 2.8
## Shots further apart than this (or 2.5 refire intervals) start a new burst for the DPS readout.
const BURST_GAP := 0.6
## Reserves and grenades top up this often.
const REFILL_INTERVAL := 1.5

## Dummy entity id -> {kind, dist, pos, dir, phase, t}.
var dummies := {}
## The local player's numbers (reset_readout()).
var readout := {}
var overlay: RangeOverlay
## The post of the dummy being added (spawn_point runs inside World.server_add_bot).
var _adding: Dictionary = {}
var _refill_t := 0.0
## Rocket shots waiting for their blast's first confirmed hit (hit % counts one per rocket).
var _rockets_pending := 0


func _init() -> void:
	name = "FiringRange"
	reset_readout()


func _ready() -> void:
	overlay = RangeOverlay.new()
	overlay.name = "RangeOverlay"
	overlay.setup(self)
	add_child(overlay)
	_build_signs()


## Floating distance signs over the lanes (and the cover lane, line and ledge).
func _build_signs() -> void:
	for s: Dictionary in world.map_info.marks.get("signs", []):
		var l := Label3D.new()
		l.text = str(s.text)
		l.position = s.pos
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.pixel_size = 0.012
		l.font_size = 72
		l.outline_size = 16
		l.modulate = Color(1.0, 0.86, 0.35)
		l.no_depth_test = false
		world.add_child(l)


# ================================================================ rules

func is_practice() -> bool:
	return true


func practice_intro() -> Array:
	return ["FIRING RANGE", "Lanes at 10, 25, 50 and 75 m  ·  %s at the console: try any gun  ·  nothing here counts toward your stats" \
		% Profile.key_text("interact")]


func clock_running() -> bool:
	return false


func respawn_delay() -> float:
	return RESPAWN


func spawn_protection() -> bool:
	return false


## Console picks stay through a respawn.
func uses_loadout(_p: Player) -> bool:
	return false


## No kill limit: the session runs until the player leaves.
func server_on_kill(_victim_id: int, _killer_id: int, _wid: String) -> void:
	pass


func ui_blocking() -> bool:
	return overlay != null and overlay.console_open()


func pause_actions() -> Array:
	return [["RESET READOUT", reset_readout]]


## Instead of bots: the dummies, once.
func server_balance() -> void:
	if not dummies.is_empty():
		return
	for d: Dictionary in world.map_info.marks.get("dummies", []):
		_adding = d
		var eid := world.server_add_bot(-1, _dummy_info(d))
		dummies[eid] = {"kind": str(d.kind), "dist": int(d.dist), "pos": d.pos, "dir": 1.0, "phase": 0, "t": 0.0}
	_adding = {}


func spawn_point(eid: int, _team: int) -> Array:
	if not _adding.is_empty():
		return [_adding.pos, PI]
	if dummies.has(eid):
		return [dummies[eid].pos, PI]
	# The player: on the firing line, facing down the lanes.
	return [world.map_info.marks.get("line", world.map_info.spawns[0]), 0.0]


static func _dummy_info(d: Dictionary) -> Dictionary:
	var title: String = {"static": "DUMMY", "strafe": "STRAFER", "peek": "PEEKER"}.get(str(d.kind), "DUMMY")
	return {
		"name": "%s %d m" % [title, int(d.dist)], "outfit": DUMMY_OUTFIT, "hat": "none", "skin": "default",
		"primary": "", "secondary": "", "tactical": "smoke", "charm": "none", "emote": "wave",
		"draw": "standard", "mods": {}, "level": 1, "dummy": true, "knife_only": true,
		"speed": STRAFE_SPEED if str(d.kind) == "strafe" else 1.0,
	}


func is_dummy(eid: int) -> bool:
	return dummies.has(eid)


# ================================================================ frame

func _physics_process(delta: float) -> void:
	if world.is_frozen():
		return
	for eid: int in dummies:
		var p: Player = world.entities.get(eid)
		if p == null or not p.alive:
			continue
		_drive_dummy(p, dummies[eid], delta)
	var me := world.local_player
	if me != null and me.alive:
		_refill_t -= delta
		if _refill_t <= 0.0:
			_refill_t = REFILL_INTERVAL
			me.top_up_reserves()
			if me.grenades < int(Data.GRENADE.per_life) or me.tacticals < Data.TACTICAL_PER_LIFE:
				world.refill_equipment(me.id)


func _drive_dummy(p: Player, d: Dictionary, delta: float) -> void:
	p.yaw = PI
	p.pitch = 0.0
	match str(d.kind):
		"strafe":
			var off: float = p.global_position.x - (d.pos as Vector3).x
			if off * float(d.dir) > STRAFE_SPAN:
				d.dir = -float(d.dir)
			# Facing +z (yaw PI), the move input's x points along world -x.
			p.in_move = Vector2(-float(d.dir), 0.0)
		"peek":
			d.t = float(d.t) - delta
			if float(d.t) <= 0.0:
				d.phase = (int(d.phase) + 1) % PEEK_CYCLE.size()
				d.t = float(PEEK_CYCLE[d.phase][1])
			var pose: String = PEEK_CYCLE[d.phase][0]
			p.in_crouch = pose == "crouch"
			p.in_lean = -1 if pose == "lean_left" else (1 if pose == "lean_right" else 0)


func _process(_delta: float) -> void:
	for eid: int in dummies:
		var p: Player = world.entities.get(eid)
		if p != null and p.nametag != null:
			p.nametag.text = "%s  ·  %d HP" % [str(p.info.name), ceili(p.health)] if p.alive else str(p.info.name)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and near_console() and not world.input_blocked():
		get_viewport().set_input_as_handled()
		overlay.open_console()


## Whether the local player stands at the weapon console.
func near_console() -> bool:
	var p := world.local_player
	if p == null or not p.alive or not world.map_info.marks.has("console"):
		return false
	var c: Vector3 = world.map_info.marks.console
	return Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() <= CONSOLE_REACH \
		and absf(p.global_position.y - c.y) < 2.5


# ================================================================ weapon console

## Puts `wid` in its slot (any gun or melee weapon, owned or not) and draws it.
## Offline the local Player is also the server's entity, so hit validation sees the new slots.
func equip(wid: String) -> void:
	var p := world.local_player
	if p == null or not Data.WEAPONS.has(wid):
		return
	var slot := {"primary": 0, "secondary": 1, "melee": 2}[str(Data.WEAPONS[wid].slot)] as int
	if p.slots[slot] != wid:
		p.give_weapon(slot, wid)
	if p.current_slot != slot:
		p.switch_to(slot)


## Switches the tactical grenade and refills frags and tactical.
func equip_tactical(kind: String) -> void:
	var p := world.local_player
	if p == null or not Data.TACTICALS.has(kind):
		return
	p.info.tactical = kind
	world.refill_equipment(p.id)


func refill_grenades() -> void:
	if world.local_player != null:
		world.refill_equipment(world.local_player.id)


func ready_grapple() -> void:
	if world.local_player != null:
		world.local_player.grapple_cooldown = 0.0


# ================================================================ readout

func reset_readout() -> void:
	readout = {
		"shots": 0, "hits": 0, "heads": 0,
		"last_wid": "", "last_dmg": 0.0, "last_dist": -1.0, "last_head": false, "last_pellets": 0,
		"burst_start": -100.0, "burst_shot": -100.0, "burst_hit": -100.0, "burst_dmg": 0.0, "burst_wid": "", "dps": 0.0,
		"kills": 0,
	}
	_rockets_pending = 0


func on_local_shot(p: Player, wid: String, ends: PackedVector3Array, hits: Dictionary) -> void:
	if not Data.WEAPONS.has(wid):
		return
	var w: Dictionary = Data.WEAPONS[wid]
	var t := World.now()
	var interval := 60.0 / float(w.rpm)
	if wid != str(readout.burst_wid) or t - float(readout.burst_shot) > maxf(BURST_GAP, interval * 2.5):
		readout.burst_start = t
		readout.burst_hit = t
		readout.burst_dmg = 0.0
		readout.burst_wid = wid
	readout.burst_shot = t
	readout.shots += 1
	if wid == "rocket":
		_rockets_pending += 1
		return
	if hits.is_empty():
		return
	readout.hits += 1
	# The target this shot hurt most (a shotgun can hit two dummies).
	var best := 0
	var best_dmg := -1.0
	for tid: int in hits:
		if float(hits[tid][0]) > best_dmg:
			best_dmg = float(hits[tid][0])
			best = tid
	var head: bool = hits[best][1]
	if head:
		readout.heads += 1
	readout.last_wid = wid
	readout.last_dmg = best_dmg
	readout.last_head = head
	readout.last_dist = _hit_distance(p, best, ends)
	readout.last_pellets = _pellets_on(best, ends)


## Eye-to-hit distance (what Player.damage_at used) of the pellet that hit `target` closest to it.
func _hit_distance(p: Player, target_id: int, ends: PackedVector3Array) -> float:
	var target: Player = world.entities.get(target_id)
	var eye := p.head.global_position
	if target == null or ends.is_empty():
		return -1.0
	var centre := target.global_position + Vector3.UP * target.body_center_height()
	var best := ends[0]
	for e: Vector3 in ends:
		if e.distance_to(centre) < best.distance_to(centre):
			best = e
	return eye.distance_to(best)


## Pellets of the last shot that stopped on `target` (shotguns).
func _pellets_on(target_id: int, ends: PackedVector3Array) -> int:
	var target: Player = world.entities.get(target_id)
	if target == null:
		return 0
	var centre := target.global_position + Vector3.UP * target.body_center_height()
	var n := 0
	for e: Vector3 in ends:
		if e.distance_to(centre) < 1.4:
			n += 1
	return n


func on_local_hit(_head: bool, killed: bool, amount: float, pos: Vector3, wid: String) -> void:
	if not Data.WEAPONS.has(wid):
		return
	var t := World.now()
	if wid == "rocket" and _rockets_pending > 0:
		_rockets_pending -= 1
		readout.hits += 1
		readout.last_wid = wid
		readout.last_dmg = amount
		readout.last_head = false
		readout.last_pellets = 1
		var p := world.local_player
		readout.last_dist = p.head.global_position.distance_to(pos - Vector3.UP * 1.0) if p != null else -1.0
	if wid == str(readout.burst_wid):
		readout.burst_dmg = float(readout.burst_dmg) + amount
		readout.burst_hit = t
		var interval := 60.0 / float(Data.WEAPONS[wid].rpm)
		readout.dps = float(readout.burst_dmg) / maxf(float(readout.burst_hit) - float(readout.burst_start) + interval, interval)
	if killed:
		readout.kills += 1


## Hit % of this session (0-100; -1 before the first shot).
func hit_percent() -> float:
	return -1.0 if int(readout.shots) == 0 else 100.0 * float(readout.hits) / float(readout.shots)


## Shots of `w` that kill `hp` at `dist` metres, every pellet landing (body, or all headshots).
## `range_mult` is the shooter's Long Barrel multiplier (Player.mod("barrel")).
static func shots_to_kill(w: Dictionary, dist: float, range_mult := 1.0, head := false, hp := 0.0) -> int:
	if hp <= 0.0:
		hp = Data.MAX_HEALTH
	var per := Player.damage_at(w, dist, range_mult) * float(w.pellets) * (float(w.head_mult) if head else 1.0)
	return ceili(hp / per - 0.0001) if per > 0.0 else 0


## Time from the first to the `shots`-th shot of `w` at its full rate (bursts at their burst rate,
## with the pause between bursts).
static func time_to_kill(w: Dictionary, shots: int) -> float:
	var n := shots - 1
	if n <= 0:
		return 0.0
	var burst := int(w.get("burst", 1))
	if burst > 1:
		return float(n / burst) * burst * 60.0 / float(w.rpm) + float(n % burst) * 60.0 / float(w.burst_rpm)
	return n * 60.0 / float(w.rpm)
