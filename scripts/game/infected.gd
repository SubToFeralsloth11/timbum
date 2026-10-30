class_name Infected
extends MatchMode
## Infected (`Net.config.mode == "infected"`): everyone starts a Survivor (team 0) with their own
## loadout. START_DELAY seconds in, one random living player turns Infected (team 1): knife
## only, no grenades, MAX_HP health, SPEED times faster and tinted green. A Survivor who dies
## for any reason turns Infected on the spot and respawns as one; the Infected respawn as usual.
## The Infected win as soon as nobody survives; the Survivors win if any survive the clock.
## Humans (and bots) joining once the infection has started join the Infected. Loadout mutators
## are off (Net.sanitize_config / Net._roll_match_variety). The role is `Player.info.team` plus
## the stat fields `infect_info` adds, sent with the entity (late joiners) and by `_s_role`.

const SURVIVORS := 0
const INFECTED := 1
const START_DELAY := 10.0
const MAX_HP := 150.0
const SPEED := 1.15
## Survivor bots back off from an Infected closer than this.
const KEEP_AWAY := 9.0

## Whether the first player has turned (every peer).
var started := false

# Server only.
## Entity id -> survivors this player infected (kills while Infected).
var _infections := {}


func _init() -> void:
	name = "Infected"


## The Infected version of a player's info: on team 1, knife only, more health, faster.
static func infect_info(info: Dictionary) -> Dictionary:
	var out := info.duplicate()
	out.team = INFECTED
	out.primary = ""
	out.secondary = ""
	out.knife_only = true
	out.max_hp = MAX_HP
	out.speed = SPEED
	return out


static func is_infected(p: Player) -> bool:
	return Teams.of(p) == INFECTED


## Seconds until the first player turns (0 once started), from the synced match clock.
func start_left() -> float:
	if started:
		return 0.0
	return maxf(0.0, world.time_left - (float(Net.config.time_limit) - START_DELAY))


# ================================================================ server

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or started or world.match_over:
		return
	if float(Net.config.time_limit) - world.time_left >= START_DELAY:
		_server_infect_random(true)


## Turns a random living Survivor Infected (the first one, or a new one when every Infected left).
func _server_infect_random(first: bool) -> void:
	var pool: Array[int] = []
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if p.alive and not is_infected(p):
			pool.append(eid)
	if pool.size() < 2:
		return
	var eid: int = pool.pick_random()
	_broadcast(&"_s_role", [eid, INFECTED, first])
	world.server_set_health(eid, MAX_HP)


func server_team_for(_is_bot: bool) -> int:
	return INFECTED if started else SURVIVORS


func prepare_info(info: Dictionary, team: int) -> Dictionary:
	return infect_info(info) if team == INFECTED else super(info, team)


## A Survivor (before the infection starts, a Survivor who dies respawns as one) keeps a loadout.
func uses_loadout(p: Player) -> bool:
	return not is_infected(p)


## A human joining an Infected-heavy match pushes an Infected bot out first; never the last
## Survivor or the last Infected.
func bot_drop_team() -> int:
	var c := Teams.counts(world)
	if c[INFECTED] > 1:
		return INFECTED
	return SURVIVORS if c[SURVIVORS] > 1 else -1


func server_sync(pid: int) -> void:
	_s_started.rpc_id(pid, started)


func server_human_left(pid: int) -> void:
	super(pid)
	_server_check_end()


func server_on_kill(victim_id: int, killer_id: int, _wid: String) -> void:
	var victim: Player = world.entities.get(victim_id)
	if victim == null or is_infected(victim) or not started:
		return
	if killer_id != victim_id and is_infected(world.entities.get(killer_id)):
		_infections[killer_id] = int(_infections.get(killer_id, 0)) + 1
	_broadcast(&"_s_role", [victim_id, INFECTED, false])
	_server_check_end()


## Nobody left to infect ends it; no Infected left (they all quit) turns a new one.
func _server_check_end() -> void:
	if not started or world.match_over:
		return
	var c := Teams.counts(world)
	if c[SURVIVORS] == 0:
		world.server_end_match()
	elif c[INFECTED] == 0:
		_server_infect_random(false)


func server_winner() -> int:
	return INFECTED if started and Teams.counts(world)[SURVIVORS] == 0 else SURVIVORS


func server_finish(rows: Array) -> Dictionary:
	annotate_rows(rows)
	var winner := server_winner()
	for r: Dictionary in rows:
		r.won = int(r.team) == winner
		r.infections = int(_infections.get(int(r.id), 0))
	# The winning side first, then by kills.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.team != b.team:
			return a.team == winner
		return a.kills > b.kills if a.kills != b.kills else a.deaths < b.deaths)
	return {"winner": winner}


