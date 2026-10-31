class_name MapEditorHud
extends CanvasLayer
## The Map Editor's screen (MapEditor.hud): the crosshair, an info card top left (map name and
## size, tool, block, brush, the keys), the validation card top right (what still stops the map
## from being played), a message line, the tool strip and the 9-slot block hotbar at the bottom.
## The side panel (Tab / Esc / Back or Start, `toggle_panel`) frees the mouse and stops the camera
## (the info card hides, the bottom row moves right of it): BACK TO BUILDING, tools, brush, the
## whole block palette (a pick goes into the selected hotbar slot), the name and SAVE, NEW at a
## size preset, OPEN a saved map, the sky (time of day), UNDO / REDO, TEST PLAY and EXIT. Every
## control is a focusable button, so a controller can drive it.

const PANEL_WIDTH := 430.0
## Seconds between validation-card rechecks: the reachability flood fill costs up to tens of
## milliseconds on the largest maps, so a run of edits rechecks a few times a second, not per edit.
const CHECK_GAP := 0.3

var editor: MapEditor

var _root: Control
var _info_card: PanelContainer
## The message line, tool strip and hotbar; centred in the space right of the panel when it is open.
var _bottom: VBoxContainer
var _info: Label
var _keys: Label
var _problems: Label
var _problems_card: PanelContainer
var _message: Label
var _message_t := 0.0
## The validation card needs a recheck (refresh), and seconds until the next one may run.
var _check_due := true
var _check_wait := 0.0
var _tool_row: HBoxContainer
var _hotbar: HBoxContainer
var _panel: PanelContainer
var _name_edit: LineEdit
var _open_pick: OptionButton
var _sky_row: HBoxContainer
var _tool_buttons := {}
var _brush_row: HBoxContainer
var _palette_buttons := {}
var _undo_button: Button
var _redo_button: Button
var _exit_button: Button
var _exit_armed := false
var _first_focus: Control
## Asks before a save replaces an unreadable file under the map's name (MapEditor.replace_broken_asked).
var _replace_confirm: ConfirmationDialog


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_build_crosshair()
	_build_info()
	_build_problems()
	_build_bottom()
	_build_panel()
	editor.changed.connect(refresh)
	editor.message.connect(show_message)
	editor.replace_broken_asked.connect(ask_replace_broken)
	refresh()


func panel_open() -> bool:
	return _panel.visible


func open_panel() -> void:
	_panel.visible = true
	_info_card.visible = false
	_bottom.offset_left = PANEL_WIDTH + 28
	_exit_armed = false
	_exit_button.text = "EXIT"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_open_list()
	refresh()
	if _first_focus != null:
		_first_focus.grab_focus.call_deferred()


func close_panel() -> void:
	_panel.visible = false
	_info_card.visible = true
	_bottom.offset_left = 0
	var f := get_viewport().gui_get_focus_owner()
	if f != null:
		f.release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle_panel() -> void:
	if _panel.visible:
		close_panel()
	else:
		open_panel()


## The save found an unreadable file under the map's name: offer to replace it. NO is the
## default (focused); REPLACE saves over the broken file.
func ask_replace_broken(map_name: String) -> void:
	if _replace_confirm == null:
		_replace_confirm = ConfirmationDialog.new()
		_replace_confirm.title = "Broken map file"
		_replace_confirm.ok_button_text = "Replace"
		_replace_confirm.cancel_button_text = "No"
		_replace_confirm.theme = UITheme.get_theme()
		_replace_confirm.confirmed.connect(func() -> void:
			editor.save(true)
			_refresh_open_list())
		add_child(_replace_confirm)
	if not _panel.visible:
		open_panel()
	_replace_confirm.dialog_text = ("The file %s.json in your maps folder can't be read: it is damaged or was made by a newer Timbum.\n"
		+ "Replace it with this map? The broken file will be lost.") % map_name
	_replace_confirm.popup_centered()
	_replace_confirm.get_cancel_button().grab_focus.call_deferred()


func show_message(text: String, error: bool) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", UITheme.BAD.lightened(0.25) if error else Color(0.7, 1.0, 0.7))
	_message.modulate.a = 1.0
	_message_t = 4.0


