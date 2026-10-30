class_name LockerScreen
extends MenuScreen
## Locker: pick loadout and cosmetics from owned items, shown on a live rotating avatar.

signal shop_requested

## [profile category, label, slot key]
const ROWS: Array = [
	["weapons", "PRIMARY", "primary"],
	["weapons", "SECONDARY", "secondary"],
	["tacticals", "TACTICAL", "tactical"],
	["skins", "WEAPON SKIN", "skin"],
	["hats", "HAT", "hat"],
	["outfits", "OUTFIT", "outfit"],
	["charms", "GUN CHARM", "charm"],
	["draws", "DRAW ANIMATION", "draw"],
	["emotes", "WIN EMOTE", "emote"],
]
## ROWS before this index are loadout, the rest style.
const STYLE_START := 3

var _pickers := {}
var _preview: ModelPreview
var _gun_preview: ModelPreview
var _summary: Label
var _name_tag: Label


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("LOCKER", "Your loadout and style. Everyone in the match sees it."))
	var body := UIKit.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	var left := UIKit.panel()
	left.custom_minimum_size.x = 400
	body.add_child(left)
	var v := UIKit.vbox(10)
	left.add_child(v)
	v.add_child(UIKit.label("LOADOUT", &"SubheaderLabel"))
	for i in ROWS.size():
		if i == STYLE_START:
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
	_fill_pickers()
	_rebuild_models()


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
	if key in ["primary", "secondary", "tactical"]:
		return Profile.loadout[key]
	return Profile.equipped[key]


func _fill_pickers() -> void:
	for row: Array in ROWS:
		var key: String = row[2]
		var o: OptionButton = _pickers[key]
		o.clear()
		var ids := owned_ids(row[0], key)
		for id in ids:
			o.add_item(String(Data.catalog(row[0])[id].name))
			o.set_item_metadata(o.item_count - 1, id)
		o.select(ids.find(_current(key)))


func _on_pick(key: String, idx: int) -> void:
	var category: String = ""
	for row: Array in ROWS:
		if row[2] == key:
			category = row[0]
	var id: String = _pickers[key].get_item_metadata(idx)
	if Profile.equip(category, id):
		_rebuild_models()


func _rebuild_models() -> void:
	var avatar := Models.build_avatar(Profile.equipped.outfit, Profile.equipped.hat)
	avatar.charm_id = Profile.equipped.charm
	avatar.hold_weapon(Profile.loadout.primary, Profile.equipped.skin)
	# Three-quarter side view so the held gun reads clearly.
	_preview.show_model(avatar, true, PI - 1.1, 0.95)
	_gun_preview.show_model(DrawPreview.create(Profile.equipped.draw, Profile.loadout.secondary, Profile.equipped.skin,
		Profile.equipped.charm), false, ShopScreen.GUN_YAW, 1.0)
	_name_tag.text = Profile.player_name.to_upper()
	_summary.text = "Secondary: %s  ·  %s  ·  Knife always carried" % [Data.WEAPONS[Profile.loadout.secondary].name,
		Data.TACTICALS[Profile.loadout.tactical].name]
