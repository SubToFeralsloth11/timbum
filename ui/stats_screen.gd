class_name StatsScreen
extends MenuScreen
## Career statistics from Profile.stats, shown as big number tiles, plus a live
## development progress card while a build is being worked on.

## Written by the developer tooling while new features are built; the card is
## hidden when the file is absent. Format:
## {updated, percent, task, agents: [{name, doing}], done: [String]}
const DEV_PROGRESS_PATH := "user://dev_progress.json"
const DEV_DONE_SHOWN := 3

var _grid: GridContainer
var _level: Label
var _xp_bar: ProgressBar
var _xp_text: Label
var _dev_card: PanelContainer
var _dev_bar: ProgressBar
var _dev_head: Label
var _dev_task: Label
var _dev_agents: Label
var _dev_done: Label
var _dev_timer: Timer
var _dev_text := ""


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("STATS", "Your career across every match."))
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var col := UIKit.vbox(16)
	col.custom_minimum_size.x = 780
	center.add_child(col)

	var level_card := UIKit.panel()
	col.add_child(level_card)
	var lh := UIKit.hbox(18)
	level_card.add_child(lh)
	_level = UIKit.label("", &"TitleLabel")
	_level.add_theme_font_size_override("font_size", 44)
	_level.add_theme_color_override("font_color", UITheme.ACCENT_2)
	lh.add_child(_level)
	var lv := UIKit.vbox(6)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lh.add_child(lv)
	_xp_text = UIKit.label("", &"SmallLabel")
	lv.add_child(_xp_text)
	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = &"XPBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size.y = 20
	lv.add_child(_xp_bar)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	col.add_child(_grid)

	_build_dev_card(col)
	_dev_timer = Timer.new()
	_dev_timer.wait_time = 2.0
	_dev_timer.timeout.connect(_refresh_dev)
	add_child(_dev_timer)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_dev_timer.start()
		else:
			_dev_timer.stop())


func _build_dev_card(parent: Control) -> void:
	_dev_card = UIKit.panel()
	_dev_card.visible = false
	parent.add_child(_dev_card)
	var v := UIKit.vbox(6)
	_dev_card.add_child(v)
	_dev_head = UIKit.label("", &"SmallLabel")
	_dev_head.add_theme_color_override("font_color", UITheme.ACCENT_2)
	v.add_child(_dev_head)
	_dev_bar = ProgressBar.new()
	_dev_bar.theme_type_variation = &"XPBar"
	_dev_bar.show_percentage = false
	_dev_bar.custom_minimum_size.y = 16
	v.add_child(_dev_bar)
	var h := UIKit.hbox(18)
	v.add_child(h)
	var left := UIKit.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	h.add_child(left)
	_dev_task = UIKit.label("", &"SmallLabel")
	_dev_task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dev_task.add_theme_color_override("font_color", UITheme.TEXT)
	left.add_child(_dev_task)
	_dev_agents = UIKit.label("", &"SmallLabel")
	_dev_agents.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_dev_agents)
	_dev_done = UIKit.label("", &"SmallLabel")
	_dev_done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dev_done.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dev_done.add_theme_color_override("font_color", UITheme.GOOD)
	h.add_child(_dev_done)


## Reloads the progress file when it changed since the last read.
func _refresh_dev() -> void:
	if not FileAccess.file_exists(DEV_PROGRESS_PATH):
		_dev_card.visible = false
		_dev_text = ""
		return
	var text := FileAccess.get_file_as_string(DEV_PROGRESS_PATH)
	if text == _dev_text:
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return # Half-written file; the next tick retries.
	_dev_text = text
	var d: Dictionary = parsed
	var pct := clampf(float(d.get("percent", 0)), 0.0, 100.0)
	_dev_card.visible = true
	_dev_bar.value = pct
	_dev_head.text = "NEW VERSION IN PROGRESS  ·  %d%%  ·  UPDATED %s" % [roundi(pct), str(d.get("updated", "?"))]
	_dev_task.text = "NOW: %s" % str(d.get("task", ""))
	var lines := PackedStringArray()
	for a in d.get("agents", []):
		if a is Dictionary:
			lines.append("AGENT %s: %s" % [str(a.get("name", "?")).to_upper(), str(a.get("doing", ""))])
	_dev_agents.text = "\n".join(lines) if not lines.is_empty() else "No sub-agents running."
	var done: Array = d.get("done", [])
	var shown := PackedStringArray(["DONE:"])
	for i in range(maxi(0, done.size() - DEV_DONE_SHOWN), done.size()):
		shown.append("✔ " + str(done[i]))
	_dev_done.text = "\n".join(shown) if done.size() > 0 else "DONE: nothing yet"


func on_shown() -> void:
	var s := Profile.stats
	var kills := int(s.kills)
	var deaths := int(s.deaths)
	var matches := int(s.matches)
	var kd := float(kills) / maxf(1.0, float(deaths))
	_level.text = "LVL %d" % Profile.level
	var need := Profile.xp_for_level(Profile.level)
	_xp_bar.max_value = need
	_xp_bar.value = Profile.xp
	_xp_text.text = "%s  ·  %s / %s XP TO LEVEL %d" % [Profile.player_name.to_upper(), UIKit.format_int(Profile.xp), UIKit.format_int(need), Profile.level + 1]
	for c in _grid.get_children():
		c.queue_free()
	_tile("KILLS", UIKit.format_int(kills), UITheme.TEXT)
	_tile("DEATHS", UIKit.format_int(deaths), UITheme.TEXT)
	_tile("K/D RATIO", "%.2f" % kd, UITheme.GOOD if kd >= 1.0 else UITheme.BAD)
	_tile("HEADSHOTS", UIKit.format_int(int(s.headshots)), UITheme.TEXT,
		"%d%% of kills" % roundi(100.0 * int(s.headshots) / maxf(1.0, kills)))
	_tile("MATCHES", UIKit.format_int(matches), UITheme.TEXT)
	_tile("WINS", UIKit.format_int(int(s.wins)), UITheme.ACCENT,
		"%d%% win rate" % roundi(100.0 * int(s.wins) / maxf(1.0, matches)))
	_tile("BEST STREAK", UIKit.format_int(int(s.best_streak)), UITheme.TEXT)
	_tile("COINS EARNED", UIKit.format_int(int(s.coins_earned)), UITheme.ACCENT)
	_dev_text = ""
	_refresh_dev()


func _tile(caption: String, value: String, color: Color, note := "") -> void:
	var p := UIKit.panel(&"CardPanel")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(180, 118)
	var v := UIKit.vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var num := UIKit.label(value, &"TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	num.add_theme_font_size_override("font_size", 40)
	num.add_theme_color_override("font_color", color)
	v.add_child(num)
	v.add_child(UIKit.label(caption, &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	if not note.is_empty():
		var n := UIKit.label(note, &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		n.add_theme_color_override("font_color", Color(UITheme.TEXT_DIM, 0.7))
		v.add_child(n)
	_grid.add_child(p)
