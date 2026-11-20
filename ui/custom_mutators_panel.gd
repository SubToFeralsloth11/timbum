class_name CustomMutatorsPanel
extends Control
## The match setup's CUSTOM MUTATORS overlay: one weapon for everyone, max health, gravity, player
## size, move speed, damage and jump height, and the headshots-only, infinite-ammo and no-grenades
## switches (CustomMutators). Edits a copy of the setup's `custom` choice and hands every change
## back through `changed`; a line under the switches names the picks the chosen mode ignores.
## Esc / pad B or DONE closes it. While open, the page behind (`behind`) takes no focus.

signal changed(custom: Dictionary)
signal closed

## Switch keys and their chip labels.
const FLAGS: Array = [["headshots", "HEADSHOTS ONLY"], ["infinite_ammo", "INFINITE AMMO"], ["no_grenades", "NO GRENADES"]]
## Numeric rows: key, row name, format.
const ROWS: Array = [["health", "HEALTH", "%s%%"], ["gravity", "GRAVITY", "%sx"], ["size", "SIZE", "%sx"],
	["speed", "SPEED", "%sx"], ["damage", "DAMAGE", "%sx"], ["jump", "JUMP", "%sx"]]
## What sanitize() drops in a mode, as the line under the switches names it.
const IGNORED_NAMES := {"weapon": "one weapon", "headshots": "headshots only", "infinite_ammo": "infinite ammo", "size": "size"}

var behind: Control
var _custom := CustomMutators.DEFAULTS.duplicate()
var _mode := "ffa"
var _weapon: OptionButton
## Weapon ids in the OptionButton's item order ("" for OFF and the separators).
var _weapon_ids: Array[String] = []
## key -> the chip row (numeric settings) or the toggle chip (switches).
var _rows := {}
var _flags := {}
var _note: Label
var _done: Button


func _init(p_behind: Control) -> void:
	behind = p_behind
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UIKit.panel()
	panel.add_theme_stylebox_override("panel", UITheme.round_box(UITheme.PANEL_SOLID, Color(1, 1, 1, 0.1), 1, UITheme.PANEL_RADIUS, 22, 12))
	panel.custom_minimum_size.x = 640
	center.add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)
	v.add_child(UIKit.label("CUSTOM MUTATORS", &"HeaderLabel"))
	var sub := UIKit.label("Your own rules on top of the match's mutator. Bots play by them too.", &"DimLabel")
	sub.add_theme_font_size_override("font_size", 14)
	v.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)

	_weapon = OptionButton.new()
	_weapon.fit_to_longest_item = false
	_weapon.add_theme_font_size_override("font_size", 14)
	_weapon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon.tooltip_text = "Everyone gets only this weapon (a gun keeps the quick melee). Deathmatch, Team Deathmatch, Capture the Flag, King of the Block and Infected."
	_weapon.add_item("OFF · everyone's own loadout")
	_weapon_ids.append("")
	for group: Array in [["GUNS", ["primary", "secondary"]], ["MELEE", ["melee"]]]:
		_weapon.add_separator(group[0])
		_weapon_ids.append("")
		for wid: String in Data.WEAPONS:
			if CustomMutators.weapon_allowed(wid) and str(Data.WEAPONS[wid].slot) in group[1]:
				_weapon.add_item(str(Data.WEAPONS[wid].name))
				_weapon_ids.append(wid)
	_weapon.item_selected.connect(func(i: int) -> void: _pick("weapon", _weapon_ids[i]))
	_row(grid, "WEAPON", _weapon)

	for row: Array in ROWS:
		var key: String = row[0]
		var chips := _chip_row()
		var group := ButtonGroup.new()
		for value: Variant in CustomMutators.CHOICES[key]:
			var text: String = row[2] % (str(value) if key == "health" else CustomMutators.num(float(value)))
			var b := _chip(text)
			b.button_group = group
			b.set_meta(&"value", value)
			b.pressed.connect(func() -> void: _pick(key, value))
			chips.add_child(b)
		_rows[key] = chips
		_row(grid, row[1], chips)
	var switches := _chip_row()
	for f: Array in FLAGS:
		var key: String = f[0]
		var b := _chip(f[1])
		b.toggled.connect(func(on: bool) -> void: _pick(key, on))
		switches.add_child(b)
		_flags[key] = b
	_row(grid, "RULES", switches)

	_note = UIKit.label("", &"DimLabel")
	_note.add_theme_font_size_override("font_size", 13)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_note)
	var actions := UIKit.hbox(8)
	v.add_child(actions)
	var reset := UIKit.button("RESET ALL")
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func() -> void:
		_custom = CustomMutators.DEFAULTS.duplicate()
		_show()
		changed.emit(_custom.duplicate()))
	actions.add_child(reset)
	_done = UIKit.button("DONE", &"PrimaryButton")
	_done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_done.pressed.connect(close)
	actions.add_child(_done)
	MatchSetupScreen._add_hover_fx(self)


## Shows `custom` (the setup's choice) for `mode`.
func open(custom: Dictionary, mode: String) -> void:
	_custom = CustomMutators.sanitize(custom)
	_mode = mode
	_show()
	visible = true
	if behind != null:
		behind.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_done.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	if behind != null:
		behind.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _pick(key: String, value: Variant) -> void:
	_custom[key] = value
	_update_note()
	changed.emit(_custom.duplicate())


## Sets every control to `_custom`.
func _show() -> void:
	_weapon.select(maxi(0, _weapon_ids.find(str(_custom.weapon))))
	for key: String in _rows:
		for b: Node in (_rows[key] as Container).get_children():
			(b as Button).set_pressed_no_signal(is_equal_approx(float(b.get_meta(&"value")), float(_custom[key])))
	for key: String in _flags:
		(_flags[key] as Button).set_pressed_no_signal(bool(_custom[key]))
	_update_note()


## Names the picks the chosen mode ignores (CustomMutators.sanitize), or what is on.
func _update_note() -> void:
	var kept := CustomMutators.sanitize(_custom, _mode)
	var dropped: Array[String] = []
	for key: String in IGNORED_NAMES:
		if kept[key] != _custom[key]:
			dropped.append(IGNORED_NAMES[key])
	var on := CustomMutators.describe(kept)
	var mode_name := str(Data.MODES[_mode].name)
	var text := "%s: %s." % [mode_name, ", ".join(on) if not on.is_empty() else "no custom mutators"]
	if not dropped.is_empty():
		text += " Not used in %s: %s." % [mode_name, ", ".join(dropped)]
	_note.text = text


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var l := UIKit.label(text, &"SmallLabel")
	l.custom_minimum_size.x = 72
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _chip_row() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 4)
	return f


func _chip(text: String) -> Button:
	var b := UIKit.button(text, &"ChipButton")
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b
