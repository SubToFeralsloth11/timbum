class_name MatchSetupScreen
extends MenuScreen
## Match configuration shared by "Play vs Bots" (offline) and "Host Game" (ENet server).

const KILL_LIMITS: Array[int] = [10, 15, 20, 30, 50]
## Team Deathmatch's limit is on the team score, so it runs higher.
const TEAM_KILL_LIMITS: Array[int] = [25, 40, 50, 75, 100]
const TIME_LIMITS: Array[int] = [5, 8, 10, 15]
const ROTATION := "rotation"

## Last choices this session, shared by both modes. Each mode with its own limit keeps it apart
## (sent as `kill_limit`): the team score, the Gun Game ladder length, King of the Block's points.
## `streaks`: mode -> killstreaks on, once picked for that mode (until then the mode's default,
## Streaks.default_for). A match setup preset (Profile.match_presets) holds a copy of it.
static var _choice := default_choice()
const MODE_IDS: Array[String] = ["ffa", "tdm", "gungame", "koth", "infected", "tactical"]
const MODE_HINTS := {
	"ffa": "Bots fill every empty slot up to the player count.",
	"tdm": "Two teams, bots fill both evenly. The kill limit is the team score; friendly fire is off.",
	"gungame": "Everyone climbs the same ladder of guns, one step per kill, and finishes on the knife. A knife kill also knocks the victim down a step. No grenades; Rocket Party and Snipers Only are off.",
	"koth": "A glowing zone moves every minute (10 s warning). Stand in it alone for a point a second; two or more contest it. First to the score limit wins.",
	"infected": "10 s in, one player turns Infected: melee only (their own melee weapon), faster, tougher. Everyone they kill turns too. Survivors win if any are left at the end. Rocket Party and Snipers Only are off.",
	"tactical": "25 v 25 in Block HQ, bots fill every slot. 30 s of planning behind barriers, then find your weapons: everyone starts with their melee weapon. One life; the last team standing wins.",
}
## One line under each mode card's name.
const MODE_TAGS := {
	"ffa": "Everyone for themselves",
	"tdm": "Two teams, team kills count",
	"gungame": "A new gun with every kill",
	"koth": "Hold the moving zone alone",
	"infected": "Outlast the spreading horde",
	"tactical": "25 v 25, plan, one life",
}
const MODE_COLORS := {
	"ffa": Color("ff8a4c"), "tdm": Color("4fa3ff"), "gungame": Color("ffc531"),
	"koth": Color("c58bff"), "infected": Color("7be05a"), "tactical": Color("9fb3c8"),
}


