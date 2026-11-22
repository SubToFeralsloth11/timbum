class_name MatchSetupScreen
extends MenuScreen
## Match configuration shared by "Play vs Bots" (offline) and "Host Game" (ENet server).
##
## Everything fits the 1280 x 720 base resolution without scrolling (canvas_items stretch: a bigger
## window only adds room); only the CUSTOM maps below the built-in map cards scroll. The budget:
##   page: 720 - 2 x 28 margins = 664 tall, 1280 - 2 x 40 = 1200 wide (MenuScreen.make_page).
##   top bar: BACK, the title (34 px) over its subtitle (15 px) ~ 66, and on the right the presets
##   strip and its EDIT row (2 x 32 + 4 = 68); then the page's 18 separation:
##   body = 664 - 68 - 18 = 578 tall.
##   Left column, 1200 - 16 - RULES_W = 764 wide:
##     mode cards: MODE_COLUMNS 5 x 3 rows (13 modes) of MODE_CARD_H 52 + 2 x 8 = 172
##     + 8 + the mode's hint (13 px, at most HINT_LINES 3 lines) 54 + 8
##     + MAP heading 28 + 8 + built-in map cards (Rotation and the 10 rotation maps):
##     MAP_COLUMNS 4 x 3 rows of MAP_CARD_H 84 + 2 x 10 = 272
##     = 550 <= 578, the rest shows the top of the CUSTOM heading. A mode's own map (Tactical,
##     Parkour, Bedwars) is one FIXED_MAP_CARD_H 260 card in place of the grid.
##   Right panel, RULES_W wide, 16 padding: 578 - 32 = 546 inside:
##     rule rows: a chip row is 32 (14 px text + 2 x 6 padding), RULE_GAP 6 apart. The most any
##     mode shows is 8 (PLAYERS, BOTS, its limit, TIME, MUTATORS, STREAKS, WEATHER, CUSTOM);
##     hosting adds LINK and up to MAX_ADDRESSES 2 address rows (PORT sits on the last one):
##     11 x 32 + 10 x 6 = 412, + 10 + status (13 px, 2 lines) 36 + 10 + START 50 = 518 <= 546.

const KILL_LIMITS: Array[int] = [10, 15, 20, 30, 50]
## Team Deathmatch's limit is on the team score, so it runs higher.
const TEAM_KILL_LIMITS: Array[int] = [25, 40, 50, 75, 100]
const TIME_LIMITS: Array[int] = [5, 8, 10, 15]
const ROTATION := "rotation"
## Layout (see the budget above).
const RULES_W := 420
const RULE_GAP := 6
const MODE_COLUMNS := 5
const MODE_CARD_H := 52
const HINT_LINES := 3
const MAP_COLUMNS := 4
const MAP_CARD_H := 84
const FIXED_MAP_CARD_H := 260
const START_H := 50
## Host: address rows shown (LAN first, NetLinkAddresses.local_addresses).
const MAX_ADDRESSES := 2

## Last choices this session, shared by both modes. Each mode with its own limit keeps it apart
## (sent as `kill_limit`): the team score, Capture the Flag's captures, the Gun Game ladder length,
## One in the Chamber's lives, King of the Block's points.
## `streaks`: mode -> killstreaks on, once picked for that mode (until then the mode's default,
## Streaks.default_for). A match setup preset (Profile.match_presets) holds a copy of it.
static var _choice := default_choice()
const MODE_IDS: Array[String] = ["ffa", "tdm", "instakill", "ctf", "gungame", "oitc", "koth", "infected", "tag", "hideseek", "blockhunt", "parkour", "bedwars", "tactical"]
const MODE_HINTS := {
	"ffa": "Bots fill every empty slot up to the player count.",
	"tdm": "Two teams, bots fill both evenly. The kill limit is the team score; friendly fire is off.",
	"instakill": "Team Deathmatch where any hit from any weapon kills. The kill limit is the team score; friendly fire is off.",
	"ctf": "Walk over the enemy flag to take it, then onto your own stand while your flag is home to score. Carriers are slower and can't grapple; a dropped flag goes home after 20 s or when its team touches it.",
	"gungame": "Everyone climbs the same ladder of guns, one step per kill, and finishes on the knife. A knife kill also knocks the victim down a step. No grenades; Rocket Party and Snipers Only are off.",
	"oitc": "Everyone has the Cuber .44 with one round and their melee weapon. Any .44 hit kills; every kill gives a round. Out of lives, you watch the rest. Last one standing wins, else the most lives. No grenades, ammo crates, mutators or killstreaks.",
	"koth": "A glowing zone moves every minute (10 s warning). Stand in it alone for a point a second; two or more contest it. First to the score limit wins.",
	"infected": "10 s in, one player turns Infected: melee only (their own melee weapon), faster, tougher. Everyone they kill turns too. Survivors win if any are left at the end. Rocket Party and Snipers Only are off.",
	"tag": "No guns, nobody gets hurt. One player is IT: swing your melee weapon at someone or run into them to make them IT (no tag-backs for 4 s). A point a second while you're not IT, +3 a tag. Most points wins.",
	"hideseek": "One seeker counts blindfolded for 20 s while everyone hides. Catch a hider (swing or bump) and you swap: they seek. No nametags; hiders see the seeker through walls. Hiders score a point a second, catches +10.",
	"blockhunt": "Pick one of 4 blocks from the map and become it; hold still to snap onto the grid. After 30 s one seeker in five hunts with their melee weapon; found hiders seek too. Balloons score 1 / 3 / 7 but light you up. Hiders win if any are left.",
	"parkour": "Race up the Parkour Run: 14 stages over a lava sea, from stepping stones to 1x1 pillars, long jumps and jump pads. Gold pads save your checkpoint; fall and you're straight back on it. First to the finish wins, 20 s later the match ends; else the furthest checkpoint. No guns, no grapple.",
	"bedwars": "Two teams, a bed each. Gather iron, gold, diamonds and emeralds, buy blocks, swords, bows and armour, bridge over and break the enemy bed. No bed, no respawn.",
	"tactical": "25 v 25 in Block HQ, bots fill every slot. 30 s of planning behind barriers, then find your weapons: everyone starts with their melee weapon. One life; the last team standing wins.",
}
## One line under each mode card's name.
const MODE_TAGS := {
	"ffa": "Everyone for themselves",
	"tdm": "Two teams, team kills count",
	"instakill": "Two teams, one hit kills",
	"ctf": "Steal their flag, bring it home",
	"gungame": "A new gun with every kill",
	"oitc": "One round, one kill, few lives",
	"koth": "Hold the moving zone alone",
	"infected": "Outlast the spreading horde",
	"tag": "You're IT! Pass it on",
	"hideseek": "One seeker, hide and swap",
	"blockhunt": "Become a block, pop balloons",
	"parkour": "Jump, climb, don't look down",
	"bedwars": "Bridge over, break their bed",
	"tactical": "25 v 25, plan, one life",
}
const MODE_COLORS := {
	"ffa": Color("ff8a4c"), "tdm": Color("4fa3ff"), "instakill": Color("ff3b3b"), "ctf": Color("ff5d73"), "gungame": Color("ffc531"),
	"oitc": Color("ffb066"), "koth": Color("c58bff"), "infected": Color("7be05a"), "tag": Color("ff6fb5"),
	"hideseek": Color("5fd3c8"), "blockhunt": Color("b8e05a"), "parkour": Color("ffd84a"), "bedwars": Color("e0484f"),
	"tactical": Color("9fb3c8"),
}


