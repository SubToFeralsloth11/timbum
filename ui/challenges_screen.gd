class_name ChallengesScreen
extends MenuScreen
## Daily and weekly challenges (Profile.challenges): one card each with its progress bar, reward
## and CLAIM button, and the time left until each set resets.

var _sections := {}
var _resets := {}
var _status: Label
var _tick: Timer


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("CHALLENGES", "Play matches to fill the bars, then claim coins and XP. Offline matches count."))
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(center)
	var col := UIKit.vbox(12)
	col.custom_minimum_size.x = 820
	center.add_child(col)
	for kind: String in Challenges.KINDS:
		var head := UIKit.hbox(12)
		col.add_child(head)
		head.add_child(UIKit.label(kind.to_upper(), &"SubheaderLabel"))
		head.add_child(UIKit.spacer())
		var reset := UIKit.label("", &"SmallLabel")
		reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(reset)
		_resets[kind] = reset
		var list := UIKit.vbox(8)
		col.add_child(list)
		_sections[kind] = list
	_status = UIKit.label("", &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_status)
	_tick = Timer.new()
	_tick.wait_time = 1.0
	_tick.timeout.connect(_on_tick)
	add_child(_tick)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_tick.start()
		else:
			_tick.stop())


func on_shown() -> void:
	_status.text = ""
	_refresh_sets()


## Rolls over finished periods (paying completed, unclaimed challenges) and redraws.
func _refresh_sets() -> void:
	var paid := Profile.refresh_challenges()
	if int(paid.coins) > 0:
		_say("Last period's unclaimed challenges paid: +%s coins, +%s XP" % [UIKit.format_int(int(paid.coins)), UIKit.format_int(int(paid.xp))], UITheme.GOOD)
	_rebuild()
	_on_tick()


func _rebuild() -> void:
	for kind: String in Challenges.KINDS:
		var list: VBoxContainer = _sections[kind]
		for c in list.get_children():
			c.queue_free()
		var entries := Profile.challenge_list(kind)
		for i in entries.size():
			list.add_child(_card(kind, i, entries[i]))


func _card(kind: String, index: int, ch: Dictionary) -> Control:
	var card := UIKit.panel(&"CardPanel")
	var h := UIKit.hbox(16)
	card.add_child(h)
	var v := UIKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var title := UIKit.label(Challenges.text(ch), &"ValueLabel")
	title.add_theme_font_size_override("font_size", 20)
	v.add_child(title)
	var bar_row := UIKit.hbox(10)
	v.add_child(bar_row)
	var bar := ProgressBar.new()
	bar.theme_type_variation = &"XPBar"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = int(ch.target)
	bar.value = int(ch.progress)
	bar_row.add_child(bar)
	var count := UIKit.label("%d / %d" % [int(ch.progress), int(ch.target)], &"SmallLabel")
	count.custom_minimum_size.x = 70
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_row.add_child(count)
	var reward := Challenges.reward(kind)
	var reward_row := UIKit.hbox(8)
	reward_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reward_row.custom_minimum_size.x = 170
	reward_row.alignment = BoxContainer.ALIGNMENT_END
	reward_row.add_child(UIKit.coin_amount(int(reward.coins), 18))
	var xp := UIKit.label("+%s XP" % UIKit.format_int(int(reward.xp)), &"SmallLabel")
	xp.add_theme_color_override("font_color", UITheme.GOOD)
	reward_row.add_child(xp)
	h.add_child(reward_row)
	var done := Challenges.is_complete(ch)
	var claim := UIKit.button("CLAIMED" if ch.claimed else "CLAIM", &"GoldButton" if done and not ch.claimed else &"", false)
	claim.custom_minimum_size = Vector2(130, 46)
	claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claim.disabled = not done or ch.claimed
	claim.tooltip_text = "" if done else "Finish the challenge to claim it."
	claim.pressed.connect(func() -> void: _claim(kind, index, claim))
	h.add_child(claim)
	return card


func _claim(kind: String, index: int, from: Button) -> void:
	var got := Profile.claim_challenge(kind, index)
	if got.is_empty():
		Sfx.play(&"ui_error")
		return
	Sfx.play(&"level_up" if int(got.levels) > 0 else &"coins")
	var parts := ["+%s coins" % UIKit.format_int(int(got.coins))]
	if int(got.xp) > 0:
		parts.append("+%s XP" % UIKit.format_int(int(got.xp)))
	if int(got.levels) > 0:
		parts.append("level %d!" % Profile.level)
	_say("Claimed: " + ", ".join(parts), UITheme.ACCENT)
	var at := from.get_global_rect().get_center()
	_rebuild()
	var menu := get_tree().current_scene
	if menu != null and menu.has_method("_float_text"):
		menu.call("_float_text", "+%d" % int(got.coins), at)


func _say(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


## Countdown to each reset; at local midnight the sets roll over while the screen is open.
func _on_tick() -> void:
	var day := Challenges.today()
	for kind: String in Challenges.KINDS:
		var cur: Dictionary = Profile.challenges.get(kind, {})
		if cur.is_empty() or int(cur.period) < Challenges.period_of(kind, day):
			_refresh_sets()
			return
	var t := Time.get_time_dict_from_system()
	var to_midnight := 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))
	(_resets.daily as Label).text = "NEW IN %s" % _duration(to_midnight)
	var days_left := Challenges.week_start(day) + 6 - day
	(_resets.weekly as Label).text = "NEW IN %s" % _duration(days_left * 86400 + to_midnight)


static func _duration(s: int) -> String:
	if s >= 86400:
		return "%dD %dH" % [s / 86400, (s / 3600) % 24]
	return "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
