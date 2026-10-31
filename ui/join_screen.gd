class_name JoinScreen
extends MenuScreen
## Join a hosted game without knowing an IP: games on the same Wi-Fi are listed automatically,
## a room code works over the internet (noray, WebRTC "W-" codes or Steam lobby ids), Steam
## lobbies can be listed, and an address (IP, hostname, Tailscale/ZeroTier, playit.gg) still works.
## Remembers the last code and address in Profile settings.

## Status words that mean the attempt is over (Net reports free-form text).
const END_WORDS: Array[String] = ["fail", "lost", "disconnect", "refused", "timed out", "timeout", "error", "could not", "can't", "invalid", "full", "kicked", "closed", "mismatch", "no game", "no answer", "isn't", "doesn't", "unavailable"]

var _nearby: VBoxContainer
var _nearby_empty: Label
var _steam_button: Button
## Nearby rows from Wi-Fi discovery and from the last Steam lobby search.
var _lan_hosts: Array[Dictionary] = []
var _steam_lobbies: Array[Dictionary] = []
var _code: LineEdit
var _ip: LineEdit
var _port: LineEdit
var _join_buttons: Array[Button] = []
var _cancel: Button
## Join as a spectator (Net.join_as_spectator) for any of the joins on this page.
var _spectate: CheckButton
var _status: Label
var _spinner: Label
var _connecting := false
var _dots := 0.0
## Set when the page is left (Esc / BACK), cleared by on_shown: the deferred room-code focus checks it.
var _left := true


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("JOIN GAME", "Pick a game on your Wi-Fi, or paste the room code your friend sent you."))
	var body := UIKit.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	# Nearby games (same Wi-Fi) + Steam lobbies
	var near_panel := UIKit.panel()
	near_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(near_panel)
	var nv := UIKit.vbox(10)
	near_panel.add_child(nv)
	nv.add_child(UIKit.label("NEARBY GAMES", &"SubheaderLabel"))
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	nv.add_child(scroll)
	_nearby = UIKit.vbox(8)
	_nearby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_nearby)
	_nearby_empty = UIKit.label("Looking for games on your Wi-Fi...", &"DimLabel")
	_nearby_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(_nearby_empty)
	_steam_button = UIKit.button("FIND STEAM GAMES")
	_steam_button.pressed.connect(_on_find_steam)
	nv.add_child(_steam_button)

	# Room code + address
	var right := UIKit.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var v := UIKit.vbox(12)
	right.add_child(v)
	v.add_child(UIKit.label("ROOM CODE", &"SubheaderLabel"))
	var code_row := UIKit.hbox(10)
	v.add_child(code_row)
	_code = LineEdit.new()
	_code.placeholder_text = "Paste the host's code"
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.text_submitted.connect(func(_t: String) -> void: _on_join_code())
	code_row.add_child(_code)
	var paste := UIKit.button("PASTE", &"IconButton")
	paste.pressed.connect(func() -> void: _code.text = DisplayServer.clipboard_get().strip_edges())
	code_row.add_child(paste)
	var join_code := UIKit.button("JOIN", &"PrimaryButton")
	join_code.pressed.connect(_on_join_code)
	code_row.add_child(join_code)
	_join_buttons.append(join_code)
	_hint(v, "The host finds it in the pause menu. Works over the internet with no port forwarding. Steam lobby numbers and W- (WebRTC) codes go here too.")

	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("ADDRESS", &"SubheaderLabel"))
	var row := UIKit.hbox(10)
	v.add_child(row)
	_ip = LineEdit.new()
	_ip.placeholder_text = "192.168.1.20 or name.example.com"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip.text_submitted.connect(func(_t: String) -> void: _on_join_address())
	row.add_child(_ip)
	row.add_child(UIKit.label(":", &"ValueLabel"))
	_port = LineEdit.new()
	_port.max_length = 5
	_port.custom_minimum_size.x = 90
	_port.text_submitted.connect(func(_t: String) -> void: _on_join_address())
	row.add_child(_port)
	var join_ip := UIKit.button("JOIN", &"PrimaryButton")
	join_ip.pressed.connect(_on_join_address)
	row.add_child(join_ip)
	_join_buttons.append(join_ip)
	_hint(v, "An IP, a hostname, a Tailscale or ZeroTier address (both players in the same virtual network), or a playit.gg tunnel address.")

	v.add_child(HSeparator.new())
	_spectate = CheckButton.new()
	_spectate.text = "JOIN AS SPECTATOR"
	_spectate.tooltip_text = "Watch without taking a player slot: fly around or follow any player. Press PLAY in the pause menu to join the fight."
	_spectate.button_pressed = Net.join_as_spectator
	_spectate.toggled.connect(func(on: bool) -> void: Net.join_as_spectator = on)
	UIKit.wire(_spectate)
	v.add_child(_spectate)
	_hint(v, "Spectators take no player slot (a bot keeps it) and can switch to playing from the pause menu.")

	v.add_child(UIKit.spacer(false))
	var status_box := UIKit.panel(&"InsetPanel")
	status_box.custom_minimum_size.y = 64
	v.add_child(status_box)
	var sh := UIKit.hbox(10)
	status_box.add_child(sh)
	_spinner = UIKit.label("", &"ValueLabel")
	_spinner.add_theme_color_override("font_color", UITheme.ACCENT)
	_spinner.custom_minimum_size.x = 26
	sh.add_child(_spinner)
	_status = UIKit.label("Not connected.", &"DimLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sh.add_child(_status)
	_cancel = UIKit.button("CANCEL", &"DangerButton")
	_cancel.pressed.connect(_on_cancel)
	v.add_child(_cancel)

	Net.status.connect(_on_status)
	Net.lan.hosts_changed.connect(func(hosts: Array[Dictionary]) -> void:
		_lan_hosts = hosts
		_rebuild_nearby())
	visibility_changed.connect(_on_visibility_changed)
	# Leaving the page abandons a pending attempt, so it can't pull the player into a match later.
	back_requested.connect(func() -> void:
		_left = true
		if _connecting:
			_on_cancel())
	_set_connecting(false)
	_rebuild_nearby()


func on_shown() -> void:
	_left = false
	_code.text = str(Profile.get_setting("last_code"))
	_ip.text = str(Profile.get_setting("last_ip"))
	_port.text = str(Profile.get_setting("last_port"))
	_status.text = "Not connected."
	_status.remove_theme_color_override("font_color")
	_set_connecting(false)
	_steam_lobbies.clear()
	_rebuild_nearby()
	_on_visibility_changed()
	_focus_code.call_deferred()


## on_shown's focus on the room code, a frame later; skipped when the page was left in between, so
## it can't pull focus back onto a page that is going away.
func _focus_code() -> void:
	if _left or not is_visible_in_tree():
		return
	_code.grab_focus()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		Net.lan.browse()
	else:
		Net.lan.stop_browsing()


func _exit_tree() -> void:
	Net.lan.stop_browsing()


func _process(delta: float) -> void:
	if not _connecting:
		return
	_dots += delta * 8.0
	const FRAMES := ["|", "/", "-", "\\"]
	_spinner.text = FRAMES[int(_dots) % FRAMES.size()]


func _hint(parent: Control, text: String) -> void:
	var l := UIKit.label(text, &"DimLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)


func _rebuild_nearby() -> void:
	for c in _nearby.get_children():
		c.queue_free()
	for h in _lan_hosts:
		_add_nearby_row("%s   %d/%d" % [h.name, h.players, h.max], "WI-FI  ·  %s" % h.address,
			func() -> void: _start(Net.join(h.address, h.port), "Connecting to %s..." % h.name))
	for l in _steam_lobbies:
		_add_nearby_row("%s   %d/%d" % [l.name if not str(l.name).is_empty() else "Steam game", l.players, l.max], "STEAM",
			func() -> void: _start(await Net.join_steam_lobby(l.lobby_id), "Joining %s on Steam..." % l.name))
	_nearby_empty.visible = _lan_hosts.is_empty() and _steam_lobbies.is_empty()


func _add_nearby_row(title: String, detail: String, on_join: Callable) -> void:
	var b := UIKit.button("", &"CardButton")
	b.custom_minimum_size.y = 56
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void:
		if not _connecting:
			on_join.call())
	var v := UIKit.vbox(0)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var t := UIKit.label(title, &"ValueLabel")
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := UIKit.label(detail, &"SmallLabel")
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	_nearby.add_child(b)


func _on_find_steam() -> void:
	_steam_button.disabled = true
	_steam_button.text = "SEARCHING STEAM..."
	var err := Net.steam.ensure_started()
	if err != "":
		_fail(err)
	else:
		_steam_lobbies = await Net.steam.find_lobbies()
		_rebuild_nearby()
		if _steam_lobbies.is_empty():
			_status.text = "No open Steam games found. Ask your friend for their code."
	_steam_button.disabled = false
	_steam_button.text = "FIND STEAM GAMES"


func _on_join_code() -> void:
	if _connecting:
		return
	var code := _code.text.strip_edges()
	if NetLinkAddresses.code_kind(code) == NetLinkAddresses.CodeKind.INVALID:
		_fail("Paste the room code from the host's pause menu.")
		return
	Profile.set_setting("last_code", code)
	_set_connecting(true)
	_start(await Net.join_code(code), "")


func _on_join_address() -> void:
	if _connecting:
		return
	var ip := _ip.text.strip_edges()
	var port_text := _port.text.strip_edges()
	var port := port_text.to_int()
	if ip.is_empty():
		_fail("Enter the host's address.")
		return
	if not port_text.is_valid_int() or port < 1 or port > 65535:
		_fail("Port must be a number between 1 and 65535.")
		return
	Profile.set_setting("last_ip", ip)
	Profile.set_setting("last_port", port)
	_start(Net.join(ip, port), "Connecting to %s:%d..." % [ip, port])


## `err` is what Net returned for the attempt it started; Net reports progress on `status`.
func _start(err: Error, text: String) -> void:
	if err == ERR_SKIP:
		return
	if err != OK:
		_set_connecting(false)
		_fail(_status.text if not _status.text.ends_with("...") else "Could not start connection: %s" % error_string(err))
		return
	_set_connecting(true)
	if not text.is_empty():
		_status.remove_theme_color_override("font_color")
		_status.text = text


func _on_cancel() -> void:
	Net.leave()
	_set_connecting(false)
	_status.text = "Cancelled."


func _on_status(text: String) -> void:
	if not is_visible_in_tree():
		return
	_status.text = text
	var lower := text.to_lower()
	for w in END_WORDS:
		if w in lower and not lower.ends_with("..."):
			_set_connecting(false)
			_status.add_theme_color_override("font_color", UITheme.BAD)
			Sfx.play(&"ui_error")
			return
	_status.remove_theme_color_override("font_color")


func _fail(text: String) -> void:
	Sfx.play(&"ui_error")
	_status.text = text
	_status.add_theme_color_override("font_color", UITheme.BAD)


func _set_connecting(on: bool) -> void:
	_connecting = on
	for b in _join_buttons:
		b.disabled = on
	_code.editable = not on
	_ip.editable = not on
	_port.editable = not on
	_cancel.visible = on
	_spinner.text = "" if not on else "|"
