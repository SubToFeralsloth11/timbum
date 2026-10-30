class_name AchievementsScreen
extends MenuScreen
## Lifetime medals (match highlights, Profile.medal_count) and the achievements
## (Data.ACHIEVEMENTS): locked or unlocked with the unlock date, and progress where it counts up.

const GOLD := Color(1, 0.82, 0.25)

var _subtitle: Label
var _medals: GridContainer
var _grid: GridContainer


func _ready() -> void:
	var page := make_page()
	var header := make_header("ACHIEVEMENTS", "")
	page.add_child(header)
	_subtitle = UIKit.label("", &"DimLabel")
	(header.get_child(1) as Control).add_child(_subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(center)
	var col := UIKit.vbox(14)
	col.custom_minimum_size.x = 900
	center.add_child(col)

	var medal_card := UIKit.panel()
	col.add_child(medal_card)
	var mv := UIKit.vbox(8)
	medal_card.add_child(mv)
	var mh := UIKit.hbox(12)
	mv.add_child(mh)
	mh.add_child(UIKit.label("MEDALS", &"SubheaderLabel"))
	var hint := UIKit.label("Match highlights you earned, counted for life", &"SmallLabel")
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mh.add_child(hint)
	_medals = GridContainer.new()
	_medals.columns = 3
	_medals.add_theme_constant_override("h_separation", 10)
	_medals.add_theme_constant_override("v_separation", 8)
	mv.add_child(_medals)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	col.add_child(_grid)


func on_shown() -> void:
	for c in _medals.get_children():
		c.queue_free()
	for id: String in Data.MEDALS:
		_medals.add_child(_medal_tile(id))
	for c in _grid.get_children():
		c.queue_free()
	for id: String in Data.ACHIEVEMENTS:
		_grid.add_child(_card(id))
	_subtitle.text = "%d of %d unlocked  ·  %d medals earned" % [Profile.achievements.size(), Data.ACHIEVEMENTS.size(),
		int(Profile.feats.get("medals", 0))]


func _medal_tile(id: String) -> Control:
	var m: Dictionary = Data.MEDALS[id]
	var count := Profile.medal_count(id)
	var tile := UIKit.panel(&"CardPanel")
	tile.custom_minimum_size.x = 290
	tile.tooltip_text = str(m.desc)
	var h := UIKit.hbox(10)
	tile.add_child(h)
	var n := UIKit.label("×%d" % count, &"ValueLabel")
	n.add_theme_font_size_override("font_size", 24)
	n.add_theme_color_override("font_color", GOLD if count > 0 else UITheme.TEXT_DIM)
	n.custom_minimum_size.x = 62
	h.add_child(n)
	var v := UIKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UIKit.label(str(m.name).to_upper(), &"ValueLabel"))
	var mode := str(m.mode)
	v.add_child(UIKit.label(str(Data.MODES[mode].name) if not mode.is_empty() else "Every mode", &"SmallLabel"))
	return tile


func _card(id: String) -> Control:
	var a: Dictionary = Data.ACHIEVEMENTS[id]
	var unlocked := Profile.achievements.has(id)
	var card := UIKit.panel(&"CardPanel")
	card.custom_minimum_size.x = 445
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not unlocked:
		card.modulate = Color(1, 1, 1, 0.72)
	var h := UIKit.hbox(12)
	card.add_child(h)
	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(46, 46)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.add_theme_stylebox_override("panel", UITheme.panel_box(GOLD.darkened(0.15) if unlocked else Color(0.22, 0.24, 0.3), GOLD if unlocked else Color(0.35, 0.37, 0.45), 2, 4, 0))
	var mark := UIKit.label("★" if unlocked else "?", &"ValueLabel", HORIZONTAL_ALIGNMENT_CENTER)
	mark.add_theme_font_size_override("font_size", 24)
	mark.add_theme_color_override("font_color", Color(0.25, 0.14, 0.0) if unlocked else UITheme.TEXT_DIM)
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_child(mark)
	h.add_child(icon)
	var v := UIKit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := UIKit.hbox(8)
	v.add_child(top)
	var title := UIKit.label(str(a.name).to_upper(), &"ValueLabel")
	if unlocked:
		title.add_theme_color_override("font_color", GOLD)
	top.add_child(title)
	top.add_child(UIKit.spacer())
	var status := UIKit.label(_date(int(Profile.achievements[id])) if unlocked else "LOCKED", &"SmallLabel")
	top.add_child(status)
	var desc := UIKit.label(str(a.desc), &"SmallLabel")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var progress := Profile.achievement_progress(id)
	if not unlocked and int(progress[1]) > 1:
		var row := UIKit.hbox(8)
		v.add_child(row)
		var bar := ProgressBar.new()
		bar.theme_type_variation = &"XPBar"
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = int(progress[1])
		bar.value = int(progress[0])
		row.add_child(bar)
		row.add_child(UIKit.label("%s / %s" % [UIKit.format_int(int(progress[0])), UIKit.format_int(int(progress[1]))], &"SmallLabel"))
	return card


## "UNLOCKED 2026-10-31" in the player's time zone.
static func _date(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return "UNLOCKED " + Time.get_date_string_from_unix_time(unix + bias * 60)
