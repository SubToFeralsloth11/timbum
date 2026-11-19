class_name SeekOverlay
extends CanvasLayer
## The screen of the hide-and-seek modes (Tag, Hide and Seek, Block Hunt), above the Hud: a role
## card top left, a blindfold under the Hud while the local seeker counts, and Block Hunt's block
## picker and balloon bar at the bottom. The mode fills it every frame from its `overlay_state()`:
##   {title, lines: [String], color,                      the card ("" title: hidden)
##    blind, blind_sub,                                    the blindfold ("" blind: none)
##    choices: [block id], choice: index,                  the block picker (empty: hidden)
##    balloons: [[name, points, ready 0..1]], balloon: index}   the balloon bar (empty: hidden)

const DIM := Color(0.75, 0.8, 0.9)

var mode: Node
var _blind_layer: CanvasLayer
var _blind: ColorRect
var _blind_title: Label
var _blind_sub: Label
var _card: PanelContainer
var _title: Label
var _lines: Label
var _picker: HBoxContainer
var _picker_ids: Array = []
var _picker_choice := -1
var _balloon_bar: HBoxContainer
var _balloon_cards: Array[PanelContainer] = []
var _balloon_labels: Array[Label] = []
var _balloon_pick := -1
var _style_on: StyleBoxFlat
var _style_off: StyleBoxFlat


func setup(p_mode: Node) -> void:
	mode = p_mode


func _ready() -> void:
	layer = 11
	_style_on = UITheme.hud_card(0.75, 8, UITheme.CARD_RADIUS, Color(1.0, 0.85, 0.3, 0.95))
	_style_on.border_width_left = 3
	_style_on.border_width_right = 3
	_style_on.border_width_top = 3
	_style_on.border_width_bottom = 3
	_style_off = UITheme.hud_card(0.5, 8, UITheme.CARD_RADIUS)
	# The blindfold sits under the Hud (layer 10), so the clock and pause menu stay on top.
	_blind_layer = CanvasLayer.new()
	_blind_layer.layer = 9
	add_child(_blind_layer)
	_blind = ColorRect.new()
	_blind.color = Color(0.02, 0.02, 0.04, 0.97)
	_blind.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blind.visible = false
	_blind_layer.add_child(_blind)
	var bv := VBoxContainer.new()
	bv.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bv.grow_vertical = Control.GROW_DIRECTION_BOTH
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blind.add_child(bv)
	_blind_title = _label("", 46, Color.WHITE)
	_blind_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_blind_title)
	_blind_sub = _label("", 20, DIM)
	_blind_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_blind_sub)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.hud_card(0.5, 10))
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.position = Vector2(16, 40)
	_card.custom_minimum_size = Vector2(260, 0)
	_card.theme = UITheme.get_theme()
	add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_card.add_child(v)
	_title = _label("", 18, Color.WHITE)
	v.add_child(_title)
	_lines = _label("", 14, DIM)
	v.add_child(_lines)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -150
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.theme = UITheme.get_theme()
	add_child(bottom)
	_picker = HBoxContainer.new()
	_picker.alignment = BoxContainer.ALIGNMENT_CENTER
	_picker.add_theme_constant_override("separation", 10)
	bottom.add_child(_picker)
	_balloon_bar = HBoxContainer.new()
	_balloon_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_balloon_bar.add_theme_constant_override("separation", 10)
	bottom.add_child(_balloon_bar)
	for i in 3:
		var c := PanelContainer.new()
		c.add_theme_stylebox_override("panel", _style_off)
		c.custom_minimum_size = Vector2(118, 0)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_balloon_bar.add_child(c)
		var l := _label("", 14, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(l)
		_balloon_cards.append(c)
		_balloon_labels.append(l)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	var over: bool = mode.world.match_over
	var s: Dictionary = {} if over else mode.overlay_state()
	var title := str(s.get("title", ""))
	_card.visible = not title.is_empty()
	if _card.visible:
		_title.text = title
		_title.add_theme_color_override("font_color", s.get("color", Color.WHITE))
		_lines.text = "\n".join(s.get("lines", []))
	var blind := str(s.get("blind", ""))
	_blind.visible = not blind.is_empty()
	if _blind.visible:
		_blind_title.text = blind
		_blind_sub.text = str(s.get("blind_sub", ""))
	_show_picker(s.get("choices", []), int(s.get("choice", -1)))
	_show_balloons(s.get("balloons", []), int(s.get("balloon", -1)))


## The block picker: one card per choice (icon, name, key), the picked one outlined.
func _show_picker(ids: Array, choice: int) -> void:
	_picker.visible = not ids.is_empty()
	if ids.is_empty():
		return
	if ids != _picker_ids:
		_picker_ids = ids.duplicate()
		_picker_choice = -1
		for c in _picker.get_children():
			c.queue_free()
		for i in ids.size():
			var card := PanelContainer.new()
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_theme_stylebox_override("panel", _style_off)
			_picker.add_child(card)
			var cv := VBoxContainer.new()
			cv.alignment = BoxContainer.ALIGNMENT_CENTER
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(cv)
			var icon := TextureRect.new()
			icon.texture = BlockAtlas.icon(int(ids[i]), 4)
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.custom_minimum_size = Vector2(64, 64)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(icon)
			var name_label := _label(BlockHunt.block_name(int(ids[i])), 13, Color.WHITE)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cv.add_child(name_label)
			var key := _label("[%d]" % (i + 1), 12, DIM)
			key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cv.add_child(key)
	if choice != _picker_choice:
		_picker_choice = choice
		for i in _picker.get_child_count():
			(_picker.get_child(i) as PanelContainer).add_theme_stylebox_override("panel", _style_on if i == choice else _style_off)


## The balloon bar: each size with its points, ready or the cooldown still to go.
func _show_balloons(sizes: Array, pick: int) -> void:
	_balloon_bar.visible = not sizes.is_empty()
	if sizes.is_empty():
		return
	for i in mini(3, sizes.size()):
		var b: Array = sizes[i]
		var ready := float(b[2]) >= 1.0
		_balloon_labels[i].text = "[%d] %s  +%d\n%s" % [i + 1, str(b[0]), int(b[1]), "READY" if ready else "%d%%" % int(float(b[2]) * 100.0)]
		_balloon_cards[i].modulate = Color.WHITE if ready else Color(1, 1, 1, 0.55)
	if pick != _balloon_pick:
		_balloon_pick = pick
		for i in 3:
			_balloon_cards[i].add_theme_stylebox_override("panel", _style_on if i == pick else _style_off)
