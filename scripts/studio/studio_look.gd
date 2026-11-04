class_name StudioLook
extends CanvasLayer
## Studio's look over the picture (a clip, a photo scene or a plain photo): one full-screen shader
## that reads what was drawn under it in Studio's SubViewport, so the preview and every exported
## frame get the same look. A filter preset (FILTERS) plus adjustments (ADJUSTMENTS: exposure,
## contrast, saturation, warmth, vignette, film grain, chromatic aberration, sharpen, pixelate and
## cinema bars) and an optional TIMBUM watermark in the corner. Set with `apply(edit)`, the
## Studio edit dictionary (keys "filter" and the ADJUSTMENTS ids).

## Filter presets: [name, shader index].
const FILTERS: Array = [["None", 0], ["Cinematic", 1], ["Black & white", 2], ["Sepia", 3], ["Noir", 4],
	["Vintage", 5], ["Vibrant", 6], ["Cool", 7], ["Warm", 8], ["Neon", 9], ["Retro 8-bit", 10], ["VHS", 11],
	["CRT", 12], ["Thermal", 13], ["Dream", 14], ["Comic", 15]]
## Adjustments: [edit key, label, min, max, default, display format ("pct", "stops" or a % format)].
const ADJUSTMENTS: Array = [
	["exposure", "Exposure", -1.5, 1.5, 0.0, "stops"],
	["contrast", "Contrast", -0.5, 0.5, 0.0, "pct"],
	["saturation", "Saturation", -1.0, 1.0, 0.0, "pct"],
	["warmth", "Warmth", -1.0, 1.0, 0.0, "pct"],
	["vignette", "Vignette", 0.0, 1.0, 0.0, "pct"],
	["grain", "Film grain", 0.0, 1.0, 0.0, "pct"],
	["chroma", "Colour fringe", 0.0, 1.0, 0.0, "pct"],
	["sharpen", "Sharpen", 0.0, 1.0, 0.0, "pct"],
	["pixelate", "Pixelate", 0.0, 1.0, 0.0, "pct"],
	["bars", "Cinema bars", 0.0, 1.0, 0.0, "pct"],
]

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int preset = 0;
uniform float exposure = 0.0;
uniform float contrast = 0.0;
uniform float saturation = 0.0;
uniform float warmth = 0.0;
uniform float vignette = 0.0;
uniform float grain = 0.0;
uniform float chroma = 0.0;
uniform float sharpen = 0.0;
uniform float pixelate = 0.0;
uniform float bars = 0.0;
uniform float frame_seed = 0.0;

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + frame_seed * 0.6180339) * 43758.5453); }

