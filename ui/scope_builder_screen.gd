class_name ScopeBuilderScreen
extends MenuScreen
## Scope builder (docs/ARCHITECTURE.md "Custom scopes"): builds the custom scope of one gun
## (Profile.has_custom_scope) on a live 3D preview of the gun.
## Left: the part catalog (CustomScopes.PARTS by group); every part added costs
## CustomScopes.PART_PRICE, charged and saved at once (Profile.save_custom_scope). Middle: the
## gun with the scope (drag or the arrow buttons to turn it), the reticle as seen through the
## lens, the part count and zoom, RESET (back to the starter parts) and CLEAR ALL. Right: PARTS
## (the fitted parts; the selected one's colour, finish, size, position and roll, DUPLICATE for
## the part price, REMOVE) and OPTICS (reticle, its colour, glow and size, the PIXEL PAINT grid,
## lens tint, view shape and size, power, height and forward position). Removing a part, RESET and
## CLEAR ALL refund nothing; every edit other than adding a part is free and saved SAVE_DELAY
## seconds after the last change (and on leaving). The header's switch turns the scope on or off.

const SAVE_DELAY := 0.6
## Two presses this close together confirm RESET / CLEAR ALL.
const CONFIRM_TIME := 3.0

## Gun being built, and the screen BACK returns to ("shop" or "locker").
var wid := "rifle"
var return_to := "shop"

var _design := {}
var _sel := -1
var _group := "BODY"
var _model_dirty := false
var _save_dirty := false
var _save_left := 0.0

var _title: Label
var _coins: Label
var _switch: CheckButton
var _preview: ModelPreview
var _reticle: _ReticleView
var _info: Label
var _group_buttons := {}
var _catalog: VBoxContainer
var _tab_buttons := {}
var _parts_page: VBoxContainer
var _optics_page: VBoxContainer
var _parts_list: VBoxContainer
var _editor: VBoxContainer
## Refresh callables of the OPTICS widgets (they read _design when called).
var _optics_refresh: Array[Callable] = []
var _paint_cells: Array[Button] = []
var _confirm_at := {}
## BUY PARTS: pays for the parts added since the last save (try them first, pay once).
var _pay: Button


## The reticle as seen through the lens: a sky-and-ground disc, the lens tint, the reticle.
class _ReticleView extends Control:
	var design := {}

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		draw_circle(c, r, Color("9cc3e6"))
		draw_rect(Rect2(c.x - r * 0.95, c.y + r * 0.2, r * 1.9, r * 0.7), Color("5f7d45"))
		if design.is_empty():
			return
		var tint: Color = design.tint
		draw_circle(c, r, Color(tint.r, tint.g, tint.b, tint.a))
		CustomScopes.draw_reticle(self, c, r, design)
		draw_arc(c, r, 0.0, TAU, 64, Color(0.05, 0.05, 0.07), 4.0, true)


func _ready() -> void:
	var page := make_page()
	var top := UIKit.hbox(14)
	page.add_child(top)
	var header := make_header("SCOPE BUILDER", "")
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(header)
	_title = header.get_child(1).get_child(0) as Label
	var sub := UIKit.label("Try any parts for free, then BUY PARTS to keep them (%d coins each). Unbought parts are dropped when you leave." \
		% CustomScopes.PART_PRICE, &"DimLabel")
	header.get_child(1).add_child(sub)
	var coins := UIKit.coin_amount(Profile.coins, 22)
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coins = coins.get_node("Amount")
	top.add_child(coins)
	_switch = CheckButton.new()
	_switch.text = "SCOPE ON"
	_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_switch.tooltip_text = "Off: the gun uses its own sights and nobody sees this scope. The scope and its design stay; switching back on is free."
	UIKit.wire(_switch)
	_switch.toggled.connect(func(on: bool) -> void:
		Profile.set_custom_scope_on(wid, on)
		_switch.text = "SCOPE ON" if on else "SCOPE OFF"
		_refresh_info())
	top.add_child(_switch)

	var body := UIKit.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	body.add_child(_build_catalog())
	body.add_child(_build_stage())
	body.add_child(_build_editor_panel())
	Profile.changed.connect(_on_profile_changed)


