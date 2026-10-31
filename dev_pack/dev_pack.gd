class_name DevPack
extends RefCounted
## THE DEV PACK: a code-only, four-piece cosmetic set. Matte black everywhere, neon green
## everywhere else, and the only animated outfit in the game. Every piece shares one look:
##   - Dev Suit     (outfit)  matte black bodysuit with a neon jagged grin (round eye, X eye) in
##                            half-size pixels, neon seams and circuit traces; bands crawl slowly
##                            along the lines, pulses run down the traces, the eye and chest core
##                            beat, a faint scan line rises through the body. ANIMATED.
##   - Dev Circuit  (skin)    carbon-black gun with neon circuit traces that slowly slide along
##                            the gun; pulses race to the muzzle.
##   - Dev Halo     (hat)     black circlet with a neon inlay, a floating neon diamond halo and a
##                            floating "</>" glyph.
##   - Dev Core     (charm)   a black cube inside a neon wireframe cage on a gunmetal chain.
## On a kill every piece the killer wears flashes: neon lines go white-hot and the whole set floods
## green, then fades over FLASH_TIME (instance uniform `kill_flash`, so the shared materials stay
## shared and only the killer flashes).
##
## NOT WIRED INTO THE GAME YET. dev_pack/ has a .gdignore, so Godot neither parses nor exports
## this folder. dev_pack/README.md is the integration brief; follow it exactly.
##
## Depends only on MeshKit and Models.AVATAR_PARTS / Models.ATLAS_SIZE.

## Unlock code "LastMinutePlaysonyt". Only its SHA-256 (of the lower-cased code) ships in the game,
## so the plain code isn't sitting in the exported build. Compared case-insensitively, spaces ignored.
const UNLOCK_CODE_SHA256 := "b8bdeb5bdc377f0bbd605ba77dd40e1b77208a709f589c329b745a98fd544471"

## Catalog ids, one per category (Data.catalog() category names).
const IDS := {"outfits": "dev_suit", "skins": "dev_circuit", "hats": "dev_halo", "charms": "dev_core"}

## Ready-to-paste Data catalog entries. price -1: never sold (Profile.buy refuses it) and never
## free (Profile.is_owned only counts price 0 as free), so the code is the only way in.
## `dev: true` marks pack items for the shop's CODE ONLY card and the bot filter.
const ENTRIES := {
	"outfits": {"name": "Dev Suit", "price": -1, "pattern": "dev", "dev": true,
		"desc": "Matte black with a neon jagged grin and neon green seams. The lines crawl, the eye and core beat. The only animated outfit. Flashes on every kill.",
		"skin": Color("07080a"), "shirt": Color("39ff14"), "pants": Color("07080a"),
		"shoes": Color("07080a"), "accent": Color("39ff14")},
	"skins": {"name": "Dev Circuit", "price": -1, "pattern": "dev", "dev": true,
		"desc": "Carbon black with neon green circuit traces. Pulses race to the muzzle. Flashes on every kill.",
		"a": Color("39ff14"), "b": Color("07080a"), "glow": 3.0},
	"hats": {"name": "Dev Halo", "price": -1, "dev": true,
		"desc": "A black circlet under a floating neon halo and the </> glyph. Flashes on every kill."},
	"charms": {"name": "Dev Core", "price": -1, "dev": true, "shape": "dev",
		"desc": "A black core in a neon cage. Flashes on every kill.",
		"a": Color("39ff14"), "b": Color("07080a")},
}

const NEON := Color("39ff14")
## White-hot tint for pulse heads and the kill flash.
const HOT := Color("e6ffe0")
const BLACK := Color("07080a")
## Panel seams: a hair lighter than BLACK, readable only under light.
const SEAM := Color("12151a")
## Colour the whole set floods with on a kill, and how long the flash takes to fade.
const FLASH_COLOR := Color("39ff14")
const FLASH_TIME := 0.7

# --- Shaders -----------------------------------------------------------------------------------
# All three shaders: `#define VIEWMODEL` (see shader()) adds the first-person depth squash used by
# Viewmodel.SHADER_CODE. All share `instance uniform float kill_flash` (0..1, see flash()).

