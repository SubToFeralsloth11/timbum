class_name PauseMenu
extends Control
## In-match pause overlay. Offline matches freeze while it is open (the HUD calls
## World.set_frozen, and this node runs with PROCESS_MODE_ALWAYS); online the match keeps
## running. The HUD owner shows/hides it (`visible`, or `open()` / `close()`) and listens to
## `resume_requested`. Becoming visible frees the mouse, resets to the main panel and
## animates in. While visible it consumes "pause" / "ui_cancel" in `_input` (it is a
## child of the HUD, so it sees Esc first): Esc closes the settings sub-panel, or
## requests resume.

signal resume_requested

var _dim: ColorRect
var _menu: PanelContainer
var _settings: SettingsPanel
var _resume_button: Button
var _hint: Label
## Host of an online match: how friends can join (room code, Wi-Fi, Steam invite).
var _invite: VBoxContainer


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.015, 0.03, 0.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_menu = UIKit.panel()
	_menu.custom_minimum_size = Vector2(420, 0)
	center.add_child(_menu)
	var v := UIKit.vbox(12)
	_menu.add_child(v)
	v.add_child(UIKit.label("PAUSED", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	_hint = UIKit.label("", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_hint)
	v.add_child(HSeparator.new())
	_invite = UIKit.vbox(6)
	v.add_child(_invite)
	Net.invite_changed.connect(_refresh_invite)
	_resume_button = UIKit.button("RESUME", &"PrimaryButton")
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	v.add_child(_resume_button)
	var settings_button := UIKit.button("SETTINGS")
	settings_button.pressed.connect(_open_settings)
	v.add_child(settings_button)
	var leave := UIKit.button("LEAVE MATCH", &"DangerButton")
	leave.pressed.connect(func() -> void: Net.leave())
	v.add_child(leave)

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	center.add_child(_settings)
	visibility_changed.connect(_on_visibility_changed)


func open() -> void:
	visible = true


func close() -> void:
	visible = false


func _on_visibility_changed() -> void:
	if not visible:
		if _settings.visible:
			_settings.close()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hint.text = "The match is paused." if Net.offline else "The match keeps running."
	_refresh_invite()
	_settings.visible = false
	_menu.visible = true
	_animate_in(_menu)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_resume_button.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _settings.visible:
			_settings.close()
		else:
			resume_requested.emit()


func _open_settings() -> void:
	_menu.visible = false
	_settings.visible = true
	_settings.refresh()
	_animate_in(_settings)


func _close_settings() -> void:
	if not _settings.visible and _menu.visible:
		return
	_settings.visible = false
	_menu.visible = true
	_animate_in(_menu)


func _refresh_invite() -> void:
	for c in _invite.get_children():
		c.queue_free()
	_invite.visible = not Net.offline and multiplayer.is_server() and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer
	if not _invite.visible:
		return
	_invite.add_child(UIKit.label("INVITE FRIENDS", &"SubheaderLabel"))
	if not Net.room_code.is_empty():
		var row := UIKit.hbox(8)
		var code := UIKit.label(Net.room_code, &"ValueLabel")
		code.add_theme_font_size_override("font_size", 18)
		code.add_theme_color_override("font_color", UITheme.ACCENT_2)
		code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(code)
		var copy := UIKit.button("COPY", &"IconButton")
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(Net.room_code)
			copy.text = "COPIED")
		row.add_child(copy)
		_invite.add_child(row)
		_invite_line("Friends paste this under Join > Room code.")
	elif not Net.room_code_error.is_empty():
		_invite_line(Net.room_code_error)
	elif Net.link == Net.Link.DIRECT:
		_invite_line("Getting a room code...")
	match Net.link:
		Net.Link.DIRECT:
			_invite_line("Same Wi-Fi: they'll see your game under Join.")
			for entry in NetLinkAddresses.local_addresses():
				_invite_line("%s  %s:%d" % [entry.kind, entry.address, Net.host_port])
		Net.Link.STEAM:
			var invite := UIKit.button("INVITE STEAM FRIENDS")
			invite.pressed.connect(func() -> void:
				if not Net.invite_steam_friends():
					invite.text = "STEAM OVERLAY UNAVAILABLE: SHARE THE CODE")
			_invite.add_child(invite)


func _invite_line(text: String) -> void:
	var l := UIKit.label(text, &"SmallLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_invite.add_child(l)


func _animate_in(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.94, 0.94)
	c.modulate.a = 0.0
	var t := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE, 0.22)
	t.tween_property(c, "modulate:a", 1.0, 0.15)
