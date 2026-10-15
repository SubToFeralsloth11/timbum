class_name Hud
extends CanvasLayer
## In-match interface: crosshair, hitmarkers, health, ammo, clock, killfeed, chat,
## scoreboard, death screen, scope, pause menu and end-of-match results.

const KILLFEED_MAX := 6
const KILLFEED_LIFE := 6.0
const CHAT_LIFE := 10.0
const CHAT_MAX := 8

var world: World

var _root: Control
var _crosshair: Crosshair
var _damage_ring: DamageRing
var _scope: ScopeOverlay
var _vignette: TextureRect
var _health_label: Label
var _health_bar: ProgressBar
var _ammo_label: Label
var _reserve_label: Label
var _weapon_label: Label
var _grenade_label: Label
var _hint_label: Label
var _clock_label: Label
var _goal_label: Label
var _rank_label: Label
var _killfeed: VBoxContainer
var _kill_label: Label
var _announce_label: Label
var _pickup_label: Label
var _chat_log: VBoxContainer
var _chat_input: LineEdit
var _death_panel: Control
var _death_title: Label
var _death_sub: Label
var _death_timer_label: Label
var _scoreboard: PanelContainer
var _score_rows: VBoxContainer
var _results: Control
var _results_rows: VBoxContainer
var _results_title: Label
var _results_rewards: Label
var _results_timer: Label
var _pause: PauseMenu
var _fps_label: Label

var _death_left := 0.0
var _results_left := 0.0
var _vignette_alpha := 0.0
var _kill_label_t := 0.0
var _announce_t := 0.0
var _pickup_t := 0.0
var _scores_dirty := true
var _crosshair_color := Color.WHITE
## Floating damage numbers: [Label, world position, age]
var _damage_numbers: Array = []
const DAMAGE_NUMBER_LIFE := 0.8


func setup(p_world: World) -> void:
	world = p_world


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)

	_vignette = TextureRect.new()
	_vignette.texture = _make_vignette()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate = Color(1, 1, 1, 0)
	_root.add_child(_vignette)

	_scope = ScopeOverlay.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.visible = false
	_root.add_child(_scope)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_crosshair)

	_damage_ring = DamageRing.new()
	_damage_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_damage_ring)

	_build_top()
	_build_bottom()
	_build_center()
	_build_chat()
	_build_death()
	_build_scoreboard()
	_build_results()

	_fps_label = _label("", 16)
	_fps_label.position = Vector2(10, 8)
	_root.add_child(_fps_label)

	if int(Profile.stats.matches) < 3:
		_show_controls_hint()
	_show_match_intro()
	_refresh_crosshair_color()
	Profile.changed.connect(_refresh_crosshair_color)

	_pause = PauseMenu.new()
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_pause.resume_requested.connect(_close_pause)
	add_child(_pause)


func _refresh_crosshair_color() -> void:
	var html := str(Profile.get_setting("crosshair_color"))
	_crosshair_color = Color.html(html) if Color.html_is_valid(html) else Color.WHITE


# ---------------------------------------------------------------- building

func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(alpha := 0.55) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, alpha)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _build_top() -> void:
	var top := _panel()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 10
	_root.add_child(top)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	top.add_child(v)
	_clock_label = _label("8:00", 34)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_clock_label)
	_goal_label = _label("", 15, Color(1, 0.85, 0.4))
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_goal_label)
	_rank_label = _label("", 15, Color(0.75, 0.85, 1.0))
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_rank_label)

	_killfeed = VBoxContainer.new()
	_killfeed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_killfeed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_killfeed.position = Vector2(-16, 14)
	_killfeed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_killfeed)


func _build_bottom() -> void:
	var hp := _panel()
	hp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hp.position = Vector2(18, -18)
	_root.add_child(hp)
	var hv := VBoxContainer.new()
	hp.add_child(hv)
	var row := HBoxContainer.new()
	hv.add_child(row)
	var cross := _label("+", 40, Color(1, 0.35, 0.35))
	row.add_child(cross)
	_health_label = _label("100", 44)
	row.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(240, 12)
	_health_bar.max_value = Data.MAX_HEALTH
	_health_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.95, 0.45)
	fill.set_corner_radius_all(2)
	_health_bar.add_theme_stylebox_override("background", bg)
	_health_bar.add_theme_stylebox_override("fill", fill)
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(_health_bar)

	var ammo := _panel()
	ammo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo.position = Vector2(-18, -18)
	_root.add_child(ammo)
	var av := VBoxContainer.new()
	av.alignment = BoxContainer.ALIGNMENT_END
	ammo.add_child(av)
	_weapon_label = _label("", 18, Color(0.85, 0.9, 1.0))
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	av.add_child(_weapon_label)
	var arow := HBoxContainer.new()
	arow.alignment = BoxContainer.ALIGNMENT_END
	av.add_child(arow)
	_ammo_label = _label("30", 46)
	arow.add_child(_ammo_label)
	_reserve_label = _label("/ 120", 24, Color(0.8, 0.8, 0.8))
	_reserve_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_reserve_label.size_flags_vertical = Control.SIZE_SHRINK_END
	arow.add_child(_reserve_label)
	_grenade_label = _label("", 18, Color(0.55, 0.95, 0.5))
	_grenade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	av.add_child(_grenade_label)

	_hint_label = _label("", 20, Color(1, 0.85, 0.3))
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.position.y += 70
	_root.add_child(_hint_label)


