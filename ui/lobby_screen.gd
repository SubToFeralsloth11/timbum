class_name LobbyScreen
extends Control
## Pre-match lobby (scenes/lobby.tscn) every peer of an online session sits in before the first
## match: the players with their ready ticks, level and prestige; the map vote (Net.lobby.options);
## the host's match rules; how friends can join (host); a small chat. The state lives in Net
## (Net.lobby, server-authoritative); this screen only shows it and sends this player's ready,
## vote and chat lines.

const CHAT_LINES := 8

var _players_title: Label
var _player_rows: VBoxContainer
var _vote_grid: GridContainer
var _vote_group := ButtonGroup.new()
## One card per Net.lobby.options entry, in order.
var _vote_cards: Array[Button] = []
var _vote_counts: Array[Label] = []
var _ready_button: Button
var _start_button: Button
var _status: Label
var _hint: Label
var _chat_log: VBoxContainer
var _chat_input: LineEdit
## Seconds left on the countdown as last reported by the server, counted down here (-1: none).
var _countdown := -1.0
## [TextureRect, map id] previews still to draw.
var _preview_queue: Array = []


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_music(&"menu")
	var bg := ColorRect.new()
	bg.color = Color("10162a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 40)
	m.add_theme_constant_override("margin_top", 26)
	m.add_theme_constant_override("margin_bottom", 24)
	add_child(m)
	var page := UIKit.vbox(16)
	m.add_child(page)

	var header := UIKit.hbox(18)
	page.add_child(header)
	var titles := UIKit.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UIKit.label("LOBBY", &"HeaderLabel"))
	titles.add_child(UIKit.label("%s  ·  hosted by %s" % [str(Data.MODES[str(Net.config.mode)].name),
		str(Net.players[1].name) if Net.players.has(1) else "the host"], &"DimLabel"))
	header.add_child(titles)
	var leave := UIKit.button("LEAVE", &"DangerButton")
	leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(func() -> void: Net.leave())
	header.add_child(leave)

	var body := UIKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	body.add_child(_build_players())
	body.add_child(_build_vote())
	body.add_child(_build_settings())

	var footer := UIKit.hbox(14)
	page.add_child(footer)
	var texts := UIKit.vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(texts)
	_status = UIKit.label("", &"ValueLabel")
	_status.add_theme_font_size_override("font_size", 18)
	texts.add_child(_status)
	_hint = UIKit.label("", &"SmallLabel")
	texts.add_child(_hint)
	if multiplayer.is_server():
		_start_button = UIKit.button("START NOW", &"GoldButton")
		_start_button.custom_minimum_size = Vector2(190, 56)
		_start_button.tooltip_text = "Start the match without waiting for everyone."
		_start_button.pressed.connect(func() -> void: Net.lobby_start())
		footer.add_child(_start_button)
	_ready_button = UIKit.button("READY", &"PrimaryButton")
	_ready_button.toggle_mode = true
	_ready_button.custom_minimum_size = Vector2(230, 56)
	_ready_button.add_theme_font_size_override("font_size", 24)
	_ready_button.toggled.connect(func(on: bool) -> void: Net.lobby_set_ready(on))
	footer.add_child(_ready_button)

	Net.lobby_changed.connect(_refresh)
	Net.players_changed.connect(_refresh)
	Net.lobby_chat.connect(_on_chat)
	Profile.changed.connect(_refresh_hint)
	Profile.device_changed.connect(_refresh_hint)
	_refresh()
	_ready_button.grab_focus.call_deferred()


func _panel(title: String, ratio: float) -> VBoxContainer:
	var p := UIKit.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	var v := UIKit.vbox(10)
	p.add_child(v)
	if not title.is_empty():
		v.add_child(UIKit.label(title, &"SubheaderLabel"))
	v.set_meta(&"panel", p)
	return v


