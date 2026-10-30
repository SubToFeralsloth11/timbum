class_name SettingsPanel
extends PanelContainer
## Reusable settings editor (main menu and pause menu). Edits every Profile setting
## except the remembered join address, applies changes live and saves them shortly after.

signal closed

const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]
## Rebindable actions in display order with friendly names; bindings come from Profile.
const CONTROLS: Array = [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Strafe left"],
	["move_right", "Strafe right"], ["look_up", "Look up"], ["look_down", "Look down"],
	["look_left", "Look left"], ["look_right", "Look right"], ["jump", "Jump"], ["sprint", "Sprint"],
	["crouch", "Crouch / slide (while sprinting)"], ["prone", "Go prone / get up"],
	["lean_left", "Peek left"], ["lean_right", "Peek right"],
	["fire", "Fire"], ["aim", "Aim down sights"], ["reload", "Reload"], ["weapon_1", "Primary"],
	["weapon_2", "Secondary"], ["weapon_3", "Knife"], ["quick_swap", "Last weapon"],
	["next_weapon", "Next weapon"], ["prev_weapon", "Previous weapon"], ["grenade", "Frag grenade"],
	["tactical", "Tactical grenade"], ["melee", "Quick melee"], ["grapple", "Grapple hook"],
	["streak_reward", "Call in Block Bomber (killstreak)"], ["ping", "Ping (team modes)"],
	["interact", "Swap weapon (Tactical)"], ["tactical_map", "Floor plan (Tactical)"],
	["scoreboard", "Scoreboard"], ["chat", "Chat"], ["skip_killcam", "Skip kill cam"],
	["spectate_view", "Spectator: free camera / follow"], ["photo_mode", "Photo mode (offline)"],
	["inspect", "Inspect weapon"], ["spray", "Spray"],
]
## The `index` meta of a binding button in the controller column (key columns are 0 and 1).
const PAD_SLOT := -1
const SAVE_DELAY := 0.35


