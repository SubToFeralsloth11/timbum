class_name Teams
extends RefCounted
## Shared team rules for every team mode (Team Deathmatch, Infected, Tactical): which modes have
## teams, a player's team (`Player.info.team`, set by the server at spawn: 0 or 1, -1 none), the
## team names and colours, picking a side for a newcomer, and the team look (armbands and
## nametags). Free-for-all modes have no teams: `of()` is -1 for everyone and everyone is an enemy.

const NAMES: Array[String] = ["ALPHA", "BRAVO"]
const COLORS: Array[Color] = [Color(0.3, 0.62, 1.0), Color(1.0, 0.45, 0.22)]
const NEUTRAL := Color(0.85, 0.85, 0.85)


## Whether `mode` (default: this match's `Net.config.mode`) is played in two teams
## (`Data.MODES[mode].teams`). Team-only features (pings, team radar) ask this.
static func is_team_mode(mode := "") -> bool:
	if mode.is_empty():
		mode = str(Net.config.get("mode", "ffa"))
	return bool(Data.MODES.get(mode, {}).get("teams", false))


## The player's team (0 / 1), or -1 (free-for-all, or no player).
static func of(p: Player) -> int:
	return int(p.info.get("team", -1)) if p != null else -1


## Both on the same team (never true in free-for-all).
static func same(a: Player, b: Player) -> bool:
	var ta := of(a)
	return ta >= 0 and ta == of(b)


## The mode's names for its sides (`Data.MODES[mode].team_names`, else ALPHA / BRAVO).
static func name_of(team: int) -> String:
	var names: Array = Data.MODES.get(str(Net.config.get("mode", "ffa")), {}).get("team_names", NAMES)
	return str(names[team]) if team >= 0 and team < 2 else "-"


static func color(team: int) -> Color:
	var colors: Array = Data.MODES.get(str(Net.config.get("mode", "ffa")), {}).get("team_colors", COLORS)
	return colors[team] if team >= 0 and team < 2 else NEUTRAL


## [team 0, team 1] counts of `world`'s players: all of them, or only the living.
static func counts(world: World, alive_only := false) -> Array[int]:
	var out: Array[int] = [0, 0]
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		var t := of(p)
		if t >= 0 and (p.alive or not alive_only):
			out[t] += 1
	return out


## Team for a newcomer: a human joins the side with fewer humans, then the side with fewer
## players; a bot joins the side with fewer players (ties: team 0, or random for a human).
static func pick(world: World, is_bot: bool) -> int:
	var humans: Array[int] = [0, 0]
	var total: Array[int] = [0, 0]
	for eid: int in world.entities:
		var t := of(world.entities[eid])
		if t < 0:
			continue
		total[t] += 1
		if eid > 0:
			humans[t] += 1
	if not is_bot and humans[0] != humans[1]:
		return 0 if humans[0] < humans[1] else 1
	if total[0] != total[1]:
		return 0 if total[0] < total[1] else 1
	return randi() % 2 if not is_bot else 0


## Team look on a newly spawned player (every peer): glowing armbands in the team colour, and a
## nametag in that colour; teammates' tags show through walls and from further away.
static func decorate(p: Player, my_team: int) -> void:
	var team := of(p)
	if team < 0:
		return
	set_armbands(p, color(team))
	if p.nametag != null:
		p.nametag.modulate = color(team).lightened(0.3)
		p.nametag.fixed_size = false
		_tag_range(p, team == my_team)


## Replaces `p`'s armbands with `col` (a player whose team changes, e.g. a new Infected).
static func set_armbands(p: Player, col: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.6
	var band := BoxMesh.new()
	band.size = Vector3(0.27, 0.09, 0.27)
	band.material = mat
	for arm: String in ["ArmL", "ArmR"]:
		var mount := p.avatar.find_child(arm, true, false) as Node3D
		if mount == null:
			continue
		var mi := mount.get_node_or_null("Armband") as MeshInstance3D
		if mi == null:
			mi = MeshInstance3D.new()
			mi.name = "Armband"
			mi.position = Vector3(0.0, -0.12, 0.0)
			mount.add_child(mi)
		mi.mesh = band


## The local player's team is only known once its own entity arrives (after others may have),
## and changes when it switches sides: re-colours and re-ranges every nametag.
static func refresh_tags(world: World) -> void:
	var mine := of(world.local_player)
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if p.nametag != null and of(p) >= 0:
			p.nametag.modulate = color(of(p)).lightened(0.3)
			_tag_range(p, of(p) == mine)


static func _tag_range(p: Player, friendly: bool) -> void:
	p.nametag.no_depth_test = friendly
	p.nametag.visibility_range_end = 60.0 if friendly else 30.0
