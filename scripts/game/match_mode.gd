class_name MatchMode
extends Node
## The rules of this match's mode (`Net.config.mode`). World always has exactly one, as its child
## (`World.rules`), created by `MatchMode.create()` on every peer, and asks it everything that
## differs between modes: teams, spawns, respawns, what a kill does, when the match ends and who
## won, the HUD's score line, scoreboard rows and results, and bot goals. This base class is
## plain free-for-all Deathmatch; each other mode is a subclass with its own node name (so its
## RPCs reach the same node on every peer):
##   - `TeamDeathmatch` (scripts/game/team_deathmatch.gd, "tdm")
##   - `GunGame` (scripts/game/gun_game.gd, "gungame")
##   - `KingOfTheBlock` (scripts/game/king_of_the_block.gd, "koth")
##   - `Infected` (scripts/game/infected.gd, "infected")
##   - `Tactical` (scripts/game/tactical.gd, "tactical")
## Team rules every team mode shares (teams on `Player.info.team`, names, colours, picking a side,
## armbands and nametags) live in `Teams`.
## Naming as in World: `server_*` runs on the server only, `_s_*` RPCs go server -> peers.

var world: World


func _init() -> void:
	name = "Deathmatch"


## The controller for `Net.config.mode` (plain Deathmatch for "ffa" and anything unknown).
static func create(p_world: World) -> MatchMode:
	var m: MatchMode
	match str(Net.config.get("mode", "ffa")):
		"tdm": m = TeamDeathmatch.new()
		"gungame": m = GunGame.new()
		"koth": m = KingOfTheBlock.new()
		"infected": m = Infected.new()
		"tactical": m = Tactical.new()
		_: m = MatchMode.new()
	m.world = p_world
	return m


## Sends an RPC of this node to every peer that has loaded the world, then runs it here too.
func _broadcast(method: StringName, args: Array) -> void:
	for pid: int in world.ready_peer_ids():
		callv(&"rpc_id", [pid, method] + args)
	callv(method, args)


# ================================================================ match flow (every peer)

## Whether the match clock counts down now (Tactical holds it during planning).
func clock_running() -> bool:
	return true


## True while nobody may shoot, knife or throw (Tactical's planning phase).
func attacks_blocked() -> bool:
	return false


## Seconds from death to respawn; negative: no respawns.
func respawn_delay() -> float:
	return Data.RESPAWN_TIME


## The match ended (every peer, from World._s_match_end).
func on_match_over() -> void:
	pass


## A player entity was created on this peer: team look (armbands, nametags) in team modes.
func on_player_added(p: Player) -> void:
	if Teams.of(p) < 0:
		return
	Teams.decorate(p, Teams.of(world.local_player))
	if p == world.local_player:
		Teams.refresh_tags(world)


## The local player was killed by `killer_id`.
func on_local_death(_killer_id: int) -> void:
	pass


## Living players a spectator, or the dead local player in a mode without respawns, may follow
## (Spectator), ordered by entity id. Base: everyone alive but the local player.
func spectate_candidates() -> Array[Player]:
	var out: Array[Player] = []
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if p.alive and p != world.local_player:
			out.append(p)
	out.sort_custom(func(a: Player, b: Player) -> bool: return a.id < b.id)
	return out


# ================================================================ server hooks

## Team for a player joining now (-1 in free-for-all).
func server_team_for(is_bot: bool) -> int:
	return Teams.pick(world, is_bot) if Teams.is_team_mode() else -1


## The info a player spawns with on `team` (the server sends it to every peer).
func prepare_info(info: Dictionary, team: int) -> Dictionary:
	if team < 0:
		return info
	var out := info.duplicate()
	out.team = team
	return out


## [feet position, yaw] for `eid` (on `team`) spawning or respawning now.
func spawn_point(eid: int, team: int) -> Array:
	return world.pick_spawn(eid, team)


## Whether a (re)spawn starts World.SPAWN_PROTECTION.
func spawn_protection() -> bool:
	return true


