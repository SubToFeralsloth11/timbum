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
	## Controller: look speed, invert, stick deadzone (radial, 0..0.5), response curve
	## (PAD_CURVES index) and aim assist (AimAssist.LEVEL_NAMES index; offline matches only).
	"pad_sens": 1.0,
	"pad_invert_y": false,
	"pad_deadzone": 0.15,
	"pad_curve": 1,
	"aim_assist": 2,
	"master_volume": 0.8,
	"music_volume": 0.45,
	"sfx_volume": 0.85,
	## Silence the Master bus while the game window doesn't have focus (also in menus).
	"mute_unfocused": true,
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
	## Kill cam: replay the killer's view of your death before the death screen (KillCam).
	"killcam": true,
	## Accessibility colour mode (Palette.MODE_NAMES index).
	"color_mode": 0,
	## Crosshair editor (Settings > Crosshair, drawn by `Crosshair`): style (Crosshair.STYLE_NAMES
	## index), line length, gap and thickness in pixels, outline, centre dot, dynamic spread (gap
	## follows the spread cone), colour and opacity. The defaults are the original crosshair.
	"crosshair_style": 0,
	"crosshair_size": 9.0,
	"crosshair_gap": 4.0,
	"crosshair_thickness": 2.0,
	"crosshair_outline": true,
	"crosshair_dot": true,
	"crosshair_dynamic": true,
	"crosshair_color": "ffffff",
	"crosshair_opacity": 1.0,
	"last_ip": "127.0.0.1",
	"last_port": 7777,
	"last_code": "",
}

const ANTI_ALIASING_NAMES: Array[String] = ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "TAA"]
## Controller stick response curves: [name, exponent]. The stick's travel past the deadzone (0..1)
## is raised to the exponent, so higher curves give finer control near the centre.
const PAD_CURVES: Array = [["Linear", 1.0], ["Classic", 1.8], ["Precise", 2.8]]
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
const DEFAULT_LOADOUT := {"primary": "smg", "secondary": "pistol", "tactical": "flash", "melee": "knife"}
## Loadout slot keys a preset holds (besides its name). A save from before melee weapons has no
## "melee" and loads with the knife (_clean_loadout keeps the base's).
const LOADOUT_KEYS: Array[String] = ["primary", "secondary", "tactical", "melee"]
## The loadout the player spawns with: always a copy of the active preset's guns
## (`loadout_presets[active_preset]`); equip() edits both, select_preset() copies a preset here.
var loadout := DEFAULT_LOADOUT.duplicate()
## Loadout presets: LOADOUT_PRESET_COUNT of {name, primary, secondary, tactical, melee}, picked in the
## locker, on the death screen and on the results screen (see select_preset).
const LOADOUT_PRESET_COUNT := 3
var loadout_presets: Array = fresh_presets(DEFAULT_LOADOUT)
var active_preset := 0
const DEFAULT_EQUIPPED := {"skin": "default", "hat": "none", "outfit": "classic", "charm": "none", "emote": "wave", "draw": "standard", "spray": "gg"}
## Equipped slot -> catalog category.
const EQUIP_SLOTS := {"skin": "skins", "hat": "hats", "outfit": "outfits", "charm": "charms", "emote": "emotes", "draw": "draws", "spray": "sprays"}
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
## Match setup presets: up to MAX_MATCH_PRESETS of {name, settings} where settings are
## MatchSetupScreen choices (sanitized with MatchSetupScreen.sanitize_choice on load).
var match_presets: Array = []
const MAX_MATCH_PRESETS := 8
## First-run tutorial: whether the main menu has offered it (a new profile starts false; saves
## from before the tutorial load as true, so returning players aren't asked) and whether its
## one-time Data.TUTORIAL_REWARD was paid.
var tutorial_offered := false
var tutorial_paid := false

## Set to false by tests so they never touch the real save file.
var persist := true


