class_name RangeOverlay
extends CanvasLayer
## The Firing Range's screen (canvas layer 11, above the Hud): the readout card at the right
## (last hit, burst DPS, shots-to-kill and TTK for the held gun at the hit distance, session hit %
## and headshots), the console prompt when the player stands at the counter, and the weapon
## console itself: every gun (owned or not, marked TRY), the knife, frags, both tacticals, the
## grapple and RESET READOUT. The console takes the input while open (FiringRange.ui_blocking);
## Esc / B closes it. The tutorial hides the readout (`show_readout`).

var firing: FiringRange
var show_readout := true

var _root: Control
var _card: PanelContainer
var _gun: Label
var _last: Label
var _dps: Label
var _stk: Label
var _stk_head: Label
var _falloff: Label
var _session: Label
var _hint: Label
var _prompt: Label
var _toast: Label
var _toast_t := 0.0
var _console: Control
var _first_button: Button
var _gun_buttons := {}


func setup(p_range: FiringRange) -> void:
	firing = p_range


func _ready() -> void:
	layer = 11
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_build_card()
	_prompt = _label("", 22, Color(1, 0.88, 0.45))
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position.y += 70
	_root.add_child(_prompt)
	_toast = _label("", 22, Color(0.6, 1.0, 0.6))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position.y += 110
	_root.add_child(_toast)
	_build_console()


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_card() -> void:
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.66)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	sb.border_color = Color(1, 0.85, 0.35, 0.35)
	sb.set_border_width_all(2)
	_card.add_theme_stylebox_override("panel", sb)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.offset_right = -18
	_card.custom_minimum_size = Vector2(330, 0)
	_root.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_card.add_child(v)
	v.add_child(_label("RANGE READOUT", 14, Color(1, 0.85, 0.4)))
	_gun = _label("", 19)
	v.add_child(_gun)
	_falloff = _label("", 13, Color(0.7, 0.75, 0.85))
	v.add_child(_falloff)
	v.add_child(HSeparator.new())
	_last = _label("", 17)
	v.add_child(_last)
	_dps = _label("", 17)
	v.add_child(_dps)
	_stk = _label("", 17, Color(0.75, 0.9, 1.0))
	v.add_child(_stk)
	_stk_head = _label("", 17, Color(1.0, 0.75, 0.55))
	v.add_child(_stk_head)
	v.add_child(HSeparator.new())
	_session = _label("", 16)
	v.add_child(_session)
	_hint = _label("", 13, Color(0.7, 0.75, 0.85))
	v.add_child(_hint)


