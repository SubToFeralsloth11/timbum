class_name CustomScopes
extends RefCounted
## Custom scopes (docs/ARCHITECTURE.md "Custom scopes"): the part catalog, the design codec, the
## 3D model, the reticle drawing and the ADS zoom rule.
##
## A design is a Dictionary:
##   reticle (RETICLES index), ret_color, glow (0..1), ret_scale (RETICLE_SCALE), tint (Color, a =
##   strength 0..TINT_MAX), view (VIEWS index), view_size (VIEW_SIZE, fraction of the screen
##   height), power (POWER_LIMITS, clamped per gun by power_range), rise (RISE: tube axis above the
##   mount base, m), shift (SHIFT_LIMIT: the whole scope forward (-) or back (+), m), pixels
##   (GRID x GRID bytes 0/1, the PIXEL PAINT reticle) and parts: up to MAX_PARTS entries
##   {part (PARTS index), color, finish (FINISHES index), length, width (SIZE_LIMITS), offset
##   (Vector3, each axis within OFFSET_LIMIT m), roll (ROLL_STEPS steps of 15 degrees)}.
## On disk (Profile.scope_designs, base64) and on the wire (peer_info.scopes) it is encode()'s
## bytes: HEADER bytes, then PART_BYTES per part. decode() clamps every value and drops unknown
## part indices, so it is also the sanitizer: PARTS is APPEND ONLY (saves and peers store indices).

const CATALOG := preload("res://scripts/autoload/data.gd")

## Coins: the unlock for one gun (with the STARTER parts), and every part added after that.
const UNLOCK_PRICE := 5000
const PART_PRICE := 150
const MAX_PARTS := 24
const FORMAT := 1
const HEADER := 35
const PART_BYTES := 12
const MAX_BYTES := HEADER + MAX_PARTS * PART_BYTES
## The PIXEL PAINT reticle's grid (GRID x GRID cells).
const GRID := 12

## Size of a body part at length and width 1 (m). The first body part sets the tube every other
## part fits to; without one these defaults are used.
const BASE_LENGTH := 0.16
const BASE_DIAMETER := 0.036
const RISE := Vector2(0.01, 0.08)
const DEFAULT_RISE := 0.035
const SHIFT_LIMIT := 0.06
const OFFSET_LIMIT := 0.12
const SIZE_LIMITS := Vector2(0.5, 2.0)
const ROLL_STEPS := 24
const RETICLE_SCALE := Vector2(0.5, 2.0)
const VIEW_SIZE := Vector2(0.3, 0.5)
const TINT_MAX := 0.45
## Lens power: a multiplier on the zoom of the gun's own sights (its Data ads_fov). A gun with a
## scope of its own (`scope` in Data.WEAPONS) may only zoom out (SCOPED_POWER), every other gun
## may zoom in up to 2x (SIGHTS_POWER); see ads_fov().
const POWER_LIMITS := Vector2(0.5, 2.0)
const SCOPED_POWER := Vector2(0.5, 1.0)
const SIGHTS_POWER := Vector2(1.0, 2.0)

## The parts a new unlock (and RESET) starts with, paid for by the unlock price.
const STARTER: Array[String] = ["tube_round", "two_rings", "eyepiece"]

## Catalog tabs, in order, with the colour and finish a new part of the group starts in.
const GROUPS: Array = [
	["BODY", "2a2d33", 1], ["MOUNT", "50545c", 3], ["FRONT", "2a2d33", 1], ["REAR", "1e2024", 0],
	["TURRETS", "50545c", 3], ["GEAR", "2a2d33", 0], ["DECOR", "d8343a", 2],
]

## Where a part sits (see build()): "body" (the tube, sized by its own length / width), "ring"
## (around the tube, fitted to it), "front" / "rear" (the tube's ends), "top" / "side" (right) /
## "under" (on the tube's surface), "mount" (from the gun up to the tube; width scales x only).
## APPEND ONLY: the index is what saves and peers store.
const PARTS: Array = [
	{"id": "tube_round", "name": "Round Tube", "group": "BODY", "slot": "body"},
	{"id": "tube_square", "name": "Square Block", "group": "BODY", "slot": "body"},
	{"id": "tube_octagon", "name": "Octagon Tube", "group": "BODY", "slot": "body"},
	{"id": "tube_hex", "name": "Hex Tube", "group": "BODY", "slot": "body"},
	{"id": "holo_window", "name": "Holographic Window", "group": "BODY", "slot": "body"},
	{"id": "box_reflex", "name": "Box Reflex", "group": "BODY", "slot": "body"},
	{"id": "periscope", "name": "Periscope", "group": "BODY", "slot": "body"},
	{"id": "double_tube", "name": "Double-Barrel Tube", "group": "BODY", "slot": "body"},
	{"id": "pixel_cube", "name": "Pixel Cube", "group": "BODY", "slot": "body"},
	{"id": "tapered", "name": "Tapered Tube", "group": "BODY", "slot": "body"},
	{"id": "bell", "name": "Bell Objective", "group": "BODY", "slot": "body"},
	{"id": "orb", "name": "Orb Sight", "group": "BODY", "slot": "body"},
	{"id": "prism_scope", "name": "Prism Scope", "group": "BODY", "slot": "body"},
	{"id": "long_range", "name": "Long Range Tube", "group": "BODY", "slot": "body"},
	{"id": "ring_sight", "name": "Ghost Ring Sight", "group": "BODY", "slot": "body"},
	{"id": "retro_brass", "name": "Retro Brass Tube", "group": "BODY", "slot": "body", "color": "c79a5b", "finish": 3},
	{"id": "drum_sight", "name": "Drum Sight", "group": "BODY", "slot": "body"},
	{"id": "crt", "name": "CRT Monitor", "group": "BODY", "slot": "body", "color": "e8d2a0"},
	{"id": "thermal", "name": "Thermal Block", "group": "BODY", "slot": "body"},
	{"id": "bino", "name": "Binocular Stack", "group": "BODY", "slot": "body"},
	{"id": "two_rings", "name": "Two-Ring Mount", "group": "MOUNT", "slot": "mount"},
	{"id": "one_piece", "name": "One-Piece Mount", "group": "MOUNT", "slot": "mount"},
	{"id": "offset_45", "name": "Offset 45° Mount", "group": "MOUNT", "slot": "mount"},
	{"id": "qd_mount", "name": "QD Lever Mount", "group": "MOUNT", "slot": "mount"},
	{"id": "cantilever", "name": "Cantilever Mount", "group": "MOUNT", "slot": "mount"},
	{"id": "riser_block", "name": "Riser Block", "group": "MOUNT", "slot": "mount"},
	{"id": "single_ring", "name": "Single Wide Ring", "group": "MOUNT", "slot": "mount"},
	{"id": "skeleton", "name": "Skeleton Mount", "group": "MOUNT", "slot": "mount"},
	{"id": "rail_plate", "name": "Rail Plate", "group": "MOUNT", "slot": "mount"},
	{"id": "clamp_bands", "name": "Square Clamp Bands", "group": "MOUNT", "slot": "mount"},
	{"id": "sunshade", "name": "Sunshade", "group": "FRONT", "slot": "front"},
	{"id": "honeycomb", "name": "Honeycomb Filter", "group": "FRONT", "slot": "front"},
	{"id": "flip_cap_front", "name": "Front Flip Cap", "group": "FRONT", "slot": "front"},
	{"id": "tethered_cap", "name": "Tethered Lens Cap", "group": "FRONT", "slot": "front"},
	{"id": "objective_lens", "name": "Round Objective Lens", "group": "FRONT", "slot": "front"},
	{"id": "square_lens", "name": "Square Front Lens", "group": "FRONT", "slot": "front"},
	{"id": "hex_lens", "name": "Hex Front Lens", "group": "FRONT", "slot": "front"},
	{"id": "knurled_ring", "name": "Knurled Front Ring", "group": "FRONT", "slot": "front"},
	{"id": "spiked_bezel", "name": "Spiked Bezel", "group": "FRONT", "slot": "front"},
	{"id": "flared_bell", "name": "Flared Bell", "group": "FRONT", "slot": "front"},
	{"id": "glow_ring", "name": "Glow Ring", "group": "FRONT", "slot": "front", "color": "59c4ff", "finish": 5},
	{"id": "slat_grille", "name": "Slat Grille", "group": "FRONT", "slot": "front"},
	{"id": "eyepiece", "name": "Eyepiece", "group": "REAR", "slot": "rear"},
	{"id": "eyecup", "name": "Rubber Eyecup", "group": "REAR", "slot": "rear"},
	{"id": "flip_cap_rear", "name": "Rear Flip Cap", "group": "REAR", "slot": "rear"},
	{"id": "square_eyepiece", "name": "Square Eyepiece", "group": "REAR", "slot": "rear"},
	{"id": "power_ring", "name": "Power Ring + Throw Lever", "group": "REAR", "slot": "rear"},
	{"id": "eyebrow", "name": "Eyebrow Shade", "group": "REAR", "slot": "rear"},
	{"id": "rear_glow_ring", "name": "Rear Glow Ring", "group": "REAR", "slot": "rear", "color": "ff4fae", "finish": 5},
	{"id": "elevation_turret", "name": "Elevation Turret", "group": "TURRETS", "slot": "top"},
	{"id": "windage_turret", "name": "Windage Turret", "group": "TURRETS", "slot": "side"},
	{"id": "tall_turret", "name": "Tall Target Turret", "group": "TURRETS", "slot": "top"},
	{"id": "capped_turret", "name": "Capped Turret", "group": "TURRETS", "slot": "top"},
	{"id": "focus_wheel", "name": "Side Focus Wheel", "group": "TURRETS", "slot": "side"},
	{"id": "illum_knob", "name": "Illumination Knob", "group": "TURRETS", "slot": "side"},
	{"id": "zero_stop", "name": "Zero-Stop Dial", "group": "TURRETS", "slot": "top"},
	{"id": "turret_stack", "name": "Turret Stack", "group": "TURRETS", "slot": "top"},
	{"id": "top_rail", "name": "Top Rail", "group": "GEAR", "slot": "top"},
	{"id": "side_rail", "name": "Side Rail", "group": "GEAR", "slot": "side"},
	{"id": "piggyback_dot", "name": "Piggyback Mini Red Dot", "group": "GEAR", "slot": "top"},
	{"id": "laser_box", "name": "Laser Box", "group": "GEAR", "slot": "side"},
	{"id": "flashlight", "name": "Under-Tube Flashlight", "group": "GEAR", "slot": "under"},
	{"id": "rangefinder", "name": "Rangefinder", "group": "GEAR", "slot": "top"},
	{"id": "battery_pack", "name": "Battery Pack", "group": "GEAR", "slot": "side"},
	{"id": "bubble_level", "name": "Bubble Level", "group": "GEAR", "slot": "under"},
	{"id": "offset_irons", "name": "45° Offset Irons", "group": "GEAR", "slot": "side"},
	{"id": "mini_cam", "name": "Helmet Cam", "group": "GEAR", "slot": "top"},
	{"id": "antenna", "name": "Antenna", "group": "GEAR", "slot": "top"},
	{"id": "side_plate", "name": "Side Armour Plate", "group": "GEAR", "slot": "side"},
	{"id": "top_shroud", "name": "Top Shroud", "group": "GEAR", "slot": "top"},
	{"id": "cable", "name": "Coiled Cable", "group": "GEAR", "slot": "side"},
	{"id": "compass", "name": "Compass", "group": "GEAR", "slot": "top"},
	{"id": "fins", "name": "Cooling Fins", "group": "DECOR", "slot": "top"},
	{"id": "spikes", "name": "Spikes", "group": "DECOR", "slot": "top"},
	{"id": "horns", "name": "Horns", "group": "DECOR", "slot": "top"},
	{"id": "cat_ears", "name": "Cat Ears", "group": "DECOR", "slot": "top", "color": "ff4fae"},
	{"id": "gem", "name": "Glowing Gem", "group": "DECOR", "slot": "top", "color": "8a3fd1", "finish": 5},
	{"id": "skull", "name": "Skull", "group": "DECOR", "slot": "top", "color": "f4f1ea"},
	{"id": "star_badge", "name": "Star Badge", "group": "DECOR", "slot": "side", "color": "ffd23a"},
	{"id": "band", "name": "Colour Band", "group": "DECOR", "slot": "ring"},
	{"id": "rivets", "name": "Rivet Row", "group": "DECOR", "slot": "side", "color": "7a7f88", "finish": 3},
	{"id": "led_strip", "name": "LED Strip", "group": "DECOR", "slot": "side", "color": "b8ff3a", "finish": 5},
	{"id": "chain", "name": "Hanging Chain", "group": "DECOR", "slot": "under", "color": "c79a5b", "finish": 3},
	{"id": "crown", "name": "Crown", "group": "DECOR", "slot": "top", "color": "ffd23a", "finish": 3},
	{"id": "tail_fin", "name": "Tail Fin", "group": "DECOR", "slot": "top"},
	{"id": "propeller", "name": "Propeller", "group": "DECOR", "slot": "front"},
	{"id": "dice", "name": "Lucky Die", "group": "DECOR", "slot": "top", "color": "f4f1ea"},
	{"id": "duck", "name": "Rubber Duck", "group": "DECOR", "slot": "top", "color": "ffd23a"},
	{"id": "wings", "name": "Wings", "group": "DECOR", "slot": "top", "color": "f4f1ea"},
	{"id": "pixel_heart", "name": "Pixel Heart", "group": "DECOR", "slot": "top", "color": "ff4fae"},
	{"id": "coin", "name": "Coin Badge", "group": "DECOR", "slot": "side", "color": "ffd23a", "finish": 3},
	{"id": "hazard_bands", "name": "Hazard Bands", "group": "DECOR", "slot": "ring", "color": "ffd23a"},
	{"id": "flame", "name": "Flames", "group": "DECOR", "slot": "top", "color": "ff7a2a", "finish": 5},
	{"id": "mohawk", "name": "Mohawk", "group": "DECOR", "slot": "top", "color": "b8ff3a"},
	{"id": "bow_tie", "name": "Bow Tie", "group": "DECOR", "slot": "top"},
	{"id": "smiley", "name": "Smiley Sticker", "group": "DECOR", "slot": "side", "color": "ffd23a"},
	{"id": "flag", "name": "Little Flag", "group": "DECOR", "slot": "top"},
]