func _ready() -> void:
	_add_menu_pad_events()
	_apply_bindings()
	load_profile()
	apply_settings()
	get_tree().root.window_input.connect(_note_device)
	get_tree().root.focus_exited.connect(_on_window_focus.bind(false))
	get_tree().root.focus_entered.connect(_on_window_focus.bind(true))


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
			return loadout.primary == id or loadout.secondary == id or loadout.melee == id
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
			loadout[slot] = id
			loadout_presets[active_preset][slot] = id
		"tacticals":
			loadout.tactical = id
			loadout_presets[active_preset].tactical = id
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
		"spray": equipped.spray,
		"mods": upgrades.duplicate(),
		"primary": loadout.primary,
		"secondary": loadout.secondary,
		"tactical": loadout.tactical,
		"melee": loadout.melee,
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
func owned_guns() -> Array[String]:
	var out: Array[String] = []
	for id: String in Data.WEAPONS:
		if is_owned("weapons", id):
			out.append(id)
	return out

## Weapon ids the player owns that fit `slot` ("primary", "secondary", "melee").
func owned_weapons_for_slot(slot: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in Data.WEAPONS:
		if Data.WEAPONS[id].slot == slot and is_owned("weapons", id):
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


# ---------------------------------------------------------------- tutorial

## The main menu's first-launch offer was answered (or the tutorial started): don't ask again.
func mark_tutorial_offered() -> void:
	if tutorial_offered:
		return
	tutorial_offered = true
	save()


## The tutorial was finished: pays Data.TUTORIAL_REWARD the first time, nothing on a replay.
## Returns the coins paid.
func finish_tutorial() -> int:
	tutorial_offered = true
	if tutorial_paid:
		save()
		return 0
	tutorial_paid = true
	coins += Data.TUTORIAL_REWARD
	stats.coins_earned += Data.TUTORIAL_REWARD
	save()
	changed.emit()
	return Data.TUTORIAL_REWARD


# ---------------------------------------------------------------- match setup presets

## Index of the preset called `preset_name`, or -1.
func match_preset_index(preset_name: String) -> int:
	for i in match_presets.size():
		if match_presets[i].name == preset_name:
			return i
	return -1


## Saves setup `choice` (MatchSetupScreen choices) as preset `preset_name`, replacing a preset of
## that name. Returns its index, or -1 for an empty name or when all MAX_MATCH_PRESETS are taken.
func save_match_preset(preset_name: String, choice: Dictionary) -> int:
	preset_name = sanitize_name(preset_name)
	if preset_name.is_empty():
		return -1
	var entry := {"name": preset_name, "settings": MatchSetupScreen.sanitize_choice(choice)}
	var i := match_preset_index(preset_name)
	if i < 0:
		if match_presets.size() >= MAX_MATCH_PRESETS:
			return -1
		match_presets.append(entry)
		i = match_presets.size() - 1
	else:
		match_presets[i] = entry
	save()
	return i


## False for a bad index, an empty name or a name another preset already has.
func rename_match_preset(index: int, new_name: String) -> bool:
	new_name = sanitize_name(new_name)
	if index < 0 or index >= match_presets.size() or new_name.is_empty():
		return false
	var other := match_preset_index(new_name)
	if other >= 0 and other != index:
		return false
	match_presets[index].name = new_name
	save()
	return true


func delete_match_preset(index: int) -> bool:
	if index < 0 or index >= match_presets.size():
		return false
	match_presets.remove_at(index)
	save()
	return true


# ---------------------------------------------------------------- loadout presets

static func default_preset_name(index: int) -> String:
	return "Loadout %d" % (index + 1)


## LOADOUT_PRESET_COUNT presets, each holding the guns of `base`, with the default names.
static func fresh_presets(base: Dictionary) -> Array:
	var out: Array = []
	for i in LOADOUT_PRESET_COUNT:
		var p := {"name": default_preset_name(i)}
		for k: String in LOADOUT_KEYS:
			p[k] = str(base[k])
		out.append(p)
	return out


## Makes preset `index` the active one: its guns become `loadout` (what peer_info sends, so
## Net.update_my_info() hands it to the server for the next spawn). False for a bad index.
func select_preset(index: int) -> bool:
	if index < 0 or index >= loadout_presets.size():
		return false
	active_preset = index
	for k: String in LOADOUT_KEYS:
		loadout[k] = str(loadout_presets[index][k])
	save()
	changed.emit()
	return true


## False for a bad index or an empty name (names may repeat: presets are picked by number).
func rename_preset(index: int, new_name: String) -> bool:
	new_name = sanitize_name(new_name)
	if index < 0 or index >= loadout_presets.size() or new_name.is_empty():
		return false
	loadout_presets[index].name = new_name
	save()
	changed.emit()
	return true


## "Bit-SMG · Block 9 · Flash Cube · Pixel Blade" for preset `index`.
func preset_summary(index: int) -> String:
	var p: Dictionary = loadout_presets[index]
	return "%s  ·  %s  ·  %s  ·  %s" % [Data.WEAPONS[p.primary].name, Data.WEAPONS[p.secondary].name, Data.TACTICALS[p.tactical].name,
		Data.WEAPONS[p.melee].name]


## Repairs saved loadout slots over `base`: a gun the player doesn't own or that doesn't fit the
## slot, or an unknown tactical, keeps base's.
func _clean_loadout(saved: Variant, base: Dictionary) -> Dictionary:
	var out := base.duplicate()
	if typeof(saved) != TYPE_DICTIONARY:
		return out
	for slot: String in ["primary", "secondary", "melee"]:
		var id := str(saved.get(slot, ""))
		if is_owned("weapons", id) and Data.WEAPONS[id].slot == slot:
			out[slot] = id
	if Data.TACTICALS.has(str(saved.get("tactical", ""))):
		out.tactical = str(saved.tactical)
	return out


# ---------------------------------------------------------------- settings

func get_setting(key: String) -> Variant:
	return settings.get(key, DEFAULT_SETTINGS.get(key))


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()
	save()
	changed.emit()


func apply_settings() -> void:
	_apply_master()
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


## The game window has focus. Clicking away, alt-tabbing or minimising clears it; with the
## "mute_unfocused" setting the Master bus is muted until the window gets focus back.
var window_focused := true


func _on_window_focus(focused: bool) -> void:
	window_focused = focused
	_apply_master()


func _apply_master() -> void:
	_set_bus_volume("Master", float(get_setting("master_volume")))
	if not window_focused and get_setting("mute_unfocused"):
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)


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
		"settings": settings, "stats": stats, "last_daily": last_daily, "bindings": bindings, "pad_bindings": pad_bindings,
		"weapon_stats": weapon_stats, "mastery_paid": mastery_paid, "camos": camos, "prestige": prestige,
		"challenges": challenges, "feats": feats, "achievements": achievements, "match_presets": match_presets,
		"loadout_presets": loadout_presets, "active_preset": active_preset,
		"tutorial_offered": tutorial_offered, "tutorial_paid": tutorial_paid,
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
	settings.pad_sens = clampf(float(settings.pad_sens), 0.1, 5.0)
	settings.pad_deadzone = clampf(float(settings.pad_deadzone), 0.0, 0.5)
	settings.pad_curve = clampi(int(settings.pad_curve), 0, PAD_CURVES.size() - 1)
	settings.aim_assist = clampi(int(settings.aim_assist), 0, 2)
	settings.color_mode = clampi(int(settings.color_mode), 0, Palette.MODE_NAMES.size() - 1)
	settings.ads_sens_mult = clampf(float(settings.ads_sens_mult), 0.05, 3.0)
	for key: String in ["master_volume", "music_volume", "sfx_volume"]:
		settings[key] = clampf(float(settings[key]), 0.0, 1.0)
	if not Color.html_is_valid(str(settings.crosshair_color)):
		settings.crosshair_color = DEFAULT_SETTINGS.crosshair_color
	settings.crosshair_style = clampi(int(settings.crosshair_style), 0, Crosshair.STYLE_NAMES.size() - 1)
	settings.crosshair_size = clampf(float(settings.crosshair_size), 2.0, 30.0)
	settings.crosshair_gap = clampf(float(settings.crosshair_gap), 0.0, 20.0)
	settings.crosshair_thickness = clampf(float(settings.crosshair_thickness), 1.0, 6.0)
	settings.crosshair_opacity = clampf(float(settings.crosshair_opacity), 0.1, 1.0)
	stats = DEFAULT_STATS.duplicate()
	var saved_stats: Variant = d.get("stats", {})
	if typeof(saved_stats) == TYPE_DICTIONARY:
		for key: Variant in saved_stats:
			if stats.has(key):
				stats[key] = maxi(0, _num(saved_stats[key], 0))
	loadout = _clean_loadout(d.get("loadout", {}), DEFAULT_LOADOUT)
	# Loadout presets: a save from before them gets the loadout it had in every preset (so preset 1
	# is the current loadout); a broken entry falls back to that loadout and its default name.
	var saved_lp: Variant = d.get("loadout_presets", [])
	var base := loadout.duplicate()
	loadout_presets = fresh_presets(base)
	if typeof(saved_lp) == TYPE_ARRAY:
		for i in mini((saved_lp as Array).size(), LOADOUT_PRESET_COUNT):
			var raw: Variant = saved_lp[i]
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var entry := _clean_loadout(raw, base)
			var preset_name := sanitize_name(str((raw as Dictionary).get("name", "")))
			entry.name = preset_name if not preset_name.is_empty() else default_preset_name(i)
			loadout_presets[i] = entry
	active_preset = clampi(_num(d.get("active_preset"), 0), 0, LOADOUT_PRESET_COUNT - 1)
	for k: String in LOADOUT_KEYS:
		loadout[k] = str(loadout_presets[active_preset][k])
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
	# A save from before the tutorial belongs to someone who has played: no first-launch offer.
	var offered: Variant = d.get("tutorial_offered", true)
	tutorial_offered = offered if typeof(offered) == TYPE_BOOL else true
	var paid: Variant = d.get("tutorial_paid", false)
	tutorial_paid = paid if typeof(paid) == TYPE_BOOL else false
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
	# Match setup presets (saves from before them have none); a value the setup screen no longer
	# offers falls back to its default, a repeated name or anything past the limit is dropped.
	match_presets = []
	var saved_presets: Variant = d.get("match_presets", [])
	if typeof(saved_presets) == TYPE_ARRAY:
		for raw: Variant in saved_presets:
			if typeof(raw) != TYPE_DICTIONARY or match_presets.size() >= MAX_MATCH_PRESETS:
				continue
			var preset_name := sanitize_name(str((raw as Dictionary).get("name", "")))
			if not preset_name.is_empty() and match_preset_index(preset_name) < 0:
				match_presets.append({"name": preset_name, "settings": MatchSetupScreen.sanitize_choice((raw as Dictionary).get("settings"))})
	# Saves from before achievements: what their stats already reach unlocks now.
	_unlock_achievements()
	_load_pad_bindings(d.get("pad_bindings", {}))
	_load_bindings(d.get("bindings", {}))


