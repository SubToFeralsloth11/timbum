class_name BlockTitle
extends Control
## The "TIMBUM" logo: a small isometric voxel cube emblem beside the word in a heavy rounded
## font, with a stacked extrusion, a dark rim and a warm gold gradient face (a canvas shader
## turns the pure-white face pass into the gradient). Letters bob gently on their own phases.

const FACE_TOP := Color("fff1a8")
const FACE_BOTTOM := Color("ff9f1c")
const SIDE := Color("b4440f")
const RIM := Color("2a1206")
const DEPTH := 5
const FACE_SHADER := """
shader_type canvas_item;
uniform vec4 top_color : source_color;
uniform vec4 bottom_color : source_color;
uniform float top_y;
uniform float bottom_y;
varying float local_y;
void vertex() {
	local_y = VERTEX.y;
}
void fragment() {
	vec4 c = COLOR;
	// Only the pure-white face pass gets the gradient; rim, sides and the emblem keep their colours.
	if (c.r > 0.995 && c.g > 0.995 && c.b > 0.995) {
		float t = clamp((local_y - top_y) / max(bottom_y - top_y, 1.0), 0.0, 1.0);
		c.rgb = mix(top_color.rgb, bottom_color.rgb, t);
	}
	COLOR = c;
}
"""

@export var text := "TIMBUM"
@export var font_size := 72
@export var bob_height := 3.0

var _time := 0.0
var _font: SystemFont
var _mat: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Arial Rounded MT Bold", "Nunito Black", "Arial Black", "Helvetica Neue", "sans-serif"])
	_font.font_weight = 900
	_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var shader := Shader.new()
	shader.code = FACE_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("top_color", FACE_TOP)
	_mat.set_shader_parameter("bottom_color", FACE_BOTTOM)
	material = _mat
	custom_minimum_size = _content_size()


func _emblem_size() -> float:
	return font_size * 0.78


func _content_size() -> Vector2:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return Vector2(_emblem_size() + font_size * 0.22 + w + DEPTH + 8, font_size * 1.05 + DEPTH + bob_height * 2 + 8)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var asc := _font.get_ascent(font_size)
	var base_y := bob_height + 4 + asc
	_mat.set_shader_parameter("top_y", base_y - asc * 0.78)
	_mat.set_shader_parameter("bottom_y", base_y)
	_draw_emblem(Vector2(_emblem_size() * 0.5 + 2, base_y - asc * 0.42 + sin(_time * 1.6) * bob_height))
	var x := _emblem_size() + font_size * 0.22
	for i in text.length():
		var ch := text[i]
		var pos := Vector2(x, base_y + sin(_time * 2.0 + i * 0.6) * bob_height)
		# Extrusion: darker copies stepping down-right, back to front, with a dark rim.
		for d in range(DEPTH, 0, -1):
			var off := Vector2(d, d) * 1.1
			_font.draw_char_outline(get_canvas_item(), pos + off, ch.unicode_at(0), font_size, 8, RIM)
		for d in range(DEPTH, 0, -1):
			var off := Vector2(d, d) * 1.1
			_font.draw_char(get_canvas_item(), pos + off, ch.unicode_at(0), font_size, SIDE.darkened(0.25 * d / DEPTH))
		_font.draw_char_outline(get_canvas_item(), pos, ch.unicode_at(0), font_size, 6, RIM)
		_font.draw_char(get_canvas_item(), pos, ch.unicode_at(0), font_size, Color.WHITE)
		x += _font.get_char_size(ch.unicode_at(0), font_size).x + 1.0


## Isometric voxel cube with rounded-looking bevels: light top, mid left, dark right.
func _draw_emblem(center: Vector2) -> void:
	var s := _emblem_size() * 0.5
	var top := center + Vector2(0, -s)
	var left := center + Vector2(-s * 0.87, -s * 0.5)
	var right := center + Vector2(s * 0.87, -s * 0.5)
	var bottom := center + Vector2(0, s)
	var bl := center + Vector2(-s * 0.87, s * 0.5)
	var br := center + Vector2(s * 0.87, s * 0.5)
	var outline := PackedVector2Array([top, right, br, bottom, bl, left, top])
	draw_polyline(outline, RIM, 7.0, true)
	draw_colored_polygon(PackedVector2Array([top, right, center, left]), Color("ffe36e"))
	draw_colored_polygon(PackedVector2Array([left, center, bottom, bl]), Color("f08a1c"))
	draw_colored_polygon(PackedVector2Array([center, right, br, bottom]), Color("b4440f"))
	# Inner edges and a little shine on the top face.
	draw_polyline(PackedVector2Array([left, center, right]), Color(RIM, 0.55), 2.0, true)
	draw_line(center, bottom, Color(RIM, 0.55), 2.0, true)
	draw_line(top.lerp(left, 0.35), top.lerp(right, 0.35), Color(1, 1, 1, 0.55), 3.0, true)
