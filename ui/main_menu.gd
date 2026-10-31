extends Control
## Main menu root: 3D backdrop (MenuBackdrop), persistent top bar (coins, level), home screen and
## the sub-screens (match setup, join, shop, locker, stats, challenges, achievements, settings)
## with tweened transitions. Home is a short column of MenuTiles (PLAY, LOCKER, SHOP, PROGRESS,
## SETTINGS, QUIT); PLAY and PROGRESS open sub-panels beside it (vs bots / host / join / Firing
## Range / tutorial; stats / challenges / achievements). A new profile (Profile.tutorial_offered
## false) is offered the tutorial once, over the home screen.

const TRANSITION := 0.22
const SLIDE := 36.0

var _screens := {}
var _current: Control
var _screen_layer: Control
var _backdrop: MenuBackdrop
var _curtain: ColorRect
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _transition: Tween

# Top bar / profile card widgets refreshed on Profile.changed.
var _coins_label: Label
var _level_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _name_edit: LineEdit
var _daily_button: Button
var _play_button: MenuTile
var _progress_button: MenuTile
var _challenges_button: MenuTile
## Home: the primary tiles, the sub-panels by id ("play", "progress"), the open one ("" = none),
## the control they sit in, and the tile to focus when home shows again.
var _primary: Array[MenuTile] = []
var _flyouts := {}
var _open_flyout := ""
var _flyout_slot: Control
var _home_focus: Control
## The first-launch tutorial offer (null once answered).
var tutorial_offer: Control


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_music(&"menu")

	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	_add_overlays()

	_screen_layer = Control.new()
	_screen_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_layer)
	_add_top_bar()
	_add_toast()

	var home := _build_home()
	_screens["home"] = home
	_screen_layer.add_child(home)
	_current = home

	Profile.changed.connect(_refresh_profile)
	Net.status.connect(_on_net_status)
	_backdrop.built.connect(func() -> void:
		create_tween().tween_property(_curtain, "color:a", 0.0, 1.2))
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_refresh_daily)
	add_child(tick)
	# A new day or week starts new challenge sets; the old sets' unclaimed rewards are paid.
	var carried := Profile.refresh_challenges()
	if int(carried.coins) > 0:
		toast.call_deferred("UNCLAIMED CHALLENGES PAID: +%d COINS" % int(carried.coins), UITheme.ACCENT)
	_refresh_profile()
	if not Profile.tutorial_offered:
		_add_tutorial_offer()
	else:
		_play_button.grab_focus.call_deferred()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)
	# A dropped session returns here; tell the player why.
	if not Net.last_error.is_empty():
		toast.call_deferred(Net.last_error, UITheme.BAD)
		Net.last_error = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and tutorial_offer != null:
		get_viewport().set_input_as_handled()
		decline_tutorial()
	elif event.is_action_pressed(&"ui_cancel") and _current != _screens["home"]:
		get_viewport().set_input_as_handled()
		(_current as MenuScreen).back_requested.emit()
	elif event.is_action_pressed(&"ui_cancel") and not _open_flyout.is_empty():
		get_viewport().set_input_as_handled()
		_close_flyout(true)


## The PLAY panel's TUTORIAL tile and the first-launch offer: the tutorial in the Firing Range.
func start_tutorial() -> void:
	Profile.mark_tutorial_offered()
	Net.play_range(true)


## The first-launch offer's NOT NOW (or Esc / B): never asked again; PLAY > TUTORIAL stays.
func decline_tutorial() -> void:
	Profile.mark_tutorial_offered()
	if tutorial_offer != null:
		tutorial_offer.queue_free()
		tutorial_offer = null
	_play_button.grab_focus.call_deferred()