## Accessibility preview: the colour mode's team colours with their shapes, a kill feed line,
## the health and shield bar, the three hitmarkers and King of the Block / ping / radar colours.
## Redrawn every frame while shown, so it follows the option at once.
class PalettePreview extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 236)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var x := 8.0
		for t in 2:
			var c := Palette.color(Teams.COLOR_ROLES[t])
			draw_rect(Rect2(x, 4, 150, 34), Color(c, 0.25))
			draw_rect(Rect2(x, 4, 150, 34), c, false, 2.0)
			draw_string(font, Vector2(x + 12, 28), "%s %s" % [Teams.SHAPES[t], Teams.NAMES[t]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, c.lightened(0.3))
			x += 166.0
		# A kill feed line.
		var y := 66.0
		x = 8.0
		for part: Array in [["%s Rook" % Teams.SHAPES[0], Palette.color("team_a")], ["  [AR-Cube HS]  ", Color(0.75, 0.75, 0.8)], ["%s Ivy" % Teams.SHAPES[1], Palette.color("team_b")]]:
			draw_string(font, Vector2(x, y), part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, part[1])
			x += font.get_string_size(part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		# Health (empty to full) and an Overshield segment.
		y = 86.0
		for i in 10:
			draw_rect(Rect2(8 + i * 27, y, 24, 12), Palette.health(i / 9.0))
		draw_rect(Rect2(8 + 10 * 27, y, 24, 12), Palette.color("shield"))
		draw_string(font, Vector2(320, y + 11), "health low to full, then shield", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.78, 0.85))
		# Hitmarkers: hit, headshot, kill (bigger).
		y = 140.0
		x = 26.0
		for h: Array in [["hit", 18.0, 3.0, "HIT"], ["hit_head", 18.0, 3.0, "HEADSHOT"], ["hit_kill", 24.0, 4.0, "KILL"]]:
			var c := Palette.color(h[0])
			for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(Vector2(x, y) + d.normalized() * 6.0, Vector2(x, y) + d.normalized() * float(h[1]), c, h[2])
			draw_string(font, Vector2(x + 28, y + 6), h[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
			x += 150.0
		# King of the Block zone states, pings and radar contacts.
		y = 200.0
		x = 8.0
		for z: Array in [["zone_free", "ZONE"], ["zone_mine", "YOURS"], ["zone_other", "TAKEN"], ["zone_contested", "CONTESTED"],
				["ping_spot", "PING"], ["ping_enemy", "ENEMY"], ["radar", "RADAR"]]:
			var c := Palette.color(z[0])
			draw_colored_polygon(PackedVector2Array([Vector2(x + 8, y - 8), Vector2(x + 16, y), Vector2(x + 8, y + 8), Vector2(x, y)]), c)
			draw_string(font, Vector2(x + 22, y + 5), z[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c.lightened(0.2))
			x += 30.0 + font.get_string_size(z[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0


## Crosshair tab preview: the player's crosshair (a real `Crosshair`, re-reading Profile every
## frame while shown) at twice its size over a light and a dark half (split diagonally, so each
## arm sits on one), measured against the game screen's height so gaps match a match. With
## dynamic spread on, it fires bursts: the spread blooms and recovers.
class CrosshairPreview extends Control:
	const ZOOM := 2.0
	var _xh: Crosshair
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(220, 220)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_xh = Crosshair.new()
		_xh.fov = 85.0
		_xh.scale = Vector2(ZOOM, ZOOM)
		add_child(_xh)
		resized.connect(func() -> void:
			_xh.size = size / ZOOM
			_xh.position = Vector2.ZERO)

	func _ready() -> void:
		_xh.view_half_height = ProjectSettings.get_setting("display/window/size/viewport_height", 720) * 0.5

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_t = fmod(_t + delta, 2.0)
		# 0.7 s of fire (spread climbs), then it settles back to the hip spread.
		var bloom := _t / 0.7 if _t < 0.7 else maxf(0.0, 1.0 - (_t - 0.7) / 0.5)
		_xh.spread = 1.0 + 2.0 * bloom
		_xh.load_style()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.2, 0.15))
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size]), Color(0.62, 0.72, 0.8))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), false, 2.0)
		draw_string(get_theme_default_font(), Vector2(8, size.y - 8), "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.92))


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
		custom_minimum_size = Vector2(800, 500)
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
	# The tabs get their own row under the title so all of them fit the panel.
	var tab_row := UIKit.hbox(6)
	root.add_child(tab_row)
	var group := ButtonGroup.new()
	for tab_name in ["GAMEPLAY", "CROSSHAIR", "VIDEO", "AUDIO", "CONTROLS", "ACCESSIBILITY"]:
		var t := UIKit.button(tab_name, &"TabButton")
		# Six tabs fit the pause menu's panel at this size.
		t.add_theme_font_size_override("font_size", 15)
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
	_check_row(gameplay, "show_fps", "Show FPS counter")
	_check_row(gameplay, "damage_numbers", "Show damage numbers")
	_check_row(gameplay, "killfeed", "Show kill feed")
	_check_row(gameplay, "killcam", "Kill cam (replay your killer's view)")

	var crosshair := _preview_page(pages, CrosshairPreview.new())
	_option_row(crosshair, "crosshair_style", "Style", Crosshair.STYLE_NAMES)
	_slider_row(crosshair, "crosshair_size", "Size", 2.0, 30.0, 1.0, "%d px")
	_slider_row(crosshair, "crosshair_gap", "Gap", 0.0, 20.0, 1.0, "%d px")
	_slider_row(crosshair, "crosshair_thickness", "Thickness", 1.0, 6.0, 1.0, "%d px")
	_check_row(crosshair, "crosshair_outline", "Outline")
	_check_row(crosshair, "crosshair_dot", "Centre dot")
	_check_row(crosshair, "crosshair_dynamic", "Dynamic spread")
	_color_row(crosshair, "crosshair_color", "Colour")
	_slider_row(crosshair, "crosshair_opacity", "Opacity", 0.1, 1.0, 0.05, "pct")
	# Narrower controls than other tabs, so the rows fit beside the preview.
	for row in crosshair.get_children():
		for c in row.get_children().slice(1):
			if not (c is Label):
				(c as Control).custom_minimum_size.x = minf((c as Control).custom_minimum_size.x, 230.0)
	var xh_tip := UIKit.label("Dynamic spread opens the gap as your shots spread (moving, jumping, firing); off, the gap stays where you set it. Aiming down sights hides the crosshair either way. Dot uses only size, outline, colour and opacity; Circle's ring sits half its size past the gap.", &"DimLabel")
	xh_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crosshair.add_child(xh_tip)

	var video := _page(pages)
	_check_row(video, "fullscreen", "Fullscreen")
	_check_row(video, "vsync", "V-Sync")
	_option_row(video, "quality", "Graphics quality", QUALITY_NAMES)
	video.add_child(UIKit.label("Quality sets view distance and shadow detail (next map) and switches the effects below to its preset. Effects apply at once.", &"DimLabel"))
	(video.get_child(-1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_option_row(video, "anti_aliasing", "Anti-aliasing", Profile.ANTI_ALIASING_NAMES)
	_slider_row(video, "render_scale", "Render scale", 0.5, 1.0, 0.05, "pct")
	_check_row(video, "shadows", "Shadows")
	_check_row(video, "ambient_occlusion", "Ambient occlusion")
	_check_row(video, "bloom", "Bloom")
	_check_row(video, "reflections", "Reflections")
	_check_row(video, "block_detail", "Block shader effects")
	_check_row(video, "post_fx", "Colour grading and sharpening")

	var audio := _page(pages)
	_slider_row(audio, "master_volume", "Master volume", 0.0, 1.0, 0.01, "pct")
	_slider_row(audio, "music_volume", "Music volume", 0.0, 1.0, 0.01, "pct")
	_slider_row(audio, "sfx_volume", "Effects volume", 0.0, 1.0, 0.01, "pct")

	var controls := _page(pages)
	_build_controls(controls)

	var access := _page(pages)
	_option_row(access, "color_mode", "Colour mode", Palette.MODE_NAMES)
	var access_tip := UIKit.label("Remaps the colours that tell sides and states apart: teams, enemy and teammate nametags, the kill feed, hitmarkers and damage numbers, the health and shield bar, compass pips, King of the Block's zone, pings, radar contacts and airstrike warnings. Teams also carry a shape beside every name (▲ ALPHA, ◼ BRAVO), so colour is never the only cue.", &"DimLabel")
	access_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	access.add_child(access_tip)
	access.add_child(UIKit.label("PREVIEW", &"SubheaderLabel"))
	access.add_child(PalettePreview.new())

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


## Puts the keyboard/controller focus on the open page's tab (when the panel is shown).
func focus_first() -> void:
	for t in _tabs:
		if t.button_pressed:
			t.grab_focus()


func close() -> void:
	_capture = {}
	_flush()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and _capture.is_empty() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## While a binding button is listening, the next press becomes the binding before anything else
## (menus, the pause toggle) sees it: a key or mouse button in the two key columns, a pad button,
## stick direction or trigger in the controller column. Esc or Start cancels; Backspace or Delete
## clears.
func _input(event: InputEvent) -> void:
	if _capture.is_empty() or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	var button := event as InputEventJoypadButton
	var motion := event as InputEventJoypadMotion
	if motion != null:
		# A stick on its way to a direction must not move the menu focus meanwhile.
		get_viewport().set_input_as_handled()
	var code := Profile.code_from_event(event)
	var pressed := (key != null and key.pressed and not key.echo) or (mouse != null and mouse.pressed) \
		or (button != null and button.pressed) or (motion != null and not code.is_empty())
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	var action: String = _capture.action
	var index: int = _capture.index
	var focus: Button = _capture.button
	_capture = {}
	if (key != null and key.physical_keycode == KEY_ESCAPE) or code == Profile.PAD_PAUSE:
		Sfx.play(&"ui_error", null, -6.0)
	elif key != null and key.physical_keycode in [KEY_BACKSPACE, KEY_DELETE]:
		if index == PAD_SLOT:
			Profile.set_pad_binding(action, "")
		else:
			Profile.set_binding(action, index, "")
		Sfx.play(&"ui_click")
	elif Profile.is_bindable(code) and Profile.is_pad_code(code) == (index == PAD_SLOT):
		if index == PAD_SLOT:
			Profile.set_pad_binding(action, code)
		else:
			Profile.set_binding(action, index, code)
		Sfx.play(&"ui_click")
	else:
		Sfx.play(&"ui_error", null, -6.0)
	_refresh_bindings()
	focus.grab_focus()


func _exit_tree() -> void:
	_flush()


func _show_page(idx: int) -> void:
	_capture = {}
	_refresh_bindings()
	for i in _pages.size():
		_pages[i].visible = i == idx


func _page(parent: Control) -> VBoxContainer:
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var v := UIKit.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	_pages.append(scroll)
	return v


## A page whose rows scroll beside a fixed `preview` (kept in view while any row is edited).
func _preview_page(parent: Control, preview: Control) -> VBoxContainer:
	var split := UIKit.hbox(14)
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(split)
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	var v := UIKit.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	split.add_child(preview)
	_pages.append(split)
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
	o.item_selected.connect(func(i: int) -> void:
		_stage(key, i)
		if key == "quality":
			_apply_quality_preset(i))
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


## Picking a quality preset switches the effect toggles (and anti-aliasing) to match it.
func _apply_quality_preset(quality: int) -> void:
	var preset: Dictionary = Profile.QUALITY_PRESETS[quality]
	for key: String in preset:
		Profile.settings[key] = preset[key]
		_pending[key] = preset[key]
	Profile.apply_settings()
	_save_timer.start()
	refresh()


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
	parent.add_child(UIKit.label("CONTROLLER", &"SubheaderLabel"))
	_slider_row(parent, "pad_sens", "Stick look sensitivity", 0.2, 3.0, 0.05, "%.2f")
	_check_row(parent, "pad_invert_y", "Invert stick look Y")
	_slider_row(parent, "pad_deadzone", "Stick deadzone", 0.0, 0.4, 0.01, "pct")
	var curves: Array[String] = []
	for c: Array in Profile.PAD_CURVES:
		curves.append(str(c[0]))
	_option_row(parent, "pad_curve", "Stick response curve", curves)
	_option_row(parent, "aim_assist", "Aim assist", AimAssist.LEVEL_NAMES)
	var assist_tip := UIKit.label("Aim assist slows the right stick near an enemy and follows a moving target a little. It only works offline against bots: online it is off for everyone, so a controller never has an edge over a mouse.", &"DimLabel")
	assist_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(assist_tip)
	parent.add_child(UIKit.label("BINDINGS", &"SubheaderLabel"))
	var tip := UIKit.label("Pick a binding, then press a key or mouse button (KEY columns) or a controller button, stick direction or trigger (PAD). Backspace clears it, Esc or Start cancels. A key or button moves off any action that had it.", &"DimLabel")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(tip)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	for head: String in ["ACTION", "KEY", "KEY 2", "PAD"]:
		grid.add_child(UIKit.label(head, &"DimLabel", HORIZONTAL_ALIGNMENT_LEFT if head == "ACTION" else HORIZONTAL_ALIGNMENT_CENTER))
	for entry: Array in CONTROLS:
		var name_label := UIKit.label(entry[1])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Long names and bindings shorten with an ellipsis so the three columns always fit.
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size.x = 150
		grid.add_child(name_label)
		for index: int in [0, 1, PAD_SLOT]:
			var b := UIKit.button("", &"", false)
			b.custom_minimum_size = Vector2(150, 34)
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
			b.text = "PRESS A BUTTON..." if index == PAD_SLOT else "PRESS A KEY..."
			continue
		if index == PAD_SLOT:
			b.text = Profile.code_text(Profile.get_pad_binding(action))
			continue
		var codes := Profile.get_binding(action)
		b.text = Profile.code_text(codes[index]) if index < codes.size() else "-"
