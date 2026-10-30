class_name GunGame
extends MatchMode
## Gun Game (`Net.config.mode == "gungame"`), free-for-all on the deathmatch maps. Everyone
## climbs the same weapon ladder (`steps`: guns from FULL_LADDER, then the knife), whose length
## is `Net.config.kill_limit` (2..max_length(); shorter ladders keep the first and last gun and
## spread the rest evenly). Every kill of another player moves the killer to the next step; a
## knife kill (also the quick melee) moves the victim down one step. The first knife kill on the
## last step wins; at the time limit the highest step wins (then kills, then fewest deaths).
## Suicides and falls change nothing.
## Loadouts and loadout mutators are ignored, and there are no frags or tacticals (no kill that
## skips the ladder): a player carries the step's gun in its own slot plus the knife. The step is
## `Player.info.ladder` with the slots built from it (`step_info`), set by the server, sent with
## the entity (late joiners) and changed on every peer by `_s_step`. The server's hit validation
## (`weapon_allowed`) accepts the step's gun, the knife, and for SWAP_GRACE seconds after a
## promotion the gun just replaced (shots and rockets already in flight).

## The guns in ladder order: automatics first, then the long guns and the rocket, then the
## sidearms; the knife always follows as the last step.
const FULL_LADDER: Array[String] = ["smg", "rifle", "burst_rifle", "lmg", "shotgun", "dmr", "sniper", "rocket",
	"machine_pistol", "sawed_off", "burst_pistol", "revolver", "suppressed", "pistol"]
## Ladder lengths offered in match setup (the last is the full ladder).
const LENGTHS: Array[int] = [6, 10, 15]
const SWAP_GRACE := 0.6

## Weapon id per step; the last is "knife" (every peer, from Net.config).
var steps: Array[String] = []

# Server only.
## The player whose knife kill on the last step won (0: none, the clock ran out).
var _winner_id := 0
## Entity id -> [gun replaced by the last promotion, World.now() of it] (SWAP_GRACE).
var _swapped := {}
## Entity id -> knife kills that set someone back a step.
var _demotions := {}


func _init() -> void:
	name = "GunGame"
	steps = ladder(int(Net.config.get("kill_limit", max_length())))


func _ready() -> void:
	var card := GunGameCard.new()
	card.name = "GunGameCard"
	card.setup(self)
	add_child(card)


## Steps in the full ladder: every gun plus the knife.
static func max_length() -> int:
	return FULL_LADDER.size() + 1


## The ladder of `length` steps: evenly spread guns from FULL_LADDER (first and last always
## included), then the knife.
static func ladder(length: int) -> Array[String]:
	var guns := clampi(length, 2, max_length()) - 1
	var out: Array[String] = []
	for i in guns:
		var idx := 0 if guns == 1 else roundi(float(i) * (FULL_LADDER.size() - 1) / float(guns - 1))
		out.append(FULL_LADDER[idx])
	out.append("knife")
	return out


static func step_of(p: Player) -> int:
	return int(p.info.get("ladder", 0)) if p != null else 0


func last_step() -> int:
	return steps.size() - 1


## `info` on `step`: the step's gun in its own slot (the other slot empty; neither on the knife
## step) and no grenades.
func step_info(info: Dictionary, step: int) -> Dictionary:
	var out := info.duplicate()
	step = clampi(step, 0, last_step())
	out.ladder = step
	out.primary = ""
	out.secondary = ""
	out.no_grenades = true
	var wid := steps[step]
	if wid != "knife":
		out[str(Data.WEAPONS[wid].slot)] = wid
	return out


## Weapon slot (0 primary, 1 secondary, 2 knife) of `step`'s weapon.
func slot_of_step(step: int) -> int:
	var wid := steps[clampi(step, 0, last_step())]
	if wid == "knife":
		return 2
	return 0 if str(Data.WEAPONS[wid].slot) == "primary" else 1


func weapon_name(step: int) -> String:
	return str(Data.WEAPONS[steps[clampi(step, 0, last_step())]].name)


# ================================================================ server

func prepare_info(info: Dictionary, _team: int) -> Dictionary:
	return step_info(info, 0)


func weapon_allowed(shooter: Player, wid: String) -> bool:
	if super(shooter, wid):
		return true
	var prev: Array = _swapped.get(shooter.id, [])
	return not prev.is_empty() and str(prev[0]) == wid and World.now() - float(prev[1]) < SWAP_GRACE


