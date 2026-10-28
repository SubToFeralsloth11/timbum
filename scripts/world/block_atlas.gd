class_name BlockAtlas
extends RefCounted
## Block catalog plus the procedurally painted 16x16 pixel-art tile set.
##
## Tiles are stored as layers of one `Texture2DArray` (an atlas whose tiles
## never bleed into each other at any mip level). Every block id maps to a
## top, side and bottom tile layer. Everything is generated once and cached.

const TILE := 16

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const COBBLE := 4
const PLANKS := 5
const DARK_PLANKS := 6
const LOG := 7
const LEAVES := 8
const PINE := 9
const BRICK := 10
const SAND := 11
const SANDSTONE := 12
const CARVED := 13
const SNOW := 14
const SNOW_BLOCK := 15
const ICE := 16
const METAL := 17
const CONCRETE := 18
const GLASS := 19
const LAMP := 20
const GOLD := 21
const HAZARD := 22
const RED := 23
const BLUE := 24
const YELLOW := 25
const GREEN := 26
const WHITE := 27
const ORANGE := 28
const TEAL := 29
const ROOF := 30
const GRAVEL := 31
const CRATE := 32
const CONVEYOR := 33
const GRATE := 34
const STONE_BRICK := 35
const CONTAINER_RED := 36
const CONTAINER_BLUE := 37
const PINE_SNOW := 38
const CONTAINER_GREEN := 39
const CONTAINER_YELLOW := 40
const WATER := 41
const MOSSY_BRICK := 42
const BLOCK_COUNT := 43

## Per block id: [top tile, side tile, bottom tile].
const _FACES: Array = [
	["", "", ""],
	["grass_top", "grass_side", "dirt"],
	["dirt", "dirt", "dirt"],
	["stone", "stone", "stone"],
	["cobble", "cobble", "cobble"],
	["planks", "planks", "planks"],
	["dark_planks", "dark_planks", "dark_planks"],
	["log_top", "log_side", "log_top"],
	["leaves", "leaves", "leaves"],
	["pine", "pine", "pine"],
	["brick", "brick", "brick"],
	["sand", "sand", "sand"],
	["sandstone_top", "sandstone", "sandstone_top"],
	["sandstone_top", "carved", "sandstone_top"],
	["snow_top", "snow_side", "dirt"],
	["snow_top", "snow_top", "snow_top"],
	["ice", "ice", "ice"],
	["metal", "metal", "metal"],
	["concrete", "concrete", "concrete"],
	["glass", "glass", "glass"],
	["lamp", "lamp", "lamp"],
	["gold", "gold", "gold"],
	["hazard", "hazard", "hazard"],
	["wool_red", "wool_red", "wool_red"],
	["wool_blue", "wool_blue", "wool_blue"],
	["wool_yellow", "wool_yellow", "wool_yellow"],
	["wool_green", "wool_green", "wool_green"],
	["wool_white", "wool_white", "wool_white"],
	["wool_orange", "wool_orange", "wool_orange"],
	["wool_teal", "wool_teal", "wool_teal"],
	["roof", "roof", "dark_planks"],
	["gravel", "gravel", "gravel"],
	["crate_top", "crate", "crate_top"],
	["conveyor", "metal", "metal"],
	["grate", "grate", "grate"],
	["stone_brick", "stone_brick", "stone_brick"],
	["container_top", "container_red", "container_top"],
	["container_top", "container_blue", "container_top"],
	["pine_snow", "pine", "pine"],
	["container_top", "container_green", "container_top"],
	["container_top", "container_yellow", "container_top"],
	["water", "water", "water"],
	["mossy_brick", "mossy_brick", "mossy_brick"],
]

const _WOOL := {
	"wool_red": "c2423b", "wool_blue": "3c5fc2", "wool_yellow": "e6c03c",
	"wool_green": "4f9b3a", "wool_white": "e6e6df", "wool_orange": "df7a2c",
	"wool_teal": "2b9b97",
}

const _SHADER_CODE := """
shader_type spatial;
render_mode %s;

uniform sampler2DArray tiles : source_color, filter_nearest_mipmap_anisotropic, repeat_disable;

varying flat float v_layer;
varying flat float v_emit;

void vertex() {
	v_layer = UV2.x;
	v_emit = UV2.y;
}

void fragment() {
	vec4 t = texture(tiles, vec3(UV, v_layer));
	ALBEDO = t.rgb * COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	EMISSION = t.rgb * v_emit;
	%s
}
"""

