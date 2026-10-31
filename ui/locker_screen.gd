class_name LockerScreen
extends MenuScreen
## Locker: pick loadout and cosmetics from owned items, shown on a live rotating avatar.

signal shop_requested

## [profile category, label, slot key]
const ROWS: Array = [
	["weapons", "PRIMARY", "primary"],
	["weapons", "SECONDARY", "secondary"],
	["weapons", "MELEE", "melee"],
	["tacticals", "TACTICAL", "tactical"],
	["skins", "WEAPON SKIN", "skin"],
	["hats", "HAT", "hat"],
	["outfits", "OUTFIT", "outfit"],
	["charms", "GUN CHARM", "charm"],
	["draws", "DRAW ANIMATION", "draw"],
	["emotes", "WIN EMOTE", "emote"],
	["sprays", "SPRAY", "spray"],
]
## ROWS before this index are loadout, the rest style.
const STYLE_START := 4

var _pickers := {}
var _preview: ModelPreview
var _gun_preview: ModelPreview
var _summary: Label
var _name_tag: Label
## Mastery rows (primary, secondary, melee weapon): progress and the camo switch, refilled on show.
var _mastery_box: VBoxContainer
## One ON/OFF switch per owned attachment upgrade (Profile.set_attachment_on), refilled on show.
var _attach_box: VBoxContainer
## Loadout presets: one tab per preset (the pressed one is active, and the pickers below edit it)
## and a name field with RENAME.
var _preset_tabs: Array[Button] = []
var _preset_name: LineEdit


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("LOCKER", "Your loadout presets and style. Everyone in the match sees them."))
	var body := UIKit.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	var left := UIKit.panel()
	left.custom_minimum_size.x = 400
	body.add_child(left)
	# Scrolls on short windows (loadout, mastery and style rows plus the gun preview).
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var v := UIKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(UIKit.label("LOADOUT", &"SubheaderLabel"))
	# One full-width button per preset, so a 16-character name fits.
	var tabs := UIKit.vbox(4)
	v.add_child(tabs)
	var group := ButtonGroup.new()
	for i in Profile.LOADOUT_PRESET_COUNT:
		var b := UIKit.button("", &"TabButton")
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: _on_preset_tab(i))
		tabs.add_child(b)
		_preset_tabs.append(b)
	var name_row := UIKit.hbox(6)
	v.add_child(name_row)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "Preset name"
	_preset_name.max_length = 16
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_name.text_submitted.connect(func(_t: String) -> void: _on_preset_rename())
	name_row.add_child(_preset_name)
	var rename := UIKit.button("RENAME", &"IconButton")
	rename.tooltip_text = "Give the active preset the name typed here."
	rename.pressed.connect(_on_preset_rename)
	name_row.add_child(rename)
	var preset_help := UIKit.label("The ACTIVE preset is the one you spawn with. Switch while dead with %s / %s / %s, or on the results screen."
		% [Profile.key_text("weapon_1"), Profile.key_text("weapon_2"), Profile.key_text("weapon_3")], &"DimLabel")
	preset_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(preset_help)
	for i in ROWS.size():
		if i == STYLE_START:
			v.add_child(UIKit.label("MASTERY", &"SubheaderLabel"))
			_mastery_box = UIKit.vbox(4)
			v.add_child(_mastery_box)
			v.add_child(HSeparator.new())
			v.add_child(UIKit.label("ATTACHMENTS", &"SubheaderLabel"))
			_attach_box = UIKit.vbox(4)
			v.add_child(_attach_box)
			v.add_child(HSeparator.new())
			v.add_child(UIKit.label("STYLE", &"SubheaderLabel"))
		var row: Array = ROWS[i]
		var h := UIKit.hbox(10)
		v.add_child(h)
		var l := UIKit.label(row[1], &"SmallLabel")
		l.add_theme_color_override("font_color", UITheme.TEXT)
		l.custom_minimum_size.x = 120
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		var o := OptionButton.new()
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		o.fit_to_longest_item = false
		UIKit.wire(o)
		var key: String = row[2]
		o.item_selected.connect(func(idx: int) -> void: _on_pick(key, idx))
		h.add_child(o)
		_pickers[key] = o
	v.add_child(UIKit.spacer(false))
	var gun_frame := UIKit.panel(&"InsetPanel")
	gun_frame.custom_minimum_size.y = 120
	v.add_child(gun_frame)
	_gun_preview = ModelPreview.new()
	_gun_preview.stage.spin_speed = 0.8
	gun_frame.add_child(_gun_preview)
	_summary = UIKit.label("", &"DimLabel")
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_summary)
	var shop := UIKit.button("GET MORE IN THE SHOP", &"GoldButton")
	shop.pressed.connect(func() -> void: shop_requested.emit())
	v.add_child(shop)

	var stage := UIKit.panel(&"InsetPanel")
	stage.add_theme_stylebox_override("panel", UITheme.spotlight_box())
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(stage)
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_PASS
	stage.add_child(layer)
	_preview = ModelPreview.new()
	_preview.stage.spin_speed = 0.4
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_preview)
	_name_tag = UIKit.label("", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_name_tag.add_theme_font_size_override("font_size", 26)
	_name_tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_name_tag.offset_top = 12
	layer.add_child(_name_tag)
	var hint := UIKit.label("DRAG TO ROTATE", &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -30
	hint.offset_bottom = -10
	layer.add_child(hint)


func on_shown() -> void:
	_fill_presets()
	_fill_pickers()
	_fill_mastery()
	_fill_attachments()
	_rebuild_models()


## Preset buttons ("1  NAME  ✓ ACTIVE" on the active one) and the name field (the active
## preset's name).
func _fill_presets() -> void:
	for i in _preset_tabs.size():
		var active := i == Profile.active_preset
		_preset_tabs[i].text = "%d   %s%s" % [i + 1, str(Profile.loadout_presets[i].name).to_upper(), "   ✓ ACTIVE" if active else ""]
		_preset_tabs[i].tooltip_text = Profile.preset_summary(i)
		_preset_tabs[i].set_pressed_no_signal(active)
	_preset_name.text = str(Profile.loadout_presets[Profile.active_preset].name)


## A preset tab makes that preset active: the pickers show and edit its guns.
func _on_preset_tab(index: int) -> void:
	if not Profile.select_preset(index):
		return
	_fill_presets()
	_fill_pickers()
	_fill_mastery()
	_rebuild_models()


func _on_preset_rename() -> void:
	if Profile.rename_preset(Profile.active_preset, _preset_name.text):
		Sfx.play(&"ui_click")
	else:
		Sfx.play(&"ui_error")
	_fill_presets()


## Mastery progress of the equipped guns and melee weapon, each with a CAMO switch once it reached
## Gold (Profile.set_camo).
func _fill_mastery() -> void:
	for c in _mastery_box.get_children():
		c.queue_free()
	for wid: String in [Profile.loadout.primary, Profile.loadout.secondary, Profile.loadout.melee]:
		var h := UIKit.hbox(8)
		_mastery_box.add_child(h)
		var tier := Profile.mastery_tier(wid)
		var text := UIKit.label("%s  ·  %s" % [str(Data.WEAPONS[wid].name).to_upper(), Profile.mastery_text(wid)], &"SmallLabel")
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.clip_text = true
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if tier > 0:
			text.add_theme_color_override("font_color", Data.MASTERY_TIERS[tier - 1].color)
		h.add_child(text)
		var camo := CheckButton.new()
		camo.text = "CAMO"
		camo.disabled = not Profile.has_camo(wid)
		camo.button_pressed = Profile.is_camo_on(wid)
		camo.tooltip_text = "Wear this gun's mastery camo (everyone sees it)." if Profile.has_camo(wid) \
			else "Reach Gold mastery (%d kills) to unlock this gun's camo." % int(Data.MASTERY_TIERS[-1].kills)
		UIKit.wire(camo)
		camo.toggled.connect(func(on: bool) -> void:
			if Profile.set_camo(wid, on):
				_rebuild_models())
		h.add_child(camo)


## Owned attachment upgrades with their level and an ON/OFF switch: off plays as level 0 (a
## Laser Sight switched off shows no beam); the bought level stays.
func _fill_attachments() -> void:
	for c in _attach_box.get_children():
		c.queue_free()
	var any := false
	for id: String in Data.ATTACHMENTS:
		var lvl := Profile.upgrade_level(id)
		if lvl <= 0:
			continue
		any = true
		var h := UIKit.hbox(8)
		_attach_box.add_child(h)
		var on := Profile.is_attachment_on(id)
		var text := UIKit.label("%s  ·  LEVEL %d" % [str(Data.ATTACHMENTS[id].name).to_upper(), lvl], &"SmallLabel")
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.add_theme_color_override("font_color", UITheme.TEXT if on else UITheme.TEXT_DIM)
		h.add_child(text)
		var sw := CheckButton.new()
		sw.text = "ON" if on else "OFF"
		sw.custom_minimum_size.x = 96
		sw.button_pressed = on
		sw.tooltip_text = "Switch %s off to play as if you hadn't bought it (it stays bought)." % Data.ATTACHMENTS[id].name
		UIKit.wire(sw)
		sw.toggled.connect(func(pressed: bool) -> void:
			Profile.set_attachment_on(id, pressed)
			sw.text = "ON" if pressed else "OFF"
			text.add_theme_color_override("font_color", UITheme.TEXT if pressed else UITheme.TEXT_DIM))
		h.add_child(sw)
	if not any:
		var none := UIKit.label("Attachment upgrades you buy in the shop can be switched on and off here.", &"DimLabel")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_attach_box.add_child(none)


## Owned item ids in `category`; for weapons, only those that go in loadout `slot`.
static func owned_ids(category: String, slot: String) -> Array[String]:
	var ids: Array[String] = []
	for id: String in Data.catalog(category):
		if category == "weapons" and Data.WEAPONS[id].slot != slot:
			continue
		if Profile.is_owned(category, id):
			ids.append(id)
	return ids


func _current(key: String) -> String:
	if key in Profile.LOADOUT_KEYS:
		return Profile.loadout[key]
	return Profile.equipped[key]


func _fill_pickers() -> void:
	for row: Array in ROWS:
		var key: String = row[2]
		var o: OptionButton = _pickers[key]
		o.clear()
		var ids := owned_ids(row[0], key)
		for id in ids:
			if row[0] == "sprays":
				o.add_icon_item(SprayArt.icon(id), String(Data.SPRAYS[id].name))
			else:
				o.add_item(String(Data.catalog(row[0])[id].name))
			o.set_item_metadata(o.item_count - 1, id)
		o.select(ids.find(_current(key)))
		_style_picker(o, row[0], _current(key))


## A picker showing a Dev Pack piece gets the neon edge and text, like its shop card.
static func _style_picker(o: OptionButton, category: String, id: String) -> void:
	o.theme_type_variation = &"DevOptionButton" if UIKit.is_dev_item(category, id) else &""


func _on_pick(key: String, idx: int) -> void:
	var category: String = ""
	for row: Array in ROWS:
		if row[2] == key:
			category = row[0]
	var id: String = _pickers[key].get_item_metadata(idx)
	if Profile.equip(category, id):
		_style_picker(_pickers[key], category, id)
		if key in ["primary", "secondary", "melee"]:
			_fill_mastery()
		if key in Profile.LOADOUT_KEYS:
			_fill_presets()
		_rebuild_models()


func _rebuild_models() -> void:
	var avatar := Models.build_avatar(Profile.equipped.outfit, Profile.equipped.hat)
	avatar.charm_id = Profile.equipped.charm
	avatar.hold_weapon(Profile.loadout.primary, Profile.gun_skin(Profile.loadout.primary))
	# Three-quarter side view so the held gun reads clearly.
	_preview.show_model(avatar, true, PI - 1.1, 0.95)
	_gun_preview.show_model(DrawPreview.create(Profile.equipped.draw, Profile.loadout.secondary, Profile.gun_skin(Profile.loadout.secondary),
		Profile.equipped.charm), false, ShopScreen.GUN_YAW, 1.0)
	_name_tag.text = Data.badged_name(Profile.player_name.to_upper(), Profile.prestige)
	_summary.text = "Melee: %s  ·  Secondary: %s  ·  %s" % [Data.WEAPONS[Profile.loadout.melee].name,
		Data.WEAPONS[Profile.loadout.secondary].name, Data.TACTICALS[Profile.loadout.tactical].name]