func _process(delta: float) -> void:
	if _message_t > 0.0:
		_message_t -= delta
		_message.modulate.a = clampf(_message_t, 0.0, 1.0)
	_check_wait -= delta
	if _check_due and _check_wait <= 0.0 and not editor.map.is_empty():
		_check_due = false
		_check_wait = CHECK_GAP
		_refresh_checks()


# ---------------------------------------------------------------- build

func _label(text: String, size: int, color := UITheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _card(accent: Color) -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", UITheme.hud_card(0.6, 12, UITheme.CARD_RADIUS, accent))
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _build_crosshair() -> void:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		if panel_open():
			return
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			c.draw_line(d * 4.0, d * 11.0, Color(0, 0, 0, 0.6), 4.0, true)
			c.draw_line(d * 4.0, d * 11.0, Color.WHITE, 2.0, true))
	_root.add_child(c)
	_root.set_meta(&"crosshair", c)


func _build_info() -> void:
	var card := _card(Color(1, 0.85, 0.35, 0.35))
	card.position = Vector2(18, 18)
	_info_card = card
	_root.add_child(card)
	var v := UIKit.vbox(3)
	card.add_child(v)
	_info = _label("", 18, UITheme.ACCENT)
	v.add_child(_info)
	_keys = _label("", 13, UITheme.TEXT_DIM)
	v.add_child(_keys)


func _build_problems() -> void:
	_problems_card = _card(Color(1, 1, 1, 0.07))
	_problems_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_problems_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_problems_card.offset_right = -18
	_problems_card.offset_top = 18
	_problems_card.custom_minimum_size.x = 300
	_root.add_child(_problems_card)
	_problems = _label("", 14)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.custom_minimum_size.x = 300
	_problems_card.add_child(_problems)


func _build_bottom() -> void:
	var v := UIKit.vbox(8)
	_bottom = v
	v.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	v.offset_bottom = -18
	v.alignment = BoxContainer.ALIGNMENT_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(v)
	_message = _label("", 18)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_message)
	_tool_row = UIKit.hbox(6)
	_tool_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tool_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_tool_row)
	for t: String in MapEditor.TOOLS:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.set_meta(&"tool", t)
		chip.add_child(_label(MapEditor.TOOL_NAMES[t], 13))
		_tool_row.add_child(chip)
	_hotbar = UIKit.hbox(6)
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_hotbar)
	for i in editor.hotbar.size():
		var cell := PanelContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.custom_minimum_size = Vector2(58, 58)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(42, 42)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
		var num := _label(str(i + 1), 13)
		num.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		cell.add_child(num)
		_hotbar.add_child(cell)


func _section(parent: Container, text: String) -> void:
	var l := UIKit.label(text, &"SmallLabel")
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	parent.add_child(l)


