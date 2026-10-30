class_name TutorialCard
extends CanvasLayer
## The tutorial's card (canvas layer 11, top centre): the step number and title, the prompt with
## the player's own keys or controller buttons (Tutorial.prompt, refreshed every frame), a bar
## for steps that take a while (walk 4 m, sprint 1 s), a ✓ when a step is done, and how to skip.
## During the grapple step a marker points at the ledge. At the end it says the tutorial is
## complete and whether the coin bonus was paid.

## Draws the ledge marker where it is in the world.
class MarkerLayer extends Control:
	var tutorial: Tutorial

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or tutorial.step_id() != "grapple" or not tutorial.world.map_info.marks.has("ledge"):
			return
		var ledge: AABB = tutorial.world.map_info.marks.ledge
		var pos := ledge.get_center() + Vector3.UP * 0.6
		if cam.is_position_behind(pos):
			return
		var at := cam.unproject_position(pos)
		var col := Color(1.0, 0.82, 0.25)
		var d := 14.0
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0)]), Color(col, 0.85))
		draw_polyline(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0), at + Vector2(0, -d)]), Color(0, 0, 0, 0.8), 2.0)
		var font := get_theme_default_font()
		var text := "GRAPPLE HERE  %dm" % roundi(cam.global_position.distance_to(pos))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var tp := at + Vector2(-w * 0.5, 34)
		draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.9))
		draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)

var tutorial: Tutorial
var _card: PanelContainer
var _step: Label
var _title: Label
var _prompt: Label
var _bar: ProgressBar
var _skip: Label
var _markers: MarkerLayer


func setup(p_tutorial: Tutorial) -> void:
	tutorial = p_tutorial


func _ready() -> void:
	layer = 11
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	_markers = MarkerLayer.new()
	_markers.tutorial = tutorial
	root.add_child(_markers)
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.78)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(14)
	sb.border_color = Color(1, 0.82, 0.25, 0.6)
	sb.set_border_width_all(2)
	_card.add_theme_stylebox_override("panel", sb)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 44
	_card.custom_minimum_size = Vector2(560, 0)
	root.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_card.add_child(v)
	_step = _label("", 14, Color(1, 0.82, 0.25))
	v.add_child(_step)
	_title = _label("", 30)
	v.add_child(_title)
	_prompt = _label("", 20, Color(0.88, 0.92, 1.0))
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size.x = 530
	v.add_child(_prompt)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 0.82, 0.25)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fill)
	v.add_child(_bar)
	_skip = _label("", 13, Color(0.7, 0.75, 0.85))
	v.add_child(_skip)


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	var w := tutorial.world
	_card.visible = w.local_player != null and not (w.photo != null and w.photo.is_open())
	_markers.visible = _card.visible
	_markers.queue_redraw()
	if not _card.visible:
		return
	if tutorial.finished:
		_step.text = "TUTORIAL"
		_title.text = "TUTORIAL COMPLETE"
		_title.self_modulate = Color(0.6, 1.0, 0.6)
		_prompt.text = ("+%d coins for finishing. " % tutorial.reward if tutorial.reward > 0 else "Replay: the coin bonus was paid the first time. ") \
			+ "Stay and practise on the range, or leave from the pause menu."
		_bar.visible = false
		_skip.text = "[%s] pause menu" % Profile.key_text("pause")
		return
	var done := tutorial.done_left >= 0.0
	_step.text = "TUTORIAL  ·  STEP %d / %d" % [tutorial.step + 1, Tutorial.STEPS.size()]
	_title.text = ("✓  " if done else "") + tutorial.step_title()
	_title.self_modulate = Color(0.6, 1.0, 0.6) if done else Color.WHITE
	_prompt.text = "Nice!" if done else tutorial.prompt()
	_bar.visible = tutorial.step_id() in ["move", "look", "sprint", "crouch", "peek_left", "peek_right", "aim"]
	_bar.value = tutorial.progress
	_skip.text = "[%s] pause menu: skip this step or the tutorial" % Profile.key_text("pause")