func _build_center() -> void:
	_kill_label = _label("", 22, Color(1, 0.4, 0.35))
	_kill_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_kill_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kill_label.position.y += 110
	_root.add_child(_kill_label)
	_announce_label = _label("", 48, Color(1, 0.82, 0.25))
	_announce_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_announce_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.position.y = 150
	_announce_label.pivot_offset = Vector2(0, 30)
	_root.add_child(_announce_label)
	_pickup_label = _label("", 20, Color(0.6, 1.0, 0.6))
	_pickup_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_pickup_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_label.position.y -= 130
	_root.add_child(_pickup_label)


func _build_chat() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.position = Vector2(18, -140)
	box.custom_minimum_size = Vector2(440, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_chat_log = VBoxContainer.new()
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_chat_log)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Say something... (Enter to send, Esc to cancel)"
	_chat_input.max_length = World.MAX_CHAT_LENGTH
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_on_chat_submitted)
	box.add_child(_chat_input)


func _build_death() -> void:
	_death_panel = Control.new()
	_death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_panel.visible = false
	_root.add_child(_death_panel)
	var tint := ColorRect.new()
	tint.color = Color(0.35, 0.0, 0.0, 0.25)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_panel.add_child(tint)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.position.y -= 60
	_death_panel.add_child(v)
	_death_title = _label("ELIMINATED", 54, Color(1, 0.3, 0.3))
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_title)
	_death_sub = _label("", 24)
	_death_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_sub)
	_death_timer_label = _label("", 20, Color(0.85, 0.85, 0.85))
	_death_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_timer_label)


func _build_scoreboard() -> void:
	_scoreboard = _panel(0.82)
	_scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH
	_scoreboard.custom_minimum_size = Vector2(620, 0)
	_scoreboard.visible = false
	_root.add_child(_scoreboard)
	var v := VBoxContainer.new()
	_scoreboard.add_child(v)
	var mut: Dictionary = Data.MUTATORS[str(Net.config.mutator)]
	var title := _label("%s  -  %s  -  %s" % [Data.MAPS[Net.current_map].name.to_upper(), str(mut.name).to_upper(),
		str(Net.config.time_of_day).to_upper()], 24, Color(1, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(_score_row(["#", "PLAYER", "KILLS", "DEATHS", "HS"], Color(0.7, 0.75, 0.85), false))
	_score_rows = VBoxContainer.new()
	v.add_child(_score_rows)


func _score_row(cells: Array, color: Color, highlight: bool) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.8, 0.25, 0.22) if highlight else Color(1, 1, 1, 0.04)
	sb.set_content_margin_all(4)
	sb.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	panel.add_child(h)
	var widths := [40, 300, 80, 80, 60]
	for i in cells.size():
		var l := _label(str(cells[i]), 18, color)
		l.custom_minimum_size.x = widths[i]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 1 else HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		h.add_child(l)
	return panel


func _build_results() -> void:
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.visible = false
	_root.add_child(_results)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.add_child(dim)
	var panel := _panel(0.9)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(660, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_results.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_results_title = _label("", 46, Color(1, 0.82, 0.25))
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_results_title)
	v.add_child(_score_row(["#", "PLAYER", "KILLS", "DEATHS", "HS"], Color(0.7, 0.75, 0.85), false))
	_results_rows = VBoxContainer.new()
	v.add_child(_results_rows)
	_results_rewards = _label("", 22, Color(0.6, 1.0, 0.6))
	_results_rewards.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_results_rewards)
	_results_timer = _label("", 18, Color(0.8, 0.8, 0.85))
	_results_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_results_timer)
	var leave := Button.new()
	leave.text = "Leave to Menu"
	leave.custom_minimum_size = Vector2(220, 44)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(func() -> void:
		Sfx.play(&"ui_click")
		Net.leave())
	v.add_child(leave)