func _add_tutorial_offer() -> void:
	tutorial_offer = Control.new()
	tutorial_offer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_offer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(tutorial_offer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_offer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_offer.add_child(center)
	var panel := _round_panel(UIKit.panel(), UITheme.PANEL_SOLID, Color(1, 1, 1, 0.1), 22)
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var v := UIKit.vbox(14)
	panel.add_child(v)
	v.add_child(UIKit.label("NEW TO TIMBUM?", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var text := UIKit.label("A short tutorial in the Firing Range walks you through moving, sliding, peeking, shooting, grenades and the grapple hook with your own keys or controller. Finish it once for %d coins." \
		% Data.TUTORIAL_REWARD, &"", HORIZONTAL_ALIGNMENT_CENTER)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 480
	v.add_child(text)
	var start := UIKit.button("START TUTORIAL", &"PrimaryButton")
	start.custom_minimum_size.y = 54
	MenuTile.round_styles(start, UITheme.BUTTON_GREEN, 17)
	start.pressed.connect(start_tutorial)
	v.add_child(start)
	var later := UIKit.button("NOT NOW")
	later.pressed.connect(decline_tutorial)
	later.custom_minimum_size.y = 46
	MenuTile.round_styles(later, UITheme.BUTTON_SLATE, 15)
	v.add_child(later)
	v.add_child(UIKit.label("You can take it any time from PLAY > TUTORIAL on the main menu.", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER))
	start.grab_focus.call_deferred()


## Switches to a screen by name, creating it on first use.
func go(screen_name: String) -> void:
	var next := _get_screen(screen_name)
	if next == _current:
		return
	# Toasts belong to the screen that raised them; don't let one cover the next page.
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	var prev := _current
	_current = next
	var forward := screen_name != "home"
	if _transition != null:
		_transition.kill()
	for s: Control in _screens.values():
		if s != prev and s != next:
			s.visible = false
	next.visible = true
	next.modulate.a = 0.0
	next.position.x = SLIDE if forward else -SLIDE
	if next is MenuScreen:
		(next as MenuScreen).on_shown()
	_transition = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_property(next, "modulate:a", 1.0, TRANSITION)
	_transition.tween_property(next, "position:x", 0.0, TRANSITION)
	if prev != null:
		_transition.tween_property(prev, "modulate:a", 0.0, TRANSITION * 0.7)
		_transition.tween_property(prev, "position:x", -SLIDE if forward else SLIDE, TRANSITION * 0.7)
		_transition.chain().tween_callback(func() -> void:
			prev.visible = false
			prev.position.x = 0.0)
	if screen_name == "home":
		_refresh_profile()
		_focus_home.call_deferred()
	else:
		_focus_screen.call_deferred(next)


## Gives keyboard/controller users a starting point on a freshly shown screen, unless the
## screen already focused something itself in `on_shown()`.
func _focus_screen(screen: Control) -> void:
	if screen != _current:
		return
	var owner_now := get_viewport().gui_get_focus_owner()
	if owner_now != null and screen.is_ancestor_of(owner_now):
		return
	var first := _first_focusable(screen)
	if first != null:
		first.grab_focus()


func _first_focusable(node: Node) -> Control:
	for c in node.get_children():
		var ctl := c as Control
		if ctl == null or not ctl.visible:
			continue
		if ctl.focus_mode == Control.FOCUS_ALL:
			return ctl
		var found := _first_focusable(ctl)
		if found != null:
			return found
	return null


func _get_screen(screen_name: String) -> Control:
	if _screens.has(screen_name):
		return _screens[screen_name]
	var s: MenuScreen
	match screen_name:
		"play":
			s = MatchSetupScreen.new(false)
		"host":
			s = MatchSetupScreen.new(true)
		"join":
			s = JoinScreen.new()
		"shop":
			s = ShopScreen.new()
		"locker":
			var locker := LockerScreen.new()
			locker.shop_requested.connect(func() -> void: go("shop"))
			s = locker
		"stats":
			s = StatsScreen.new()
		"challenges":
			s = ChallengesScreen.new()
		"achievements":
			s = AchievementsScreen.new()
		"settings":
			s = _build_settings_screen()
	s.visible = false
	s.back_requested.connect(func() -> void: go("home"))
	_screens[screen_name] = s
	_screen_layer.add_child(s)
	return s


# ------------------------------------------------------------------ layers

func _add_overlays() -> void:
	# Dark curtain hides the backdrop until the map is built, then fades away.
	_curtain = ColorRect.new()
	_curtain.color = Color("10162a")
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_curtain)
	# Left-side shade keeps text readable over a bright scene.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.06, 0.82))
	g.set_color(1, Color(0.02, 0.03, 0.06, 0.0))
	g.add_point(0.45, Color(0.02, 0.03, 0.06, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.anchor_right = 0.75
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# Radial vignette.
	var vig := TextureRect.new()
	var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0.0))
	vg.set_color(1, Color(0, 0, 0, 0.6))
	vg.set_offset(0, 0.55)
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.05, 1.05)
	vt.width = 256
	vt.height = 256
	vig.texture = vt
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)