vec3 fetch(vec2 uv, vec2 px) {
	vec3 c;
	if (chroma > 0.0) {
		vec2 d = (uv - 0.5) * chroma * 0.012;
		c = vec3(textureLod(screen_tex, uv + d, 0.0).r, textureLod(screen_tex, uv, 0.0).g, textureLod(screen_tex, uv - d, 0.0).b);
	} else {
		c = textureLod(screen_tex, uv, 0.0).rgb;
	}
	if (sharpen > 0.0) {
		vec3 n = textureLod(screen_tex, uv + vec2(px.x, 0.0), 0.0).rgb + textureLod(screen_tex, uv - vec2(px.x, 0.0), 0.0).rgb
			+ textureLod(screen_tex, uv + vec2(0.0, px.y), 0.0).rgb + textureLod(screen_tex, uv - vec2(0.0, px.y), 0.0).rgb;
		c += (c * 4.0 - n) * sharpen * 0.6;
	}
	return c;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	float px_amount = pixelate;
	if (preset == 10) px_amount = max(px_amount, 0.45);
	if (px_amount > 0.0) {
		float cell = 1.0 + px_amount * 15.0;
		vec2 grid = px * cell;
		uv = (floor(uv / grid) + 0.5) * grid;
	}
	if (preset == 11) {
		// VHS: wobbling lines and a smeared, shifted red.
		uv.x += sin(uv.y * 240.0 + frame_seed * 3.1) * 0.0009 + (hash(vec2(floor(uv.y * 90.0), 1.0)) - 0.5) * 0.0015;
	}
	vec3 c = fetch(uv, px);
	if (preset == 11) {
		c.r = textureLod(screen_tex, uv + vec2(px.x * 3.0, 0.0), 0.0).r;
	}
	if (preset == 14) {
		// Dream: a soft glow from a wide blur over the picture.
		vec3 b = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			b += textureLod(screen_tex, uv + vec2(cos(a), sin(a)) * px * 9.0, 0.0).rgb;
		}
		b /= 8.0;
		c = mix(c, max(c, b), 0.65) * 1.05 + vec3(0.04, 0.02, 0.05);
	}
	c = clamp(c, 0.0, 1.0);
	float y = luma(c);
	if (preset == 1) {
		c = mix(c * vec3(0.86, 1.0, 1.08), c * vec3(1.12, 1.0, 0.84), smoothstep(0.15, 0.75, y));
		c = mix(vec3(luma(c)), c, 1.3);
		c = mix(c, c * c * (3.0 - 2.0 * c), 0.45);
	} else if (preset == 2) {
		c = vec3(mix(y, y * y * (3.0 - 2.0 * y), 0.5));
	} else if (preset == 3) {
		c = vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131)));
	} else if (preset == 4) {
		float g = smoothstep(0.08, 0.85, y);
		c = vec3(g * g * (3.0 - 2.0 * g)) * vec3(0.98, 1.0, 1.04);
	} else if (preset == 5) {
		c = mix(c, vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131))), 0.45);
		c = c * 0.86 + vec3(0.07, 0.05, 0.02);
	} else if (preset == 6) {
		c = mix(vec3(y), c, 1.55);
		c = mix(c, c * c * (3.0 - 2.0 * c), 0.3);
	} else if (preset == 7) {
		c *= vec3(0.88, 0.98, 1.14);
	} else if (preset == 8) {
		c *= vec3(1.14, 1.0, 0.82);
	} else if (preset == 9) {
		vec3 hi = mix(vec3(0.15, 0.0, 0.35), vec3(0.0, 1.0, 0.95), smoothstep(0.2, 0.6, y));
		c = mix(c, hi * (0.4 + y), 0.55) + vec3(1.0, 0.1, 0.8) * smoothstep(0.7, 1.0, y) * 0.35;
	} else if (preset == 10) {
		c = floor(c * 5.0 + 0.5) / 5.0;
	} else if (preset == 11) {
		c = mix(vec3(y), c, 0.75) * vec3(1.05, 0.98, 1.08);
	} else if (preset == 12) {
		float line = 0.82 + 0.18 * sin(SCREEN_UV.y / px.y * 3.14159);
		float col = mod(FRAGCOORD.x, 3.0);
		vec3 mask = vec3(0.92) + 0.16 * vec3(step(col, 0.999), step(1.0, col) * step(col, 1.999), step(2.0, col));
		c = c * line * mask * 1.12;
	} else if (preset == 13) {
		c = mix(mix(vec3(0.05, 0.0, 0.25), vec3(0.9, 0.1, 0.3), smoothstep(0.1, 0.5, y)), vec3(1.0, 0.95, 0.3), smoothstep(0.5, 0.95, y));
	} else if (preset == 15) {
		vec3 n = textureLod(screen_tex, uv + vec2(px.x, 0.0), 0.0).rgb + textureLod(screen_tex, uv + vec2(0.0, px.y), 0.0).rgb;
		float edge = length(c * 2.0 - n);
		c = floor(mix(vec3(y), c, 1.4) * 4.0 + 0.5) / 4.0;
		c *= 1.0 - smoothstep(0.12, 0.3, edge);
	}
	c *= exp2(exposure);
	c = (c - 0.5) * (1.0 + contrast) + 0.5;
	c = mix(vec3(luma(c)), c, 1.0 + saturation);
	c *= vec3(1.0 + warmth * 0.12, 1.0, 1.0 - warmth * 0.12);
	vec2 d = SCREEN_UV - 0.5;
	float vig = vignette + (preset == 4 || preset == 5 || preset == 3 ? 0.35 : 0.0) + (preset == 12 ? 0.25 : 0.0);
	c *= 1.0 - vig * dot(d, d) * 2.2;
	float g = grain + (preset == 5 || preset == 4 ? 0.25 : 0.0) + (preset == 11 ? 0.35 : 0.0);
	if (g > 0.0) {
		c += (hash(FRAGCOORD.xy) - 0.5) * g * 0.18;
	}
	if (bars > 0.0 && abs(SCREEN_UV.y - 0.5) > 0.5 - bars * 0.13) {
		c = vec3(0.0);
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial
var _mark: Label
var _frame := 0


func _init() -> void:
	name = "Look"
	layer = 5
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect.material = _mat
	add_child(_rect)
	_mark = Label.new()
	_mark.text = "TIMBUM"
	_mark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_mark.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mark.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.add_theme_font_override("font", UITheme.heavy_font())
	_mark.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_mark.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_mark.add_theme_constant_override("outline_size", 6)
	add_child(_mark)


## Studio edit -> shader. The watermark scales with the picture (`height` in pixels).
func apply(edit: Dictionary, height: float) -> void:
	var f := clampi(int(edit.get("filter", 0)), 0, FILTERS.size() - 1)
	_mat.set_shader_parameter("preset", int(FILTERS[f][1]))
	var any := f != 0
	for a: Array in ADJUSTMENTS:
		var v := float(edit.get(a[0], a[4]))
		_mat.set_shader_parameter(a[0], v)
		any = any or not is_equal_approx(v, float(a[4]))
	_rect.visible = any
	_mark.visible = bool(edit.get("watermark", false))
	var size := maxi(12, roundi(height * 0.035))
	_mark.add_theme_font_size_override("font_size", size)
	_mark.offset_right = -size
	_mark.offset_bottom = -size * 0.6


func _process(_delta: float) -> void:
	# A new grain pattern every drawn frame (the same sequence in every export).
	_frame += 1
	_mat.set_shader_parameter("frame_seed", float(_frame % 997))


## Default values of every look setting (for a fresh edit).
static func defaults() -> Dictionary:
	var d := {"filter": 0, "watermark": false}
	for a: Array in ADJUSTMENTS:
		d[a[0]] = a[4]
	return d