## Small code-drawn emblem on a mode card.
class ModeIcon extends Control:
	var mode := "ffa"
	var color := Color.WHITE

	func _init(p_mode: String, p_color: Color) -> void:
		mode = p_mode
		color = p_color
		custom_minimum_size = Vector2(36, 36)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 18.0, Color(color, 0.18))
		var w := 3.0
		match mode:
			"ffa":
				draw_arc(c, 10.0, 0.0, TAU, 32, color, w, true)
				for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(c + d * 6.0, c + d * 15.0, color, w, true)
			"tdm":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -11), c + Vector2(-1, 3), c + Vector2(-17, 3)]), color)
				draw_rect(Rect2(c + Vector2(2, -6), Vector2(14, 14)), Color("ff8a4c"))
			"ctf":
				draw_line(c + Vector2(-9, -13), c + Vector2(-9, 13), Color(0.92, 0.92, 0.95), w, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -13), c + Vector2(13, -6), c + Vector2(-8, 1)]), color)
				draw_rect(Rect2(c + Vector2(-14, 11), Vector2(10, 3)), Color(0.92, 0.92, 0.95))
			"gungame":
				for i in 3:
					draw_rect(Rect2(c + Vector2(-13 + i * 9, 8 - i * 7), Vector2(7, 6 + i * 7)), color)
			"oitc":
				# One upright cartridge: copper nose, brass case, rim.
				draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -5), c + Vector2(-4, -11), c + Vector2(0, -14),
					c + Vector2(4, -11), c + Vector2(6, -5)]), Color(0.85, 0.5, 0.3))
				draw_rect(Rect2(c + Vector2(-6, -5), Vector2(12, 15)), color)
				draw_rect(Rect2(c + Vector2(-7.5, 10), Vector2(15, 3)), color.darkened(0.3))
			"koth":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-13, 9), c + Vector2(-13, -7), c + Vector2(-6, 0),
					c + Vector2(0, -11), c + Vector2(6, 0), c + Vector2(13, -7), c + Vector2(13, 9)]), color)
			"infected":
				draw_circle(c, 12.0, color)
				draw_circle(c + Vector2(-4.5, -2), 2.6, Color(0.05, 0.12, 0.05))
				draw_circle(c + Vector2(4.5, -2), 2.6, Color(0.05, 0.12, 0.05))
				draw_line(c + Vector2(-5, 5), c + Vector2(5, 5), Color(0.05, 0.12, 0.05), 2.0, true)
			"tag":
				# A hand mid-tap: palm block and four fingers, motion lines behind.
				draw_rect(Rect2(c + Vector2(-4, -2), Vector2(12, 12)), color)
				for i in 4:
					draw_rect(Rect2(c + Vector2(-4 + i * 3.2, -12), Vector2(2.4, 10)), color)
				for i in 3:
					draw_line(c + Vector2(-15, -6 + i * 6), c + Vector2(-8, -6 + i * 6), Color(color, 0.6), 2.0, true)
			"hideseek":
				# An eye peeking over a wall.
				draw_rect(Rect2(c + Vector2(-14, 2), Vector2(28, 11)), color.darkened(0.35))
				draw_circle(c + Vector2(0, -3), 8.0, Color(0.95, 0.97, 1.0))
				draw_circle(c + Vector2(0, -3), 4.0, color)
				draw_circle(c + Vector2(0, -3), 1.8, Color(0.05, 0.08, 0.1))
			"blockhunt":
				# A grass block with a balloon on a string.
				draw_rect(Rect2(c + Vector2(-13, -1), Vector2(14, 14)), Color(0.55, 0.38, 0.22))
				draw_rect(Rect2(c + Vector2(-13, -1), Vector2(14, 4)), color)
				draw_line(c + Vector2(-2, -1), c + Vector2(7, -6), Color(0.92, 0.92, 0.95), 1.5, true)
				draw_circle(c + Vector2(8, -10), 5.5, Color("ff5d73"))
			"parkour":
				# Three rising blocks with a figure leaping between them.
				for i in 3:
					draw_rect(Rect2(c + Vector2(-14 + i * 10, 8 - i * 6), Vector2(7, 6 + i * 6)), color.darkened(0.15 * i))
				draw_arc(c + Vector2(-2, 0), 9.0, PI * 1.1, PI * 1.9, 10, Color(color, 0.7), 1.5, true)
				draw_circle(c + Vector2(3, -11), 2.6, Color(0.95, 0.97, 1.0))
			"bedwars":
				# A bed side-on: frame and legs, a red blanket, a white pillow at the head.
				draw_rect(Rect2(c + Vector2(-14, 2), Vector2(28, 5)), Color(0.55, 0.38, 0.22))
				draw_rect(Rect2(c + Vector2(-14, 7), Vector2(3, 5)), Color(0.55, 0.38, 0.22))
				draw_rect(Rect2(c + Vector2(11, 7), Vector2(3, 5)), Color(0.55, 0.38, 0.22))
				draw_rect(Rect2(c + Vector2(-5, -5), Vector2(19, 7)), color)
				draw_rect(Rect2(c + Vector2(-13, -4), Vector2(8, 6)), Color(0.95, 0.97, 1.0))
			"tactical":
				draw_rect(Rect2(c + Vector2(-11, -13), Vector2(22, 26)), color)
				for y in 3:
					for x in 2:
						draw_rect(Rect2(c + Vector2(-7 + x * 9, -9 + y * 7), Vector2(5, 4)), Color(0.08, 0.1, 0.14))


const LINK_HINTS := {
	Net.Link.DIRECT: "Wi-Fi friends see it under Join; others use the room code.",
	Net.Link.STEAM: "Both players need Steam open. Invite from the lobby or the pause menu.",
	Net.Link.WEBRTC: "Fallback if room codes fail. The code is in the lobby and the pause menu.",
}

var hosting := false

var _map_desc: Label
var _players_label: Label
var _port_edit: LineEdit
var _status: Label
var _start: Button
var _players_slider: HSlider
var _map_group: ButtonGroup
var _map_grid: GridContainer
## The CUSTOM heading and cards (saved playable Map Editor maps, _refresh_custom_maps).
var _custom_head: Label
## Under CUSTOM in Capture the Flag: why some custom maps are greyed out (CustomMaps.ctf_problems).
var _custom_hint: Label
var _custom_grid: GridContainer
var _difficulty_row: Container
## Port and address rows, only shown for the DIRECT connection.
var _direct_rows: Array[Control] = []
## Waiting for Steam/WebRTC to set up hosting; leaving the page cancels it.
var _host_pending := false
var _kill_row: Container
var _team_kill_row: Container
var _ladder_row: Container
var _koth_row: Container
var _ctf_row: Container
var _lives_row: Container
var _time_row: Container
var _mutator_row: Container
var _streak_row: Container
## WEATHER chips: AUTO, CLEAR and the weathers the picked map allows (_fill_weather_row).
var _weather_row: HFlowContainer
## Map preview rects still waiting for their texture.
var _preview_queue: Array[TextureRect] = []
## Mode cards in MODE_IDS order (a ButtonGroup of toggles).
var _mode_row: Container
## Rule rows (name label and control) and the modes that show them.
var _mode_rules: Array = []
## The chosen mode's hint, under the mode cards.
var _rules_hint: Label
## The CUSTOM row's button (a summary of the picks) and the overlay it opens.
var _custom_button: Button
var _custom_panel: CustomMutatorsPanel
## Second preset row (name, SAVE, RENAME, DELETE), opened with the EDIT toggle.
var _preset_manage: Container
var _preset_edit: Button
var _link_row: Container
## Match setup presets (Profile.match_presets): the list, the name field and its buttons.
var _preset_pick: OptionButton
var _preset_name: LineEdit
var _preset_load: Button
var _preset_rename: Button
var _preset_delete: Button
var _preset_quick: Button
## DELETE was pressed once for the picked preset; the second press deletes it.
var _delete_armed := false