func _build_catalog() -> Control:
	var panel := UIKit.panel()
	panel.custom_minimum_size.x = 290
	var v := UIKit.vbox(8)
	panel.add_child(v)
	v.add_child(UIKit.label("ADD A PART · %d EACH" % CustomScopes.PART_PRICE, &"SubheaderLabel"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	v.add_child(flow)
	var group := ButtonGroup.new()
	for g: Array in CustomScopes.GROUPS:
		var name_: String = g[0]
		var b := UIKit.button(name_, &"ChipButton")
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func() -> void: _show_group(name_))
		flow.add_child(b)
		_group_buttons[name_] = b
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_catalog = UIKit.vbox(4)
	_catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_catalog)
	return panel


func _build_stage() -> Control:
	var v := UIKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stage := UIKit.panel(&"InsetPanel")
	stage.add_theme_stylebox_override("panel", UITheme.spotlight_box())
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(stage)
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_PASS
	stage.add_child(layer)
	_preview = ModelPreview.new()
	_preview.stage.spin_speed = 0.0
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_preview)
	var hint := UIKit.label("DRAG TO ROTATE", &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -28
	hint.offset_bottom = -8
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint)

	var row := UIKit.hbox(12)
	v.add_child(row)
	_reticle = _ReticleView.new()
	_reticle.custom_minimum_size = Vector2(150, 150)
	row.add_child(_reticle)
	var side := UIKit.vbox(8)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(side)
	_info = UIKit.label("", &"SmallLabel")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_info)
	_pay = UIKit.button("", &"GoldButton", false)
	_pay.custom_minimum_size.y = 44
	_pay.pressed.connect(_buy_parts)
	side.add_child(_pay)
	var turn := UIKit.hbox(6)
	side.add_child(turn)
	for step: float in [-0.5, 0.5]:
		var b := UIKit.button("◀ TURN" if step < 0.0 else "TURN ▶", &"IconButton")
		b.pressed.connect(func() -> void: _preview.stage.nudge(step))
		turn.add_child(b)
	var actions := UIKit.hbox(6)
	side.add_child(actions)
	var reset := UIKit.button("RESET")
	var starter_names := PackedStringArray()
	for id in CustomScopes.STARTER:
		starter_names.append(str(CustomScopes.part_info(CustomScopes.index_of(id)).name))
	reset.tooltip_text = "Back to the starter scope (%s). Nothing is refunded." % ", ".join(starter_names)
	reset.pressed.connect(func() -> void: _confirm(reset, "RESET", _reset_design))
	actions.add_child(reset)
	var clear := UIKit.button("CLEAR ALL", &"DangerButton")
	clear.tooltip_text = "Remove every part (the optics stay). Nothing is refunded; without parts the gun uses its own sights."
	clear.pressed.connect(func() -> void: _confirm(clear, "CLEAR ALL", _clear_parts))
	actions.add_child(clear)
	return v


func _build_editor_panel() -> Control:
	var panel := UIKit.panel()
	panel.custom_minimum_size.x = 390
	var v := UIKit.vbox(8)
	panel.add_child(v)
	var tabs := UIKit.hbox(6)
	v.add_child(tabs)
	var group := ButtonGroup.new()
	for t: String in ["PARTS", "OPTICS"]:
		var b := UIKit.button(t, &"TabButton")
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func() -> void: _show_tab(t))
		tabs.add_child(b)
		_tab_buttons[t] = b
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var pages := UIKit.vbox(0)
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	_parts_page = UIKit.vbox(8)
	pages.add_child(_parts_page)
	_parts_page.add_child(UIKit.label("FITTED PARTS", &"SubheaderLabel"))
	_parts_list = UIKit.vbox(3)
	_parts_page.add_child(_parts_list)
	_parts_page.add_child(HSeparator.new())
	_editor = UIKit.vbox(6)
	_parts_page.add_child(_editor)
	_optics_page = UIKit.vbox(8)
	pages.add_child(_optics_page)
	_build_optics()
	_show_tab("PARTS")
	return panel


