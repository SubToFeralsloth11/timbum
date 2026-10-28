class_name SettingsPanel
extends PanelContainer
## Reusable settings editor (main menu and pause menu). Edits every Profile setting
## except the remembered join address, applies changes live and saves them shortly after.

signal closed

const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]
## Rebindable actions in display order with friendly names; bindings come from Profile.
const CONTROLS: Array = [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Strafe left"],
	["move_right", "Strafe right"], ["jump", "Jump"], ["sprint", "Sprint"],
	["crouch", "Crouch / slide (while sprinting)"], ["lean_left", "Peek left"], ["lean_right", "Peek right"],
	["fire", "Fire"], ["aim", "Aim down sights"], ["reload", "Reload"], ["weapon_1", "Primary"],
	["weapon_2", "Secondary"], ["weapon_3", "Knife"], ["quick_swap", "Last weapon"],
	["next_weapon", "Next weapon"], ["prev_weapon", "Previous weapon"], ["grenade", "Frag grenade"],
	["tactical", "Tactical grenade"], ["melee", "Quick melee"], ["grapple", "Grapple hook"],
	["scoreboard", "Scoreboard"], ["chat", "Chat"],
]
const SAVE_DELAY := 0.35

var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _pending := {}
var _save_timer: Timer
## key -> callable refreshing that row's control from Profile.
var _refreshers := {}
## Binding button waiting for a key: {action, index, button}; empty when not listening.
var _capture := {}
var _bind_buttons: Array[Button] = []


