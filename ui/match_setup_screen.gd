class_name MatchSetupScreen
extends MenuScreen
## Match configuration shared by "Play vs Bots" (offline) and "Host Game" (ENet server).

const KILL_LIMITS: Array[int] = [10, 15, 20, 30, 50]
const TIME_LIMITS: Array[int] = [5, 8, 10, 15]
const ROTATION := "rotation"

## Last choices this session, shared by both modes.
static var _choice := {"mode": "ffa", "map": ROTATION, "bots_fill": 8, "difficulty": 1, "kill_limit": 20, "time_minutes": 8, "mutators": true, "link": Net.Link.DIRECT}
const MODE_IDS: Array[String] = ["ffa", "tactical"]
const FFA_HINT := "Bots fill every empty slot up to the player count."
const TACTICAL_HINT := "25 v 25 in Block HQ, bots fill every slot. 30 s of planning behind barriers, then find your weapons: everyone starts with a knife. One life; the last team standing wins."

const LINK_HINTS := {
	Net.Link.DIRECT: "Wi-Fi friends see it under Join; others use the room code.",
	Net.Link.STEAM: "Both players need Steam open. Invite from the pause menu.",
	Net.Link.WEBRTC: "Fallback if room codes fail. Code is in the pause menu.",
}

var hosting := false

var _map_desc: Label
var _players_label: Label
var _port_edit: LineEdit
var _status: Label
var _start: Button
var _players_slider: HSlider
var _map_group: ButtonGroup
var _difficulty_row: HBoxContainer
## Port and address rows, only shown for the DIRECT connection.
var _direct_rows: Array[Control] = []
## Waiting for Steam/WebRTC to set up hosting; leaving the page cancels it.
var _host_pending := false
var _kill_row: HBoxContainer
var _time_row: HBoxContainer
var _mutator_row: HBoxContainer
## Map preview rects still waiting for their texture.
var _preview_queue: Array[TextureRect] = []
var _mode_row: HBoxContainer
## Rule rows (name label and control) that only apply to deathmatch.
var _ffa_rules: Array[Control] = []
var _rules_hint: Label