func _init(host_mode: bool) -> void:
	super()
	hosting = host_mode


## The setup screen's starting choices (also what a preset's missing or invalid fields fall back to).
## `custom`: the custom mutators (CustomMutators.sanitize with no mode: picks a mode ignores stay).
static func default_choice() -> Dictionary:
	return {"mode": "ffa", "map": ROTATION, "bots_fill": 8, "difficulty": 1, "kill_limit": 20,
		"team_kill_limit": TeamDeathmatch.DEFAULT_KILL_LIMIT, "ctf_limit": CaptureTheFlag.DEFAULT_CAPTURES,
		"ladder": GunGame.max_length(), "oitc_lives": OneInTheChamber.DEFAULT_LIVES,
		"koth_limit": KingOfTheBlock.DEFAULT_SCORE_LIMIT, "time_minutes": 8,
		"mutators": true, "link": Net.Link.DIRECT,
		"streaks": {}, "weather": "auto", "custom": CustomMutators.DEFAULTS.duplicate()}


## A full, valid set of setup choices from saved data (a preset from an old or edited save): each
## field must be one the screen offers today, else it takes default_choice()'s value.
static func sanitize_choice(raw: Variant) -> Dictionary:
	var out := default_choice()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw
	var mode := str(d.get("mode", ""))
	if MODE_IDS.has(mode):
		out.mode = mode
	var map_id := str(d.get("map", ""))
	if map_id == ROTATION or Data.MAP_ROTATION.has(map_id) or (CustomMaps.is_custom(map_id) and FileAccess.file_exists(CustomMaps.path_for(CustomMaps.name_of(map_id)))):
		out.map = map_id
	out.bots_fill = clampi(_int(d.get("bots_fill"), out.bots_fill), 2, Data.MAX_PLAYERS)
	out.difficulty = clampi(_int(d.get("difficulty"), out.difficulty), 0, Data.DIFFICULTY_NAMES.size() - 1)
	for pair: Array in [["kill_limit", KILL_LIMITS], ["team_kill_limit", TEAM_KILL_LIMITS], ["ctf_limit", CaptureTheFlag.LIMITS],
			["ladder", GunGame.LENGTHS], ["oitc_lives", OneInTheChamber.LIVES], ["koth_limit", KingOfTheBlock.LIMITS],
			["time_minutes", TIME_LIMITS]]:
		var v := _int(d.get(pair[0]), -1)
		if (pair[1] as Array).has(v):
			out[pair[0]] = v
	if typeof(d.get("mutators")) == TYPE_BOOL:
		out.mutators = d.mutators
	var link := _int(d.get("link"), -1)
	var weather := str(d.get("weather", ""))
	if weather == "auto" or Data.WEATHERS.has(weather):
		out.weather = weather
	if link in [Net.Link.DIRECT, Net.Link.STEAM, Net.Link.WEBRTC]:
		out.link = link
	var streaks: Variant = d.get("streaks", {})
	if typeof(streaks) == TYPE_DICTIONARY:
		for m: String in MODE_IDS:
			if typeof((streaks as Dictionary).get(m)) == TYPE_BOOL:
				out.streaks[m] = streaks[m]
	out.custom = CustomMutators.sanitize(d.get("custom"))
	return out


## A whole number from saved data (JSON numbers are floats), or `fallback`.
static func _int(v: Variant, fallback: int) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else fallback


## A copy of the current choices (what SAVE stores in a preset).
static func current_choice() -> Dictionary:
	return _choice.duplicate(true)


