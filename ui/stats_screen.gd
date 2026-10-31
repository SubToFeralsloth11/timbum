class_name StatsScreen
extends MenuScreen
## Career statistics from Profile.stats, shown as big number tiles, plus a live
## development progress card while a build is being worked on. CREDITS opens the CreditsPanel
## overlay (and, behind its DEV row, the keypad for the dev code).

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
var _backup_status: Label
var _export_dialog: FileDialog
var _import_dialog: FileDialog
var _confirm: ConfirmationDialog
var _import_path := ""
var _prestige_btn: Button
var _prestige_confirm: ConfirmationDialog
var _weapon_table: GridContainer
var _credits_btn: Button
var _credits: CreditsPanel
## Per-weapon table columns: [header, minimum width].
const WEAPON_COLUMNS: Array = [["WEAPON", 190], ["KILLS", 70], ["ACCURACY", 100], ["HEADSHOT %", 100],
	["DAMAGE", 90], ["MASTERY", 160]]


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("STATS", "Your career across every match."))
	# Scrolls when the per-weapon table and the dev card don't fit the window.
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(center)
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
	_backup_status = UIKit.label("", &"SmallLabel")
	lv.add_child(_backup_status)
	var backup := UIKit.vbox(6)
	backup.alignment = BoxContainer.ALIGNMENT_CENTER
	lh.add_child(backup)
	_prestige_btn = UIKit.button("PRESTIGE", &"GoldButton")
	_prestige_btn.pressed.connect(func() -> void:
		_prestige_confirm.dialog_text = ("Prestige to rank %d?\nYour level goes back to 1 and you get %s coins and the %s badge.\n"
			+ "Coins, items, upgrades and stats stay.") % [Profile.prestige + 1, UIKit.format_int(Profile.prestige_bonus()),
			Data.prestige_badge(Profile.prestige + 1)]
		_prestige_confirm.popup_centered())
	backup.add_child(_prestige_btn)
	_prestige_confirm = ConfirmationDialog.new()
	_prestige_confirm.title = "Prestige"
	_prestige_confirm.ok_button_text = "Prestige"
	_prestige_confirm.confirmed.connect(_do_prestige)
	add_child(_prestige_confirm)
	var export_btn := UIKit.button("EXPORT PROGRESS", &"IconButton")
	export_btn.tooltip_text = "Save your coins, items, upgrades, stats and settings to a file."
	export_btn.pressed.connect(func() -> void:
		_export_dialog.current_file = "timbum-progress-%s.json" % Time.get_date_string_from_system()
		_export_dialog.popup_centered_ratio(0.7))
	backup.add_child(export_btn)
	var import_btn := UIKit.button("IMPORT PROGRESS", &"IconButton")
	import_btn.tooltip_text = "Load progress from a file you exported (replaces what you have now)."
	import_btn.pressed.connect(func() -> void: _import_dialog.popup_centered_ratio(0.7))
	backup.add_child(import_btn)
	_credits_btn = UIKit.button("CREDITS", &"IconButton")
	_credits_btn.tooltip_text = "Who made Timbum."
	_credits_btn.pressed.connect(open_credits)
	backup.add_child(_credits_btn)
	_build_backup_dialogs()

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	col.add_child(_grid)

	var table_card := UIKit.panel()
	col.add_child(table_card)
	var tv := UIKit.vbox(8)
	table_card.add_child(tv)
	tv.add_child(UIKit.label("PER WEAPON", &"SubheaderLabel"))
	_weapon_table = GridContainer.new()
	_weapon_table.columns = WEAPON_COLUMNS.size()
	_weapon_table.add_theme_constant_override("h_separation", 14)
	_weapon_table.add_theme_constant_override("v_separation", 4)
	tv.add_child(_weapon_table)

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
	# Last child, so the overlay covers the page.
	_credits = CreditsPanel.new(page.get_parent())
	_credits.closed.connect(func() -> void: _credits_btn.grab_focus())
	add_child(_credits)


func open_credits() -> void:
	_credits.open()


## Export/import of the whole profile (Profile.export_to / import_from) through the system's
## file dialogs, with a confirmation before an import replaces the current progress.
func _build_backup_dialogs() -> void:
	_export_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Export Timbum progress")
	_export_dialog.file_selected.connect(func(path: String) -> void:
		var err := Profile.export_to(path)
		if err == OK:
			_say("Progress saved to %s" % path.get_file(), UITheme.GOOD)
		else:
			_say("Couldn't save: %s" % error_string(err), UITheme.BAD))
	_import_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Import Timbum progress")
	_import_dialog.file_selected.connect(func(path: String) -> void:
		_import_path = path
		_confirm.dialog_text = "Replace your current progress with %s?\nCoins, items, upgrades, stats and settings will all be replaced." % path.get_file()
		_confirm.popup_centered())
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Import progress"
	_confirm.ok_button_text = "Replace"
	_confirm.confirmed.connect(_do_import)
	add_child(_confirm)


