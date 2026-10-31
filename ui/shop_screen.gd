class_name ShopScreen
extends MenuScreen
## Shop: four groups (WEAPONS, STYLE, CHARACTER, EXTRAS) with a strip of sub-tabs per catalog
## category (the weapons catalog split into GUNS and MELEE), a grid of rounded item cards with
## rendered icons and their owned / equipped / price state, and a detail panel with a live 3D
## preview, stats (weapons), price and Buy/Equip actions.
## The ATTACHMENTS tab sells upgrade levels instead of items (Data.ATTACHMENTS): one level at a
## time, each dearer than the last, applying to every gun.
## Dev Pack pieces (`dev: true`) get a neon-edged card and a CODE ONLY tag instead of a price and
## no Buy button; owned, they equip like anything else.

## Group name -> its sub-tabs ([tab id, label]); a tab id is a Data catalog, or "melee".
const GROUPS := {
	"WEAPONS": [["weapons", "GUNS"], ["melee", "MELEE"], ["attachments", "ATTACHMENTS"]],
	"STYLE": [["skins", "SKINS"], ["charms", "CHARMS"]],
	"CHARACTER": [["outfits", "OUTFITS"], ["hats", "HATS"]],
	"EXTRAS": [["emotes", "WIN EMOTES"], ["draws", "DRAWS"], ["sprays", "SPRAYS"]],
}
const CARD_WIDTH := 180.0
## Gun pointing right, angled a little towards the camera.
const GUN_YAW := -PI * 0.5 - 0.3
## Characters and hats face -Z; turn them to face the camera, three-quarter view.
const FRONT_YAW := PI - 0.45
## Spray tiles face the camera straight on.
const SPRAY_YAW := PI
## Moment of each win emote shown on its card.
const EMOTE_ICON_TIME := {"wave": 0.15, "flex": 0.3, "dance": 0.2, "salute": 1.0, "dab": 0.5,
	"spin": 0.0, "jumps": 0.39, "backflip": 0.75, "chicken": 0.1}

## The Data catalog of the open tab ("weapons" for both GUNS and MELEE).
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
## Sub-tab chips of the open group (tab id -> Button), and the group tabs (name -> Button).
var _tab_buttons := {}
var _group_buttons := {}
var _sub_tabs: HBoxContainer
var _group := ""
var _shake: Tween
var _flash: Tween


## Leaving the shop goes back to the menu song.
func _exit_tree() -> void:
	Sfx.play_music(&"menu")


func _ready() -> void:
	Sfx.play_music(&"shop")
	var page := make_page()
	page.add_child(make_header("SHOP", "Everything is earned in matches. No loot boxes, ever."))
	_thumbs = Thumbnailer.new()
	add_child(_thumbs)

	var body := UIKit.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var groups := UIKit.hbox(6)
	left.add_child(groups)
	var group := ButtonGroup.new()
	for g: String in GROUPS:
		var b := UIKit.button(g, &"TabButton")
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func() -> void: show_group(g))
		groups.add_child(b)
		_group_buttons[g] = b
	_sub_tabs = UIKit.hbox(6)
	left.add_child(_sub_tabs)
	var list_panel := UIKit.panel(&"InsetPanel")
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(list_panel)
	_scroll = UIKit.pad_friendly(ScrollContainer.new())
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.resized.connect(_fit_columns)
	list_panel.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
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
	_grid.columns = maxi(2, int((_scroll.size.x - 12.0) / (CARD_WIDTH + 12.0)))


## Items listed under `cat`: a Data catalog, or the attachment upgrades.
static func _items(cat: String) -> Dictionary:
	return Data.ATTACHMENTS if cat == "attachments" else Data.catalog(cat)


## Item ids on `tab`: its catalog, with the weapons split into guns ("weapons") and "melee".
static func _tab_ids(tab: String) -> Array:
	if tab == "weapons" or tab == "melee":
		return Data.WEAPONS.keys().filter(func(id: String) -> bool: return Data.is_melee(id) == (tab == "melee"))
	return _items(tab).keys()


# ------------------------------------------------------------------ list

## Opens a group on its first sub-tab.
func show_group(g: String) -> void:
	_show_category(str(GROUPS[g][0][0]))


## The group holding sub-tab `tab`.
static func _group_of(tab: String) -> String:
	for g: String in GROUPS:
		for t: Array in GROUPS[g]:
			if t[0] == tab:
				return g
	return ""


