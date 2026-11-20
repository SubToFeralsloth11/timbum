class_name MatchScore
extends RefCounted
## MATCH SCORE: one number per player for the results screen, with an itemised breakdown. The
## server works it out once in World._server_end_match (score_rows) and sends it inside the final
## rows (`score`, `score_parts`, `time`), so every peer shows the same numbers. No top cap; the
## total never goes below 0.
##
## Parts (only the non-zero ones are listed):
## - Kills KILL each, headshots HEADSHOT each, deaths DEATH each (negative).
## - Placement: team modes WIN for the winning side, DRAW on a draw; free-for-all modes by rank,
##   PLACE_TOP for first sliding down to 0 for last, plus FIRST_EXTRA for the winner.
## - Time: TIME_PER_MINUTE for each minute the player was in the match (`time`, seconds).
## - Objective: Bedwars BED per bed broken (`beds`); Capture the Flag CAPTURE per capture and RETURN
##   per flag return; modes with `points` (King of the Block, Block Hunt) POINT per point; other
##   modes whose race isn't kills (Gun Game's ladder, One in the Chamber's lives, Parkour's
##   checkpoints, Tag's points) RACE_FULL scaled by race value / race limit.

const KILL := 100
const HEADSHOT := 25
const DEATH := -40
const WIN := 400
const DRAW := 150
const PLACE_TOP := 400
const FIRST_EXTRA := 200
const TIME_PER_MINUTE := 20
const CAPTURE := 300
const RETURN := 100
const POINT := 5
const BED := 500
const RACE_FULL := 1000


## Fills `score`, `score_parts` ([[label, points], ...]) on every row. `rows` are the final rows,
## best first (MatchMode.server_finish), each with `time` (seconds in the match); `draw` a team
## result nobody won.
static func score_rows(rows: Array, rules: MatchMode, teams: bool, draw: bool) -> void:
	var n := rows.size()
	for i in n:
		var r: Dictionary = rows[i]
		var parts := breakdown(r, rules, teams, draw, i + 1, n)
		var total := 0
		for p: Array in parts:
			total += int(p[1])
		r.score = maxi(0, total)
		r.score_parts = parts


## The parts of one row at `rank` (1-based) of `players`.
static func breakdown(r: Dictionary, rules: MatchMode, teams: bool, draw: bool, rank: int, players: int) -> Array:
	var parts: Array = []
	var kills := int(r.get("kills", 0))
	var heads := int(r.get("headshots", 0))
	var deaths := int(r.get("deaths", 0))
	_add(parts, "Kills  %d × %d" % [kills, KILL], kills * KILL)
	_add(parts, "Headshots  %d × %d" % [heads, HEADSHOT], heads * HEADSHOT)
	_add(parts, "Deaths  %d × %d" % [deaths, DEATH], deaths * DEATH)
	var obj := objective(r, rules)
	_add(parts, str(obj[0]), int(obj[1]))
	if teams:
		if bool(r.get("won", false)):
			_add(parts, "Team victory", WIN)
		elif draw:
			_add(parts, "Draw", DRAW)
	elif players > 1:
		var place := roundi(float(PLACE_TOP) * (players - rank) / (players - 1))
		if rank == 1:
			place += FIRST_EXTRA
		_add(parts, "Placement  #%d of %d" % [rank, players], place)
	var secs := maxi(0, int(r.get("time", 0)))
	_add(parts, "Time played  %s" % clock_text(secs), secs * TIME_PER_MINUTE / 60)
	return parts


## [label, points] for the mode's objective ("", 0 when the mode is a plain kill race).
static func objective(r: Dictionary, rules: MatchMode) -> Array:
	if r.has("beds"):
		var beds := int(r.get("beds", 0))
		return ["Objective  %d bed%s broken" % [beds, "" if beds == 1 else "s"], beds * BED]
	if r.has("captures") or r.has("returns"):
		var caps := int(r.get("captures", 0))
		var rets := int(r.get("returns", 0))
		return ["Objective  %d cap%s, %d return%s" % [caps, "" if caps == 1 else "s", rets, "" if rets == 1 else "s"],
			caps * CAPTURE + rets * RETURN]
	if r.has("points"):
		var pts := int(r.get("points", 0))
		return ["Objective  %d point%s" % [pts, "" if pts == 1 else "s"], pts * POINT]
	# A race that isn't kills names its unit differently ("level 1", "1 life", "checkpoint 1").
	if rules.race_text(1) != "1 kill":
		var v := rules.race_value(r)
		return ["Objective  %s" % rules.race_text(v), roundi(float(RACE_FULL) * maxi(0, v) / maxf(1.0, rules.race_limit()))]
	return ["", 0]


## "7:42" (minutes can pass 59: "75:03").
static func clock_text(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]


static func _add(parts: Array, label: String, points: int) -> void:
	if points != 0 and not label.is_empty():
		parts.append([label, points])