# ---------------------------------------------------------------- input

## Default keyboard and mouse bindings, action -> codes. A code is "k<physical keycode>" or
## "m<mouse button index>". Players can rebind every action except "pause" (Esc must always reach
## the menus). The look_* actions turn the camera like the right stick (unbound on the keyboard).
const DEFAULT_BINDINGS := {
	"move_forward": ["k%d" % KEY_W, "k%d" % KEY_UP], "move_back": ["k%d" % KEY_S, "k%d" % KEY_DOWN],
	"move_left": ["k%d" % KEY_A, "k%d" % KEY_LEFT], "move_right": ["k%d" % KEY_D, "k%d" % KEY_RIGHT],
	"look_up": [], "look_down": [], "look_left": [], "look_right": [],
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
	"skip_killcam": ["k%d" % KEY_K],
	"spectate_view": ["k%d" % KEY_N], "photo_mode": ["k%d" % KEY_P], "inspect": ["k%d" % KEY_I], "spray": ["k%d" % KEY_Y],
	"pause": ["k%d" % KEY_ESCAPE],
}
## Keyboard/mouse bindings per action; at most this many codes each.
const MAX_BINDINGS := 2

## Default controller bindings, action -> one code: "j<joypad button>", or "a<axis>+" / "a<axis>-"
## for a stick direction or a trigger. Godot's SDL layout (Xbox names): buttons A 0, B 1, X 2, Y 3,
## Back 4, Start 6, L3 7, R3 8, LB 9, RB 10, D-pad up/down/left/right 11-14; axes: left stick 0 (x)
## and 1 (y, down is +), right stick 2 and 3, LT 4, RT 5. A pad has 24 inputs for 39 actions, so
## the direct weapon slots, last/previous weapon, peeking, chat, weapon inspect and spray have no
## default (Y cycles the weapons; every button is taken and neither can share one); the player can
## bind them. Start is the pause button and can't be rebound.
const DEFAULT_PAD_BINDINGS := {
	"move_forward": "a1-", "move_back": "a1+", "move_left": "a0-", "move_right": "a0+",
	"look_up": "a3-", "look_down": "a3+", "look_left": "a2-", "look_right": "a2+",
	"jump": "j0", "skip_killcam": "j0", "crouch": "j1", "reload": "j2", "next_weapon": "j3",
	"sprint": "j7", "melee": "j8", "tactical": "j9", "grenade": "j10",
	"aim": "a4+", "fire": "a5+",
	"grapple": "j11", "prone": "j12", "ping": "j13", "streak_reward": "j14",
	"interact": "j2", "tactical_map": "j11", "spectate_view": "j2", "photo_mode": "j15",
	"scoreboard": "j4", "pause": "j6",
}
## Actions that may share one pad button, by default and when rebound, because they never get in
## each other's way: Tactical has no grapple hook (so D-pad up opens its floor plan), a gun
## swapped in at a Tactical weapon spot comes with a full magazine (so the reload that goes with
## X's swap does nothing), the kill cam only plays while you are dead (so A skips it), and a
## spectator (who has no gun to reload or swap) switches the camera view with X.
const PAD_SHARED: Array = [["reload", "interact"], ["grapple", "tactical_map"], ["jump", "skip_killcam"],
	["reload", "spectate_view"], ["interact", "spectate_view"]]
