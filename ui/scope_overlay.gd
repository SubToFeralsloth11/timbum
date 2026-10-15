class_name ScopeOverlay
extends Control
## Sniper scope: black mask with a round lens and fine crosshairs.

const SHADER := """
shader_type canvas_item;
uniform float aspect = 1.777;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float d = length(p);
	float lens = smoothstep(0.44, 0.435, d);
	float rim = smoothstep(0.30, 0.44, d) * 0.35;
	COLOR = vec4(0.0, 0.0, 0.0, mix(1.0, rim, lens));
}
"""

var _mask: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask = ColorRect.new()
	_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mask.material = _mat
	add_child(_mask)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if size.y > 0.0:
		_mat.set_shader_parameter("aspect", size.x / size.y)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := size.y * 0.44
	var col := Color(0, 0, 0, 0.9)
	draw_line(Vector2(c.x - r, c.y), Vector2(c.x - 6, c.y), col, 2.0)
	draw_line(Vector2(c.x + 6, c.y), Vector2(c.x + r, c.y), col, 2.0)
	draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y - 6), col, 2.0)
	draw_line(Vector2(c.x, c.y + 6), Vector2(c.x, c.y + r), col, 2.0)
	draw_circle(c, 1.5, Color(1, 0.2, 0.2))
