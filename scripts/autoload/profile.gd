extends Node
## Persistent player profile: coins, inventory, loadout, cosmetics, settings, stats.
## Also owns the input map so key bindings exist before any scene loads.

signal changed

const SAVE_PATH := "user://profile.json"
const SAVE_VERSION := 1

const DEFAULT_SETTINGS := {
	"mouse_sens": 1.0,
	"ads_sens_mult": 0.75,
	"fov": 85.0,
	"invert_y": false,
	"master_volume": 0.8,
	"music_volume": 0.45,
	"sfx_volume": 0.85,
	"fullscreen": false,
	"vsync": true,
	"quality": 1,
	"post_fx": true,
	## 0 off, 1 FXAA, 2 MSAA 2x, 3 MSAA 4x, 4 TAA (see ANTI_ALIASING_NAMES).
	"anti_aliasing": 2,
	"render_scale": 1.0,
	"shadows": true,
	"ambient_occlusion": true,
	"bloom": true,
	"reflections": false,
	"block_detail": true,
	"show_fps": false,
	"damage_numbers": true,
	"killfeed": true,
	"crosshair_color": "ffffff",
	"last_ip": "127.0.0.1",
	"last_port": 7777,
	"last_code": "",
}

const ANTI_ALIASING_NAMES: Array[String] = ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "TAA"]
## Effect toggles each graphics quality preset (Low, Medium, High) switches to when picked.
const QUALITY_PRESETS: Array[Dictionary] = [
	{"shadows": true, "ambient_occlusion": false, "bloom": false, "reflections": false, "anti_aliasing": 1},
	{"shadows": true, "ambient_occlusion": true, "bloom": true, "reflections": false, "anti_aliasing": 2},
	{"shadows": true, "ambient_occlusion": true, "bloom": true, "reflections": true, "anti_aliasing": 3},
]

const DEFAULT_STATS := {
	"kills": 0, "deaths": 0, "headshots": 0, "matches": 0, "wins": 0,
	"best_streak": 0, "coins_earned": 0,
}
## Per-weapon numbers kept for each Data.WEAPONS id and Data.STAT_EXTRA_SOURCES (weapon_stats).
## A shot is one round leaving the gun: one trigger pull of a single-shot gun, each round of a
## burst (a 3-round burst is 3 shots), one shotgun shell however many pellets it holds, one rocket,
## one knife swing. A hit is a shot that struck at least one enemy (never more than one hit per
## shot, so accuracy stays 0-100 %). Damage is what the server says the hits took (health and
## Overshield). Grenades and the Block Bomber have kills, headshots and damage but no shots.
const WEAPON_STAT_KEYS: Array[String] = ["kills", "headshots", "shots", "hits", "damage"]

var player_name := "Player"
var coins := 500
var xp := 0
var level := 1
var owned := {}
var loadout := {"primary": "smg", "secondary": "pistol", "tactical": "flash"}
const DEFAULT_EQUIPPED := {"skin": "default", "hat": "none", "outfit": "classic", "charm": "none", "emote": "wave", "draw": "standard"}
## Equipped slot -> catalog category.
const EQUIP_SLOTS := {"skin": "skins", "hat": "hats", "outfit": "outfits", "charm": "charms", "emote": "emotes", "draw": "draws"}
var equipped := DEFAULT_EQUIPPED.duplicate()
## Attachment id -> level bought (see Data.ATTACHMENTS); missing means 0.
var upgrades := {}
var settings := DEFAULT_SETTINGS.duplicate()
var stats := DEFAULT_STATS.duplicate()
var last_daily := 0
## Lifetime per-weapon stats: weapon or source id -> {kills, headshots, shots, hits, damage}.
var weapon_stats := {}
## Weapon id -> mastery tiers already paid for (0-3), so each tier's coins are paid once.
var mastery_paid := {}
## Weapon ids whose mastery camo the player switched on (only Gold guns; see set_camo).
var camos: Array = []
## Prestige rank 0..Data.PRESTIGE_MAX.
var prestige := 0
## Daily and weekly challenges: "daily" / "weekly" -> {period (Challenges.period_of), list
## (Challenges entries)}; refresh_challenges rolls them over.
var challenges := {}
## Lifetime counters from MatchFacts.tally that stats and weapon_stats don't already hold:
## movement and range kills, per-mode and per-map kills / matches / wins, the best multi-kill,
## medals ("medal:<id>" and "medals") and "challenges_done". See _is_feat_key.
var feats := {}
## Unlocked achievement id (Data.ACHIEVEMENTS) -> unlock time (Unix seconds).
var achievements := {}

## Set to false by tests so they never touch the real save file.
var persist := true


func _ready() -> void:
	_apply_bindings()
	load_profile()
	apply_settings()


# ---------------------------------------------------------------- inventory

func is_owned(category: String, id: String) -> bool:
	var cat := Data.catalog(category)
	if not cat.has(id):
		return false
	if int(cat[id].price) == 0:
		return true
	return id in owned.get(category, [])


func price_of(category: String, id: String) -> int:
	var cat := Data.catalog(category)
	return int(cat[id].price) if cat.has(id) else -1


func buy(category: String, id: String) -> bool:
	var price := price_of(category, id)
	if price < 0 or is_owned(category, id) or coins < price:
		return false
	coins -= price
	var list: Array = owned.get(category, [])
	list.append(id)
	owned[category] = list
	save()
	changed.emit()
	return true


func is_equipped(category: String, id: String) -> bool:
	match category:
		"weapons":
			return loadout.primary == id or loadout.secondary == id
		"tacticals":
			return loadout.tactical == id
	for slot: String in EQUIP_SLOTS:
		if EQUIP_SLOTS[slot] == category:
			return equipped[slot] == id
	return false


