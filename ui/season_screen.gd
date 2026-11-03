class_name SeasonScreen
extends MenuScreen
## The season pass (Season, Profile.season_*): a header with the tier, the season XP bar, the
## days left and CLAIM ALL; a horizontally scrolling track of one card per tier (reward thumbnail,
## name, locked / reached / claimed state, the next tier's progress) with a CLAIM button under
## each; and a detail panel with a live 3D preview of the selected cosmetic (as the shop shows it)
## and EQUIP once it is owned. Keyboard and controller: left / right walk the cards (the preview
## follows the focus), down reaches a card's CLAIM, the right stick scrolls, Esc / B goes back.

const CARD_SIZE := Vector2(150, 0)
## Card thumbnails are taller than the shop's (Thumbnailer.size).
const THUMB_SIZE := Vector2i(180, 240)
## Pixels per second the right stick scrolls the track at full push.
const STICK_SCROLL := 1100.0

var _tier_label: Label
var _xp_label: Label
var _next_label: Label
var _bar: ProgressBar
var _time_label: Label
var _claim_all: Button
var _scroll: ScrollContainer
var _track: HBoxContainer
var _thumbs: Thumbnailer
var _preview: ModelPreview
var _coin_view: TextureRect
var _name: Label
var _kind: Label
var _state: Label
var _equip: Button
var _status: Label
## Per tier (1-based index - 1): {card, claim, mark, bar}.
var _cards: Array[Dictionary] = []
var _selected := 0


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header(Season.title(),
		"Free for everyone. Matches and challenge claims earn season XP: every %s fills a tier. Claim each tier's reward below." % UIKit.format_int(Season.XP_PER_TIER)))
	_thumbs = Thumbnailer.new()
	_thumbs.size = THUMB_SIZE
	add_child(_thumbs)
	page.add_child(_build_summary())
	var body := UIKit.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	body.add_child(_build_detail())
	var track_panel := UIKit.panel(&"InsetPanel")
	track_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(track_panel)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	track_panel.add_child(_scroll)
	_track = UIKit.hbox(12)
	_track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_track)
	var group := ButtonGroup.new()
	for t in range(1, Season.TIERS + 1):
		_track.add_child(_make_column(t, group))
	_status = UIKit.label("", &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	page.add_child(_status)
	Profile.changed.connect(_on_profile_changed)


func on_shown() -> void:
	_status.text = ""
	_refresh()
	# Start on the first tier waiting to be claimed, else the tier being worked on.
	var claimable := Profile.claimable_season_tiers()
	var start := claimable[0] if not claimable.is_empty() else mini(Profile.season_tier() + 1, Season.TIERS)
	# Rebuild the preview even for the same tier: the player's gear may have changed in between.
	_selected = 0
	_select(start)
	_focus_card.call_deferred(start)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var push := Profile.pad_stick(&"look_left", &"look_right", &"look_up", &"look_down").x
	if push != 0.0:
		_scroll.scroll_horizontal += roundi(push * STICK_SCROLL * delta)


# ------------------------------------------------------------------ layout

func _build_summary() -> Control:
	var panel := UIKit.panel()
	var h := UIKit.hbox(24)
	panel.add_child(h)
	var tier_box := UIKit.vbox(0)
	tier_box.custom_minimum_size.x = 150
	tier_box.add_child(UIKit.label("SEASON TIER", &"SmallLabel"))
	_tier_label = UIKit.label("", &"HeaderLabel")
	_tier_label.add_theme_font_size_override("font_size", 38)
	_tier_label.add_theme_color_override("font_color", Season.COLOR)
	tier_box.add_child(_tier_label)
	h.add_child(tier_box)
	var xp_box := UIKit.vbox(6)
	xp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_box.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(xp_box)
	var xp_row := UIKit.hbox(8)
	xp_box.add_child(xp_row)
	xp_row.add_child(UIKit.label("SEASON XP", &"SmallLabel"))
	xp_row.add_child(UIKit.spacer())
	_xp_label = UIKit.label("", &"SmallLabel")
	xp_row.add_child(_xp_label)
	_bar = UITheme.slim_bar(Season.COLOR, Vector2(0, 18))
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_box.add_child(_bar)
	_next_label = UIKit.label("", &"DimLabel")
	xp_box.add_child(_next_label)
	var time_box := UIKit.vbox(2)
	time_box.alignment = BoxContainer.ALIGNMENT_CENTER
	time_box.custom_minimum_size.x = 200
	_time_label = UIKit.label("", &"ValueLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_time_label.add_theme_font_size_override("font_size", 18)
	time_box.add_child(_time_label)
	var ends := UIKit.label("%s  ·  NO FOMO: STAYS CLAIMABLE" % Season.end_text(), &"SmallLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	time_box.add_child(ends)
	h.add_child(time_box)
	_claim_all = UIKit.button("CLAIM ALL", &"GoldButton", false)
	_claim_all.custom_minimum_size = Vector2(170, 52)
	_claim_all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_claim_all.pressed.connect(claim_all)
	h.add_child(_claim_all)
	return panel


func _build_detail() -> Control:
	var panel := UIKit.panel()
	panel.custom_minimum_size.x = 330
	var v := UIKit.vbox(6)
	panel.add_child(v)
	var stage := UIKit.panel(&"InsetPanel")
	stage.add_theme_stylebox_override("panel", UITheme.spotlight_box())
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 170
	v.add_child(stage)
	_preview = ModelPreview.new()
	stage.add_child(_preview)
	_coin_view = TextureRect.new()
	_coin_view.texture = UIKit.coin_icon()
	_coin_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_coin_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_coin_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_coin_view.custom_minimum_size = Vector2(128, 128)
	_coin_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_center := CenterContainer.new()
	coin_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_center.add_child(_coin_view)
	stage.add_child(coin_center)
	_name = UIKit.label("", &"HeaderLabel")
	_name.add_theme_font_size_override("font_size", 24)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	v.add_child(_name)
	_kind = UIKit.label("", &"SmallLabel")
	_kind.add_theme_color_override("font_color", Season.COLOR)
	v.add_child(_kind)
	var actions := UIKit.hbox(10)
	v.add_child(actions)
	_state = UIKit.label("", &"ValueLabel")
	_state.add_theme_font_size_override("font_size", 16)
	_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(_state)
	_equip = UIKit.button("EQUIP", &"PrimaryButton")
	_equip.custom_minimum_size = Vector2(120, 46)
	_equip.pressed.connect(_on_equip)
	actions.add_child(_equip)
	return panel


## One tier: its card (selects it) over its CLAIM button.
func _make_column(tier: int, group: ButtonGroup) -> Control:
	var col := UIKit.vbox(8)
	col.custom_minimum_size = CARD_SIZE
	var cat := Season.reward_category(tier)
	var card := UIKit.button("", &"SeasonCardButton" if cat != "coins" else &"CardButton")
	card.toggle_mode = true
	card.button_group = group
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.pressed.connect(func() -> void: _select(tier))
	card.focus_entered.connect(func() -> void: _select(tier))
	col.add_child(card)
	var v := UIKit.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var top := UIKit.hbox(4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var num := UIKit.label("TIER %d" % tier, &"ValueLabel")
	num.add_theme_font_size_override("font_size", 15)
	top.add_child(num)
	top.add_child(UIKit.spacer())
	var mark := UIKit.label("", &"SmallLabel")
	mark.add_theme_font_size_override("font_size", 12)
	top.add_child(mark)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.spotlight_box())
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(frame)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cat == "coins":
		# A coin, a little bigger for the bigger rewards.
		icon.texture = UIKit.coin_icon()
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var side := 48.0 + 24.0 * clampf((int(Season.reward(tier).coins) - 200) / 600.0, 0.0, 1.0)
		icon.custom_minimum_size = Vector2(side, side)
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(icon)
		frame.add_child(center)
	else:
		var id := str(Season.reward(tier).item[1])
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		frame.add_child(icon)
		_thumbs.request("season:%s/%s" % [cat, id], ShopScreen._thumb_builder(cat, id), Callable(icon, &"set_texture"),
			ShopScreen.FRONT_YAW if cat == "charms" else ShopScreen._yaw_for(cat))
	var title := UIKit.label(Season.reward_name(tier).to_upper(), &"ValueLabel")
	title.add_theme_font_size_override("font_size", 14)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	if cat != "coins":
		title.add_theme_color_override("font_color", Season.COLOR)
	else:
		title.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(title)
	var kind := UIKit.label(str(Season.KIND_NAMES[cat]), &"SmallLabel")
	kind.add_theme_font_size_override("font_size", 11)
	v.add_child(kind)
	var bar := UITheme.slim_bar(Season.COLOR, Vector2(0, 6))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(bar)
	var claim := UIKit.button("CLAIM", &"GoldButton", false)
	claim.custom_minimum_size = Vector2(0, 40)
	claim.pressed.connect(func() -> void: claim_tier(tier))
	col.add_child(claim)
	_cards.append({"card": card, "claim": claim, "mark": mark, "bar": bar})
	return col


# ------------------------------------------------------------------ state

func _on_profile_changed() -> void:
	if is_inside_tree():
		_refresh()


## Header, every card's state and the detail panel, from Profile.
func _refresh() -> void:
	var xp := Profile.season_xp
	var tier := Profile.season_tier()
	_tier_label.text = "%d / %d" % [tier, Season.TIERS]
	_xp_label.text = "%s / %s" % [UIKit.format_int(xp), UIKit.format_int(Season.MAX_XP)]
	if tier >= Season.TIERS:
		_bar.value = 1.0
		_next_label.text = "Every tier reached. The whole pass is yours."
	else:
		_bar.value = float(Season.tier_progress(xp)) / Season.XP_PER_TIER
		_next_label.text = "%s / %s to tier %d  ·  next: %s" % [UIKit.format_int(Season.tier_progress(xp)),
			UIKit.format_int(Season.XP_PER_TIER), tier + 1, Season.reward_text(tier + 1)]
	_time_label.text = Season.time_left_text()
	_time_label.add_theme_color_override("font_color", UITheme.GOOD if Season.ended() else UITheme.TEXT)
	var claimable := Profile.claimable_season_tiers().size()
	_claim_all.disabled = claimable == 0
	_claim_all.text = "CLAIM ALL (%d)" % claimable if claimable > 0 else "CLAIM ALL"
	_claim_all.focus_mode = Control.FOCUS_ALL if claimable > 0 else Control.FOCUS_NONE
	for i in _cards.size():
		_refresh_card(i + 1)
	_refresh_detail()


func _refresh_card(tier: int) -> void:
	var c: Dictionary = _cards[tier - 1]
	var card: Button = c.card
	var claim: Button = c.claim
	var mark: Label = c.mark
	var bar: ProgressBar = c.bar
	var reached := tier <= Profile.season_tier()
	var claimed := Profile.season_claimed.has(tier)
	card.modulate = Color.WHITE if reached else Color(0.62, 0.62, 0.68)
	claim.disabled = not Profile.can_claim_tier(tier)
	claim.focus_mode = Control.FOCUS_NONE if claim.disabled else Control.FOCUS_ALL
	claim.theme_type_variation = &"GoldButton" if not claim.disabled else &""
	if claimed:
		claim.text = "CLAIMED"
		mark.text = "✓"
		mark.add_theme_color_override("font_color", UITheme.GOOD)
	elif reached:
		claim.text = "CLAIM"
		mark.text = "READY"
		mark.add_theme_color_override("font_color", UITheme.ACCENT)
	else:
		claim.text = "LOCKED"
		mark.text = "LOCKED"
		mark.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	# The tier being worked on shows how far along it is.
	bar.visible = tier == Profile.season_tier() + 1
	bar.value = float(Season.tier_progress(Profile.season_xp)) / Season.XP_PER_TIER


## Shows tier `tier` in the detail panel: its live preview (cosmetics) or the coin, and its state.
func _select(tier: int) -> void:
	if tier == _selected:
		return
	_selected = tier
	(_cards[tier - 1].card as Button).set_pressed_no_signal(true)
	var r := Season.reward(tier)
	var cat := Season.reward_category(tier)
	_coin_view.get_parent().visible = cat == "coins"
	_preview.visible = cat != "coins"
	if cat == "coins":
		_preview.show_model(null)
	else:
		var id := str(r.item[1])
		var gun := cat in ["skins", "charms"]
		_preview.show_model(ShopScreen._preview_model(cat, id), cat == "outfits", ShopScreen._yaw_for(cat), 1.15 if gun else 0.95)
	_refresh_detail()


func _refresh_detail() -> void:
	if _selected < 1:
		return
	var tier := _selected
	var cat := Season.reward_category(tier)
	_name.text = Season.reward_name(tier).to_upper()
	_name.add_theme_color_override("font_color", UITheme.ACCENT if cat == "coins" else Season.COLOR)
	_kind.text = "TIER %d  ·  %s" % [tier, Season.KIND_NAMES[cat]]
	var claimed := Profile.season_claimed.has(tier)
	_equip.visible = false
	if claimed:
		_state.text = "CLAIMED"
		_state.add_theme_color_override("font_color", UITheme.GOOD)
		if cat != "coins":
			var id := str(Season.reward(tier).item[1])
			if Profile.is_equipped(cat, id):
				_state.text = "EQUIPPED"
			else:
				_equip.visible = true
	elif Profile.can_claim_tier(tier):
		_state.text = "READY TO CLAIM"
		_state.add_theme_color_override("font_color", UITheme.ACCENT)
	else:
		var need := tier * Season.XP_PER_TIER - Profile.season_xp
		_state.text = "%s SEASON XP TO GO" % UIKit.format_int(need)
		_state.add_theme_color_override("font_color", UITheme.TEXT_DIM)


func _focus_card(tier: int) -> void:
	if not is_visible_in_tree():
		return
	var card: Button = _cards[tier - 1].card
	card.grab_focus()
	_scroll.ensure_control_visible(card)


# ------------------------------------------------------------------ actions

## CLAIM on a card: pays the tier once (Profile.claim_season_tier).
func claim_tier(tier: int) -> void:
	var from: Button = _cards[tier - 1].claim
	var got := Profile.claim_season_tier(tier)
	if got.is_empty():
		Sfx.play(&"ui_error")
		return
	_select(tier)
	_pop(_cards[tier - 1].card)
	if (got.item as Array).is_empty():
		Sfx.play(&"coins")
		_say("Tier %d claimed: +%s coins" % [tier, UIKit.format_int(int(got.coins))], UITheme.ACCENT)
		_float("+%d" % int(got.coins), from)
	else:
		Sfx.play(&"ui_buy")
		_say("Tier %d claimed: %s unlocked. Equip it here or in the Locker." % [tier, Season.reward_text(tier)], Season.COLOR)
		_float("UNLOCKED!", from)
	# The claimed button can no longer hold the focus; keep it on the card.
	_cards[tier - 1].card.grab_focus()


## CLAIM ALL: every reached tier at once (Profile.claim_all_season).
func claim_all() -> void:
	var got := Profile.claim_all_season()
	if (got.tiers as Array).is_empty():
		Sfx.play(&"ui_error")
		return
	Sfx.play(&"level_up")
	var parts: Array[String] = []
	if int(got.coins) > 0:
		parts.append("+%s coins" % UIKit.format_int(int(got.coins)))
	for item: Array in got.items:
		parts.append(str(Data.catalog(item[0])[item[1]].name))
	var n := (got.tiers as Array).size()
	_say("Claimed %d tier%s: %s" % [n, "" if n == 1 else "s", ", ".join(parts)], Season.COLOR)
	if int(got.coins) > 0:
		_float("+%d" % int(got.coins), _claim_all)
	for t: int in got.tiers:
		_pop(_cards[t - 1].card)
	_focus_card(int(got.tiers[-1]))


func _on_equip() -> void:
	var r := Season.reward(_selected)
	if r.has("item") and Profile.equip(str(r.item[0]), str(r.item[1])):
		Sfx.play(&"ui_click")
		_say("%s equipped." % Season.reward_name(_selected), UITheme.GOOD)
		_cards[_selected - 1].card.grab_focus()


func _say(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _float(text: String, from: Control) -> void:
	var menu := get_tree().current_scene
	if menu != null and menu.has_method("_float_text"):
		menu.call("_float_text", text, from.get_global_rect().get_center())


func _pop(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2(1.06, 1.06), 0.08)
	t.tween_property(c, "scale", Vector2.ONE, 0.18)