const FINISHES: Array[String] = ["Matte", "Satin", "Gloss", "Metallic", "Chrome", "Glow", "Camo", "Digital",
	"Carbon", "Stripes", "Holo", "Gun Skin"]
enum { F_MATTE, F_SATIN, F_GLOSS, F_METAL, F_CHROME, F_GLOW, F_CAMO, F_DIGITAL, F_CARBON, F_STRIPES, F_HOLO, F_SKIN }

const RETICLES: Array[String] = ["Crosshair", "Mil-Dot", "Duplex", "German #4", "Chevron", "Circle-Dot",
	"Horseshoe", "Dot", "T-Post", "BDC Tree", "Ring", "Cross-Dot", "Triangle", "Box", "Smiley", "Pixel Paint"]
const PIXEL_RETICLE := 15

## Eyepiece view shapes (the black mask's opening); OPEN is a reflex view with no mask.
const VIEWS: Array[String] = ["Round", "Square", "Octagon", "Hexagon", "Wide", "Open"]

## Colour chips offered for parts, the reticle and the lens tint (any RGB is allowed too).
const PALETTE: Array[String] = ["1a1a1e", "3a3d44", "7a7f88", "d8dade", "f4f1ea", "2b4a2e", "5b7a3a",
	"9bb04a", "3d2f22", "7a5634", "c79a5b", "e8d2a0", "1f3a68", "2f6fd6", "59c4ff", "143c3c", "2fbfa5",
	"7a2030", "d8343a", "ff7a2a", "ffd23a", "8a3fd1", "ff4fae", "b8ff3a"]

## Piece material roles: the part's own colour and finish, or fixed accents.
enum { MAIN, DARK, METAL, BRASS, LENS, GLOW }

static var _index := {}
static var _decoded := {}
static var _units := {}
static var _materials := {}


# --- Catalog -----------------------------------------------------------------------------------

## PARTS index of part `id`, -1 when unknown.
static func index_of(id: String) -> int:
	if _index.is_empty():
		for i in PARTS.size():
			_index[PARTS[i].id] = i
	return int(_index.get(id, -1))


static func part_info(part: int) -> Dictionary:
	return PARTS[part] if part >= 0 and part < PARTS.size() else {}


static func group_of(group: String) -> Array:
	for g: Array in GROUPS:
		if g[0] == group:
			return g
	return GROUPS[0]


## Parts listed under catalog tab `group`, as PARTS indices.
static func parts_in(group: String) -> Array[int]:
	var out: Array[int] = []
	for i in PARTS.size():
		if PARTS[i].group == group:
			out.append(i)
	return out


## True for weapon ids that can carry a custom scope: every gun, never a melee weapon.
static func is_scope_gun(wid: String) -> bool:
	return CATALOG.WEAPONS.has(wid) and CATALOG.WEAPONS[wid].slot != "melee"


## A fresh part `part` in its group's (or its own) colour and finish, centred, unrolled.
static func new_part(part: int) -> Dictionary:
	var info := part_info(part)
	var g := group_of(str(info.get("group", "BODY")))
	return {"part": part, "color": Color(str(info.get("color", g[1]))), "finish": int(info.get("finish", g[2])),
		"length": 1.0, "width": 1.0, "offset": Vector3.ZERO, "roll": 0}


## A design with no parts and the default optics.
static func blank() -> Dictionary:
	var pixels := PackedByteArray()
	pixels.resize(GRID * GRID)
	# A small plus in the middle, so the PIXEL PAINT reticle shows something before painting.
	for i in range(3, 9):
		pixels[5 * GRID + i] = 1
		pixels[6 * GRID + i] = 1
		pixels[i * GRID + 5] = 1
		pixels[i * GRID + 6] = 1
	return {"reticle": 0, "ret_color": Color("ff3030"), "glow": 0.5, "ret_scale": 1.0,
		"tint": Color(0.35, 0.6, 1.0, 0.1), "view": 0, "view_size": 0.44, "power": 1.0,
		"rise": DEFAULT_RISE, "shift": 0.0, "pixels": pixels, "parts": []}


## What an unlock (and RESET) gives: the default optics on STARTER.
static func starter() -> Dictionary:
	var d := blank()
	for id in STARTER:
		(d.parts as Array).append(new_part(index_of(id)))
	return d


# --- Codec -------------------------------------------------------------------------------------