## Start: the pad's pause button, reserved like Esc.
const PAD_PAUSE := "j6"
## On-screen names of the pad buttons (JoyButton index) and axes ([negative, positive]).
const PAD_BUTTON_NAMES := {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "BACK", 6: "START", 7: "L3", 8: "R3", 9: "LB", 10: "RB",
	11: "D-PAD UP", 12: "D-PAD DOWN", 13: "D-PAD LEFT", 14: "D-PAD RIGHT", 15: "SHARE",
	16: "PADDLE 1", 17: "PADDLE 2", 18: "PADDLE 3", 19: "PADDLE 4", 20: "TOUCHPAD",
}
const PAD_AXIS_NAMES: Array = [["LS LEFT", "LS RIGHT"], ["LS UP", "LS DOWN"], ["RS LEFT", "RS RIGHT"],
	["RS UP", "RS DOWN"], ["", "LT"], ["", "RT"]]

## Emitted when the player switches between the controller and the keyboard/mouse.
signal device_changed

## action -> Array of codes, for actions the player has rebound (others use DEFAULT_BINDINGS).
var bindings := {}
## action -> pad code ("" = none), for actions the player has rebound on the controller (others
## use DEFAULT_PAD_BINDINGS).
var pad_bindings := {}
## True while the controller was the last device the player touched: key_text shows pad buttons,
## AimAssist may work, and a trigger fires without a captured mouse.
var using_pad := false