## Keeps the bots at the player count (World.server_balance_bots).
func server_balance() -> void:
	world.server_balance_bots()


## Team a bot should leave from when one has to go (-1: any): the bigger team in team modes.
func bot_drop_team() -> int:
	if not Teams.is_team_mode():
		return -1
	var c := Teams.counts(world)
	return -1 if c[0] == c[1] else (0 if c[0] > c[1] else 1)


## A peer finished loading the match (players and spectators): the mode's state so far (scores,
## zone, phase). Runs before server_human_joined.
func server_sync(_pid: int) -> void:
	pass


## A human finished loading the match, or a spectator started playing.
func server_human_joined(pid: int) -> void:
	world.server_add_human(pid, server_team_for(false), true)


## A human left mid-match, or started spectating.
func server_human_left(pid: int) -> void:
	world.server_remove_entity(pid)


## After World counted a kill (scores already updated and broadcast).
func server_on_kill(_victim_id: int, killer_id: int, _wid: String) -> void:
	var s: Dictionary = world.scores.get(killer_id, {})
	if not s.is_empty() and int(s.kills) >= int(Net.config.kill_limit):
		world.server_end_match()


## Final rows (World._server_end_match: {id, name, kills, deaths, headshots, best_streak, bot,
## level}): annotates and orders them, best first. Returns what the results need besides the
## next match (team modes: {winner}); rows of team modes carry `team`, `alive` and `won`.
func server_finish(rows: Array) -> Dictionary:
	sort_rows(rows)
	return {}


## Whether the results screen leads into a next match on a timer (Tactical: NEW GAME instead).
func has_next_match() -> bool:
	return true


## Whether the server accepts a hit or rocket from `shooter` with `wid`: the knife, or a gun in
## the shooter's current slots (Gun Game also takes the gun just replaced, for shots in flight).
func weapon_allowed(shooter: Player, wid: String) -> bool:
	return wid == "knife" or shooter.slots.has(wid)


# ================================================================ HUD, scoreboard, results

## Adds what this mode's scoreboard shows to rows built from World.scores: `team` and `alive`
## in team modes.
func annotate_rows(rows: Array) -> void:
	if not Teams.is_team_mode():
		return
	for r: Dictionary in rows:
		var p: Player = world.entities.get(int(r.id))
		if not r.has("team"):
			r.team = Teams.of(p)
		if not r.has("alive"):
			r.alive = p != null and p.alive


## Scoreboard order: by kills (fewer deaths first); team modes group by team first.
func sort_rows(rows: Array) -> void:
	var teams := Teams.is_team_mode()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if teams and int(a.get("team", -1)) != int(b.get("team", -1)):
			return int(a.get("team", -1)) < int(b.get("team", -1))
		return a.kills > b.kills if a.kills != b.kills else a.deaths < b.deaths)



## Headers of the scoreboard's three stat columns (after # and PLAYER).
func score_columns() -> Array:
	return ["KILLS", "DEATHS", "HS"]


## A row's values for `score_columns()`.
func row_cells(r: Dictionary) -> Array:
	return [r.kills, r.deaths, r.headshots]


## Free-for-all race in the HUD's top panel: what a row has toward the limit (kills; Gun Game:
## ladder level; King of the Block: points), the limit, and how the value reads.
func race_value(r: Dictionary) -> int:
	return int(r.kills)


func race_limit() -> int:
	return int(Net.config.kill_limit)


func race_text(value: int) -> String:
	return "%d kill%s" % [value, "" if value == 1 else "s"]


## Extra word after a name on the scoreboard ("KIA", a role).
func row_tag(_r: Dictionary) -> String:
	return ""


## Whether a scoreboard row is drawn dimmed (Tactical: the fallen).
func row_dimmed(_r: Dictionary) -> bool:
	return false


## Scoreboard line above `team`'s rows (team modes).
func group_header(team: int, rows: Array) -> String:
	var kills := 0
	var n := 0
	for r: Dictionary in rows:
		if int(r.get("team", -1)) == team:
			kills += int(r.kills)
			n += 1
	return "%s  ·  %d player%s  ·  %d kills" % [Teams.label(team), n, "" if n == 1 else "s", kills]