## Outfit: 64x64 atlas (Models.AVATAR_PARTS layout). mask_tex: r static neon (breathes), g circuit
## trace (pulses travel down it), b pulse phase (0 head top .. 1 soles), a chest core (heartbeat).
const OUTFIT_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform sampler2D mask_tex : filter_nearest;
uniform vec4 neon : source_color;
uniform vec4 hot : source_color;
uniform vec4 flash_color : source_color;
uniform float energy = 1.8;
instance uniform float kill_flash = 0.0;

void vertex() {
#ifdef VIEWMODEL
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.w, POSITION.z, 0.04);
#endif
}

void fragment() {
	float t = TIME;
	vec4 m = texture(mask_tex, UV);
	float breathe = 0.72 + 0.28 * sin(t * 2.1);
	float pulse = pow(fract(m.b * 1.6 - t * 0.55), 9.0);
	float beat = 0.55 + 0.45 * pow(0.5 + 0.5 * sin(t * 4.2), 6.0);
	float wy = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float scan = smoothstep(0.95, 1.0, fract(wy * 0.4 - t * 0.3)) * 0.07;
	float lines = max(m.r, max(m.g, m.a));
	// Bright bands crawl slowly along every neon line (diagonally in atlas texels, so they travel
	// along vertical traces and round the horizontal rings alike): about 1.2 texels a second.
	float crawl = 0.55 + 0.45 * smoothstep(0.35, 0.5, abs(fract(((UV.x + UV.y) * 64.0 - t * 1.2) / 6.0) - 0.5) * 2.0);
	vec3 g = neon.rgb * m.r * breathe * crawl;
	g += mix(neon.rgb, hot.rgb, pulse * 0.75) * m.g * (0.2 * crawl + 1.9 * pulse);
	g += mix(neon.rgb, hot.rgb, 0.35) * m.a * beat * 1.6;
	g += neon.rgb * scan;
	float f = clamp(kill_flash, 0.0, 1.0);
	g = mix(g, hot.rgb * lines * 1.6, f);
	g += flash_color.rgb * f * f * 0.3;
	ALBEDO = texture(albedo_tex, UV).rgb;
	ROUGHNESS = 0.62;
	METALLIC = 0.1;
	SPECULAR = 0.35;
	EMISSION = g * energy;
}
"""

## Weapon skin: 32x32 tiling planar texture (MeshKit UVs). mask_tex: r trace, g pad/via.
## Pulses travel along the gun's own -Z, so they always race towards the muzzle.
const SKIN_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_nearest_mipmap, repeat_enable;
uniform vec4 neon : source_color;
uniform vec4 hot : source_color;
uniform vec4 flash_color : source_color;
uniform float energy = 2.0;
instance uniform float kill_flash = 0.0;
varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
#ifdef VIEWMODEL
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.w, POSITION.z, 0.04);
#endif
}

void fragment() {
	float t = TIME;
	// The whole circuit slides slowly along the gun (side faces' planar U runs along its length).
	vec2 uv = UV + vec2(t * 0.035, 0.0);
	vec4 m = texture(mask_tex, uv);
	float pulse = pow(fract(-v_obj.z * 2.6 - t * 0.95), 12.0);
	float breathe = 0.7 + 0.3 * sin(t * 2.1);
	float lines = max(m.r, m.g);
	vec3 g = mix(neon.rgb, hot.rgb, pulse * 0.7) * m.r * (0.28 + 2.2 * pulse);
	g += neon.rgb * m.g * breathe;
	float f = clamp(kill_flash, 0.0, 1.0);
	g = mix(g, hot.rgb * lines * 1.6, f);
	g += flash_color.rgb * f * f * 0.3;
	ALBEDO = texture(albedo_tex, uv).rgb;
	ROUGHNESS = 0.45;
	METALLIC = 0.3;
	SPECULAR = 0.45;
	EMISSION = g * energy;
}
"""