## Codes currently bound to `action` on the keyboard and mouse.
func get_binding(action: String) -> Array:
	return bindings.get(action, DEFAULT_BINDINGS.get(action, []))


## The pad code bound to `action` ("" for none).
func get_pad_binding(action: String) -> String:
	return str(pad_bindings.get(action, DEFAULT_PAD_BINDINGS.get(action, "")))


## True for codes a player may bind: well-formed, and never Esc or Start (reserved for the menus).
static func is_bindable(code: String) -> bool:
	return code != "k%d" % KEY_ESCAPE and code != PAD_PAUSE and event_from_code(code) != null


## True for controller codes ("j..." buttons, "a..." axes).
static func is_pad_code(code: String) -> bool:
	return code.begins_with("j") or code.begins_with("a")


## Whether actions `a` and `b` may share one pad button (PAD_SHARED).
static func pad_may_share(a: String, b: String) -> bool:
	for pair: Array in PAD_SHARED:
		if pair.has(a) and pair.has(b):
			return true
	return false


## Binds key/mouse `code` to `action` in slot `index` (0 primary, 1 alternate). The code is taken
## away from any other action, so one key never does two things. An empty `code` clears the slot.
func set_binding(action: String, index: int, code: String) -> void:
	if not DEFAULT_BINDINGS.has(action) or action == "pause" or index < 0 or index >= MAX_BINDINGS:
		return
	if not code.is_empty():
		if not is_bindable(code) or is_pad_code(code):
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