func _build_optics() -> void:
	var o := _optics_page
	o.add_child(UIKit.label("RETICLE", &"SubheaderLabel"))
	_optics_refresh.append(_chips(o, CustomScopes.RETICLES,
		func() -> int: return int(_design.get("reticle", 0)),
		func(i: int) -> void: _design.reticle = i))
	_optics_refresh.append_array(_color_editor(o, "COLOUR",
		func() -> Color: return _design.get("ret_color", Color.RED),
		func(c: Color) -> void: _design.ret_color = c))
	_optics_refresh.append(_slider(o, "GLOW", 0.0, 1.0, 0.05, _pct,
		func() -> float: return float(_design.get("glow", 0.5)),
		func(x: float) -> void: _design.glow = x))
	_optics_refresh.append(_slider(o, "SIZE", CustomScopes.RETICLE_SCALE.x, CustomScopes.RETICLE_SCALE.y, 0.05, _times,
		func() -> float: return float(_design.get("ret_scale", 1.0)),
		func(x: float) -> void: _design.ret_scale = x))
	o.add_child(UIKit.label("PIXEL PAINT (the %s reticle)" % CustomScopes.RETICLES[CustomScopes.PIXEL_RETICLE].to_upper(), &"SmallLabel"))
	var grid := GridContainer.new()
	grid.columns = CustomScopes.GRID
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	o.add_child(grid)
	_paint_cells.clear()
	for i in CustomScopes.GRID * CustomScopes.GRID:
		var cell := _cell_button()
		cell.toggled.connect(func(on: bool) -> void:
			var px: PackedByteArray = _design.get("pixels", PackedByteArray())
			if i < px.size():
				px[i] = 1 if on else 0
				_design.pixels = px
				_touch())
		grid.add_child(cell)
		_paint_cells.append(cell)
	var paint_row := UIKit.hbox(6)
	o.add_child(paint_row)
	for fill: bool in [false, true]:
		var b := UIKit.button("FILL" if fill else "CLEAR PAINT", &"IconButton")
		b.pressed.connect(func() -> void:
			var px := PackedByteArray()
			px.resize(CustomScopes.GRID * CustomScopes.GRID)
			px.fill(1 if fill else 0)
			_design.pixels = px
			_refresh_paint()
			_touch())
		paint_row.add_child(b)
	o.add_child(HSeparator.new())
	o.add_child(UIKit.label("LENS", &"SubheaderLabel"))
	_optics_refresh.append_array(_color_editor(o, "TINT",
		func() -> Color: return _design.get("tint", Color.WHITE),
		func(c: Color) -> void:
			var t: Color = _design.get("tint", Color.WHITE)
			_design.tint = Color(c.r, c.g, c.b, t.a)))
	_optics_refresh.append(_slider(o, "TINT STRENGTH", 0.0, CustomScopes.TINT_MAX, 0.01, _pct,
		func() -> float: return (_design.get("tint", Color.WHITE) as Color).a,
		func(x: float) -> void:
			var t: Color = _design.get("tint", Color.WHITE)
			_design.tint = Color(t.r, t.g, t.b, x)))
	o.add_child(UIKit.label("VIEW SHAPE (a shaped body sets its own: square, octagon, hex, the Prism Scope's triangle)", &"SmallLabel"))
	_optics_refresh.append(_chips(o, CustomScopes.VIEWS,
		func() -> int: return int(_design.get("view", 0)),
		func(i: int) -> void: _design.view = i))
	_optics_refresh.append(_slider(o, "VIEW SIZE", CustomScopes.VIEW_SIZE.x, CustomScopes.VIEW_SIZE.y, 0.01, _pct,
		func() -> float: return float(_design.get("view_size", 0.44)),
		func(x: float) -> void: _design.view_size = x))
	var power_text := func(x: float) -> String:
		var r := CustomScopes.power_range(wid)
		return "%.2fx" % clampf(x, r.x, r.y)
	_optics_refresh.append(_slider(o, "POWER", CustomScopes.POWER_LIMITS.x, CustomScopes.POWER_LIMITS.y, 0.05, power_text,
		func() -> float: return float(_design.get("power", 1.0)),
		func(x: float) -> void: _design.power = x))
	var power_note := UIKit.label("", &"DimLabel")
	power_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	o.add_child(power_note)
	_optics_refresh.append(func() -> void:
		var r := CustomScopes.power_range(wid)
		power_note.text = "Power multiplies the zoom of the gun's own sights. This gun allows %.1fx to %.1fx%s." % [r.x, r.y,
			" (it has its own scope, so a custom one can only zoom out)" if r.y <= 1.0 else ""])
	o.add_child(HSeparator.new())
	o.add_child(UIKit.label("PLACEMENT", &"SubheaderLabel"))
	_optics_refresh.append(_slider(o, "HEIGHT", CustomScopes.RISE.x, CustomScopes.RISE.y, 0.001, _cm,
		func() -> float: return float(_design.get("rise", CustomScopes.DEFAULT_RISE)),
		func(x: float) -> void: _design.rise = x))
	_optics_refresh.append(_slider(o, "FORWARD", -CustomScopes.SHIFT_LIMIT, CustomScopes.SHIFT_LIMIT, 0.002, _cm,
		func() -> float: return -float(_design.get("shift", 0.0)),
		func(x: float) -> void: _design.shift = -x))


