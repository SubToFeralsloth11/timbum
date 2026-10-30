class_name PauseMenu
extends Control
## In-match pause overlay. Offline matches freeze while it is open (the HUD calls
## World.set_frozen, and this node runs with PROCESS_MODE_ALWAYS); online the match keeps
## running. The HUD owner shows/hides it (`visible`, or `open()` / `close()`) and listens to
## `resume_requested`. Becoming visible frees the mouse, resets to the main panel and
## animates in. While visible it consumes "pause" / "ui_cancel" in `_input` (it is a
## child of the HUD, so it sees Esc first): Esc closes the settings sub-panel, or
## requests resume. `configure(world)` (before showing) sets the match buttons: SPECTATE / PLAY
## (offline SPECTATE BOTS / PLAY; `spectate_requested`) and PHOTO MODE (offline only, not during
## a kill cam replay or the results; `photo_requested`). In a practice session (Firing Range,
## tutorial) there is no spectating, the mode's own buttons (`MatchMode.pause_actions`, e.g. RESET
## READOUT, SKIP STEP) sit above SETTINGS, and LEAVE MATCH reads LEAVE.

signal resume_requested
## SPECTATE (`on`) or PLAY.
signal spectate_requested(on: bool)
signal photo_requested

var _dim: ColorRect
var _menu: PanelContainer
var _settings: SettingsPanel
var _resume_button: Button
var _settings_button: Button
var _spectate_button: Button
var _photo_button: Button
## The spectate button's request: true = spectate, false = play.
var _spectate_on := true
var _hint: Label
## Host of an online match: how friends can join (room code, Wi-Fi, Steam invite).
var _invite: InviteBox
## The mode's own buttons (MatchMode.pause_actions), rebuilt by configure().
var _actions: VBoxContainer
var _leave_button: Button


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
	_menu.custom_minimum_size = Vector2(420, 0)
	center.add_child(_menu)
	var v := UIKit.vbox(12)
	_menu.add_child(v)
	v.add_child(UIKit.label("PAUSED", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	_hint = UIKit.label("", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_hint)
	v.add_child(HSeparator.new())
	_invite = InviteBox.new()
	v.add_child(_invite)
	_resume_button = UIKit.button("RESUME", &"PrimaryButton")
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	v.add_child(_resume_button)
	_spectate_button = UIKit.button("SPECTATE")
	_spectate_button.pressed.connect(func() -> void: spectate_requested.emit(_spectate_on))
	v.add_child(_spectate_button)
	_photo_button = UIKit.button("PHOTO MODE")
	_photo_button.pressed.connect(func() -> void: photo_requested.emit())
	v.add_child(_photo_button)
	_actions = UIKit.vbox(12)
	v.add_child(_actions)
	_settings_button = UIKit.button("SETTINGS")
	_settings_button.pressed.connect(_open_settings)
	v.add_child(_settings_button)
	_leave_button = UIKit.button("LEAVE MATCH", &"DangerButton")
	_leave_button.pressed.connect(func() -> void: Net.leave())
	v.add_child(_leave_button)

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	center.add_child(_settings)
	visibility_changed.connect(_on_visibility_changed)


func open() -> void:
	visible = true


## Match state for the buttons, read each time the menu opens.
func configure(world: World) -> void:
	_spectate_on = not Net.is_spectator(world.my_id())
	var key := Profile.key_text("photo_mode")
	if Net.offline:
		_spectate_button.text = "SPECTATE BOTS" if _spectate_on else "PLAY"
	else:
		_spectate_button.text = "SPECTATE" if _spectate_on else "PLAY"
	_spectate_button.visible = not world.match_over and not world.rules.is_practice()
	_photo_button.text = "PHOTO MODE  [%s]" % key
	_photo_button.visible = world.photo.can_open()
	_leave_button.text = "LEAVE" if world.rules.is_practice() else "LEAVE MATCH"
	for c in _actions.get_children():
		c.queue_free()
	for a: Array in world.rules.pause_actions():
		var b := UIKit.button(str(a[0]))
		var action: Callable = a[1]
		b.pressed.connect(func() -> void:
			resume_requested.emit()
			action.call())
		_actions.add_child(b)
	_actions.visible = not world.rules.pause_actions().is_empty()


func close() -> void:
	visible = false


func _on_visibility_changed() -> void:
	if not visible:
		if _settings.visible:
			_settings.close()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hint.text = "The match is paused." if Net.offline else "The match keeps running."
	_invite.refresh()
	_settings.visible = false
	_menu.visible = true
	_animate_in(_menu)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_resume_button.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if not visible:
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
	_settings.focus_first.call_deferred()


func _close_settings() -> void:
	if not _settings.visible and _menu.visible:
		return
	_settings.visible = false
	_menu.visible = true
	_animate_in(_menu)
	_settings_button.grab_focus.call_deferred()


func _animate_in(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.94, 0.94)
	c.modulate.a = 0.0
	var t := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE, 0.22)
	t.tween_property(c, "modulate:a", 1.0, 0.15)
