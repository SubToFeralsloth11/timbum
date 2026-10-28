class_name PostProcess
extends CanvasLayer
## Full-screen grade over the 3D view (under the HUD): light sharpening so the pixel-art
## textures stay crisp after TAA-free scaling, vibrance, split toning per time of day and a soft
## vignette. Toggled live by the "post_fx" setting.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float sharpen = 0.3;
uniform float vibrance = 0.2;
uniform float vignette = 0.3;
uniform vec3 shadow_tint = vec3(0.97, 1.0, 1.04);
uniform vec3 highlight_tint = vec3(1.04, 1.0, 0.95);

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 n = textureLod(screen_tex, SCREEN_UV + vec2(0.0, -px.y), 0.0).rgb
		+ textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), 0.0).rgb
		+ textureLod(screen_tex, SCREEN_UV + vec2(-px.x, 0.0), 0.0).rgb
		+ textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), 0.0).rgb;
	c = max(c + (c - n * 0.25) * sharpen, vec3(0.0));
	// Vibrance: boost saturation most where colours are dull, leaving vivid ones alone.
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, 1.0 + vibrance * (1.0 - sat));
	c *= mix(shadow_tint, highlight_tint, smoothstep(0.08, 0.8, l));
	// Gentle S-curve for punchier midtones.
	c = mix(c, c * c * (3.0 - 2.0 * c), 0.2);
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * dot(d, d) * 1.6;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

## Per time of day: [shadow tint, highlight tint, vibrance].
const GRADES := {
	"day": [Color(0.97, 1.0, 1.04), Color(1.04, 1.0, 0.95), 0.08],
	"sunset": [Color(0.94, 0.96, 1.08), Color(1.08, 0.99, 0.9), 0.12],
	"night": [Color(0.92, 0.98, 1.12), Color(1.0, 1.0, 1.02), 0.05],
}

var _rect: ColorRect


func setup(time_of_day: String) -> void:
	layer = 1
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var grade: Array = GRADES.get(time_of_day, GRADES.day)
	var shadow: Color = grade[0]
	var highlight: Color = grade[1]
	mat.set_shader_parameter("shadow_tint", Vector3(shadow.r, shadow.g, shadow.b))
	mat.set_shader_parameter("highlight_tint", Vector3(highlight.r, highlight.g, highlight.b))
	mat.set_shader_parameter("vibrance", grade[2])
	_rect.material = mat
	add_child(_rect)
	_apply_setting()
	Profile.changed.connect(_apply_setting)


func _apply_setting() -> void:
	visible = bool(Profile.get_setting("post_fx"))
