class_name JoinScreen
extends MenuScreen
## Join a hosted game by IP and port. Remembers the last address in Profile settings.

## Status words that mean the attempt is over (Net reports free-form text).
const END_WORDS: Array[String] = ["fail", "lost", "disconnect", "refused", "timed out", "timeout", "error", "could not", "invalid", "full", "kicked", "closed", "mismatch"]

var _ip: LineEdit
var _port: LineEdit
var _join: Button
var _cancel: Button
var _status: Label
var _spinner: Label
var _connecting := false
var _dots := 0.0


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("JOIN GAME", "Connect to a friend's game on your network or over the internet."))
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var panel := UIKit.panel()
	panel.custom_minimum_size.x = 520
	center.add_child(panel)
	var v := UIKit.vbox(12)
	panel.add_child(v)
	v.add_child(UIKit.label("HOST ADDRESS", &"SubheaderLabel"))
	var row := UIKit.hbox(10)
	v.add_child(row)
	_ip = LineEdit.new()
	_ip.placeholder_text = "192.168.1.20"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip.text_submitted.connect(func(_t: String) -> void: _on_join())
	row.add_child(_ip)
	var colon := UIKit.label(":", &"ValueLabel")
	row.add_child(colon)
	_port = LineEdit.new()
	_port.max_length = 5
	_port.custom_minimum_size.x = 100
	_port.text_submitted.connect(func(_t: String) -> void: _on_join())
	row.add_child(_port)
	var hint := UIKit.label("Ask the host for the address shown on their Host Game screen.", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)

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

	var buttons := UIKit.hbox(10)
	v.add_child(buttons)
	_cancel = UIKit.button("CANCEL", &"DangerButton")
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel.pressed.connect(_on_cancel)
	buttons.add_child(_cancel)
	_join = UIKit.button("JOIN", &"PrimaryButton")
	_join.add_theme_font_size_override("font_size", 24)
	_join.custom_minimum_size.y = 56
	_join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join.size_flags_stretch_ratio = 2.0
	_join.pressed.connect(_on_join)
	buttons.add_child(_join)

	Net.status.connect(_on_status)
	# Leaving the page abandons a pending attempt, so it can't pull the player into a match later.
	back_requested.connect(func() -> void:
		if _connecting:
			_on_cancel())
	_set_connecting(false)


func on_shown() -> void:
	_ip.text = str(Profile.get_setting("last_ip"))
	_port.text = str(Profile.get_setting("last_port"))
	_status.text = "Not connected."
	_status.remove_theme_color_override("font_color")
	_set_connecting(false)
	_ip.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if not _connecting:
		return
	_dots += delta * 8.0
	const FRAMES := ["|", "/", "-", "\\"]
	_spinner.text = FRAMES[int(_dots) % FRAMES.size()]


func _on_join() -> void:
	if _connecting:
		return
	var ip := _ip.text.strip_edges()
	var port_text := _port.text.strip_edges()
	var port := port_text.to_int()
	if ip.is_empty():
		_fail("Enter the host's IP address.")
		return
	if not port_text.is_valid_int() or port < 1 or port > 65535:
		_fail("Port must be a number between 1 and 65535.")
		return
	Profile.set_setting("last_ip", ip)
	Profile.set_setting("last_port", port)
	_status.remove_theme_color_override("font_color")
	_status.text = "Connecting to %s:%d..." % [ip, port]
	_set_connecting(true)
	var err := Net.join(ip, port)
	if err != OK:
		_set_connecting(false)
		_fail("Could not start connection: %s" % error_string(err))


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
		if w in lower:
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
	_join.disabled = on
	_ip.editable = not on
	_port.editable = not on
	_cancel.visible = on
	_spinner.text = "" if not on else "|"