func equip(category: String, id: String) -> bool:
	if not is_owned(category, id):
		return false
	match category:
		"weapons":
			var slot: String = Data.WEAPONS[id].slot
			if slot == "melee":
				return false
			loadout[slot] = id
		"tacticals":
			loadout.tactical = id
		_:
			var slot := ""
			for s: String in EQUIP_SLOTS:
				if EQUIP_SLOTS[s] == category:
					slot = s
			if slot.is_empty():
				return false
			equipped[slot] = id
	save()
	changed.emit()
	return true


# ---------------------------------------------------------------- attachment upgrades

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func is_upgrade_maxed(id: String) -> bool:
	return upgrade_level(id) >= int(Data.ATTACHMENTS[id].max)


## Price of the next level of `id` (-1 when maxed). Each level costs ATTACHMENT_GROWTH times the
## last, so early levels are cheap and noticeable and the top levels take a while to save for.
func upgrade_price(id: String) -> int:
	if not Data.ATTACHMENTS.has(id) or is_upgrade_maxed(id):
		return -1
	var a: Dictionary = Data.ATTACHMENTS[id]
	return int(round(float(a.base_price) * pow(Data.ATTACHMENT_GROWTH, upgrade_level(id)) / 10.0)) * 10


func buy_upgrade(id: String) -> bool:
	var price := upgrade_price(id)
	if price < 0 or coins < price:
		return false
	coins -= price
	upgrades[id] = upgrade_level(id) + 1
	save()
	changed.emit()
	return true


func peer_info() -> Dictionary:
	return {
		"name": player_name,
		"outfit": equipped.outfit,
		"hat": equipped.hat,
		"skin": equipped.skin,
		"charm": equipped.charm,
		"emote": equipped.emote,
		"draw": equipped.draw,
		"mods": upgrades.duplicate(),
		"primary": loadout.primary,
		"secondary": loadout.secondary,
		"tactical": loadout.tactical,
		"level": level,
		"prestige": prestige,
		"camos": camos.duplicate(),
	}


func set_player_name(new_name: String) -> void:
	new_name = sanitize_name(new_name)
	if new_name.is_empty():
		return
	player_name = new_name
	save()
	changed.emit()


static func sanitize_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.unicode_at(0) >= 32 and ch != "[" and ch != "]":
			out += ch
	return out.substr(0, 16).strip_edges()


# ---------------------------------------------------------------- progression

func xp_for_level(lvl: int) -> int:
	return 500 + 250 * (lvl - 1)


func can_claim_daily() -> bool:
	return _daily_elapsed() >= 86400


func seconds_until_daily() -> int:
	return maxi(0, int(86400 - _daily_elapsed()))


## Seconds since the last daily claim. A claim time in the future means the system clock
## was moved back; the 24 h wait restarts from now instead of locking the reward until the
## clock catches up.
func _daily_elapsed() -> float:
	var now := Time.get_unix_time_from_system()
	if last_daily > now:
		last_daily = int(now)
	return now - last_daily


func claim_daily() -> int:
	if not can_claim_daily():
		return 0
	last_daily = int(Time.get_unix_time_from_system())
	coins += Data.DAILY_REWARD
	stats.coins_earned += Data.DAILY_REWARD
	save()
	changed.emit()
	return Data.DAILY_REWARD


## result: {kills, deaths, headshots, placement (1-based), players, won, best_streak, weapons,
## mode, map, moves, best_multi} (MatchFacts.result). `weapons` is the match's per-weapon numbers
## (World.my_weapon_stats: id -> {kills, headshots, shots, hits, damage}); they are added to
## weapon_stats and pay any mastery tier reached. The whole result (MatchFacts.tally) advances the
## challenges.
## Returns {coins, xp, levels_gained, breakdown, accuracy, shots, hits, most_used, mastery, feats};
## breakdown is [[label, coins, xp], ...], one row per source, in the order the results screen
## lists them. accuracy is hits / shots of the match (-1 without shots), most_used the weapon
## fired most ("" if none), mastery the [weapon id, tier] pairs reached this match, feats the
## challenges it completed and achievements it unlocked ([key, title, text], see preview_feats).
## The tally also goes into feats (medals included) for the achievements.
## At Data.LEVEL_CAP XP stops: the match pays no XP until the player prestiges.
func record_match(result: Dictionary) -> Dictionary:
	var kills := int(result.get("kills", 0))
	var heads := int(result.get("headshots", 0))
	var placement := int(result.get("placement", 99))
	# Placement rewards, the victory bonus and the win stat need someone to beat.
	var contested := int(result.get("players", 1)) > 1
	var won := bool(result.get("won", false)) and contested
	var breakdown: Array = [["Match played", Data.COINS_PARTICIPATION, Data.XP_MATCH]]
	# A period that ended during the match pays its completed, unclaimed challenges here.
	var carried := refresh_challenges(-1, false)
	if int(carried.coins) > 0 or int(carried.xp) > 0:
		breakdown.append(["Unclaimed challenges", int(carried.coins), int(carried.xp)])
	if kills > 0:
		breakdown.append(["%d kill%s" % [kills, "" if kills == 1 else "s"], kills * Data.COINS_PER_KILL, kills * Data.XP_PER_KILL])
	if heads > 0:
		breakdown.append(["%d headshot%s" % [heads, "" if heads == 1 else "s"], heads * Data.COINS_PER_HEADSHOT, heads * Data.XP_PER_HEADSHOT])
	var place_coins := 0
	if placement >= 1 and placement <= Data.COINS_PLACEMENT.size() and contested:
		place_coins = Data.COINS_PLACEMENT[placement - 1]
	if won:
		breakdown.append(["Victory", place_coins, 200])
	elif place_coins > 0:
		breakdown.append(["#%d place" % placement, place_coins, 0])
	var match_weapons := clean_weapon_stats(result.get("weapons", {}))
	var summary := match_summary(match_weapons)
	_add_weapon_stats(match_weapons)
	var tally := MatchFacts.tally(result)
	var done_feats := _advance_challenges(tally)
	_add_feats(tally)
	var reached := _pay_mastery(match_weapons.keys(), breakdown)
	var capped := level >= Data.LEVEL_CAP
	if capped:
		for row: Array in breakdown:
			row[2] = 0
		breakdown.append(["Max level: prestige for more XP", 0, 0])
	var earned := 0
	var gained_xp := 0
	for row: Array in breakdown:
		earned += int(row[1])
		gained_xp += int(row[2])
	var levels := _add_xp(gained_xp)
	if levels > 0:
		breakdown.append(["Level up! Level %d" % level, levels * Data.COINS_PER_LEVEL, 0])
		earned += levels * Data.COINS_PER_LEVEL
	coins += earned
	stats.kills += kills
	stats.deaths += int(result.get("deaths", 0))
	stats.headshots += heads
	stats.matches += 1
	stats.wins += 1 if won else 0
	stats.best_streak = maxi(int(stats.best_streak), int(result.get("best_streak", 0)))
	stats.coins_earned += earned
	done_feats.append_array(_unlock_achievements())
	save()
	changed.emit()
	var out := {"coins": earned, "xp": gained_xp, "levels_gained": levels, "breakdown": breakdown, "mastery": reached, "feats": done_feats}
	out.merge(summary)
	return out


