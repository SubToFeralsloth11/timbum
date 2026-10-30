class_name MatchFacts
extends RefCounted
## The local player's facts for one match: the one source challenges (Challenges, Profile.challenges)
## read. World keeps one per match on every peer (offline, host and client alike) and fills in what
## only this peer knows: how the player moved at each of their kills (sliding, prone, grappling,
## mid-air), how far away the victim was and the best multi-kill. Kills and headshots per weapon stay
## in World.my_weapon_stats (the per-weapon stats) and the scoreboard row gives kills, deaths,
## headshots and the best streak; `result()` joins them into the dictionary Profile.record_match
## takes, and `tally()` turns that dictionary into named counters.

## A kill still counts as a slide / grapple kill this long after the slide or grapple ended: on a
## client the server's kill event arrives a round trip after the shot.
const SLIDE_GRACE := 0.6
const GRAPPLE_GRACE := 1.0
## Movement and range kill counters kept per match.
const MOVE_KEYS: Array[String] = ["slide_kills", "prone_kills", "grapple_kills", "air_kills", "long_kills"]
## Tally counters that are a per-match best rather than a count.
const MAX_KEYS: Array[String] = ["best_streak", "best_multi"]

## MOVE_KEYS -> kills this match.
var moves := {}
## Most kills inside World.MULTI_KILL_WINDOW of each other.
var best_multi := 0
var _slide_at := -100.0
var _grapple_at := -100.0


func _init() -> void:
	for k: String in MOVE_KEYS:
		moves[k] = 0


## Every frame for the local player: remembers when they last slid or grappled.
func track(p: Player, t: float) -> void:
	if p == null or not p.alive:
		return
	if p.sliding:
		_slide_at = t
	if p.grappling:
		_grapple_at = t


## A kill by the local player as this peer learns it (World._s_killed). `dist` is the server's
## killer-victim distance (negative: unknown), `multi` the multi-kill count it makes. Grenade and
## Block Bomber kills count for range but not movement (thrown or called in earlier); the Bomber
## counts for neither.
func on_kill(p: Player, wid: String, dist: float, multi: int, t: float) -> void:
	best_multi = maxi(best_multi, multi)
	if wid == Streaks.WEAPON:
		return
	if dist >= Data.LONG_KILL_DISTANCE:
		moves.long_kills += 1
	if p == null or not p.alive or not Data.WEAPONS.has(wid):
		return
	if p.sliding or t - _slide_at <= SLIDE_GRACE:
		moves.slide_kills += 1
	if p.prone:
		moves.prone_kills += 1
	if p.grappling or t - _grapple_at <= GRAPPLE_GRACE:
		moves.grapple_kills += 1
	elif not p.is_on_floor():
		moves.air_kills += 1


## The record_match dictionary for this match so far: `row` is the local player's scoreboard row
## (kills, deaths, headshots, best_streak), `weapons` World.my_weapon_stats.
func result(row: Dictionary, weapons: Dictionary, placement: int, players: int, won: bool) -> Dictionary:
	return {
		"kills": int(row.get("kills", 0)), "deaths": int(row.get("deaths", 0)), "headshots": int(row.get("headshots", 0)),
		"best_streak": int(row.get("best_streak", 0)), "placement": placement, "players": players, "won": won,
		"weapons": weapons, "mode": str(Net.config.mode), "map": Net.current_map,
		"moves": moves.duplicate(), "best_multi": best_multi,
	}


## Named counters of one match result (see result()), only those above 0:
## kills, headshots, deaths, matches, wins (a win needs someone to beat, as in record_match),
## best_streak / best_multi (per-match bests, MAX_KEYS), w_kills:<source> / w_heads:<source> (per
## weapon, grenade and Bomber), the MOVE_KEYS, mode_kills|mode_matches|wins_mode:<mode> and
## map_kills|map_matches|wins_map:<map>.
static func tally(result: Dictionary) -> Dictionary:
	var t := {}
	var kills := maxi(0, int(result.get("kills", 0)))
	var won := bool(result.get("won", false)) and int(result.get("players", 1)) > 1
	_put(t, "kills", kills)
	_put(t, "headshots", int(result.get("headshots", 0)))
	_put(t, "deaths", int(result.get("deaths", 0)))
	_put(t, "matches", 1)
	_put(t, "wins", 1 if won else 0)
	_put(t, "best_streak", int(result.get("best_streak", 0)))
	_put(t, "best_multi", int(result.get("best_multi", 0)))
	var weapons := Profile.clean_weapon_stats(result.get("weapons", {}))
	for id: String in weapons:
		_put(t, "w_kills:" + id, int(weapons[id].kills))
		_put(t, "w_heads:" + id, int(weapons[id].headshots))
	var moves: Variant = result.get("moves", {})
	if typeof(moves) == TYPE_DICTIONARY:
		for k: String in MOVE_KEYS:
			var v: Variant = (moves as Dictionary).get(k, 0)
			_put(t, k, int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0)
	var mode := str(result.get("mode", ""))
	if Data.MODES.has(mode):
		_put(t, "mode_kills:" + mode, kills)
		_put(t, "mode_matches:" + mode, 1)
		_put(t, "wins_mode:" + mode, 1 if won else 0)
	var map := str(result.get("map", ""))
	if Data.MAPS.has(map):
		_put(t, "map_kills:" + map, kills)
		_put(t, "map_matches:" + map, 1)
		_put(t, "wins_map:" + map, 1 if won else 0)
	return t


static func _put(t: Dictionary, key: String, value: int) -> void:
	if value > 0:
		t[key] = value