func _ready() -> void:
	var page := make_page()
	# Top bar: BACK and the title on the left, the presets strip (and its EDIT row) on the right.
	var top := make_header("HOST GAME" if hosting else "PLAY VS BOTS",
		"Friends join by room code, Wi-Fi or Steam. Bots fill the empty slots." if hosting else "Offline match against bots.")
	top.add_child(UIKit.spacer())
	var presets := UIKit.vbox(4)
	presets.custom_minimum_size.x = RULES_W
	presets.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(presets)
	_build_presets(presets)
	page.add_child(top)

	var body := UIKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	# Left: the modes as a grid of tiles, the chosen mode's hint, then the map preview cards.
	var mv := UIKit.vbox(8)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mv)
	var mode_grid := GridContainer.new()
	mode_grid.columns = MODE_COLUMNS
	mode_grid.add_theme_constant_override("h_separation", 8)
	mode_grid.add_theme_constant_override("v_separation", 8)
	_mode_row = mode_grid
	mv.add_child(mode_grid)
	var mode_group := ButtonGroup.new()
	for id: String in MODE_IDS:
		_mode_row.add_child(_mode_card(id, mode_group))
	# A fixed height, so the map cards below never move when the mode changes.
	_rules_hint = UIKit.label(MODE_HINTS.ffa, &"DimLabel")
	_rules_hint.add_theme_font_size_override("font_size", 13)
	_rules_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_hint.max_lines_visible = HINT_LINES
	_rules_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rules_hint.custom_minimum_size.y = 18 * HINT_LINES
	_rules_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	mv.add_child(_rules_hint)
	var map_head := UIKit.hbox(12)
	mv.add_child(map_head)
	map_head.add_child(UIKit.label("MAP", &"SubheaderLabel"))
	_map_desc = UIKit.label("", &"DimLabel")
	_map_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_map_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_desc.add_theme_font_size_override("font_size", 14)
	map_head.add_child(_map_desc)
	# Built-in maps, then the playable custom maps (Map Editor) under CUSTOM. The built-in cards
	# always fit (MAP_CARD_H); only the custom maps below them scroll.
	var map_scroll := UIKit.pad_friendly(ScrollContainer.new())
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_child(map_scroll)
	var map_list := UIKit.vbox(10)
	map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_scroll.add_child(map_list)
	var grid := GridContainer.new()
	grid.columns = MAP_COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_list.add_child(grid)
	_map_grid = grid
	var group := ButtonGroup.new()
	_map_group = group
	_add_map_card(grid, group, ROTATION, "Rotation", "Play every map in turn.")
	for id: String in Data.MAP_ROTATION:
		_add_map_card(grid, group, id, Data.MAPS[id].name, Data.MAPS[id].desc)
	# The maps of Tactical, Parkour and Bedwars; the only card shown in that mode.
	for id: String in Data.MODE_MAPS.values():
		_add_map_card(grid, group, id, Data.MAPS[id].name, Data.MAPS[id].desc)
	_custom_head = UIKit.label("CUSTOM", &"SubheaderLabel")
	map_list.add_child(_custom_head)
	_custom_hint = UIKit.label("", &"DimLabel")
	_custom_hint.add_theme_font_size_override("font_size", 13)
	_custom_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_custom_hint.visible = false
	map_list.add_child(_custom_hint)
	_custom_grid = GridContainer.new()
	_custom_grid.columns = MAP_COLUMNS
	_custom_grid.add_theme_constant_override("h_separation", 10)
	_custom_grid.add_theme_constant_override("v_separation", 10)
	map_list.add_child(_custom_grid)
	_refresh_custom_maps()

	# Right: the rules that apply to the mode (and the host's connection rows), the status line
	# and START. Every row fits without scrolling (see the budget at the top).
	var rules_panel := UIKit.panel()
	rules_panel.custom_minimum_size.x = RULES_W
	body.add_child(rules_panel)
	var rv := UIKit.vbox(10)
	rules_panel.add_child(rv)
	var rules := GridContainer.new()
	rules.columns = 2
	rules.add_theme_constant_override("h_separation", 10)
	rules.add_theme_constant_override("v_separation", RULE_GAP)
	rv.add_child(rules)

	var players_row := UIKit.hbox(8)
	var players := HSlider.new()
	_players_slider = players
	players.min_value = 2
	players.max_value = Data.MAX_PLAYERS
	players.step = 1
	players.value = _choice.bots_fill
	players.custom_minimum_size.y = 26
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	players.value_changed.connect(func(v: float) -> void:
		_choice.bots_fill = int(v)
		_update_players_label())
	players_row.add_child(players)
	_players_label = UIKit.label("", &"SmallLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_players_label.add_theme_color_override("font_color", UITheme.TEXT)
	_players_label.custom_minimum_size.x = 86
	_players_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	players_row.add_child(_players_label)
	_rule(rules, "PLAYERS", players_row)
	_mode_rule(rules, ["ffa", "tdm", "ctf", "gungame", "oitc", "koth", "infected", "tag", "hideseek", "blockhunt", "parkour", "bedwars"])
	_update_players_label()

	var difficulty_names: Array[String] = []
	for d in Data.DIFFICULTY_NAMES:
		difficulty_names.append(d.to_upper())
	_difficulty_row = _segmented(difficulty_names, _choice.difficulty, func(i: int) -> void: _choice.difficulty = i)
	_rule(rules, "BOTS", _difficulty_row)
	var kill_names: Array[String] = []
	for k in KILL_LIMITS:
		kill_names.append(str(k))
	_kill_row = _segmented(kill_names, KILL_LIMITS.find(_choice.kill_limit),
		func(i: int) -> void: _choice.kill_limit = KILL_LIMITS[i])
	_rule(rules, "KILLS", _kill_row)
	_mode_rule(rules, ["ffa"])
	var team_kill_names: Array[String] = []
	for k in TEAM_KILL_LIMITS:
		team_kill_names.append(str(k))
	_team_kill_row = _segmented(team_kill_names, TEAM_KILL_LIMITS.find(_choice.team_kill_limit),
		func(i: int) -> void: _choice.team_kill_limit = TEAM_KILL_LIMITS[i])
	_rule(rules, "TEAM KILLS", _team_kill_row)
	_mode_rule(rules, ["tdm", "instakill"])
	var ctf_names: Array[String] = []
	for k in CaptureTheFlag.LIMITS:
		ctf_names.append(str(k))
	_ctf_row = _segmented(ctf_names, CaptureTheFlag.LIMITS.find(_choice.ctf_limit),
		func(i: int) -> void: _choice.ctf_limit = CaptureTheFlag.LIMITS[i])
	_rule(rules, "CAPTURES", _ctf_row)
	_mode_rule(rules, ["ctf"])
	var ladder_names: Array[String] = []
	for n in GunGame.LENGTHS:
		ladder_names.append("%d" % (n - 1) if n < GunGame.max_length() else "ALL %d" % (n - 1))
	_ladder_row = _segmented(ladder_names, GunGame.LENGTHS.find(_choice.ladder),
		func(i: int) -> void: _choice.ladder = GunGame.LENGTHS[i])
	_rule(rules, "GUNS", _ladder_row)
	_mode_rule(rules, ["gungame"])
	var lives_names: Array[String] = []
	for n in OneInTheChamber.LIVES:
		lives_names.append(str(n))
	_lives_row = _segmented(lives_names, OneInTheChamber.LIVES.find(_choice.oitc_lives),
		func(i: int) -> void: _choice.oitc_lives = OneInTheChamber.LIVES[i])
	_rule(rules, "LIVES", _lives_row)
	_mode_rule(rules, ["oitc"])
	var koth_names: Array[String] = []
	for k in KingOfTheBlock.LIMITS:
		koth_names.append(str(k))
	_koth_row = _segmented(koth_names, KingOfTheBlock.LIMITS.find(_choice.koth_limit),
		func(i: int) -> void: _choice.koth_limit = KingOfTheBlock.LIMITS[i])
	_rule(rules, "POINTS", _koth_row)
	_mode_rule(rules, ["koth"])
	var time_names: Array[String] = []
	for t in TIME_LIMITS:
		time_names.append("%d MIN" % t)
	_time_row = _segmented(time_names, TIME_LIMITS.find(_choice.time_minutes),
		func(i: int) -> void: _choice.time_minutes = TIME_LIMITS[i])
	_rule(rules, "TIME", _time_row)
	var mutator_names: Array[String] = ["RANDOM", "OFF"]
	_mutator_row = _segmented(mutator_names, 0 if _choice.mutators else 1,
		func(i: int) -> void: _choice.mutators = i == 0)
	_rule(rules, "MUTATORS", _mutator_row)
	_mode_rule(rules, ["ffa", "tdm", "ctf", "gungame", "koth", "infected"])
	_streak_row = _segmented(["ON", "OFF"] as Array[String], 0 if _streaks_on() else 1,
		func(i: int) -> void: _choice.streaks[_choice.mode] = i == 0)
	_rule(rules, "STREAKS", _streak_row)
	_mode_rule(rules, ["ffa", "tdm", "ctf", "gungame", "koth", "infected", "tactical"])
	_weather_row = _flow()
	_rule(rules, "WEATHER", _weather_row)
	_custom_button = UIKit.button("", &"ChipButton")
	_custom_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_custom_button.clip_text = true
	_custom_button.pressed.connect(func() -> void: _custom_panel.open(_choice.custom, _choice.mode))
	_rule(rules, "CUSTOM", _custom_button)
	_update_custom_button()

	if hosting:
		_build_host_section(rules)

	rv.add_child(UIKit.spacer(false))
	_status = UIKit.label("", &"DimLabel")
	_status.add_theme_font_size_override("font_size", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_status)
	_start = UIKit.button("START HOSTING" if hosting else "START MATCH", &"PrimaryButton")
	_start.add_theme_font_size_override("font_size", 24)
	_start.custom_minimum_size.y = START_H
	_start.pressed.connect(_on_start)
	rv.add_child(_start)

	_custom_panel = CustomMutatorsPanel.new(page.get_parent())
	_custom_panel.changed.connect(func(custom: Dictionary) -> void:
		_choice.custom = custom
		_update_custom_button())
	_custom_panel.closed.connect(func() -> void: _custom_button.grab_focus())
	add_child(_custom_panel)

	Net.status.connect(_on_status)
	back_requested.connect(func() -> void:
		if _host_pending:
			Net.leave())
	_select_map(_choice.map)
	_apply_mode()
	_add_hover_fx(self)


## A wrapping row of chips: rows of chips wrap instead of widening the panel past the window.
static func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 4)
	return f