static var _texture: Texture2DArray
static var _face_layers := PackedInt32Array()
static var _top_colors := PackedColorArray()
static var _opaque_material: ShaderMaterial
static var _glass_material: ShaderMaterial


## Tile layer for `block`'s face: 0 top, 1 side, 2 bottom.
static func face_layers() -> PackedInt32Array:
	_ensure()
	return _face_layers


static func emission(block: int) -> float:
	return 3.0 if block == LAMP else 0.0


static func is_transparent(block: int) -> bool:
	return block == GLASS


## Average colour of the block's top tile (used for minimap previews).
static func top_color(block: int) -> Color:
	_ensure()
	return _top_colors[block]


static func texture() -> Texture2DArray:
	_ensure()
	return _texture


static func material(transparent: bool) -> ShaderMaterial:
	_ensure()
	return _glass_material if transparent else _opaque_material


static func _ensure() -> void:
	if _texture != null:
		return
	var names: Array[String] = []
	var index := {}
	for faces: Array in _FACES:
		for n: String in faces:
			if n != "" and not index.has(n):
				index[n] = names.size()
				names.append(n)
	var images: Array[Image] = []
	var averages: Array[Color] = []
	for n in names:
		var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(n)
		_paint(n, img, rng)
		averages.append(_average(img))
		img.generate_mipmaps()
		images.append(img)
	_texture = Texture2DArray.new()
	_texture.create_from_images(images)
	_face_layers.resize(BLOCK_COUNT * 3)
	_top_colors.resize(BLOCK_COUNT)
	for b in BLOCK_COUNT:
		for f in 3:
			var n: String = _FACES[b][f]
			_face_layers[b * 3 + f] = index[n] if n != "" else 0
		_top_colors[b] = averages[index[_FACES[b][0]]] if b != AIR else Color(0, 0, 0, 0)
	_opaque_material = _make_material(false)
	_glass_material = _make_material(true)


static func _make_material(transparent: bool) -> ShaderMaterial:
	var shader := Shader.new()
	if transparent:
		shader.code = _SHADER_CODE % ["blend_mix, cull_back, depth_draw_opaque", "ALPHA = t.a;"]
	else:
		shader.code = _SHADER_CODE % ["cull_back", ""]
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tiles", _texture)
	return mat


static func _average(img: Image) -> Color:
	var acc := Color(0, 0, 0, 0)
	for y in TILE:
		for x in TILE:
			acc += img.get_pixel(x, y)
	return acc / float(TILE * TILE)


# --- painting -----------------------------------------------------------------

