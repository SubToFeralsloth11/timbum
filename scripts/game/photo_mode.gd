class_name PhotoMode
extends CanvasLayer
## Photo mode, World's child "PhotoMode" (`World.photo`), offline matches only (online the match
## can't freeze, so the pause menu hides the button and `photo_mode` does nothing). Opened from
## the pause menu or with `photo_mode` (P / Share): the match freezes (World.set_frozen), every
## other canvas layer (Hud, overlays) and the nametags hide, the local player's first-person
## viewmodel hides and their body shows, and a FreeCam starts at the current view. It flies with
## the player's bindings (FreeCam) plus a roll (lean keys, LB / RB) and a speed scale; the panel
## on the right sets the field of view, speed and roll, picks a filter (PostProcess.FILTER_NAMES:
## none, colour grade, black and white, sepia) and takes the photo: the panel hides for two
## drawn frames, the viewport image is saved as `user://screenshots/timbum_<date>_<time>.png`
## (`_2`, `_3`... if taken within the same second) and its full path shows with an OPEN FOLDER
## button. Esc / B (pause, ui_cancel) closes it: filter back to none, the previous camera, layers,
## nametags and viewmodel restored, and the pause menu comes back (`closed`).
## Keyboard and mouse: hold the right mouse button to look, the wheel zooms (FOV), R the next
## filter, Enter takes the photo; the panel's controls take clicks. Controller: the panel has no
## focus (the sticks fly the camera); A takes the photo, X the next filter, Y opens the folder,
## D-pad left / right zoom, D-pad up / down change the speed, RT / LT rise / sink, LB / RB roll.

signal closed
## A photo was saved (checks): its path and size.
signal photo_taken(path: String, size: Vector2i)

const DIR := "user://screenshots"
const FOV_MIN := 20.0
const FOV_MAX := 110.0
const FOV_STEP := 5.0
const SPEED_MIN := 0.25
const SPEED_MAX := 4.0

var world: World
## The last photo's user:// path ("" before the first).
var last_path := ""

var _open := false
var _busy := false
var _cam: FreeCam
var _prev_cam: Camera3D
var _hidden_layers: Array[CanvasLayer] = []
var _hidden_tags: Array[Label3D] = []
## The local player's look changed for the photos (body shown, viewmodel hidden), to put back.
var _player_changed: Player
var _looking := false

var _root: Control
var _panel: PanelContainer
var _fov: HSlider
var _fov_value: Label
var _speed: HSlider
var _speed_value: Label
var _roll: HSlider
var _roll_value: Label
var _filters: Array[Button] = []
var _path_label: Label
var _open_folder: Button
var _keys: Label


func _init() -> void:
	name = "PhotoMode"


func _ready() -> void:
	layer = 20
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cam = FreeCam.new()
	_cam.name = "PhotoCam"
	_cam.allow_roll = true
	_cam.fly_when_paused = true
	_cam.set_bounds(world.map_info.bounds)
	add_child(_cam)
	_build_ui()
	Profile.device_changed.connect(_refresh_keys)


## Whether photo mode may open now: offline, in a running match, no kill cam replay on screen.
func can_open() -> bool:
	return Net.offline and not _open and not world.match_over and not world.killcam.is_playing()


func is_open() -> bool:
	return _open


func camera() -> FreeCam:
	return _cam


func open() -> void:
	if not can_open():
		return
	_open = true
	world.set_frozen(true)
	_prev_cam = get_viewport().get_camera_3d()
	var from := _prev_cam.global_transform if _prev_cam != null else Transform3D(Basis.IDENTITY, world.map_info.bounds.get_center())
	_cam.speed_scale = 1.0
	_cam.place(from, _prev_cam.fov if _prev_cam != null else float(Profile.get_setting("fov")))
	_cam.make_current()
	_cam.active = true
	for node: Node in world.find_children("*", "CanvasLayer", true, false):
		var l := node as CanvasLayer
		if l != self and not (l is PostProcess) and l.visible:
			l.visible = false
			_hidden_layers.append(l)
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if p.nametag != null and p.nametag.visible:
			p.nametag.visible = false
			_hidden_tags.append(p.nametag)
	var me := world.local_player
	if me != null and me.alive and me.viewmodel != null and me.viewmodel.visible:
		me.viewmodel.visible = false
		me.avatar.set_first_person(false)
		_player_changed = me
	world.spectator.set_photo(true)
	_refresh_lasers()
	_set_filter(0)
	_fov.set_value_no_signal(_cam.fov)
	_speed.set_value_no_signal(1.0)
	_path_label.text = "Photos go to %s" % ProjectSettings.globalize_path(DIR)
	_open_folder.disabled = false
	_refresh_keys()
	_root.visible = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Back to the pause menu with the view as it was.