## Two bars in the HUD's top panel instead of the free-for-all kill race: [[fraction, text], x2]
## (empty: the kill race).
func hud_bars() -> Array:
	return []


## The HUD's goal line ("": the free-for-all leader line).
func hud_goal() -> String:
	return ""


## The HUD's line under the goal ("": the free-for-all rank line).
func hud_rank() -> String:
	return ""


## Compass pips [[heading degrees, Color], ...] seen from `cam` (Tactical's team markers, King of
## the Block's zone).
func compass_pips(_cam: Camera3D) -> Array:
	return []


## Results title [text, colour] for `next` from the server ("" text: the placement title).
func results_title(rows: Array, next: Dictionary) -> Array:
	if not next.has("winner"):
		return ["", Color.WHITE]
	var winner := int(next.winner)
	var mine := _my_row(rows)
	if winner < 0:
		return ["DRAW", Teams.NEUTRAL]
	var who := "%s WINS" % Teams.label(winner)
	if mine.is_empty() or int(mine.get("team", -1)) < 0:
		return [who, Teams.color(winner)]
	return ["VICTORY!  " + who if bool(mine.get("won", false)) else "DEFEAT  ·  " + who, Teams.color(winner)]


## The end-of-match banner over the winner's emote (team modes: the winning side).
func win_banner(next: Dictionary) -> String:
	var winner := int(next.get("winner", -1))
	return "%s WINS!" % Teams.label(winner) if winner >= 0 else ""


## The results screen's match highlights, which are also the medals (Data.MEDALS):
## [[text, is this player, medal id], ...]. Best streak, most headshots and fewest deaths of the
## match (ties go to the higher finisher), then the mode's extra_highlights.
func highlights(rows: Array) -> Array:
	var out: Array = []
	if rows.is_empty():
		return out
	# [medal, stat, higher is better, minimum to award, unit (singular), unit (plural)]
	var awards := [
		["best_streak", "best_streak", true, 2, "in a row", "in a row"],
		["sharpshooter", "headshots", true, 1, "headshot", "headshots"],
		["survivor", "deaths", false, 0, "death", "deaths"],
	]
	for a: Array in awards:
		if hides_award(str(a[1])):
			continue
		var best: Dictionary = {}
		for r: Dictionary in rows:
			# Fewest deaths only counts for someone who actually fought.
			if not a[2] and int(r.kills) == 0:
				continue
			var v := int(r.get(a[1], 0))
			if best.is_empty() or (v > int(best[a[1]]) if a[2] else v < int(best[a[1]])):
				best = r
		if best.is_empty() or (a[2] and int(best[a[1]]) < int(a[3])):
			continue
		var value := int(best[a[1]])
		var amount := "%d %s" % [value, a[4] if value == 1 else a[5]]
		out.append(["%s:  %s  (%s)" % [Data.MEDALS[a[0]].name, best.name, amount], int(best.id) == world.my_id(), a[0]])
	out.append_array(extra_highlights(rows))
	return out


## The mode's own highlights: [[text, is this player, medal id], ...].
func extra_highlights(_rows: Array) -> Array:
	return []


## Whether the results skip a standard highlight (stat "best_streak", "headshots", "deaths").
func hides_award(_stat: String) -> bool:
	return false


func _my_row(rows: Array) -> Dictionary:
	for r: Dictionary in rows:
		if int(r.id) == world.my_id():
			return r
	return {}


# ================================================================ bots

## Where a bot with no target should head (null: free roaming).
func bot_roam_goal(_p: Player) -> Variant:
	return null


## Closest a bot lets `target` come before backing off (0: its weapon's range decides).
func bot_min_range(_p: Player, _target: Player) -> float:
	return 0.0


## An area a bot should stay in and fight from, [centre, radius] (King of the Block's zone), or
## [] to roam and chase freely.
func bot_hold_area(_p: Player) -> Array:
	return []