func _build_console() -> void:
	_console = Control.new()
	_console.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_console.mouse_filter = Control.MOUSE_FILTER_STOP
	_console.visible = false
	_root.add_child(_console)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_console.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_console.add_child(center)
	var panel := UIKit.panel()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)
	v.add_child(UIKit.label("WEAPON CONSOLE", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("Try any gun, owned or not, with your own attachment upgrades. TRY marks a gun you don't own yet.",
		&"DimLabel", HORIZONTAL_ALIGNMENT_CENTER))
	for slot: String in ["primary", "secondary"]:
		v.add_child(UIKit.label("PRIMARIES" if slot == "primary" else "SECONDARIES", &"SubheaderLabel"))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		v.add_child(grid)
		for wid: String in Data.weapon_ids_for_slot(slot):
			var b := UIKit.button("")
			b.custom_minimum_size = Vector2(178, 40)
			b.pressed.connect(_pick.bind(wid))
			grid.add_child(b)
			_gun_buttons[wid] = b
			if _first_button == null:
				_first_button = b
	v.add_child(UIKit.label("KNIFE, GRENADES AND HOOK", &"SubheaderLabel"))
	var row := GridContainer.new()
	row.columns = 4
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	v.add_child(row)
	var extras: Array = [
		[str(Data.WEAPONS.knife.name).to_upper(), func() -> void: firing.equip("knife")],
		["FRAGS (REFILL)", firing.refill_grenades],
		[str(Data.TACTICALS.smoke.name).to_upper(), func() -> void: firing.equip_tactical("smoke")],
		[str(Data.TACTICALS.flash.name).to_upper(), func() -> void: firing.equip_tactical("flash")],
		["GRAPPLE (READY)", firing.ready_grapple],
		["RESET READOUT", firing.reset_readout],
	]
	for e: Array in extras:
		var b := UIKit.button(str(e[0]))
		b.custom_minimum_size = Vector2(178, 40)
		b.pressed.connect(_run.bind(e[1], str(e[0])))
		row.add_child(b)
	var close := UIKit.button("CLOSE", &"PrimaryButton")
	close.pressed.connect(close_console)
	v.add_child(close)


func console_open() -> bool:
	return _console.visible


func open_console() -> void:
	if _console.visible:
		return
	var p := firing.world.local_player
	for wid: String in _gun_buttons:
		var b: Button = _gun_buttons[wid]
		var held := p != null and p.slots.has(wid)
		b.text = "%s%s" % [str(Data.WEAPONS[wid].name).to_upper(),
			"  ✓" if held else ("" if Profile.is_owned("weapons", wid) else "  ·  TRY")]
	_console.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_first_button.grab_focus.call_deferred()


func close_console() -> void:
	if not _console.visible:
		return
	_console.visible = false
	if not firing.world.hud.is_blocking():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pick(wid: String) -> void:
	firing.equip(wid)
	close_console()
	toast("EQUIPPED %s%s" % [str(Data.WEAPONS[wid].name).to_upper(), "" if Profile.is_owned("weapons", wid) else "  ·  TRYING IT"])


func _run(action: Callable, text: String) -> void:
	action.call()
	close_console()
	toast(text)


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.0


func _input(event: InputEvent) -> void:
	if _console.visible and (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		close_console()


func _process(delta: float) -> void:
	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	var w := firing.world
	var p := w.local_player
	var hud_hidden := w.photo != null and w.photo.is_open()
	_prompt.visible = not hud_hidden and not _console.visible and firing.near_console() and not w.hud.is_blocking()
	if _prompt.visible:
		_prompt.text = "[%s]  WEAPON CONSOLE" % Profile.key_text("interact")
	_card.visible = show_readout and not hud_hidden and p != null
	if _card.visible:
		_refresh_card(p)


## Fills the readout from FiringRange.readout and the held gun.
func _refresh_card(p: Player) -> void:
	var r := firing.readout
	var wid := p.weapon_id()
	var w: Dictionary = Data.WEAPONS[wid]
	var owned := Profile.is_owned("weapons", wid) or wid == "knife"
	_gun.text = "%s%s" % [str(w.name).to_upper(), "" if owned else "  ·  TRY"]
	var barrel := p.mod("barrel")
	if wid == "knife":
		_falloff.text = "%d damage per slash  ·  %.1f m reach" % [roundi(float(w.damage)), float(w.range)]
	elif w.get("projectile", false):
		_falloff.text = "%d direct  ·  %.1f m splash" % [roundi(float(w.damage)), float(w.splash_radius)]
	else:
		_falloff.text = "%s%d dmg, falls off %d-%d m to %d%%%s" % ["%d x " % int(w.pellets) if int(w.pellets) > 1 else "",
			roundi(float(w.damage)), roundi(float(w.falloff_start) * barrel), roundi(float(w.falloff_end) * barrel),
			roundi(float(w.min_mult) * 100.0), "  (Long Barrel)" if barrel > 1.0 else ""]
	var dist := float(r.last_dist)
	if dist < 0.0:
		_last.text = "LAST HIT   -"
		_stk.text = "Hit a dummy for shots-to-kill and TTK"
		_stk_head.text = ""
	else:
		_last.text = "LAST HIT   %d%s  @ %.1f m%s" % [roundi(float(r.last_dmg)), "  HEAD" if bool(r.last_head) else "",
			dist, "  (%d pellets)" % int(r.last_pellets) if int(Data.WEAPONS.get(str(r.last_wid), {}).get("pellets", 1)) > 1 else ""]
		var body := FiringRange.shots_to_kill(w, dist, barrel, false)
		var head := FiringRange.shots_to_kill(w, dist, barrel, true)
		_stk.text = "AT %.0f m   %d shot%s  ·  TTK %.2f s" % [dist, body, "" if body == 1 else "s", FiringRange.time_to_kill(w, body)]
		_stk_head.text = "HEADSHOTS   %d shot%s  ·  TTK %.2f s" % [head, "" if head == 1 else "s", FiringRange.time_to_kill(w, head)]
	_dps.text = "BURST DPS  %d" % roundi(float(r.dps)) if float(r.dps) > 0.0 else "BURST DPS  -"
	var pct := firing.hit_percent()
	_session.text = "HITS  %s  (%d / %d)  ·  HEADSHOTS  %d" % ["-" if pct < 0.0 else "%d%%" % roundi(pct),
		int(r.hits), int(r.shots), int(r.heads)]
	_hint.text = "%s at the console: any gun, reset  ·  %s: leave" % [Profile.key_text("interact"), Profile.key_text("pause")]