func _chip(text: String, action: Callable) -> Button:
	var b := UIKit.button(text, &"ChipButton")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	return b


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.round_box(UITheme.PANEL_SOLID, Color(UITheme.ACCENT, 0.3), 1, UITheme.PANEL_RADIUS, 14))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 14
	_panel.offset_top = 14
	_panel.offset_bottom = -14
	_panel.custom_minimum_size.x = PANEL_WIDTH
	_panel.visible = false
	_root.add_child(_panel)
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var v := UIKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(UIKit.label("MAP EDITOR", &"SubheaderLabel"))

	var resume := UIKit.button("BACK TO BUILDING", &"PrimaryButton")
	resume.pressed.connect(close_panel)
	v.add_child(resume)
	_first_focus = resume

	_section(v, "TOOL  (Q / E, pad LB / RB)")
	var tools := GridContainer.new()
	tools.columns = 3
	tools.add_theme_constant_override("h_separation", 4)
	tools.add_theme_constant_override("v_separation", 4)
	v.add_child(tools)
	for t: String in MapEditor.TOOLS:
		var b := _chip(MapEditor.TOOL_NAMES[t], func() -> void: editor.set_tool(t))
		b.toggle_mode = true
		_tool_buttons[t] = b
		tools.add_child(b)

	_section(v, "BRUSH  (R, pad X)")
	_brush_row = UIKit.hbox(4)
	v.add_child(_brush_row)
	for n: int in [1, 3]:
		var b := _chip("%d x %d" % [n, n], func() -> void: editor.set_brush(n))
		b.toggle_mode = true
		_brush_row.add_child(b)

	_section(v, "BLOCKS  (goes into the selected hotbar slot)")
	var pal := GridContainer.new()
	pal.columns = 7
	pal.add_theme_constant_override("h_separation", 4)
	pal.add_theme_constant_override("v_separation", 4)
	v.add_child(pal)
	for e: Array in MapEditor.PALETTE:
		var b := Button.new()
		b.icon = BlockAtlas.icon(e[0], 2)
		b.expand_icon = false
		b.tooltip_text = e[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(52, 46)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.theme_type_variation = &"ChipButton"
		UIKit.wire(b)
		var block: int = e[0]
		b.pressed.connect(func() -> void: editor.pick_block(block))
		_palette_buttons[block] = b
		pal.add_child(b)

	_section(v, "NAME")
	var name_row := UIKit.hbox(6)
	v.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.max_length = CustomMaps.NAME_MAX
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(t: String) -> void:
		editor.set_map_name(t)
		_name_edit.text = editor.map.name)
	_name_edit.focus_exited.connect(func() -> void:
		editor.set_map_name(_name_edit.text)
		_name_edit.text = editor.map.name)
	name_row.add_child(_name_edit)
	var save := UIKit.button("SAVE", &"PrimaryButton")
	save.pressed.connect(func() -> void:
		editor.set_map_name(_name_edit.text)
		editor.save()
		_refresh_open_list())
	name_row.add_child(save)

	_section(v, "NEW MAP (flat floor, height 24)")
	var new_row := UIKit.hbox(4)
	v.add_child(new_row)
	for size: Vector3i in CustomMaps.PRESETS:
		new_row.add_child(_chip("%d x %d" % [size.x, size.z], func() -> void: editor.new_map(size)))

	_section(v, "OPEN")
	var open_row := UIKit.hbox(6)
	v.add_child(open_row)
	_open_pick = OptionButton.new()
	_open_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_row.add_child(_open_pick)
	var open := UIKit.button("OPEN")
	open.pressed.connect(func() -> void:
		if _open_pick.selected >= 0 and _open_pick.item_count > 0:
			editor.load_saved(_open_pick.get_item_text(_open_pick.selected)))
	open_row.add_child(open)

	_section(v, "SKY")
	_sky_row = UIKit.hbox(4)
	v.add_child(_sky_row)
	for tod: String in ["day", "sunset", "night"]:
		var b := _chip(tod.to_upper(), func() -> void: editor.set_time_of_day(tod))
		b.toggle_mode = true
		b.set_meta(&"tod", tod)
		_sky_row.add_child(b)

	var edit_row := UIKit.hbox(4)
	v.add_child(edit_row)
	_undo_button = _chip("UNDO (Ctrl+Z)", editor.undo)
	edit_row.add_child(_undo_button)
	_redo_button = _chip("REDO (Ctrl+Y)", editor.redo)
	edit_row.add_child(_redo_button)

	var test := UIKit.button("TEST PLAY vs BOTS", &"GoldButton")
	test.pressed.connect(editor.test_play)
	v.add_child(test)
	_exit_button = UIKit.button("EXIT", &"DangerButton")
	_exit_button.pressed.connect(func() -> void:
		if editor.unsaved and not _exit_armed:
			_exit_armed = true
			_exit_button.text = "UNSAVED CHANGES: PRESS AGAIN TO EXIT"
			return
		editor.exit_to_menu())
	v.add_child(_exit_button)


func _refresh_open_list() -> void:
	_open_pick.clear()
	for n in CustomMaps.list():
		_open_pick.add_item(n)
	_open_pick.disabled = _open_pick.item_count == 0


# ---------------------------------------------------------------- refresh