func close() -> void:
	if not _open:
		return
	_open = false
	_looking = false
	visible = false
	_cam.active = false
	_set_filter(0)
	for l in _hidden_layers:
		if is_instance_valid(l):
			l.visible = true
	_hidden_layers.clear()
	for tag in _hidden_tags:
		if is_instance_valid(tag):
			tag.visible = true
	_hidden_tags.clear()
	if is_instance_valid(_player_changed) and _player_changed.alive:
		_player_changed.viewmodel.visible = true
		_player_changed.avatar.set_first_person(true)
	_player_changed = null
	world.spectator.set_photo(false)
	if is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	_prev_cam = null
	_refresh_lasers()
	closed.emit()


## The match is frozen, so re-aim every Laser Sight beam now: the local player's leaves their
## body's gun while photo mode shows it, their viewmodel's again afterwards.
func _refresh_lasers() -> void:
	for eid: int in world.entities:
		(world.entities[eid] as Player).update_laser()


## Saves what the camera sees (without this panel) and returns the user:// path ("" on failure).
func take_photo() -> String:
	if not _open or _busy:
		return ""
	# No renderer draws frames (headless): there is no image to save.
	if DisplayServer.get_name() == "headless":
		_path_label.text = "Couldn't capture the screen (no display)."
		return ""
	_busy = true
	_root.visible = false
	# The first frame after hiding may already be in flight; the second surely has no panel.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_root.visible = true
	_busy = false
	if img == null or img.is_empty():
		_path_label.text = "Couldn't capture the screen."
		Sfx.play(&"ui_error")
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := photo_path()
	var err := img.save_png(path)
	if err != OK:
		_path_label.text = "Couldn't save the photo (%s)." % error_string(err)
		Sfx.play(&"ui_error")
		return ""
	last_path = path
	_path_label.text = "Saved %s" % ProjectSettings.globalize_path(path)
	Sfx.play(&"ui_buy")
	photo_taken.emit(path, img.get_size())
	return path


## user://screenshots/timbum_<YYYY-MM-DD>_<HH-MM-SS>.png, numbered if that name is taken.
static func photo_path() -> String:
	var d := Time.get_datetime_dict_from_system()
	var base := "%s/timbum_%04d-%02d-%02d_%02d-%02d-%02d" % [DIR, d.year, d.month, d.day, d.hour, d.minute, d.second]
	var path := base + ".png"
	var n := 2
	while FileAccess.file_exists(path):
		path = "%s_%d.png" % [base, n]
		n += 1
	return path


func set_filter(index: int) -> void:
	_set_filter(index)


func _set_filter(index: int) -> void:
	var post := world.get_node_or_null(^"PostProcess") as PostProcess
	if post != null:
		post.set_filter(index)
	for i in _filters.size():
		_filters[i].set_pressed_no_signal(i == index)


func filter() -> int:
	var post := world.get_node_or_null(^"PostProcess") as PostProcess
	return post.filter if post != null else 0


func _open_screenshots() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	if last_path.is_empty():
		OS.shell_open(dir)
	else:
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(last_path))


func _set_fov(v: float) -> void:
	_cam.fov = clampf(v, FOV_MIN, FOV_MAX)
	_fov.set_value_no_signal(_cam.fov)


func _set_speed(v: float) -> void:
	_cam.speed_scale = clampf(v, SPEED_MIN, SPEED_MAX)
	_speed.set_value_no_signal(_cam.speed_scale)


func _process(_delta: float) -> void:
	if not _open:
		return
	# Controller triggers rise / sink and bumpers roll (keyboard: jump / crouch, lean keys).
	if Profile.using_pad:
		_cam.up_input = Input.get_action_strength("fire") - Input.get_action_strength("aim")
		_cam.roll_input = Input.get_action_strength("grenade") - Input.get_action_strength("tactical")
	else:
		_cam.up_input = 0.0
		_cam.roll_input = 0.0
	_cam.active = not _busy
	_fov_value.text = "%d°" % roundi(_cam.fov)
	_speed_value.text = "%.2fx" % _cam.speed_scale
	_roll.set_value_no_signal(rad_to_deg(-_cam.roll))
	_roll_value.text = "%d°" % roundi(rad_to_deg(-_cam.roll))


