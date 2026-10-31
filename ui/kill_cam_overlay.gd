class_name KillCamOverlay
extends CanvasLayer
## The kill cam's screen (owned by KillCam): letterbox bars, the KILLCAM banner with the killer's
## name (team colour and shape in team modes) and weapon, the skip key with a progress bar, and
## the scope mask while the killer aims a scoped gun. Canvas layer 9, under the Hud, whose kill
## feed, chat, scoreboard and pause menu stay on top.

var _killer: Label
var _skip: Label
var _bar: ProgressBar
var _scope: ScopeOverlay


func _ready() -> void:
	layer = 9
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	_scope = ScopeOverlay.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.visible = false
	root.add_child(_scope)
	var top := ColorRect.new()
	top.color = Color(0, 0, 0, 0.55)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = 96
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var bottom := ColorRect.new()
	bottom.color = Color(0, 0, 0, 0.55)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.custom_minimum_size.y = 64
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	head.grow_horizontal = Control.GROW_DIRECTION_BOTH
	head.position.y = 6
	head.add_theme_constant_override("separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	var title := _label("KILLCAM", 44, Color(1.0, 0.32, 0.26))
	head.add_child(title)
	_killer = _label("", 22, Color.WHITE)
	head.add_child(_killer)

	var foot := HBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	foot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.position.y -= 18
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 16)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(foot)
	_skip = _label("", 20, Color(1.0, 0.85, 0.3))
	foot.add_child(_skip)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(280, 6)
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.add_theme_stylebox_override("background", UITheme.bar_box(Color(1, 1, 1, 0.15), 3))
	_bar.add_theme_stylebox_override("fill", UITheme.bar_box(Color(1.0, 0.32, 0.26), 3))
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(_bar)
	Profile.device_changed.connect(_refresh_key)
	Profile.changed.connect(_refresh_key)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Shows the screen for a replay of `killer` (display text, coloured `color`) with `weapon`.
func show_for(killer: String, color: Color, weapon: String) -> void:
	_killer.text = "%s  ·  %s" % [killer, weapon]
	_killer.add_theme_color_override("font_color", color.lightened(0.25))
	_bar.value = 0.0
	_refresh_key()
	visible = true


func set_progress(fraction: float) -> void:
	_bar.value = fraction


func set_scope(on: bool, style: String) -> void:
	if on:
		_scope.style = style
	_scope.visible = on


func _refresh_key() -> void:
	_skip.text = "[%s]  SKIP" % Profile.key_text("skip_killcam")