## Small code-drawn emblem on a mode card.
class ModeIcon extends Control:
	var mode := "ffa"
	var color := Color.WHITE

	func _init(p_mode: String, p_color: Color) -> void:
		mode = p_mode
		color = p_color
		custom_minimum_size = Vector2(40, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 20.0, Color(color, 0.18))
		var w := 3.0
		match mode:
			"ffa":
				draw_arc(c, 10.0, 0.0, TAU, 32, color, w, true)
				for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(c + d * 6.0, c + d * 15.0, color, w, true)
			"tdm":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -11), c + Vector2(-1, 3), c + Vector2(-17, 3)]), color)
				draw_rect(Rect2(c + Vector2(2, -6), Vector2(14, 14)), Color("ff8a4c"))
			"gungame":
				for i in 3:
					draw_rect(Rect2(c + Vector2(-13 + i * 9, 8 - i * 7), Vector2(7, 6 + i * 7)), color)
			"koth":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-13, 9), c + Vector2(-13, -7), c + Vector2(-6, 0),
					c + Vector2(0, -11), c + Vector2(6, 0), c + Vector2(13, -7), c + Vector2(13, 9)]), color)
			"infected":
				draw_circle(c, 12.0, color)
				draw_circle(c + Vector2(-4.5, -2), 2.6, Color(0.05, 0.12, 0.05))
				draw_circle(c + Vector2(4.5, -2), 2.6, Color(0.05, 0.12, 0.05))
				draw_line(c + Vector2(-5, 5), c + Vector2(5, 5), Color(0.05, 0.12, 0.05), 2.0, true)
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
var _custom_grid: GridContainer
var _difficulty_row: HBoxContainer
## Port and address rows, only shown for the DIRECT connection.
var _direct_rows: Array[Control] = []
## Waiting for Steam/WebRTC to set up hosting; leaving the page cancels it.
var _host_pending := false
var _kill_row: HBoxContainer
var _team_kill_row: HBoxContainer
var _ladder_row: HBoxContainer
var _koth_row: HBoxContainer
var _time_row: HBoxContainer
var _mutator_row: HBoxContainer
var _streak_row: HBoxContainer
## Map preview rects still waiting for their texture.
var _preview_queue: Array[TextureRect] = []
## Mode cards in MODE_IDS order (a ButtonGroup of toggles).
var _mode_row: Container
## Rule rows (name label and control) and the modes that show them.
var _mode_rules: Array = []
var _rules_hint: Label
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
static func default_choice() -> Dictionary:
	return {"mode": "ffa", "map": ROTATION, "bots_fill": 8, "difficulty": 1, "kill_limit": 20,
		"team_kill_limit": TeamDeathmatch.DEFAULT_KILL_LIMIT, "ladder": GunGame.max_length(),
		"koth_limit": KingOfTheBlock.DEFAULT_SCORE_LIMIT, "time_minutes": 8, "mutators": true, "link": Net.Link.DIRECT,
		"streaks": {}}


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
	for pair: Array in [["kill_limit", KILL_LIMITS], ["team_kill_limit", TEAM_KILL_LIMITS], ["ladder", GunGame.LENGTHS],
			["koth_limit", KingOfTheBlock.LIMITS], ["time_minutes", TIME_LIMITS]]:
		var v := _int(d.get(pair[0]), -1)
		if (pair[1] as Array).has(v):
			out[pair[0]] = v
	if typeof(d.get("mutators")) == TYPE_BOOL:
		out.mutators = d.mutators
	var link := _int(d.get("link"), -1)
	if link in [Net.Link.DIRECT, Net.Link.STEAM, Net.Link.WEBRTC]:
		out.link = link
	var streaks: Variant = d.get("streaks", {})
	if typeof(streaks) == TYPE_DICTIONARY:
		for m: String in MODE_IDS:
			if typeof((streaks as Dictionary).get(m)) == TYPE_BOOL:
				out.streaks[m] = streaks[m]
	return out


## A whole number from saved data (JSON numbers are floats), or `fallback`.
static func _int(v: Variant, fallback: int) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else fallback