func _build_players() -> Control:
	var v := _panel("", 1.0)
	_players_title = UIKit.label("PLAYERS", &"SubheaderLabel")
	v.add_child(_players_title)
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_player_rows = UIKit.vbox(6)
	_player_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_player_rows)
	var bots := UIKit.label("Bots fill the empty slots." if str(Net.config.mode) != "tactical" else "Bots fill both teams to %d v %d." % [Tactical.PLAYERS / 2, Tactical.PLAYERS / 2], &"SmallLabel")
	bots.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(bots)
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("CHAT", &"SmallLabel"))
	_chat_log = UIKit.vbox(2)
	_chat_log.custom_minimum_size.y = 120
	v.add_child(_chat_log)
	_chat_input = LineEdit.new()
	_chat_input.max_length = World.MAX_CHAT_LENGTH
	_chat_input.placeholder_text = "Say something..."
	_chat_input.text_submitted.connect(func(text: String) -> void:
		if not text.strip_edges().is_empty():
			Net.lobby_say(text)
		_chat_input.clear())
	v.add_child(_chat_input)
	return v.get_meta(&"panel")


func _build_vote() -> Control:
	var options: Array = Net.lobby.get("options", [])
	var v := _panel("MAP VOTE" if not options.is_empty() else "MAP", 1.5)
	if options.is_empty():
		# Tactical: one map, no vote.
		var card := _map_card(Data.TACTICAL_MAP, false)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_NONE
		v.add_child(card)
		v.add_child(UIKit.label("Tactical always plays %s." % Data.MAPS[Data.TACTICAL_MAP].name, &"DimLabel"))
		return v.get_meta(&"panel")
	_vote_grid = GridContainer.new()
	_vote_grid.columns = 2
	_vote_grid.add_theme_constant_override("h_separation", 10)
	_vote_grid.add_theme_constant_override("v_separation", 10)
	_vote_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_vote_grid)
	for i in options.size():
		var card := _map_card(str(options[i]), true)
		card.pressed.connect(func() -> void: Net.lobby_vote(i))
		_vote_grid.add_child(card)
		_vote_cards.append(card)
	var keep := "the rotation's first map" if str(Net.config.map) == "rotation" else str(Data.MAPS[str(Net.config.map)].name)
	var note := UIKit.label("The most votes picks the first map; no votes or a tie plays %s." % keep, &"SmallLabel")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	return v.get_meta(&"panel")