func server_on_kill(victim_id: int, killer_id: int, wid: String) -> void:
	if world.match_over or killer_id == victim_id:
		return
	var killer: Player = world.entities.get(killer_id)
	if killer == null:
		return
	var step := step_of(killer)
	var victim: Player = world.entities.get(victim_id)
	if wid == "knife" and victim != null and step_of(victim) > 0:
		_demotions[killer_id] = int(_demotions.get(killer_id, 0)) + 1
		_broadcast(&"_s_step", [victim_id, step_of(victim) - 1, killer_id])
	if step >= last_step():
		if wid == "knife":
			_winner_id = killer_id
			world.server_end_match()
		return
	_swapped[killer_id] = [steps[step], World.now()]
	_broadcast(&"_s_step", [killer_id, step + 1, killer_id])


func server_finish(rows: Array) -> Dictionary:
	annotate_rows(rows)
	sort_rows(rows)
	if _winner_id != 0:
		for i in rows.size():
			if int(rows[i].id) == _winner_id:
				rows.push_front(rows.pop_at(i))
				break
	for i in rows.size():
		var r: Dictionary = rows[i]
		r.won = i == 0
		r.knife_win = i == 0 and int(r.id) == _winner_id
		r.demotions = int(_demotions.get(int(r.id), 0))
	return {}


# ================================================================ every peer

## `eid` moves to `step` (`by`: the killer behind it; `by == eid` a promotion).
@rpc("authority", "call_remote", "reliable")
func _s_step(eid: int, step: int, by: int) -> void:
	var p: Player = world.entities.get(eid)
	if p == null:
		return
	p.apply_info(step_info(p.info, step))
	var up := by == eid
	if up and p.mode != Player.Mode.REMOTE and p.alive:
		# Draw the new gun (Player.switch_to plays the player's draw and blocks firing for it).
		var slot := slot_of_step(step)
		if p.current_slot != slot:
			p.switch_to(slot)
		else:
			p.switch_timer = p.switch_time()
		p.previous_slot = 2 if slot != 2 else p.previous_slot
	if p == world.local_player:
		if not up:
			world.hud.announce("KNIFED!  BACK TO LEVEL %d" % (step + 1))
			Sfx.play(&"hurt", null, -4.0)
		elif step == last_step():
			world.hud.announce("KNIFE LEVEL  ·  A KNIFE KILL WINS")
		else:
			world.hud.announce("LEVEL %d  ·  %s" % [step + 1, weapon_name(step).to_upper()])
		Sfx.play(&"weapon_switch", null, -4.0)
	elif up and step == last_step() and not world.match_over:
		world.hud.announce("%s HAS THE KNIFE" % world.display_name(eid).to_upper())
	world.hud.refresh_scores()


# ================================================================ HUD and results

func annotate_rows(rows: Array) -> void:
	for r: Dictionary in rows:
		if not r.has("ladder"):
			r.ladder = step_of(world.entities.get(int(r.id)))


## Highest step first, then kills, then fewest deaths.
func sort_rows(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.ladder) != int(b.ladder):
			return int(a.ladder) > int(b.ladder)
		return a.kills > b.kills if a.kills != b.kills else a.deaths < b.deaths)


func score_columns() -> Array:
	return ["LEVEL", "KILLS", "DEATHS"]


func row_cells(r: Dictionary) -> Array:
	return ["%d/%d" % [int(r.get("ladder", 0)) + 1, steps.size()], r.kills, r.deaths]


func race_value(r: Dictionary) -> int:
	return int(r.get("ladder", 0)) + 1


func race_limit() -> int:
	return steps.size()


func race_text(value: int) -> String:
	return "level %d" % value


func extra_highlights(rows: Array) -> Array:
	var out: Array = []
	var me := world.my_id()
	if not rows.is_empty() and bool(rows[0].get("knife_win", false)):
		out.append(["Won it with the knife:  %s" % rows[0].name, int(rows[0].id) == me, "knife_finish"])
	var best: Dictionary = {}
	for r: Dictionary in rows:
		if int(r.get("demotions", 0)) > 0 and (best.is_empty() or int(r.demotions) > int(best.demotions)):
			best = r
	if not best.is_empty():
		var n := int(best.demotions)
		out.append(["Most knife setbacks:  %s  (%d)" % [best.name, n], int(best.id) == me, "setbacks"])
	return out


# ================================================================ bots

## On the knife step a bot hunts the nearest player instead of roaming.
func bot_roam_goal(p: Player) -> Variant:
	if step_of(p) < last_step():
		return null
	var best: Player = null
	var best_d := INF
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if o != p and o.alive:
			var d := p.global_position.distance_squared_to(o.global_position)
			if d < best_d:
				best_d = d
				best = o
	return best.global_position if best != null else null