## Binds pad `code` to `action` (one per action). Other actions lose it unless they may share it
## (PAD_SHARED). An empty `code` unbinds the action on the pad.
func set_pad_binding(action: String, code: String) -> void:
	if not DEFAULT_BINDINGS.has(action) or action == "pause":
		return
	if not code.is_empty():
		if not is_bindable(code) or not is_pad_code(code):
			return
		for other: String in DEFAULT_BINDINGS:
			if other != action and other != "pause" and get_pad_binding(other) == code and not pad_may_share(action, other):
				pad_bindings[other] = ""
	pad_bindings[action] = code
	_apply_bindings()
	save()
	changed.emit()


func reset_bindings() -> void:
	bindings = {}
	pad_bindings = {}
	_apply_bindings()
	save()
	changed.emit()


## "k87" -> InputEventKey (physical W), "m1" -> InputEventMouseButton, "j0" ->
## InputEventJoypadButton (A), "a5+" -> InputEventJoypadMotion (RT); null if malformed. Pad events
## match every connected controller.
static func event_from_code(code: String) -> InputEvent:
	if code.length() < 2:
		return null
	if code[0] == "a":
		var axis_text := code.substr(1, code.length() - 2)
		var sign := code[code.length() - 1]
		if not axis_text.is_valid_int() or not (sign == "+" or sign == "-"):
			return null
		var axis := axis_text.to_int()
		# Triggers (LT 4, RT 5) only go one way.
		if axis < 0 or axis >= JOY_AXIS_SDL_MAX or (axis >= JOY_AXIS_TRIGGER_LEFT and sign == "-"):
			return null
		var jm := InputEventJoypadMotion.new()
		jm.device = -1
		jm.axis = axis as JoyAxis
		jm.axis_value = 1.0 if sign == "+" else -1.0
		return jm
	if not code.substr(1).is_valid_int():
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
		"j":
			if n < 0 or n >= JOY_BUTTON_SDL_MAX or n == JOY_BUTTON_GUIDE:
				return null
			var jb := InputEventJoypadButton.new()
			jb.device = -1
			jb.button_index = n as JoyButton
			return jb
	return null


## Code for a key, mouse button, pad button or stick/trigger push the player made while rebinding
## ("" if it can't be bound, or a stick barely moved).
static func code_from_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var phys := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return "" if phys == KEY_NONE else "k%d" % phys
	if ev is InputEventMouseButton:
		return "m%d" % (ev as InputEventMouseButton).button_index
	if ev is InputEventJoypadButton:
		return "j%d" % (ev as InputEventJoypadButton).button_index
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		if absf(jm.axis_value) < 0.6:
			return ""
		return "a%d%s" % [jm.axis, "+" if jm.axis_value > 0.0 else "-"]
	return ""


## Human-readable name of a binding code, e.g. "SHIFT", "MOUSE 4", "RT".
static func code_text(code: String) -> String:
	var ev := event_from_code(code)
	return binding_text(ev) if ev != null else "-"