# ------------------------------------------------------------------ open / refresh

## Shows gun `p_wid`'s design; BACK returns to `from`.
func open(p_wid: String, from: String) -> void:
	flush()
	wid = p_wid
	return_to = from
	_design = Profile.custom_scope_design(wid)
	if _design.is_empty():
		_design = CustomScopes.starter()
	_sel = 0 if not (_design.parts as Array).is_empty() else -1


func on_shown() -> void:
	_title.text = "SCOPE BUILDER · %s" % str(Data.WEAPONS[wid].name).to_upper()
	_coins.text = UIKit.format_int(Profile.coins)
	_switch.set_pressed_no_signal(Profile.is_custom_scope_on(wid))
	_switch.text = "SCOPE ON" if _switch.button_pressed else "SCOPE OFF"
	_show_group(_group)
	_refresh_parts()
	for f in _optics_refresh:
		f.call()
	_refresh_paint()
	_rebuild_model()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		flush()
	elif what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()


func _process(delta: float) -> void:
	if _model_dirty:
		_model_dirty = false
		_rebuild_model()
	if _save_dirty:
		_save_left -= delta
		if _save_left <= 0.0:
			flush()


## Marks the design edited (free changes): the preview rebuilds next frame, the save follows.
func _touch() -> void:
	_model_dirty = true
	_save_dirty = true
	_save_left = SAVE_DELAY
	_reticle.design = _design
	_reticle.queue_redraw()
	_refresh_info()


## Saves pending free edits (MainMenu calls it on BACK, before the next screen reads the profile).
## While there are unbought parts nothing saves; leaving then drops them (open() reloads).
func flush() -> void:
	if not _save_dirty or _unpaid() > 0:
		return
	_save_dirty = false
	if Profile.has_custom_scope(wid):
		Profile.save_custom_scope(wid, _design)


## Parts in the design beyond the saved scope's: what BUY PARTS charges for.
func _unpaid() -> int:
	return maxi(0, (_design.get("parts", []) as Array).size() - Profile.custom_scope_parts(wid))


func _buy_parts() -> void:
	var n := _unpaid()
	if n == 0 or not Profile.save_custom_scope(wid, _design, n):
		Sfx.play(&"ui_error")
		return
	Sfx.play(&"ui_buy")
	_save_dirty = false
	_design = Profile.custom_scope_design(wid)
	_refresh_info()


func _on_profile_changed() -> void:
	if not is_inside_tree():
		return
	_coins.text = UIKit.format_int(Profile.coins)
	_refresh_catalog_state()
	_refresh_info()


func _rebuild_model() -> void:
	var yaw := _preview.stage.pivot.rotation.y if _preview.stage.model != null else ShopScreen.GUN_YAW
	var parts := _design.get("parts", []) as Array
	_preview.show_model(Models.build_gun(wid, Profile.gun_skin(wid), Profile.equipped.charm, _design if not parts.is_empty() else {}),
		false, yaw, 1.1)
	_reticle.design = _design
	_reticle.queue_redraw()
	_refresh_info()


