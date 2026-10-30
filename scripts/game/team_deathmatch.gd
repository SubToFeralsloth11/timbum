class_name TeamDeathmatch
extends MatchMode
## Team Deathmatch (`Net.config.mode == "tdm"`): two teams (Teams: ALPHA / BRAVO) on the
## deathmatch maps with respawns. Every kill of an enemy scores a point for the killer's team;
## the first team to `Net.config.kill_limit` (default DEFAULT_KILL_LIMIT) wins, or the higher
## score when time runs out (equal: a draw). Friendly fire is off (World._server_damage), humans
## are split evenly and bots fill both teams evenly (Teams.pick, MatchMode.bot_drop_team).
## Spawns prefer the team's own half of the map and teammates, away from enemies.
## The team score is kept here (a leaver's kills stay counted) and sent with `_s_score`.

const DEFAULT_KILL_LIMIT := 50
## Spawn ranking: metres of distance to the nearest enemy that count (further is no better), and
## the bonuses for the team's own half of the map and for a teammate within MATE_RANGE.
const ENEMY_CAP := 45.0
const OWN_SIDE_BONUS := 10.0
const MATE_BONUS := 8.0
const MATE_RANGE := 20.0

## Kills per team [ALPHA, BRAVO]; the server's values on every peer.
var score: Array[int] = [0, 0]
## Team that last led outright (-1 none yet), for the lead-change callout.
var _leader := -1


func _init() -> void:
	name = "TeamDeathmatch"


# ================================================================ server

func spawn_point(eid: int, team: int) -> Array:
	var space := world.get_world_3d().direct_space_state
	var centre := world.map_info.bounds.get_center()
	var size := world.map_info.bounds.size
	var ranked: Array = []
	for s: Vector3 in world.map_info.spawns:
		var enemy := INF
		var mate := INF
		var seen := false
		for id: int in world.entities:
			var p: Player = world.entities[id]
			if id == eid or not p.alive:
				continue
			var d := s.distance_to(p.global_position)
			if Teams.of(p) == team:
				mate = minf(mate, d)
				continue
			enemy = minf(enemy, d)
			if not seen and d < 70.0:
				var q := PhysicsRayQueryParameters3D.create(s + Vector3.UP * 1.6, p.global_position + Vector3.UP * 1.6, Player.MASK_WORLD)
				seen = space.intersect_ray(q).is_empty()
		# ALPHA's half is the low end of the map's longer axis, BRAVO's the high end.
		var along := (s.x - centre.x) if size.x >= size.z else (s.z - centre.z)
		var score_s := minf(enemy, ENEMY_CAP)
		if (along < 0.0) == (team == 0):
			score_s += OWN_SIDE_BONUS
		if mate < MATE_RANGE:
			score_s += MATE_BONUS
		# Never where an enemy can see it or right on top of one, nor inside a teammate.
		if seen:
			score_s -= 1000.0
		if enemy < 8.0 or mate < 1.5:
			score_s -= 500.0
		ranked.append([score_s, s])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	# Vary among the best three while they are nearly as good as the best.
	var pool := 1
	while pool < mini(3, ranked.size()) and float(ranked[pool][0]) > float(ranked[0][0]) - 6.0:
		pool += 1
	var pick: Vector3 = ranked[randi() % pool][1]
	var to_center := centre - pick
	return [pick, atan2(-to_center.x, -to_center.z)]


func server_sync(pid: int) -> void:
	_s_score.rpc_id(pid, score[0], score[1])


func server_on_kill(victim_id: int, killer_id: int, _wid: String) -> void:
	var kt := Teams.of(world.entities.get(killer_id))
	if killer_id == victim_id or kt < 0 or kt == Teams.of(world.entities.get(victim_id)):
		return
	score[kt] += 1
	_broadcast(&"_s_score", [score[0], score[1]])
	if score[kt] >= int(Net.config.kill_limit):
		world.server_end_match()


## 0 / 1, or -1 for a draw.
func server_winner() -> int:
	if score[0] == score[1]:
		return -1
	return 0 if score[0] > score[1] else 1


func server_finish(rows: Array) -> Dictionary:
	annotate_rows(rows)
	var winner := server_winner()
	for r: Dictionary in rows:
		r.won = winner >= 0 and int(r.team) == winner
	# The winning team first (ALPHA first on a draw), then by kills.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.team != b.team:
			return a.team == winner or (winner < 0 and a.team < b.team)
		return a.kills > b.kills if a.kills != b.kills else a.deaths < b.deaths)
	return {"winner": winner, "score": [score[0], score[1]]}


@rpc("authority", "call_remote", "reliable")
func _s_score(alpha: int, bravo: int) -> void:
	score = [alpha, bravo]
	var lead := -1 if alpha == bravo else (0 if alpha > bravo else 1)
	var mine := Teams.of(world.local_player)
	if lead >= 0 and lead != _leader and not world.match_over and mine >= 0:
		world.hud.announce("YOUR TEAM TAKES THE LEAD" if lead == mine else "%s TAKES THE LEAD" % Teams.label(lead))
	if lead >= 0:
		_leader = lead
	world.hud.refresh_scores()


# ================================================================ HUD and results

func hud_bars() -> Array:
	var limit := maxf(1.0, float(Net.config.kill_limit))
	return [[score[0] / limit, str(score[0])], [score[1] / limit, str(score[1])]]


func hud_goal() -> String:
	var mine := Teams.of(world.local_player)
	var goal := "First team to %d kills" % int(Net.config.kill_limit)
	return goal if mine < 0 else "Your team: %s  ·  %s" % [Teams.label(mine), goal.to_lower()]


func hud_rank() -> String:
	if score[0] == score[1]:
		return "Tied %d - %d" % [score[0], score[1]]
	var lead := 0 if score[0] > score[1] else 1
	return "%s leads by %d" % [Teams.label(lead), absi(score[0] - score[1])]


func group_header(team: int, rows: Array) -> String:
	var n := 0
	for r: Dictionary in rows:
		if int(r.get("team", -1)) == team:
			n += 1
	return "%s  ·  %d  ·  %d player%s" % [Teams.label(team), score[team], n, "" if n == 1 else "s"]


func results_title(rows: Array, next: Dictionary) -> Array:
	var out := super(rows, next)
	var s: Array = next.get("score", score)
	out[0] = "%s   %d - %d" % [out[0], int(s[0]), int(s[1])]
	return out


## Each team's top scorer.
func extra_highlights(rows: Array) -> Array:
	var out: Array = []
	for team in 2:
		var best: Dictionary = {}
		for r: Dictionary in rows:
			if int(r.get("team", -1)) == team and (best.is_empty() or int(r.kills) > int(best.kills)):
				best = r
		if not best.is_empty() and int(best.kills) > 0:
			out.append(["Top of %s:  %s  (%d kills)" % [Teams.label(team), best.name, int(best.kills)], int(best.id) == world.my_id(), "team_top"])
	return out
