class_name ShopScreen
extends MenuScreen
## Shop: tabs per catalog category, a grid of item cards with rendered icons, and a
## detail panel with a live 3D preview, stats (guns), price and Buy/Equip actions.

const TABS: Array = [["weapons", "GUNS"], ["skins", "WEAPON SKINS"], ["hats", "HATS"], ["outfits", "OUTFITS"]]
const CARD_WIDTH := 200.0
## Gun pointing right, angled a little towards the camera.
const GUN_YAW := -PI * 0.5 - 0.3
## Characters and hats face -Z; turn them to face the camera, three-quarter view.
const FRONT_YAW := PI - 0.45

var _category := "weapons"
var _selected := ""
var _grid: GridContainer
var _scroll: ScrollContainer
var _cards := {}
var _preview: ModelPreview
var _thumbs: Thumbnailer
var _name: Label
var _kind: Label
var _desc: Label
var _stats: VBoxContainer
var _price_row: HBoxContainer
var _buy: Button
var _equip: Button
var _state: Label
var _tab_buttons := {}
var _shake: Tween
var _flash: Tween


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("SHOP", "Everything is earned in matches. No loot boxes, ever."))
	_thumbs = Thumbnailer.new()
	add_child(_thumbs)

	var body := UIKit.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	var left := UIKit.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var tabs := UIKit.hbox(6)
	left.add_child(tabs)
	var group := ButtonGroup.new()
	for t: Array in TABS:
		var b := UIKit.button(t[1], &"TabButton")
		b.toggle_mode = true
		b.button_group = group
		var cat: String = t[0]
		b.pressed.connect(func() -> void: _show_category(cat))
		tabs.add_child(b)
		_tab_buttons[cat] = b
	var list_panel := UIKit.panel(&"InsetPanel")
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(list_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.resized.connect(_fit_columns)
	list_panel.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)

	body.add_child(_build_detail())
	Profile.changed.connect(_on_profile_changed)
	_show_category("weapons")


func on_shown() -> void:
	_refresh_cards()
	# Rebuild the preview too: it shows the equipped skin/hat/gun, which the locker may have changed.
	if not _selected.is_empty():
		_select(_selected)


func _build_detail() -> Control:
	var panel := UIKit.panel()
	panel.custom_minimum_size.x = 400
	var v := UIKit.vbox(8)
	panel.add_child(v)
	var stage := UIKit.panel(&"InsetPanel")
	stage.add_theme_stylebox_override("panel", UITheme.spotlight_box())
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 190
	v.add_child(stage)
	_preview = ModelPreview.new()
	stage.add_child(_preview)
	_name = UIKit.label("", &"HeaderLabel")
	_name.add_theme_font_size_override("font_size", 28)
	v.add_child(_name)
	_kind = UIKit.label("", &"SmallLabel")
	_kind.add_theme_color_override("font_color", UITheme.ACCENT_2)
	v.add_child(_kind)
	_desc = UIKit.label("", &"DimLabel")
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size.x = 360
	v.add_child(_desc)
	_stats = UIKit.vbox(4)
	v.add_child(_stats)
	v.add_child(HSeparator.new())
	var actions := UIKit.hbox(10)
	v.add_child(actions)
	_price_row = UIKit.hbox(0)
	_price_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_price_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(_price_row)
	_state = UIKit.label("", &"ValueLabel")
	_state.add_theme_font_size_override("font_size", 18)
	_state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(_state)
	_buy = UIKit.button("BUY", &"GoldButton", false)
	_buy.custom_minimum_size = Vector2(140, 52)
	_buy.pressed.connect(_on_buy)
	_buy.gui_input.connect(_on_buy_input)
	actions.add_child(_buy)
	_equip = UIKit.button("EQUIP", &"PrimaryButton")
	_equip.custom_minimum_size = Vector2(140, 52)
	_equip.pressed.connect(_on_equip)
	actions.add_child(_equip)
	return panel


func _fit_columns() -> void:
	_grid.columns = maxi(2, int((_scroll.size.x - 12.0) / (CARD_WIDTH + 10.0)))


# ------------------------------------------------------------------ list