func _add_top_bar() -> void:
	var bar := UIKit.hbox(10)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.offset_right = -40
	bar.offset_top = 30
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var level_pill := _round_panel(UIKit.panel(), UITheme.PANEL, Color(1, 1, 1, 0.08), 18, 10)
	_level_label = UIKit.label("LVL 1", &"ValueLabel")
	_level_label.add_theme_color_override("font_color", UITheme.ACCENT_2)
	_level_label.add_theme_font_size_override("font_size", 18)
	level_pill.add_child(_level_label)
	bar.add_child(level_pill)
	var coin_pill := _round_panel(UIKit.panel(), UITheme.PANEL, Color(1, 1, 1, 0.08), 18, 10)
	var coins := UIKit.coin_amount(Profile.coins, 22)
	_coins_label = coins.get_node("Amount")
	_coins_label.add_theme_font_size_override("font_size", 18)
	coin_pill.add_child(coins)
	bar.add_child(coin_pill)


func _add_toast() -> void:
	_toast = UIKit.panel()
	var style := UITheme.round_box(UITheme.PANEL_SOLID, UITheme.ACCENT, 2, 18, 12, 6)
	_toast.add_theme_stylebox_override("panel", style)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -34
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = UIKit.label("", &"ValueLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.add_theme_font_size_override("font_size", 18)
	_toast.add_child(_toast_label)
	_toast.modulate.a = 0.0
	add_child(_toast)


## Brief message at the bottom of the screen.
func toast(text: String, color := UITheme.TEXT) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	_toast.reset_size()
	_toast.offset_left = -_toast.size.x * 0.5
	_toast.offset_right = _toast.size.x * 0.5
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_net_status(text: String) -> void:
	# The message is shown now, so it must not reappear when the menu reloads.
	Net.last_error = ""
	# Setup/join screens show status inline; elsewhere surface it as a toast.
	if _current is MatchSetupScreen or _current is JoinScreen:
		return
	toast(text)


# ------------------------------------------------------------------ home

func _build_home() -> MenuScreen:
	var home := MenuScreen.new()
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 64)
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_top", 30)
	m.add_theme_constant_override("margin_bottom", 30)
	home.add_child(m)
	var row := UIKit.hbox(24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)

	var left := UIKit.vbox(10)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	var title := BlockTitle.new()
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(title)
	var tagline := UIKit.label("BLOCKY FREE-FOR-ALL SHOOTER", &"SubheaderLabel")
	left.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	left.add_child(gap)

	var menu_row := UIKit.hbox(22)
	menu_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(menu_row)
	var column := UIKit.vbox(10)
	column.custom_minimum_size.x = 300
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_row.add_child(column)
	_flyout_slot = Control.new()
	_flyout_slot.custom_minimum_size.x = 300
	_flyout_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_row.add_child(_flyout_slot)

	_play_button = _add_tile(column, "play", "PLAY", &"PrimaryButton", func() -> void: _toggle_flyout("play"))
	_add_tile(column, "locker", "LOCKER", &"", func() -> void: go("locker"))
	_add_tile(column, "shop", "SHOP", &"GoldButton", func() -> void: go("shop"))
	_progress_button = _add_tile(column, "progress", "PROGRESS", &"", func() -> void: _toggle_flyout("progress"))
	_add_tile(column, "settings", "SETTINGS", &"", func() -> void: go("settings"))
	_add_tile(column, "quit", "QUIT", &"DangerButton", func() -> void: get_tree().quit())

	_add_flyout("play", "PLAY", [
		["bots", "PLAY VS BOTS", &"PrimaryButton", func() -> void: go("play")],
		["host", "HOST GAME", &"", func() -> void: go("host")],
		["join", "JOIN GAME", &"", func() -> void: go("join")],
		["range", "FIRING RANGE", &"", func() -> void: Net.play_range()],
		["tutorial", "TUTORIAL", &"", start_tutorial],
	])
	var progress := _add_flyout("progress", "PROGRESS", [
		["stats", "STATS", &"", func() -> void: go("stats")],
		["challenges", "CHALLENGES", &"", func() -> void: go("challenges")],
		["achievements", "ACHIEVEMENTS", &"", func() -> void: go("achievements")],
	])
	_challenges_button = progress[1]

	row.add_child(UIKit.spacer())
	var right := UIKit.vbox(0)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	right.add_child(_build_profile_card())

	var version := UIKit.label("v%s" % ProjectSettings.get_setting("application/config/version", "1.0"), &"SmallLabel")
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 18
	version.offset_top = -26
	home.add_child(version)
	return home


## A primary home tile (big, with icon): `action` runs on press. The PLAY and PROGRESS tiles'
## ids are also their sub-panel ids.
func _add_tile(parent: Container, icon_id: String, text: String, variation: StringName, action: Callable) -> MenuTile:
	var dark := variation == &"GoldButton"
	var t := MenuTile.new(text, icon_id, variation, 60.0, 24, UITheme.ACCENT,
		Color("2a1c00") if dark else UITheme.TEXT)
	t.pressed.connect(func() -> void:
		if not _flyouts.has(icon_id):
			# Clicked with the mouse while a sub-panel is open: close it first.
			_close_flyout(false)
			_home_focus = t
		action.call())
	_primary.append(t)
	parent.add_child(t)
	return t


