class_name MatchSetupScreen
extends MenuScreen
## Match configuration shared by "Play vs Bots" (offline) and "Host Game" (ENet server).

const KILL_LIMITS: Array[int] = [10, 15, 20, 30, 50]
const TIME_LIMITS: Array[int] = [5, 8, 10, 15]
const ROTATION := "rotation"

## Last choices this session, shared by both modes.
static var _choice := {"map": ROTATION, "bots_fill": 8, "difficulty": 1, "kill_limit": 20, "time_minutes": 8}

var hosting := false

var _map_desc: Label
var _players_label: Label
var _port_edit: LineEdit
var _status: Label
var _start: Button
## Map preview rects still waiting for their texture.
var _preview_queue: Array[TextureRect] = []


func _init(host_mode: bool) -> void:
	super()
	hosting = host_mode


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("HOST GAME" if hosting else "PLAY VS BOTS",
		"Friends join you by IP. Bots fill the empty slots." if hosting else "Offline match against bots."))
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
	_add_map_card(grid, group, ROTATION, "Rotation", "Play every map in turn.")
	for id: String in Data.MAP_ROTATION:
		_add_map_card(grid, group, id, Data.MAPS[id].name, Data.MAPS[id].desc)
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

	var players_row := UIKit.hbox(10)
	var players := HSlider.new()
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
	_update_players_label()

	var difficulty_names: Array[String] = []
	for d in Data.DIFFICULTY_NAMES:
		difficulty_names.append(d.to_upper())
	_rule(rules, "BOTS", _segmented(difficulty_names, _choice.difficulty, func(i: int) -> void: _choice.difficulty = i))
	var kill_names: Array[String] = []
	for k in KILL_LIMITS:
		kill_names.append(str(k))
	_rule(rules, "KILL LIMIT", _segmented(kill_names, KILL_LIMITS.find(_choice.kill_limit),
		func(i: int) -> void: _choice.kill_limit = KILL_LIMITS[i]))
	var time_names: Array[String] = []
	for t in TIME_LIMITS:
		time_names.append("%d MIN" % t)
	_rule(rules, "TIME LIMIT", _segmented(time_names, TIME_LIMITS.find(_choice.time_minutes),
		func(i: int) -> void: _choice.time_minutes = TIME_LIMITS[i]))
	var hint := UIKit.label("Bots fill every empty slot up to the player count.", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(hint)

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
	_select_map(_choice.map)


func on_shown() -> void:
	_status.text = ""
	_start.disabled = false


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
	_choice.map = id
	var grid_card := find_child(id, true, false) as Button
	if grid_card != null:
		grid_card.set_pressed_no_signal(true)
		_map_desc.text = grid_card.get_meta(&"desc")


func _build_host_section(parent: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	_port_edit = LineEdit.new()
	_port_edit.text = str(Net.DEFAULT_PORT)
	_port_edit.max_length = 5
	var port_row := UIKit.hbox(10)
	_port_edit.custom_minimum_size.x = 100
	port_row.add_child(_port_edit)
	var port_hint := UIKit.label("Forward this port for internet play.", &"SmallLabel")
	port_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	port_row.add_child(port_hint)
	_rule(grid, "PORT", port_row)

	var addresses := lan_addresses()
	if addresses.is_empty():
		var none := UIKit.label("No local network found. Connect to Wi-Fi or Ethernet.", &"DimLabel")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rule(grid, "JOIN AT", none)
	for i in addresses.size():
		var ip := addresses[i]
		var row := UIKit.hbox(8)
		var ip_label := UIKit.label(ip, &"ValueLabel")
		ip_label.add_theme_font_size_override("font_size", 18)
		ip_label.add_theme_color_override("font_color", UITheme.ACCENT_2)
		ip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ip_label)
		var copy := UIKit.button("COPY", &"IconButton")
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(ip)
			_status.text = "Copied %s to the clipboard." % ip)
		row.add_child(copy)
		_rule(grid, "JOIN AT" if i == 0 else "", row)


## Private IPv4 addresses of this machine (what LAN friends type into Join).
static func lan_addresses() -> Array[String]:
	var out: Array[String] = []
	for addr in IP.get_local_addresses():
		if not addr.is_valid_ip_address() or ":" in addr:
			continue
		var p := addr.split(".")
		var a := int(p[0])
		var b := int(p[1])
		if a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31):
			if not out.has(addr):
				out.append(addr)
	out.sort()
	return out


func _config() -> Dictionary:
	return {
		"map": _choice.map,
		"bots_fill": _choice.bots_fill,
		"difficulty": _choice.difficulty,
		"kill_limit": _choice.kill_limit,
		"time_limit": int(_choice.time_minutes) * 60,
	}


func _on_start() -> void:
	if not hosting:
		_start.disabled = true
		_status.text = "Loading map..."
		Net.play_offline(_config())
		return
	var port := _port_edit.text.strip_edges().to_int()
	if not _port_edit.text.strip_edges().is_valid_int() or port < 1024 or port > 65535:
		Sfx.play(&"ui_error")
		_set_error("Port must be a number between 1024 and 65535.")
		return
	_start.disabled = true
	_status.remove_theme_color_override("font_color")
	_status.text = "Starting server on port %d..." % port
	var err := Net.host(port, _config())
	if err != OK:
		_start.disabled = false
		Sfx.play(&"ui_error")
		_set_error("Could not host on port %d: %s" % [port, error_string(err)])


func _set_error(text: String) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UITheme.BAD)


func _on_status(text: String) -> void:
	if not is_visible_in_tree():
		return
	_status.remove_theme_color_override("font_color")
	_status.text = text
	_start.disabled = false