## Gives every button under `root` a 3D-feeling hover: it lifts toward the viewer, tilts toward
## the pointer and brightens; it settles back when the pointer leaves.
static func _add_hover_fx(root: Node) -> void:
	for n: Node in root.find_children("*", "Button", true, false):
		_hover_fx(n as Button)


static func _hover_fx(b: Button) -> void:
	if b.has_meta(&"hover_fx"):
		return
	b.set_meta(&"hover_fx", true)
	var big := b.custom_minimum_size.y >= 60.0 or b.theme_type_variation == &"CardButton"
	var lift := 1.045 if big else 1.08
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	var settle := func(on: bool) -> void:
		var t := b.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "scale", Vector2.ONE * (lift if on else 1.0), 0.16)
		t.tween_property(b, "self_modulate", Color(1.15, 1.15, 1.2) if on else Color.WHITE, 0.16)
		if not on:
			t.tween_property(b, "rotation", 0.0, 0.2)
		b.z_index = 1 if on else 0
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			settle.call(true))
	b.mouse_exited.connect(func() -> void: settle.call(false))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseMotion and not b.disabled and b.size.x > 0.0:
			# Tilt up to ~2.5 degrees toward the side the pointer is on, like a card on a pivot.
			var lean: float = ((e as InputEventMouseMotion).position.x / b.size.x - 0.5) * 2.0
			b.rotation = lerpf(b.rotation, deg_to_rad(2.5 if big else 4.0) * lean * 0.5, 0.35))


