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
// Custom scopes: no black mask, only the lens tint inside the view shape (the gun stays visible).
uniform bool see_through = false;
// Lens centre in UV (custom scopes follow the gun's eyepiece on screen).
uniform vec2 center = vec2(0.5);
void fragment() {
	vec2 p = (UV - center) * vec2(aspect, 1.0);
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
	} else if (shape == 6) {
		d = max(p.y, a.x * 0.866 - p.y * 0.5);
	}
	float lens = 1.0 - smoothstep(radius - 0.005, radius, d);
	float rim = smoothstep(radius * 0.68, radius, d) * 0.35;
	if (shape == 5) {
		lens = 1.0;
		rim = smoothstep(radius * 1.6, radius * 2.6, d) * 0.35;
	}
	vec4 inside = vec4(tint.rgb * (tint.a / max(tint.a + rim, 0.001)), clamp(rim + tint.a, 0.0, 1.0));
	if (see_through) {
		COLOR = vec4(tint.rgb, tint.a * lens);
	} else {
		COLOR = mix(vec4(0.0, 0.0, 0.0, 1.0), inside, lens);
	}
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

## Custom scopes: the eyepiece on screen (x, y: centre px, z: inner radius px; z <= 0: screen
## centre at the design's view_size). Set every frame from Viewmodel.lens_screen.
var lens := Vector3.ZERO:
	set(v):
		if v.is_equal_approx(lens):
			return
		lens = v
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
	if design.is_empty():
		return float(RADIUS[style])
	if lens.z > 0.0 and size.y > 0.0:
		return lens.z / size.y
	return float(design.view_size)


func _center() -> Vector2:
	return Vector2(lens.x, lens.y) if not design.is_empty() and lens.z > 0.0 else size * 0.5


func _apply() -> void:
	if _mat != null:
		_mat.set_shader_parameter("radius", _radius())
		_mat.set_shader_parameter("shape", CustomScopes.view_of(design) if not design.is_empty() else 0)
		var tint: Color = design.tint if not design.is_empty() else Color(0, 0, 0, 0)
		_mat.set_shader_parameter("tint", tint)
		_mat.set_shader_parameter("see_through", not design.is_empty())
		_mat.set_shader_parameter("center", _center() / size if size.x > 0.0 and size.y > 0.0 else Vector2(0.5, 0.5))
	queue_redraw()


func _on_resized() -> void:
	if size.y > 0.0:
		_mat.set_shader_parameter("aspect", size.x / size.y)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := size.y * _radius()
	if not design.is_empty():
		c = _center()
		_draw_housing(c, r)
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


## The scope's housing round the lens, as it looks from the eyepiece: a band in the body's
## colour in the lens's shape, darker on the inner edge, lit on the outer one.
func _draw_housing(c: Vector2, r: float) -> void:
	var view := CustomScopes.view_of(design)
	if view == 5:
		return
	var body := CustomScopes.body_color(design)
	var band := maxf(6.0, r * 0.22)
	draw_polyline(CustomScopes.shape_points(c, r + band * 0.5, view), body, band, true)
	draw_polyline(CustomScopes.shape_points(c, r + 1.5, view), body.darkened(0.6), 3.0, true)
	draw_polyline(CustomScopes.shape_points(c, r + band - 1.0, view), body.lightened(0.3), 2.0, true)
