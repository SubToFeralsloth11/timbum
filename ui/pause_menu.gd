class_name PauseMenu
extends Control
## In-match pause overlay. Does not pause the tree (the match keeps running).
## The HUD owner calls `open()` / `close()` and listens to `resume_requested`.
## While visible it consumes the "pause" / "ui_cancel" key itself (in `_input`):
## Esc closes the settings sub-panel, or requests resume.

signal resume_requested

var _dim: ColorRect
var _menu: PanelContainer
var _settings: SettingsPanel
var _resume_button: Button
var _tween: Tween


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.015, 0.03, 0.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_menu = UIKit.panel()
	_menu.custom_minimum_size = Vector2(360, 0)
	center.add_child(_menu)
	var v := UIKit.vbox(12)
	_menu.add_child(v)
	v.add_child(UIKit.label("PAUSED", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var hint := UIKit.label("The match keeps running.", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(hint)
	v.add_child(HSeparator.new())
	_resume_button = UIKit.button("RESUME", &"PrimaryButton")
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	v.add_child(_resume_button)
	var settings_button := UIKit.button("SETTINGS")
	settings_button.pressed.connect(_open_settings)
	v.add_child(settings_button)
	var leave := UIKit.button("LEAVE MATCH", &"DangerButton")
	leave.pressed.connect(func() -> void: Net.leave())
	v.add_child(leave)

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	center.add_child(_settings)


## Shows the menu with a short fade and frees the mouse.
func open() -> void:
	if visible:
		return
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_close_settings()
	_animate_in(_menu)
	modulate.a = 0.0
	_restart_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_resume_button.grab_focus.call_deferred()


## Hides the menu. Mouse capture is left to the caller.
func close() -> void:
	if not visible:
		return
	if _settings.visible:
		_settings.close()
	var t := _restart_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.1)
	t.tween_callback(hide)


func _input(event: InputEvent) -> void:
	if not visible or modulate.a < 0.99:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _settings.visible:
			_settings.close()
		else:
			resume_requested.emit()


func _open_settings() -> void:
	_menu.visible = false
	_settings.visible = true
	_settings.refresh()
	_animate_in(_settings)


func _close_settings() -> void:
	if not _settings.visible and _menu.visible:
		return
	_settings.visible = false
	_menu.visible = true
	_animate_in(_menu)


func _animate_in(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.94, 0.94)
	c.modulate.a = 0.0
	var t := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE, 0.22)
	t.tween_property(c, "modulate:a", 1.0, 0.15)


func _restart_tween() -> Tween:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	return _tween