## A copy of the current choices (what SAVE stores in a preset).
static func current_choice() -> Dictionary:
	return _choice.duplicate(true)


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("HOST GAME" if hosting else "PLAY VS BOTS",
		"Friends join by room code, Wi-Fi or Steam. Bots fill the empty slots." if hosting else "Offline match against bots."))
	var body := UIKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	# Left: one big card per mode.
	var modes := UIKit.vbox(8)
	modes.custom_minimum_size.x = 262
	body.add_child(modes)
	modes.add_child(UIKit.label("MODE", &"SubheaderLabel"))
	_mode_row = UIKit.vbox(8)
	_mode_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modes.add_child(_mode_row)
	var mode_group := ButtonGroup.new()
	for id: String in MODE_IDS:
		_mode_row.add_child(_mode_card(id, mode_group))

	# Middle: map preview cards.
	var mv := UIKit.vbox(8)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mv)
	var map_head := UIKit.hbox(12)
	mv.add_child(map_head)
	map_head.add_child(UIKit.label("MAP", &"SubheaderLabel"))
	_map_desc = UIKit.label("", &"DimLabel")
	_map_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_map_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_desc.add_theme_font_size_override("font_size", 14)
	map_head.add_child(_map_desc)
	# Built-in maps, then the playable custom maps (Map Editor) under CUSTOM; they scroll once
	# custom maps don't fit.
	var map_scroll := UIKit.pad_friendly(ScrollContainer.new())
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_child(map_scroll)
	var map_list := UIKit.vbox(10)
	map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_scroll.add_child(map_list)
	var grid := GridContainer.new()
	grid.columns = 3
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
	# Tactical's map; the only card shown in that mode.
	_add_map_card(grid, group, Data.TACTICAL_MAP, Data.MAPS[Data.TACTICAL_MAP].name, Data.MAPS[Data.TACTICAL_MAP].desc)
	_custom_head = UIKit.label("CUSTOM", &"SubheaderLabel")
	map_list.add_child(_custom_head)
	_custom_grid = GridContainer.new()
	_custom_grid.columns = 3
	_custom_grid.add_theme_constant_override("h_separation", 10)
	_custom_grid.add_theme_constant_override("v_separation", 10)
	map_list.add_child(_custom_grid)
	_refresh_custom_maps()

	# Right: presets strip, the rules that apply to the mode, START.
	var rules_panel := UIKit.panel()
	rules_panel.custom_minimum_size.x = 384
	body.add_child(rules_panel)
	var rv := UIKit.vbox(10)
	rules_panel.add_child(rv)
	_build_presets(rv)
	rv.add_child(UIKit.label("RULES", &"SubheaderLabel"))
	# The rules (and the host's connection rows) scroll when a mode's rows outgrow a 720p window,
	# so the status line and the start button always stay on screen below them.
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(scroll)
	var sv := UIKit.vbox(10)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sv)
	var rules := GridContainer.new()
	rules.columns = 2
	rules.add_theme_constant_override("h_separation", 10)
	rules.add_theme_constant_override("v_separation", 8)
	sv.add_child(rules)

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
	_mode_rule(rules, ["ffa", "tdm", "gungame", "koth", "infected"])
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
	_mode_rule(rules, ["tdm"])
	var ladder_names: Array[String] = []
	for n in GunGame.LENGTHS:
		ladder_names.append("%d" % (n - 1) if n < GunGame.max_length() else "ALL %d" % (n - 1))
	_ladder_row = _segmented(ladder_names, GunGame.LENGTHS.find(_choice.ladder),
		func(i: int) -> void: _choice.ladder = GunGame.LENGTHS[i])
	_rule(rules, "GUNS", _ladder_row)
	_mode_rule(rules, ["gungame"])
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
	_mode_rule(rules, ["ffa", "tdm", "gungame", "koth", "infected"])
	_streak_row = _segmented(["ON", "OFF"] as Array[String], 0 if _streaks_on() else 1,
		func(i: int) -> void: _choice.streaks[_choice.mode] = i == 0)
	_rule(rules, "STREAKS", _streak_row)
	_rules_hint = UIKit.label(MODE_HINTS.ffa, &"DimLabel")
	_rules_hint.add_theme_font_size_override("font_size", 13)
	_rules_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(_rules_hint)

	if hosting:
		sv.add_child(HSeparator.new())
		_build_host_section(sv)

	_status = UIKit.label("", &"DimLabel")
	_status.add_theme_font_size_override("font_size", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_status)
	_start = UIKit.button("START HOSTING" if hosting else "START MATCH", &"PrimaryButton")
	_start.add_theme_font_size_override("font_size", 24)
	_start.custom_minimum_size.y = 58
	_start.pressed.connect(_on_start)
	rv.add_child(_start)

	Net.status.connect(_on_status)
	back_requested.connect(func() -> void:
		if _host_pending:
			Net.leave())
	_select_map(_choice.map)
	_apply_mode()