## A sub-panel beside the primary column, opened by tile `id`: a header, one tile per entry
## (`[icon, text, variation, action]`) and BACK. Returns its tiles in entry order.
func _add_flyout(id: String, header: String, entries: Array) -> Array[MenuTile]:
	var panel := UIKit.panel()
	_round_panel(panel, Color(0.04, 0.05, 0.08, 0.8), Color(UITheme.ACCENT, 0.35), 20, 14)
	panel.custom_minimum_size.x = 300
	panel.visible = false
	_flyout_slot.add_child(panel)
	var v := UIKit.vbox(8)
	panel.add_child(v)
	v.add_child(UIKit.label(header, &"SubheaderLabel"))
	var tiles: Array[MenuTile] = []
	for e: Array in entries:
		var t := MenuTile.new(e[1], e[0], e[2], 50.0, 19)
		var action: Callable = e[3]
		t.pressed.connect(func() -> void:
			_home_focus = t
			action.call())
		v.add_child(t)
		tiles.append(t)
	var back := MenuTile.new("BACK", "back", &"", 42.0, 16, UITheme.TEXT_DIM, UITheme.TEXT_DIM)
	back.pressed.connect(func() -> void: _close_flyout(true))
	v.add_child(back)
	tiles.append(back)
	# Left on the D-pad / arrow keys also steps back out to the primary column.
	for t in tiles:
		t.gui_input.connect(func(event: InputEvent) -> void:
			if event.is_action_pressed(&"ui_left"):
				t.accept_event()
				_close_flyout(true))
	_flyouts[id] = panel
	return tiles


func _toggle_flyout(id: String) -> void:
	if _open_flyout == id:
		_close_flyout(true)
		return
	if not _open_flyout.is_empty():
		_close_flyout(false)
	_open_flyout = id
	var parent: MenuTile = _flyout_parent(id)
	parent.selected = true
	# While a sub-panel is open the primary tiles stay clickable but leave the focus chain, so the
	# D-pad moves within the sub-panel; Esc / B / left / BACK return.
	for t in _primary:
		t.focus_mode = Control.FOCUS_NONE
		if t != parent:
			t.modulate = Color(1, 1, 1, 0.55)
	var panel: Control = _flyouts[id]
	panel.visible = true
	panel.reset_size()
	# Beside its tile, but never past the bottom of the window.
	var lowest := get_viewport_rect().size.y - 24.0 - _flyout_slot.global_position.y - panel.size.y
	panel.position = Vector2(-16.0, minf(maxf(parent.position.y - 44.0, 0.0), lowest))
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, TRANSITION)
	tw.tween_property(panel, "position:x", 0.0, TRANSITION)
	var first := _first_focusable(panel)
	_home_focus = first
	first.grab_focus.call_deferred()


## Closes the open sub-panel; `refocus` moves the focus back to the tile that opened it.
func _close_flyout(refocus: bool) -> void:
	if _open_flyout.is_empty():
		return
	var parent: MenuTile = _flyout_parent(_open_flyout)
	(_flyouts[_open_flyout] as Control).visible = false
	_open_flyout = ""
	parent.selected = false
	for t in _primary:
		t.focus_mode = Control.FOCUS_ALL
		t.modulate = Color.WHITE
	_home_focus = parent
	if refocus:
		Sfx.play(&"ui_click")
		parent.grab_focus()


func _flyout_parent(id: String) -> MenuTile:
	return _play_button if id == "play" else _progress_button


## Focus for the home screen: the tile used last (inside an open sub-panel too), else PLAY.
func _focus_home() -> void:
	if _home_focus != null and _home_focus.is_visible_in_tree() and _home_focus.focus_mode == Control.FOCUS_ALL:
		_home_focus.grab_focus()
	else:
		_play_button.grab_focus()


## Gives `p` a smooth rounded panel style (radius `radius`, content padding `pad`).
func _round_panel(p: PanelContainer, bg: Color, border: Color, radius: int, pad := 16) -> PanelContainer:
	p.add_theme_stylebox_override("panel", UITheme.round_box(bg, border, 2, radius, pad, 8))
	return p


