class_name PostProcess
extends CanvasLayer
## The game's colour grade over the 3D view (under the HUD): vibrance, split toning per time of
## day, a gentle S-curve and a soft vignette. Toggled live by the "post_fx" setting. Sharpening is
## the upscaler's (Profile "sharpness", FSR's RCAS pass), not drawn here.
##
## Nothing here reads the screen back. The grade is a per-colour function, so it is baked into a
## 3D colour lookup table that the map's Environment applies inside Godot's tonemap pass (at the
## 3D render resolution, before upscaling, at no extra cost). The vignette is a multiply-blended
## rectangle (no screen copy). Only photo mode's `filter` (FILTER_NAMES: none, a cinematic colour
## grade, black and white, sepia) reads the screen, and only while one is picked; it is shown
## even with post_fx off.
##
## Before this, one full-screen shader sampled the screen five times after a mipmapped screen
## copy, at the window's full size: 23 ms a frame fullscreen on a 5K (HiDPI 2560 x 1440) display.

const FILTER_NAMES: Array[String] = ["None", "Colour grade", "Black & white", "Sepia"]
## Side of the colour lookup table (LUT_SIZE^3 entries).
const LUT_SIZE := 32
const VIGNETTE := 0.3

const VIGNETTE_SHADER := """
shader_type canvas_item;
render_mode blend_mul, unshaded;
uniform float vignette = 0.3;

void fragment() {
	vec2 d = UV - 0.5;
	COLOR = vec4(vec3(1.0 - vignette * dot(d, d) * 1.6), 1.0);
}
"""

const FILTER_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int photo_filter = 0;

void fragment() {
	vec3 c = clamp(textureLod(screen_tex, SCREEN_UV, 0.0).rgb, 0.0, 1.0);
	float y = dot(c, vec3(0.2126, 0.7152, 0.0722));
	if (photo_filter == 1) {
		// Cinematic grade: teal shadows, warm highlights, richer colour and contrast.
		c = mix(c * vec3(0.86, 1.0, 1.08), c * vec3(1.12, 1.0, 0.84), smoothstep(0.15, 0.75, y));
		c = mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, 1.3);
		c = mix(c, c * c * (3.0 - 2.0 * c), 0.45);
	} else if (photo_filter == 2) {
		float g = mix(y, y * y * (3.0 - 2.0 * y), 0.5);
		c = vec3(g);
	} else if (photo_filter == 3) {
		vec3 s = vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131)));
		vec2 d2 = SCREEN_UV - 0.5;
		c = s * (1.0 - 0.5 * dot(d2, d2));
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

## Per time of day: [shadow tint, highlight tint, vibrance].
const GRADES := {
	"day": [Color(0.97, 1.0, 1.04), Color(1.04, 1.0, 0.95), 0.08],
	"sunset": [Color(0.94, 0.96, 1.08), Color(1.08, 0.99, 0.9), 0.12],
	"night": [Color(0.92, 0.98, 1.12), Color(1.0, 1.0, 1.02), 0.05],
}

## time of day -> its grade's ImageTexture3D (built once per run).
static var _luts := {}

var _vignette: ColorRect
var _filter_rect: ColorRect
var _filter_mat: ShaderMaterial
var _lut: ImageTexture3D
## Photo mode's filter (FILTER_NAMES index; 0 none).
var filter := 0


func setup(time_of_day: String) -> void:
	layer = 1
	_lut = grade_lut(time_of_day)
	_vignette = _full_rect(VIGNETTE_SHADER)
	(_vignette.material as ShaderMaterial).set_shader_parameter("vignette", VIGNETTE)
	_filter_rect = _full_rect(FILTER_SHADER)
	_filter_mat = _filter_rect.material
	_apply_setting()
	Profile.changed.connect(_apply_setting)


func _full_rect(code: String) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	r.material = mat
	add_child(r)
	return r


## Photo mode: `index` into FILTER_NAMES (0 none). Leaving photo mode sets it back to 0.
func set_filter(index: int) -> void:
	filter = clampi(index, 0, FILTER_NAMES.size() - 1)
	_filter_mat.set_shader_parameter("photo_filter", filter)
	_apply_setting()


func _apply_setting() -> void:
	var fx := bool(Profile.get_setting("post_fx"))
	_vignette.visible = fx
	_filter_rect.visible = filter > 0
	visible = fx or filter > 0
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(MapBuilder.GRAPHICS_GROUP):
		var we := node as WorldEnvironment
		if we != null and we.environment != null:
			we.environment.adjustment_color_correction = _lut if fx else null


func _enter_tree() -> void:
	if _vignette != null:
		_apply_setting()


## The grade of `time_of_day` as a LUT_SIZE^3 colour lookup table for
## Environment.adjustment_color_correction, which samples it with the display (sRGB) colour after
## tonemapping, the same values the old screen shader graded. Texel i holds the grade of
## (i + 0.5) / LUT_SIZE (the sampler's texel centres).
static func grade_lut(time_of_day: String) -> ImageTexture3D:
	if _luts.has(time_of_day):
		return _luts[time_of_day]
	var grade: Array = GRADES.get(time_of_day, GRADES.day)
	var shadow := Vector3((grade[0] as Color).r, (grade[0] as Color).g, (grade[0] as Color).b)
	var highlight := Vector3((grade[1] as Color).r, (grade[1] as Color).g, (grade[1] as Color).b)
	var vibrance: float = grade[2]
	var n := LUT_SIZE
	var images: Array[Image] = []
	var bytes := PackedByteArray()
	bytes.resize(n * n * 3)
	for bz in n:
		var i := 0
		for gy in n:
			for rx in n:
				var c := Vector3((rx + 0.5) / n, (gy + 0.5) / n, (bz + 0.5) / n)
				c = grade_color(c, shadow, highlight, vibrance)
				bytes[i] = roundi(clampf(c.x, 0.0, 1.0) * 255.0)
				bytes[i + 1] = roundi(clampf(c.y, 0.0, 1.0) * 255.0)
				bytes[i + 2] = roundi(clampf(c.z, 0.0, 1.0) * 255.0)
				i += 3
		images.append(Image.create_from_data(n, n, false, Image.FORMAT_RGB8, bytes))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, images)
	_luts[time_of_day] = tex
	return tex


## The grade of one display colour: vibrance (most where colours are dull), shadow / highlight
## tints and a gentle S-curve for punchier midtones.
static func grade_color(c: Vector3, shadow: Vector3, highlight: Vector3, vibrance: float) -> Vector3:
	var sat := maxf(c.x, maxf(c.y, c.z)) - minf(c.x, minf(c.y, c.z))
	var l := c.dot(Vector3(0.2126, 0.7152, 0.0722))
	c = Vector3(l, l, l).lerp(c, 1.0 + vibrance * (1.0 - sat))
	c *= shadow.lerp(highlight, smoothstep(0.08, 0.8, l))
	var s := c * c * (Vector3(3.0, 3.0, 3.0) - 2.0 * c)
	return c.lerp(s, 0.2)