## A big selectable mode card: emblem, name and a one-line description.
func _mode_card(id: String, group: ButtonGroup) -> Button:
	var card := UIKit.button("", &"CardButton")
	card.toggle_mode = true
	card.button_group = group
	card.name = id
	card.custom_minimum_size = Vector2(0, 62)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.button_pressed = id == _choice.mode
	card.pressed.connect(func() -> void: pick_mode(id))
	var h := UIKit.hbox(12)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -10
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	h.add_child(ModeIcon.new(id, MODE_COLORS[id]))
	var v := UIKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var title := UIKit.label(str(Data.MODES[id].name).to_upper(), &"ValueLabel")
	title.add_theme_font_size_override("font_size", 16)
	v.add_child(title)
	var tag := UIKit.label(MODE_TAGS[id], &"DimLabel")
	tag.add_theme_font_size_override("font_size", 13)
	v.add_child(tag)
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


## (Re)builds the CUSTOM cards from the saved playable maps (CustomMaps.playable), each with its
## preview; hidden when there are none or in Tactical. A picked custom map that is gone falls
## back to the rotation.
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
			_add_map_card(_custom_grid, _map_group, ids[i], names[i], "Custom map · %d x %d · %d spawns · %s" % [g.size.x, g.size.z, m.spawns.size(), str(m.time_of_day)])
	if CustomMaps.is_custom(_choice.map) and not ids.has(_choice.map):
		_choice.map = ROTATION
	_custom_head.visible = not ids.is_empty() and _choice.mode != "tactical"


## Sets every control to `_choice`.
func _show_choice() -> void:
	_players_slider.set_value_no_signal(_choice.bots_fill)
	_update_players_label()
	_pick_segment(_difficulty_row, _choice.difficulty)
	_pick_segment(_kill_row, KILL_LIMITS.find(_choice.kill_limit))
	_pick_segment(_team_kill_row, TEAM_KILL_LIMITS.find(_choice.team_kill_limit))
	_pick_segment(_ladder_row, GunGame.LENGTHS.find(_choice.ladder))
	_pick_segment(_koth_row, KingOfTheBlock.LIMITS.find(_choice.koth_limit))
	_pick_segment(_time_row, TIME_LIMITS.find(_choice.time_minutes))
	_pick_segment(_mutator_row, 0 if _choice.mutators else 1)
	if _link_row != null:
		_pick_segment(_link_row, [Net.Link.DIRECT, Net.Link.STEAM, Net.Link.WEBRTC].find(_choice.link))
		_update_link_rows()
	_select_map(_choice.map)
	_pick_segment(_mode_row, MODE_IDS.find(_choice.mode))
	_apply_mode()


## Shows the rules that apply to the chosen mode (the others keep their choices for switching
## back). Tactical fixes the map, player count, kill rule and mutators: only its own map card.
func _apply_mode() -> void:
	var tactical: bool = _choice.mode == "tactical"
	for entry: Array in _mode_rules:
		for c: Control in entry[0]:
			c.visible = (entry[1] as Array).has(_choice.mode)
	_rules_hint.text = MODE_HINTS[_choice.mode]
	_pick_segment(_streak_row, 0 if _streaks_on() else 1)
	for b in _map_group.get_buttons():
		b.visible = (b.get_meta(&"map_id") == Data.TACTICAL_MAP) == tactical
	_custom_head.visible = _custom_grid.get_child_count() > 0 and not tactical
	# Tactical's single card keeps a card's size instead of filling the whole column.
	_map_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if tactical else Control.SIZE_EXPAND_FILL
	if tactical:
		for b in _map_group.get_buttons():
			b.set_pressed_no_signal(b.get_meta(&"map_id") == Data.TACTICAL_MAP)
		_map_desc.text = Data.MAPS[Data.TACTICAL_MAP].desc
	else:
		_select_map(_choice.map)


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
	var h: Container = UIKit.hbox(4)
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
	card.custom_minimum_size = Vector2(150, 120)
	# Custom map ids hold characters a node name can't, so cards are found by their meta.
	card.name = id.validate_node_name()
	card.set_meta(&"map_id", id)
	card.set_meta(&"desc", desc)
	card.pressed.connect(func() -> void: _select_map(id))
	if id == Data.TACTICAL_MAP:
		card.custom_minimum_size.y = 300
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
	if id != Data.TACTICAL_MAP:
		_choice.map = id
	# set_pressed_no_signal skips the ButtonGroup, so release the other cards here.
	for b in _map_group.get_buttons():
		var on: bool = b.get_meta(&"map_id") == id
		b.set_pressed_no_signal(on)
		if on:
			_map_desc.text = b.get_meta(&"desc")