static func _paint(n: String, img: Image, rng: RandomNumberGenerator) -> void:
	if _WOOL.has(n):
		_wool(img, rng, Color(_WOOL[n]))
		return
	match n:
		"grass_top":
			_noise(img, rng, Color("5f9e3f"), 0.05)
			_sprinkle(img, rng, Color("82c057"), 22)
			_sprinkle(img, rng, Color("4a8331"), 16)
		"grass_side":
			_dirt(img, rng)
			for x in TILE:
				var depth := 3 + rng.randi_range(0, 2)
				for y in depth:
					_dot(img, x, y, _vary(Color("5f9e3f") if y > 0 else Color("74b14c"), rng, 0.05))
				if rng.randf() < 0.4:
					_dot(img, x, depth, Color("4a8331"))
		"dirt":
			_dirt(img, rng)
		"stone":
			_noise(img, rng, Color("8a8c8f"), 0.05)
			for i in 7:
				var x := rng.randi_range(0, 15)
				var y := rng.randi_range(0, 15)
				for k in rng.randi_range(2, 4):
					_dot(img, x + k, y, Color("6d6f73"))
					_dot(img, x + k, y - 1, Color("a1a3a6"))
		"cobble":
			_cells(img, rng, [Color("8f9194"), Color("85878a"), Color("7c7e82"), Color("989a9d")], Color("5d5f62"), 8)
		"stone_brick":
			_bricks(img, rng, 8, 8, [Color("8e9093"), Color("85878a"), Color("96989b")], Color("56585b"))
		"planks":
			_planks(img, rng, Color("b28a52"))
		"dark_planks":
			_planks(img, rng, Color("6e4c2c"))
		"log_side":
			_noise(img, rng, Color("6b4e2d"), 0.05)
			for x in TILE:
				if rng.randf() < 0.35:
					var y0 := rng.randi_range(0, 15)
					for k in rng.randi_range(4, 10):
						_dot(img, x, y0 + k, Color("4a3520"))
		"log_top":
			for y in TILE:
				for x in TILE:
					var r := Vector2(x - 7.5, y - 7.5).length()
					var c := Color("5e4428") if r > 6.6 else (Color("b8925a") if int(r * 0.9) % 2 == 0 else Color("a07c48"))
					_dot(img, x, y, _vary(c, rng, 0.03))
		"leaves":
			_leaves(img, rng, Color("3f8a2e"), Color("22501a"), Color("5ba83f"))
		"pine":
			_leaves(img, rng, Color("2b5a3a"), Color("142e20"), Color("3a744c"))
		"pine_snow":
			_leaves(img, rng, Color("2b5a3a"), Color("142e20"), Color("3a744c"))
			for i in 70:
				_dot(img, rng.randi_range(0, 15), rng.randi_range(0, 15), _vary(Color("eef4f8"), rng, 0.03))
		"brick":
			_bricks(img, rng, 8, 4, [Color("a3463a"), Color("b04f40"), Color("943f32"), Color("a84b3d")], Color("c8c0b2"))
		"sand":
			_noise(img, rng, Color("e2cd93"), 0.035)
			_sprinkle(img, rng, Color("cdb578"), 14)
			_sprinkle(img, rng, Color("f0e2b2"), 10)
		"sandstone":
			_noise(img, rng, Color("d8c084"), 0.03)
			for x in TILE:
				_dot(img, x, 0, Color("e8d49c"))
				_dot(img, x, 1, Color("e2cc90"))
				_dot(img, x, 15, Color("b49b62"))
				if rng.randf() < 0.5:
					_dot(img, x, 8, Color("c6ad72"))
		"sandstone_top":
			_noise(img, rng, Color("dcc58b"), 0.025)
			_border(img, Color("c4ab70"), Color("c4ab70"))
		"carved":
			_noise(img, rng, Color("d8c084"), 0.025)
			_border(img, Color("e8d49c"), Color("ad945c"))
			var glyph := [
				"................",
				"................",
				"..############..",
				"..#..........#..",
				"..#.########.#..",
				"..#.#......#.#..",
				"..#.#.####.#.#..",
				"..#.#.#..#.#.#..",
				"..#.#.#..#.#.#..",
				"..#.#.####.#.#..",
				"..#.#......#.#..",
				"..#.###..###.#..",
				"..#..........#..",
				"..############..",
				"................",
				"................",
			]
			for y in TILE:
				for x in TILE:
					if glyph[y][x] == "#":
						_dot(img, x, y, Color("a88f58"))
						if glyph[y - 1][x] != "#":
							_dot(img, x, y - 1, Color("ead8a4"))
		"snow_top":
			_noise(img, rng, Color("eef3f8"), 0.02)
			_sprinkle(img, rng, Color("d6e2ee"), 18)
		"snow_side":
			_dirt(img, rng)
			for x in TILE:
				var depth := 4 + rng.randi_range(0, 2)
				for y in depth:
					_dot(img, x, y, _vary(Color("eef3f8"), rng, 0.02))
				if rng.randf() < 0.35:
					_dot(img, x, depth, Color("d6e2ee"))
		"ice":
			_noise(img, rng, Color("9fcdea"), 0.03)
			for y in TILE:
				for x in TILE:
					if (x + y) % 9 == 0 or ((x + y) % 9 == 1 and x % 3 != 0):
						_dot(img, x, y, Color("cfe8f8"))
			_border(img, Color("c2e2f6"), Color("83b6d6"))
		"metal":
			_noise(img, rng, Color("8d959d"), 0.02)
			_border(img, Color("b8c0c8"), Color("5b626a"))
			for p: Vector2i in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13)]:
				_dot(img, p.x, p.y, Color("cfd6dc"))
				_dot(img, p.x + 1, p.y + 1, Color("4f565d"))
		"concrete":
			_noise(img, rng, Color("a5a39d"), 0.025)
			_sprinkle(img, rng, Color("8f8d87"), 12)
			for x in TILE:
				_dot(img, x, 15, Color("96948e"))
		"glass":
			img.fill(Color(0.72, 0.88, 1.0, 0.16))
			_border(img, Color(0.86, 0.93, 0.97, 0.95), Color(0.62, 0.72, 0.8, 0.95))
			for k in 4:
				_dot(img, 4 + k, 9 - k, Color(1, 1, 1, 0.55))
				_dot(img, 4 + k + 2, 9 - k, Color(1, 1, 1, 0.35))
		"lamp":
			for y in TILE:
				for x in TILE:
					var d := maxf(absf(x - 7.5), absf(y - 7.5))
					_dot(img, x, y, Color("fff1c0") if d < 3.0 else Color("ffd473"))
			for k in TILE:
				_dot(img, k, 7, Color("6a5a3a"))
				_dot(img, 7, k, Color("6a5a3a"))
			_border(img, Color("4a463f"), Color("2f2c27"))
		"gold":
			_noise(img, rng, Color("efc030"), 0.04)
			_border(img, Color("fff0a0"), Color("b8891a"))
			for k in 5:
				_dot(img, 3 + k, 3, Color("fff6c2"))
				_dot(img, 3, 3 + k, Color("fff6c2"))
		"hazard":
			for y in TILE:
				for x in TILE:
					var c := Color("f0be2c") if ((x + y) / 4) % 2 == 0 else Color("2b2a28")
					_dot(img, x, y, _vary(c, rng, 0.03))
		"roof":
			for y in TILE:
				var row := y / 4
				for x in TILE:
					var col := (x + (2 if row % 2 == 1 else 0)) / 4
					var c := Color("b04e38").darkened(0.06 * float((col * 7 + row * 3) % 3))
					if y % 4 == 3:
						c = Color("6f2f22")
					elif y % 4 == 0:
						c = c.lightened(0.12)
					if (x + (2 if row % 2 == 1 else 0)) % 4 == 0:
						c = c.darkened(0.25)
					_dot(img, x, y, _vary(c, rng, 0.03))
		"gravel":
			_cells(img, rng, [Color("8c8781"), Color("96918b"), Color("827d77"), Color("9d9892"), Color("8a7f72")], Color("6e6963"), 14)
		"crate":
			_planks(img, rng, Color("b88a50"))
			_border(img, Color("7a5630"), Color("5e4124"))
			for x in TILE:
				_dot(img, x, 1, Color("7a5630"))
				_dot(img, x, 14, Color("5e4124"))
			for k in range(2, 14):
				_dot(img, k, 15 - k, Color("8a6238"))
				_dot(img, k + 1, 15 - k, Color("6e4c2a"))
		"crate_top":
			_planks(img, rng, Color("b88a50"))
			_border(img, Color("7a5630"), Color("5e4124"))
		"conveyor":
			_noise(img, rng, Color("33363a"), 0.03)
			for y in TILE:
				for x in range(3, 13):
					if (y + int(absf(x - 7.5))) % 6 < 2:
						_dot(img, x, y, Color("707781"))
				for x: int in [0, 1, 14, 15]:
					_dot(img, x, y, Color("a9b1b9") if x == 0 or x == 14 else Color("6a7179"))
		"grate":
			img.fill(Color("26292d"))
			for y in TILE:
				for x in TILE:
					if x % 4 == 0 or y % 4 == 0:
						_dot(img, x, y, Color("7c848c") if y % 4 == 0 else Color("646c74"))
			_border(img, Color("9aa2aa"), Color("4b5259"))
		"container_red", "container_blue", "container_green", "container_yellow":
			var base: Color = {
				"container_red": Color("a8382e"), "container_blue": Color("2f5c9a"),
				"container_green": Color("3f7a45"), "container_yellow": Color("c99a2e"),
			}[n]
			_noise(img, rng, base, 0.02)
			for x in TILE:
				if x % 4 == 1:
					for y in TILE:
						_dot(img, x, y, base.lightened(0.15))
				elif x % 4 == 2:
					for y in TILE:
						_dot(img, x, y, base.darkened(0.25))
			for x in TILE:
				_dot(img, x, 0, base.darkened(0.4))
				_dot(img, x, 15, base.darkened(0.4))
		"container_top":
			_noise(img, rng, Color("7f868d"), 0.02)
			_border(img, Color("a3aab1"), Color("575e65"))
		"water":
			_noise(img, rng, Color("2a6f8f"), 0.025)
			for y in TILE:
				for x in TILE:
					if (x * 2 + y * 3) % 11 == 0 and rng.randf() < 0.7:
						_dot(img, x, y, Color("5aa2c0"))
		"mossy_brick":
			_bricks(img, rng, 8, 8, [Color("7f8478"), Color("767b6e"), Color("878c80")], Color("4c5046"))
			for i in 40:
				var x := rng.randi_range(0, 15)
				var y := rng.randi_range(0, 15)
				_dot(img, x, y, _vary(Color("4f7a33"), rng, 0.06))
				if rng.randf() < 0.5:
					_dot(img, x + 1, y, Color("5f8c3c"))
		_:
			push_error("BlockAtlas: unknown tile %s" % n)