func _file_dialog(file_mode: FileDialog.FileMode, dialog_title: String) -> FileDialog:
	var d := FileDialog.new()
	d.file_mode = file_mode
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.title = dialog_title
	d.filters = PackedStringArray(["*.json ; Timbum progress"])
	d.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	add_child(d)
	return d


func _do_import() -> void:
	var problem := Profile.import_from(_import_path)
	if problem.is_empty():
		Sfx.play(&"ui_buy")
		on_shown()
		_say("Progress restored from %s" % _import_path.get_file(), UITheme.GOOD)
	else:
		Sfx.play(&"ui_error")
		_say(problem, UITheme.BAD)


func _say(text: String, color: Color) -> void:
	_backup_status.text = text
	_backup_status.add_theme_color_override("font_color", color)


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
	_credits.close()
	var s := Profile.stats
	var kills := int(s.kills)
	var deaths := int(s.deaths)
	var matches := int(s.matches)
	var kd := float(kills) / maxf(1.0, float(deaths))
	_level.text = Data.badged_name("LVL %d" % Profile.level, Profile.prestige)
	var need := Profile.xp_for_level(Profile.level)
	_xp_bar.max_value = need
	_xp_bar.value = need if Profile.level >= Data.LEVEL_CAP else Profile.xp
	if Profile.level >= Data.LEVEL_CAP:
		_xp_text.text = "%s  ·  MAX LEVEL  ·  PRESTIGE %d / %d" % [Profile.player_name.to_upper(), Profile.prestige, Data.PRESTIGE_MAX]
	else:
		_xp_text.text = "%s  ·  %s / %s XP TO LEVEL %d" % [Profile.player_name.to_upper(), UIKit.format_int(Profile.xp), UIKit.format_int(need), Profile.level + 1]
	_prestige_btn.disabled = not Profile.can_prestige()
	if Profile.prestige >= Data.PRESTIGE_MAX:
		_prestige_btn.tooltip_text = "Top prestige rank reached."
	elif Profile.level < Data.LEVEL_CAP:
		_prestige_btn.tooltip_text = "Reach level %d to prestige." % Data.LEVEL_CAP
	else:
		_prestige_btn.tooltip_text = "Back to level 1 for prestige rank %d and %s coins." % [Profile.prestige + 1, UIKit.format_int(Profile.prestige_bonus())]
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
	_fill_weapon_table()
	_refresh_dev()


func _do_prestige() -> void:
	var bonus := Profile.do_prestige()
	if bonus < 0:
		Sfx.play(&"ui_error")
		return
	Sfx.play(&"level_up")
	on_shown()
	_say("Prestige %d! +%s coins" % [Profile.prestige, UIKit.format_int(bonus)], UITheme.GOOD)


## One row per weapon (and grenade / Block Bomber) the player has used: kills, accuracy,
## headshot share of kills, damage and mastery tier.
func _fill_weapon_table() -> void:
	for c in _weapon_table.get_children():
		c.queue_free()
	for col: Array in WEAPON_COLUMNS:
		var h := UIKit.label(str(col[0]), &"SmallLabel")
		h.custom_minimum_size.x = int(col[1])
		_weapon_table.add_child(h)
	var any := false
	for id: String in Profile.stat_sources():
		var kills := Profile.weapon_stat(id, "kills")
		var shots := Profile.weapon_stat(id, "shots")
		var damage := Profile.weapon_stat(id, "damage")
		if kills == 0 and shots == 0 and damage == 0:
			continue
		any = true
		var gun := Data.WEAPONS.has(id)
		var name_text: String = str(Data.WEAPONS[id].name) if gun else World.weapon_label(id)
		var acc := "-" if shots == 0 else "%d%%" % roundi(100.0 * Profile.weapon_stat(id, "hits") / shots)
		var hs := "-" if kills == 0 else "%d%%" % roundi(100.0 * Profile.weapon_stat(id, "headshots") / kills)
		var tier := Profile.mastery_tier(id)
		var mastery := "-" if not gun else ("None" if tier == 0 else str(Data.MASTERY_TIERS[tier - 1].name))
		var cells := [name_text, UIKit.format_int(kills), acc, hs, UIKit.format_int(damage), mastery]
		for i in cells.size():
			var l := UIKit.label(str(cells[i]), &"ValueLabel")
			l.add_theme_font_size_override("font_size", 16)
			if i == 5 and tier > 0:
				l.add_theme_color_override("font_color", Data.MASTERY_TIERS[tier - 1].color)
			_weapon_table.add_child(l)
	if not any:
		var empty := UIKit.label("Play a match to fill this table.", &"DimLabel")
		_weapon_table.add_child(empty)


func _tile(caption: String, value: String, color: Color, note := "") -> void:
	var p := UIKit.panel(&"CardPanel")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(180, 100)
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