## Adds `amount` XP and levels up (no XP at Data.LEVEL_CAP). Returns the levels gained; the caller
## pays their Data.COINS_PER_LEVEL.
func _add_xp(amount: int) -> int:
	if level >= Data.LEVEL_CAP:
		xp = 0
		return 0
	xp += amount
	var levels := 0
	while level < Data.LEVEL_CAP and xp >= xp_for_level(level):
		xp -= xp_for_level(level)
		level += 1
		levels += 1
	if level >= Data.LEVEL_CAP:
		xp = 0
	return levels


# ---------------------------------------------------------------- challenges

## Gun ids the player owns (challenge params).
func owned_guns() -> Array:
	var out: Array = []
	for id: String in Data.WEAPONS:
		if is_owned("weapons", id):
			out.append(id)
	return out


## Starts a new set for each kind whose period ended (local midnight for daily, Monday for
## weekly; `day` overrides today's Challenges.day_number). Unfinished challenges of the old set are
## dropped; completed ones not yet claimed are paid rather than lost. A clock moved back keeps the
## current sets. Returns that payout {coins, xp}; with `pay` it is added now (coins, XP, level-ups),
## else the caller pays it (record_match lists it in the breakdown).
func refresh_challenges(day := -1, pay := true) -> Dictionary:
	if day < 0:
		day = Challenges.today()
	var owed := {"coins": 0, "xp": 0}
	var rolled := false
	for kind: String in Challenges.KINDS:
		var period := Challenges.period_of(kind, day)
		var cur: Dictionary = challenges.get(kind, {})
		if not cur.is_empty() and int(cur.period) >= period:
			continue
		for ch: Dictionary in cur.get("list", []):
			if Challenges.is_complete(ch) and not ch.claimed:
				owed.coins += int(Challenges.reward(kind).coins)
				owed.xp += int(Challenges.reward(kind).xp)
		challenges[kind] = {"period": period, "list": Challenges.generate(kind, period, owned_guns())}
		rolled = true
	if pay and (owed.coins > 0 or owed.xp > 0):
		_grant(owed.coins, owed.xp)
	if rolled:
		save()
		changed.emit()
	return owed


## The current `kind` set (entries as in Challenges); empty before the first refresh.
func challenge_list(kind: String) -> Array:
	return (challenges.get(kind, {}) as Dictionary).get("list", [])


## Challenges ready to claim, for the menu badge.
func claimable_challenges() -> int:
	var n := 0
	for kind: String in Challenges.KINDS:
		for ch: Dictionary in challenge_list(kind):
			if Challenges.is_complete(ch) and not ch.claimed:
				n += 1
	return n


## Pays challenge `index` of `kind` once it is complete: {coins, xp, levels} (XP is 0 at the level
## cap), or {} if it isn't complete or was already claimed.
func claim_challenge(kind: String, index: int) -> Dictionary:
	var list := challenge_list(kind)
	if index < 0 or index >= list.size():
		return {}
	var ch: Dictionary = list[index]
	if not Challenges.is_complete(ch) or ch.claimed:
		return {}
	ch.claimed = true
	var reward := Challenges.reward(kind)
	var gained_xp := 0 if level >= Data.LEVEL_CAP else int(reward.xp)
	var levels := _grant(int(reward.coins), gained_xp)
	save()
	changed.emit()
	return {"coins": int(reward.coins), "xp": gained_xp, "levels": levels}


## Adds coins and XP outside a match (claims, carried rewards), level-up coins included. Returns
## the levels gained.
func _grant(add_coins: int, add_xp: int) -> int:
	var levels := _add_xp(add_xp)
	var paid := add_coins + levels * Data.COINS_PER_LEVEL
	coins += paid
	stats.coins_earned += paid
	return levels


## Advances every unfinished challenge by one match's tally. Returns the ones it completed as
## [key, title, text].
func _advance_challenges(tally: Dictionary) -> Array:
	var done: Array = []
	for kind: String in Challenges.KINDS:
		var list := challenge_list(kind)
		for i in list.size():
			var ch: Dictionary = list[i]
			if Challenges.is_complete(ch):
				continue
			ch.progress = mini(int(ch.target), int(ch.progress) + Challenges.amount(ch, tally))
			if Challenges.is_complete(ch):
				done.append(_challenge_feat(kind, i, ch))
				feats.challenges_done = int(feats.get("challenges_done", 0)) + 1
	return done


static func _challenge_feat(kind: String, index: int, ch: Dictionary) -> Array:
	return ["%s:%d:%s" % [kind, index, ch.id], "%s CHALLENGE COMPLETE" % kind.to_upper(), Challenges.text(ch)]


