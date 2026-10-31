class_name CreditsPanel
extends Control
## Stats > CREDITS: who made Timbum, as a rounded overlay over the stats page. The DEV row opens a
## keypad (on-screen letter and number keys, or type on the keyboard) whose ENTER goes to
## Profile.redeem_code, the only way to unlock THE DEV PACK. Esc / pad B closes the keypad, then
## the credits. While open, the page behind (`behind`) takes no focus, so pad navigation stays here.

signal closed

## Credited AI models: [name, role, line].
const ENTRIES: Array = [
	["Claude Opus 5.5", "LEAD ENGINEER", "Built the game systems, modes and menus, and wrote the docs."],
	["Claude Haiku 5.5", "QUICK FIXER", "Fast fixes, quick checks and tidy commits."],
	["GLM 3.2 Flash", "CHIEF BUG INTRODUCER", "Made sure the others never ran out of bugs to fix. Thanks, we think."],
]
const DEV_NAME := "LastMinutePlays"
const KEYS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const KEY_COLUMNS := 9
const MAX_LEN := 24

var behind: Control
var _credits: VBoxContainer
var _keypad: VBoxContainer
var _dev_button: Button
var _close_button: Button
var _display_box: PanelContainer
var _display: Label
var _status: Label
var _status_sub: Label
var _keys := {}
var _typed := ""
var _shake: Tween
var _pop: Tween
var _burst: CPUParticles2D


func _init(p_behind: Control) -> void:
	behind = p_behind
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UIKit.panel()
	panel.add_theme_stylebox_override("panel", UITheme.round_box(UITheme.PANEL_SOLID, Color(1, 1, 1, 0.1), 1, UITheme.PANEL_RADIUS, 22, 12))
	panel.custom_minimum_size.x = 640
	center.add_child(panel)
	var stack := UIKit.vbox(0)
	panel.add_child(stack)
	_credits = _build_credits()
	stack.add_child(_credits)
	_keypad = _build_keypad()
	stack.add_child(_keypad)
	_burst = CPUParticles2D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 70
	_burst.lifetime = 1.3
	_burst.explosiveness = 1.0
	_burst.direction = Vector2.UP
	_burst.spread = 180.0
	_burst.initial_velocity_min = 180.0
	_burst.initial_velocity_max = 460.0
	_burst.gravity = Vector2(0, 520)
	_burst.scale_amount_min = 5.0
	_burst.scale_amount_max = 10.0
	var ramp := Gradient.new()
	ramp.set_color(0, DevPack.HOT)
	ramp.set_color(1, Color(DevPack.NEON, 0.0))
	_burst.color_ramp = ramp
	add_child(_burst)


func _build_credits() -> VBoxContainer:
	var v := UIKit.vbox(10)
	v.add_child(UIKit.label("CREDITS", &"HeaderLabel"))
	v.add_child(UIKit.label("Timbum was made by a small, strange team.", &"DimLabel"))
	for e: Array in ENTRIES:
		var card := UIKit.panel(&"CardPanel")
		card.add_child(_credit_row(e[0], e[1], e[2]))
		v.add_child(card)
	# The developer's row is a card button: it opens the keypad.
	_dev_button = UIKit.button("", &"CardButton")
	_dev_button.custom_minimum_size.y = 76
	_dev_button.pressed.connect(show_keypad)
	var row := _credit_row("DEV", "CREATOR", "%s: ideas, playtesting and every last-minute call." % DEV_NAME)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.offset_top = 8
	row.offset_bottom = -8
	_dev_button.add_child(row)
	v.add_child(_dev_button)
	_close_button = UIKit.button("CLOSE", &"PrimaryButton")
	_close_button.pressed.connect(close)
	v.add_child(_close_button)
	return v


## One credit: name and line on the left, the role as a pill on the right.
func _credit_row(who: String, role: String, line: String) -> HBoxContainer:
	var h := UIKit.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := UIKit.vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(text)
	var name_label := UIKit.label(who, &"ValueLabel")
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)
	var line_label := UIKit.label(line, &"DimLabel")
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size.x = 380
	line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(line_label)
	var role_tag := UIKit.badge(role, &"GoldBadgePanel")
	role_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(role_tag)
	return h


