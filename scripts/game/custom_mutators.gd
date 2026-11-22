class_name CustomMutators
extends RefCounted
## Custom mutators: the host's own match tweaks, picked in the match setup's CUSTOM MUTATORS panel
## and carried in `Net.config.custom` (sanitize() runs inside Net.sanitize_config, so every peer
## holds the same, already mode-filtered values). They stack with the rolled mutator (Data.MUTATORS).
##   weapon         - one weapon for everyone ("" = off): a gun takes its own slot and the other
##                    gun slot is empty, a melee weapon empties both gun slots (apply_loadout,
##                    via World._apply_loadout_mutator). Only in WEAPON_MODES.
##   health         - max health in % (Player.max_health; World's spawn health).
##   gravity        - gravity multiplier (Player.gravity_scale, every simulating peer).
##   size           - player size: body, collider, hitboxes and eye height (Player.size_scale).
##                    Not in Block Hunt (hiders are blocks).
##   speed          - movement speed multiplier (Player.speed_scale).
##   damage         - damage multiplier (World._server_damage).
##   jump           - jump height multiplier (the jump speed scales by its square root).
##   headshots      - hitscan guns only hurt on a headshot (World._server_hitscan); melee,
##                    projectiles, blasts and killstreaks still do.
##   infinite_ammo  - magazines never empty (Player._shoot; the server skips the mode's round count).
##   no_grenades    - no frags or tacticals (`no_grenades` in the player's info).
## Other code reads them with value(key) (or the typed helpers below).

const DEFAULTS := {
	"weapon": "", "health": 100, "gravity": 1.0, "size": 1.0, "speed": 1.0, "damage": 1.0, "jump": 1.0,
	"headshots": false, "infinite_ammo": false, "no_grenades": false,
}
## Numeric settings: [min, max] (sanitize clamps to them).
const RANGES := {
	"health": [25, 400], "gravity": [0.25, 3.0], "size": [0.5, 1.5], "speed": [0.5, 2.0],
	"damage": [0.25, 4.0], "jump": [0.5, 3.0],
}
## The choices the setup panel offers for each numeric setting (DEFAULTS' value among them).
const CHOICES := {
	"health": [25, 50, 100, 150, 200, 400],
	"gravity": [0.25, 0.5, 1.0, 1.5, 2.0, 3.0],
	"size": [0.5, 0.75, 1.0, 1.25, 1.5],
	"speed": [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
	"damage": [0.5, 1.0, 1.5, 2.0, 3.0],
	"jump": [0.5, 1.0, 1.5, 2.0, 3.0],
}
## Modes where the one-weapon pick applies (the others hand out their own weapons: Gun Game's
## ladder, One in the Chamber's .44, Tactical's pickups, Bedwars' shop, or no guns at all).
const WEAPON_MODES: Array[String] = ["ffa", "tdm", "instakill", "ctf", "koth", "infected"]
## Modes without guns (Bedwars sells its own bow): no one-weapon pick, infinite ammo or headshots-only.
const GUNLESS_MODES: Array[String] = ["tag", "hideseek", "blockhunt", "parkour", "bedwars"]


## A full, valid set of custom mutators from `raw` (a config, a preset or a peer), with the settings
## `mode` ignores set back to their defaults ("" keeps them all: the setup screen's stored picks,
## kept across mode switches). Unknown keys are dropped; numbers are clamped.
static func sanitize(raw: Variant, mode := "") -> Dictionary:
	var out := DEFAULTS.duplicate()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw
	var wid := str(d.get("weapon", ""))
	if weapon_allowed(wid) and (mode.is_empty() or mode in WEAPON_MODES):
		out.weapon = wid
	for key: String in RANGES:
		var v: Variant = d.get(key)
		if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			var r: Array = RANGES[key]
			out[key] = clampi(int(v), r[0], r[1]) if key == "health" else clampf(float(v), r[0], r[1])
	for key: String in ["headshots", "infinite_ammo", "no_grenades"]:
		if typeof(d.get(key)) == TYPE_BOOL:
			out[key] = d[key]
	if mode in GUNLESS_MODES:
		out.headshots = false
		out.infinite_ammo = false
	if mode == "oitc":
		# One round per kill is the mode.
		out.infinite_ammo = false
	if mode == "blockhunt":
		out.size = 1.0
	return out


## Whether `wid` may be the one weapon for everyone: any gun or melee weapon in Data.WEAPONS except
## Bedwars' own (`bedwars` in its entry).
static func weapon_allowed(wid: String) -> bool:
	return Data.WEAPONS.has(wid) and not bool(Data.WEAPONS[wid].get("bedwars", false)) \
		and str(Data.WEAPONS[wid].get("slot", "")) in ["primary", "secondary", "melee"]


## This match's value of `key` (Net.config.custom, else DEFAULTS).
static func value(key: String) -> Variant:
	var custom: Variant = Net.config.get("custom", {})
	if typeof(custom) == TYPE_DICTIONARY and (custom as Dictionary).has(key):
		return custom[key]
	return DEFAULTS[key]


static func mult(key: String) -> float:
	return float(value(key))


static func health_mult() -> float:
	return float(value("health")) / 100.0


## The jump speed multiplier that gives `jump` times the jump height.
static func jump_speed_mult() -> float:
	return sqrt(mult("jump"))


static func flag(key: String) -> bool:
	return bool(value(key))


## Server: `info` with the one weapon and no-grenades applied (World._apply_loadout_mutator).
## Infected players (knife only) keep their melee.
static func apply_loadout(info: Dictionary) -> Dictionary:
	var wid := str(value("weapon"))
	var no_grenades := flag("no_grenades")
	if (wid.is_empty() or bool(info.get("knife_only", false))) and not no_grenades:
		return info
	var out := info.duplicate()
	if no_grenades:
		out.no_grenades = true
	if not wid.is_empty() and not bool(info.get("knife_only", false)):
		var slot := str(Data.WEAPONS[wid].slot)
		out.primary = wid if slot == "primary" else ""
		out.secondary = wid if slot == "secondary" else ""
		if slot == "melee":
			out.melee = wid
	return out


## Short labels of what `custom` changes, e.g. ["Rail Cube only", "150% health", "0.5x gravity"].
static func describe(custom: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var wid := str(custom.get("weapon", ""))
	if not wid.is_empty() and Data.WEAPONS.has(wid):
		out.append("%s only" % str(Data.WEAPONS[wid].name))
	if int(custom.get("health", 100)) != 100:
		out.append("%d%% health" % int(custom.health))
	for pair: Array in [["gravity", "gravity"], ["size", "size"], ["speed", "speed"], ["damage", "damage"], ["jump", "jump"]]:
		var v := float(custom.get(pair[0], 1.0))
		if not is_equal_approx(v, 1.0):
			out.append("%sx %s" % [num(v), pair[1]])
	if bool(custom.get("headshots", false)):
		out.append("headshots only")
	if bool(custom.get("infinite_ammo", false)):
		out.append("infinite ammo")
	if bool(custom.get("no_grenades", false)):
		out.append("no grenades")
	return out


## A multiplier as text without trailing zeros: 0.25, 0.5, 1, 1.5.
static func num(v: float) -> String:
	return str(snappedf(v, 0.01)).trim_suffix(".0")
