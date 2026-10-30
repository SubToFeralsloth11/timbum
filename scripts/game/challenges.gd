class_name Challenges
extends RefCounted
## Daily and weekly challenges: periods from the local date, deterministic sets from
## Data.CHALLENGE_TEMPLATES, their text, and progress from MatchFacts.tally counters. The sets and
## their progress live in Profile.challenges (refresh_challenges rolls them over, record_match
## advances them, claim_challenge pays them).
##
## A challenge entry: {id (template), param, n (number in the text: the target, or the per-match
## threshold), target, progress, claimed}.

const KINDS: Array[String] = ["daily", "weekly"]


## Today's day number (days since 1970-01-01) by the local calendar, so daily sets change at local
## midnight.
static func today() -> int:
	var d := Time.get_date_dict_from_system()
	return day_number(int(d.year), int(d.month), int(d.day))


static func day_number(year: int, month: int, day: int) -> int:
	var unix := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": 0, "minute": 0, "second": 0})
	return floori(float(unix) / 86400.0)


## Day number of the Monday that starts `day`'s week (1970-01-01 was a Thursday).
static func week_start(day: int) -> int:
	return day - posmod(day + 3, 7)


## The period a `kind` set of `day` belongs to: the day itself, or its week's Monday.
static func period_of(kind: String, day: int) -> int:
	return day if kind == "daily" else week_start(day)


## Ids a template's `param` kind can take, in catalog order; `owned` are the gun ids the player owns.
static func param_pool(param: String, owned: Array) -> Array:
	var out: Array = []
	match param:
		"gun", "gun_hs":
			for id: String in Data.WEAPONS:
				# The rocket's blast never lands a headshot.
				if owned.has(id) and Data.WEAPONS[id].slot != "melee" and not (param == "gun_hs" and id == "rocket"):
					out.append(id)
		"mode":
			out.assign(Data.MODES.keys())
		"map":
			out.assign(Data.MAP_ROTATION)
		_:
			out.append("")
	return out


## The `kind` set ("daily" or "weekly") for `period` (period_of). The same period and owned guns
## always give the same set; each slot of Data.CHALLENGE_SLOTS draws a different template.
static func generate(kind: String, period: int, owned: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("timbum-challenges-%s-%d" % [kind, period]).hash()
	var out: Array = []
	var used := {}
	for groups: Array in Data.CHALLENGE_SLOTS[kind]:
		var options: Array[String] = []
		for id: String in Data.CHALLENGE_TEMPLATES:
			var t: Dictionary = Data.CHALLENGE_TEMPLATES[id]
			if groups.has(t.group) and t.has(kind) and not used.has(id) and not param_pool(str(t.param), owned).is_empty():
				options.append(id)
		if options.is_empty():
			continue
		var pick := options[rng.randi_range(0, options.size() - 1)]
		used[pick] = true
		var tpl: Dictionary = Data.CHALLENGE_TEMPLATES[pick]
		var pool := param_pool(str(tpl.param), owned)
		var param: String = pool[rng.randi_range(0, pool.size() - 1)]
		var bounds: Array = tpl[kind]
		var n := rng.randi_range(int(bounds[0]), int(bounds[1]))
		out.append({"id": pick, "param": param, "n": n, "target": 1 if tpl.get("per_match", false) else n,
			"progress": 0, "claimed": false})
	return out


## A saved entry made safe (unknown template or param, bad numbers), or {} when it can't be kept.
static func sanitize(raw: Variant, kind: String) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = raw
	var id := str(d.get("id", ""))
	if not Data.CHALLENGE_TEMPLATES.has(id) or not (Data.CHALLENGE_TEMPLATES[id] as Dictionary).has(kind):
		return {}
	var tpl: Dictionary = Data.CHALLENGE_TEMPLATES[id]
	var param := str(d.get("param", ""))
	if not param_pool(str(tpl.param), Data.WEAPONS.keys()).has(param):
		return {}
	var n := clampi(Profile._num(d.get("n"), 0), 1, 100000)
	var target := 1 if tpl.get("per_match", false) else n
	var claimed: Variant = d.get("claimed", false)
	return {"id": id, "param": param, "n": n, "target": target,
		"progress": clampi(Profile._num(d.get("progress"), 0), 0, target), "claimed": typeof(claimed) == TYPE_BOOL and claimed}


static func is_complete(ch: Dictionary) -> bool:
	return int(ch.progress) >= int(ch.target)


## How far one match's tally (MatchFacts.tally) advances `ch`.
static func amount(ch: Dictionary, tally: Dictionary) -> int:
	var tpl: Dictionary = Data.CHALLENGE_TEMPLATES[ch.id]
	var key := str(tpl.key)
	if key.contains("%s"):
		key = key % str(ch.param)
	var v := int(tally.get(key, 0))
	if tpl.get("per_match", false):
		return 1 if v >= int(ch.n) else 0
	return v


## "Get 12 kills with the Bit-SMG".
static func text(ch: Dictionary) -> String:
	var tpl: Dictionary = Data.CHALLENGE_TEMPLATES[ch.id]
	var s := str(tpl.text[0 if int(ch.n) == 1 else 1])
	return s.replace("{n}", str(int(ch.n))).replace("{p}", param_name(str(tpl.param), str(ch.param)))


static func param_name(param: String, id: String) -> String:
	match param:
		"gun", "gun_hs":
			return str(Data.WEAPONS[id].name)
		"mode":
			return str(Data.MODES[id].name)
		"map":
			return str(Data.MAPS[id].name)
	return ""


## {coins, xp} claiming a `kind` challenge pays.
static func reward(kind: String) -> Dictionary:
	return Data.CHALLENGE_REWARDS[kind]