static func encode(d: Dictionary) -> PackedByteArray:
	var parts: Array = d.get("parts", []) if typeof(d.get("parts")) == TYPE_ARRAY else []
	var count := mini(parts.size(), MAX_PARTS)
	var b := PackedByteArray()
	b.resize(HEADER + count * PART_BYTES)
	b[0] = FORMAT
	b[1] = clampi(_int(d.get("reticle"), 0), 0, RETICLES.size() - 1)
	_put_color(b, 2, _color(d.get("ret_color"), Color.RED))
	b[5] = clampi(roundi(_float(d.get("glow"), 0.5) * 255.0), 0, 255)
	b[6] = clampi(roundi(_float(d.get("ret_scale"), 1.0) * 100.0), roundi(RETICLE_SCALE.x * 100.0), roundi(RETICLE_SCALE.y * 100.0))
	var tint := _color(d.get("tint"), Color(0, 0, 0, 0))
	_put_color(b, 7, tint)
	b[10] = clampi(roundi(tint.a / TINT_MAX * 255.0), 0, 255)
	b[11] = clampi(_int(d.get("view"), 0), 0, VIEWS.size() - 1)
	b[12] = clampi(roundi(_float(d.get("view_size"), 0.44) * 100.0), roundi(VIEW_SIZE.x * 100.0), roundi(VIEW_SIZE.y * 100.0))
	b[13] = clampi(roundi(_float(d.get("power"), 1.0) * 20.0), roundi(POWER_LIMITS.x * 20.0), roundi(POWER_LIMITS.y * 20.0))
	b[14] = clampi(roundi(_float(d.get("rise"), DEFAULT_RISE) * 1000.0), roundi(RISE.x * 1000.0), roundi(RISE.y * 1000.0))
	b.encode_s8(15, clampi(roundi(_float(d.get("shift"), 0.0) * 1000.0), -roundi(SHIFT_LIMIT * 1000.0), roundi(SHIFT_LIMIT * 1000.0)))
	var pixels: PackedByteArray = d.get("pixels") if d.get("pixels") is PackedByteArray else PackedByteArray()
	for i in mini(pixels.size(), GRID * GRID):
		if pixels[i] != 0:
			b[16 + (i >> 3)] |= 1 << (i & 7)
	b[34] = count
	var limit := roundi(OFFSET_LIMIT / 0.002)
	for i in count:
		var p: Dictionary = parts[i] if typeof(parts[i]) == TYPE_DICTIONARY else {}
		var o := HEADER + i * PART_BYTES
		b[o] = clampi(_int(p.get("part"), 0), 0, 255)
		_put_color(b, o + 1, _color(p.get("color"), Color.GRAY))
		b[o + 4] = clampi(_int(p.get("finish"), 0), 0, FINISHES.size() - 1)
		b[o + 5] = clampi(roundi(_float(p.get("length"), 1.0) * 50.0), roundi(SIZE_LIMITS.x * 50.0), roundi(SIZE_LIMITS.y * 50.0))
		b[o + 6] = clampi(roundi(_float(p.get("width"), 1.0) * 50.0), roundi(SIZE_LIMITS.x * 50.0), roundi(SIZE_LIMITS.y * 50.0))
		var off: Vector3 = p.get("offset") if p.get("offset") is Vector3 else Vector3.ZERO
		b.encode_s8(o + 7, clampi(roundi(off.x / 0.002), -limit, limit))
		b.encode_s8(o + 8, clampi(roundi(off.y / 0.002), -limit, limit))
		b.encode_s8(o + 9, clampi(roundi(off.z / 0.002), -limit, limit))
		b[o + 10] = posmod(_int(p.get("roll"), 0), ROLL_STEPS)
		b[o + 11] = 0
	return b


## The design in `b` with every value clamped and unknown parts dropped; {} when `b` isn't one.
static func decode(b: PackedByteArray) -> Dictionary:
	if b.size() < HEADER or b.size() > MAX_BYTES or b[0] != FORMAT:
		return {}
	var d := {}
	d.reticle = mini(b[1], RETICLES.size() - 1)
	d.ret_color = Color8(b[2], b[3], b[4])
	d.glow = b[5] / 255.0
	d.ret_scale = clampf(b[6] / 100.0, RETICLE_SCALE.x, RETICLE_SCALE.y)
	var tint := Color8(b[7], b[8], b[9])
	tint.a = b[10] / 255.0 * TINT_MAX
	d.tint = tint
	d.view = mini(b[11], VIEWS.size() - 1)
	d.view_size = clampf(b[12] / 100.0, VIEW_SIZE.x, VIEW_SIZE.y)
	d.power = clampf(b[13] / 20.0, POWER_LIMITS.x, POWER_LIMITS.y)
	d.rise = clampf(b[14] / 1000.0, RISE.x, RISE.y)
	d.shift = clampf(b.decode_s8(15) / 1000.0, -SHIFT_LIMIT, SHIFT_LIMIT)
	var pixels := PackedByteArray()
	pixels.resize(GRID * GRID)
	for i in GRID * GRID:
		pixels[i] = (b[16 + (i >> 3)] >> (i & 7)) & 1
	d.pixels = pixels
	var parts: Array = []
	for i in mini(b[34], MAX_PARTS):
		var o := HEADER + i * PART_BYTES
		if o + PART_BYTES > b.size():
			break
		if b[o] >= PARTS.size():
			continue
		parts.append({"part": int(b[o]), "color": Color8(b[o + 1], b[o + 2], b[o + 3]),
			"finish": mini(b[o + 4], FINISHES.size() - 1),
			"length": clampf(b[o + 5] / 50.0, SIZE_LIMITS.x, SIZE_LIMITS.y),
			"width": clampf(b[o + 6] / 50.0, SIZE_LIMITS.x, SIZE_LIMITS.y),
			"offset": Vector3(b.decode_s8(o + 7), b.decode_s8(o + 8), b.decode_s8(o + 9)).clampf(-OFFSET_LIMIT / 0.002, OFFSET_LIMIT / 0.002) * 0.002,
			"roll": b[o + 10] % ROLL_STEPS})
	d.parts = parts
	return d


## A deep copy of `d` with every value clamped (decode of its encoding).
static func sanitize(d: Dictionary) -> Dictionary:
	return decode(encode(d))


static func to_text(d: Dictionary) -> String:
	return Marshalls.raw_to_base64(encode(d))


## The design saved as `text` (Profile.scope_designs); {} when it isn't one.
static func from_text(text: String) -> Dictionary:
	return decode(Marshalls.base64_to_raw(text))


## The shared decoded design of wire bytes `raw` (do not modify it); {} when `raw` isn't a design
## or has no parts (a scope without parts isn't fitted: the gun uses its own sights).
static func decode_cached(raw: Variant) -> Dictionary:
	if not (raw is PackedByteArray):
		return {}
	var key := Marshalls.raw_to_base64(raw)
	if _decoded.has(key):
		return _decoded[key]
	if _decoded.size() >= 128:
		_decoded.clear()
	var d := decode(raw)
	if d.is_empty() or (d.parts as Array).is_empty():
		d = {}
	_decoded[key] = d
	return d


## The design gun `wid` wears for scopes dictionary `scopes` (peer_info.scopes: weapon id ->
## encode() bytes); {} for none.
static func design_in(scopes: Variant, wid: String) -> Dictionary:
	if typeof(scopes) != TYPE_DICTIONARY or not is_scope_gun(wid):
		return {}
	return decode_cached((scopes as Dictionary).get(wid))


## The design `wid` wears for a player whose (peer or entity) info is `info`.
static func from_info(info: Dictionary, wid: String) -> Dictionary:
	return design_in(info.get("scopes"), wid)


## A clean peer_info.scopes from an untrusted peer: guns only (known, not melee), each design
## decoded and re-encoded (values clamped, unknown parts dropped, at most MAX_BYTES), designs
## without parts left out.
static func sanitize_wire(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var n := 0
	for key: Variant in raw:
		n += 1
		if n > CATALOG.WEAPONS.size():
			break
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not is_scope_gun(str(key)):
			continue
		var bytes: Variant = raw[key]
		if not (bytes is PackedByteArray) or (bytes as PackedByteArray).size() > MAX_BYTES:
			continue
		var d := decode(bytes)
		if d.is_empty() or (d.parts as Array).is_empty():
			continue
		out[str(key)] = encode(d)
	return out


# --- Zoom --------------------------------------------------------------------------------------

## The power range `wid` allows (see SCOPED_POWER / SIGHTS_POWER).
static func power_range(wid: String) -> Vector2:
	if CATALOG.WEAPONS.has(wid) and CATALOG.WEAPONS[wid].get("scope", false):
		return SCOPED_POWER
	return SIGHTS_POWER


## Field of view while aiming `wid` with `design` ({}: the gun's own ads_fov). The power divides
## the tangent of the half angle of the gun's own ADS view, so 2x shows half as wide a view.
static func ads_fov(wid: String, design: Dictionary) -> float:
	var own := float(CATALOG.WEAPONS[wid].ads_fov) if CATALOG.WEAPONS.has(wid) else 60.0
	if design.is_empty():
		return own
	var r := power_range(wid)
	var p := clampf(float(design.get("power", 1.0)), r.x, r.y)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(own) * 0.5) / p))


# --- Model -------------------------------------------------------------------------------------

## Tube length and diameter of `d` (the first body part's, else the base size).
static func tube(d: Dictionary) -> Vector2:
	for p: Dictionary in d.get("parts", []):
		if part_info(int(p.part)).get("slot", "") == "body":
			return Vector2(BASE_LENGTH * float(p.length), BASE_DIAMETER * float(p.width))
	return Vector2(BASE_LENGTH, BASE_DIAMETER)


## Where the scope's origin (the mount base under the rear of the tube) sits on a gun whose rear
## sight marker is `sight`: on the receiver just under the iron sights, or for a gun with its own
## scope (built without it, Models.build_gun) low enough that the tube takes its place.
static func mount_point(sight: Vector3, own_scope: bool, d: Dictionary) -> Vector3:
	var base_y := sight.y - (0.035 if own_scope else 0.012)
	return Vector3(0.0, base_y, sight.z + 0.01 + float(d.get("shift", 0.0)))


## The scope model of `d` in scope space: origin = mount base under the tube's rear end, tube along
## -Z at height `rise`. `skin_id` dresses parts in the Gun Skin finish.
static func build(d: Dictionary, skin_id := "default") -> Node3D:
	var root := Node3D.new()
	root.name = "CustomScope"
	var t := tube(d)
	var tl := t.x
	var td := t.y
	var rise := float(d.get("rise", DEFAULT_RISE))
	var tint: Color = d.get("tint", Color(0.35, 0.6, 1.0, 0.1))
	for p: Dictionary in d.get("parts", []):
		var info := part_info(int(p.part))
		if info.is_empty():
			continue
		var slot: String = info.slot
		var outer := Node3D.new()
		var zc := -tl * 0.5
		if slot == "front":
			zc = -tl
		elif slot == "rear":
			zc = 0.0
		outer.position = Vector3(0.0, rise, zc) + (p.offset as Vector3)
		outer.rotation.z = deg_to_rad(15.0 * int(p.roll))
		root.add_child(outer)
		var inner := Node3D.new()
		match slot:
			"top":
				inner.position = Vector3(0.0, td * 0.5, 0.0)
			"side":
				inner.position = Vector3(td * 0.5, 0.0, 0.0)
			"under":
				inner.position = Vector3(0.0, -td * 0.5, 0.0)
			"mount":
				inner.position = Vector3(0.0, -rise, 0.0)
		var w := float(p.width)
		inner.scale = Vector3(w, 1.0 if slot == "mount" else w, float(p.length))
		outer.add_child(inner)
		var body := slot == "body"
		for pc: Array in _pieces(str(info.id), BASE_LENGTH if body else tl, BASE_DIAMETER if body else td, rise):
			var mi := MeshInstance3D.new()
			mi.mesh = _unit(pc[0])
			mi.transform = pc[1]
			mi.material_override = _material(int(pc[2]), p.color, int(p.finish), skin_id, tint)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			inner.add_child(mi)
	return root