func _refresh_info() -> void:
	var parts := (_design.get("parts", []) as Array).size()
	var fov := CustomScopes.ads_fov(wid, _design if parts > 0 else {})
	var r := CustomScopes.power_range(wid)
	_info.text = "%d / %d PARTS  ·  POWER %.2fx  ·  ADS VIEW %d° (OWN SIGHTS %d°)%s" % [parts, CustomScopes.MAX_PARTS,
		clampf(float(_design.get("power", 1.0)), r.x, r.y), roundi(fov), roundi(float(Data.WEAPONS[wid].ads_fov)),
		"" if parts > 0 else "\nNo parts: the gun uses its own sights."]
	if not Profile.is_custom_scope_on(wid):
		_info.text += "\nSwitched OFF: in a match the gun uses its own sights."
	var n := _unpaid()
	var cost := n * CustomScopes.PART_PRICE
	_pay.visible = n > 0
	_pay.text = "BUY %d PART%s · %s" % [n, "" if n == 1 else "S", UIKit.format_int(cost)]
	_pay.disabled = Profile.coins < cost
	_pay.tooltip_text = "You need %s more coins." % UIKit.format_int(cost - Profile.coins) if _pay.disabled \
		else "Keep the new parts. Leaving without buying drops them."


# ------------------------------------------------------------------ catalog

func _show_group(g: String) -> void:
	_group = g
	_group_buttons[g].set_pressed_no_signal(true)
	for c in _catalog.get_children():
		c.queue_free()
	for part in CustomScopes.parts_in(g):
		var info := CustomScopes.part_info(part)
		var b := UIKit.button("+  %s" % str(info.name).to_upper(), &"", false)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "Try a %s (free until you BUY PARTS, %d coins each)." % [info.name, CustomScopes.PART_PRICE]
		b.set_meta(&"part", part)
		b.pressed.connect(func() -> void: _add_part(CustomScopes.new_part(part)))
		_catalog.add_child(b)
	_refresh_catalog_state()


func _refresh_catalog_state() -> void:
	var full := (_design.get("parts", []) as Array).size() >= CustomScopes.MAX_PARTS
	for c in _catalog.get_children():
		var b := c as Button
		if b != null and not b.is_queued_for_deletion():
			b.disabled = full
			if full:
				b.tooltip_text = "This scope has the most parts it can carry (%d)." % CustomScopes.MAX_PARTS


## Adds `part` (a part dictionary) to the design for free trying, and selects it; BUY PARTS keeps it.
func _add_part(part: Dictionary) -> void:
	if (_design.parts as Array).size() >= CustomScopes.MAX_PARTS:
		Sfx.play(&"ui_error")
		return
	(_design.parts as Array).append(part)
	Sfx.play(&"ui_click")
	_sel = (_design.parts as Array).size() - 1
	_show_tab("PARTS")
	_refresh_parts()
	_refresh_catalog_state()
	_touch()


## RESET: the starter parts and default optics. CLEAR ALL: no parts, the optics stay.
func _reset_design() -> void:
	_replace_design(CustomScopes.starter())


func _clear_parts() -> void:
	var d := _design.duplicate(true)
	d.parts = []
	_replace_design(d)


## Replaces the whole design (RESET / CLEAR ALL: no refund); saved like any free edit.
func _replace_design(d: Dictionary) -> void:
	_design = d
	_sel = 0 if not (_design.parts as Array).is_empty() else -1
	_touch()
	_refresh_catalog_state()
	_refresh_parts()
	for f in _optics_refresh:
		f.call()
	_refresh_paint()
	_rebuild_model()


## First press arms `b` ("PRESS AGAIN"), a second within CONFIRM_TIME runs `action`.
func _confirm(b: Button, label: String, action: Callable) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_confirm_at.get(label, -100.0)) <= CONFIRM_TIME:
		_confirm_at.erase(label)
		b.text = label
		action.call()
		return
	_confirm_at[label] = now
	b.text = "PRESS AGAIN"
	get_tree().create_timer(CONFIRM_TIME).timeout.connect(func() -> void:
		if is_instance_valid(b):
			b.text = label)


# ------------------------------------------------------------------ parts tab

func _show_tab(t: String) -> void:
	_tab_buttons[t].set_pressed_no_signal(true)
	_parts_page.visible = t == "PARTS"
	_optics_page.visible = t == "OPTICS"