func _init(host_mode: bool) -> void:
	super()
	hosting = host_mode


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("HOST GAME" if hosting else "PLAY VS BOTS",
		"Friends join by room code, on the same Wi-Fi or through Steam. Bots fill the empty slots." if hosting else "Offline match against bots."))
	var body := UIKit.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	# Map picker
	var map_panel := UIKit.panel()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 1.55
	body.add_child(map_panel)
	var mv := UIKit.vbox(12)
	map_panel.add_child(mv)
	mv.add_child(UIKit.label("MAP", &"SubheaderLabel"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_child(grid)
	var group := ButtonGroup.new()
	_map_group = group
	_add_map_card(grid, group, ROTATION, "Rotation", "Play every map in turn.")
	for id: String in Data.MAP_ROTATION:
		_add_map_card(grid, group, id, Data.MAPS[id].name, Data.MAPS[id].desc)
	# Tactical's map; the only card shown in that mode.
	_add_map_card(grid, group, Data.TACTICAL_MAP, Data.MAPS[Data.TACTICAL_MAP].name, Data.MAPS[Data.TACTICAL_MAP].desc)
	_map_desc = UIKit.label("", &"DimLabel")
	_map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mv.add_child(_map_desc)

	# Rules
	var rules_panel := UIKit.panel()
	rules_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rules_panel)
	var rv := UIKit.vbox(12)
	rules_panel.add_child(rv)
	rv.add_child(UIKit.label("MATCH RULES", &"SubheaderLabel"))
	var rules := GridContainer.new()
	rules.columns = 2
	rules.add_theme_constant_override("h_separation", 14)
	rules.add_theme_constant_override("v_separation", 12)
	rv.add_child(rules)

	var mode_names: Array[String] = []
	for id in MODE_IDS:
		mode_names.append(str(Data.MODES[id].name).to_upper())
	_mode_row = _segmented(mode_names, MODE_IDS.find(_choice.mode), func(i: int) -> void:
		_choice.mode = MODE_IDS[i]
		_apply_mode())
	_rule(rules, "MODE", _mode_row)

	var players_row := UIKit.hbox(10)
	var players := HSlider.new()
	_players_slider = players
	players.min_value = 2
	players.max_value = Data.MAX_PLAYERS
	players.step = 1
	players.tick_count = Data.MAX_PLAYERS - 1
	players.ticks_on_borders = true
	players.value = _choice.bots_fill
	players.custom_minimum_size.y = 26
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	players.value_changed.connect(func(v: float) -> void:
		_choice.bots_fill = int(v)
		_update_players_label())
	players_row.add_child(players)
	_players_label = UIKit.label("", &"ValueLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_players_label.add_theme_font_size_override("font_size", 16)
	_players_label.custom_minimum_size.x = 104
	players_row.add_child(_players_label)
	_rule(rules, "PLAYERS", players_row)
	_ffa_rules.append_array([rules.get_child(rules.get_child_count() - 2), players_row])
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
	_rule(rules, "KILL LIMIT", _kill_row)
	_ffa_rules.append_array([rules.get_child(rules.get_child_count() - 2), _kill_row])
	var time_names: Array[String] = []
	for t in TIME_LIMITS:
		time_names.append("%d MIN" % t)
	_time_row = _segmented(time_names, TIME_LIMITS.find(_choice.time_minutes),
		func(i: int) -> void: _choice.time_minutes = TIME_LIMITS[i])
	_rule(rules, "TIME LIMIT", _time_row)
	var mutator_names: Array[String] = ["RANDOM", "OFF"]
	_mutator_row = _segmented(mutator_names, 0 if _choice.mutators else 1,
		func(i: int) -> void: _choice.mutators = i == 0)
	_rule(rules, "MUTATORS", _mutator_row)
	_ffa_rules.append_array([rules.get_child(rules.get_child_count() - 2), _mutator_row])
	_rules_hint = UIKit.label(FFA_HINT, &"DimLabel")
	_rules_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_rules_hint)

	if hosting:
		rv.add_child(HSeparator.new())
		_build_host_section(rv)

	rv.add_child(UIKit.spacer(false))
	_status = UIKit.label("", &"DimLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_status)
	_start = UIKit.button("START HOSTING" if hosting else "START MATCH", &"PrimaryButton")
	_start.add_theme_font_size_override("font_size", 24)
	_start.custom_minimum_size.y = 56
	_start.pressed.connect(_on_start)
	rv.add_child(_start)

	Net.status.connect(_on_status)
	back_requested.connect(func() -> void:
		if _host_pending:
			Net.leave())
	_select_map(_choice.map)
	_apply_mode()


func on_shown() -> void:
	_status.text = LINK_HINTS[_choice.link] if hosting else ""
	_start.disabled = false
	# Choices are shared with the other mode's screen, which may have changed them.
	_players_slider.set_value_no_signal(_choice.bots_fill)
	_update_players_label()
	_pick_segment(_difficulty_row, _choice.difficulty)
	_pick_segment(_kill_row, KILL_LIMITS.find(_choice.kill_limit))
	_pick_segment(_time_row, TIME_LIMITS.find(_choice.time_minutes))
	_pick_segment(_mutator_row, 0 if _choice.mutators else 1)
	_select_map(_choice.map)
	_pick_segment(_mode_row, MODE_IDS.find(_choice.mode))
	_apply_mode()


## Tactical fixes the map, player count, kill rule and mutators: only its own map card and the
## rules that still apply are shown. The deathmatch choices are kept for switching back.
func _apply_mode() -> void:
	var tactical: bool = _choice.mode == "tactical"
	for c in _ffa_rules:
		c.visible = not tactical
	_rules_hint.text = TACTICAL_HINT if tactical else FFA_HINT
	for b in _map_group.get_buttons():
		b.visible = (b.name == Data.TACTICAL_MAP) == tactical
	if tactical:
		for b in _map_group.get_buttons():
			b.set_pressed_no_signal(b.name == Data.TACTICAL_MAP)
		_map_desc.text = Data.MAPS[Data.TACTICAL_MAP].desc
	else:
		_select_map(_choice.map)


func _pick_segment(row: HBoxContainer, selected: int) -> void:
	for i in row.get_child_count():
		(row.get_child(i) as Button).set_pressed_no_signal(i == selected)


func _rule_name(text: String) -> Label:
	var l := UIKit.label(text, &"SmallLabel")
	l.add_theme_color_override("font_color", UITheme.TEXT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _rule(grid: GridContainer, text: String, control: Control) -> void:
	grid.add_child(_rule_name(text))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _update_players_label() -> void:
	var bots: int = _choice.bots_fill - 1
	_players_label.text = "%d  ·  %d BOT%s" % [_choice.bots_fill, bots, "" if bots == 1 else "S"]


## Row of toggle buttons acting as a radio group.
func _segmented(names: Array[String], selected: int, on_pick: Callable) -> HBoxContainer:
	var h := UIKit.hbox(6)
	var group := ButtonGroup.new()
	for i in names.size():
		var b := UIKit.button(names[i], &"TabButton")
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
	card.custom_minimum_size = Vector2(170, 130)
	card.name = id
	card.set_meta(&"desc", desc)
	card.pressed.connect(func() -> void: _select_map(id))
	grid.add_child(card)
	var v := UIKit.vbox(6)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var pic_frame := UIKit.panel(&"InsetPanel")
	pic_frame.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.1, 0.15, 0.22), Color(0, 0, 0, 0.6), 2, 2, 0))
	pic_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic_frame.clip_contents = true
	v.add_child(pic_frame)
	if id == ROTATION:
		var strip := UIKit.hbox(2)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic_frame.add_child(strip)
		for map_id: String in Data.MAP_ROTATION:
			strip.add_child(_preview_rect(map_id))
	else:
		pic_frame.add_child(_preview_rect(id))
	var name_label := UIKit.label(title.to_upper(), &"ValueLabel")
	name_label.add_theme_font_size_override("font_size", 16)
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
		b.set_pressed_no_signal(b.name == id)
		if b.name == id:
			_map_desc.text = b.get_meta(&"desc")


