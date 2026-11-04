class_name StudioTimeline
extends Control
## Studio's timeline for a clip: the track with a tick every second, the trimmed part lit between
## its IN and OUT handles (the rest dimmed), the kill (red), the drone keyframes (gold) and the
## playhead. Click or drag anywhere to scrub (`seeked`); drag a handle to trim (`trim_changed`).
## Times run from 0 (the clip's first frame) to `length`.

signal seeked(t: float)
signal trim_changed(t_in: float, t_out: float)

## Shortest trim, in seconds.
const MIN_TRIM := 0.5
const HANDLE_GRAB := 10.0

var length := 1.0
var time := 0.0
var trim_in := 0.0
var trim_out := 1.0
## The kill's time (-1: none).
var kill_t := -1.0
var keys := PackedFloat32Array()

var _drag := ""


func _init() -> void:
	custom_minimum_size = Vector2(200, 46)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_state(t: float, t_in: float, t_out: float, key_times: PackedFloat32Array) -> void:
	time = t
	trim_in = t_in
	trim_out = t_out
	keys = key_times
	queue_redraw()


func _x(t: float) -> float:
	return 8.0 + (size.x - 16.0) * clampf(t / maxf(length, 0.001), 0.0, 1.0)


func _t(x: float) -> float:
	return clampf((x - 8.0) / maxf(size.x - 16.0, 1.0), 0.0, 1.0) * length


func _draw() -> void:
	var top := 8.0
	var h := size.y - 16.0
	var track := Rect2(8.0, top, size.x - 16.0, h)
	draw_rect(track, Color(0.08, 0.1, 0.16, 0.95))
	var lit := Rect2(_x(trim_in), top, _x(trim_out) - _x(trim_in), h)
	draw_rect(lit, Color(UITheme.ACCENT_2, 0.2))
	draw_rect(lit, Color(UITheme.ACCENT_2, 0.8), false, 2.0)
	for s in int(length) + 1:
		var x := _x(float(s))
		draw_line(Vector2(x, top + h - (10.0 if s % 5 == 0 else 5.0)), Vector2(x, top + h), Color(1, 1, 1, 0.35), 1.0)
	if kill_t >= 0.0:
		var kx := _x(kill_t)
		draw_line(Vector2(kx, top), Vector2(kx, top + h), Color(1.0, 0.35, 0.3), 2.0)
		draw_circle(Vector2(kx, top), 4.0, Color(1.0, 0.35, 0.3))
	for k in keys:
		var x := _x(k)
		draw_colored_polygon(PackedVector2Array([Vector2(x, top + h * 0.5 - 6), Vector2(x + 5, top + h * 0.5),
			Vector2(x, top + h * 0.5 + 6), Vector2(x - 5, top + h * 0.5)]), UITheme.ACCENT)
	for edge: float in [trim_in, trim_out]:
		var x := _x(edge)
		draw_rect(Rect2(x - 3.0, top - 4.0, 6.0, h + 8.0), UITheme.ACCENT_2)
	var px := _x(time)
	draw_line(Vector2(px, 2.0), Vector2(px, size.y - 2.0), Color.WHITE, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(px - 6, 0), Vector2(px + 6, 0), Vector2(px, 8)]), Color.WHITE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			_drag = ""
			return
		if absf(mb.position.x - _x(trim_in)) <= HANDLE_GRAB:
			_drag = "in"
		elif absf(mb.position.x - _x(trim_out)) <= HANDLE_GRAB:
			_drag = "out"
		else:
			_drag = "seek"
		_drag_to(mb.position.x)
		accept_event()
	elif event is InputEventMouseMotion and not _drag.is_empty():
		_drag_to((event as InputEventMouseMotion).position.x)
		accept_event()


func _drag_to(x: float) -> void:
	var t := _t(x)
	match _drag:
		"in":
			trim_in = minf(t, trim_out - MIN_TRIM)
			trim_in = maxf(trim_in, 0.0)
			trim_changed.emit(trim_in, trim_out)
		"out":
			trim_out = maxf(t, trim_in + MIN_TRIM)
			trim_out = minf(trim_out, length)
			trim_changed.emit(trim_in, trim_out)
		_:
			seeked.emit(t)
	queue_redraw()