func _refresh_parts() -> void:
	for c in _parts_list.get_children():
		c.queue_free()
	var parts := _design.get("parts", []) as Array
	var group := ButtonGroup.new()
	for i in parts.size():
		var p: Dictionary = parts[i]
		var info := CustomScopes.part_info(int(p.part))
		var b := UIKit.button("%d   %s" % [i + 1, str(info.name).to_upper()], &"CardButton")
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 34
		b.set_pressed_no_signal(i == _sel)
		b.pressed.connect(func() -> void:
			_sel = i
			_refresh_editor())
		_parts_list.add_child(b)
	if parts.is_empty():
		var none := UIKit.label("No parts yet. Add one from the catalog on the left.", &"DimLabel")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_parts_list.add_child(none)
	_refresh_catalog_state()
	_refresh_editor()


func _refresh_editor() -> void:
	for c in _editor.get_children():
		c.queue_free()
	var parts := _design.get("parts", []) as Array
	if _sel < 0 or _sel >= parts.size():
		return
	var p: Dictionary = parts[_sel]
	var info := CustomScopes.part_info(int(p.part))
	var e := _editor
	e.add_child(UIKit.label("%s  ·  %s" % [str(info.name).to_upper(), str(info.group)], &"SubheaderLabel"))
	_color_editor(e, "COLOUR", func() -> Color: return p.color, func(c: Color) -> void: p.color = c)
	e.add_child(UIKit.label("FINISH", &"SmallLabel"))
	_chips(e, CustomScopes.FINISHES, func() -> int: return int(p.finish), func(i: int) -> void: p.finish = i)
	var limits := CustomScopes.SIZE_LIMITS
	_slider(e, "LENGTH", limits.x, limits.y, 0.02, _times, func() -> float: return float(p.length),
		func(x: float) -> void: p.length = x)
	_slider(e, "WIDTH", limits.x, limits.y, 0.02, _times, func() -> float: return float(p.width),
		func(x: float) -> void: p.width = x)
	var lim := CustomScopes.OFFSET_LIMIT
	_slider(e, "LEFT / RIGHT", -lim, lim, 0.002, _cm, func() -> float: return (p.offset as Vector3).x,
		func(x: float) -> void: p.offset = Vector3(x, (p.offset as Vector3).y, (p.offset as Vector3).z))
	_slider(e, "DOWN / UP", -lim, lim, 0.002, _cm, func() -> float: return (p.offset as Vector3).y,
		func(x: float) -> void: p.offset = Vector3((p.offset as Vector3).x, x, (p.offset as Vector3).z))
	_slider(e, "BACK / FRONT", -lim, lim, 0.002, _cm, func() -> float: return -(p.offset as Vector3).z,
		func(x: float) -> void: p.offset = Vector3((p.offset as Vector3).x, (p.offset as Vector3).y, -x))
	_slider(e, "ROLL", 0, CustomScopes.ROLL_STEPS - 1, 1, func(x: float) -> String: return "%d°" % roundi(x * 15.0),
		func() -> float: return float(p.roll), func(x: float) -> void: p.roll = int(x))
	var row := UIKit.hbox(6)
	e.add_child(row)
	var dup := UIKit.button("DUPLICATE", &"GoldButton", false)
	dup.tooltip_text = "Add a copy of this part, a little to the right (%d coins at BUY PARTS)." % CustomScopes.PART_PRICE
	dup.disabled = parts.size() >= CustomScopes.MAX_PARTS
	dup.pressed.connect(func() -> void:
		var copy := p.duplicate(true)
		var off: Vector3 = copy.offset
		copy.offset = Vector3(clampf(off.x + 0.01, -lim, lim), off.y, off.z)
		_add_part(copy)
		_tab_buttons["PARTS"].grab_focus())
	row.add_child(dup)
	var remove := UIKit.button("REMOVE", &"DangerButton")
	remove.tooltip_text = "Take this part off (bought parts are not refunded)."
	remove.pressed.connect(func() -> void:
		(_design.parts as Array).remove_at(_sel)
		_sel = mini(_sel, (_design.parts as Array).size() - 1)
		_refresh_parts()
		_refresh_catalog_state()
		_touch()
		# The pressed button is gone; keep keyboard / controller focus on this panel.
		_tab_buttons["PARTS"].grab_focus())
	row.add_child(remove)


func _refresh_paint() -> void:
	var px: PackedByteArray = _design.get("pixels", PackedByteArray())
	for i in _paint_cells.size():
		_paint_cells[i].set_pressed_no_signal(i < px.size() and px[i] != 0)


