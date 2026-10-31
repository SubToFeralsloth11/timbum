class_name SprayArt
extends RefCounted
## Sprays (Data.SPRAYS): 16x16 pixel-art stickers drawn from the character grids below. Each
## character is a PALETTE colour ("." is clear); a black outline is added around the shape and
## every pixel gets a little seeded grain, so the result looks sprayed on. `texture(id)` is the
## in-world decal (upscaled 4x with nearest filtering so the decal's filtering keeps the pixels
## sharp), `icon(id)` the 32 px menu icon.

const SIZE := 16
const UPSCALE := 4
const OUTLINE := Color(0.06, 0.06, 0.08)
const PALETTE := {
	"w": Color(0.96, 0.96, 0.94), "k": Color(0.06, 0.06, 0.08), "r": Color(0.92, 0.16, 0.2),
	"o": Color(1.0, 0.52, 0.1), "y": Color(1.0, 0.86, 0.16), "g": Color(0.38, 0.82, 0.26),
	"c": Color(0.2, 0.88, 1.0), "b": Color(0.22, 0.45, 1.0), "p": Color(1.0, 0.36, 0.76),
	"n": Color(0.6, 0.38, 0.2), "m": Color(0.4, 0.25, 0.14),
}
const ART := {
	"gg": [
		"................",
		"................",
		"................",
		"................",
		"..cccc....pppp..",
		".cccccc..pppppp.",
		".cc......pp.....",
		".cc.ccc..pp.ppp.",
		".cc..cc..pp..pp.",
		".cccccc..pppppp.",
		"..cccc....pppp..",
		"................",
		"................",
		"................",
		"................",
		"................",
	],
	"heart": [
		"................",
		"................",
		"...rrr....rrr...",
		"..rrrrr..rrrrr..",
		".rrwwrrrrrrrrrr.",
		".rrwrrrrrrrrrrr.",
		".rrrrrrrrrrrrrr.",
		".rrrrrrrrrrrrrr.",
		"..rrrrrrrrrrrr..",
		"...rrrrrrrrrr...",
		"....rrrrrrrr....",
		".....rrrrrr.....",
		"......rrrr......",
		".......rr.......",
		"................",
		"................",
	],
	"smile": [
		"................",
		".....yyyyyy.....",
		"...yyyyyyyyyy...",
		"..yyyyyyyyyyyy..",
		"..yyyyyyyyyyyy..",
		".yyyykyyyykyyyy.",
		".yyyykyyyykyyyy.",
		".yyyyyyyyyyyyyy.",
		".yyyyyyyyyyyyyy.",
		".yykyyyyyyyykyy.",
		"..yykyyyyyykyy..",
		"..yyykkkkkkyyy..",
		"...yyyyyyyyyy...",
		".....yyyyyy.....",
		"................",
		"................",
	],
	"star": [
		"................",
		".......yy.......",
		".......yy.......",
		"......yyyy......",
		"......yyyy......",
		".yyyyyyyyyyyyyy.",
		"..yyyyyoyyyyyy..",
		"...yyyyoyyyyy...",
		"....yyyyyyyy....",
		"....yyyyyyyy....",
		"...yyyyyyyyyy...",
		"...yyyy..yyyy...",
		"..yyy......yyy..",
		"..yy........yy..",
		"................",
		"................",
	],
	"skull": [
		"................",
		"....wwwwwwww....",
		"...wwwwwwwwww...",
		"..wwwwwwwwwwww..",
		"..wwwwwwwwwwww..",
		"..wwkkkwwkkkww..",
		"..wwkkkwwkkkww..",
		"..wwkkkwwkkkww..",
		"..wwwwwkkwwwww..",
		"...wwwwkkwwww...",
		"....wwwwwwww....",
		".....wkwkwkw....",
		".....wwwwwww....",
		"................",
		"................",
		"................",
	],
	"bolt": [
		"................",
		".........yyyy...",
		"........yyyy....",
		".......yyyy.....",
		"......yyyy......",
		".....yyyy.......",
		"....yyyyyyyyy...",
		"...yyyyyyyyy....",
		".......yyyy.....",
		"......yyyy......",
		".....yyyy.......",
		"....yyy.........",
		"...yy...........",
		"..y.............",
		"................",
		"................",
	],
	"crown": [
		"................",
		"................",
		"................",
		".y.....yy.....y.",
		".yy...yyyy...yy.",
		".yyy.yyyyyy.yyy.",
		".yyyyyyyyyyyyyy.",
		".yyyyyyyyyyyyyy.",
		".yyryyybbyyyryy.",
		".yyyyyyyyyyyyyy.",
		".yyyyyyyyyyyyyy.",
		".oooooooooooooo.",
		"................",
		"................",
		"................",
		"................",
	],
	"ghost": [
		"................",
		".....wwwwww.....",
		"...wwwwwwwwww...",
		"..wwwwwwwwwwww..",
		"..wwwwwwwwwwww..",
		".wwwkkwwwwkkwww.",
		".wwwkbwwwwkbwww.",
		".wwwwwwwwwwwwww.",
		".wwwwwwwwwwwwww.",
		".wwwwwwwwwwwwww.",
		".wwwwwwwwwwwwww.",
		".wwwwwwwwwwwwww.",
		".ww.www..www.ww.",
		".w...w....w...w.",
		"................",
		"................",
	],
	"flame": [
		"................",
		".......r........",
		"......rr........",
		"......rrr...r...",
		".....rrrr..rr...",
		"....rrrorr.rrr..",
		"...rrroorrrrrr..",
		"...rrooyoorrrr..",
		"..rrrooyyoorrr..",
		"..rroooyyyoorr..",
		"..rrooyyyyoorr..",
		"..rrooyyyyyorr..",
		"...rroyyyyorr...",
		"....rrooooorr...",
		".....rrrrrr.....",
		"................",
	],
	"cube": [
		"................",
		".......gg.......",
		".....gggggg.....",
		"...gggggggggg...",
		".gggggggggggggg.",
		".nnggggggggggmm.",
		".nnnnggggggmmmm.",
		".nnnnnnggmmmmmm.",
		".nnnnnnnmmmmmmm.",
		".nnnnnnnmmmmmmm.",
		".nnnnnnnmmmmmmm.",
		".nnnnnnnmmmmmmm.",
		"..nnnnnnmmmmmm..",
		"....nnnnmmmm....",
		"......nnmm......",
		"................",
	],
}