func _build_host_section(parent: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	var links: Array[int] = [Net.Link.DIRECT, Net.Link.STEAM, Net.Link.WEBRTC]
	var link_names: Array[String] = ["CODE · WI-FI", "STEAM", "WEBRTC"]
	_link_row = _segmented(link_names, links.find(_choice.link), func(i: int) -> void:
		_choice.link = links[i]
		_update_link_rows())
	_rule(grid, "LINK", _link_row)

	# One row per address, then the port (only joining by address uses it, and only over the
	# internet does it need forwarding).
	_port_edit = LineEdit.new()
	_port_edit.text = str(Net.DEFAULT_PORT)
	_port_edit.max_length = 5
	_port_edit.custom_minimum_size.x = 84
	_port_edit.add_theme_font_size_override("font_size", 15)
	_port_edit.tooltip_text = "Port for joining by address. Forward it only for internet joins by address."
	var addresses := NetLinkAddresses.local_addresses()
	if addresses.is_empty():
		var none := UIKit.label("No local network found.", &"DimLabel")
		none.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_direct_rule(grid, "ADDRESS", none)
	for i in addresses.size():
		var ip: String = addresses[i].address
		var row := UIKit.hbox(6)
		var ip_label := UIKit.label(ip, &"ValueLabel")
		ip_label.add_theme_font_size_override("font_size", 16)
		ip_label.add_theme_color_override("font_color", UITheme.ACCENT_2)
		ip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ip_label)
		var kind := UIKit.label(str(addresses[i].kind).to_upper(), &"SmallLabel")
		kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(kind)
		var copy := UIKit.button("COPY", &"ChipButton")
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(ip)
			_status.text = "Copied %s to the clipboard." % ip)
		row.add_child(copy)
		_direct_rule(grid, "ADDRESS" if i == 0 else "", row)
	var port_row := UIKit.hbox(6)
	port_row.add_child(_port_edit)
	_direct_rule(grid, "PORT", port_row)
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
		rows.append(["MAP", "Rotation" if cfg.map == ROTATION else MapBuilder.map_name(str(cfg.map))])
		rows.append(["PLAYERS", "%d players" % int(cfg.bots_fill)])
	rows.append(["BOTS", "%s bots" % Data.DIFFICULTY_NAMES[int(cfg.difficulty)]])
	match mode:
		"ffa":
			rows.append(["KILL LIMIT", "%d kills" % int(cfg.kill_limit)])
		"tdm":
			rows.append(["TEAM KILLS", "%d team kills" % int(cfg.kill_limit)])
		"gungame":
			rows.append(["LADDER", "%d guns" % (int(cfg.kill_limit) - 1)])
		"koth":
			rows.append(["POINTS", "%d points" % int(cfg.kill_limit)])
	rows.append(["TIME LIMIT", "%d min" % (int(cfg.time_limit) / 60)])
	if mode != "tactical":
		rows.append(["MUTATORS", "Random mutators" if cfg.mutators else "No mutators"])
	rows.append(["KILLSTREAKS", "Killstreaks on" if cfg.streaks else "Killstreaks off"])
	return rows


## The Net config a set of setup choices starts.
static func config_from(choice: Dictionary) -> Dictionary:
	return {
		"mode": choice.mode,
		"map": choice.map,
		"bots_fill": choice.bots_fill,
		"difficulty": choice.difficulty,
		"kill_limit": {"tdm": choice.team_kill_limit, "gungame": choice.ladder, "koth": choice.koth_limit}.get(choice.mode, choice.kill_limit),
		"time_limit": int(choice.time_minutes) * 60,
		"mutators": choice.mutators,
		"streaks": bool(choice.streaks.get(choice.mode, Streaks.default_for(choice.mode))),
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