func _build_keypad() -> VBoxContainer:
	var v := UIKit.vbox(12)
	v.visible = false
	var head := UIKit.hbox(14)
	v.add_child(head)
	var back := UIKit.button("< BACK", &"IconButton")
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(show_credits.bind(true))
	head.add_child(back)
	var title := UIKit.label("DEV KEYPAD", &"HeaderLabel")
	title.add_theme_color_override("font_color", DevPack.NEON)
	head.add_child(title)
	_display_box = PanelContainer.new()
	_display_box.add_theme_stylebox_override("panel", UITheme.round_box(DevPack.BLACK, Color(DevPack.NEON, 0.7), 2, 12, 14))
	_display_box.custom_minimum_size.y = 64
	v.add_child(_display_box)
	_display = UIKit.label("", &"ValueLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_display.add_theme_font_size_override("font_size", 28)
	_display.add_theme_color_override("font_color", DevPack.NEON)
	_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_display.clip_text = true
	_display_box.add_child(_display)
	var grid := GridContainer.new()
	grid.columns = KEY_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for ch in KEYS:
		var b := UIKit.button(ch, &"IconButton")
		b.name = "Key_" + ch
		b.custom_minimum_size = Vector2(60, 52)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(type_char.bind(ch))
		grid.add_child(b)
		_keys[ch] = b
	var actions := UIKit.hbox(8)
	v.add_child(actions)
	var clear := UIKit.button("CLEAR", &"DangerButton")
	clear.name = "Clear"
	clear.pressed.connect(clear_code)
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(clear)
	var backspace := UIKit.button("BACKSPACE")
	backspace.name = "Backspace"
	backspace.pressed.connect(backspace_char)
	backspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(backspace)
	var enter := UIKit.button("ENTER", &"PrimaryButton", false)
	enter.name = "Enter"
	enter.pressed.connect(submit)
	enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(enter)
	_status = UIKit.label("", &"ValueLabel", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_status)
	_status_sub = UIKit.label("", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_status_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status_sub)
	v.add_child(UIKit.label("Pick keys, or type on your keyboard. Enter submits, Backspace deletes.", &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	return v


## Opens on the credits list. The page behind stops taking focus until close().
func open() -> void:
	visible = true
	if behind != null:
		behind.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	show_credits()


func close() -> void:
	if not visible:
		return
	visible = false
	if behind != null:
		behind.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	closed.emit()


## The list; `from_keypad` puts the focus back on the DEV row, else on CLOSE.
func show_credits(from_keypad := false) -> void:
	_keypad.visible = false
	_credits.visible = true
	(_dev_button if from_keypad else _close_button).grab_focus.call_deferred()


func show_keypad() -> void:
	_credits.visible = false
	_keypad.visible = true
	_typed = ""
	_status.text = ""
	_status_sub.text = ""
	_refresh_display()
	(_keys[KEYS[0]] as Button).grab_focus.call_deferred()


func is_keypad_open() -> bool:
	return visible and _keypad.visible


## The code typed so far and the result line (the keypad's state, for tests).
func typed() -> String:
	return _typed


func status_text() -> String:
	return _status.text


func type_char(ch: String) -> void:
	if _typed.length() >= MAX_LEN:
		Sfx.play(&"ui_error", null, -8.0)
		return
	_typed += ch
	_refresh_display()


func backspace_char() -> void:
	_typed = _typed.substr(0, maxi(0, _typed.length() - 1))
	_refresh_display()


func clear_code() -> void:
	_typed = ""
	_status.text = ""
	_status_sub.text = ""
	_refresh_display()


func submit() -> void:
	var result := Profile.redeem_code(_typed)
	_status.text = result.to_upper()
	_status.remove_theme_font_size_override("font_size")
	_status.scale = Vector2.ONE
	match result:
		Profile.REDEEM_UNLOCKED:
			_celebrate()
		Profile.REDEEM_ALREADY:
			Sfx.play(&"ui_click")
			_status.add_theme_color_override("font_color", UITheme.ACCENT_2)
			_status_sub.text = "The Dev Pack is already in your locker."
			_typed = ""
		_:
			Sfx.play(&"ui_error")
			_status.add_theme_color_override("font_color", UITheme.BAD)
			_status_sub.text = ""
			_shake_display()
	_refresh_display()


func _refresh_display() -> void:
	_display.text = _typed + "_"


func _celebrate() -> void:
	Sfx.play(&"level_up")
	_typed = ""
	_status.add_theme_color_override("font_color", DevPack.NEON)
	_status.add_theme_font_size_override("font_size", 30)
	_status_sub.text = "Dev Suit, Dev Circuit, Dev Halo and Dev Core are yours. Equip them in the locker."
	if _pop != null:
		_pop.kill()
	_status.pivot_offset = _status.size * 0.5
	_pop = _status.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_status.scale = Vector2(0.4, 0.4)
	_pop.tween_property(_status, "scale", Vector2(1.12, 1.12), 0.25)
	_pop.tween_property(_status, "scale", Vector2.ONE, 0.2)
	_burst.global_position = _display_box.global_position + _display_box.size * 0.5
	_burst.restart()


func _shake_display() -> void:
	if _shake != null and _shake.is_running():
		_shake.kill()
		_display_box.position.x = 0.0
	# The box sits in a VBox, so its x is 0; shake around it and settle back.
	_shake = _display_box.create_tween()
	for i in 6:
		_shake.tween_property(_display_box, "position:x", 10.0 if i % 2 == 0 else -10.0, 0.04)
	_shake.tween_property(_display_box, "position:x", 0.0, 0.04)


## Esc / pad B steps back (keypad > credits > closed). On the keypad, keyboard letters and digits
## type, Backspace deletes, Delete clears and Enter submits; Space is swallowed so it can't press
## the focused key. Pad buttons still drive the focused on-screen key.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _keypad.visible:
			show_credits(true)
		else:
			close()
		return
	if not _keypad.visible:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.ctrl_pressed or k.meta_pressed or k.alt_pressed:
		return
	match k.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if not k.echo:
				submit()
		KEY_BACKSPACE:
			backspace_char()
		KEY_DELETE:
			clear_code()
		KEY_SPACE:
			pass
		_:
			var ch := char(k.unicode) if k.unicode > 0 else ""
			if ch.length() != 1 or not (ch.to_upper() in KEYS):
				return
			if not k.echo:
				Sfx.play(&"ui_click", null, -8.0)
				type_char(ch)
	get_viewport().set_input_as_handled()