## Name of what `action` is bound to for on-screen hints ("" when unbound): the pad button while
## the controller is in use (if the action has one), else the first key.
func key_text(action: String) -> String:
	if using_pad:
		var pad := get_pad_binding(action)
		if not pad.is_empty():
			return code_text(pad)
	var codes := get_binding(action)
	return code_text(codes[0]) if not codes.is_empty() else ""


## A stick read through four actions (the pad's axes, or keys bound to them) with the player's
## radial deadzone and response curve: zero inside the deadzone, then the rest of the travel as
## 0..1 raised to the curve's exponent (PAD_CURVES), so small pushes turn finely.
func pad_stick(left: StringName, right: StringName, up: StringName, down: StringName) -> Vector2:
	var v := Vector2(Input.get_action_raw_strength(right) - Input.get_action_raw_strength(left),
		Input.get_action_raw_strength(down) - Input.get_action_raw_strength(up))
	var push := minf(v.length(), 1.0)
	var dead := float(get_setting("pad_deadzone"))
	if push <= dead:
		return Vector2.ZERO
	var travel := (push - dead) / maxf(1.0 - dead, 0.001)
	return v.normalized() * pow(travel, float(PAD_CURVES[int(get_setting("pad_curve"))][1]))


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
	if ev is InputEventJoypadButton:
		var b := int((ev as InputEventJoypadButton).button_index)
		return str(PAD_BUTTON_NAMES.get(b, "PAD %d" % b))
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		return str(PAD_AXIS_NAMES[jm.axis][1 if jm.axis_value > 0.0 else 0])
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
		var pad := event_from_code(get_pad_binding(action))
		if pad != null:
			InputMap.action_add_event(action, pad)


## Menus on the pad: A accepts and B goes back (the D-pad and left stick already move the focus).
func _add_menu_pad_events() -> void:
	for pair: Array in [[&"ui_accept", JOY_BUTTON_A], [&"ui_cancel", JOY_BUTTON_B]]:
		var ev := InputEventJoypadButton.new()
		ev.device = -1
		ev.button_index = pair[1]
		if not InputMap.action_has_event(pair[0], ev):
			InputMap.action_add_event(pair[0], ev)


## Follows the last device the player touched (see using_pad). Every event reaches the window
## first, before any node can consume it.
func _note_device(event: InputEvent) -> void:
	var pad: Variant = null
	if event is InputEventJoypadButton:
		if event.pressed:
			pad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed():
			pad = false
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() > 6.0:
			pad = false
	if pad != null and pad != using_pad:
		using_pad = pad
		device_changed.emit()


## Keeps saved key/mouse bindings for known actions with valid, unique codes; anything else falls
## back to the defaults.
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
				if is_bindable(c) and not is_pad_code(c) and not used.has(c) and list.size() < MAX_BINDINGS:
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


## Keeps saved pad bindings for known actions with valid codes, each used once (or shared as
## PAD_SHARED allows); a default that a rebind took is cleared. Saves from before controller
## support have none and get DEFAULT_PAD_BINDINGS.
func _load_pad_bindings(saved: Variant) -> void:
	pad_bindings = {}
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for action: Variant in saved:
		var a := str(action)
		var c := str(saved[action])
		if not DEFAULT_BINDINGS.has(a) or a == "pause" or not (c.is_empty() or (is_pad_code(c) and is_bindable(c))):
			continue
		if not c.is_empty() and _pad_code_taken(c, a):
			continue
		pad_bindings[a] = c
	for action: String in DEFAULT_PAD_BINDINGS:
		if action != "pause" and not pad_bindings.has(action) and _pad_code_taken(str(DEFAULT_PAD_BINDINGS[action]), action):
			pad_bindings[action] = ""


## Whether a loaded pad binding of another action already holds `code` (and can't share it).
func _pad_code_taken(code: String, action: String) -> bool:
	for other: String in pad_bindings:
		if other != action and pad_bindings[other] == code and not pad_may_share(action, other):
			return true
	return false
