class_name Teams
extends RefCounted
## Shared team rules for every team mode (Team Deathmatch, Infected, Tactical): which modes have
## teams, a player's team (`Player.info.team`, set by the server at spawn: 0 or 1, -1 none), the
## team names, colours (Palette) and shapes, picking a side for a newcomer, and the team look
## (armbands and nametags). Free-for-all modes have no teams: `of()` is -1 for everyone and
## everyone is an enemy.

const NAMES: Array[String] = ["ALPHA", "BRAVO"]
## Palette roles of the two sides' colours (a mode may name its own: Data.MODES[mode].team_colors).
const COLOR_ROLES: Array[String] = ["team_a", "team_b"]
## A shape per side, shown beside team names and player names (kill feed, scoreboard, nametags,
## HUD team labels) so colour is never the only cue.
## (◼ U+25FC: the font's ■ draws as a small dot-sized square.)
const SHAPES: Array[String] = ["▲", "◼"]
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


## The side's colour in the player's colour mode (Palette; Data.MODES[mode].team_colors names the
## roles, else team_a / team_b).
static func color(team: int) -> Color:
	if team < 0 or team > 1:
		return NEUTRAL
	var roles: Array = Data.MODES.get(str(Net.config.get("mode", "ffa")), {}).get("team_colors", COLOR_ROLES)
	return Palette.color(str(roles[team]))


## The side's shape ("" for no team).
static func shape(team: int) -> String:
	return SHAPES[team] if team >= 0 and team < 2 else ""


## The side's name with its shape: "▲ ALPHA".
static func label(team: int) -> String:
	return "%s %s" % [shape(team), name_of(team)] if team >= 0 and team < 2 else name_of(team)


## `text` (a player's name) with their side's shape in front in team modes.
static func tagged(team: int, text: String) -> String:
	return "%s %s" % [shape(team), text] if team >= 0 and team < 2 else text


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
## nametag in that colour with the team's shape; teammates' tags show through walls and from
## further away.
static func decorate(p: Player, my_team: int) -> void:
	var team := of(p)
	if team < 0:
		return
	set_armbands(p, color(team))
	if p.nametag != null:
		p.nametag.fixed_size = false
		_tag(p, team, team == my_team)


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
	# New meshes join the avatar's geometry list so a first-person body (the local player, or the
	# player a spectator follows) keeps them shadow-only instead of floating in front of the camera.
	p.avatar._refresh_geoms()


## The local player's team is only known once its own entity arrives (after others may have),
## and changes when it switches sides; the colour mode can change mid-match. Re-colours, re-tags
## and re-ranges every nametag and re-colours the armbands.
static func refresh_tags(world: World) -> void:
	var mine := of(world.local_player)
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if of(p) < 0:
			continue
		set_armbands(p, color(of(p)))
		if p.nametag != null:
			_tag(p, of(p), of(p) == mine)


## Nametag colour, shape and range. The tag's own text (name, level) is kept as its "base" meta the
## first time, so a later change of side swaps the shape instead of stacking another.
static func _tag(p: Player, team: int, friendly: bool) -> void:
	if not p.nametag.has_meta(&"base"):
		p.nametag.set_meta(&"base", p.nametag.text)
	p.nametag.text = tagged(team, str(p.nametag.get_meta(&"base")))
	p.nametag.modulate = color(team).lightened(0.3)
	p.nametag.no_depth_test = friendly
	p.nametag.visibility_range_end = 60.0 if friendly else 30.0
