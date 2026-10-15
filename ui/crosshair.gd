class_name Crosshair
extends Control
## Dynamic crosshair whose gap matches the real spread cone, plus hitmarkers.

var spread := 1.0
var fov := 85.0
var color := Color.WHITE
## False while aiming down sights: the lines and dot hide, but hitmarkers still draw.
var show_lines := true
var _hit_t := 0.0
var _hit_color := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func hit(head: bool, killed: bool) -> void:
	_hit_t = 0.28 if killed else 0.18
	_hit_color = Color(1, 0.25, 0.2) if killed else (Color(1, 0.8, 0.2) if head else Color.WHITE)


func _process(delta: float) -> void:
	if _hit_t > 0.0:
		_hit_t -= delta
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	if show_lines:
		_draw_lines(c)
	if _hit_t > 0.0:
		var k := clampf(_hit_t / 0.18, 0.0, 1.0)
		var hc := _hit_color
		hc.a = k
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn := d.normalized()
			draw_line(c + dn * 8.0, c + dn * 18.0, hc, 3.0)


func _draw_lines(c: Vector2) -> void:
	var half_h := size.y * 0.5
	var gap := tan(deg_to_rad(spread)) / tan(deg_to_rad(fov) * 0.5) * half_h + 4.0
	gap = clampf(gap, 4.0, size.y * 0.25)
	var len := 9.0
	var shadow := Color(0, 0, 0, 0.6)
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var a := c + d * gap
		var b := c + d * (gap + len)
		draw_line(a, b, shadow, 4.0)
		draw_line(a, b, color, 2.0)
	draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), shadow)
	draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), color)
