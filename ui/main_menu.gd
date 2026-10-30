extends Control
## Main menu root: 3D backdrop, persistent top bar (coins, level), home screen and the
## sub-screens (match setup, join, shop, locker, stats, challenges, achievements, settings) with
## tweened transitions. The home screen also starts the Firing Range and the tutorial; a new
## profile (Profile.tutorial_offered false) is offered the tutorial once, over the home screen.

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
var _play_button: Button
var _challenges_button: Button
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


## Home's TUTORIAL button and the first-launch offer: the tutorial in the Firing Range.
func start_tutorial() -> void:
	Profile.mark_tutorial_offered()
	Net.play_range(true)


## The first-launch offer's NOT NOW (or Esc / B): never asked again; the TUTORIAL button stays.
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
	var panel := UIKit.panel()
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
	start.pressed.connect(start_tutorial)
	v.add_child(start)
	var later := UIKit.button("NOT NOW")
	later.pressed.connect(decline_tutorial)
	v.add_child(later)
	v.add_child(UIKit.label("You can take it any time with TUTORIAL on the main menu.", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER))
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
		_play_button.grab_focus.call_deferred()
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
	var level_pill := UIKit.panel(&"CardPanel")
	_level_label = UIKit.label("LVL 1", &"ValueLabel")
	_level_label.add_theme_color_override("font_color", UITheme.ACCENT_2)
	_level_label.add_theme_font_size_override("font_size", 18)
	level_pill.add_child(_level_label)
	bar.add_child(level_pill)
	var coin_pill := UIKit.panel(&"CardPanel")
	var coins := UIKit.coin_amount(Profile.coins, 22)
	_coins_label = coins.get_node("Amount")
	_coins_label.add_theme_font_size_override("font_size", 18)
	coin_pill.add_child(coins)
	bar.add_child(coin_pill)


func _add_toast() -> void:
	_toast = UIKit.panel()
	var style := UITheme.panel_box(UITheme.PANEL_SOLID, UITheme.ACCENT, 2, 4, 12)
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
	m.add_theme_constant_override("margin_left", 56)
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_top", 30)
	m.add_theme_constant_override("margin_bottom", 30)
	home.add_child(m)
	var row := UIKit.hbox(24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)

	var left := UIKit.vbox(10)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.custom_minimum_size.x = 440
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	var title := BlockTitle.new()
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(title)
	var tagline := UIKit.label("BLOCKY FREE-FOR-ALL SHOOTER", &"SubheaderLabel")
	left.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	left.add_child(gap)

	var buttons := UIKit.vbox(10)
	buttons.custom_minimum_size.x = 380
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(buttons)
	_play_button = UIKit.button("PLAY VS BOTS", &"PrimaryButton")
	_play_button.add_theme_font_size_override("font_size", 26)
	_play_button.custom_minimum_size.y = 62
	_play_button.pressed.connect(func() -> void: go("play"))
	buttons.add_child(_play_button)
	var net_row := UIKit.hbox(10)
	buttons.add_child(net_row)
	_add_grid_button(net_row, "HOST GAME", "host")
	_add_grid_button(net_row, "JOIN GAME", "join")
	var row2 := UIKit.hbox(10)
	buttons.add_child(row2)
	_add_grid_button(row2, "SHOP", "shop", &"GoldButton")
	_add_grid_button(row2, "LOCKER", "locker")
	var row3 := UIKit.hbox(10)
	buttons.add_child(row3)
	_add_grid_button(row3, "STATS", "stats")
	_add_grid_button(row3, "SETTINGS", "settings")
	var row4 := UIKit.hbox(10)
	buttons.add_child(row4)
	_challenges_button = _add_grid_button(row4, "CHALLENGES", "challenges")
	_add_grid_button(row4, "ACHIEVEMENTS", "achievements")
	var row5 := UIKit.hbox(10)
	buttons.add_child(row5)
	var range_button := UIKit.button("FIRING RANGE")
	range_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_button.custom_minimum_size.y = 50
	range_button.pressed.connect(func() -> void: Net.play_range())
	row5.add_child(range_button)
	var tutorial_button := UIKit.button("TUTORIAL")
	tutorial_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_button.custom_minimum_size.y = 50
	tutorial_button.pressed.connect(start_tutorial)
	row5.add_child(tutorial_button)
	var quit := UIKit.button("QUIT", &"DangerButton")
	quit.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit)

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


func _add_grid_button(parent: Container, text: String, screen: String, variation: StringName = &"") -> Button:
	var b := UIKit.button(text, variation)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = 1.0
	b.custom_minimum_size.y = 50
	b.pressed.connect(func() -> void: go(screen))
	parent.add_child(b)
	return b


func _build_profile_card() -> Control:
	var card := UIKit.panel()
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
	v.add_child(_xp_bar)

	v.add_child(HSeparator.new())
	_daily_button = UIKit.button("", &"GoldButton", false)
	_daily_button.custom_minimum_size.y = 50
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
	_challenges_button.text = "CHALLENGES (%d)" % to_claim if to_claim > 0 else "CHALLENGES"
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