## What a match result so far (MatchFacts.result) would complete or unlock if the match ended now,
## as [key, title, text] (the key is stable, so the HUD toasts each once); changes nothing.
func preview_feats(result: Dictionary) -> Array:
	var tally := MatchFacts.tally(result)
	var out: Array = []
	for kind: String in Challenges.KINDS:
		var list := challenge_list(kind)
		for i in list.size():
			var ch: Dictionary = list[i]
			if not Challenges.is_complete(ch) and int(ch.progress) + Challenges.amount(ch, tally) >= int(ch.target):
				out.append(_challenge_feat(kind, i, ch))
	for id: String in Data.ACHIEVEMENTS:
		if not achievements.has(id) and achievement_value(str(Data.ACHIEVEMENTS[id].key), tally) >= achievement_target(id):
			out.append(_achievement_feat(id))
	return out


# ---------------------------------------------------------------- achievements and medals

## Lifetime value of an achievement key (Data.ACHIEVEMENTS), with one match's `tally`
## (MatchFacts.tally) added when given. Keys: the stats ones (kills, headshots, deaths, matches,
## wins, best_streak), w_kills:<id> / w_heads:<id> (weapon_stats), the counts guns_with_kill,
## maps_won, modes_won and gold_guns, or a feats counter.
func achievement_value(key: String, tally: Dictionary = {}) -> int:
	var n := 0
	match key:
		"guns_with_kill":
			for id: String in Data.WEAPONS:
				if Data.WEAPONS[id].slot != "melee" and weapon_stat(id, "kills") + int(tally.get("w_kills:" + id, 0)) > 0:
					n += 1
			return n
		"gold_guns":
			for id: String in Data.WEAPONS:
				if Data.mastery_tier_for(weapon_stat(id, "kills") + int(tally.get("w_kills:" + id, 0))) >= Data.MASTERY_TIERS.size():
					n += 1
			return n
		"maps_won":
			for m: String in Data.MAP_ROTATION:
				if int(feats.get("wins_map:" + m, 0)) + int(tally.get("wins_map:" + m, 0)) > 0:
					n += 1
			return n
		"modes_won":
			for m: String in Data.MODES:
				if int(feats.get("wins_mode:" + m, 0)) + int(tally.get("wins_mode:" + m, 0)) > 0:
					n += 1
			return n
	var base := 0
	if key.begins_with("w_kills:"):
		base = weapon_stat(key.trim_prefix("w_kills:"), "kills")
	elif key.begins_with("w_heads:"):
		base = weapon_stat(key.trim_prefix("w_heads:"), "headshots")
	elif stats.has(key):
		base = int(stats[key])
	else:
		base = int(feats.get(key, 0))
	if MatchFacts.MAX_KEYS.has(key):
		return maxi(base, int(tally.get(key, 0)))
	return base + int(tally.get(key, 0))


## The value that unlocks achievement `id` (Data.ACHIEVE_ALL resolved to how many there are).
func achievement_target(id: String) -> int:
	var a: Dictionary = Data.ACHIEVEMENTS[id]
	if int(a.target) != Data.ACHIEVE_ALL:
		return int(a.target)
	match str(a.key):
		"guns_with_kill":
			return Data.WEAPONS.keys().filter(func(w: String) -> bool: return Data.WEAPONS[w].slot != "melee").size()
		"maps_won":
			return Data.MAP_ROTATION.size()
		"modes_won":
			return Data.MODES.size()
	return 1


## [value so far (capped at the target), target] of achievement `id`.
func achievement_progress(id: String) -> Array:
	var target := achievement_target(id)
	return [mini(achievement_value(str(Data.ACHIEVEMENTS[id].key)), target), target]


## Lifetime count of medal `id` (Data.MEDALS).
func medal_count(id: String) -> int:
	return int(feats.get("medal:" + id, 0))


## Unlocks every achievement whose target is reached (each once). Returns them as feats.
func _unlock_achievements() -> Array:
	var out: Array = []
	var now := int(Time.get_unix_time_from_system())
	for id: String in Data.ACHIEVEMENTS:
		if not achievements.has(id) and achievement_value(str(Data.ACHIEVEMENTS[id].key)) >= achievement_target(id):
			achievements[id] = now
			out.append(_achievement_feat(id))
	return out


static func _achievement_feat(id: String) -> Array:
	return ["ach:" + id, "ACHIEVEMENT UNLOCKED", str(Data.ACHIEVEMENTS[id].name)]


## Adds one match's tally to feats (keys stats / weapon_stats already count are skipped).
func _add_feats(tally: Dictionary) -> void:
	for key: String in tally:
		if not _is_feat_key(key):
			continue
		if MatchFacts.MAX_KEYS.has(key):
			feats[key] = maxi(int(feats.get(key, 0)), int(tally[key]))
		else:
			feats[key] = int(feats.get(key, 0)) + int(tally[key])


## Keys feats keeps: MatchFacts.MOVE_KEYS, best_multi, medals, challenges_done, and
## mode_kills|mode_matches|wins_mode:<mode>, map_kills|map_matches|wins_map:<map>, medal:<id>.
static func _is_feat_key(key: String) -> bool:
	if MatchFacts.MOVE_KEYS.has(key) or key in ["best_multi", "medals", "challenges_done"]:
		return true
	var parts := key.split(":")
	if parts.size() != 2:
		return false
	match parts[0]:
		"mode_kills", "mode_matches", "wins_mode":
			return Data.MODES.has(parts[1])
		"map_kills", "map_matches", "wins_map":
			return Data.MAPS.has(parts[1])
		"medal":
			return Data.MEDALS.has(parts[1])
	return false


# ---------------------------------------------------------------- per-weapon stats and mastery