## A selectable mode tile: emblem beside the short name, a one-line description below, and a
## strip in the mode's colour along the bottom. The full name and line are its tooltip.
func _mode_card(id: String, group: ButtonGroup) -> Button:
	var card := UIKit.button("", &"CardButton")
	card.toggle_mode = true
	card.button_group = group
	card.name = id
	card.custom_minimum_size = Vector2(130, MODE_CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.button_pressed = id == _choice.mode
	card.tooltip_text = "%s: %s" % [Data.MODES[id].name, MODE_TAGS[id]]
	card.pressed.connect(func() -> void: pick_mode(id))
	var h := UIKit.hbox(8)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -6
	h.offset_bottom = -4
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	h.add_child(ModeIcon.new(id, MODE_COLORS[id]))
	var v := UIKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var title := UIKit.label(str(Data.MODES[id].short), &"ValueLabel")
	title.add_theme_font_size_override("font_size", 14)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(title)
	var tag := UIKit.label(MODE_TAGS[id], &"DimLabel")
	tag.add_theme_font_size_override("font_size", 11)
	tag.clip_text = true
	tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(tag)
	var strip := ColorRect.new()
	strip.color = Color(MODE_COLORS[id], 0.85)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -4
	strip.offset_left = 8
	strip.offset_right = -8
	strip.offset_bottom = -2
	card.add_child(strip)
	return card


## Picks a mode as its card would (also used by scripted checks).
func pick_mode(id: String) -> void:
	_choice.mode = id
	_pick_segment(_mode_row, MODE_IDS.find(id))
	_apply_mode()


func on_shown() -> void:
	_status.remove_theme_color_override("font_color")
	_status.text = LINK_HINTS[_choice.link] if hosting else ""
	_start.disabled = false
	_refresh_custom_maps()
	# Choices are shared with the other mode's screen, which may have changed them.
	_show_choice()
	_refresh_presets(_preset_pick.selected)
	_add_hover_fx(self)


## (Re)builds the CUSTOM cards from the saved playable maps (CustomMaps.playable), each with its
## preview, name (`title` meta) and why Capture the Flag can't be played on it (`ctf_why` meta, the
## first of CustomMaps.ctf_problems, "" when it can);
## hidden when there are none or in Tactical. A picked custom map that is gone falls back to the
## rotation.
func _refresh_custom_maps() -> void:
	var names := CustomMaps.playable()
	var ids: Array[String] = []
	for n in names:
		ids.append(CustomMaps.id_for(n))
	var have: Array[String] = []
	for b: Node in _custom_grid.get_children():
		have.append(str(b.get_meta(&"map_id")))
	if have != ids:
		for b: Node in _custom_grid.get_children():
			_preview_queue.erase(b.get_meta(&"preview"))
			b.free()
		for i in ids.size():
			MapBuilder.forget_preview(ids[i])
			var m := CustomMaps.load_map(names[i])
			var g: VoxelGrid = m.grid
			var ctf := CustomMaps.ctf_problems(m)
			_add_map_card(_custom_grid, _map_group, ids[i], names[i], "Custom map · %d x %d · %d spawns · %s" % [g.size.x, g.size.z,
				m.spawns.size(), str(m.time_of_day)])
			var card: Button = _custom_grid.get_child(_custom_grid.get_child_count() - 1)
			card.set_meta(&"base_desc", card.get_meta(&"desc"))
			card.set_meta(&"title", names[i])
			card.set_meta(&"ctf_why", "" if ctf.is_empty() else ctf[0])
	if CustomMaps.is_custom(_choice.map) and not ids.has(_choice.map):
		_choice.map = ROTATION
	_custom_head.visible = not ids.is_empty() and Data.fixed_map(_choice.mode).is_empty()
	_apply_custom_ctf()


## Capture the Flag greys out the custom maps it can't be played on (CustomMaps.ctf_problems:
## the first problem is the card's tooltip and goes into the hint under CUSTOM and, in this
## mode only, the map's description), and moves a pick of one to the rotation.
func _apply_custom_ctf() -> void:
	var ctf: bool = _choice.mode == "ctf"
	var blocked: Array[Button] = []
	for b: Node in _custom_grid.get_children():
		var card := b as Button
		var why := str(card.get_meta(&"ctf_why", ""))
		var off := ctf and not why.is_empty()
		card.disabled = off
		card.modulate = Color(1, 1, 1, 0.45) if off else Color.WHITE
		card.tooltip_text = "Not for Capture the Flag: %s Fix it in the Map Editor." % why if off else ""
		card.set_meta(&"desc", str(card.get_meta(&"base_desc")) + (" · not for Capture the Flag" if off else ""))
		if off:
			blocked.append(card)
			if _choice.map == card.get_meta(&"map_id"):
				_choice.map = ROTATION
	if blocked.size() == 1:
		_custom_hint.text = "%s can't host Capture the Flag: %s" % [blocked[0].get_meta(&"title"), blocked[0].get_meta(&"ctf_why")]
	elif blocked.size() > 1:
		_custom_hint.text = "%d greyed-out maps can't host Capture the Flag (point at one for why). %s: %s" % [blocked.size(),
			blocked[0].get_meta(&"title"), blocked[0].get_meta(&"ctf_why")]
	_custom_hint.visible = not blocked.is_empty() and _custom_head.visible


## Sets every control to `_choice`.
func _show_choice() -> void:
	_players_slider.set_value_no_signal(_choice.bots_fill)
	_update_players_label()
	_pick_segment(_difficulty_row, _choice.difficulty)
	_pick_segment(_kill_row, KILL_LIMITS.find(_choice.kill_limit))
	_pick_segment(_team_kill_row, TEAM_KILL_LIMITS.find(_choice.team_kill_limit))
	_pick_segment(_ctf_row, CaptureTheFlag.LIMITS.find(_choice.ctf_limit))
	_pick_segment(_ladder_row, GunGame.LENGTHS.find(_choice.ladder))
	_pick_segment(_koth_row, KingOfTheBlock.LIMITS.find(_choice.koth_limit))
	_pick_segment(_lives_row, OneInTheChamber.LIVES.find(_choice.oitc_lives))
	_pick_segment(_time_row, TIME_LIMITS.find(_choice.time_minutes))
	_pick_segment(_mutator_row, 0 if _choice.mutators else 1)
	if _link_row != null:
		_pick_segment(_link_row, [Net.Link.DIRECT, Net.Link.STEAM, Net.Link.WEBRTC].find(_choice.link))
		_update_link_rows()
	_select_map(_choice.map)
	_pick_segment(_mode_row, MODE_IDS.find(_choice.mode))
	_apply_mode()


## Shows the rules that apply to the chosen mode (the others keep their choices for switching
## back). Tactical, Parkour and Bedwars fix the map (Tactical also the player count, kill rule and
## mutators): only their own map card.
func _apply_mode() -> void:
	var fixed := Data.fixed_map(_choice.mode)
	for entry: Array in _mode_rules:
		for c: Control in entry[0]:
			c.visible = (entry[1] as Array).has(_choice.mode)
	_rules_hint.text = MODE_HINTS[_choice.mode]
	_rules_hint.tooltip_text = MODE_HINTS[_choice.mode]
	_pick_segment(_streak_row, 0 if _streaks_on() else 1)
	for b in _map_group.get_buttons():
		var id: String = b.get_meta(&"map_id")
		b.visible = id == fixed if not fixed.is_empty() else not Data.MODE_MAPS.values().has(id)
	_custom_head.visible = _custom_grid.get_child_count() > 0 and fixed.is_empty()
	_apply_custom_ctf()
	# A fixed map's single card keeps a card's size instead of filling the whole column.
	_map_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if not fixed.is_empty() else Control.SIZE_EXPAND_FILL
	if not fixed.is_empty():
		for b in _map_group.get_buttons():
			b.set_pressed_no_signal(b.get_meta(&"map_id") == fixed)
		_map_desc.text = Data.MAPS[fixed].desc
	else:
		_select_map(_choice.map)
	_fill_weather_row()
	_update_custom_button()


## The CUSTOM button: "OFF", or how many custom mutators the chosen mode plays with; the
## tooltip lists them.
func _update_custom_button() -> void:
	var on := CustomMutators.describe(CustomMutators.sanitize(_choice.custom, _choice.mode))
	_custom_button.text = "CUSTOM MUTATORS · %s" % ("OFF" if on.is_empty() else "%d ON" % on.size())
	_custom_button.tooltip_text = ", ".join(on) if not on.is_empty() \
		else "One weapon for everyone, health, gravity, size, speed, damage, jump and more."


## The WEATHER choices on `map_id` (ROTATION: AUTO, CLEAR, RAIN, STORM; a map in the rotation
## that doesn't allow the pick rolls its own weather, see Net._roll_weather).
static func weather_options(map_id: String) -> Array[String]:
	var out: Array[String] = ["auto", "clear"]
	var allowed: Dictionary = Data.DEFAULT_WEATHER if map_id == ROTATION else Net.weathers_for(map_id)
	for w: String in allowed:
		if w != "clear":
			out.append(w)
	return out


## Rebuilds the WEATHER chips for the picked map (Tactical: its own map). A pick the map doesn't
## offer shows as AUTO, which is what it plays there; the pick itself is kept for other maps.
func _fill_weather_row() -> void:
	var fixed := Data.fixed_map(_choice.mode)
	var map_id: String = fixed if not fixed.is_empty() else _choice.map
	var options := weather_options(map_id)
	for c: Node in _weather_row.get_children():
		c.free()
	var group := ButtonGroup.new()
	var selected := maxi(options.find(str(_choice.weather)), 0)
	for i in options.size():
		var id := options[i]
		var b := UIKit.button("AUTO" if id == "auto" else str(Data.WEATHERS[id].short), &"ChipButton")
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = i == selected
		b.pressed.connect(func() -> void: _choice.weather = id)
		_weather_row.add_child(b)
	_add_hover_fx(_weather_row)


func _pick_segment(row: Container, selected: int) -> void:
	for i in row.get_child_count():
		(row.get_child(i) as Button).set_pressed_no_signal(i == selected)


func _rule_name(text: String) -> Label:
	var l := UIKit.label(text, &"SmallLabel")
	l.custom_minimum_size.x = 72
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _rule(grid: GridContainer, text: String, control: Control) -> void:
	grid.add_child(_rule_name(text))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


## The rule row just added to `grid` only shows in `modes`.
func _mode_rule(grid: GridContainer, modes: Array) -> void:
	var n := grid.get_child_count()
	_mode_rules.append([[grid.get_child(n - 2), grid.get_child(n - 1)], modes])


func _update_players_label() -> void:
	var bots: int = _choice.bots_fill - 1
	_players_label.text = "%d · %d BOT%s" % [_choice.bots_fill, bots, "" if bots == 1 else "S"]


## Row of small toggle chips acting as a radio group.
func _segmented(names: Array[String], selected: int, on_pick: Callable) -> Container:
	var h: Container = _flow()
	var group := ButtonGroup.new()
	for i in names.size():
		var b := UIKit.button(names[i], &"ChipButton")
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = i == selected
		b.pressed.connect(func() -> void: on_pick.call(i))
		h.add_child(b)
	return h


func _add_map_card(grid: GridContainer, group: ButtonGroup, id: String, title: String, desc: String) -> void:
	var card := UIKit.button("", &"CardButton")
	card.toggle_mode = true
	card.button_group = group
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(120, MAP_CARD_H)
	# Custom map ids hold characters a node name can't, so cards are found by their meta.
	card.name = id.validate_node_name()
	card.set_meta(&"map_id", id)
	card.set_meta(&"desc", desc)
	card.pressed.connect(func() -> void: _select_map(id))
	if Data.MODE_MAPS.values().has(id):
		card.custom_minimum_size.y = FIXED_MAP_CARD_H
	grid.add_child(card)
	var v := UIKit.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_top = 6
	v.offset_right = -6
	v.offset_bottom = -6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	# The rounded frame masks the preview's corners.
	var pic_frame := PanelContainer.new()
	pic_frame.add_theme_stylebox_override("panel", UITheme.round_box(Color(0.1, 0.15, 0.22), Color(0, 0, 0, 0), 0, 10, 0))
	pic_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	pic_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic_frame)
	if id == ROTATION:
		var strip := UIKit.hbox(2)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic_frame.add_child(strip)
		for map_id: String in Data.MAP_ROTATION:
			strip.add_child(_preview_rect(map_id))
	else:
		var pic := _preview_rect(id)
		card.set_meta(&"preview", pic)
		pic_frame.add_child(pic)
	var name_label := UIKit.label(title.to_upper(), &"ValueLabel")
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	v.add_child(name_label)


func _preview_rect(map_id: String) -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.set_meta(&"map_id", map_id)
	_preview_queue.append(r)
	return r


## Fills one preview per frame (MapBuilder caches them) so opening the screen never stalls.
func _process(_delta: float) -> void:
	if _preview_queue.is_empty() or not is_visible_in_tree():
		return
	var r: TextureRect = _preview_queue.pop_front()
	r.texture = MapBuilder.preview(r.get_meta(&"map_id"))


