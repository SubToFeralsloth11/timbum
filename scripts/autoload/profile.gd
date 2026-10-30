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


## result: {kills, deaths, headshots, placement (1-based), players, won, best_streak}
## Returns {coins, xp, levels_gained, breakdown}; breakdown is [[label, coins, xp], ...], one row
## per source, in the order the results screen lists them.
func record_match(result: Dictionary) -> Dictionary:
	var kills := int(result.get("kills", 0))
	var heads := int(result.get("headshots", 0))
	var placement := int(result.get("placement", 99))
	# Placement rewards, the victory bonus and the win stat need someone to beat.
	var contested := int(result.get("players", 1)) > 1
	var won := bool(result.get("won", false)) and contested
	var breakdown: Array = [["Match played", Data.COINS_PARTICIPATION, Data.XP_MATCH]]
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
	var earned := 0
	var gained_xp := 0
	for row: Array in breakdown:
		earned += int(row[1])
		gained_xp += int(row[2])
	xp += gained_xp
	var levels := 0
	while xp >= xp_for_level(level):
		xp -= xp_for_level(level)
		level += 1
		levels += 1
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
	save()
	changed.emit()
	return {"coins": earned, "xp": gained_xp, "levels_gained": levels, "breakdown": breakdown}


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