# ================================================================ every peer

@rpc("authority", "call_remote", "reliable")
func _s_started(on: bool) -> void:
	started = on


## `eid` takes `role`; `first` marks the infection's start (everyone is told who turned).
@rpc("authority", "call_remote", "reliable")
func _s_role(eid: int, role: int, first: bool) -> void:
	if first:
		started = true
	var p: Player = world.entities.get(eid)
	if p == null:
		return
	p.apply_info(prepare_info(p.info, role))
	_apply_look(p)
	Teams.refresh_tags(world)
	if p == world.local_player:
		world.hud.announce("YOU ARE INFECTED" if role == INFECTED else "YOU SURVIVE")
		Sfx.play(&"flashbang" if first else &"hurt", null, -8.0)
	elif first:
		world.hud.announce("%s IS INFECTED!" % world.display_name(eid).to_upper())
	world.hud.refresh_scores()


func on_player_added(p: Player) -> void:
	super(p)
	_apply_look(p)


## Green tint and armbands for the Infected, the survivor colour otherwise.
func _apply_look(p: Player) -> void:
	p.avatar.set_tint(Models.infected_overlay_material() if is_infected(p) else null)
	Teams.set_armbands(p, Teams.color(Teams.of(p)))


# ================================================================ HUD and results

func hud_bars() -> Array:
	var c := Teams.counts(world)
	var total := maxf(1.0, float(c[0] + c[1]))
	return [[c[SURVIVORS] / total, str(c[SURVIVORS])], [c[INFECTED] / total, str(c[INFECTED])]]


func hud_goal() -> String:
	if not started:
		return "Infection in %d  ·  get away from everyone" % ceili(start_left())
	if is_infected(world.local_player):
		return "You are INFECTED  ·  knife every survivor"
	return "You are a SURVIVOR  ·  stay alive until the clock runs out"


func hud_rank() -> String:
	var n := Teams.counts(world)[SURVIVORS]
	return "%d survivor%s left" % [n, "" if n == 1 else "s"] if started else ""


func row_tag(r: Dictionary) -> String:
	return "INFECTED" if int(r.get("team", -1)) == INFECTED else "SURVIVOR"


func group_header(team: int, rows: Array) -> String:
	var n := 0
	for r: Dictionary in rows:
		if int(r.get("team", -1)) == team:
			n += 1
	return "%s  ·  %d" % [Teams.label(team), n]


func results_title(rows: Array, next: Dictionary) -> Array:
	var winner := int(next.get("winner", SURVIVORS))
	var text := "THE SURVIVORS HOLD OUT" if winner == SURVIVORS else "THE INFECTED TAKE OVER"
	var mine := _my_row(rows)
	if not mine.is_empty():
		text = ("VICTORY!  " if bool(mine.get("won", false)) else "DEFEAT  ·  ") + text
	return [text, Teams.color(winner)]


func win_banner(next: Dictionary) -> String:
	return "SURVIVORS WIN!" if int(next.get("winner", SURVIVORS)) == SURVIVORS else "INFECTED WIN!"


## Who survived to the end, and who infected the most.
func extra_highlights(rows: Array) -> Array:
	var out: Array = []
	var me := world.my_id()
	var survivors: Array[String] = []
	var mine := false
	for r: Dictionary in rows:
		if int(r.get("team", -1)) == SURVIVORS:
			survivors.append(str(r.name))
			mine = mine or int(r.id) == me
	if not survivors.is_empty():
		out.append(["Survived:  %s" % ", ".join(survivors), mine, "survived"])
	var best: Dictionary = {}
	for r: Dictionary in rows:
		if int(r.get("infections", 0)) > 0 and (best.is_empty() or int(r.infections) > int(best.infections)):
			best = r
	if not best.is_empty():
		var n := int(best.infections)
		out.append(["Most infections:  %s  (%d survivor%s)" % [best.name, n, "" if n == 1 else "s"], int(best.id) == me, "top_infector"])
	return out


## Fewest deaths ("Survivor") would clash with the real survivors.
func hides_award(stat: String) -> bool:
	return stat == "deaths"


# ================================================================ bots

## The Infected always know where the nearest Survivor is and rush them.
func bot_roam_goal(p: Player) -> Variant:
	if not is_infected(p):
		return null
	var best: Player = null
	var best_d := INF
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if o.alive and not is_infected(o):
			var d := p.global_position.distance_squared_to(o.global_position)
			if d < best_d:
				best_d = d
				best = o
	if best == null:
		return null
	return best.global_position


## Survivors fight the Infected at range and back away when one closes in.
func bot_min_range(p: Player, target: Player) -> float:
	return KEEP_AWAY if not is_infected(p) and is_infected(target) else 0.0
