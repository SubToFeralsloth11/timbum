class_name InviteBox
extends VBoxContainer
## How friends can join this session (host only): the room code with COPY, the same-Wi-Fi and
## address hints, or the Steam invite button. Shown in the pause menu and the pre-match lobby;
## hides itself offline and on clients, and follows Net.invite_changed (the code arrives late).


func _init() -> void:
	add_theme_constant_override("separation", 6)


func _ready() -> void:
	Net.invite_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	visible = not Net.offline and multiplayer.is_server() and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer
	if not visible:
		return
	add_child(UIKit.label("INVITE FRIENDS", &"SubheaderLabel"))
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
		add_child(row)
		_line("Friends paste this under Join > Room code.")
	elif not Net.room_code_error.is_empty() and Net.link == Net.Link.DIRECT:
		# The reason (e.g. the room code server is unreachable) goes to the log from Net; the
		# player needs to know what still works.
		_line("No room code (no internet). Friends on your network can join with the address below.")
	elif not Net.room_code_error.is_empty():
		_line(Net.room_code_error)
	elif Net.link == Net.Link.DIRECT:
		_line("Getting a room code...")
	match Net.link:
		Net.Link.DIRECT:
			_line("Same Wi-Fi: they'll see your game under Join.")
			for entry in NetLinkAddresses.local_addresses():
				_line("%s  %s:%d" % [entry.kind, entry.address, Net.host_port])
		Net.Link.STEAM:
			var invite := UIKit.button("INVITE STEAM FRIENDS")
			invite.pressed.connect(func() -> void:
				if not Net.invite_steam_friends():
					invite.text = "STEAM OVERLAY UNAVAILABLE: SHARE THE CODE")
			add_child(invite)


func _line(text: String) -> void:
	var l := UIKit.label(text, &"SmallLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