func _show_category(cat: String) -> void:
	_category = cat
	_tab_buttons[cat].button_pressed = true
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	var group := ButtonGroup.new()
	var first := ""
	for id: String in Data.catalog(cat):
		_grid.add_child(_make_card(cat, id, group))
		if first.is_empty():
			first = id
	_scroll.scroll_vertical = 0
	_refresh_cards()
	_select(first)


func _make_card(cat: String, id: String, group: ButtonGroup) -> Button:
	var item: Dictionary = Data.catalog(cat)[id]
	var card := UIKit.button("", &"CardButton")
	card.toggle_mode = true
	card.button_group = group
	card.custom_minimum_size = Vector2(CARD_WIDTH, 176)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.pressed.connect(func() -> void: _select(id))
	_cards[id] = card
	var v := UIKit.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_top = 8
	v.offset_right = -10
	v.offset_bottom = -10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var icon_frame := PanelContainer.new()
	icon_frame.add_theme_stylebox_override("panel", UITheme.spotlight_box())
	icon_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon_frame)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_child(icon)
	var builder := _thumb_builder(cat, id)
	if builder.is_valid():
		# Bound to the icon itself so the callback is skipped if the card was freed.
		_thumbs.request("%s/%s" % [cat, id], builder, Callable(icon, &"set_texture"), _yaw_for(cat))
	else:
		var none := UIKit.label("NONE", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
		none.add_theme_color_override("font_color", Color(UITheme.TEXT_DIM, 0.4))
		none.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_child(none)
	var name_row := UIKit.hbox(6)
	v.add_child(name_row)
	var title := UIKit.label(String(item.name).to_upper(), &"ValueLabel")
	title.add_theme_font_size_override("font_size", 15)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	name_row.add_child(title)
	var colors := UIKit.item_colors(cat, id)
	if not colors.is_empty():
		name_row.add_child(UIKit.swatch(colors, 10))
	var foot := UIKit.hbox(6)
	foot.name = "Foot"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	return card


## Returns a Callable building the icon model, or an invalid Callable for "no item".
func _thumb_builder(cat: String, id: String) -> Callable:
	match cat:
		"weapons":
			return func() -> Node3D: return Models.build_gun(id, "default")
		"skins":
			return func() -> Node3D: return Models.build_gun("rifle", id)
		"hats":
			if id == "none":
				return Callable()
			return func() -> Node3D: return Models.build_hat(id)
		"outfits":
			return func() -> Node3D: return Models.build_avatar(id, "none")
	return Callable()


func _refresh_cards() -> void:
	for id: String in _cards:
		var foot: HBoxContainer = _cards[id].find_child("Foot", true, false)
		for c in foot.get_children():
			c.queue_free()
		if _is_equipped(id):
			foot.add_child(UIKit.badge("EQUIPPED", &"GoodBadgePanel"))
		elif Profile.is_owned(_category, id):
			foot.add_child(UIKit.badge("OWNED"))
		else:
			var price := UIKit.coin_amount(Profile.price_of(_category, id), 16)
			if Profile.coins < Profile.price_of(_category, id):
				price.modulate = Color(1, 1, 1, 0.45)
			foot.add_child(price)


func _is_equipped(id: String) -> bool:
	if _category == "weapons" and Data.WEAPONS[id].slot == "melee":
		return true
	return Profile.is_equipped(_category, id)


# ------------------------------------------------------------------ detail

func _select(id: String) -> void:
	_selected = id
	if _cards.has(id):
		_cards[id].set_pressed_no_signal(true)
	_refresh_detail()
	var gun := _category in ["weapons", "skins"]
	_preview.show_model(_preview_model(_category, id), _category == "outfits" or (_category == "hats" and id == "none"),
		_yaw_for(_category), 1.15 if gun else 0.95)


func _yaw_for(cat: String) -> float:
	return GUN_YAW if cat in ["weapons", "skins"] else FRONT_YAW


func _preview_model(cat: String, id: String) -> Node3D:
	match cat:
		"weapons":
			return Models.build_gun(id, Profile.equipped.skin)
		"skins":
			return Models.build_gun(Profile.loadout.primary, id)
		"hats":
			if id == "none":
				return Models.build_avatar(Profile.equipped.outfit, "none")
			return Models.build_hat(id)
		"outfits":
			var avatar := Models.build_avatar(id, Profile.equipped.hat)
			avatar.hold_weapon(Profile.loadout.primary, Profile.equipped.skin)
			return avatar
	return null


func _refresh_detail() -> void:
	if _selected.is_empty():
		return
	var cat := _category
	var id := _selected
	var item: Dictionary = Data.catalog(cat)[id]
	_name.text = String(item.name).to_upper()
	_desc.text = UIKit.item_description(cat, id)
	for c in _stats.get_children():
		c.queue_free()
	match cat:
		"weapons":
			var slot: String = item.slot
			_kind.text = {"primary": "PRIMARY WEAPON", "secondary": "SECONDARY WEAPON", "melee": "MELEE"}[slot]
			for s: Array in UIKit.weapon_stats(id):
				_stats.add_child(UIKit.stat_bar(s[0], s[1], s[2]))
		"skins":
			_kind.text = "WEAPON SKIN"
		"hats":
			_kind.text = "HAT"
		"outfits":
			_kind.text = "OUTFIT"
	for c in _price_row.get_children():
		c.queue_free()
	var owned := Profile.is_owned(cat, id)
	var equipped := _is_equipped(id)
	var price := Profile.price_of(cat, id)
	_buy.visible = not owned
	_equip.visible = owned and not equipped
	_state.visible = equipped
	if cat == "weapons" and item.slot == "melee":
		_state.text = "ALWAYS CARRIED"
	else:
		_state.text = "EQUIPPED"
	_state.add_theme_color_override("font_color", UITheme.GOOD)
	if not owned:
		_price_row.add_child(UIKit.coin_amount(price, 26))
		var short := price - Profile.coins
		_buy.disabled = short > 0
		_buy.tooltip_text = "You need %s more coins." % UIKit.format_int(short) if short > 0 else ""
	elif not equipped:
		var owned_label := UIKit.label("OWNED", &"ValueLabel")
		owned_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_price_row.add_child(owned_label)


func _on_buy() -> void:
	if Profile.buy(_category, _selected):
		Sfx.play(&"ui_buy")
		_pop(_cards.get(_selected))
		_flash_text("PURCHASED!")
	else:
		_buy_failed()


## Disabled buttons emit no `pressed`; still give feedback when clicked.
func _on_buy_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if _buy.disabled and mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_buy_failed()


func _buy_failed() -> void:
	Sfx.play(&"ui_error")
	var short := Profile.price_of(_category, _selected) - Profile.coins
	if short > 0:
		_flash_text("NEED %s MORE COINS" % UIKit.format_int(short), UITheme.BAD)
	# Repeated clicks mid-shake would capture an offset position and leave the button shifted.
	if _shake != null and _shake.is_running():
		return
	_shake = _buy.create_tween()
	var x := _buy.position.x
	for i in 4:
		_shake.tween_property(_buy, "position:x", x + (6.0 if i % 2 == 0 else -6.0), 0.04)
	_shake.tween_property(_buy, "position:x", x, 0.04)


func _on_equip() -> void:
	if Profile.equip(_category, _selected):
		_pop(_cards.get(_selected))
		if _category != "weapons":
			_flash_text("EQUIPPED!")
		else:
			_flash_text("EQUIPPED AS %s" % String(Data.WEAPONS[_selected].slot).to_upper())


func _on_profile_changed() -> void:
	if not is_inside_tree():
		return
	_refresh_cards()
	_refresh_detail()


func _pop(c: Control) -> void:
	if c == null:
		return
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2(1.06, 1.06), 0.08)
	t.tween_property(c, "scale", Vector2.ONE, 0.18)


func _flash_text(text: String, color := UITheme.GOOD) -> void:
	_state.visible = true
	_state.text = text
	_state.add_theme_color_override("font_color", color)
	_state.modulate.a = 1.0
	# An older flash's reset must not cut this one short.
	if _flash != null:
		_flash.kill()
	_flash = _state.create_tween()
	_flash.tween_interval(1.4)
	_flash.tween_callback(_refresh_detail)