## Hat and charm parts: flat colour. neon_amt 1 = neon part (breathes, a shimmer climbs it along
## the part's own +Y), 0 = matte black part (only the kill flash lights it).
const SOLID_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec4 albedo : source_color;
uniform vec4 neon : source_color;
uniform vec4 hot : source_color;
uniform vec4 flash_color : source_color;
uniform float neon_amt = 0.0;
uniform float energy = 2.0;
uniform float metallic = 0.3;
uniform float roughness = 0.4;
instance uniform float kill_flash = 0.0;
varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
#ifdef VIEWMODEL
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.w, POSITION.z, 0.04);
#endif
}

void fragment() {
	float t = TIME;
	float breathe = 0.72 + 0.28 * sin(t * 2.1);
	float shimmer = pow(fract(v_obj.y * 3.0 + v_obj.x * 1.5 - t * 0.6), 10.0);
	vec3 g = mix(neon.rgb, hot.rgb, shimmer * 0.7) * neon_amt * (breathe + 1.4 * shimmer);
	float f = clamp(kill_flash, 0.0, 1.0);
	g = mix(g, hot.rgb * neon_amt * 1.6, f);
	g += flash_color.rgb * f * f * 0.3;
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = 0.4;
	EMISSION = g * energy;
}
"""

static var _shaders: Dictionary = {}
static var _outfit_mat: ShaderMaterial
static var _skin_mat: ShaderMaterial
static var _solid_mats: Dictionary = {}
static var _hat_mesh: ArrayMesh
static var _charm_mesh: ArrayMesh
## Source material -> its first-person (VIEWMODEL) copy.
static var _vm_mats: Dictionary = {}


## The pack's shader `kind` ("outfit" | "skin" | "solid"); `viewmodel` = first-person variant.
static func shader(kind: String, viewmodel := false) -> Shader:
	var key := kind + ("_vm" if viewmodel else "")
	if not _shaders.has(key):
		var code: String = {"outfit": OUTFIT_SHADER, "skin": SKIN_SHADER, "solid": SOLID_SHADER}[kind]
		var sh := Shader.new()
		sh.code = code.replace("shader_type spatial;", "shader_type spatial;\n#define VIEWMODEL") if viewmodel else code
		_shaders[key] = sh
	return _shaders[key]


## True when `code` is the unlock code (any case, spaces ignored).
static func code_matches(code: String) -> bool:
	return code.strip_edges().replace(" ", "").to_lower().sha256_text() == UNLOCK_CODE_SHA256


static func is_dev_item(category: String, id: String) -> bool:
	return IDS.get(category, "") == id


## True for a material built by this pack (either variant).
static func is_dev_material(m: Material) -> bool:
	if not (m is ShaderMaterial):
		return false
	var sh := (m as ShaderMaterial).shader
	return sh != null and _shaders.values().has(sh)


## First-person copy of a pack material (VIEWMODEL shader, every parameter copied), or `m` itself
## if it isn't one. Viewmodel._converted_material must route pack materials through this.
static func viewmodel_material(m: Material) -> Material:
	if not is_dev_material(m):
		return m
	if _vm_mats.has(m):
		return _vm_mats[m]
	var src := m as ShaderMaterial
	var kind := ""
	for k: String in ["outfit", "skin", "solid"]:
		if src.shader == shader(k) or src.shader == shader(k, true):
			kind = k
	if src.shader == shader(kind, true):
		return m
	var vm := ShaderMaterial.new()
	vm.shader = shader(kind, true)
	for u: Dictionary in src.shader.get_shader_uniform_list():
		vm.set_shader_parameter(u.name, src.get_shader_parameter(u.name))
	_vm_mats[m] = vm
	return vm


static func _base_params(sm: ShaderMaterial) -> void:
	sm.set_shader_parameter("neon", NEON)
	sm.set_shader_parameter("hot", HOT)
	sm.set_shader_parameter("flash_color", FLASH_COLOR)


# --- Kill flash --------------------------------------------------------------------------------

## Flashes every pack piece under `root` (an Avatar, a third-person gun, the Viewmodel): lines go
## white-hot and the set floods FLASH_COLOR, fading over FLASH_TIME. Restarts if already flashing.
## Pieces that aren't from the pack are untouched, so it's safe to call on any killer.
static func flash(root: Node) -> void:
	if root == null or not root.is_inside_tree():
		return
	var geoms: Array[GeometryInstance3D] = []
	for node in root.find_children("*", "GeometryInstance3D", true, false) + ([root] if root is GeometryInstance3D else []):
		if _wears_pack(node as GeometryInstance3D):
			geoms.append(node)
	if geoms.is_empty():
		return
	var old: Variant = root.get_meta(&"dev_flash_tween") if root.has_meta(&"dev_flash_tween") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := root.create_tween()
	tw.tween_method(_set_flash.bind(geoms), 1.0, 0.0, FLASH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	root.set_meta(&"dev_flash_tween", tw)


static func _set_flash(v: float, geoms: Array[GeometryInstance3D]) -> void:
	for g in geoms:
		if is_instance_valid(g):
			g.set_instance_shader_parameter(&"kill_flash", v)


static func _wears_pack(g: GeometryInstance3D) -> bool:
	if is_dev_material(g.material_override):
		return true
	if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
		var mi := g as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s)
			if is_dev_material(m if m != null else mi.mesh.surface_get_material(s)):
				return true
	return false


# --- Dev Suit (outfit) -------------------------------------------------------------------------

## Pixel maps per part and face. '.' black, '-' seam, 'g' circuit trace (pulses), 'R' static neon,
## 'o' neon pad, 'C' chest core (heartbeat). Faces: 0 front, 1 back, 2 +X side, 3 -X side,
## 4 top, 5 bottom (Models._face_rect order). Missing faces are plain black.
const _TORSO_FRONT := [
	"RRRRRRRR",
	"...g....",
	".o.g..o.",
	".g.g..g.",
	".g.CC.g.",
	".ggCCgg.",
	"...gg...",
	"..g..g..",
	".g....g.",
	".o....o.",
	"RRRRRRRR",
	"-......-",
]
const _TORSO_BACK := [
	"RRRRRRRR",
	"...gg...",
	"..g..g..",
	".g.oo.g.",
	".g.oo.g.",
	"..g..g..",
	"...gg...",
	"...gg...",
	"..g..g..",
	".o....o.",
	"RRRRRRRR",
	"-......-",
]
const _HEAD_BACK := [
	"........",
	"........",
	"........",
	"...oo...",
	"...gg...",
	"...gg...",
	"...gg...",
	"...gg...",
]
## The grin on the head's front face, at half-size pixels (16x16 on the 8x8 face; the suit atlas
## is drawn at SUIT_SCALE x the normal resolution). One-pixel strokes: a ring eye on the left with a
## beating hot pupil ('C'), an X eye on the right, and a wide open grin: thin lips with sharp
## one-pixel teeth hanging from the top lip and rising from the bottom, spikes off the corners.
const _FACE := [
	"................",
	"................",
	"..RRR....R...R..",
	".R...R....R.R...",
	".R.C.R.....R....",
	".R...R....R.R...",
	"..RRR....R...R..",
	"................",
	"R..............R",
	".RRRRRRRRRRRRRR.",
	".R.R..R..R..R.R.",
	".R............R.",
	"..R.R..RR..R.R..",
	"...RRRRRRRRRR...",
	"....R......R....",
	"................",
]
## The suit atlas is this many times Models.ATLAS_SIZE. UVs are normalised, so the avatar meshes
## map it unchanged; every normal texel is a SUIT_SCALE x SUIT_SCALE block except on the face.
const SUIT_SCALE := 2
## Atlas row where each part starts on the 32-row body (head top = 0): the pulse phase.
const _PART_ROW := {"head": 0, "torso": 8, "arm_r": 8, "arm_l": 8, "thigh_r": 20, "thigh_l": 20,
	"shin_r": 26, "shin_l": 26}


## The shared Dev Suit material (atlas ShaderMaterial). Use it wherever Models.outfit_material()
## would be used for "dev_suit".
static func outfit_material() -> ShaderMaterial:
	if _outfit_mat != null:
		return _outfit_mat
	var n := Models.ATLAS_SIZE * SUIT_SCALE
	var albedo := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var mask := Image.create(n, n, false, Image.FORMAT_RGBA8)
	albedo.fill(BLACK)
	mask.fill(Color(0, 0, 0, 0))
	for part: String in Models.AVATAR_PARTS:
		var origin: Vector2i = Models.AVATAR_PARTS[part][0]
		var dims: Vector3i = Models.AVATAR_PARTS[part][1]
		for face in 6:
			var r := _face_rect(origin, dims, face)
			var is_face := part == "head" and face == 0
			for y in r.size.y:
				for x in r.size.x:
					var row: float = _PART_ROW[part] + (0 if face == 4 else (dims.y if face == 5 else y))
					var px := r.position + Vector2i(x, y)
					var ch := _suit_char(part, face, x, y, r.size.x, r.size.y)
					for sy in SUIT_SCALE:
						for sx in SUIT_SCALE:
							if is_face:
								ch = _FACE[y * SUIT_SCALE + sy][x * SUIT_SCALE + sx]
							var sp := px * SUIT_SCALE + Vector2i(sx, sy)
							albedo.set_pixel(sp.x, sp.y, _suit_albedo(ch, px))
							mask.set_pixel(sp.x, sp.y, _suit_mask(ch, row / 32.0))
	var sm := ShaderMaterial.new()
	sm.shader = shader("outfit")
	_base_params(sm)
	sm.set_shader_parameter("albedo_tex", ImageTexture.create_from_image(albedo))
	sm.set_shader_parameter("mask_tex", ImageTexture.create_from_image(mask))
	_outfit_mat = sm
	return sm


## Same layout as Models._face_rect (copied so this file stands alone).
static func _face_rect(o: Vector2i, d: Vector3i, face: int) -> Rect2i:
	match face:
		0: return Rect2i(o.x + d.z, o.y + d.z, d.x, d.y)
		1: return Rect2i(o.x + 2 * d.z + d.x, o.y + d.z, d.x, d.y)
		2: return Rect2i(o.x, o.y + d.z, d.z, d.y)
		3: return Rect2i(o.x + d.z + d.x, o.y + d.z, d.z, d.y)
		4: return Rect2i(o.x + d.z, o.y, d.x, d.z)
	return Rect2i(o.x + d.z + d.x, o.y, d.x, d.z)


static func _suit_char(part: String, face: int, x: int, y: int, w: int, h: int) -> String:
	var side := face == 2 or face == 3
	match part:
		"head":
			# Front: the _FACE grin (painted in outfit_material). Neon ring round the crown, spine down the back.
			if face == 4 and (x == 0 or y == 0 or x == w - 1 or y == h - 1):
				return "R"
			if face == 1:
				return _HEAD_BACK[y][x]
			return "."
		"torso":
			match face:
				0: return _TORSO_FRONT[y][x]
				1: return _TORSO_BACK[y][x]
				2, 3:
					if y == 0 or y == 10:
						return "R"
					return "-" if y == 11 else "."
			return "."
		"arm_r", "arm_l":
			var outer := (face == 2 and part == "arm_r") or (face == 3 and part == "arm_l")
			if face <= 3 and y == 8:
				return "R"
			if outer and y >= 1 and y <= 7 and x == 1:
				return "o" if y == 1 else "g"
			if face <= 3 and y == 0:
				return "-"
			return "."
		"thigh_r", "thigh_l":
			var outer := (face == 2 and part == "thigh_r") or (face == 3 and part == "thigh_l")
			if outer and x == 1 and face <= 3:
				return "g"
			return "."
	# Shins: neon knee pads, the trace runs on down to glowing soles.
	var outer := (face == 2 and part == "shin_r") or (face == 3 and part == "shin_l")
	if face == 5 or (face <= 3 and y == h - 1):
		return "R"
	if face == 0 and y == 0 and (x == 1 or x == 2):
		return "R"
	if outer and x == 1 and y <= 2:
		return "g"
	if face <= 3 and y == 3:
		return "-"
	return "."


static func _suit_albedo(ch: String, px: Vector2i) -> Color:
	match ch:
		"g": return NEON.darkened(0.78)
		"R", "o": return NEON.darkened(0.45)
		"C": return HOT.darkened(0.2)
		"-": return SEAM
	# Matte black with a barely-there grain so flat faces don't look like holes.
	var h := float(hash(px) & 0xff) / 255.0
	return BLACK.lerp(Color("0c0e12"), h * 0.6)


static func _suit_mask(ch: String, phase: float) -> Color:
	match ch:
		"g": return Color(0, 1, phase, 0)
		"R": return Color(1, 0, phase, 0)
		"o": return Color(1, 0.6, phase, 0)
		"C": return Color(0.6, 0, phase, 1)
	return Color(0, 0, phase, 0)


# --- Dev Circuit (weapon skin) -----------------------------------------------------------------

## The shared Dev Circuit material. Use it wherever Models.skin_material() would be used for
## "dev_circuit" (the gun's BODY slot).
static func skin_material() -> ShaderMaterial:
	if _skin_mat != null:
		return _skin_mat
	const N := 32
	var albedo := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var mask := Image.create(N, N, false, Image.FORMAT_RGBA8)
	# Carbon weave: 2x2 twill of two near-blacks.
	for y in N:
		for x in N:
			var twill := ((x >> 1) + (y >> 1)) % 2 == 0
			albedo.set_pixel(x, y, BLACK if twill else Color("0d0f13"))
			mask.set_pixel(x, y, Color.BLACK)
	# Four horizontal bus lines, each jogging down and back up once, tiling seamlessly.
	var jogs := [[3, 13, 3], [19, 27, 2], [6, 22, 3], [11, 25, -3]]
	for k in 4:
		var y0 := 8 * k + (2 if jogs[k][2] > 0 else 6)
		var a: int = jogs[k][0]
		var b: int = jogs[k][1]
		var dy: int = jogs[k][2]
		for x in N:
			var y := y0 + (dy if x > a and x < b else 0)
			_trace(albedo, mask, x, y)
		for s in absi(dy) + 1:
			_trace(albedo, mask, a, y0 + signi(dy) * s)
			_trace(albedo, mask, b, y0 + signi(dy) * s)
		# A stub off the jog ending in a pad.
		var sx := (a + b) / 2
		var sy := y0 + dy
		for s in 2:
			_trace(albedo, mask, sx, sy - signi(dy) * (s + 1))
		_pad(albedo, mask, sx, sy - signi(dy) * 3)
	albedo.generate_mipmaps()
	mask.generate_mipmaps()
	var sm := ShaderMaterial.new()
	sm.shader = shader("skin")
	_base_params(sm)
	sm.set_shader_parameter("albedo_tex", ImageTexture.create_from_image(albedo))
	sm.set_shader_parameter("mask_tex", ImageTexture.create_from_image(mask))
	_skin_mat = sm
	return sm


static func _trace(albedo: Image, mask: Image, x: int, y: int) -> void:
	x = posmod(x, albedo.get_width())
	y = posmod(y, albedo.get_height())
	if mask.get_pixel(x, y).g > 0.5:
		return
	albedo.set_pixel(x, y, NEON.darkened(0.75))
	mask.set_pixel(x, y, Color(1, 0, 0))


static func _pad(albedo: Image, mask: Image, x: int, y: int) -> void:
	x = posmod(x, albedo.get_width())
	y = posmod(y, albedo.get_height())
	albedo.set_pixel(x, y, NEON.darkened(0.4))
	mask.set_pixel(x, y, Color(0, 1, 0))


# --- Dev Halo (hat) and Dev Core (charm) -------------------------------------------------------

## Flat pack material: black (neon_amt 0) or neon (1).
static func solid_material(neon_part: bool, metallic := 0.3, roughness := 0.4) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f" % [neon_part, metallic, roughness]
	if _solid_mats.has(key):
		return _solid_mats[key]
	var sm := ShaderMaterial.new()
	sm.shader = shader("solid")
	_base_params(sm)
	sm.set_shader_parameter("albedo", NEON.darkened(0.3) if neon_part else BLACK)
	sm.set_shader_parameter("neon_amt", 1.0 if neon_part else 0.0)
	sm.set_shader_parameter("metallic", metallic)
	sm.set_shader_parameter("roughness", roughness)
	_solid_mats[key] = sm
	return sm


## Dev Halo mesh; origin at the top centre of the 0.45 m avatar head, front -Z (as Models._hat_mesh).
static func hat_mesh() -> ArrayMesh:
	if _hat_mesh != null:
		return _hat_mesh
	var k := MeshKit.new()
	const BLK := 0
	const GLO := 1
	# Circlet: four black walls hugging the top of the head, with a neon inlay round the outside.
	const R := 0.237
	for sx: float in [1.0, -1.0]:
		k.box(BLK, Vector3(0, -0.035, R * sx), Vector3(0.5, 0.07, 0.026))
		k.box(BLK, Vector3(R * sx, -0.035, 0), Vector3(0.026, 0.07, 0.448))
		k.box(GLO, Vector3(0, -0.035, (R + 0.014) * sx), Vector3(0.44, 0.012, 0.004))
		k.box(GLO, Vector3((R + 0.014) * sx, -0.035, 0), Vector3(0.004, 0.012, 0.44))
	# Front node on the circlet.
	k.box(BLK, Vector3(0, -0.035, -R - 0.012), Vector3(0.07, 0.07, 0.02))
	k.box(GLO, Vector3(0, -0.035, -R - 0.023), Vector3(0.03, 0.03, 0.004))
	# Floating diamond halo: a square ring turned 45 degrees.
	const SIDE := 0.3
	const BAR := 0.022
	for i in 4:
		var th := PI * 0.25 + i * PI * 0.5
		var c := Vector3(cos(th), 0, sin(th)) * (SIDE * 0.5)
		k.box(GLO, c + Vector3(0, 0.15, 0), Vector3(SIDE + BAR, BAR, BAR), Vector3(0, -(th + PI * 0.5), 0))
	# Floating "</>" glyph above the halo, in pixel blocks.
	const P := 0.024
	var pixels := [[2, 0], [1, 1], [0, 2], [1, 3], [2, 4],
		[6, 0], [6, 1], [5, 2], [4, 3], [4, 4],
		[8, 0], [9, 1], [10, 2], [9, 3], [8, 4]]
	for p: Array in pixels:
		k.box(GLO, Vector3((p[0] - 5) * P, 0.37 - p[1] * P, 0), Vector3(P, P, 0.02))
	_hat_mesh = k.build([solid_material(false, 0.5, 0.3), solid_material(true)])
	return _hat_mesh


## Dev Halo node, like Models.build_hat().
static func build_hat() -> Node3D:
	var root := Node3D.new()
	root.name = "Hat"
	var mi := MeshInstance3D.new()
	mi.mesh = hat_mesh()
	root.add_child(mi)
	return root


## Dev Core charm mesh, same frame as GunCharm.mesh_for(): ring and chain from the origin down to
## the trinket around (0, -GunCharm.LENGTH, 0).
static func charm_mesh(length := 0.05) -> ArrayMesh:
	if _charm_mesh != null:
		return _charm_mesh
	var k := MeshKit.new()
	const CORE := 0
	const CAGE := 1
	const CHAIN := 2
	k.box(CHAIN, Vector3(0, -0.003, 0), Vector3(0.006, 0.006, 0.006))
	for i in 3:
		k.box(CHAIN, Vector3(0, -0.01 - i * 0.009, 0), Vector3(0.0025, 0.007, 0.0025), Vector3(0, i * 1.57, 0))
	var c := Vector3(0, -length, 0)
	k.box(CORE, c, Vector3(0.017, 0.017, 0.017))
	# Neon wireframe cage: the twelve edges of a 0.028 m cube.
	const H := 0.014
	const T := 0.003
	for a: float in [-H, H]:
		for b: float in [-H, H]:
			k.box(CAGE, c + Vector3(0, a, b), Vector3(2 * H + T, T, T))
			k.box(CAGE, c + Vector3(a, 0, b), Vector3(T, 2 * H + T, T))
			k.box(CAGE, c + Vector3(a, b, 0), Vector3(T, T, 2 * H + T))
	# Tiny lit pip in the middle of the core's front and back.
	k.box(CAGE, c + Vector3(0, 0, -0.0088), Vector3(0.005, 0.005, 0.001))
	k.box(CAGE, c + Vector3(0, 0, 0.0088), Vector3(0.005, 0.005, 0.001))
	_charm_mesh = k.build([solid_material(false, 0.5, 0.3), solid_material(true), solid_material(false, 0.85, 0.25)])
	return _charm_mesh