func _ready() -> void:
	theme = UITheme.get_theme()
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(760, 500)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(_flush)
	add_child(_save_timer)

	var root := UIKit.vbox(14)
	add_child(root)
	var head := UIKit.hbox(12)
	root.add_child(head)
	head.add_child(UIKit.label("SETTINGS", &"HeaderLabel"))
	head.add_child(UIKit.spacer())
	var tab_row := UIKit.hbox(6)
	tab_row.alignment = BoxContainer.ALIGNMENT_END
	head.add_child(tab_row)
	var group := ButtonGroup.new()
	for tab_name in ["GAMEPLAY", "VIDEO", "AUDIO", "CONTROLS"]:
		var t := UIKit.button(tab_name, &"TabButton")
		t.toggle_mode = true
		t.button_group = group
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var idx := _tabs.size()
		t.pressed.connect(func() -> void: _show_page(idx))
		tab_row.add_child(t)
		_tabs.append(t)

	var body := UIKit.panel(&"InsetPanel")
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var pages := Control.new()
	pages.clip_contents = true
	body.add_child(pages)

	var gameplay := _page(pages)
	_slider_row(gameplay, "mouse_sens", "Mouse sensitivity", 0.1, 5.0, 0.05, "%.2f")
	_slider_row(gameplay, "ads_sens_mult", "Aim sensitivity", 0.2, 1.5, 0.05, "%.2fx")
	_check_row(gameplay, "invert_y", "Invert mouse Y")
	_slider_row(gameplay, "fov", "Field of view", 60.0, 110.0, 1.0, "%d°")
	_color_row(gameplay, "crosshair_color", "Crosshair colour")
	_check_row(gameplay, "show_fps", "Show FPS counter")
	_check_row(gameplay, "damage_numbers", "Show damage numbers")
	_check_row(gameplay, "killfeed", "Show kill feed")

	var video := _page(pages)
	_check_row(video, "fullscreen", "Fullscreen")
	_check_row(video, "vsync", "V-Sync")
	_option_row(video, "quality", "Graphics quality", QUALITY_NAMES)
	video.add_child(UIKit.label("Quality changes the view distance, shadows and effects. It takes effect from the next map.", &"DimLabel"))
	(video.get_child(-1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var audio := _page(pages)
	_slider_row(audio, "master_volume", "Master volume", 0.0, 1.0, 0.01, "pct")
	_slider_row(audio, "music_volume", "Music volume", 0.0, 1.0, 0.01, "pct")
	_slider_row(audio, "sfx_volume", "Effects volume", 0.0, 1.0, 0.01, "pct")

	var controls := _page(pages)
	_build_controls(controls)

	var foot := UIKit.hbox(12)
	root.add_child(foot)
	var reset := UIKit.button("RESET DEFAULTS", &"DangerButton")
	reset.pressed.connect(_reset_defaults)
	foot.add_child(reset)
	foot.add_child(UIKit.spacer())
	var done := UIKit.button("DONE", &"PrimaryButton")
	done.custom_minimum_size.x = 160
	done.pressed.connect(close)
	foot.add_child(done)

	_tabs[0].button_pressed = true
	_show_page(0)
	refresh()


## Reloads every control from Profile (call when re-shown).
func refresh() -> void:
	for key: String in _refreshers:
		(_refreshers[key] as Callable).call()


func close() -> void:
	_capture = {}
	_flush()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and _capture.is_empty() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## While a binding button is listening, the next key or mouse press becomes the binding before
## anything else (menus, the pause toggle) sees it. Esc cancels; Backspace or Delete clears.
func _input(event: InputEvent) -> void:
	if _capture.is_empty() or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	if not ((key != null and key.pressed and not key.echo) or (mouse != null and mouse.pressed)):
		return
	get_viewport().set_input_as_handled()
	var action: String = _capture.action
	var index: int = _capture.index
	_capture = {}
	if key != null and key.physical_keycode == KEY_ESCAPE:
		Sfx.play(&"ui_error", null, -6.0)
	elif key != null and key.physical_keycode in [KEY_BACKSPACE, KEY_DELETE]:
		Profile.set_binding(action, index, "")
		Sfx.play(&"ui_click")
	else:
		var code := Profile.code_from_event(event)
		if Profile.is_bindable(code):
			Profile.set_binding(action, index, code)
			Sfx.play(&"ui_click")
		else:
			Sfx.play(&"ui_error", null, -6.0)
	_refresh_bindings()


func _exit_tree() -> void:
	_flush()


func _show_page(idx: int) -> void:
	_capture = {}
	_refresh_bindings()
	for i in _pages.size():
		_pages[i].visible = i == idx


func _page(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var v := UIKit.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	_pages.append(scroll)
	return v


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := UIKit.hbox(14)
	var l := UIKit.label(text)
	l.add_theme_font_override("font", UITheme.heavy_font())
	l.add_theme_font_size_override("font_size", 17)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	parent.add_child(h)
	return h


func _slider_row(parent: Control, key: String, text: String, lo: float, hi: float, step: float, fmt: String) -> void:
	var h := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(300, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var v := UIKit.label("", &"ValueLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_theme_font_size_override("font_size", 17)
	v.custom_minimum_size.x = 70
	h.add_child(v)
	var show_value := func(x: float) -> void:
		v.text = "%d%%" % roundi(x * 100.0) if fmt == "pct" else fmt % x
	s.value_changed.connect(func(x: float) -> void:
		show_value.call(x)
		_stage(key, x))
	s.drag_started.connect(func() -> void: Sfx.play(&"ui_hover", null, -8.0))
	_refreshers[key] = func() -> void:
		s.set_value_no_signal(float(Profile.get_setting(key)))
		show_value.call(s.value)


func _check_row(parent: Control, key: String, text: String) -> void:
	var h := _row(parent, text)
	var c := CheckBox.new()
	c.text = "ON"
	c.add_theme_font_override("font", UITheme.heavy_font())
	c.custom_minimum_size.x = 384
	UIKit.wire(c)
	c.toggled.connect(func(on: bool) -> void:
		c.text = "ON" if on else "OFF"
		_stage(key, on))
	h.add_child(c)
	_refreshers[key] = func() -> void:
		c.set_pressed_no_signal(bool(Profile.get_setting(key)))
		c.text = "ON" if c.button_pressed else "OFF"


func _option_row(parent: Control, key: String, text: String, names: Array[String]) -> void:
	var h := _row(parent, text)
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.custom_minimum_size.x = 384
	UIKit.wire(o)
	o.item_selected.connect(func(i: int) -> void: _stage(key, i))
	h.add_child(o)
	_refreshers[key] = func() -> void: o.select(int(Profile.get_setting(key)))


func _color_row(parent: Control, key: String, text: String) -> void:
	var h := _row(parent, text)
	var c := ColorPickerButton.new()
	c.edit_alpha = false
	c.custom_minimum_size = Vector2(384, 38)
	UIKit.wire(c)
	c.color_changed.connect(func(col: Color) -> void: _stage(key, col.to_html(false)))
	var picker := c.get_picker()
	picker.presets_visible = true
	picker.sampler_visible = false
	picker.color_modes_visible = false
	for preset in [Color.WHITE, Color("ffc531"), Color("5bd15b"), Color("39d0ff"), Color("ff5a4f"), Color("ff4fd8")]:
		picker.add_preset(preset)
	h.add_child(c)
	_refreshers[key] = func() -> void: c.color = Color.from_string(str(Profile.get_setting(key)), Color.WHITE)


## Applies a value immediately (live preview) and schedules the save.
func _stage(key: String, value: Variant) -> void:
	Profile.settings[key] = value
	Profile.apply_settings()
	_pending[key] = value
	_save_timer.start()


func _flush() -> void:
	if _pending.is_empty():
		return
	var pending := _pending
	_pending = {}
	for key: String in pending:
		Profile.set_setting(key, pending[key])


func _reset_defaults() -> void:
	for key: String in Profile.DEFAULT_SETTINGS:
		if key in ["last_ip", "last_port"]:
			continue
		_pending[key] = Profile.DEFAULT_SETTINGS[key]
		Profile.settings[key] = Profile.DEFAULT_SETTINGS[key]
	_flush()
	refresh()


func _build_controls(parent: VBoxContainer) -> void:
	var tip := UIKit.label("Click a binding, then press a key or mouse button. Backspace clears it, Esc cancels. A key moves off any action that had it.", &"DimLabel")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(tip)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	for entry: Array in CONTROLS:
		var name_label := UIKit.label(entry[1])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		for index in Profile.MAX_BINDINGS:
			var b := UIKit.button("", &"", false)
			b.custom_minimum_size = Vector2(170, 34)
			b.set_meta(&"action", entry[0])
			b.set_meta(&"index", index)
			b.pressed.connect(_start_capture.bind(b))
			grid.add_child(b)
			_bind_buttons.append(b)
	var reset := UIKit.button("RESET CONTROLS", &"DangerButton")
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		_capture = {}
		Profile.reset_bindings()
		_refresh_bindings())
	parent.add_child(reset)
	_refreshers["_bindings"] = _refresh_bindings


func _start_capture(b: Button) -> void:
	Sfx.play(&"ui_click")
	_capture = {"action": str(b.get_meta(&"action")), "index": int(b.get_meta(&"index")), "button": b}
	_refresh_bindings()


func _refresh_bindings() -> void:
	for b in _bind_buttons:
		var action := str(b.get_meta(&"action"))
		var index := int(b.get_meta(&"index"))
		if not _capture.is_empty() and _capture.button == b:
			b.text = "PRESS A KEY..."
			continue
		var codes := Profile.get_binding(action)
		b.text = Profile.code_text(codes[index]) if index < codes.size() else "-"