func _select_map(id: String) -> void:
	# The Tactical card is fixed by the mode; the deathmatch pick stays for switching back.
	if not Data.MODE_MAPS.values().has(id):
		_choice.map = id
	# set_pressed_no_signal skips the ButtonGroup, so release the other cards here.
	for b in _map_group.get_buttons():
		var on: bool = b.get_meta(&"map_id") == id
		b.set_pressed_no_signal(on)
		if on:
			_map_desc.text = b.get_meta(&"desc")
	if _weather_row != null:
		_fill_weather_row()


## The host's rows, in the rules grid: LINK, then (DIRECT only) one row per local address, LAN
## first and at most MAX_ADDRESSES, each named by its kind, with the port on the last one (only
## joining by address uses it, and only over the internet does it need forwarding).
func _build_host_section(grid: GridContainer) -> void:
	var links: Array[int] = [Net.Link.DIRECT, Net.Link.STEAM, Net.Link.WEBRTC]
	var link_names: Array[String] = ["CODE · WI-FI", "STEAM", "WEBRTC"]
	_link_row = _segmented(link_names, links.find(_choice.link), func(i: int) -> void:
		_choice.link = links[i]
		_update_link_rows())
	_rule(grid, "LINK", _link_row)

	_port_edit = LineEdit.new()
	_port_edit.text = str(Net.DEFAULT_PORT)
	_port_edit.max_length = 5
	_port_edit.custom_minimum_size.x = 68
	_port_edit.add_theme_font_size_override("font_size", 15)
	_port_edit.tooltip_text = "Port for joining by address. Forward it only for internet joins by address."
	var port_box := UIKit.hbox(6)
	var port_name := UIKit.label("PORT", &"SmallLabel")
	port_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	port_box.add_child(port_name)
	port_box.add_child(_port_edit)
	var addresses := NetLinkAddresses.local_addresses()
	if addresses.is_empty():
		var row := UIKit.hbox(6)
		var none := UIKit.label("No local network found.", &"DimLabel")
		none.add_theme_font_size_override("font_size", 14)
		none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		none.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(none)
		row.add_child(port_box)
		_direct_rule(grid, "ADDRESS", row)
	var shown := mini(addresses.size(), MAX_ADDRESSES)
	for i in shown:
		var ip: String = addresses[i].address
		var row := UIKit.hbox(6)
		var ip_label := UIKit.label(ip, &"ValueLabel")
		ip_label.add_theme_font_size_override("font_size", 15)
		ip_label.add_theme_color_override("font_color", UITheme.ACCENT_2)
		ip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ip_label)
		var copy := UIKit.button("COPY", &"ChipButton")
		copy.tooltip_text = "Friends on this network type it into Join."
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(ip)
			_status.text = "Copied %s to the clipboard." % ip)
		row.add_child(copy)
		if i == shown - 1:
			row.add_child(port_box)
		_direct_rule(grid, str(addresses[i].kind).to_upper(), row)
	_update_link_rows()


func _direct_rule(grid: GridContainer, text: String, control: Control) -> void:
	_rule(grid, text, control)
	_direct_rows.append(grid.get_child(grid.get_child_count() - 2))
	_direct_rows.append(control)


## The idle status line explains the chosen connection (keeps the panel short enough for 720p).
func _update_link_rows() -> void:
	if _status:
		_status.remove_theme_color_override("font_color")
		_status.text = LINK_HINTS[_choice.link]
	for c in _direct_rows:
		c.visible = _choice.link == Net.Link.DIRECT


# ---------------------------------------------------------------- presets

## Saved match setups (Profile.match_presets), as a compact strip: pick one to load or start it
## right away (QUICK PLAY / QUICK HOST); EDIT opens a second row to save the current choices under
## a name, rename or delete the picked one.
func _build_presets(parent: VBoxContainer) -> void:
	var top := UIKit.hbox(4)
	parent.add_child(top)
	_preset_pick = OptionButton.new()
	_preset_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_pick.fit_to_longest_item = false
	_preset_pick.clip_text = true
	_preset_pick.add_theme_font_size_override("font_size", 14)
	_preset_pick.item_selected.connect(_on_preset_picked)
	top.add_child(_preset_pick)
	_preset_load = UIKit.button("LOAD", &"ChipButton")
	_preset_load.pressed.connect(_on_preset_load)
	top.add_child(_preset_load)
	_preset_quick = UIKit.button("QUICK HOST" if hosting else "QUICK PLAY", &"ChipButton")
	_preset_quick.tooltip_text = "Load the picked preset and start straight away."
	_preset_quick.pressed.connect(_on_preset_quick)
	top.add_child(_preset_quick)
	_preset_edit = UIKit.button("EDIT", &"ChipButton")
	_preset_edit.toggle_mode = true
	_preset_edit.tooltip_text = "Save, rename or delete presets."
	_preset_edit.toggled.connect(func(on: bool) -> void: _preset_manage.visible = on)
	top.add_child(_preset_edit)
	var row := UIKit.hbox(4)
	_preset_manage = row
	row.visible = false
	parent.add_child(row)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "Preset name"
	_preset_name.max_length = 16
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_name.add_theme_font_size_override("font_size", 15)
	_preset_name.text_submitted.connect(func(_t: String) -> void: _on_preset_save())
	row.add_child(_preset_name)
	var save := UIKit.button("SAVE", &"ChipButton")
	save.tooltip_text = "Save the current settings under this name (replaces a preset of the same name)."
	save.pressed.connect(_on_preset_save)
	row.add_child(save)
	_preset_rename = UIKit.button("RENAME", &"ChipButton")
	_preset_rename.tooltip_text = "Give the picked preset the name typed here."
	_preset_rename.pressed.connect(_on_preset_rename)
	row.add_child(_preset_rename)
	_preset_delete = UIKit.button("DELETE", &"ChipButton")
	_preset_delete.pressed.connect(_on_preset_delete)
	row.add_child(_preset_delete)
	_refresh_presets(0)


## Refills the preset list and picks entry `select` (clamped).
func _refresh_presets(select: int) -> void:
	var list := Profile.match_presets
	_preset_pick.clear()
	for p: Dictionary in list:
		_preset_pick.add_item(str(p.name))
		_preset_pick.set_item_tooltip(_preset_pick.item_count - 1, choice_summary(p.settings))
	if list.is_empty():
		_preset_pick.add_item("No presets saved yet")
	_preset_pick.disabled = list.is_empty()
	_preset_pick.select(clampi(select, 0, maxi(0, list.size() - 1)))
	for b: Button in [_preset_load, _preset_rename, _preset_delete]:
		b.disabled = list.is_empty()
	# While a match is starting QUICK stays off with START.
	if _start == null or not _start.disabled:
		_preset_quick.disabled = list.is_empty()
	_disarm_delete()


## The picked preset's index in Profile.match_presets, or -1 when there are none.
func _preset_index() -> int:
	return _preset_pick.selected if not Profile.match_presets.is_empty() else -1


func _preset_named(i: int) -> String:
	return str(Profile.match_presets[i].name)


func _disarm_delete() -> void:
	_delete_armed = false
	_preset_delete.text = "DELETE"


func _on_preset_picked(i: int) -> void:
	_disarm_delete()
	_preset_name.text = _preset_named(i)
	_show_status("%s: %s" % [_preset_named(i), choice_summary(Profile.match_presets[i].settings)])


func _on_preset_save() -> void:
	var preset_name := Profile.sanitize_name(_preset_name.text)
	if preset_name.is_empty():
		_preset_error("Type a name for the preset first.")
		return
	var i := Profile.save_match_preset(preset_name, current_choice())
	if i < 0:
		_preset_error("All %d preset slots are in use: delete one first." % Profile.MAX_MATCH_PRESETS)
		return
	_preset_name.text = preset_name
	_refresh_presets(i)
	_show_status("Saved preset %s." % preset_name)