func _make_vignette() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.8, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.8, 0.0, 0.0, 0.85))
	g.set_offset(0, 0.55)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 256
	tex.height = 256
	return tex


# ---------------------------------------------------------------- frame update

func _process(delta: float) -> void:
	var p := world.local_player
	_update_damage_numbers(delta)
	var scoreboard_held := Input.is_action_pressed("scoreboard") and not _chat_input.visible and not _pause.visible
	_scoreboard.visible = scoreboard_held and not _results.visible
	if _scoreboard.visible and _scores_dirty:
		_fill_rows(_score_rows, _sorted_rows())
		_scores_dirty = false
	_fps_label.visible = Profile.get_setting("show_fps")
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()

	var t := int(ceil(world.time_left))
	_clock_label.text = "%d:%02d" % [t / 60, t % 60]
	# self_modulate tints without the re-layout a theme override triggers.
	_clock_label.self_modulate = Color(1, 0.4, 0.35) if t <= 30 else Color.WHITE

	_kill_label_t -= delta
	_kill_label.modulate.a = clampf(_kill_label_t, 0.0, 1.0)
	_announce_t -= delta
	_announce_label.modulate.a = clampf(_announce_t, 0.0, 1.0)
	_pickup_t -= delta
	_pickup_label.modulate.a = clampf(_pickup_t, 0.0, 1.0)
	_age_list(_killfeed, delta, KILLFEED_LIFE)
	if not _chat_input.visible:
		_age_list(_chat_log, delta, CHAT_LIFE)

	if _death_panel.visible:
		_death_left = maxf(0.0, _death_left - delta)
		_death_timer_label.text = "Respawning in %d" % int(ceil(_death_left)) if _death_left > 0.0 else "Respawning..."
	if _results.visible:
		_results_left = maxf(0.0, _results_left - delta)
		_results_timer.text = "Next match in %d" % int(ceil(_results_left))

	if p == null:
		_crosshair.visible = false
		return
	var hp_frac := p.health / Data.MAX_HEALTH
	_health_label.text = str(int(ceil(p.health)))
	_health_bar.value = p.health
	(_health_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.95, 0.3, 0.25).lerp(Color(0.35, 0.95, 0.45), hp_frac)
	var low := 0.0
	if p.alive and hp_frac < 0.35:
		low = (0.35 - hp_frac) * 1.6 * (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.008))
	_vignette_alpha = move_toward(_vignette_alpha, 0.0, delta * 1.8)
	_vignette.modulate.a = clampf(maxf(_vignette_alpha, low), 0.0, 1.0)

	var wid := p.weapon_id()
	var w := p.weapon_data()
	_weapon_label.text = str(w.name).to_upper()
	if int(w.mag) > 0:
		var a: Vector2i = p.ammo[wid]
		_ammo_label.text = str(a.x)
		_reserve_label.text = "/ %d" % a.y
		_ammo_label.self_modulate = Color(1, 0.35, 0.3) if a.x <= int(w.mag) / 4 else Color.WHITE
		if p.reloading:
			_hint_label.text = "RELOADING"
		elif a.x == 0 and a.y == 0:
			_hint_label.text = "NO AMMO - FIND AN AMMO CRATE"
		elif a.x <= int(w.mag) / 4 and a.y > 0:
			_hint_label.text = "[R] RELOAD"
		else:
			_hint_label.text = ""
	else:
		_ammo_label.text = "-"
		_reserve_label.text = ""
		_hint_label.text = ""
	_hint_label.visible = p.alive
	_grenade_label.text = "GRENADES  " + "■ ".repeat(p.grenades) + "□ ".repeat(maxi(0, int(Data.GRENADE.per_life) - p.grenades))

	var scoped: bool = w.get("scope", false) and p.aim_blend > 0.85 and p.alive
	_scope.visible = scoped
	_crosshair.visible = p.alive and not _results.visible and ((not scoped and p.aim_blend < 0.6) or wid == "knife")
	_crosshair.spread = p.current_spread()
	_crosshair.fov = p.camera.fov if p.camera != null else 85.0
	_crosshair.color = _crosshair_color
	_crosshair.queue_redraw()
	_damage_ring.update_view(p)


func _age_list(list: Container, delta: float, life: float) -> void:
	for child in list.get_children():
		var age: float = child.get_meta("age", 0.0) + delta
		child.set_meta("age", age)
		child.modulate.a = clampf((life - age) / 0.6, 0.0, 1.0)
		if age > life:
			child.queue_free()


# ---------------------------------------------------------------- world events

func is_blocking() -> bool:
	return _pause.visible or _chat_input.visible or _results.visible