static func _pc(key: String, pos: Vector3, size: Vector3, role := MAIN, rot := Vector3.ZERO) -> Array:
	return [key, Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos), role]


## The pieces of part `id` ([unit mesh, transform, role]) for a tube `l` long and `d` wide whose
## axis is `rise` above the mount base. Body pieces centre on the tube; front pieces run forward
## (-Z) from the front end, rear pieces back (+Z) from the rear end; top / side / under pieces
## start on the tube's surface; mount pieces stand on the gun (y 0) and reach the axis (y rise).
static func _pieces(id: String, l: float, d: float, rise: float) -> Array:
	var out: Array = []
	var h := maxf(0.004, rise - d * 0.45)
	match id:
		# --- Bodies
		"tube_round":
			out.append(_pc("cyl16", Vector3.ZERO, Vector3(d, d, l)))
		"tube_square":
			out.append(_pc("box", Vector3.ZERO, Vector3(d, d, l)))
		"tube_octagon":
			out.append(_pc("cyl8", Vector3.ZERO, Vector3(d, d, l)))
		"tube_hex":
			out.append(_pc("cyl6", Vector3.ZERO, Vector3(d, d, l)))
		"holo_window":
			out.append(_pc("box", Vector3(0, -d * 0.45, 0), Vector3(d * 1.2, d * 0.25, l * 0.7)))
			for s: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(s * d * 0.56, 0, -l * 0.05), Vector3(d * 0.16, d, l * 0.5)))
			out.append(_pc("box", Vector3(0, d * 0.5, -l * 0.05), Vector3(d * 1.28, d * 0.16, l * 0.5)))
			out.append(_pc("box", Vector3(0, d * 0.02, -l * 0.25), Vector3(d * 0.96, d * 0.8, 0.002), LENS))
			out.append(_pc("box", Vector3(0, -d * 0.2, l * 0.25), Vector3(d * 0.9, d * 0.35, l * 0.25), DARK))
		"box_reflex":
			out.append(_pc("box", Vector3(0, -d * 0.28, l * 0.1), Vector3(d * 1.1, d * 0.45, l * 0.55)))
			out.append(_pc("box", Vector3(0, d * 0.5, -l * 0.1), Vector3(d * 1.1, d * 0.12, l * 0.35)))
			for s: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(s * d * 0.5, d * 0.1, -l * 0.22), Vector3(d * 0.1, d * 0.8, l * 0.1)))
			out.append(_pc("box", Vector3(0, d * 0.12, -l * 0.22), Vector3(d * 0.9, d * 0.75, 0.002), LENS, Vector3(-0.3, 0, 0)))
		"periscope":
			out.append(_pc("cyl16", Vector3(0, 0, l * 0.3), Vector3(d, d, l * 0.4)))
			out.append(_pc("box", Vector3(0, d * 0.65, l * 0.08), Vector3(d * 1.05, d * 1.8, d * 1.05)))
			out.append(_pc("cyl16", Vector3(0, d * 1.3, -l * 0.2), Vector3(d, d, l * 0.5)))
			out.append(_pc("cyl16", Vector3(0, d * 1.3, -l * 0.45 - 0.0015), Vector3(d * 0.85, d * 0.85, 0.003), LENS))
			out.append(_pc("cyl16", Vector3(0, 0, l * 0.5 + 0.0015), Vector3(d * 0.85, d * 0.85, 0.003), LENS))
		"double_tube":
			for s: float in [-1.0, 1.0]:
				out.append(_pc("cyl16", Vector3(s * d * 0.34, 0, 0), Vector3(d * 0.62, d * 0.62, l)))
			out.append(_pc("box", Vector3.ZERO, Vector3(d * 0.5, d * 0.3, l * 0.8), DARK))
		"pixel_cube":
			out.append(_pc("box", Vector3.ZERO, Vector3(d * 1.5, d * 1.5, d * 1.5)))
			for x: float in [-1.0, 1.0]:
				for y: float in [-1.0, 1.0]:
					for z: float in [-1.0, 1.0]:
						out.append(_pc("box", Vector3(x, y, z) * d * 0.62, Vector3.ONE * d * 0.3, DARK))
			for z: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(0, 0, z * (d * 0.75 + 0.001)), Vector3(d * 0.9, d * 0.9, 0.002), LENS))
		"tapered":
			out.append(_pc("cyl16", Vector3(0, 0, l * 0.2), Vector3(d, d, l * 0.6)))
			out.append(_pc("frustum", Vector3(0, 0, -l * 0.3), Vector3(d * 1.65, d * 1.65, l * 0.4)))
		"bell":
			out.append(_pc("cyl16", Vector3(0, 0, l * 0.125), Vector3(d, d, l * 0.75)))
			out.append(_pc("frustum", Vector3(0, 0, -l * 0.325), Vector3(d * 1.7, d * 1.7, l * 0.15)))
			out.append(_pc("cyl16", Vector3(0, 0, -l * 0.45), Vector3(d * 1.7, d * 1.7, l * 0.1)))
		"orb":
			out.append(_pc("sphere", Vector3.ZERO, Vector3.ONE * d * 1.7))
			for z: float in [-1.0, 1.0]:
				out.append(_pc("cyl16", Vector3(0, 0, z * d * 0.83), Vector3(d * 0.8, d * 0.8, 0.004), LENS))
		"prism_scope":
			out.append(_pc("prism", Vector3(0, d * 0.1, 0), Vector3(d * 1.4, d * 1.3, l)))
			out.append(_pc("box", Vector3(0, 0, -l * 0.5 - 0.0015), Vector3(d * 0.5, d * 0.4, 0.003), LENS))
		"long_range":
			out.append(_pc("cyl16", Vector3.ZERO, Vector3(d * 0.8, d * 0.8, l * 1.25)))
			out.append(_pc("frustum", Vector3(0, 0, -l * 0.46), Vector3(d * 1.6, d * 1.6, l * 0.12)))
			out.append(_pc("cyl16", Vector3(0, 0, -l * 0.62), Vector3(d * 1.6, d * 1.6, l * 0.2)))
		"ring_sight":
			out.append(_pc("torus", Vector3(0, d * 0.2, -l * 0.35), Vector3(d * 1.7, d * 1.7, d * 0.22)))
			out.append(_pc("box", Vector3(0, -d * 0.45, -l * 0.35), Vector3(d * 0.25, d * 0.9, d * 0.25)))
			out.append(_pc("box", Vector3(0, -d * 0.85, 0), Vector3(d * 0.4, d * 0.2, l), DARK))
			out.append(_pc("torus", Vector3(0, 0, l * 0.4), Vector3(d * 0.7, d * 0.7, d * 0.2)))
			out.append(_pc("box", Vector3(0, -d * 0.6, l * 0.4), Vector3(d * 0.2, d * 0.5, d * 0.2)))
		"retro_brass":
			out.append(_pc("cyl16", Vector3.ZERO, Vector3(d * 0.6, d * 0.6, l * 1.3)))
			for z: float in [-0.6, 0.0, 0.6]:
				out.append(_pc("cyl16", Vector3(0, 0, l * z), Vector3(d * 0.78, d * 0.78, 0.008), BRASS))
		"drum_sight":
			out.append(_pc("cyl16", Vector3.ZERO, Vector3(d * 1.8, d * 1.8, l * 0.35)))
			for z: float in [-1.0, 1.0]:
				out.append(_pc("cyl16", Vector3(0, 0, z * (l * 0.175 + 0.0015)), Vector3(d * 1.5, d * 1.5, 0.003), LENS))
		"crt":
			out.append(_pc("box", Vector3(0, d * 0.3, l * 0.05), Vector3(d * 2.0, d * 1.6, l * 0.55)))
			out.append(_pc("box", Vector3(0, d * 0.3, -l * 0.225 - 0.0015), Vector3(d * 1.5, d * 1.1, 0.003), LENS))
			out.append(_pc("box", Vector3(0, d * 0.3, l * 0.4), Vector3(d * 1.4, d * 1.1, l * 0.2), DARK))
		"thermal":
			out.append(_pc("box", Vector3.ZERO, Vector3(d * 1.3, d * 1.2, l * 0.8)))
			for x: float in [-0.45, -0.22, 0.0, 0.22, 0.45]:
				out.append(_pc("box", Vector3(x * d, d * 0.75, 0), Vector3(d * 0.1, d * 0.35, l * 0.7), DARK))
			out.append(_pc("cyl16", Vector3(0, 0, -l * 0.4 - 0.002), Vector3(d, d, 0.004), LENS))
		"bino":
			for s: float in [-1.0, 1.0]:
				out.append(_pc("cyl16", Vector3(0, s * d * 0.33, 0), Vector3(d * 0.62, d * 0.62, l)))
			out.append(_pc("box", Vector3.ZERO, Vector3(d * 0.3, d * 0.8, l * 0.6), DARK))
		# --- Mounts
		"two_rings", "qd_mount":
			for z: float in [-l * 0.28, l * 0.28]:
				out.append(_pc("box", Vector3(0, h * 0.5, z), Vector3(d * 0.55, h, d * 0.3)))
				out.append(_pc("box", Vector3(0, 0.003, z), Vector3(d * 0.8, 0.006, d * 0.45)))
				out.append(_pc("torus", Vector3(0, rise, z), Vector3(d * 1.22, d * 1.22, d * 0.32)))
				if id == "qd_mount":
					out.append(_pc("box", Vector3(d * 0.45, h * 0.4, z), Vector3(d * 0.12, d * 0.5, d * 0.12), DARK, Vector3(0.5, 0, 0)))
					out.append(_pc("sphere", Vector3(d * 0.45, h * 0.4 + d * 0.22, z - d * 0.12), Vector3.ONE * d * 0.16, DARK))
		"one_piece":
			out.append(_pc("box", Vector3(0, 0.004, 0), Vector3(d * 0.8, 0.008, l * 0.75)))
			for z: float in [-l * 0.25, l * 0.25]:
				out.append(_pc("box", Vector3(0, h * 0.5, z), Vector3(d * 0.55, h, d * 0.3)))
				out.append(_pc("torus", Vector3(0, rise, z), Vector3(d * 1.22, d * 1.22, d * 0.32)))
		"offset_45":
			out.append(_pc("box", Vector3(d * 0.7, 0.004, 0), Vector3(d * 0.6, 0.008, l * 0.5)))
			for z: float in [-l * 0.2, l * 0.2]:
				out.append(_pc("box", Vector3(d * 0.4, rise * 0.5, z), Vector3(d * 0.25, rise * 1.4, d * 0.3), MAIN, Vector3(0, 0, 0.785)))
				out.append(_pc("torus", Vector3(0, rise, z), Vector3(d * 1.22, d * 1.22, d * 0.32)))
		"cantilever":
			out.append(_pc("box", Vector3(0, 0.004, l * 0.45), Vector3(d * 0.8, 0.008, l * 0.4)))
			out.append(_pc("box", Vector3(0, h * 0.5, l * 0.45), Vector3(d * 0.5, h, d * 0.3)))
			out.append(_pc("box", Vector3(0, h, l * 0.05), Vector3(d * 0.5, 0.012, l * 0.8)))
			for z: float in [-l * 0.2, l * 0.15]:
				out.append(_pc("torus", Vector3(0, rise, z), Vector3(d * 1.22, d * 1.22, d * 0.32)))
		"riser_block":
			out.append(_pc("box", Vector3(0, h * 0.5, 0), Vector3(d * 0.9, h, l * 0.6)))
			out.append(_pc("box", Vector3(0, h, 0), Vector3(d * 1.1, d * 0.3, l * 0.5)))
			for z: float in [-l * 0.2, l * 0.2]:
				out.append(_pc("torus", Vector3(0, rise, z), Vector3(d * 1.22, d * 1.22, d * 0.3)))
		"single_ring":
			out.append(_pc("box", Vector3(0, h * 0.5, 0), Vector3(d * 0.6, h, d * 0.8)))
			out.append(_pc("torus", Vector3(0, rise, 0), Vector3(d * 1.25, d * 1.25, d * 0.8)))
		"skeleton":
			for z: float in [-l * 0.28, l * 0.28]:
				out.append(_pc("prism", Vector3(0, h * 0.5, z), Vector3(d * 0.9, h, d * 0.2), MAIN, Vector3(0, 0, PI)))
				out.append(_pc("torus", Vector3(0, rise, z), Vector3(d * 1.22, d * 1.22, d * 0.25)))
		"rail_plate":
			out.append(_pc("box", Vector3(0, 0.005, 0), Vector3(d * 0.75, 0.01, l * 0.9)))
			for i in 6:
				out.append(_pc("box", Vector3(0, 0.01, -l * 0.4 + i * l * 0.16), Vector3(d * 0.78, 0.004, 0.006), DARK))
		"clamp_bands":
			for z: float in [-l * 0.28, l * 0.28]:
				out.append(_pc("box", Vector3(0, h * 0.5, z), Vector3(d * 0.5, h, d * 0.3)))
				out.append(_pc("box", Vector3(0, rise, z), Vector3(d * 1.12, d * 1.12, 0.01)))
		# --- Front (forward from the front end)
		"sunshade":
			out.append(_pc("cyl16", Vector3(0, 0, -l * 0.175), Vector3(d * 1.04, d * 1.04, l * 0.35)))
		"honeycomb":
			out.append(_pc("cyl16", Vector3(0, 0, -0.006), Vector3(d * 1.04, d * 1.04, 0.012)))
			for c: Vector2 in [Vector2.ZERO, Vector2(0.3, 0), Vector2(-0.3, 0), Vector2(0.15, 0.26),
					Vector2(-0.15, 0.26), Vector2(0.15, -0.26), Vector2(-0.15, -0.26)]:
				out.append(_pc("cyl6", Vector3(c.x * d, c.y * d, -0.0065), Vector3(d * 0.28, d * 0.28, 0.013), DARK))
		"flip_cap_front":
			out.append(_pc("box", Vector3(0, d * 0.55, -0.004), Vector3(d * 0.3, d * 0.12, d * 0.12), DARK))
			out.append(_pc("cyl16", Vector3(0, d * 0.62, -d * 0.5), Vector3(d * 1.1, d * 1.1, 0.006), MAIN, Vector3(1.35, 0, 0)))
		"tethered_cap":
			out.append(_pc("box", Vector3(0, -d * 0.75, -0.004), Vector3(d * 0.12, d * 0.6, 0.004), DARK))
			out.append(_pc("cyl16", Vector3(0, -d * 1.1, -0.01), Vector3(d, d, 0.008)))
		"objective_lens":
			out.append(_pc("cyl16", Vector3(0, 0, -0.002), Vector3(d * 0.9, d * 0.9, 0.004), LENS))
			out.append(_pc("torus", Vector3(0, 0, -0.004), Vector3(d * 1.05, d * 1.05, 0.008)))
		"square_lens":
			out.append(_pc("box", Vector3(0, 0, -0.002), Vector3(d * 0.9, d * 0.9, 0.004), LENS))
			for s: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(s * d * 0.5, 0, -0.004), Vector3(d * 0.12, d * 1.12, 0.008)))
				out.append(_pc("box", Vector3(0, s * d * 0.5, -0.004), Vector3(d * 1.12, d * 0.12, 0.008)))
		"hex_lens":
			out.append(_pc("cyl6", Vector3(0, 0, -0.002), Vector3(d * 1.12, d * 1.12, 0.004)))
			out.append(_pc("cyl6", Vector3(0, 0, -0.0055), Vector3(d * 0.9, d * 0.9, 0.003), LENS))
		"knurled_ring":
			out.append(_pc("cyl8", Vector3(0, 0, -l * 0.04), Vector3(d * 1.18, d * 1.18, l * 0.08)))
			out.append(_pc("cyl16", Vector3(0, 0, -l * 0.04), Vector3(d * 1.12, d * 1.12, l * 0.1), DARK))
		"spiked_bezel":
			out.append(_pc("torus", Vector3(0, 0, -0.005), Vector3(d * 1.15, d * 1.15, 0.01)))
			for i in 6:
				var a := TAU * i / 6.0
				out.append(_pc("cone", Vector3(cos(a), sin(a), 0) * d * 0.55 + Vector3(0, 0, -d * 0.2), Vector3(d * 0.15, d * 0.15, d * 0.4), METAL))
		"flared_bell":
			out.append(_pc("frustum", Vector3(0, 0, -l * 0.125), Vector3(d * 1.9, d * 1.9, l * 0.25)))
		"glow_ring":
			out.append(_pc("torus", Vector3(0, 0, -0.004), Vector3(d * 1.12, d * 1.12, 0.008)))
		"slat_grille":
			out.append(_pc("cyl16", Vector3(0, 0, -0.006), Vector3(d * 1.04, d * 1.04, 0.012)))
			for y: float in [-0.3, -0.1, 0.1, 0.3]:
				out.append(_pc("box", Vector3(0, y * d, -0.0065), Vector3(d * 0.9, 0.003, 0.013), DARK))
		# --- Rear (back from the rear end)
		"eyepiece":
			out.append(_pc("cyl16", Vector3(0, 0, l * 0.09), Vector3(d * 1.15, d * 1.15, l * 0.18)))
			out.append(_pc("cyl16", Vector3(0, 0, l * 0.18 + 0.0015), Vector3(d * 0.9, d * 0.9, 0.003), LENS))
		"eyecup":
			out.append(_pc("frustum_r", Vector3(0, 0, l * 0.075), Vector3(d * 1.45, d * 1.45, l * 0.15)))
		"flip_cap_rear":
			out.append(_pc("box", Vector3(d * 0.55, 0, 0.004), Vector3(d * 0.12, d * 0.3, d * 0.12), DARK))
			out.append(_pc("cyl16", Vector3(d * 1.05, 0, 0.012), Vector3(d * 1.05, d * 1.05, 0.006), MAIN, Vector3(0, 1.35, 0)))
		"square_eyepiece":
			out.append(_pc("box", Vector3(0, 0, l * 0.075), Vector3(d * 1.2, d * 1.2, l * 0.15)))
			out.append(_pc("box", Vector3(0, 0, l * 0.15 + 0.0015), Vector3(d * 0.9, d * 0.9, 0.003), LENS))
		"power_ring":
			out.append(_pc("cyl16", Vector3(0, 0, l * 0.04), Vector3(d * 1.12, d * 1.12, l * 0.08)))
			out.append(_pc("box", Vector3(0, d * 0.75, l * 0.04), Vector3(d * 0.15, d * 0.5, d * 0.15), DARK))
		"eyebrow":
			out.append(_pc("box", Vector3(0, d * 0.62, l * 0.12), Vector3(d * 1.3, 0.004, l * 0.28)))
			for s: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(s * d * 0.63, d * 0.45, l * 0.12), Vector3(0.004, d * 0.35, l * 0.28)))
		"rear_glow_ring":
			out.append(_pc("torus", Vector3(0, 0, 0.004), Vector3(d * 1.1, d * 1.1, 0.008)))
		# --- Turrets (top / side)
		"elevation_turret":
			out.append(_pc("cyl16y", Vector3(0, d * 0.2, 0), Vector3(d * 0.6, d * 0.45, d * 0.6)))
			out.append(_pc("cyl16y", Vector3(0, d * 0.45, 0), Vector3(d * 0.65, d * 0.08, d * 0.65), DARK))
		"windage_turret":
			out.append(_pc("cyl16y", Vector3(d * 0.2, 0, 0), Vector3(d * 0.6, d * 0.45, d * 0.6), MAIN, Vector3(0, 0, PI * 0.5)))
			out.append(_pc("cyl16y", Vector3(d * 0.45, 0, 0), Vector3(d * 0.65, d * 0.08, d * 0.65), DARK, Vector3(0, 0, PI * 0.5)))
		"tall_turret":
			out.append(_pc("cyl16y", Vector3(0, d * 0.45, 0), Vector3(d * 0.5, d * 0.95, d * 0.5)))
			for y: float in [0.3, 0.5, 0.7]:
				out.append(_pc("cyl16y", Vector3(0, d * y, 0), Vector3(d * 0.54, 0.002, d * 0.54), DARK))
		"capped_turret":
			out.append(_pc("cyl16y", Vector3(0, d * 0.1, 0), Vector3(d * 0.55, d * 0.2, d * 0.55)))
			out.append(_pc("cyl8y", Vector3(0, d * 0.32, 0), Vector3(d * 0.8, d * 0.25, d * 0.8)))
		"focus_wheel":
			out.append(_pc("cyl16y", Vector3(d * 0.25, 0, 0), Vector3(d * 1.4, d * 0.12, d * 1.4), MAIN, Vector3(0, 0, PI * 0.5)))
			out.append(_pc("cyl16y", Vector3(d * 0.12, 0, 0), Vector3(d * 0.4, d * 0.25, d * 0.4), DARK, Vector3(0, 0, PI * 0.5)))
		"illum_knob":
			out.append(_pc("cyl16y", Vector3(d * 0.17, 0, 0), Vector3(d * 0.5, d * 0.35, d * 0.5), MAIN, Vector3(0, 0, PI * 0.5)))
			out.append(_pc("cyl16y", Vector3(d * 0.35, 0, 0), Vector3(d * 0.3, 0.004, d * 0.3), GLOW, Vector3(0, 0, PI * 0.5)))
		"zero_stop":
			out.append(_pc("cyl16y", Vector3(0, d * 0.11, 0), Vector3(d * 0.95, d * 0.22, d * 0.95)))
			for i in 4:
				var a := TAU * i / 4.0
				out.append(_pc("box", Vector3(sin(a), 0, cos(a)) * d * 0.46 + Vector3(0, d * 0.11, 0), Vector3(d * 0.05, d * 0.23, d * 0.12), DARK, Vector3(0, a, 0)))
		"turret_stack":
			for z: float in [-0.25, 0.0, 0.25]:
				out.append(_pc("cyl8y", Vector3(0, d * 0.15, l * z), Vector3(d * 0.4, d * 0.3, d * 0.4)))
		# --- Gear
		"top_rail":
			out.append(_pc("box", Vector3(0, d * 0.09, 0), Vector3(d * 0.55, d * 0.18, l * 0.7)))
			for i in 7:
				out.append(_pc("box", Vector3(0, d * 0.16, -l * 0.3 + i * l * 0.1), Vector3(d * 0.58, d * 0.05, 0.004), DARK))
		"side_rail":
			out.append(_pc("box", Vector3(d * 0.09, 0, 0), Vector3(d * 0.18, d * 0.55, l * 0.7)))
			for i in 7:
				out.append(_pc("box", Vector3(d * 0.16, 0, -l * 0.3 + i * l * 0.1), Vector3(d * 0.05, d * 0.58, 0.004), DARK))
		"piggyback_dot":
			out.append(_pc("box", Vector3(0, d * 0.09, 0), Vector3(d * 0.55, d * 0.18, d)))
			out.append(_pc("box", Vector3(0, d * 0.33, 0), Vector3(d * 0.6, d * 0.3, d * 0.9)))
			out.append(_pc("box", Vector3(0, d * 0.62, -d * 0.4), Vector3(d * 0.6, d * 0.08, d * 0.08)))
			for s: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(s * d * 0.27, d * 0.55, -d * 0.4), Vector3(d * 0.06, d * 0.2, d * 0.08)))
			out.append(_pc("box", Vector3(0, d * 0.56, -d * 0.36), Vector3(d * 0.45, d * 0.12, 0.002), LENS))
			out.append(_pc("box", Vector3(0, d * 0.52, d * 0.3), Vector3.ONE * d * 0.1, GLOW))
		"laser_box":
			out.append(_pc("box", Vector3(d * 0.3, 0, 0), Vector3(d * 0.6, d * 0.6, l * 0.35)))
			out.append(_pc("cyl16", Vector3(d * 0.3, d * 0.1, -l * 0.175 - 0.002), Vector3(d * 0.2, d * 0.2, 0.004), GLOW))
			out.append(_pc("cyl16", Vector3(d * 0.3, -d * 0.14, -l * 0.175 - 0.002), Vector3(d * 0.16, d * 0.16, 0.004), LENS))
		"flashlight":
			out.append(_pc("cyl16", Vector3(0, -d * 0.3, 0), Vector3(d * 0.6, d * 0.6, l * 0.45)))
			out.append(_pc("cyl16", Vector3(0, -d * 0.3, -l * 0.25), Vector3(d * 0.8, d * 0.8, l * 0.1)))
			out.append(_pc("cyl16", Vector3(0, -d * 0.3, -l * 0.3 - 0.0015), Vector3(d * 0.7, d * 0.7, 0.003), GLOW))
		"rangefinder":
			out.append(_pc("box", Vector3(0, d * 0.3, 0), Vector3(d * 1.1, d * 0.6, l * 0.4)))
			for s: float in [-1.0, 1.0]:
				out.append(_pc("cyl16", Vector3(s * d * 0.25, d * 0.3, -l * 0.2 - 0.0015), Vector3(d * 0.35, d * 0.35, 0.003), LENS))
		"battery_pack":
			out.append(_pc("box", Vector3(d * 0.22, 0, l * 0.1), Vector3(d * 0.45, d * 0.7, l * 0.3)))
			out.append(_pc("cyl16", Vector3(d * 0.22, 0, l * 0.25 + 0.005), Vector3(d * 0.35, d * 0.35, 0.01), DARK))
		"bubble_level":
			out.append(_pc("box", Vector3(0, -d * 0.1, 0), Vector3(d * 0.6, d * 0.2, d * 0.8)))
			out.append(_pc("box", Vector3(0, -d * 0.22, 0), Vector3(d * 0.4, d * 0.06, d * 0.6), LENS))
			out.append(_pc("sphere", Vector3(0, -d * 0.24, 0), Vector3.ONE * d * 0.12, GLOW))
		"offset_irons":
			for z: float in [l * 0.35, -l * 0.4]:
				out.append(_pc("box", Vector3(d * 0.1, 0, z), Vector3(d * 0.2, d * 0.3, d * 0.4)))
				out.append(_pc("box", Vector3(d * 0.3, d * 0.2, z), Vector3(d * 0.08, d * 0.5, d * 0.08), MAIN, Vector3(0, 0, -0.785)))
		"mini_cam":
			out.append(_pc("box", Vector3(0, d * 0.25, l * 0.1), Vector3(d * 0.6, d * 0.5, d * 0.8)))
			out.append(_pc("cyl16", Vector3(0, d * 0.25, l * 0.1 - d * 0.4 - 0.002), Vector3(d * 0.3, d * 0.3, 0.004), LENS))
			out.append(_pc("box", Vector3(d * 0.2, d * 0.4, l * 0.1 - d * 0.38), Vector3.ONE * d * 0.08, GLOW))
		"antenna":
			out.append(_pc("cyl16y", Vector3(d * 0.2, d * 0.05, l * 0.3), Vector3(d * 0.2, d * 0.1, d * 0.2), DARK))
			out.append(_pc("cyl16y", Vector3(d * 0.2, d * 1.25, l * 0.3), Vector3(0.003, d * 2.5, 0.003)))
			out.append(_pc("sphere", Vector3(d * 0.2, d * 2.5, l * 0.3), Vector3.ONE * d * 0.2, GLOW))
		"side_plate":
			out.append(_pc("box", Vector3(d * 0.04, 0, 0), Vector3(0.004, d * 0.95, l * 0.85)))
			for y: float in [-1.0, 1.0]:
				for z: float in [-1.0, 1.0]:
					out.append(_pc("sphere", Vector3(d * 0.065, y * d * 0.35, z * l * 0.38), Vector3.ONE * d * 0.08, DARK))
		"top_shroud":
			out.append(_pc("box", Vector3(0, d * 0.12, 0), Vector3(d * 1.3, 0.004, l * 0.85)))
			for s: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(s * d * 0.65, -d * 0.05, 0), Vector3(0.004, d * 0.35, l * 0.85)))
		"cable":
			out.append(_pc("cyl16", Vector3(d * 0.12, -d * 0.2, 0), Vector3(d * 0.12, d * 0.12, l * 0.9)))
			for z: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(d * 0.12, -d * 0.2, z * l * 0.45), Vector3(d * 0.2, d * 0.2, d * 0.25), DARK))
		"compass":
			out.append(_pc("cyl16y", Vector3(0, d * 0.06, 0), Vector3(d * 0.7, d * 0.12, d * 0.7)))
			out.append(_pc("cyl16y", Vector3(0, d * 0.125, 0), Vector3(d * 0.6, 0.002, d * 0.6), LENS))
			out.append(_pc("box", Vector3(0, d * 0.128, 0), Vector3(d * 0.05, 0.002, d * 0.45), GLOW))
		# --- Decorations
		"fins":
			for x: float in [-0.3, 0.0, 0.3]:
				out.append(_pc("prism", Vector3(x * d, d * 0.35, 0), Vector3(0.004, d * 0.7, l * 0.5)))
		"spikes":
			for z: float in [-0.3, -0.1, 0.1, 0.3]:
				out.append(_pc("coney", Vector3(0, d * 0.25, l * z), Vector3(d * 0.2, d * 0.5, d * 0.2)))
		"horns":
			for s: float in [-1.0, 1.0]:
				out.append(_pc("coney", Vector3(s * d * 0.35, d * 0.35, l * 0.15), Vector3(d * 0.25, d * 0.8, d * 0.25), MAIN, Vector3(0, 0, -s * 0.6)))
		"cat_ears":
			for s: float in [-1.0, 1.0]:
				out.append(_pc("prism", Vector3(s * d * 0.3, d * 0.22, l * 0.2), Vector3(d * 0.4, d * 0.45, d * 0.1)))
		"gem":
			out.append(_pc("box", Vector3(0, d * 0.04, 0), Vector3(d * 0.35, d * 0.08, d * 0.35), DARK))
			out.append(_pc("gem", Vector3(0, d * 0.3, 0), Vector3.ONE * d * 0.45))
		"skull":
			out.append(_pc("box", Vector3(0, d * 0.4, 0), Vector3(d * 0.6, d * 0.5, d * 0.6)))
			out.append(_pc("box", Vector3(0, d * 0.1, -d * 0.03), Vector3(d * 0.45, d * 0.15, d * 0.5)))
			for s: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(s * d * 0.13, d * 0.4, -d * 0.3 - 0.0015), Vector3(d * 0.15, d * 0.15, 0.003), DARK))
		"star_badge":
			out.append(_pc("prism", Vector3(d * 0.03, d * 0.05, 0), Vector3(d * 0.6, d * 0.55, 0.004), MAIN, Vector3(0, PI * 0.5, 0)))
			out.append(_pc("prism", Vector3(d * 0.032, -d * 0.05, 0), Vector3(d * 0.6, d * 0.55, 0.004), MAIN, Vector3(PI, PI * 0.5, 0)))
		"band":
			out.append(_pc("cyl16", Vector3.ZERO, Vector3(d * 1.08, d * 1.08, 0.012)))
		"rivets":
			for i in 5:
				out.append(_pc("sphere", Vector3(d * 0.02, d * 0.2, -l * 0.36 + i * l * 0.18), Vector3.ONE * d * 0.1))
		"led_strip":
			out.append(_pc("box", Vector3(d * 0.03, d * 0.15, 0), Vector3(d * 0.06, d * 0.12, l * 0.8)))
		"chain":
			for i in 4:
				out.append(_pc("torus", Vector3(0, -d * 0.15 - i * d * 0.22, 0), Vector3(d * 0.3, d * 0.3, d * 0.08), MAIN, Vector3(0, PI * 0.5 * (i % 2), 0)))
		"crown":
			out.append(_pc("cyl16y", Vector3(0, d * 0.08, 0), Vector3(d * 0.7, d * 0.15, d * 0.7)))
			for i in 5:
				var a := TAU * i / 5.0
				out.append(_pc("prism", Vector3(sin(a), 0, cos(a)) * d * 0.33 + Vector3(0, d * 0.3, 0), Vector3(d * 0.15, d * 0.3, d * 0.04), MAIN, Vector3(0, a, 0)))
		"tail_fin":
			out.append(_pc("prism", Vector3(0, d * 0.6, l * 0.35), Vector3(0.005, d * 1.2, l * 0.4)))
		"propeller":
			out.append(_pc("cyl16", Vector3(0, 0, -d * 0.15), Vector3(d * 0.3, d * 0.3, d * 0.3), DARK))
			for a: float in [0.3, 0.3 + PI * 0.5]:
				out.append(_pc("box", Vector3(0, 0, -d * 0.3), Vector3(d * 2.2, d * 0.25, 0.005), MAIN, Vector3(0, 0, a)))
		"dice":
			out.append(_pc("box", Vector3(0, d * 0.3, 0), Vector3.ONE * d * 0.6))
			out.append(_pc("box", Vector3(0, d * 0.3, -d * 0.3 - 0.001), Vector3(d * 0.1, d * 0.1, 0.002), DARK))
			for c: Vector2 in [Vector2(-0.15, -0.15), Vector2.ZERO, Vector2(0.15, 0.15)]:
				out.append(_pc("box", Vector3(c.x * d, d * 0.6 + 0.001, c.y * d), Vector3(d * 0.1, 0.002, d * 0.1), DARK))
			for c: Vector2 in [Vector2(-0.15, -0.15), Vector2(0.15, 0.15)]:
				out.append(_pc("box", Vector3(d * 0.3 + 0.001, d * 0.3 + c.x * d, c.y * d), Vector3(0.002, d * 0.1, d * 0.1), DARK))
		"duck":
			out.append(_pc("sphere", Vector3(0, d * 0.3, 0), Vector3(d * 0.7, d * 0.55, d * 0.9)))
			out.append(_pc("sphere", Vector3(0, d * 0.7, -d * 0.3), Vector3.ONE * d * 0.45))
			out.append(_pc("box", Vector3(0, d * 0.68, -d * 0.58), Vector3(d * 0.2, d * 0.08, d * 0.2), BRASS))
			for s: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(s * d * 0.12, d * 0.78, -d * 0.5), Vector3.ONE * d * 0.06, DARK))
		"wings":
			for s: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(s * d * 0.8, d * 0.2, 0), Vector3(d * 1.2, 0.004, d), MAIN, Vector3(0, 0, s * 0.4)))
		"pixel_heart":
			var c := d * 0.15
			for cell: Vector2i in [Vector2i(1, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
					Vector2i(3, 1), Vector2i(4, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3)]:
				out.append(_pc("box", Vector3((cell.x - 2) * c, d * 0.15 + (3 - cell.y) * c, 0), Vector3.ONE * c))
		"coin":
			out.append(_pc("cyl16", Vector3(d * 0.02, 0, 0), Vector3(d * 0.6, d * 0.6, 0.004), MAIN, Vector3(0, PI * 0.5, 0)))
		"hazard_bands":
			for i in 5:
				out.append(_pc("cyl16", Vector3(0, 0, l * (-0.2 + i * 0.1)), Vector3(d * 1.05, d * 1.05, l * 0.1), MAIN if i % 2 == 0 else DARK))
		"flame":
			for f: Vector3 in [Vector3(0.0, 0.8, 0.0), Vector3(0.12, 0.6, 1.0), Vector3(-0.12, 0.5, -1.0)]:
				out.append(_pc("prism", Vector3(0, d * f.y * 0.5, l * f.x), Vector3(d * 0.3, d * f.y, 0.004), MAIN, Vector3(0, PI * 0.5, 0.25 * f.z)))
		"mohawk":
			for i in 6:
				var tall := d * (0.4 + 0.15 * sin(i * 1.3))
				out.append(_pc("box", Vector3(0, tall * 0.5, -l * 0.35 + i * l * 0.14), Vector3(0.004, tall, d * 0.15)))
		"bow_tie":
			for s: float in [-1.0, 1.0]:
				out.append(_pc("prism", Vector3(s * d * 0.22, d * 0.2, 0), Vector3(d * 0.45, d * 0.4, d * 0.1), MAIN, Vector3(0, 0, s * PI * 0.5)))
			out.append(_pc("box", Vector3(0, d * 0.2, 0), Vector3.ONE * d * 0.12, DARK))
		"smiley":
			out.append(_pc("cyl16", Vector3(d * 0.02, 0, 0), Vector3(d * 0.6, d * 0.6, 0.004), MAIN, Vector3(0, PI * 0.5, 0)))
			for s: float in [-1.0, 1.0]:
				out.append(_pc("box", Vector3(d * 0.045, d * 0.08, s * d * 0.1), Vector3(0.002, d * 0.08, d * 0.08), DARK))
			out.append(_pc("box", Vector3(d * 0.045, -d * 0.12, 0), Vector3(0.002, d * 0.05, d * 0.25), DARK))
		"flag":
			out.append(_pc("cyl16y", Vector3(0, d, l * 0.35), Vector3(0.003, d * 2.0, 0.003), DARK))
			out.append(_pc("box", Vector3(0, d * 1.7, l * 0.35 + d * 0.45), Vector3(0.003, d * 0.6, d * 0.9)))
	return out


## A unit mesh (1 m across on every axis): "box", "sphere", "gem" (faceted), "prism" (apex +Y,
## along Z), "coney" (cone, tip +Y), "cyl16y" / "cyl8y" (cylinders along Y); along Z: "cyl6",
## "cyl8", "cyl16", "cone" (tip -Z), "frustum" (wide end -Z), "frustum_r" (wide end +Z), "torus"
## (ring around Z, 1 thick along Z).
static func _unit(key: String) -> Mesh:
	if _units.has(key):
		return _units[key]
	var pm: PrimitiveMesh
	var fix := Basis.IDENTITY
	var to_z := Basis(Vector3.RIGHT, PI * 0.5)
	match key:
		"box":
			pm = BoxMesh.new()
		"sphere", "gem":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 12 if key == "sphere" else 6
			s.rings = 6 if key == "sphere" else 2
			pm = s
		"prism":
			pm = PrismMesh.new()
		"coney", "cone":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 10
			c.rings = 1
			pm = c
			if key == "cone":
				fix = Basis(Vector3.RIGHT, -PI * 0.5)
		"frustum", "frustum_r":
			var c := CylinderMesh.new()
			c.top_radius = 0.3
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 16
			c.rings = 1
			pm = c
			fix = to_z if key == "frustum" else Basis(Vector3.RIGHT, -PI * 0.5)
		"torus":
			var t := TorusMesh.new()
			t.inner_radius = 0.4
			t.outer_radius = 0.5
			t.rings = 20
			t.ring_segments = 8
			pm = t
			# The tube is 0.1 thick; stretch it to 1 along the ring's axis.
			fix = to_z * Basis.from_scale(Vector3(1.0, 10.0, 1.0))
		_:
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = int(key.trim_prefix("cyl").trim_suffix("y"))
			c.rings = 1
			pm = c
			if not key.ends_with("y"):
				fix = to_z * Basis(Vector3.UP, PI / c.radial_segments if c.radial_segments == 8 else 0.0)
	var arrays := pm.get_mesh_arrays()
	if fix != Basis.IDENTITY:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var nfix := fix.inverse().transposed()
		for i in verts.size():
			verts[i] = fix * verts[i]
			normals[i] = (nfix * normals[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_units[key] = am
	return am


## The material of a piece: `role` MAIN in the part's colour and finish, the fixed accents, LENS in
## the design's tint, GLOW the part's colour lit up.
static func _material(role: int, color: Color, finish: int, skin_id: String, tint: Color) -> Material:
	match role:
		DARK:
			return Models.flat_material(Color(0.08, 0.08, 0.09), 0.7)
		METAL:
			return Models.flat_material(Color(0.3, 0.31, 0.34), 0.35, 0.75)
		BRASS:
			return Models.flat_material(Color(0.86, 0.66, 0.26), 0.35, 0.8)
		LENS:
			var glass := Color(tint.r, tint.g, tint.b).lerp(Color(0.08, 0.12, 0.18), 0.45)
			return Models.flat_material(Color(glass.r, glass.g, glass.b), 0.05, 0.4, 0.5)
		GLOW:
			return Models.flat_material(Color(color.r, color.g, color.b), 0.4, 0.0, 2.0)
	return finish_material(color, finish, skin_id)


## Material of finish `finish` (FINISHES) in `color`; Gun Skin wears `skin_id`.
static func finish_material(color: Color, finish: int, skin_id := "default") -> Material:
	var c := Color(color.r, color.g, color.b)
	match finish:
		F_MATTE:
			return Models.flat_material(c, 0.9)
		F_SATIN:
			return Models.flat_material(c, 0.55, 0.2)
		F_GLOSS:
			return Models.flat_material(c, 0.12)
		F_METAL:
			return Models.flat_material(c, 0.35, 0.8)
		F_CHROME:
			return Models.flat_material(c.lightened(0.25), 0.04, 1.0)
		F_GLOW:
			return Models.flat_material(c, 0.4, 0.0, 1.8)
		F_SKIN:
			return Models.skin_material(skin_id if CATALOG.is_gun_skin(skin_id) else "default")
	var key := "%d|%s" % [finish, c.to_html(false)]
	if _materials.has(key):
		return _materials[key]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, _pattern(finish, c, x, y))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_scale = Vector3(2, 2, 2)
	m.roughness = 0.2 if finish == F_HOLO else 0.7
	m.metallic = 0.5 if finish == F_HOLO else (0.3 if finish == F_CARBON else 0.0)
	_materials[key] = m
	return m


static func _pattern(finish: int, c: Color, x: int, y: int) -> Color:
	match finish:
		F_CAMO:
			var n := 0.65 * Models._value_noise(x, y, 16, 4, 31) + 0.35 * Models._value_noise(x, y, 16, 8, 32)
			return c.darkened(0.45) if n < 0.4 else (c.lightened(0.25) if n > 0.62 else c)
		F_DIGITAL:
			var h := Models._hash(x >> 1, y >> 1, 41)
			return c.darkened(0.45) if h < 0.3 else (c.lightened(0.3) if h > 0.75 else c)
		F_CARBON:
			var weave := ((x >> 1) + (y >> 1)) % 2 == 0
			var shade := 0.25 + 0.2 * float((x if weave else y) % 2)
			return c.darkened(0.55 - shade * 0.5)
		F_STRIPES:
			return c if ((x + y) >> 2) % 2 == 0 else Color(0.07, 0.07, 0.08)
		F_HOLO:
			return Color.from_hsv(fposmod(c.h + (x + y) / 32.0, 1.0), 0.55, 1.0)
	return c


# --- Reticle -----------------------------------------------------------------------------------

## Draws `d`'s reticle on `ci` around `c` for a lens of radius `r` (px): a soft halo when it
## glows, then the reticle in its colour.
static func draw_reticle(ci: CanvasItem, c: Vector2, r: float, d: Dictionary) -> void:
	var col: Color = d.get("ret_color", Color.RED)
	var glow := float(d.get("glow", 0.0))
	if glow > 0.02:
		_reticle_pass(ci, c, r, d, Color(col, 0.16 * glow), 4.0)
	_reticle_pass(ci, c, r, d, col, 1.0)


static func _reticle_pass(ci: CanvasItem, c: Vector2, r: float, d: Dictionary, col: Color, wm: float) -> void:
	var s := float(d.get("ret_scale", 1.0))
	var u := r * s
	var w := maxf(1.5, r * 0.006) * s * wm
	var dot := maxf(2.0, r * 0.012) * s + (w - w / wm) * 0.5
	var x := Vector2(1, 0)
	var y := Vector2(0, 1)
	match int(d.get("reticle", 0)):
		0:  # Crosshair
			ci.draw_line(c - x * r, c + x * r, col, w, true)
			ci.draw_line(c - y * r, c + y * r, col, w, true)
		1:  # Mil-Dot
			ci.draw_line(c - x * r, c + x * r, col, w, true)
			ci.draw_line(c - y * r, c + y * r, col, w, true)
			for i in range(1, 5):
				for v: Vector2 in [x, -x, y, -y]:
					ci.draw_circle(c + v * u * 0.1 * i, w * 1.4, col)
		2:  # Duplex
			ci.draw_line(c - x * r, c - x * u * 0.35, col, w * 3.5)
			ci.draw_line(c + x * u * 0.35, c + x * r, col, w * 3.5)
			ci.draw_line(c - y * r, c - y * u * 0.35, col, w * 3.5)
			ci.draw_line(c + y * u * 0.35, c + y * r, col, w * 3.5)
			ci.draw_line(c - x * u * 0.35, c + x * u * 0.35, col, w, true)
			ci.draw_line(c - y * u * 0.35, c + y * u * 0.35, col, w, true)
		3:  # German #4
			ci.draw_line(c - x * r, c - x * u * 0.12, col, w * 4.0)
			ci.draw_line(c + x * u * 0.12, c + x * r, col, w * 4.0)
			ci.draw_line(c + y * r, c + y * u * 0.08, col, w * 4.0)
			ci.draw_colored_polygon(PackedVector2Array([c + y * u * 0.08 - x * w * 2.0, c + y * u * 0.08 + x * w * 2.0, c]), col)
			ci.draw_line(c - x * u * 0.12, c + x * u * 0.12, col, w, true)
		4:  # Chevron
			var a := u * 0.05
			ci.draw_polyline(PackedVector2Array([c + Vector2(-a, a), c, c + Vector2(a, a)]), col, w * 1.6, true)
			for i in range(1, 4):
				ci.draw_line(c + Vector2(-a * (1.0 - i * 0.2), a * (1.0 + i * 0.9)), c + Vector2(a * (1.0 - i * 0.2), a * (1.0 + i * 0.9)), col, w, true)
		5:  # Circle-Dot
			ci.draw_arc(c, u * 0.12, 0.0, TAU, 48, col, w, true)
			ci.draw_circle(c, dot, col)
		6:  # Horseshoe
			ci.draw_arc(c, u * 0.1, PI * 0.75, PI * 2.25, 40, col, w * 1.3, true)
			ci.draw_circle(c, dot, col)
		7:  # Dot
			ci.draw_circle(c, dot * 1.4, col)
		8:  # T-Post
			ci.draw_line(c - x * r, c + x * r, col, w, true)
			ci.draw_line(c, c + y * r, col, w * 2.5)
		9:  # BDC Tree
			ci.draw_line(c - x * r, c + x * r, col, w, true)
			ci.draw_line(c - y * r, c + y * u * 0.6, col, w, true)
			for i in range(1, 6):
				var half := u * (0.02 + 0.012 * i)
				ci.draw_line(c + y * u * 0.1 * i - x * half, c + y * u * 0.1 * i + x * half, col, w, true)
		10:  # Ring
			ci.draw_arc(c, u * 0.35, 0.0, TAU, 64, col, w, true)
			ci.draw_circle(c, dot * 0.7, col)
		11:  # Cross-Dot
			for v: Vector2 in [x, -x, y, -y]:
				ci.draw_line(c + v * u * 0.02, c + v * u * 0.07, col, w * 1.3, true)
			ci.draw_circle(c, dot * 0.8, col)
		12:  # Triangle
			var a := u * 0.05
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -a), c + Vector2(a * 0.87, a * 0.5), c + Vector2(-a * 0.87, a * 0.5), c + Vector2(0, -a)]), col, w * 1.3, true)
		13:  # Box
			var a := u * 0.05
			ci.draw_rect(Rect2(c - Vector2(a, a), Vector2(a, a) * 2.0), col, false, w * 1.3)
			ci.draw_circle(c, dot * 0.6, col)
		14:  # Smiley
			ci.draw_arc(c, u * 0.08, 0.0, TAU, 40, col, w * 1.2, true)
			ci.draw_circle(c + Vector2(-u * 0.028, -u * 0.02), dot * 0.8, col)
			ci.draw_circle(c + Vector2(u * 0.028, -u * 0.02), dot * 0.8, col)
			ci.draw_arc(c + Vector2(0, u * 0.005), u * 0.045, PI * 0.2, PI * 0.8, 16, col, w * 1.2, true)
		_:  # Pixel Paint
			var pixels: PackedByteArray = d.get("pixels", PackedByteArray())
			var cell := u * 0.02
			var origin := c - Vector2.ONE * cell * GRID * 0.5
			var grow := (w - w / wm) * 0.5
			for i in mini(pixels.size(), GRID * GRID):
				if pixels[i] != 0:
					var p := origin + Vector2(i % GRID, floorf(float(i) / GRID)) * cell
					ci.draw_rect(Rect2(p - Vector2.ONE * grow, Vector2.ONE * (cell + grow * 2.0)), col)


# --- Helpers -----------------------------------------------------------------------------------

static func _put_color(b: PackedByteArray, at: int, c: Color) -> void:
	b[at] = clampi(c.r8, 0, 255)
	b[at + 1] = clampi(c.g8, 0, 255)
	b[at + 2] = clampi(c.b8, 0, 255)


static func _int(v: Variant, fallback: int) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else fallback


static func _float(v: Variant, fallback: float) -> float:
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else fallback


static func _color(v: Variant, fallback: Color) -> Color:
	return v if v is Color else fallback