## Rebuilds the sub-tab chips for group `g`.
func _build_sub_tabs(g: String) -> void:
	_group = g
	_group_buttons[g].button_pressed = true
	for c in _sub_tabs.get_children():
		c.queue_free()
	_tab_buttons.clear()
	var chips := ButtonGroup.new()
	for t: Array in GROUPS[g]:
		var b := UIKit.button(t[1], &"ChipButton")
		b.toggle_mode = true
		b.button_group = chips
		var tab: String = t[0]
		b.pressed.connect(func() -> void: _show_category(tab))
		_sub_tabs.add_child(b)
		_tab_buttons[tab] = b


func _show_category(tab: String) -> void:
	var g := _group_of(tab)
	if g != _group:
		_build_sub_tabs(g)
	_category = "weapons" if tab == "melee" else tab
	_tab_buttons[tab].button_pressed = true
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	var group := ButtonGroup.new()
	var first := ""
	for id: String in _tab_ids(tab):
		_grid.add_child(_make_card(_category, id, group))
		if first.is_empty():
			first = id
	_scroll.scroll_vertical = 0
	_refresh_cards()
	_select(first)


func _make_card(cat: String, id: String, group: ButtonGroup) -> Button:
	var item: Dictionary = _items(cat)[id]
	var dev := cat != "attachments" and UIKit.is_dev_item(cat, id)
	# Dev Pack pieces: neon-edged black card and neon title, CODE ONLY instead of a price.
	var card := UIKit.button("", &"DevCardButton" if dev else &"CardButton")
	card.toggle_mode = true
	card.button_group = group
	card.custom_minimum_size = Vector2(CARD_WIDTH, 168)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.pressed.connect(func() -> void: _select(id))
	_cards[id] = card
	var v := UIKit.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
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
		var thumb_yaw := FRONT_YAW if cat == "charms" else _yaw_for(cat)
		_thumbs.request("%s/%s" % [cat, id], builder, Callable(icon, &"set_texture"), thumb_yaw)
	else:
		var none := UIKit.label("NONE", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
		none.add_theme_color_override("font_color", Color(UITheme.TEXT_DIM, 0.4))
		none.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_child(none)
	var name_row := UIKit.hbox(6)
	v.add_child(name_row)
	var title := UIKit.label(String(item.name).to_upper(), &"ValueLabel")
	title.add_theme_font_size_override("font_size", 14)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	if dev:
		title.add_theme_color_override("font_color", DevPack.NEON)
	name_row.add_child(title)
	if cat != "attachments":
		var colors := UIKit.item_colors(cat, id)
		if not colors.is_empty():
			name_row.add_child(UIKit.swatch(colors, 10))
	var foot := UIKit.hbox(6)
	foot.custom_minimum_size.y = 20
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
		"charms":
			if id == "none":
				return Callable()
			return func() -> Node3D: return Models.build_charm(id)
		"emotes":
			return func() -> Node3D:
				var a := Models.build_avatar("classic", "none")
				a.pose_emote(id, float(EMOTE_ICON_TIME.get(id, 0.3)))
				return a
		"draws":
			return func() -> Node3D: return DrawPreview.create(id, "revolver", "default", "none", 0.45)
		"sprays":
			return func() -> Node3D: return Models.build_spray(id)
		"attachments":
			return func() -> Node3D: return Models.build_attachment(id)
	return Callable()


func _refresh_cards() -> void:
	for id: String in _cards:
		var foot: HBoxContainer = _cards[id].find_child("Foot", true, false)
		for c in foot.get_children():
			c.queue_free()
		if _category == "attachments":
			_attachment_foot(foot, id)
		elif _is_equipped(id):
			foot.add_child(UIKit.badge("EQUIPPED", &"GoodBadgePanel"))
		elif Profile.is_owned(_category, id):
			var owned := UIKit.label("OWNED", &"SmallLabel")
			owned.add_theme_font_size_override("font_size", 12)
			foot.add_child(owned)
		elif UIKit.is_dev_item(_category, id):
			foot.add_child(UIKit.code_only_badge())
		else:
			var price := UIKit.coin_amount(Profile.price_of(_category, id), 16)
			if Profile.coins < Profile.price_of(_category, id):
				price.modulate = Color(1, 1, 1, 0.45)
			foot.add_child(price)


## Card footer for an attachment: level pips, then the next level's price or MAX.
func _attachment_foot(foot: HBoxContainer, id: String) -> void:
	foot.add_child(_level_pips(id, 12))
	foot.add_child(UIKit.spacer())
	if Profile.is_upgrade_maxed(id):
		foot.add_child(UIKit.badge("MAX", &"GoodBadgePanel"))
		return
	var cost := Profile.upgrade_price(id)
	var price := UIKit.coin_amount(cost, 16)
	if Profile.coins < cost:
		price.modulate = Color(1, 1, 1, 0.45)
	foot.add_child(price)


## Row of squares, filled up to the level owned.
func _level_pips(id: String, block: int) -> HBoxContainer:
	var lvl := Profile.upgrade_level(id)
	var colors: Array[Color] = []
	for i in int(Data.ATTACHMENTS[id].max):
		colors.append(UITheme.ACCENT if i < lvl else Color(UITheme.TEXT_DIM, 0.25))
	return UIKit.swatch(colors, block)


func _is_equipped(id: String) -> bool:
	return Profile.is_equipped(_category, id)


# ------------------------------------------------------------------ detail

func _select(id: String) -> void:
	_selected = id
	if _cards.has(id):
		_cards[id].set_pressed_no_signal(true)
	_refresh_detail()
	var cat := _category
	var gun := cat in ["weapons", "skins", "charms", "draws"]
	var pedestal := cat in ["outfits", "emotes"] or (cat == "hats" and id == "none")
	_preview.show_model(_preview_model(cat, id), pedestal, _yaw_for(cat), 1.15 if gun else 0.95)


func _yaw_for(cat: String) -> float:
	if cat == "sprays":
		return SPRAY_YAW
	return GUN_YAW if cat in ["weapons", "skins", "charms", "draws", "attachments"] else FRONT_YAW


func _preview_model(cat: String, id: String) -> Node3D:
	match cat:
		"weapons":
			return Models.build_gun(id, Profile.gun_skin(id), Profile.equipped.charm)
		"skins":
			return Models.build_gun(Profile.loadout.primary, id, Profile.equipped.charm)
		"hats":
			if id == "none":
				return Models.build_avatar(Profile.equipped.outfit, "none")
			return Models.build_hat(id)
		"outfits":
			var avatar := Models.build_avatar(id, Profile.equipped.hat)
			avatar.charm_id = Profile.equipped.charm
			avatar.hold_weapon(Profile.loadout.primary, Profile.gun_skin(Profile.loadout.primary))
			return avatar
		"charms":
			# On the equipped primary, so it swings as the preview turns.
			return Models.build_gun(Profile.loadout.primary, Profile.gun_skin(Profile.loadout.primary), id)
		"emotes":
			var dancer := Models.build_avatar(Profile.equipped.outfit, Profile.equipped.hat)
			dancer.play_emote(id)
			return dancer
		"draws":
			return DrawPreview.create(id, Profile.loadout.secondary, Profile.gun_skin(Profile.loadout.secondary), Profile.equipped.charm)
		"sprays":
			return Models.build_spray(id)
		"attachments":
			return Models.build_attachment(id)
	return null


func _refresh_detail() -> void:
	if _selected.is_empty():
		return
	var cat := _category
	var id := _selected
	for c in _stats.get_children():
		c.queue_free()
	for c in _price_row.get_children():
		c.queue_free()
	var dev := cat != "attachments" and UIKit.is_dev_item(cat, id)
	if dev:
		_name.add_theme_color_override("font_color", DevPack.NEON)
	else:
		_name.remove_theme_color_override("font_color")
	if cat == "attachments":
		_refresh_attachment_detail(id)
		return
	var item: Dictionary = Data.catalog(cat)[id]
	_name.text = String(item.name).to_upper()
	_desc.text = UIKit.item_description(cat, id)
	_buy.text = "BUY"
	match cat:
		"weapons":
			var slot: String = item.slot
			_kind.text = {"primary": "PRIMARY WEAPON", "secondary": "SECONDARY WEAPON", "melee": "MELEE"}[slot]
			for s: Array in UIKit.weapon_stats(id):
				_stats.add_child(UIKit.stat_bar(s[0], s[1], s[2]))
			# Mastery progress towards Gold (Data.MASTERY_TIERS), with the tier reached.
			var gold := int(Data.MASTERY_TIERS[-1].kills)
			var kills := Profile.weapon_stat(id, "kills")
			var tier := Profile.mastery_tier(id)
			_stats.add_child(UIKit.stat_bar("MASTERY", minf(1.0, float(kills) / gold), "%s  %d/%d" % [
				"NONE" if tier == 0 else str(Data.MASTERY_TIERS[tier - 1].name).to_upper(), mini(kills, gold), gold]))
		"skins":
			_kind.text = "WEAPON SKIN"
		"hats":
			_kind.text = "HAT"
		"outfits":
			_kind.text = "OUTFIT"
		"charms":
			_kind.text = "WEAPON CHARM · HANGS FROM EVERY GUN"
		"emotes":
			_kind.text = "WIN EMOTE · PLAYED WHEN YOU WIN A MATCH"
		"draws":
			_kind.text = "DRAW ANIMATION · LOOKS ONLY, NEVER SLOWER"
		"sprays":
			_kind.text = "SPRAY · PAINT IT ON A WALL WITH %s" % Profile.key_text("spray")
	if dev:
		_kind.text += " · THE DEV PACK"
	var owned := Profile.is_owned(cat, id)
	var equipped := _is_equipped(id)
	var price := Profile.price_of(cat, id)
	_buy.visible = not owned and not dev
	_equip.visible = owned and not equipped
	_state.visible = equipped
	_state.text = "EQUIPPED"
	_state.add_theme_color_override("font_color", UITheme.GOOD)
	if not owned and dev:
		_price_row.add_child(UIKit.code_only_badge())
	elif not owned:
		_price_row.add_child(UIKit.coin_amount(price, 26))
		var short := price - Profile.coins
		_buy.disabled = short > 0
		_buy.tooltip_text = "You need %s more coins." % UIKit.format_int(short) if short > 0 else ""
	elif not equipped:
		var owned_label := UIKit.label("OWNED", &"ValueLabel")
		owned_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_price_row.add_child(owned_label)


## Attachment detail: level pips, the stat now and after the next level, and the upgrade price.
func _refresh_attachment_detail(id: String) -> void:
	var a: Dictionary = Data.ATTACHMENTS[id]
	var lvl := Profile.upgrade_level(id)
	var top := int(a.max)
	_name.text = String(a.name).to_upper()
	_kind.text = "ATTACHMENT · LEVEL %d / %d · EVERY GUN" % [lvl, top]
	if lvl > 0 and not Profile.is_attachment_on(id):
		_kind.text += " · SWITCHED OFF IN THE LOCKER"
	_desc.text = String(a.desc)
	var pips := UIKit.hbox(10)
	pips.add_child(UIKit.label("LEVEL", &"SmallLabel"))
	pips.add_child(_level_pips(id, 18))
	_stats.add_child(pips)
	var now := _effect_text(id, lvl)
	var text := now if lvl >= top else "%s  >  %s" % [now, _effect_text(id, lvl + 1)]
	_stats.add_child(UIKit.stat_bar(String(a.stat), float(lvl) / top, text))
	_equip.visible = false
	_buy.text = "UPGRADE"
	if lvl >= top:
		_buy.visible = false
		_state.visible = true
		_state.text = "MAXED"
		_state.add_theme_color_override("font_color", UITheme.GOOD)
		return
	_state.visible = false
	_buy.visible = true
	var cost := Profile.upgrade_price(id)
	_price_row.add_child(UIKit.coin_amount(cost, 26))
	var short := cost - Profile.coins
	_buy.disabled = short > 0
	_buy.tooltip_text = "You need %s more coins." % UIKit.format_int(short) if short > 0 else ""


## "-21%" style change an attachment makes at `level` ("+0%" at level 0).
static func _effect_text(id: String, level: int) -> String:
	var pct := roundi((Data.attachment_mult(id, level) - 1.0) * 100.0)
	return "%s%d%%" % ["+" if pct >= 0 else "", pct]


## Price of the selected item (or next attachment level); -1 if it can't be bought.
func _selected_price() -> int:
	if _category == "attachments":
		return Profile.upgrade_price(_selected)
	return Profile.price_of(_category, _selected)


func _on_buy() -> void:
	var ok := Profile.buy_upgrade(_selected) if _category == "attachments" else Profile.buy(_category, _selected)
	if ok:
		Sfx.play(&"ui_buy")
		_pop(_cards.get(_selected))
		if _category == "attachments":
			_flash_text("LEVEL %d!" % Profile.upgrade_level(_selected))
		else:
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
	var short := _selected_price() - Profile.coins
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