## The validation card: what stops the map from being played (CustomMaps.validate), or on a
## playable map the spots bots can't route to (MapEditor.bot_warnings), plus the marker counts.
func _refresh_checks() -> void:
	var problems := editor.problems()
	var counts := "Spawns %d · Pickups %d · Jump pads %d" % [editor.map.spawns.size(), editor.map.pickups.size(), editor.map.jump_pads.size()]
	if problems.is_empty():
		var notes := editor.bot_warnings()
		if notes.is_empty():
			_problems.text = "READY TO PLAY\n" + counts
			_problems.add_theme_color_override("font_color", UITheme.GOOD.lightened(0.2))
		else:
			var lines := notes.slice(0, 2)
			if notes.size() > 2:
				lines.append("... and %d more" % (notes.size() - 2))
			_problems.text = "READY TO PLAY (BOTS WILL STRUGGLE)\n" + "\n".join(lines) + "\n" + counts
			_problems.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	else:
		var lines := problems.slice(0, 4)
		if problems.size() > 4:
			lines.append("... and %d more" % (problems.size() - 4))
		_problems.text = "NOT PLAYABLE YET\n" + "\n".join(lines) + "\n" + counts
		_problems.add_theme_color_override("font_color", Color(1, 0.75, 0.6))


func refresh() -> void:
	if editor.map.is_empty():
		return
	var s: Vector3i = editor.grid.size
	var tool_text: String = MapEditor.TOOL_NAMES[editor.tool]
	if editor.tool == "block":
		tool_text += "  ·  %s  ·  BRUSH %d x %d" % [MapEditor.block_name(editor.block()).to_upper(), editor.brush, editor.brush]
	elif editor.tool == "pad":
		tool_text += "  ·  %s" % ("PLACE THE LANDING" if editor.pad_start != null else "PLACE THE PAD")
	_info.text = "%s%s  ·  %d x %d x %d\n%s" % [editor.map.name, " *" if editor.unsaved else "", s.x, s.z, s.y, tool_text]
	_keys.text = "LMB place · RMB remove · 1-9 / wheel block · Q / E tool · R brush\nWASD fly · Space / Ctrl up / down · Shift fast · Ctrl+Z / Ctrl+Y undo / redo · Ctrl+S save · Tab menu"
	_check_due = true
	for chip: PanelContainer in _tool_row.get_children():
		var t: String = chip.get_meta(&"tool")
		var on := t == editor.tool
		chip.add_theme_stylebox_override("panel", UITheme.chip_box(Color(MapEditor.TOOL_COLORS[t], 0.85) if on else Color(0, 0, 0, 0.5),
			Color(1, 1, 1, 0.5) if on else Color(1, 1, 1, 0.08), 10, 3))
		(chip.get_child(0) as Label).add_theme_color_override("font_color", Color(0.08, 0.08, 0.1) if on else UITheme.TEXT)
	for i in _hotbar.get_child_count():
		var cell := _hotbar.get_child(i) as PanelContainer
		var on: bool = i == editor.slot and editor.tool == "block"
		cell.add_theme_stylebox_override("panel", UITheme.round_box(Color(0, 0, 0, 0.55), UITheme.ACCENT if on else Color(1, 1, 1, 0.12), 3 if on else 1, 10, 6))
		(cell.get_child(0) as TextureRect).texture = BlockAtlas.icon(editor.hotbar[i], 3)
	if _panel.visible:
		if not _name_edit.has_focus():
			_name_edit.text = editor.map.name
		for b: Button in _sky_row.get_children():
			b.set_pressed_no_signal(b.get_meta(&"tod") == editor.map.time_of_day)
		for t: String in _tool_buttons:
			(_tool_buttons[t] as Button).set_pressed_no_signal(t == editor.tool)
		(_brush_row.get_child(0) as Button).set_pressed_no_signal(editor.brush == 1)
		(_brush_row.get_child(1) as Button).set_pressed_no_signal(editor.brush == 3)
		for b: int in _palette_buttons:
			(_palette_buttons[b] as Button).set_pressed_no_signal(b == editor.block())
		_undo_button.disabled = not editor.can_undo()
		_redo_button.disabled = not editor.can_redo()
	(_root.get_meta(&"crosshair") as Control).queue_redraw()