func _build_host_section(parent: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	var links: Array[int] = [Net.Link.DIRECT, Net.Link.STEAM, Net.Link.WEBRTC]
	var link_names: Array[String] = ["CODE + WI-FI", "STEAM", "WEBRTC"]
	_rule(grid, "CONNECTION", _segmented(link_names, links.find(_choice.link), func(i: int) -> void:
		_choice.link = links[i]
		_update_link_rows()))

	# One row per address; the first also holds the port (only joining by address uses it, and
	# only over the internet does it need forwarding).
	_port_edit = LineEdit.new()
	_port_edit.text = str(Net.DEFAULT_PORT)
	_port_edit.max_length = 5
	_port_edit.custom_minimum_size.x = 84
	_port_edit.tooltip_text = "Port for joining by address. Forward it only for internet joins by address."
	var addresses := NetLinkAddresses.local_addresses()
	if addresses.is_empty():
		var row := UIKit.hbox(8)
		var none := UIKit.label("No local network found.", &"DimLabel")
		none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		none.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(none)
		row.add_child(UIKit.label("PORT", &"SmallLabel"))
		row.add_child(_port_edit)
		_direct_rule(grid, "ADDRESS", row)
	for i in addresses.size():
		var ip: String = addresses[i].address
		var row := UIKit.hbox(8)
		var ip_label := UIKit.label(ip, &"ValueLabel")
		ip_label.add_theme_font_size_override("font_size", 18)
		ip_label.add_theme_color_override("font_color", UITheme.ACCENT_2)
		ip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ip_label)
		var kind := UIKit.label(str(addresses[i].kind).to_upper(), &"SmallLabel")
		kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(kind)
		if i == 0:
			var port_label := UIKit.label("PORT", &"SmallLabel")
			port_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(port_label)
			row.add_child(_port_edit)
		var copy := UIKit.button("COPY", &"IconButton")
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(ip)
			_status.text = "Copied %s to the clipboard." % ip)
		row.add_child(copy)
		_direct_rule(grid, "ADDRESS" if i == 0 else "", row)
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



func _config() -> Dictionary:
	return {
		"mode": _choice.mode,
		"map": _choice.map,
		"bots_fill": _choice.bots_fill,
		"difficulty": _choice.difficulty,
		"kill_limit": _choice.kill_limit,
		"time_limit": int(_choice.time_minutes) * 60,
		"mutators": _choice.mutators,
	}


func _on_start() -> void:
	if not hosting:
		_start.disabled = true
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
	_status.remove_theme_color_override("font_color")
	_status.text = "Starting server on port %d..." % port if link == Net.Link.DIRECT else "Starting..."
	_host_pending = true
	var err: Error = await Net.host(port, _config(), link)
	_host_pending = false
	if err != OK and err != ERR_SKIP:
		_start.disabled = false
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