static var _textures := {}
static var _icons := {}


## The 16x16 image of spray `id` (an unknown id draws "gg").
static func image(id: String) -> Image:
	var rows: Array = ART.get(id, ART.gg)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for y in SIZE:
		var row: String = rows[y]
		for x in SIZE:
			var ch := row[x]
			if ch == ".":
				continue
			var c: Color = PALETTE[ch]
			var grain := rng.randf_range(-0.07, 0.07)
			c = c.lightened(grain) if grain > 0.0 else c.darkened(-grain)
			c.a = rng.randf_range(0.86, 1.0)
			img.set_pixel(x, y, c)
	# Outline: clear pixels touching the shape (8 neighbours) turn dark.
	var shape := img.duplicate() as Image
	for y in SIZE:
		for x in SIZE:
			if shape.get_pixel(x, y).a > 0.0:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < SIZE and ny < SIZE and shape.get_pixel(nx, ny).a > 0.0:
						img.set_pixel(x, y, Color(OUTLINE, 0.92))
	return img


## Decal texture of spray `id` (cached).
static func texture(id: String) -> ImageTexture:
	if not _textures.has(id):
		var img := image(id)
		img.resize(SIZE * UPSCALE, SIZE * UPSCALE, Image.INTERPOLATE_NEAREST)
		_textures[id] = ImageTexture.create_from_image(img)
	return _textures[id]


## 32 px menu icon of spray `id` (cached).
static func icon(id: String) -> ImageTexture:
	if not _icons.has(id):
		var img := image(id)
		img.resize(SIZE * 2, SIZE * 2, Image.INTERPOLATE_NEAREST)
		_icons[id] = ImageTexture.create_from_image(img)
	return _icons[id]