static func _dot(img: Image, x: int, y: int, c: Color) -> void:
	img.set_pixel(x & 15, y & 15, c)


static func _vary(c: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var v := float(rng.randi_range(-2, 2)) * amount
	return c.lightened(v) if v > 0.0 else c.darkened(-v)


static func _noise(img: Image, rng: RandomNumberGenerator, base: Color, amount: float) -> void:
	for y in TILE:
		for x in TILE:
			_dot(img, x, y, _vary(base, rng, amount))


static func _sprinkle(img: Image, rng: RandomNumberGenerator, c: Color, count: int) -> void:
	for i in count:
		_dot(img, rng.randi_range(0, 15), rng.randi_range(0, 15), c)


static func _border(img: Image, light: Color, dark: Color) -> void:
	for k in TILE:
		_dot(img, k, 0, light)
		_dot(img, 0, k, light)
		_dot(img, k, 15, dark)
		_dot(img, 15, k, dark)


static func _dirt(img: Image, rng: RandomNumberGenerator) -> void:
	_noise(img, rng, Color("86603e"), 0.06)
	_sprinkle(img, rng, Color("5f4229"), 10)
	_sprinkle(img, rng, Color("a17a52"), 8)


static func _wool(img: Image, rng: RandomNumberGenerator, base: Color) -> void:
	for y in TILE:
		for x in TILE:
			var c := base.darkened(0.1) if (x + y * 2) % 4 == 0 else base
			_dot(img, x, y, _vary(c, rng, 0.025))


static func _leaves(img: Image, rng: RandomNumberGenerator, base: Color, hole: Color, light: Color) -> void:
	_noise(img, rng, base, 0.05)
	for i in 34:
		_dot(img, rng.randi_range(0, 15), rng.randi_range(0, 15), hole)
	for i in 18:
		var x := rng.randi_range(0, 15)
		var y := rng.randi_range(0, 15)
		_dot(img, x, y, light)
		_dot(img, x + 1, y, light.darkened(0.08))


static func _planks(img: Image, rng: RandomNumberGenerator, base: Color) -> void:
	for board in 4:
		var c := base.darkened(0.06 * float(rng.randi_range(0, 2)))
		var seam := rng.randi_range(0, 15)
		for y in range(board * 4, board * 4 + 4):
			for x in TILE:
				var p := _vary(c, rng, 0.025)
				if y % 4 == 3:
					p = base.darkened(0.35)
				elif x == seam:
					p = base.darkened(0.3)
				elif y % 4 == 0:
					p = p.lightened(0.06)
				_dot(img, x, y, p)
		for i in 3:
			var gx := rng.randi_range(0, 15)
			var gy := board * 4 + rng.randi_range(0, 2)
			_dot(img, gx, gy, c.darkened(0.15))
			_dot(img, gx + 1, gy, c.darkened(0.15))


static func _bricks(img: Image, rng: RandomNumberGenerator, w: int, h: int, shades: Array, mortar: Color) -> void:
	for row in TILE / h:
		var offset := (w / 2) if row % 2 == 1 else 0
		for y in range(row * h, row * h + h):
			for x in TILE:
				var bx := (x + offset) % TILE
				var brick := (bx / w) + row * 5
				var c: Color = shades[brick % shades.size()]
				if y % h == h - 1 or bx % w == w - 1:
					c = mortar
				elif y % h == 0:
					c = c.lightened(0.08)
				_dot(img, x, y, _vary(c, rng, 0.025))


## Voronoi stones separated by mortar lines; tiles seamlessly.
static func _cells(img: Image, rng: RandomNumberGenerator, shades: Array, mortar: Color, count: int) -> void:
	var pts: Array[Vector2] = []
	var cols: Array[Color] = []
	for i in count:
		pts.append(Vector2(rng.randf() * TILE, rng.randf() * TILE))
		cols.append(shades[rng.randi() % shades.size()])
	for y in TILE:
		for x in TILE:
			var p := Vector2(x + 0.5, y + 0.5)
			var d1 := INF
			var d2 := INF
			var best := 0
			for i in count:
				var d := p - pts[i]
				d.x = absf(d.x)
				d.y = absf(d.y)
				d.x = minf(d.x, TILE - d.x)
				d.y = minf(d.y, TILE - d.y)
				var l := d.length()
				if l < d1:
					d2 = d1
					d1 = l
					best = i
				elif l < d2:
					d2 = l
			var c := mortar if d2 - d1 < 1.0 else _vary(cols[best], rng, 0.025)
			if d2 - d1 >= 1.0 and d2 - d1 < 2.0:
				c = c.lightened(0.04)
			_dot(img, x, y, c)
