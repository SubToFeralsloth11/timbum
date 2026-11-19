class_name ScopeOverlay
extends Control
## Scope view: black mask with a round lens and a reticle. Style "sniper" (fine
## crosshairs, red dot) or "marksman" (wider low-power lens, red chevron), chosen per
## weapon by `Data.WEAPONS[id].scope_style`. A custom scope (`design`, CustomScopes) replaces
## both: its view shape and size, lens tint and reticle (CustomScopes.draw_reticle).

const SHADER := """
shader_type canvas_item;
uniform float aspect = 1.777;
uniform float radius = 0.44;
// CustomScopes.VIEWS: 0 round, 1 square, 2 octagon, 3 hexagon, 4 wide, 5 open (no mask).
uniform int shape = 0;
uniform vec4 tint = vec4(0.0);
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	vec2 a = abs(p);
	float d = length(p);
	if (shape == 1) {
		d = max(a.x, a.y);
	} else if (shape == 2) {
		d = max(max(a.x, a.y), (a.x + a.y) * 0.7071);
	} else if (shape == 3) {
		d = max(a.x * 0.866 + a.y * 0.5, a.y);
	} else if (shape == 4) {
		d = length(p * vec2(0.62, 1.0));
	}
	float lens = 1.0 - smoothstep(radius - 0.005, radius, d);
	float rim = smoothstep(radius * 0.68, radius, d) * 0.35;
	if (shape == 5) {
		lens = 1.0;
		rim = smoothstep(radius * 1.6, radius * 2.6, d) * 0.35;
	}
	vec4 inside = vec4(tint.rgb * (tint.a / max(tint.a + rim, 0.001)), clamp(rim + tint.a, 0.0, 1.0));
	COLOR = mix(vec4(0.0, 0.0, 0.0, 1.0), inside, lens);
}
"""
## Lens radius as a fraction of the screen height.
const RADIUS := {"sniper": 0.44, "marksman": 0.47}

var style := "sniper":
	set(v):
		if v == style or not RADIUS.has(v):
			return
		style = v
		_apply()

## Custom scope design ({}: the gun's own `style`). Designs from CustomScopes.decode_cached are
## shared, so the same design is recognised by identity and costs nothing per frame.
var design := {}:
	set(v):
		if is_same(v, design):
			return
		design = v
		_apply()

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
	_apply()
	_on_resized()


## Lens radius (fraction of the screen height) of the current style or design.
func _radius() -> float:
	return float(design.view_size) if not design.is_empty() else float(RADIUS[style])


func _apply() -> void:
	if _mat != null:
		_mat.set_shader_parameter("radius", _radius())
		_mat.set_shader_parameter("shape", int(design.view) if not design.is_empty() else 0)
		var tint: Color = design.tint if not design.is_empty() else Color(0, 0, 0, 0)
		_mat.set_shader_parameter("tint", tint)
	queue_redraw()


func _on_resized() -> void:
	if size.y > 0.0:
		_mat.set_shader_parameter("aspect", size.x / size.y)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := size.y * _radius()
	if not design.is_empty():
		CustomScopes.draw_reticle(self, c, r, design)
		return
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