## Every id weapon_stats tracks: the weapons, then the frag grenade and the Block Bomber.
static func stat_sources() -> Array[String]:
	var ids: Array[String] = []
	for id: String in Data.WEAPONS:
		ids.append(id)
	ids.append_array(Data.STAT_EXTRA_SOURCES)
	return ids


## Lifetime `key` (one of WEAPON_STAT_KEYS) for weapon or source `wid`.
func weapon_stat(wid: String, key: String) -> int:
	return int((weapon_stats.get(wid, {}) as Dictionary).get(key, 0))


## Match accuracy and most-used weapon of a set of per-weapon numbers (see record_match).
static func match_summary(per_weapon: Dictionary) -> Dictionary:
	var shots := 0
	var hits := 0
	var most := ""
	for id: String in per_weapon:
		var s: Dictionary = per_weapon[id]
		shots += int(s.get("shots", 0))
		hits += int(s.get("hits", 0))
		if int(s.get("shots", 0)) <= 0 or not Data.WEAPONS.has(id):
			continue
		if most.is_empty() or int(s.shots) > int(per_weapon[most].shots) \
				or (int(s.shots) == int(per_weapon[most].shots) and int(s.get("kills", 0)) > int(per_weapon[most].get("kills", 0))):
			most = id
	return {"shots": shots, "hits": hits, "accuracy": float(hits) / shots if shots > 0 else -1.0, "most_used": most}


## Keeps known ids and non-negative whole numbers, with hits never above shots.
static func clean_weapon_stats(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for id: String in stat_sources():
		var s: Variant = (raw as Dictionary).get(id)
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var clean := {}
		var any := false
		for key: String in WEAPON_STAT_KEYS:
			var v: Variant = (s as Dictionary).get(key, 0)
			clean[key] = maxi(0, roundi(float(v)) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0)
			any = any or clean[key] > 0
		clean.hits = mini(clean.hits, clean.shots) if Data.WEAPONS.has(id) else 0
		if not Data.WEAPONS.has(id):
			clean.shots = 0
		if any:
			out[id] = clean
	return out


func _add_weapon_stats(per_weapon: Dictionary) -> void:
	for id: String in per_weapon:
		var total: Dictionary = weapon_stats.get(id, {})
		for key: String in WEAPON_STAT_KEYS:
			total[key] = int(total.get(key, 0)) + int(per_weapon[id][key])
		weapon_stats[id] = total


## Mastery tier (0 none .. 3 Gold) `wid` has reached with its lifetime kills.
func mastery_tier(wid: String) -> int:
	return Data.mastery_tier_for(weapon_stat(wid, "kills")) if Data.WEAPONS.has(wid) else 0


## Short mastery progress for `wid`: "GOLD · 162 KILLS", "BRONZE · 41/75 KILLS", "12/25 KILLS".
func mastery_text(wid: String) -> String:
	var tier := mastery_tier(wid)
	var kills := weapon_stat(wid, "kills")
	var reached: String = "" if tier == 0 else str(Data.MASTERY_TIERS[tier - 1].name).to_upper() + " · "
	if tier >= Data.MASTERY_TIERS.size():
		return "%s%d KILLS" % [reached, kills]
	return "%s%d/%d KILLS" % [reached, kills, int(Data.MASTERY_TIERS[tier].kills)]


## Pays each mastery tier the guns in `ids` reached and haven't been paid for yet, as rows in
## `breakdown`. Returns the [weapon id, tier] pairs paid.
func _pay_mastery(ids: Array, breakdown: Array) -> Array:
	var paid: Array = []
	for id: String in Data.WEAPONS:
		if not ids.has(id):
			continue
		var tier := mastery_tier(id)
		for t in range(int(mastery_paid.get(id, 0)), tier):
			var info: Dictionary = Data.MASTERY_TIERS[t]
			var label := "%s %s mastery" % [Data.WEAPONS[id].name, info.name]
			if t == Data.MASTERY_TIERS.size() - 1:
				label += ": camo unlocked"
			breakdown.append([label, int(info.coins), 0])
			paid.append([id, t + 1])
		mastery_paid[id] = maxi(int(mastery_paid.get(id, 0)), tier)
	return paid


## True once `wid` reached Gold mastery.
func has_camo(wid: String) -> bool:
	return mastery_tier(wid) >= Data.MASTERY_TIERS.size()


func is_camo_on(wid: String) -> bool:
	return camos.has(wid)


## Switches `wid`'s mastery camo on or off (only for a Gold gun). Returns false if not allowed.
func set_camo(wid: String, on: bool) -> bool:
	if on and not has_camo(wid):
		return false
	if on and not camos.has(wid):
		camos.append(wid)
	elif not on:
		camos.erase(wid)
	save()
	changed.emit()
	return true


## The skin this player's `wid` wears (mastery camo when switched on, else the equipped skin).
func gun_skin(wid: String) -> String:
	return Data.gun_skin_for(peer_info(), wid)


# ---------------------------------------------------------------- prestige

func can_prestige() -> bool:
	return level >= Data.LEVEL_CAP and prestige < Data.PRESTIGE_MAX


## Coins the next prestige pays.
func prestige_bonus() -> int:
	return Data.PRESTIGE_COINS * (prestige + 1)


## At the level cap: level back to 1 (XP 0), prestige rank +1 and its coin bonus; coins, items,
## upgrades and stats stay. Returns the coins paid, or -1 when not allowed (below the cap or at
## the top rank).
func do_prestige() -> int:
	if not can_prestige():
		return -1
	var bonus := prestige_bonus()
	prestige += 1
	level = 1
	xp = 0
	coins += bonus
	stats.coins_earned += bonus
	save()
	changed.emit()
	return bonus


# ---------------------------------------------------------------- settings

func get_setting(key: String) -> Variant:
	return settings.get(key, DEFAULT_SETTINGS.get(key))


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()
	save()
	changed.emit()


func apply_settings() -> void:
	_set_bus_volume("Master", float(get_setting("master_volume")))
	_set_bus_volume("Music", float(get_setting("music_volume")))
	_set_bus_volume("SFX", float(get_setting("sfx_volume")))
	if DisplayServer.get_name() == "headless":
		return
	var want_fs: bool = get_setting("fullscreen")
	var mode := DisplayServer.window_get_mode()
	var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want_fs != is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_setting("vsync") else DisplayServer.VSYNC_DISABLED)
	_apply_graphics()


