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
	"show_fps": false,
	"crosshair_color": "ffffff",
	"last_ip": "127.0.0.1",
	"last_port": 7777,
}

const DEFAULT_STATS := {
	"kills": 0, "deaths": 0, "headshots": 0, "matches": 0, "wins": 0,
	"best_streak": 0, "coins_earned": 0,
}

var player_name := "Player"
var coins := 500
var xp := 0
var level := 1
var owned := {}
var loadout := {"primary": "smg", "secondary": "pistol"}
var equipped := {"skin": "default", "hat": "none", "outfit": "classic"}
var settings := DEFAULT_SETTINGS.duplicate()
var stats := DEFAULT_STATS.duplicate()
var last_daily := 0

## Set to false by tests so they never touch the real save file.
var persist := true


func _ready() -> void:
	_register_input()
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
			return loadout.values().has(id)
		"skins":
			return equipped.skin == id
		"hats":
			return equipped.hat == id
		"outfits":
			return equipped.outfit == id
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
		"skins":
			equipped.skin = id
		"hats":
			equipped.hat = id
		"outfits":
			equipped.outfit = id
		_:
			return false
	save()
	changed.emit()
	return true


func peer_info() -> Dictionary:
	return {
		"name": player_name,
		"outfit": equipped.outfit,
		"hat": equipped.hat,
		"skin": equipped.skin,
		"primary": loadout.primary,
		"secondary": loadout.secondary,
		"level": level,
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
	return Time.get_unix_time_from_system() - last_daily >= 86400


func seconds_until_daily() -> int:
	return maxi(0, int(86400 - (Time.get_unix_time_from_system() - last_daily)))


func claim_daily() -> int:
	if not can_claim_daily():
		return 0
	last_daily = int(Time.get_unix_time_from_system())
	coins += Data.DAILY_REWARD
	stats.coins_earned += Data.DAILY_REWARD
	save()
	changed.emit()
	return Data.DAILY_REWARD


## result: {kills, deaths, headshots, placement (1-based), players, won, best_streak}
func record_match(result: Dictionary) -> Dictionary:
	var kills := int(result.get("kills", 0))
	var heads := int(result.get("headshots", 0))
	var placement := int(result.get("placement", 99))
	var won := bool(result.get("won", false))
	var earned := Data.COINS_PARTICIPATION + kills * Data.COINS_PER_KILL + heads * Data.COINS_PER_HEADSHOT
	if placement >= 1 and placement <= Data.COINS_PLACEMENT.size() and int(result.get("players", 1)) > 1:
		earned += Data.COINS_PLACEMENT[placement - 1]
	var gained_xp := Data.XP_MATCH + kills * Data.XP_PER_KILL + heads * Data.XP_PER_HEADSHOT
	if won:
		gained_xp += 200
	xp += gained_xp
	var levels := 0
	while xp >= xp_for_level(level):
		xp -= xp_for_level(level)
		level += 1
		levels += 1
		earned += Data.COINS_PER_LEVEL
	coins += earned
	stats.kills += kills
	stats.deaths += int(result.get("deaths", 0))
	stats.headshots += heads
	stats.matches += 1
	stats.wins += 1 if won else 0
	stats.best_streak = maxi(int(stats.best_streak), int(result.get("best_streak", 0)))
	stats.coins_earned += earned
	save()
	changed.emit()
	return {"coins": earned, "xp": gained_xp, "levels_gained": levels}


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
	var payload := {
		"version": SAVE_VERSION,
		"player_name": player_name, "coins": coins, "xp": xp, "level": level,
		"owned": owned, "loadout": loadout, "equipped": equipped,
		"settings": settings, "stats": stats, "last_daily": last_daily,
	}
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save profile: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(SAVE_PATH))


func load_profile() -> void:
	if not persist or not FileAccess.file_exists(SAVE_PATH):
		player_name = "Player%d" % (randi() % 900 + 100)
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Profile file is corrupt; starting fresh.")
		return
	load_from_dict(parsed)


## Merges a saved dictionary over defaults and repairs anything invalid.
func load_from_dict(d: Dictionary) -> void:
	var loaded_name := sanitize_name(str(d.get("player_name", "")))
	player_name = loaded_name if not loaded_name.is_empty() else "Player"
	coins = maxi(0, int(d.get("coins", coins)))
	xp = maxi(0, int(d.get("xp", 0)))
	level = maxi(1, int(d.get("level", 1)))
	last_daily = int(d.get("last_daily", 0))
	owned = {}
	var saved_owned: Variant = d.get("owned", {})
	if typeof(saved_owned) == TYPE_DICTIONARY:
		for cat: String in Data.CATEGORIES:
			var ids: Array = []
			for id in saved_owned.get(cat, []):
				if Data.catalog(cat).has(str(id)) and not ids.has(str(id)):
					ids.append(str(id))
			owned[cat] = ids
	settings = DEFAULT_SETTINGS.duplicate()
	var saved_settings: Variant = d.get("settings", {})
	if typeof(saved_settings) == TYPE_DICTIONARY:
		for key: String in saved_settings:
			if settings.has(key) and typeof(saved_settings[key]) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING]:
				settings[key] = saved_settings[key]
	settings.quality = clampi(int(settings.quality), 0, 2)
	stats = DEFAULT_STATS.duplicate()
	var saved_stats: Variant = d.get("stats", {})
	if typeof(saved_stats) == TYPE_DICTIONARY:
		for key: String in saved_stats:
			if stats.has(key):
				stats[key] = int(saved_stats[key])
	var saved_loadout: Variant = d.get("loadout", {})
	loadout = {"primary": "smg", "secondary": "pistol"}
	if typeof(saved_loadout) == TYPE_DICTIONARY:
		for slot in ["primary", "secondary"]:
			var id := str(saved_loadout.get(slot, ""))
			if is_owned("weapons", id) and Data.WEAPONS[id].slot == slot:
				loadout[slot] = id
	var saved_eq: Variant = d.get("equipped", {})
	equipped = {"skin": "default", "hat": "none", "outfit": "classic"}
	if typeof(saved_eq) == TYPE_DICTIONARY:
		for pair in [["skin", "skins"], ["hat", "hats"], ["outfit", "outfits"]]:
			var id := str(saved_eq.get(pair[0], ""))
			if is_owned(pair[1], id):
				equipped[pair[0]] = id


# ---------------------------------------------------------------- input

func _register_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C],
		"reload": [KEY_R], "weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
		"quick_swap": [KEY_Q], "grenade": [KEY_G], "melee": [KEY_V, KEY_F],
		"scoreboard": [KEY_TAB], "chat": [KEY_T, KEY_ENTER], "pause": [KEY_ESCAPE],
	}
	for action: String in keys:
		_ensure_action(action)
		for k: Key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var buttons := {
		"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT,
		"next_weapon": MOUSE_BUTTON_WHEEL_DOWN, "prev_weapon": MOUSE_BUTTON_WHEEL_UP,
	}
	for action: String in buttons:
		_ensure_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = buttons[action]
		InputMap.action_add_event(action, mb)


func _ensure_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