func refresh_scores() -> void:
	_scores_dirty = true
	var rows := _sorted_rows()
	var me := world.my_id()
	var my_rank := 0
	for i in rows.size():
		if int(rows[i].id) == me:
			my_rank = i + 1
	var limit := int(Net.config.kill_limit)
	if rows.is_empty():
		_goal_label.text = "First to %d kills" % limit
	else:
		_goal_label.text = "Leader: %s  %d / %d" % [rows[0].name, rows[0].kills, limit]
	if my_rank > 0:
		_rank_label.text = "You: %d kills  -  #%d of %d" % [rows[my_rank - 1].kills, my_rank, rows.size()]


func _sorted_rows() -> Array:
	var rows: Array = []
	for eid: int in world.scores:
		var s: Dictionary = world.scores[eid]
		rows.append({"id": eid, "name": s.name, "level": s.get("level", 1), "kills": s.kills, "deaths": s.deaths, "headshots": s.headshots, "bot": s.bot})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.kills > b.kills if a.kills != b.kills else a.deaths < b.deaths)
	return rows


func _fill_rows(container: VBoxContainer, rows: Array) -> void:
	for c in container.get_children():
		c.queue_free()
	var me := world.my_id()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var player_name := "%s  Lv %d%s" % [r.name, int(r.get("level", 1)), "  [BOT]" if r.bot else ""]
		var mine := int(r.id) == me
		container.add_child(_score_row([i + 1, player_name, r.kills, r.deaths, r.headshots],
			Color(1, 0.95, 0.8) if mine else Color.WHITE, mine))


func show_damage(from_pos: Vector3) -> void:
	_vignette_alpha = minf(_vignette_alpha + 0.45, 0.8)
	_damage_ring.add_hit(from_pos)


func damage_number(pos: Vector3, amount: float, head: bool) -> void:
	if amount < 0.5:
		return
	var l := _label(str(roundi(amount)), 26 if head else 21, Color(1, 0.8, 0.2) if head else Color.WHITE)
	_root.add_child(l)
	_damage_numbers.append([l, pos + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)), 0.0])
	if _damage_numbers.size() > 12:
		var old: Array = _damage_numbers.pop_front()
		(old[0] as Label).queue_free()


func _update_damage_numbers(delta: float) -> void:
	if _damage_numbers.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	for i in range(_damage_numbers.size() - 1, -1, -1):
		var entry: Array = _damage_numbers[i]
		var l: Label = entry[0]
		entry[2] += delta
		var pos: Vector3 = entry[1] + Vector3.UP * entry[2] * 0.9
		if entry[2] > DAMAGE_NUMBER_LIFE or cam == null:
			l.queue_free()
			_damage_numbers.remove_at(i)
			continue
		l.visible = not cam.is_position_behind(pos)
		l.position = cam.unproject_position(pos) - l.size * 0.5
		l.modulate.a = clampf((DAMAGE_NUMBER_LIFE - entry[2]) / 0.3, 0.0, 1.0)


## Big centred card announcing the map, mutator and time of day; fades after a few seconds.
func _show_match_intro() -> void:
	var mut: Dictionary = Data.MUTATORS[str(Net.config.mutator)]
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.position.y = 120
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	var map_label := _label(Data.MAPS[Net.current_map].name.to_upper(), 46, Color(1, 0.85, 0.35))
	map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(map_label)
	var sub := "%s  ·  %s" % [str(mut.name).to_upper(), str(Net.config.time_of_day).to_upper()]
	var sub_label := _label(sub, 24, Color(0.6, 0.9, 1.0) if Net.config.mutator != "none" else Color.WHITE)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub_label)
	var desc := _label(str(mut.desc), 18, Color(0.85, 0.85, 0.9))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(desc)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(box, "modulate:a", 0.0, 0.8)
	tw.tween_callback(box.queue_free)


func _show_controls_hint() -> void:
	var panel := _panel(0.6)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position.x = 18
	_root.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(_label("CONTROLS", 18, Color(1, 0.85, 0.4)))
	for line in ["WASD  move", "Shift  sprint   Ctrl  crouch", "Right mouse  aim", "R  reload   G  grenade",
			"V  quick melee   1/2/3  weapons", "Tab  scores   T  chat   Esc  menu"]:
		v.add_child(_label(line, 15))
	var tw := create_tween()
	tw.tween_interval(10.0)
	tw.tween_property(panel, "modulate:a", 0.0, 1.0)
	tw.tween_callback(panel.queue_free)


func show_hitmarker(head: bool, killed: bool) -> void:
	_crosshair.hit(head, killed)