# ------------------------------------------------------------------ widgets

## A labelled slider: shows `get`, calls `set` on a change (then _touch). Returns its refresh.
func _slider(parent: Control, text: String, lo: float, hi: float, step: float, fmt: Callable, getter: Callable,
		setter: Callable) -> Callable:
	var h := UIKit.hbox(8)
	parent.add_child(h)
	var l := UIKit.label(text, &"SmallLabel")
	l.custom_minimum_size.x = 104
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size.y = 26
	h.add_child(s)
	var v := UIKit.label("", &"ValueLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_theme_font_size_override("font_size", 14)
	v.custom_minimum_size.x = 64
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		setter.call(x)
		v.text = fmt.call(x)
		_touch())
	s.drag_started.connect(func() -> void: Sfx.play(&"ui_hover", null, -8.0))
	var refresh := func() -> void:
		s.set_value_no_signal(getter.call())
		v.text = fmt.call(s.value)
	refresh.call()
	return refresh


## A row of toggle chips, one per name; shows `get` (an index), calls `set`. Returns its refresh.
func _chips(parent: Control, names: Array[String], getter: Callable, setter: Callable) -> Callable:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	parent.add_child(flow)
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	for i in names.size():
		var b := UIKit.button(names[i].to_upper(), &"ChipButton")
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func() -> void:
			setter.call(i)
			_touch())
		flow.add_child(b)
		buttons.append(b)
	var refresh := func() -> void:
		var at := clampi(int(getter.call()), 0, buttons.size() - 1)
		buttons[at].set_pressed_no_signal(true)
	refresh.call()
	return refresh


## Palette chips plus R / G / B sliders for a colour; shows `get`, calls `set`. Returns the
## refreshes of its sliders.
func _color_editor(parent: Control, text: String, getter: Callable, setter: Callable) -> Array[Callable]:
	parent.add_child(UIKit.label(text, &"SmallLabel"))
	var grid := GridContainer.new()
	grid.columns = 12
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)
	var refreshes: Array[Callable] = []
	for hex in CustomScopes.PALETTE:
		var c := Color(hex)
		var b := _swatch_button(c)
		b.tooltip_text = "#" + hex
		b.pressed.connect(func() -> void:
			setter.call(c)
			for f in refreshes:
				f.call()
			_touch())
		grid.add_child(b)
	for ch: int in 3:
		var channel := ch
		var get_channel := func() -> float:
			var c: Color = getter.call()
			return float([c.r8, c.g8, c.b8][channel])
		var set_channel := func(x: float) -> void:
			var c: Color = getter.call()
			var rgb := [c.r8, c.g8, c.b8]
			rgb[channel] = roundi(x)
			setter.call(Color8(rgb[0], rgb[1], rgb[2], c.a8))
		var label: String = ["RED", "GREEN", "BLUE"][channel]
		refreshes.append(_slider(parent, label, 0, 255, 1, func(x: float) -> String: return str(roundi(x)), get_channel, set_channel))
	return refreshes


static func _swatch_button(c: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(24, 22)
	b.focus_mode = Control.FOCUS_ALL
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c.lightened(0.15) if state == "hover" else c
		sb.set_corner_radius_all(5)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.18)
		b.add_theme_stylebox_override(state, sb)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(5)
	focus.set_border_width_all(2)
	focus.border_color = Color.WHITE
	b.add_theme_stylebox_override("focus", focus)
	UIKit.wire(b)
	return b


## A PIXEL PAINT grid cell: dark when off, the accent colour when on.
static func _cell_button() -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(17, 17)
	b.focus_mode = Control.FOCUS_ALL
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		var on := state.ends_with("pressed")
		sb.bg_color = UITheme.ACCENT if on else Color(0.16, 0.18, 0.22)
		if state.begins_with("hover"):
			sb.bg_color = sb.bg_color.lightened(0.2)
		sb.set_corner_radius_all(2)
		b.add_theme_stylebox_override(state, sb)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = Color.WHITE
	b.add_theme_stylebox_override("focus", focus)
	return b


static func _pct(x: float) -> String:
	return "%d%%" % roundi(x * 100.0)


static func _times(x: float) -> String:
	return "x%.2f" % x


static func _cm(x: float) -> String:
	return "%+.1f cm" % (x * 100.0)
