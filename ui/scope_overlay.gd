class_name ScopeOverlay
extends Control
## Scope view: black mask with a round lens and a reticle. Style "sniper" (fine
## crosshairs, red dot) or "marksman" (wider low-power lens, red chevron), chosen per
## weapon by `Data.WEAPONS[id].scope_style`.

const SHADER := """
shader_type canvas_item;
uniform float aspect = 1.777;
uniform float radius = 0.44;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float d = length(p);
	float lens = 1.0 - smoothstep(radius - 0.005, radius, d);
	float rim = smoothstep(radius * 0.68, radius, d) * 0.35;
	COLOR = vec4(0.0, 0.0, 0.0, mix(1.0, rim, lens));
}
"""
## Lens radius as a fraction of the screen height.
const RADIUS := {"sniper": 0.44, "marksman": 0.47}

var style := "sniper":
	set(v):
		if v == style or not RADIUS.has(v):
			return
		style = v
		if _mat != null:
			_mat.set_shader_parameter("radius", RADIUS[style])
		queue_redraw()

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
	_mat.set_shader_parameter("radius", RADIUS[style])
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
	var r := size.y * float(RADIUS[style])
	var col := Color(0, 0, 0, 0.9)
	if style == "marksman":
		# Thick posts from the rim that stop well short of the centre, plus a chevron.
		var gap := r * 0.3
		draw_line(Vector2(c.x - r, c.y), Vector2(c.x - gap, c.y), col, 4.0)
		draw_line(Vector2(c.x + gap, c.y), Vector2(c.x + r, c.y), col, 4.0)
		draw_line(Vector2(c.x, c.y + gap), Vector2(c.x, c.y + r), col, 4.0)
		var red := Color(1, 0.25, 0.2)
		var w := size.y * 0.014
		draw_polyline(PackedVector2Array([c + Vector2(-w, w), c, c + Vector2(w, w)]), red, 2.5, true)
		return
	draw_line(Vector2(c.x - r, c.y), Vector2(c.x - 6, c.y), col, 2.0)
	draw_line(Vector2(c.x + 6, c.y), Vector2(c.x + r, c.y), col, 2.0)
	draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y - 6), col, 2.0)
	draw_line(Vector2(c.x, c.y + 6), Vector2(c.x, c.y + r), col, 2.0)
	draw_circle(c, 1.5, Color(1, 0.2, 0.2))