func add_killfeed(killer: String, weapon: String, victim: String, head: bool, suicide: bool) -> void:
	var panel := _panel(0.5)
	var h := HBoxContainer.new()
	panel.add_child(h)
	var me: String = Net.players.get(world.my_id(), {}).get("name", "")
	if suicide:
		h.add_child(_label(victim, 18, Color(1, 0.9, 0.6) if victim == me else Color.WHITE))
		h.add_child(_label(" [%s] " % weapon, 16, Color(0.7, 0.7, 0.75)))
	else:
		h.add_child(_label(killer, 18, Color(1, 0.9, 0.4) if killer == me else Color(1, 0.55, 0.5)))
		h.add_child(_label(" [%s%s] " % [weapon, " HS" if head else ""], 16, Color(0.75, 0.75, 0.8)))
		h.add_child(_label(victim, 18, Color(1, 0.9, 0.4) if victim == me else Color(0.6, 0.8, 1.0)))
	panel.set_meta("age", 0.0)
	_killfeed.add_child(panel)
	while _killfeed.get_child_count() > KILLFEED_MAX:
		var old := _killfeed.get_child(0)
		_killfeed.remove_child(old)
		old.queue_free()


func show_kill(victim: String, head: bool) -> void:
	_kill_label.text = ("HEADSHOT  " if head else "") + "ELIMINATED %s" % victim.to_upper()
	_kill_label_t = 2.0


func announce(text: String) -> void:
	_announce_label.text = text
	_announce_t = 2.4
	_announce_label.scale = Vector2(1.4, 1.4)
	create_tween().tween_property(_announce_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func pickup_message(kind: String) -> void:
	var color := Color(0.6, 1.0, 0.6)
	match kind:
		"health": _pickup_label.text = "+%d HEALTH" % int(World.HEALTH_PICKUP)
		"ammo": _pickup_label.text = "+AMMO"
		"grenade": _pickup_label.text = "+1 GRENADE"
		"no_grenades":
			_pickup_label.text = "NO GRENADES"
			color = Color(1.0, 0.45, 0.4)
	_pickup_label.add_theme_color_override("font_color", color)
	_pickup_t = 1.6


func show_death(killer: String, weapon: String, respawn_time: float) -> void:
	_death_panel.visible = true
	_death_left = respawn_time
	if killer.is_empty():
		_death_sub.text = "You took yourself out (%s)" % weapon
	else:
		_death_sub.text = "Killed by %s  with %s" % [killer, weapon]


func hide_death() -> void:
	_death_panel.visible = false


func add_chat(sender: String, text: String) -> void:
	var l := _label("", 17)
	if sender.is_empty():
		l.text = text
		l.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	else:
		l.text = "%s: %s" % [sender, text]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 440
	l.set_meta("age", 0.0)
	_chat_log.add_child(l)
	while _chat_log.get_child_count() > CHAT_MAX:
		var old := _chat_log.get_child(0)
		_chat_log.remove_child(old)
		old.queue_free()


func show_results(rows: Array, placement: int, rewards: Dictionary, wait: float) -> void:
	_close_pause()
	_close_chat()
	_death_panel.visible = false
	_results.visible = true
	_results_left = wait
	if placement == 1:
		_results_title.text = "VICTORY!"
	elif placement > 0:
		_results_title.text = "YOU PLACED #%d" % placement
	else:
		_results_title.text = "MATCH OVER"
	_fill_rows(_results_rows, rows)
	if rewards.is_empty():
		_results_rewards.text = ""
	else:
		var txt := "+%d coins    +%d XP" % [rewards.coins, rewards.xp]
		if int(rewards.levels_gained) > 0:
			txt += "    LEVEL UP! (Level %d)" % Profile.level
			Sfx.play(&"level_up")
		_results_rewards.text = txt
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- input

## Esc is read in _input so a focused chat box or menu can't swallow it.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if _chat_input.visible:
		_close_chat()
	elif _pause.visible:
		_close_pause()
	elif not _results.visible:
		_pause.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat") and not is_blocking():
		get_viewport().set_input_as_handled()
		_chat_input.visible = true
		_chat_input.text = ""
		_chat_input.grab_focus.call_deferred()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		for c in _chat_log.get_children():
			c.set_meta("age", 0.0)
		return
	if event is InputEventMouseButton and event.pressed and not is_blocking() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _on_chat_submitted(text: String) -> void:
	if not text.strip_edges().is_empty():
		world.send_chat(text)
	_close_chat()


func _close_chat() -> void:
	if not _chat_input.visible:
		return
	_chat_input.visible = false
	_chat_input.release_focus()
	if not is_blocking():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _close_pause() -> void:
	_pause.visible = false
	if not is_blocking():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