## A selectable map card: preview (a "?" for RANDOM_MAP), name and, for a vote, the count.
func _map_card(map_id: String, vote: bool) -> Button:
	var card := UIKit.button("", &"CardButton")
	card.toggle_mode = vote
	if vote:
		card.button_group = _vote_group
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(150, 110)
	var v := UIKit.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var frame := UIKit.panel(&"InsetPanel")
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	v.add_child(frame)
	if map_id == Net.RANDOM_MAP:
		var q := UIKit.label("?", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.add_theme_color_override("font_color", UITheme.ACCENT)
		frame.add_child(q)
	else:
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview_queue.append([pic, map_id])
		frame.add_child(pic)
	var row := UIKit.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var title := UIKit.label("RANDOM" if map_id == Net.RANDOM_MAP else str(Data.MAPS[map_id].name).to_upper(), &"ValueLabel")
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	if vote:
		var count := UIKit.label("", &"ValueLabel", HORIZONTAL_ALIGNMENT_RIGHT)
		count.add_theme_font_size_override("font_size", 16)
		count.add_theme_color_override("font_color", UITheme.ACCENT)
		row.add_child(count)
		_vote_counts.append(count)
	return card


func _build_settings() -> Control:
	var v := _panel("MATCH RULES", 1.0)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var cfg: Dictionary = Net.config
	for row: Array in MatchSetupScreen.describe_config(cfg):
		grid.add_child(UIKit.label(str(row[0]), &"SmallLabel"))
		var value := UIKit.label(str(row[1]), &"ValueLabel")
		value.add_theme_font_size_override("font_size", 15)
		grid.add_child(value)
	# Join info for the host (clients have none), as in the pause menu.
	if multiplayer.is_server():
		v.add_child(HSeparator.new())
		v.add_child(InviteBox.new())
	return v.get_meta(&"panel")


func _refresh() -> void:
	if not Net.in_lobby or _ready_button == null:
		return
	var ready_ids: Dictionary = Net.lobby.get("ready", {})
	var me := multiplayer.get_unique_id()
	# Player list: the host first, then in join order.
	for c in _player_rows.get_children():
		c.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	for pid: int in ids:
		_player_rows.add_child(_player_row(pid, ready_ids.has(pid), pid == me))
	_players_title.text = "PLAYERS  %d / %d" % [ids.size(), Data.MAX_PLAYERS]
	# Map vote.
	var options: Array = Net.lobby.get("options", [])
	var counts := Net.vote_counts(Net.lobby.get("votes", {}), options.size())
	var mine := int((Net.lobby.get("votes", {}) as Dictionary).get(me, -1))
	for i in _vote_cards.size():
		_vote_counts[i].text = "%d" % int(counts[i]) if int(counts[i]) > 0 else ""
		_vote_cards[i].set_pressed_no_signal(i == mine)
	_ready_button.set_pressed_no_signal(ready_ids.has(me))
	_ready_button.text = "CANCEL READY" if ready_ids.has(me) else "READY UP"
	_countdown = float(Net.lobby.get("countdown", -1.0))
	_refresh_status()
	_refresh_hint()


func _player_row(pid: int, is_ready: bool, is_me: bool) -> Control:
	var info: Dictionary = Net.players[pid]
	var row := UIKit.hbox(8)
	var tick := UIKit.label("READY" if is_ready else "WAITING", &"SmallLabel")
	tick.custom_minimum_size.x = 74
	tick.add_theme_color_override("font_color", UITheme.GOOD if is_ready else UITheme.TEXT_DIM)
	row.add_child(tick)
	var player_name := UIKit.label(Data.badged_name(str(info.name), int(info.get("prestige", 0))), &"ValueLabel")
	player_name.add_theme_font_size_override("font_size", 16)
	player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_name.clip_text = true
	if is_me:
		player_name.add_theme_color_override("font_color", UITheme.ACCENT)
	row.add_child(player_name)
	if pid == 1:
		row.add_child(UIKit.badge("HOST"))
	var lvl := UIKit.label("LVL %d" % int(info.get("level", 1)), &"SmallLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	lvl.custom_minimum_size.x = 56
	row.add_child(lvl)
	return row


func _refresh_status() -> void:
	var humans := Net.players.size()
	var n := Net.lobby_ready_count()
	var line := "%d of %d ready" % [n, humans]
	if _countdown >= 0.0:
		line += "  ·  starting in %d" % ceili(_countdown)
	elif humans > 1:
		line += "  ·  starts when everyone is ready, or %d s after %d are" % [int(Net.LOBBY_COUNTDOWN), Net.majority(humans)]
	else:
		line += "  ·  starts when you're ready"
	_status.text = line


func _refresh_hint() -> void:
	if _hint == null:
		return
	var host := "  ·  START NOW skips the wait" if multiplayer.is_server() else ""
	# Leaving is the menus' back input (Esc / B), not a bindable action.
	_hint.text = "%s chat  ·  %s leave%s" % [Profile.key_text("chat"), "B" if Profile.using_pad else "ESC", host]


func _process(delta: float) -> void:
	# One map preview per frame (MapBuilder builds each map once), so the lobby opens without a stall.
	if not _preview_queue.is_empty():
		var entry: Array = _preview_queue.pop_front()
		(entry[0] as TextureRect).texture = MapBuilder.preview(str(entry[1]))
	if _countdown > 0.0:
		var before := ceili(_countdown)
		_countdown = maxf(0.0, _countdown - delta)
		if ceili(_countdown) != before:
			_refresh_status()


func _on_chat(sender: String, text: String) -> void:
	var l := UIKit.label(text if sender.is_empty() else "%s: %s" % [sender, text], &"SmallLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM if sender.is_empty() else UITheme.TEXT)
	_chat_log.add_child(l)
	while _chat_log.get_child_count() > CHAT_LINES:
		var old := _chat_log.get_child(0)
		_chat_log.remove_child(old)
		old.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _chat_input.has_focus():
		if event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			_chat_input.release_focus()
			_ready_button.grab_focus()
		return
	if event.is_action_pressed(&"chat"):
		get_viewport().set_input_as_handled()
		_chat_input.grab_focus.call_deferred()
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Net.leave()