func _on_preset_load() -> void:
	var i := _preset_index()
	if i < 0:
		return
	_load_preset(i)
	_show_status("Loaded %s: %s" % [_preset_named(i), choice_summary(_choice)])


## Puts preset `i` into the controls (fields no longer offered fall back to the defaults).
func _load_preset(i: int) -> void:
	_choice = sanitize_choice(Profile.match_presets[i].settings)
	_show_choice()


func _on_preset_rename() -> void:
	var i := _preset_index()
	if i < 0:
		return
	var new_name := Profile.sanitize_name(_preset_name.text)
	if new_name.is_empty():
		_preset_error("Type the new name first.")
		return
	var old_name := _preset_named(i)
	if not Profile.rename_match_preset(i, new_name):
		_preset_error("Another preset is already called %s." % new_name)
		return
	_refresh_presets(i)
	_show_status("Renamed %s to %s." % [old_name, new_name])


## The first press asks for a second one, which deletes the preset.
func _on_preset_delete() -> void:
	var i := _preset_index()
	if i < 0:
		return
	var preset_name := _preset_named(i)
	if not _delete_armed:
		_delete_armed = true
		_preset_delete.text = "SURE?"
		_show_status("Press SURE? to delete %s." % preset_name)
		return
	Profile.delete_match_preset(i)
	_refresh_presets(i)
	_preset_name.text = _preset_named(_preset_index()) if _preset_index() >= 0 else ""
	_show_status("Deleted %s." % preset_name)


func _on_preset_quick() -> void:
	var i := _preset_index()
	if i < 0:
		return
	_load_preset(i)
	_on_start()


func _show_status(text: String) -> void:
	_status.remove_theme_color_override("font_color")
	_status.text = text


func _preset_error(text: String) -> void:
	Sfx.play(&"ui_error")
	_set_error(text)


## One line describing a set of setup choices (preset tooltips and status lines).
static func choice_summary(choice: Dictionary) -> String:
	var parts: Array[String] = []
	for row: Array in describe_config(config_from(sanitize_choice(choice))):
		parts.append(str(row[1]))
	return "  ·  ".join(parts)


## The match rules of a config as [name, value] rows (preset summaries, the pre-match lobby).
static func describe_config(cfg: Dictionary) -> Array:
	var mode := str(cfg.mode)
	var rows: Array = [["MODE", str(Data.MODES[mode].name)]]
	if mode == "tactical":
		rows.append(["MAP", str(Data.MAPS[Data.TACTICAL_MAP].name)])
		rows.append(["PLAYERS", "%d v %d" % [Tactical.PLAYERS / 2, Tactical.PLAYERS / 2]])
	else:
		var fixed := Data.fixed_map(mode)
		rows.append(["MAP", MapBuilder.map_name(fixed) if not fixed.is_empty() else "Rotation" if cfg.map == ROTATION else MapBuilder.map_name(str(cfg.map))])
		rows.append(["PLAYERS", "%d players" % int(cfg.bots_fill)])
	rows.append(["BOTS", "%s bots" % Data.DIFFICULTY_NAMES[int(cfg.difficulty)]])
	match mode:
		"ffa":
			rows.append(["KILL LIMIT", "%d kills" % int(cfg.kill_limit)])
		"tdm", "instakill":
			rows.append(["TEAM KILLS", "%d team kills" % int(cfg.kill_limit)])
		"ctf":
			rows.append(["CAPTURES", "%d capture%s" % [int(cfg.kill_limit), "" if int(cfg.kill_limit) == 1 else "s"]])
		"gungame":
			rows.append(["LADDER", "%d guns" % (int(cfg.kill_limit) - 1)])
		"oitc":
			rows.append(["LIVES", "%d li%s each" % [int(cfg.kill_limit), "fe" if int(cfg.kill_limit) == 1 else "ves"]])
		"koth":
			rows.append(["POINTS", "%d points" % int(cfg.kill_limit)])
	rows.append(["TIME LIMIT", "%d min" % (int(cfg.time_limit) / 60)])
	var gunless := mode in ["tag", "hideseek", "blockhunt", "parkour", "bedwars"]
	if mode != "tactical" and mode != "oitc" and not gunless:
		rows.append(["MUTATORS", "Random mutators" if cfg.mutators else "No mutators"])
	if not gunless:
		rows.append(["KILLSTREAKS", "Killstreaks on" if cfg.streaks else "Killstreaks off"])
	var pick := str(cfg.get("weather_pick", "auto"))
	rows.append(["WEATHER", "Random weather" if pick == "auto" else str(Data.WEATHERS[pick].name)])
	var custom := CustomMutators.describe(CustomMutators.sanitize(cfg.get("custom", {}), mode))
	if not custom.is_empty():
		rows.append(["CUSTOM", ", ".join(custom)])
	return rows


## The Net config a set of setup choices starts.
static func config_from(choice: Dictionary) -> Dictionary:
	return {
		"mode": choice.mode,
		"map": choice.map,
		"bots_fill": choice.bots_fill,
		"difficulty": choice.difficulty,
		"kill_limit": {"tdm": choice.team_kill_limit, "instakill": choice.team_kill_limit, "ctf": choice.ctf_limit, "gungame": choice.ladder,
			"oitc": choice.oitc_lives, "koth": choice.koth_limit}.get(choice.mode, choice.kill_limit),
		"time_limit": int(choice.time_minutes) * 60,
		"mutators": choice.mutators,
		"streaks": bool(choice.streaks.get(choice.mode, Streaks.default_for(choice.mode))),
		"weather_pick": choice.weather,
		"custom": choice.get("custom", {}),
	}


func _config() -> Dictionary:
	return config_from(_choice)


func _streaks_on() -> bool:
	return bool(_choice.streaks.get(_choice.mode, Streaks.default_for(_choice.mode)))


func _on_start() -> void:
	if not hosting:
		_start.disabled = true
		_preset_quick.disabled = true
		_status.text = "Loading map..."
		Net.play_offline(_config())
		return
	var link: int = _choice.link
	var port := Net.DEFAULT_PORT
	if link == Net.Link.DIRECT:
		port = _port_edit.text.strip_edges().to_int()
		if not _port_edit.text.strip_edges().is_valid_int() or port < 1024 or port > 65535:
			Sfx.play(&"ui_error")
			_set_error("Port must be a number between 1024 and 65535.")
			return
	_start.disabled = true
	_preset_quick.disabled = true
	_status.remove_theme_color_override("font_color")
	_status.text = "Starting server on port %d..." % port if link == Net.Link.DIRECT else "Starting..."
	_host_pending = true
	var err: Error = await Net.host(port, _config(), link)
	_host_pending = false
	if err != OK and err != ERR_SKIP:
		_start.disabled = false
		_preset_quick.disabled = Profile.match_presets.is_empty()
		Sfx.play(&"ui_error")
		# Net already reported why on `status`.
		_set_error(_status.text if not _status.text.ends_with("...") else "Could not start hosting: %s" % error_string(err))


func _set_error(text: String) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UITheme.BAD)


func _on_status(text: String) -> void:
	if not is_visible_in_tree():
		return
	_status.remove_theme_color_override("font_color")
	_status.text = text