func _over_panel() -> bool:
	return _panel.get_global_rect().has_point(_panel.get_global_mouse_position())


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	if _busy:
		return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		match jb.button_index:
			JOY_BUTTON_A: take_photo()
			JOY_BUTTON_X: _set_filter((filter() + 1) % PostProcess.FILTER_NAMES.size())
			JOY_BUTTON_Y: _open_screenshots()
			JOY_BUTTON_DPAD_LEFT: _set_fov(_cam.fov - FOV_STEP)
			JOY_BUTTON_DPAD_RIGHT: _set_fov(_cam.fov + FOV_STEP)
			JOY_BUTTON_DPAD_UP: _set_speed(_cam.speed_scale * 1.5)
			JOY_BUTTON_DPAD_DOWN: _set_speed(_cam.speed_scale / 1.5)
			_: return
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed and not _over_panel():
				_looking = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif not mb.pressed and _looking:
				_looking = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and not _over_panel() and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_set_fov(_cam.fov + (-FOV_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else FOV_STEP) * 0.5)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if _looking:
			_cam.look_mouse((event as InputEventMouseMotion).relative)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_ENTER or key == KEY_KP_ENTER:
			take_photo()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("reload"):
			_set_filter((filter() + 1) % PostProcess.FILTER_NAMES.size())
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _open or not event.is_action_pressed("photo_mode"):
		return
	if can_open() and not world.hud.is_chatting():
		get_viewport().set_input_as_handled()
		world.hud.open_photo()


# ---------------------------------------------------------------- panel

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_panel = UIKit.panel()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.position.x -= 24
	_panel.custom_minimum_size.x = 340
	_root.add_child(_panel)
	var v := UIKit.vbox(10)
	_panel.add_child(v)
	v.add_child(UIKit.label("PHOTO MODE", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(HSeparator.new())
	_fov = _slider(v, "FIELD OF VIEW", FOV_MIN, FOV_MAX, 1.0, _set_fov)
	_fov_value = _fov.get_meta(&"value")
	_speed = _slider(v, "CAMERA SPEED", SPEED_MIN, SPEED_MAX, 0.05, _set_speed)
	_speed_value = _speed.get_meta(&"value")
	_roll = _slider(v, "ROLL", -60.0, 60.0, 1.0, func(d: float) -> void: _cam.roll = deg_to_rad(-d))
	_roll_value = _roll.get_meta(&"value")
	v.add_child(UIKit.label("FILTER", &"SmallLabel"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var group := ButtonGroup.new()
	for i in PostProcess.FILTER_NAMES.size():
		var b := UIKit.button(PostProcess.FILTER_NAMES[i].to_upper())
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_filter.bind(i))
		grid.add_child(b)
		_filters.append(b)
	v.add_child(HSeparator.new())
	var take := UIKit.button("TAKE PHOTO", &"PrimaryButton")
	take.focus_mode = Control.FOCUS_NONE
	take.custom_minimum_size.y = 52
	take.pressed.connect(take_photo)
	v.add_child(take)
	_path_label = UIKit.label("", &"SmallLabel")
	_path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_path_label.custom_minimum_size.x = 300
	v.add_child(_path_label)
	var row := UIKit.hbox(8)
	v.add_child(row)
	_open_folder = UIKit.button("OPEN FOLDER")
	_open_folder.focus_mode = Control.FOCUS_NONE
	_open_folder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_folder.pressed.connect(_open_screenshots)
	row.add_child(_open_folder)
	var back := UIKit.button("BACK", &"DangerButton")
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(close)
	row.add_child(back)
	_keys = UIKit.label("", &"SmallLabel")
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keys.custom_minimum_size.x = 300
	_keys.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	v.add_child(_keys)


func _slider(parent: Control, title: String, lo: float, hi: float, step: float, on_change: Callable) -> HSlider:
	var head := UIKit.hbox(8)
	parent.add_child(head)
	var t := UIKit.label(title, &"SmallLabel")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var value := UIKit.label("", &"SmallLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(value)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(on_change)
	s.set_meta(&"value", value)
	parent.add_child(s)
	return s


func _refresh_keys() -> void:
	if _keys == null:
		return
	if Profile.using_pad:
		_keys.text = "LEFT STICK fly  ·  RIGHT STICK look  ·  RT / LT up / down  ·  %s fast  ·  LB / RB roll  ·  D-PAD ← → zoom  ·  D-PAD ↑ ↓ speed  ·  X filter  ·  A take photo  ·  Y open folder  ·  B back" \
			% Profile.key_text("sprint")
	else:
		var k := Profile.key_text
		_keys.text = "%s%s%s%s fly  ·  hold RIGHT MOUSE to look  ·  %s / %s up / down  ·  %s fast  ·  %s / %s roll  ·  WHEEL zoom  ·  %s filter  ·  ENTER take photo  ·  ESC back" % [
			k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right"),
			k.call("jump"), k.call("crouch"), k.call("sprint"), k.call("lean_left"), k.call("lean_right"), k.call("reload")]
