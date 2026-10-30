class_name Crosshair
extends Control
## The crosshair the player designs in Settings > Crosshair (style, size, gap, thickness, outline,
## centre dot, dynamic spread, colour, opacity), plus hitmarkers. With dynamic spread on, the gap
## matches the real spread cone; off, it stays at the set gap. The defaults draw the original
## crosshair: four 9 px lines, 2 px thick with a dark outline, 4 px gap, a 2 px centre dot.

const STYLE_NAMES: Array[String] = ["Cross", "Dot", "Circle", "T"]
enum { CROSS, DOT, CIRCLE, T }
const OUTLINE_ALPHA := 0.6

var spread := 1.0
var fov := 85.0
## False while aiming down sights: the lines and dot hide, but hitmarkers still draw.
var show_lines := true
## Half the height the spread cone is measured against; 0 uses this control's own height (the HUD
## fills the screen). The settings preview sets the game screen's, so its gap matches a match.
var view_half_height := 0.0
var style := CROSS
var line_length := 9.0
var gap := 4.0
var thickness := 2.0
var outline := true
var center_dot := true
var dynamic := true
var color := Color.WHITE
## The gap last drawn (pixels from the centre to the inner end of a line).
var drawn_gap := 0.0
var _hit_t := 0.0
var _hit_kill := false
var _hit_color := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_style()


## Reads the style from Profile (call when the settings change).
func load_style() -> void:
	style = clampi(int(Profile.get_setting("crosshair_style")), 0, STYLE_NAMES.size() - 1)
	line_length = float(Profile.get_setting("crosshair_size"))
	gap = float(Profile.get_setting("crosshair_gap"))
	thickness = float(Profile.get_setting("crosshair_thickness"))
	outline = bool(Profile.get_setting("crosshair_outline"))
	center_dot = bool(Profile.get_setting("crosshair_dot"))
	dynamic = bool(Profile.get_setting("crosshair_dynamic"))
	var html := str(Profile.get_setting("crosshair_color"))
	color = Color.html(html) if Color.html_is_valid(html) else Color.WHITE
	color.a = clampf(float(Profile.get_setting("crosshair_opacity")), 0.0, 1.0)
	queue_redraw()


## Hitmarker in the colour mode's hit / headshot / kill colour (Palette); a kill's marker is also
## bigger and thicker, so it doesn't rely on colour alone.
func hit(head: bool, killed: bool) -> void:
	_hit_t = 0.28 if killed else 0.18
	_hit_kill = killed
	_hit_color = Palette.color("hit_kill" if killed else ("hit_head" if head else "hit"))


func _process(delta: float) -> void:
	if _hit_t > 0.0:
		_hit_t -= delta
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	if show_lines:
		_draw_crosshair(c)
	if _hit_t > 0.0:
		var k := clampf(_hit_t / 0.18, 0.0, 1.0)
		var hc := _hit_color
		hc.a = k
		var reach := 24.0 if _hit_kill else 18.0
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn := d.normalized()
			draw_line(c + dn * 8.0, c + dn * reach, hc, 4.0 if _hit_kill else 3.0)


## Pixels from the centre to where the lines start: the set gap, plus (dynamic spread) the spread
## cone's edge on screen, capped at a quarter of the screen height.
func current_gap() -> float:
	var half_h := view_half_height if view_half_height > 0.0 else size.y * 0.5
	if not dynamic:
		return gap
	var g := tan(deg_to_rad(spread)) / tan(deg_to_rad(fov) * 0.5) * half_h + gap
	return clampf(g, gap, maxf(gap, half_h * 0.5))


func _draw_crosshair(c: Vector2) -> void:
	drawn_gap = current_gap()
	var shadow := Color(0, 0, 0, OUTLINE_ALPHA * color.a)
	match style:
		DOT:
			var r := maxf(line_length * 0.3, 1.0)
			if outline:
				draw_circle(c, r + 1.0, shadow)
			draw_circle(c, r, color)
			return
		CIRCLE:
			var radius := drawn_gap + line_length * 0.5
			if outline:
				draw_arc(c, radius, 0.0, TAU, 48, shadow, thickness + 2.0, true)
			draw_arc(c, radius, 0.0, TAU, 48, color, thickness, true)
		_:
			var dirs: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]
			if style == CROSS:
				dirs.append(Vector2.UP)
			if outline:
				for d in dirs:
					draw_line(c + d * drawn_gap, c + d * (drawn_gap + line_length), shadow, thickness + 2.0)
			for d in dirs:
				draw_line(c + d * drawn_gap, c + d * (drawn_gap + line_length), color, thickness)
	if center_dot:
		var h := thickness * 0.5
		if outline:
			draw_rect(Rect2(c - Vector2(h + 0.5, h + 0.5), Vector2(thickness + 1.0, thickness + 1.0)), shadow)
		draw_rect(Rect2(c - Vector2(h, h), Vector2(thickness, thickness)), color)