func _build_profile_card() -> Control:
	var card := _round_panel(UIKit.panel(), UITheme.PANEL, Color(1, 1, 1, 0.08), 20)
	card.custom_minimum_size.x = 360
	var v := UIKit.vbox(10)
	card.add_child(v)
	v.add_child(UIKit.label("PLAYER", &"SubheaderLabel"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "Your name"
	_name_edit.select_all_on_focus = true
	_name_edit.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	_name_edit.add_theme_stylebox_override("normal", UITheme.round_box(UITheme.INSET, Color(0, 0, 0, 0.35), 2, 12, 10))
	var name_focus := UITheme.round_box(Color(0, 0, 0, 0), Color(UITheme.ACCENT, 0.95), 2, 13, 10)
	name_focus.draw_center = false
	_name_edit.add_theme_stylebox_override("focus", name_focus)
	v.add_child(_name_edit)

	var lvl_row := UIKit.hbox(8)
	v.add_child(lvl_row)
	var lvl_title := UIKit.label("PROGRESS", &"SmallLabel")
	lvl_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvl_row.add_child(lvl_title)
	lvl_row.add_child(UIKit.spacer())
	_xp_label = UIKit.label("", &"SmallLabel")
	lvl_row.add_child(_xp_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = &"XPBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size.y = 18
	_xp_bar.add_theme_stylebox_override("background", UITheme.round_box(UITheme.INSET, Color(0, 0, 0, 0.35), 1, 9, 0))
	_xp_bar.add_theme_stylebox_override("fill", UITheme.round_box(UITheme.ACCENT_2, Color(0, 0, 0, 0), 0, 9, 0))
	v.add_child(_xp_bar)

	v.add_child(HSeparator.new())
	_daily_button = UIKit.button("", &"GoldButton", false)
	_daily_button.custom_minimum_size.y = 50
	MenuTile.round_styles(_daily_button, UITheme.BUTTON_GOLD, 16)
	_daily_button.pressed.connect(_claim_daily)
	v.add_child(_daily_button)
	return card


func _commit_name() -> void:
	if _name_edit.text.strip_edges() != Profile.player_name:
		Profile.set_player_name(_name_edit.text)
	_name_edit.text = Profile.player_name


func _refresh_profile() -> void:
	_coins_label.text = UIKit.format_int(Profile.coins)
	_level_label.text = Data.badged_name("LVL %d" % Profile.level, Profile.prestige)
	if not _name_edit.has_focus():
		_name_edit.text = Profile.player_name
	var need := Profile.xp_for_level(Profile.level)
	_xp_bar.max_value = need
	if Profile.level >= Data.LEVEL_CAP:
		_xp_bar.value = need
		_xp_label.text = "LVL %d  ·  MAX LEVEL%s" % [Profile.level, "  ·  PRESTIGE IN STATS" if Profile.can_prestige() else ""]
	else:
		_xp_bar.value = Profile.xp
		_xp_label.text = "LVL %d  ·  %s / %s XP" % [Profile.level, UIKit.format_int(Profile.xp), UIKit.format_int(need)]
	var to_claim := Profile.claimable_challenges()
	var badge := str(to_claim) if to_claim > 0 else ""
	_challenges_button.set_badge(badge)
	_progress_button.set_badge(badge)
	_refresh_daily()


func _refresh_daily() -> void:
	if Profile.can_claim_daily():
		_daily_button.disabled = false
		_daily_button.text = "CLAIM DAILY REWARD  +%d" % Data.DAILY_REWARD
	else:
		_daily_button.disabled = true
		var s := Profile.seconds_until_daily()
		_daily_button.text = "NEXT REWARD IN %02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func _claim_daily() -> void:
	var amount := Profile.claim_daily()
	if amount <= 0:
		Sfx.play(&"ui_error")
		return
	Sfx.play(&"coins")
	toast("DAILY REWARD: +%d COINS" % amount, UITheme.ACCENT)
	_float_text("+%d" % amount, _daily_button.get_global_rect().get_center())


## Gold number that floats up and fades, for reward feedback.
func _float_text(text: String, at: Vector2) -> void:
	var l := UIKit.label(text, &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_color", UITheme.ACCENT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.reset_size()
	l.position = at - l.size * 0.5
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "position:y", l.position.y - 90.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.5)
	t.chain().tween_callback(l.queue_free)


func _build_settings_screen() -> MenuScreen:
	var s := MenuScreen.new()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(center)
	var panel := SettingsPanel.new()
	panel.custom_minimum_size = Vector2(820, 560)
	panel.closed.connect(func() -> void: s.back_requested.emit())
	center.add_child(panel)
	s.visibility_changed.connect(func() -> void:
		if s.visible:
			panel.refresh())
	return s