## Anti-aliasing and render scale on the main viewport; shadows, AO, bloom and reflections on
## the current map; block shader detail on the shared block materials. All live.
func _apply_graphics() -> void:
	var vp := get_viewport()
	var aa := int(get_setting("anti_aliasing"))
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_DISABLED][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == 4
	vp.scaling_3d_scale = float(get_setting("render_scale"))
	BlockAtlas.set_detail(bool(get_setting("block_detail")))
	MapBuilder.apply_graphics(get_tree())


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


# ---------------------------------------------------------------- persistence

func save() -> void:
	if not persist:
		return
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save profile: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(_payload(), "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(SAVE_PATH))


func _payload() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"player_name": player_name, "coins": coins, "xp": xp, "level": level,
		"owned": owned, "loadout": loadout, "equipped": equipped, "upgrades": upgrades,
		"settings": settings, "stats": stats, "last_daily": last_daily, "bindings": bindings,
		"weapon_stats": weapon_stats, "mastery_paid": mastery_paid, "camos": camos, "prestige": prestige,
		"challenges": challenges, "feats": feats, "achievements": achievements,
	}


## Writes the whole profile (progress, items, upgrades, settings, key bindings) to `path`, a
## file the player picked, so it can be restored on another computer or after a reinstall.
func export_to(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var data := _payload()
	data["timbum_profile"] = true
	data["exported_at"] = Time.get_datetime_string_from_system(false, true)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return OK


## Replaces the current profile with one exported by export_to (or a copy of profile.json).
## Returns "" on success or a message saying what is wrong with the file; nothing changes then.
func import_from(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "That file doesn't exist."
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return "That isn't a Timbum progress file."
	var d: Dictionary = parsed
	if not (d.has("timbum_profile") or d.has("version")) or not d.has("coins") or not d.has("owned"):
		return "That isn't a Timbum progress file."
	if _num(d.get("version"), SAVE_VERSION) > SAVE_VERSION:
		return "That file is from a newer version of Timbum."
	load_from_dict(d)
	_apply_bindings()
	apply_settings()
	save()
	changed.emit()
	return ""


func load_profile() -> void:
	if not persist or not FileAccess.file_exists(SAVE_PATH):
		player_name = "Player%d" % (randi() % 900 + 100)
		# Keep the generated name from changing every launch until something else saves.
		save()
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Profile file is corrupt; backing it up and starting fresh.")
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_PATH + ".bak"))
		player_name = "Player%d" % (randi() % 900 + 100)
		save()
		return
	load_from_dict(parsed)


## Saved number or `fallback` when the value is missing or not a number (JSON numbers are floats).
static func _num(v: Variant, fallback: int) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else fallback


## Merges a saved dictionary over defaults and repairs anything invalid.
func load_from_dict(d: Dictionary) -> void:
	var loaded_name := sanitize_name(str(d.get("player_name", "")))
	player_name = loaded_name if not loaded_name.is_empty() else "Player"
	coins = maxi(0, _num(d.get("coins"), coins))
	xp = maxi(0, _num(d.get("xp"), 0))
	level = maxi(1, _num(d.get("level"), 1))
	last_daily = _num(d.get("last_daily"), 0)
	owned = {}
	var saved_owned: Variant = d.get("owned", {})
	if typeof(saved_owned) == TYPE_DICTIONARY:
		for cat: String in Data.CATEGORIES:
			var ids: Array = []
			var saved_ids: Variant = saved_owned.get(cat, [])
			if typeof(saved_ids) != TYPE_ARRAY:
				saved_ids = []
			for id: Variant in saved_ids:
				if Data.catalog(cat).has(str(id)) and not ids.has(str(id)):
					ids.append(str(id))
			owned[cat] = ids
	settings = DEFAULT_SETTINGS.duplicate()
	var saved_settings: Variant = d.get("settings", {})
	if typeof(saved_settings) == TYPE_DICTIONARY:
		for key: Variant in saved_settings:
			# Only accept a value of the same kind as the default (ints and floats interchange).
			var want := typeof(DEFAULT_SETTINGS.get(key))
			var got := typeof(saved_settings[key])
			var numeric := want in [TYPE_INT, TYPE_FLOAT] and got in [TYPE_INT, TYPE_FLOAT]
			if settings.has(key) and (got == want or numeric):
				settings[key] = int(saved_settings[key]) if want == TYPE_INT and numeric else saved_settings[key]
	settings.quality = clampi(int(settings.quality), 0, 2)
	# Saves from before the per-effect toggles take them from their quality preset.
	var preset: Dictionary = QUALITY_PRESETS[settings.quality]
	for key: String in preset:
		if typeof(saved_settings) != TYPE_DICTIONARY or not (saved_settings as Dictionary).has(key):
			settings[key] = preset[key]
	settings.anti_aliasing = clampi(int(settings.anti_aliasing), 0, ANTI_ALIASING_NAMES.size() - 1)
	settings.render_scale = clampf(float(settings.render_scale), 0.5, 1.0)
	settings.fov = clampf(float(settings.fov), 60.0, 110.0)
	settings.mouse_sens = clampf(float(settings.mouse_sens), 0.05, 10.0)
	settings.ads_sens_mult = clampf(float(settings.ads_sens_mult), 0.05, 3.0)
	for key: String in ["master_volume", "music_volume", "sfx_volume"]:
		settings[key] = clampf(float(settings[key]), 0.0, 1.0)
	if not Color.html_is_valid(str(settings.crosshair_color)):
		settings.crosshair_color = DEFAULT_SETTINGS.crosshair_color
	stats = DEFAULT_STATS.duplicate()
	var saved_stats: Variant = d.get("stats", {})
	if typeof(saved_stats) == TYPE_DICTIONARY:
		for key: Variant in saved_stats:
			if stats.has(key):
				stats[key] = maxi(0, _num(saved_stats[key], 0))
	var saved_loadout: Variant = d.get("loadout", {})
	loadout = {"primary": "smg", "secondary": "pistol", "tactical": "flash"}
	if typeof(saved_loadout) == TYPE_DICTIONARY:
		for slot in ["primary", "secondary"]:
			var id := str(saved_loadout.get(slot, ""))
			if is_owned("weapons", id) and Data.WEAPONS[id].slot == slot:
				loadout[slot] = id
		if Data.TACTICALS.has(str(saved_loadout.get("tactical", ""))):
			loadout.tactical = str(saved_loadout.tactical)
	var saved_eq: Variant = d.get("equipped", {})
	equipped = DEFAULT_EQUIPPED.duplicate()
	if typeof(saved_eq) == TYPE_DICTIONARY:
		for slot: String in EQUIP_SLOTS:
			var id := str(saved_eq.get(slot, ""))
			if is_owned(EQUIP_SLOTS[slot], id):
				equipped[slot] = id
	upgrades = {}
	var saved_up: Variant = d.get("upgrades", {})
	if typeof(saved_up) == TYPE_DICTIONARY:
		for id: String in Data.ATTACHMENTS:
			var lvl := clampi(_num(saved_up.get(id), 0), 0, int(Data.ATTACHMENTS[id].max))
			if lvl > 0:
				upgrades[id] = lvl
	# Per-weapon stats, mastery and prestige (saves from before them start empty / at rank 0).
	weapon_stats = clean_weapon_stats(d.get("weapon_stats", {}))
	mastery_paid = {}
	var saved_paid: Variant = d.get("mastery_paid", {})
	if typeof(saved_paid) == TYPE_DICTIONARY:
		for id: String in Data.WEAPONS:
			var t := clampi(_num(saved_paid.get(id), 0), 0, Data.MASTERY_TIERS.size())
			if t > 0:
				mastery_paid[id] = t
	camos = []
	var saved_camos: Variant = d.get("camos", [])
	if typeof(saved_camos) == TYPE_ARRAY:
		for id: Variant in saved_camos:
			if has_camo(str(id)) and not camos.has(str(id)):
				camos.append(str(id))
	prestige = clampi(_num(d.get("prestige"), 0), 0, Data.PRESTIGE_MAX)
	# Challenges (saves from before them get today's sets at the next refresh).
	challenges = {}
	var saved_ch: Variant = d.get("challenges", {})
	if typeof(saved_ch) == TYPE_DICTIONARY:
		for kind: String in Challenges.KINDS:
			var c: Variant = (saved_ch as Dictionary).get(kind)
			if typeof(c) != TYPE_DICTIONARY or typeof((c as Dictionary).get("list")) != TYPE_ARRAY:
				continue
			var list: Array = []
			for raw: Variant in c.list:
				var ch := Challenges.sanitize(raw, kind)
				if not ch.is_empty():
					list.append(ch)
			challenges[kind] = {"period": _num(c.get("period"), 0), "list": list}
	feats = {}
	var saved_feats: Variant = d.get("feats", {})
	if typeof(saved_feats) == TYPE_DICTIONARY:
		for key: Variant in saved_feats:
			var v := _num(saved_feats[key], 0)
			if _is_feat_key(str(key)) and v > 0:
				feats[str(key)] = v
	achievements = {}
	var saved_ach: Variant = d.get("achievements", {})
	if typeof(saved_ach) == TYPE_DICTIONARY:
		for id: Variant in saved_ach:
			var at := _num(saved_ach[id], 0)
			if Data.ACHIEVEMENTS.has(str(id)) and at > 0:
				achievements[str(id)] = at
	# Saves from before achievements: what their stats already reach unlocks now.
	_unlock_achievements()
	_load_bindings(d.get("bindings", {}))


# ---------------------------------------------------------------- input

## Default bindings, action -> codes. A code is "k<physical keycode>" or "m<mouse button index>".
## Players can rebind every action except "pause" (Esc must always reach the menus).
const DEFAULT_BINDINGS := {
	"move_forward": ["k%d" % KEY_W, "k%d" % KEY_UP], "move_back": ["k%d" % KEY_S, "k%d" % KEY_DOWN],
	"move_left": ["k%d" % KEY_A, "k%d" % KEY_LEFT], "move_right": ["k%d" % KEY_D, "k%d" % KEY_RIGHT],
	"jump": ["k%d" % KEY_SPACE], "sprint": ["k%d" % KEY_SHIFT], "crouch": ["k%d" % KEY_CTRL, "k%d" % KEY_C],
	"prone": ["k%d" % KEY_Z],
	"lean_left": ["k%d" % KEY_Q], "lean_right": ["k%d" % KEY_E],
	"fire": ["m%d" % MOUSE_BUTTON_LEFT], "aim": ["m%d" % MOUSE_BUTTON_RIGHT],
	"reload": ["k%d" % KEY_R], "weapon_1": ["k%d" % KEY_1], "weapon_2": ["k%d" % KEY_2],
	"weapon_3": ["k%d" % KEY_3], "quick_swap": ["k%d" % KEY_X],
	"next_weapon": ["m%d" % MOUSE_BUTTON_WHEEL_DOWN], "prev_weapon": ["m%d" % MOUSE_BUTTON_WHEEL_UP],
	"grenade": ["k%d" % KEY_G], "tactical": ["k%d" % KEY_H], "melee": ["k%d" % KEY_V],
	"grapple": ["k%d" % KEY_F], "streak_reward": ["k%d" % KEY_4], "ping": ["m%d" % MOUSE_BUTTON_MIDDLE],
	"interact": ["k%d" % KEY_B], "tactical_map": ["k%d" % KEY_M],
	"scoreboard": ["k%d" % KEY_TAB], "chat": ["k%d" % KEY_T, "k%d" % KEY_ENTER],
	"pause": ["k%d" % KEY_ESCAPE],
}
## Bindings per action; at most this many codes each.
const MAX_BINDINGS := 2

## action -> Array of codes, for actions the player has rebound (others use DEFAULT_BINDINGS).
var bindings := {}


## Codes currently bound to `action`.
func get_binding(action: String) -> Array:
	return bindings.get(action, DEFAULT_BINDINGS.get(action, []))


## True for codes a player may bind: well-formed, and never Esc (reserved for the menus).
static func is_bindable(code: String) -> bool:
	return code != "k%d" % KEY_ESCAPE and event_from_code(code) != null


## Binds `code` to `action` in slot `index` (0 primary, 1 alternate). The code is taken away from
## any other action, so one key never does two things. An empty `code` clears the slot.
func set_binding(action: String, index: int, code: String) -> void:
	if not DEFAULT_BINDINGS.has(action) or action == "pause" or index < 0 or index >= MAX_BINDINGS:
		return
	if not code.is_empty():
		if not is_bindable(code):
			return
		for other: String in DEFAULT_BINDINGS:
			if other != action and get_binding(other).has(code):
				var stripped := get_binding(other).duplicate()
				stripped.erase(code)
				bindings[other] = stripped
	var list := get_binding(action).duplicate()
	list.erase(code)
	while list.size() <= index:
		list.append("")
	list[index] = code
	bindings[action] = list.filter(func(c: String) -> bool: return not c.is_empty())
	_apply_bindings()
	save()
	changed.emit()


func reset_bindings() -> void:
	bindings = {}
	_apply_bindings()
	save()
	changed.emit()


## "k87" -> InputEventKey (physical W), "m1" -> InputEventMouseButton; null if malformed.
static func event_from_code(code: String) -> InputEvent:
	if code.length() < 2 or not code.substr(1).is_valid_int():
		return null
	var n := code.substr(1).to_int()
	match code[0]:
		"k":
			if n <= 0:
				return null
			var ev := InputEventKey.new()
			ev.physical_keycode = n as Key
			return ev
		"m":
			if n <= 0 or n > MOUSE_BUTTON_XBUTTON2:
				return null
			var mb := InputEventMouseButton.new()
			mb.button_index = n as MouseButton
			return mb
	return null


## Code for a key or mouse press the player made while rebinding ("" if it can't be bound).
static func code_from_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var phys := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return "" if phys == KEY_NONE else "k%d" % phys
	if ev is InputEventMouseButton:
		return "m%d" % (ev as InputEventMouseButton).button_index
	return ""


## Human-readable name of a binding code, e.g. "SHIFT", "MOUSE 4".
static func code_text(code: String) -> String:
	var ev := event_from_code(code)
	return binding_text(ev) if ev != null else "-"


## Name of the first key bound to `action` for on-screen hints ("" when unbound).
func key_text(action: String) -> String:
	var codes := get_binding(action)
	return code_text(codes[0]) if not codes.is_empty() else ""


## Human-readable name of an input binding.
static func binding_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		# Bindings are physical (layout-independent); show the key cap of the user's layout. The
		# headless display server can't map layouts, so it falls back to the QWERTY name.
		var code := k.keycode if k.physical_keycode == KEY_NONE else k.physical_keycode
		if k.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
		return OS.get_keycode_string(code).to_upper()
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "LEFT MOUSE"
			MOUSE_BUTTON_RIGHT: return "RIGHT MOUSE"
			MOUSE_BUTTON_MIDDLE: return "MIDDLE MOUSE"
			MOUSE_BUTTON_WHEEL_UP: return "WHEEL UP"
			MOUSE_BUTTON_WHEEL_DOWN: return "WHEEL DOWN"
			MOUSE_BUTTON_WHEEL_LEFT: return "WHEEL LEFT"
			MOUSE_BUTTON_WHEEL_RIGHT: return "WHEEL RIGHT"
			MOUSE_BUTTON_XBUTTON1: return "MOUSE 4"
			MOUSE_BUTTON_XBUTTON2: return "MOUSE 5"
	return ev.as_text().to_upper()


func _apply_bindings() -> void:
	for action: String in DEFAULT_BINDINGS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		for code: String in get_binding(action):
			var ev := event_from_code(code)
			if ev != null:
				InputMap.action_add_event(action, ev)


## Keeps saved bindings for known actions with valid, unique codes; anything else falls back to
## the defaults.
func _load_bindings(saved: Variant) -> void:
	bindings = {}
	if typeof(saved) == TYPE_DICTIONARY:
		var used := {}
		for action: Variant in saved:
			if not DEFAULT_BINDINGS.has(str(action)) or str(action) == "pause" or typeof(saved[action]) != TYPE_ARRAY:
				continue
			var list: Array = []
			for code: Variant in saved[action]:
				var c := str(code)
				if is_bindable(c) and not used.has(c) and list.size() < MAX_BINDINGS:
					used[c] = true
					list.append(c)
			bindings[str(action)] = list
		# A default key the player never rebound may now also be bound elsewhere; drop it there.
		for action: String in DEFAULT_BINDINGS:
			if bindings.has(action):
				continue
			var defaults: Array = DEFAULT_BINDINGS[action]
			if defaults.any(func(c: String) -> bool: return used.has(c)):
				bindings[action] = defaults.filter(func(c: String) -> bool: return not used.has(c))
	_apply_bindings()
