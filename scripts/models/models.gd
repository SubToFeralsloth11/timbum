class_name Models
extends RefCounted
## Procedural voxel models: guns, avatars, hats, pickups, projectiles and their materials.
## Everything is built from boxes. Meshes, textures and materials are generated once and
## cached in static dictionaries; builders return fresh node trees that share them.

const CATALOG := preload("res://scripts/autoload/data.gd")

## Guns in third person are drawn this much larger than real-world size so they read well
## in chunky blocky hands.
const THIRD_PERSON_GUN_SCALE := 1.5
## Avatar pixel size: 32 texels tall = 1.8 m.
const PX := 1.8 / 32.0
const ATLAS_SIZE := 64

## Gun material slots. BODY takes the weapon skin; the rest are shared accents.
enum { BODY, DARK, METAL, LENS, RED, BRASS }

## Avatar texture atlas layout: part -> [atlas origin (px), box size (w, h, d) in px].
const AVATAR_PARTS := {
	"head": [Vector2i(0, 0), Vector3i(8, 8, 8)],
	"torso": [Vector2i(16, 16), Vector3i(8, 12, 4)],
	"arm_r": [Vector2i(40, 16), Vector3i(4, 12, 4)],
	"arm_l": [Vector2i(32, 48), Vector3i(4, 12, 4)],
	"thigh_r": [Vector2i(0, 16), Vector3i(4, 6, 4)],
	"shin_r": [Vector2i(0, 26), Vector3i(4, 6, 4)],
	"thigh_l": [Vector2i(0, 36), Vector3i(4, 6, 4)],
	"shin_l": [Vector2i(0, 46), Vector3i(4, 6, 4)],
}

const _HAIR := {
	"classic": Color("4a2f1c"), "camper": Color("1e1814"), "tuxedo": Color("16120f"),
	"zombie": Color("24301c"),
}
const _IRIS := {
	"classic": Color("3554b0"), "camper": Color("4a2c14"), "tuxedo": Color("2a3a2a"),
}

static var _guns: Dictionary = {}
static var _skin_materials: Dictionary = {}
static var _flat_materials: Dictionary = {}
static var _outfit_materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _noise_texture: ImageTexture
static var _overlay: StandardMaterial3D
static var _shield_overlay: ShaderMaterial
static var _infected_overlay: StandardMaterial3D


# --- Public API ------------------------------------------------------------------------------

## Gun for `weapon_id` in `skin_id`. Origin = grip, forward = -Z, real-world scale.
## Children: MeshInstance3D "Mesh", Marker3D "Muzzle" (barrel tip / knife tip),
## Marker3D "Sight" (rear sight line, for aiming down sights) and, for two-handed holds,
## Marker3D "Support" (where the off hand goes; absent on the knife). A `charm_id` other than
## "none" hangs that GunCharm off the left side of the receiver (never on the knife).
static func build_gun(weapon_id: String, skin_id: String, charm_id := "none") -> Node3D:
	if not CATALOG.WEAPONS.has(weapon_id):
		push_warning("Models: unknown weapon '%s'" % weapon_id)
		weapon_id = "pistol"
	var info := _gun_info(weapon_id)
	var root := Node3D.new()
	root.name = "Gun"
	root.set_meta(&"weapon_id", weapon_id)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = info.mesh
	mi.set_surface_override_material(0, skin_material(skin_id))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	_add_marker(root, "Muzzle", info.muzzle)
	_add_marker(root, "Sight", info.sight)
	if info.support != null:
		_add_marker(root, "Support", info.support)
	if charm_id != "none" and CATALOG.CHARMS.has(charm_id) and CATALOG.WEAPONS[weapon_id].slot != "melee":
		var charm := GunCharm.create(charm_id)
		charm.position = charm_anchor(weapon_id)
		root.add_child(charm)
	return root


## Where a charm hangs on `weapon_id` (gun space): the left face of the gun, a little below the
## barrel line, where neither hand covers it in first person: behind the grip on long guns (the
## off hand is out on the handguard), ahead of it on pistols (the off hand wraps the grip).
static func charm_anchor(weapon_id: String) -> Vector3:
	var info := _gun_info(weapon_id)
	var box: AABB = (info.mesh as ArrayMesh).get_aabb()
	var muzzle: Vector3 = info.muzzle
	var support: Variant = info.support
	var two_handed := support != null and (support as Vector3).z < -0.12
	var z := 0.07 if two_handed else muzzle.z * 0.6
	z = clampf(z, box.position.z + 0.02, box.end.z - 0.02)
	return Vector3(box.position.x - 0.003, muzzle.y - 0.015, z)


## A charm on its own (shop icon/preview): the trinket and chain, hanging still.
static func build_charm(charm_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Charm"
	var mi := MeshInstance3D.new()
	mi.mesh = GunCharm.mesh_for(charm_id)
	root.add_child(mi)
	return root


## Shop model of an attachment upgrade (Data.ATTACHMENTS id), built from a few boxes.
static func build_attachment(attachment_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Attachment"
	var mi := MeshInstance3D.new()
	mi.mesh = _attachment_mesh(attachment_id)
	root.add_child(mi)
	return root


static func _attachment_mesh(attachment_id: String) -> ArrayMesh:
	var key := "attachment/" + attachment_id
	if _meshes.has(key):
		return _meshes[key]
	var k := MeshKit.new()
	match attachment_id:
		"laser":
			k.box(DARK, Vector3.ZERO, Vector3(0.04, 0.03, 0.09))
			k.box(METAL, Vector3(0, 0.022, 0), Vector3(0.03, 0.014, 0.07))
			k.box(RED, Vector3(0.008, 0, -0.046), Vector3(0.012, 0.012, 0.004))
			k.box(LENS, Vector3(-0.009, 0, -0.046), Vector3(0.01, 0.01, 0.004))
		"grip":
			k.box(METAL, Vector3(0, 0.03, 0), Vector3(0.03, 0.012, 0.06))
			k.box(DARK, Vector3(0, -0.02, 0), Vector3(0.028, 0.09, 0.03), Vector3(-0.15, 0, 0))
			k.box(DARK, Vector3(0, -0.07, 0.006), Vector3(0.034, 0.012, 0.036))
		"stabilizer":
			k.box(DARK, Vector3.ZERO, Vector3(0.036, 0.036, 0.09))
			for i in 3:
				k.box(METAL, Vector3(0, 0, -0.03 + i * 0.026), Vector3(0.042, 0.012, 0.01))
		"mag":
			k.box(DARK, Vector3(0, -0.02, 0), Vector3(0.03, 0.16, 0.05), Vector3(0.2, 0, 0))
			k.box(BRASS, Vector3(0, 0.062, -0.016), Vector3(0.016, 0.01, 0.03), Vector3(0.2, 0, 0))
			k.box(METAL, Vector3(0, -0.1, 0.016), Vector3(0.034, 0.012, 0.054), Vector3(0.2, 0, 0))
		"speed_loader":
			k.box(METAL, Vector3.ZERO, Vector3(0.06, 0.02, 0.06))
			for i in 6:
				var a := i * TAU / 6.0
				k.box(BRASS, Vector3(cos(a) * 0.018, 0.02, sin(a) * 0.018), Vector3(0.01, 0.03, 0.01))
			k.box(DARK, Vector3(0, -0.018, 0), Vector3(0.02, 0.02, 0.02))
		"optic":
			k.box(DARK, Vector3(0, 0, 0), Vector3(0.04, 0.012, 0.07))
			k.box(DARK, Vector3(0, 0.03, -0.02), Vector3(0.04, 0.05, 0.008))
			k.box(DARK, Vector3(0, 0.03, 0.02), Vector3(0.04, 0.05, 0.008))
			k.box(LENS, Vector3(0, 0.03, -0.02), Vector3(0.03, 0.036, 0.009))
			k.box(RED, Vector3(0, 0.03, 0.0245), Vector3(0.006, 0.006, 0.002))
		"barrel":
			k.box(METAL, Vector3(0, 0, 0), Vector3(0.024, 0.024, 0.3))
			k.box(DARK, Vector3(0, 0, -0.16), Vector3(0.034, 0.034, 0.04))
			k.box(DARK, Vector3(0, 0, 0.13), Vector3(0.032, 0.032, 0.04))
		"stock":
			k.box(DARK, Vector3(0, 0, -0.06), Vector3(0.024, 0.024, 0.12))
			k.box(DARK, Vector3(0, -0.01, 0.06), Vector3(0.03, 0.09, 0.024))
			k.box(METAL, Vector3(0, 0.02, 0.0), Vector3(0.026, 0.012, 0.1))
		"holster":
			k.box(DARK, Vector3(0, -0.02, 0), Vector3(0.05, 0.13, 0.03))
			k.box(DARK, Vector3(0, 0.06, 0.012), Vector3(0.05, 0.04, 0.012))
			k.box(BRASS, Vector3(0, 0.05, -0.017), Vector3(0.012, 0.012, 0.004))
		_:
			k.box(METAL, Vector3.ZERO, Vector3(0.06, 0.06, 0.08))
			k.box(RED, Vector3(0, 0.035, 0), Vector3(0.03, 0.012, 0.03))
			k.box(DARK, Vector3(0, 0, -0.05), Vector3(0.02, 0.02, 0.03))
	var mats := _gun_accent_materials()
	mats[BODY] = skin_material("default")
	_meshes[key] = k.build(mats)
	return _meshes[key]


## Shared weapon-skin material: a 32x32 nearest-filtered pixel pattern generated from the
## skin's colours. Cached per skin id.
static func skin_material(skin_id: String) -> Material:
	if _skin_materials.has(skin_id):
		return _skin_materials[skin_id]
	if not CATALOG.SKINS.has(skin_id):
		push_warning("Models: unknown skin '%s'" % skin_id)
		return skin_material("default")
	var skin: Dictionary = CATALOG.SKINS[skin_id]
	var tex := ImageTexture.create_from_image(_skin_image(skin, skin_id.hash()))
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	match skin_id:
		"gold", "diamond":
			m.metallic = 0.85
			m.roughness = 0.22
			m.metallic_specular = 0.8
		"default":
			m.metallic = 0.45
			m.roughness = 0.45
		"galaxy":
			m.metallic = 0.3
			m.roughness = 0.35
		_:
			m.metallic = 0.15
			m.roughness = 0.55
	var glow: float = skin.glow
	if glow > 0.0:
		m.emission_enabled = true
		# Multiply (not the default Add, which adds the flat emission colour everywhere).
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission = Color.WHITE
		m.emission_texture = tex
		m.emission_energy_multiplier = glow
	_skin_materials[skin_id] = m
	return m


static func build_avatar(outfit_id: String, hat_id: String) -> Avatar:
	var a := Avatar.new()
	a.setup(outfit_id, hat_id)
	return a


## Hat whose origin is the top centre of the 0.45 m avatar head (front = -Z).
## "none" (or an unknown id) returns an empty Node3D.
static func build_hat(hat_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Hat"
	if hat_id == "none" or not CATALOG.HATS.has(hat_id):
		return root
	_add_mesh(root, _cached_mesh("hat_" + hat_id, _hat_mesh.bind(hat_id)))
	return root


## Pickup prop for kind "health" | "ammo" | "grenade": about 0.5 m, origin at bottom centre.
static func build_pickup(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Pickup"
	if not kind in ["health", "ammo", "grenade"]:
		push_warning("Models: unknown pickup kind '%s'" % kind)
		kind = "ammo"
	_add_mesh(root, _cached_mesh("pickup_" + kind, _pickup_mesh.bind(kind)))
	return root


## Blocky frag grenade, about 0.12 m tall, origin at its centre.
static func build_grenade() -> Node3D:
	var root := Node3D.new()
	root.name = "Grenade"
	_add_mesh(root, _cached_mesh("grenade", _grenade_mesh))
	return root


## Tactical grenade for kind "smoke" (grey can, green band) or "flash" (white, blue band),
## same size as the frag.
static func build_tactical(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Tactical"
	_add_mesh(root, _cached_mesh("tactical_" + kind, _tactical_mesh.bind(kind)))
	return root


static func _tactical_mesh(kind: String) -> ArrayMesh:
	var k := MeshKit.new()
	_grenade_into(k, Vector3.ZERO, 0, 1, 2, 3)
	var flash := kind == "flash"
	return k.build([
		flat_material(Color("dcdfe4") if flash else Color("5d6168"), 0.5, 0.3 if flash else 0.0),
		flat_material(Color("2f7fe0") if flash else Color("5a9b3a")),
		flat_material(Color(0.42, 0.43, 0.46), 0.35, 0.7),
		flat_material(Color("c9a646"), 0.3, 0.8),
	])


## Rocket projectile, about 0.5 m long, origin at its centre, nose towards -Z.
static func build_rocket() -> Node3D:
	var root := Node3D.new()
	root.name = "Rocket"
	_add_mesh(root, _cached_mesh("rocket", _rocket_mesh))
	return root


## First-person forearms posed around a gun whose grip is at the origin, forward -Z.
## Put the gun under child "GunMount" via ViewmodelArms.attach_gun(); the left hand then
## moves to the gun's "Support" marker. Meshes do not cast shadows.
static func build_viewmodel_arms(outfit_id: String) -> Node3D:
	var arms := ViewmodelArms.new()
	arms.setup(outfit_id)
	return arms


## Sets visual layers and shadow casting on every GeometryInstance3D in `node`'s subtree,
## e.g. `set_render(gun, 2, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)` for viewmodels.
static func set_render(node: Node, layers: int, shadows: GeometryInstance3D.ShadowCastingSetting) -> void:
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = layers
		(g as GeometryInstance3D).cast_shadow = shadows
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers = layers
		(node as GeometryInstance3D).cast_shadow = shadows


## Character atlas material for an outfit (64x64 pixel-art skin). Cached per outfit id.
static func outfit_material(outfit_id: String) -> StandardMaterial3D:
	if _outfit_materials.has(outfit_id):
		return _outfit_materials[outfit_id]
	if not CATALOG.OUTFITS.has(outfit_id):
		push_warning("Models: unknown outfit '%s'" % outfit_id)
		return outfit_material("classic")
	var o: Dictionary = CATALOG.OUTFITS[outfit_id]
	var img := Image.create(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8)
	var glow := Image.create(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8)
	glow.fill(Color.BLACK)
	var has_glow := false
	var style := _outfit_style(outfit_id, o)
	var part_index := 0
	for part: String in AVATAR_PARTS:
		part_index += 1
		var origin: Vector2i = AVATAR_PARTS[part][0]
		var dims: Vector3i = AVATAR_PARTS[part][1]
		for face in 6:
			var r := _face_rect(origin, dims, face)
			for y in r.size.y:
				for x in r.size.x:
					var h := _hash(r.position.x + x, r.position.y + y, outfit_id.hash())
					var c := _paint(outfit_id, style, o, part, face, x, y, r.size.x, r.size.y, h)
					if c.a < 1.0:
						c.a = 1.0
						glow.set_pixel(r.position.x + x, r.position.y + y, c)
						has_glow = true
					else:
						c = _jitter(c, h)
					img.set_pixel(r.position.x + x, r.position.y + y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.85
	if style == "armor" or style == "robot":
		m.metallic = 0.45
		m.roughness = 0.45
	if has_glow:
		m.emission_enabled = true
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission = Color.WHITE
		m.emission_texture = ImageTexture.create_from_image(glow)
		m.emission_energy_multiplier = 2.5
	_outfit_materials[outfit_id] = m
	return m


## Mesh for one avatar body part ("head", "torso", "arm_r", "arm_l", "thigh_r", "shin_r",
## "thigh_l", "shin_l", "forearm_r", "forearm_l"), placed relative to its joint pivot.
static func avatar_part_mesh(part: String) -> ArrayMesh:
	return _cached_mesh("part_" + part, _part_mesh.bind(part))


## Outfit-specific 3D details for an avatar mount ("head", "torso", "arm"), or null.
static func build_outfit_extra(outfit_id: String, mount: String) -> Node3D:
	var key := "extra_%s_%s" % [outfit_id, mount]
	if not _meshes.has(key):
		_meshes[key] = _extra_mesh(outfit_id, mount)
	var mesh: ArrayMesh = _meshes[key]
	if mesh == null:
		return null
	var root := Node3D.new()
	root.name = "Extra"
	_add_mesh(root, mesh)
	return root


## Shared translucent overlay used by Avatar.flash_hit().
static func hit_overlay_material() -> StandardMaterial3D:
	if _overlay == null:
		_overlay = StandardMaterial3D.new()
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_overlay.albedo_color = Color(1.0, 0.18, 0.15, 0.6)
	return _overlay


## Shared sickly green tint over an Infected player's avatar (still lit by the scene).
static func infected_overlay_material() -> StandardMaterial3D:
	if _infected_overlay == null:
		_infected_overlay = StandardMaterial3D.new()
		_infected_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_infected_overlay.albedo_color = Color(0.3, 0.95, 0.2, 0.5)
		_infected_overlay.emission_enabled = true
		_infected_overlay.emission = Color(0.15, 0.5, 0.05)
		_infected_overlay.emission_energy_multiplier = 0.4
	return _infected_overlay


## Shared pulsing cyan shell used while an Avatar has spawn protection.
static func shield_overlay_material() -> ShaderMaterial:
	if _shield_overlay == null:
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float pulse = 0.55 + 0.45 * sin(TIME * 9.0);
	ALBEDO = vec3(0.3, 0.8, 1.0) * (0.25 + rim * 0.9) * pulse;
}
"""
		_shield_overlay = ShaderMaterial.new()
		_shield_overlay.shader = shader
	return _shield_overlay


## Shared flat-colour material with a subtle pixel-noise texture. Cached per parameters.
static func flat_material(color: Color, roughness := 0.8, metallic := 0.0, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), roughness, metallic, glow]
	if _flat_materials.has(key):
		return _flat_materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _noise()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = roughness
	m.metallic = metallic
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_flat_materials[key] = m
	return m


# --- Shared helpers --------------------------------------------------------------------------

static func _add_marker(root: Node3D, marker_name: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	m.gizmo_extents = 0.05
	root.add_child(m)


static func _add_mesh(root: Node3D, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return mi


static func _cached_mesh(key: String, builder: Callable) -> ArrayMesh:
	if not _meshes.has(key):
		_meshes[key] = builder.call()
	return _meshes[key]


static func _noise() -> ImageTexture:
	if _noise_texture == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				var v := 0.86 + 0.14 * _hash(x, y, 7)
				img.set_pixel(x, y, Color(v, v, v))
		img.generate_mipmaps()
		_noise_texture = ImageTexture.create_from_image(img)
	return _noise_texture


static func _hash(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 982451653) & 0xffffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


## Smooth tileable value noise over a `size`-pixel square with `cells` lattice cells.
static func _value_noise(x: int, y: int, size: int, cells: int, s: int) -> float:
	var cs := float(size) / cells
	var fx := x / cs
	var fy := y / cs
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := smoothstep(0.0, 1.0, fx - x0)
	var ty := smoothstep(0.0, 1.0, fy - y0)
	var x1 := posmod(x0 + 1, cells)
	var y1 := posmod(y0 + 1, cells)
	x0 = posmod(x0, cells)
	y0 = posmod(y0, cells)
	var top := lerpf(_hash(x0, y0, s), _hash(x1, y0, s), tx)
	var bottom := lerpf(_hash(x0, y1, s), _hash(x1, y1, s), tx)
	return lerpf(top, bottom, ty)


static func _jitter(c: Color, h: float) -> Color:
	var k := 0.94 + 0.09 * h
	return Color(c.r * k, c.g * k, c.b * k, c.a)


# --- Weapon skins ----------------------------------------------------------------------------

static func _skin_image(skin: Dictionary, seed: int) -> Image:
	const N := 32
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var a: Color = skin.a
	var b: Color = skin.b
	var pattern: String = skin.pattern
	var glow: float = skin.glow
	for y in N:
		for x in N:
			var h := _hash(x, y, seed)
			var c := a
			match pattern:
				"camo":
					var n := 0.65 * _value_noise(x, y, N, 4, seed) + 0.35 * _value_noise(x, y, N, 8, seed + 1)
					if n < 0.42:
						c = b
					elif n < 0.56:
						c = a.lerp(b, 0.5)
				"stripes":
					var t := fposmod(x + y * 0.5 + 2.0 * sin(TAU * y / 16.0), 8.0)
					var stripe := t < 2.6 + h * 0.8
					if glow >= 0.5:
						c = a if t < 1.6 else b
					elif stripe:
						c = b
				"sparkle":
					var n := _value_noise(x, y, N, 4, seed) * 0.7 + _value_noise(x, y, N, 8, seed + 3) * 0.3
					c = b.lerp(a, floorf(n * 4.0 + h * 0.5) / 4.0)
					if h > 0.985:
						c = Color(1, 1, 1)
					elif h > 0.94:
						c = a.lightened(0.55)
				"gradient":
					var v := absf(y / 16.0 - 1.0)
					c = a.lerp(b, clampf(floorf(v * 5.0 + h * 0.7) / 5.0, 0.0, 1.0))
					if h > 0.97:
						c = Color(1, 1, 1)
				"glow":
					c = b
					if x % 8 == 0 or y % 8 == 0:
						c = a
				_:
					c = a.lerp(b, h * 0.22)
			c = _jitter(c, _hash(x, y, seed + 11))
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return img


# --- Guns ------------------------------------------------------------------------------------

static func _gun_info(weapon_id: String) -> Dictionary:
	if _guns.has(weapon_id):
		return _guns[weapon_id]
	var k := MeshKit.new()
	var info: Dictionary
	match weapon_id:
		"pistol": info = _gun_pistol(k)
		"revolver": info = _gun_revolver(k)
		"smg": info = _gun_smg(k)
		"rifle": info = _gun_rifle(k)
		"shotgun": info = _gun_shotgun(k)
		"lmg": info = _gun_lmg(k)
		"sniper": info = _gun_sniper(k)
		"rocket": info = _gun_rocket(k)
		"machine_pistol": info = _gun_machine_pistol(k)
		"burst_pistol": info = _gun_burst_pistol(k)
		"sawed_off": info = _gun_sawed_off(k)
		"suppressed": info = _gun_suppressed(k)
		"dmr": info = _gun_dmr(k)
		"burst_rifle": info = _gun_burst_rifle(k)
		_: info = _gun_knife(k)
	info.mesh = k.build(_gun_accent_materials())
	_guns[weapon_id] = info
	return info


static func _gun_accent_materials() -> Array:
	return [
		null,
		flat_material(Color(0.1, 0.1, 0.11), 0.75),
		flat_material(Color(0.3, 0.31, 0.34), 0.35, 0.75),
		flat_material(Color(0.3, 0.75, 1.0), 0.1, 0.3, 0.8),
		flat_material(Color(0.82, 0.16, 0.1), 0.6),
		flat_material(Color(0.86, 0.66, 0.26), 0.35, 0.8),
	]


static func _trigger(k: MeshKit, z: float, length := 0.05) -> void:
	k.box(DARK, Vector3(0, -0.026, z - length * 0.5 + 0.01), Vector3(0.01, 0.007, length))
	k.box(DARK, Vector3(0, -0.013, z - length + 0.012), Vector3(0.01, 0.03, 0.007))
	k.box(METAL, Vector3(0, -0.01, z - 0.012), Vector3(0.007, 0.024, 0.007))


static func _gun_pistol(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.045, 0.012), Vector3(0.03, 0.105, 0.042), Vector3(-0.22, 0, 0))
	k.box(DARK, Vector3(0, -0.098, 0.024), Vector3(0.034, 0.012, 0.048), Vector3(-0.22, 0, 0))
	k.box(BODY, Vector3(0, 0.032, -0.065), Vector3(0.032, 0.036, 0.215))
	k.box(BODY, Vector3(0, 0.004, -0.06), Vector3(0.028, 0.022, 0.15))
	k.box(DARK, Vector3(0, 0.003, -0.12), Vector3(0.03, 0.012, 0.05))
	for i in 4:
		k.box(DARK, Vector3(0, 0.034, 0.012 + i * 0.008), Vector3(0.034, 0.028, 0.003))
	k.box(DARK, Vector3(0.0165, 0.038, -0.03), Vector3(0.002, 0.012, 0.035))
	k.box(METAL, Vector3(0, 0.034, -0.175), Vector3(0.016, 0.016, 0.01))
	k.box(DARK, Vector3(0, 0.034, -0.1805), Vector3(0.008, 0.008, 0.002))
	k.box(METAL, Vector3(0, 0.054, -0.16), Vector3(0.006, 0.008, 0.01))
	k.box(METAL, Vector3(0, 0.054, 0.03), Vector3(0.026, 0.009, 0.008))
	k.box(METAL, Vector3(0, 0.032, 0.045), Vector3(0.012, 0.016, 0.01))
	_trigger(k, -0.022)
	return {"muzzle": Vector3(0, 0.034, -0.185), "sight": Vector3(0, 0.06, 0.03),
		"support": Vector3(-0.02, -0.05, 0.0)}


static func _gun_revolver(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.045, 0.03), Vector3(0.03, 0.1, 0.04), Vector3(-0.35, 0, 0))
	k.box(METAL, Vector3(0, -0.092, 0.047), Vector3(0.032, 0.01, 0.042), Vector3(-0.35, 0, 0))
	k.box(BODY, Vector3(0, 0.012, 0.0), Vector3(0.028, 0.045, 0.07))
	k.box(METAL, Vector3(0, 0.022, -0.045), Vector3(0.042, 0.042, 0.045))
	k.box(DARK, Vector3(0, 0.022, -0.045), Vector3(0.044, 0.007, 0.038))
	k.box(DARK, Vector3(0, 0.022, -0.045), Vector3(0.007, 0.044, 0.038))
	k.box(BODY, Vector3(0, 0.03, -0.135), Vector3(0.022, 0.022, 0.135))
	k.box(BODY, Vector3(0, 0.012, -0.12), Vector3(0.018, 0.016, 0.1))
	k.box(METAL, Vector3(0, 0.044, -0.135), Vector3(0.008, 0.006, 0.135))
	k.box(DARK, Vector3(0, 0.03, -0.2035), Vector3(0.01, 0.01, 0.002))
	k.box(METAL, Vector3(0, 0.05, -0.195), Vector3(0.006, 0.012, 0.01))
	k.box(METAL, Vector3(0, 0.04, 0.042), Vector3(0.01, 0.02, 0.016), Vector3(0.3, 0, 0))
	k.box(METAL, Vector3(0, 0.04, 0.03), Vector3(0.022, 0.008, 0.008))
	_trigger(k, -0.002, 0.042)
	return {"muzzle": Vector3(0, 0.03, -0.205), "sight": Vector3(0, 0.048, 0.03),
		"support": Vector3(-0.02, -0.05, 0.0)}


static func _gun_smg(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.05, 0.02), Vector3(0.032, 0.1, 0.04), Vector3(-0.2, 0, 0))
	k.box(BODY, Vector3(0, 0.04, -0.07), Vector3(0.046, 0.07, 0.3))
	k.box(DARK, Vector3(0, -0.065, -0.11), Vector3(0.03, 0.15, 0.036))
	k.box(METAL, Vector3(0, -0.142, -0.11), Vector3(0.034, 0.01, 0.04))
	for i in 3:
		k.box(DARK, Vector3(0, 0.045, -0.165 - i * 0.022), Vector3(0.048, 0.012, 0.01))
	k.box(METAL, Vector3(0, 0.045, -0.25), Vector3(0.03, 0.03, 0.06))
	k.box(METAL, Vector3(0, 0.045, -0.29), Vector3(0.022, 0.022, 0.02))
	k.box(DARK, Vector3(0, 0.045, -0.3005), Vector3(0.01, 0.01, 0.002))
	k.box(METAL, Vector3(-0.027, 0.055, -0.02), Vector3(0.008, 0.01, 0.03))
	k.box(DARK, Vector3(0.0235, 0.05, -0.04), Vector3(0.002, 0.02, 0.05))
	k.box(METAL, Vector3(0, 0.079, -0.07), Vector3(0.022, 0.008, 0.18))
	k.box(METAL, Vector3(0, 0.091, 0.04), Vector3(0.024, 0.016, 0.012))
	k.box(METAL, Vector3(0, 0.091, -0.19), Vector3(0.006, 0.018, 0.01))
	k.box(METAL, Vector3(0, 0.06, 0.16), Vector3(0.01, 0.012, 0.16))
	k.box(METAL, Vector3(0, 0.005, 0.16), Vector3(0.01, 0.012, 0.16))
	k.box(DARK, Vector3(0, 0.032, 0.245), Vector3(0.03, 0.085, 0.016))
	_trigger(k, -0.025)
	return {"muzzle": Vector3(0, 0.045, -0.302), "sight": Vector3(0, 0.1, 0.04),
		"support": Vector3(0, -0.01, -0.18)}


static func _gun_rifle(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.045, 0.018), Vector3(0.03, 0.095, 0.04), Vector3(-0.3, 0, 0))
	k.box(BODY, Vector3(0, 0.05, -0.04), Vector3(0.05, 0.05, 0.26))
	k.box(BODY, Vector3(0, 0.012, -0.05), Vector3(0.045, 0.03, 0.18))
	k.box(DARK, Vector3(0, -0.05, -0.105), Vector3(0.032, 0.1, 0.055), Vector3(0.12, 0, 0))
	k.box(DARK, Vector3(0, -0.128, -0.128), Vector3(0.032, 0.075, 0.055), Vector3(0.32, 0, 0))
	k.box(BODY, Vector3(0, 0.045, -0.29), Vector3(0.056, 0.058, 0.24))
	for i in 4:
		k.box(DARK, Vector3(0, 0.035, -0.215 - i * 0.05), Vector3(0.058, 0.014, 0.025))
	k.box(METAL, Vector3(0, 0.06, -0.425), Vector3(0.03, 0.03, 0.03))
	k.box(METAL, Vector3(0, 0.095, -0.425), Vector3(0.008, 0.04, 0.012))
	k.box(METAL, Vector3(0, 0.05, -0.475), Vector3(0.02, 0.02, 0.1))
	k.box(METAL, Vector3(0, 0.05, -0.54), Vector3(0.03, 0.03, 0.04))
	k.box(DARK, Vector3(0, 0.05, -0.5605), Vector3(0.012, 0.012, 0.002))
	k.box(METAL, Vector3(0, 0.081, -0.04), Vector3(0.03, 0.012, 0.24))
	for i in 6:
		k.box(DARK, Vector3(0, 0.0875, 0.06 - i * 0.04), Vector3(0.031, 0.002, 0.012))
	k.box(METAL, Vector3(0, 0.1, 0.06), Vector3(0.032, 0.028, 0.024))
	k.box(METAL, Vector3(0, 0.06, 0.095), Vector3(0.03, 0.015, 0.012))
	k.box(DARK, Vector3(0.026, 0.055, -0.03), Vector3(0.003, 0.02, 0.05))
	k.box(DARK, Vector3(0, 0.05, 0.13), Vector3(0.026, 0.026, 0.08))
	k.box(BODY, Vector3(0, 0.035, 0.2), Vector3(0.042, 0.075, 0.14))
	k.box(DARK, Vector3(0, 0.03, 0.28), Vector3(0.046, 0.1, 0.02))
	_trigger(k, -0.022)
	return {"muzzle": Vector3(0, 0.05, -0.562), "sight": Vector3(0, 0.11, 0.06),
		"support": Vector3(0, 0.005, -0.3)}


static func _gun_shotgun(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.035, 0.04), Vector3(0.032, 0.08, 0.05), Vector3(-0.5, 0, 0))
	k.box(BODY, Vector3(0, 0.04, -0.06), Vector3(0.05, 0.07, 0.2))
	k.box(BODY, Vector3(0, 0.012, 0.2), Vector3(0.045, 0.1, 0.26), Vector3(0.06, 0, 0))
	k.box(DARK, Vector3(0, 0.004, 0.334), Vector3(0.05, 0.12, 0.02), Vector3(0.06, 0, 0))
	k.box(METAL, Vector3(0, 0.065, -0.4), Vector3(0.026, 0.026, 0.48))
	k.box(DARK, Vector3(0, 0.065, -0.6405), Vector3(0.014, 0.014, 0.002))
	k.box(METAL, Vector3(0, 0.032, -0.36), Vector3(0.024, 0.024, 0.4))
	k.box(METAL, Vector3(0, 0.032, -0.565), Vector3(0.028, 0.028, 0.012))
	k.box(METAL, Vector3(0, 0.048, -0.55), Vector3(0.02, 0.04, 0.012))
	k.box(DARK, Vector3(0, 0.03, -0.32), Vector3(0.046, 0.042, 0.16))
	for i in 5:
		k.box(DARK, Vector3(0, 0.03, -0.26 - i * 0.03), Vector3(0.05, 0.046, 0.01))
	k.box(METAL, Vector3(0, 0.083, -0.63), Vector3(0.008, 0.01, 0.008))
	k.box(DARK, Vector3(0.026, 0.05, -0.07), Vector3(0.003, 0.025, 0.06))
	k.box(METAL, Vector3(0, 0.077, -0.06), Vector3(0.012, 0.004, 0.18))
	_trigger(k, 0.005)
	return {"muzzle": Vector3(0, 0.065, -0.642), "sight": Vector3(0, 0.085, 0.0),
		"support": Vector3(0, 0.0, -0.32)}


static func _gun_lmg(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.045, 0.02), Vector3(0.034, 0.095, 0.042), Vector3(-0.25, 0, 0))
	k.box(BODY, Vector3(0, 0.055, -0.05), Vector3(0.07, 0.1, 0.32))
	k.box(METAL, Vector3(0, 0.112, -0.06), Vector3(0.066, 0.014, 0.2))
	k.box(DARK, Vector3(-0.01, -0.06, -0.1), Vector3(0.09, 0.11, 0.13))
	k.box(METAL, Vector3(-0.01, -0.01, -0.1), Vector3(0.092, 0.01, 0.132))
	k.box(METAL, Vector3(-0.056, -0.06, -0.1), Vector3(0.002, 0.04, 0.06))
	for i in 4:
		k.box(BRASS, Vector3(-0.05, 0.03, -0.085 - i * 0.018), Vector3(0.05, 0.012, 0.012))
	k.box(BODY, Vector3(0, 0.065, -0.37), Vector3(0.056, 0.056, 0.32))
	for i in 5:
		k.box(DARK, Vector3(0, 0.065, -0.25 - i * 0.06), Vector3(0.058, 0.02, 0.02))
		k.box(DARK, Vector3(0, 0.065, -0.25 - i * 0.06), Vector3(0.02, 0.058, 0.02))
	k.box(METAL, Vector3(0, 0.065, -0.585), Vector3(0.024, 0.024, 0.11))
	k.box(METAL, Vector3(0, 0.065, -0.655), Vector3(0.034, 0.034, 0.03))
	k.box(DARK, Vector3(0, 0.065, -0.6705), Vector3(0.014, 0.014, 0.002))
	k.box(METAL, Vector3(0, 0.11, -0.5), Vector3(0.008, 0.04, 0.012))
	k.box(DARK, Vector3(0, 0.13, -0.02), Vector3(0.014, 0.04, 0.014))
	k.box(DARK, Vector3(0, 0.13, -0.14), Vector3(0.014, 0.04, 0.014))
	k.box(DARK, Vector3(0, 0.155, -0.08), Vector3(0.018, 0.016, 0.14))
	k.box(METAL, Vector3(-0.018, 0.026, -0.46), Vector3(0.012, 0.012, 0.18))
	k.box(METAL, Vector3(0.018, 0.026, -0.46), Vector3(0.012, 0.012, 0.18))
	k.box(BODY, Vector3(0, 0.04, 0.24), Vector3(0.05, 0.095, 0.26))
	k.box(DARK, Vector3(0, 0.035, 0.38), Vector3(0.054, 0.11, 0.02))
	k.box(METAL, Vector3(0, 0.122, 0.08), Vector3(0.03, 0.02, 0.02))
	_trigger(k, -0.022)
	return {"muzzle": Vector3(0, 0.065, -0.672), "sight": Vector3(0, 0.135, 0.08),
		"support": Vector3(0, 0.025, -0.32)}


static func _gun_sniper(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.045, 0.03), Vector3(0.032, 0.09, 0.04), Vector3(-0.35, 0, 0))
	k.box(BODY, Vector3(0, 0.0, 0.22), Vector3(0.046, 0.1, 0.32))
	k.box(BODY, Vector3(0, 0.062, 0.21), Vector3(0.044, 0.03, 0.16))
	k.box(DARK, Vector3(0, -0.005, 0.11), Vector3(0.048, 0.04, 0.05))
	k.box(DARK, Vector3(0, 0.0, 0.39), Vector3(0.05, 0.11, 0.02))
	k.box(BODY, Vector3(0, 0.04, -0.08), Vector3(0.05, 0.055, 0.28))
	k.box(BODY, Vector3(0, 0.025, -0.35), Vector3(0.05, 0.045, 0.26))
	k.box(METAL, Vector3(0, 0.055, -0.64), Vector3(0.022, 0.022, 0.32))
	k.box(METAL, Vector3(0, 0.055, -0.83), Vector3(0.036, 0.03, 0.05))
	k.box(DARK, Vector3(0, 0.055, -0.8555), Vector3(0.012, 0.012, 0.002))
	k.box(DARK, Vector3(0.0255, 0.055, -0.83), Vector3(0.002, 0.008, 0.03))
	k.box(DARK, Vector3(-0.0255, 0.055, -0.83), Vector3(0.002, 0.008, 0.03))
	k.box(DARK, Vector3(0, -0.01, -0.1), Vector3(0.034, 0.05, 0.07))
	k.box(METAL, Vector3(0.04, 0.05, 0.02), Vector3(0.05, 0.012, 0.012))
	k.box(METAL, Vector3(0.068, 0.045, 0.025), Vector3(0.02, 0.02, 0.02))
	k.box(DARK, Vector3(0, 0.125, -0.08), Vector3(0.04, 0.04, 0.26))
	k.box(DARK, Vector3(0, 0.125, -0.25), Vector3(0.058, 0.058, 0.08))
	k.box(DARK, Vector3(0, 0.125, 0.07), Vector3(0.05, 0.05, 0.05))
	k.box(METAL, Vector3(0, 0.155, -0.08), Vector3(0.02, 0.02, 0.02))
	k.box(METAL, Vector3(0.03, 0.125, -0.08), Vector3(0.02, 0.02, 0.02))
	k.box(METAL, Vector3(0, 0.1, -0.15), Vector3(0.046, 0.03, 0.016))
	k.box(METAL, Vector3(0, 0.1, -0.01), Vector3(0.046, 0.03, 0.016))
	k.box(LENS, Vector3(0, 0.125, -0.2915), Vector3(0.046, 0.046, 0.004))
	k.box(LENS, Vector3(0, 0.125, 0.0955), Vector3(0.036, 0.036, 0.004))
	_trigger(k, -0.01)
	return {"muzzle": Vector3(0, 0.055, -0.858), "sight": Vector3(0, 0.125, 0.1),
		"support": Vector3(0, 0.0, -0.34)}


static func _gun_rocket(k: MeshKit) -> Dictionary:
	k.box(BODY, Vector3(0, 0.1, -0.22), Vector3(0.12, 0.12, 0.96))
	k.box(DARK, Vector3(0, 0.1, -0.72), Vector3(0.15, 0.15, 0.06))
	k.box(DARK, Vector3(0, 0.1, 0.27), Vector3(0.14, 0.14, 0.05))
	k.box(DARK, Vector3(0, 0.1, -0.45), Vector3(0.124, 0.124, 0.03))
	k.box(DARK, Vector3(0, 0.1, 0.05), Vector3(0.124, 0.124, 0.03))
	k.box(RED, Vector3(0, 0.1, -0.6), Vector3(0.122, 0.122, 0.025))
	k.box(RED, Vector3(0, 0.1, -0.745), Vector3(0.08, 0.08, 0.02))
	k.box(DARK, Vector3(0, -0.03, 0.0), Vector3(0.032, 0.09, 0.04), Vector3(-0.2, 0, 0))
	k.box(DARK, Vector3(0, 0.025, -0.02), Vector3(0.04, 0.04, 0.09))
	k.box(DARK, Vector3(0, -0.0, -0.3), Vector3(0.03, 0.08, 0.035))
	k.box(DARK, Vector3(0, 0.035, -0.3), Vector3(0.035, 0.02, 0.05))
	k.box(DARK, Vector3(0, 0.035, 0.15), Vector3(0.06, 0.03, 0.14))
	k.box(METAL, Vector3(-0.07, 0.14, -0.12), Vector3(0.03, 0.012, 0.02))
	k.box(DARK, Vector3(-0.1, 0.16, -0.12), Vector3(0.04, 0.05, 0.09))
	k.box(LENS, Vector3(-0.1, 0.16, -0.166), Vector3(0.03, 0.03, 0.004))
	k.box(LENS, Vector3(-0.1, 0.16, -0.074), Vector3(0.024, 0.024, 0.004))
	_trigger(k, -0.03, 0.04)
	return {"muzzle": Vector3(0, 0.1, -0.76), "sight": Vector3(-0.1, 0.16, -0.07),
		"support": Vector3(0, -0.02, -0.3)}


## Compact auto pistol: extended magazine, folding front grip, compensator.
static func _gun_machine_pistol(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.045, 0.012), Vector3(0.03, 0.105, 0.042), Vector3(-0.18, 0, 0))
	k.box(DARK, Vector3(0, -0.125, 0.028), Vector3(0.026, 0.07, 0.034), Vector3(-0.18, 0, 0))
	k.box(METAL, Vector3(0, -0.162, 0.035), Vector3(0.03, 0.01, 0.038), Vector3(-0.18, 0, 0))
	k.box(BODY, Vector3(0, 0.034, -0.07), Vector3(0.036, 0.04, 0.23))
	k.box(BODY, Vector3(0, 0.004, -0.06), Vector3(0.032, 0.024, 0.16))
	for i in 5:
		k.box(DARK, Vector3(0, 0.036, 0.0 + i * 0.008), Vector3(0.038, 0.03, 0.003))
	k.box(METAL, Vector3(0, 0.034, -0.2), Vector3(0.03, 0.03, 0.04))
	for i in 3:
		k.box(DARK, Vector3(0, 0.05, -0.19 - i * 0.012), Vector3(0.012, 0.004, 0.006))
	k.box(DARK, Vector3(0, 0.034, -0.2205), Vector3(0.01, 0.01, 0.002))
	k.box(DARK, Vector3(0, -0.035, -0.13), Vector3(0.02, 0.06, 0.022), Vector3(0.25, 0, 0))
	k.box(METAL, Vector3(0, 0.058, -0.17), Vector3(0.006, 0.008, 0.01))
	k.box(METAL, Vector3(0, 0.058, 0.03), Vector3(0.028, 0.009, 0.008))
	k.box(METAL, Vector3(0.0185, 0.038, -0.03), Vector3(0.002, 0.012, 0.012))
	_trigger(k, -0.022)
	return {"muzzle": Vector3(0, 0.034, -0.222), "sight": Vector3(0, 0.064, 0.03),
		"support": Vector3(0, -0.06, -0.13)}


## Burst pistol: long slide with a red burst selector and a short rail.
static func _gun_burst_pistol(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.047, 0.014), Vector3(0.032, 0.11, 0.044), Vector3(-0.2, 0, 0))
	k.box(DARK, Vector3(0, -0.102, 0.026), Vector3(0.036, 0.012, 0.05), Vector3(-0.2, 0, 0))
	k.box(BODY, Vector3(0, 0.034, -0.075), Vector3(0.034, 0.038, 0.24))
	k.box(BODY, Vector3(0, 0.004, -0.07), Vector3(0.03, 0.024, 0.17))
	k.box(DARK, Vector3(0, -0.006, -0.13), Vector3(0.032, 0.008, 0.06))
	for i in 3:
		k.box(DARK, Vector3(0, 0.054, -0.06 - i * 0.03), Vector3(0.02, 0.003, 0.012))
	k.box(RED, Vector3(0.018, 0.02, 0.0), Vector3(0.004, 0.012, 0.012))
	k.box(METAL, Vector3(0, 0.034, -0.198), Vector3(0.018, 0.018, 0.01))
	k.box(DARK, Vector3(0, 0.034, -0.2035), Vector3(0.008, 0.008, 0.002))
	k.box(METAL, Vector3(0, 0.058, -0.185), Vector3(0.006, 0.008, 0.01))
	k.box(METAL, Vector3(0, 0.058, 0.035), Vector3(0.028, 0.009, 0.008))
	_trigger(k, -0.024)
	return {"muzzle": Vector3(0, 0.034, -0.205), "sight": Vector3(0, 0.064, 0.035),
		"support": Vector3(-0.02, -0.05, 0.0)}


## Sawn-off double barrel: two short barrels side by side, wooden pistol stock.
static func _gun_sawed_off(k: MeshKit) -> Dictionary:
	k.box(BRASS, Vector3(0, -0.045, 0.04), Vector3(0.034, 0.1, 0.05), Vector3(-0.45, 0, 0))
	k.box(BRASS, Vector3(0, -0.09, 0.065), Vector3(0.036, 0.03, 0.06), Vector3(-0.45, 0, 0))
	k.box(DARK, Vector3(0, 0.025, 0.0), Vector3(0.05, 0.05, 0.08))
	k.box(BODY, Vector3(-0.0135, 0.05, -0.17), Vector3(0.026, 0.026, 0.27))
	k.box(BODY, Vector3(0.0135, 0.05, -0.17), Vector3(0.026, 0.026, 0.27))
	k.box(DARK, Vector3(-0.0135, 0.05, -0.3055), Vector3(0.016, 0.016, 0.002))
	k.box(DARK, Vector3(0.0135, 0.05, -0.3055), Vector3(0.016, 0.016, 0.002))
	k.box(BRASS, Vector3(0, 0.022, -0.13), Vector3(0.046, 0.03, 0.15))
	k.box(METAL, Vector3(0, 0.066, -0.29), Vector3(0.006, 0.008, 0.008))
	k.box(METAL, Vector3(0, 0.062, 0.03), Vector3(0.008, 0.02, 0.02), Vector3(0.4, 0, 0))
	k.box(METAL, Vector3(0, 0.068, -0.02), Vector3(0.012, 0.006, 0.04))
	_trigger(k, 0.01)
	return {"muzzle": Vector3(0, 0.05, -0.307), "sight": Vector3(0, 0.07, 0.02),
		"support": Vector3(0, 0.0, -0.13)}


## Suppressed pistol: slim slide with a long fat can on the muzzle.
static func _gun_suppressed(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.045, 0.012), Vector3(0.028, 0.1, 0.04), Vector3(-0.22, 0, 0))
	k.box(BODY, Vector3(0, 0.03, -0.055), Vector3(0.028, 0.032, 0.19))
	k.box(BODY, Vector3(0, 0.004, -0.05), Vector3(0.026, 0.02, 0.13))
	for i in 4:
		k.box(DARK, Vector3(0, 0.032, 0.012 + i * 0.008), Vector3(0.03, 0.024, 0.003))
	k.box(DARK, Vector3(0, 0.03, -0.25), Vector3(0.038, 0.038, 0.2))
	for i in 4:
		k.box(METAL, Vector3(0, 0.03, -0.18 - i * 0.045), Vector3(0.04, 0.04, 0.006))
	k.box(METAL, Vector3(0, 0.03, -0.3505), Vector3(0.012, 0.012, 0.002))
	k.box(METAL, Vector3(0, 0.05, 0.03), Vector3(0.024, 0.008, 0.008))
	k.box(METAL, Vector3(0, 0.05, -0.135), Vector3(0.005, 0.008, 0.008))
	_trigger(k, -0.02)
	return {"muzzle": Vector3(0, 0.03, -0.352), "sight": Vector3(0, 0.056, 0.03),
		"support": Vector3(-0.02, -0.05, 0.0)}


## Marksman rifle: long handguard, 20-round box mag, compact scope, bipod nubs.
static func _gun_dmr(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.045, 0.018), Vector3(0.03, 0.095, 0.04), Vector3(-0.3, 0, 0))
	k.box(BODY, Vector3(0, 0.05, -0.04), Vector3(0.05, 0.055, 0.28))
	k.box(BODY, Vector3(0, 0.012, -0.05), Vector3(0.045, 0.03, 0.2))
	k.box(DARK, Vector3(0, -0.04, -0.11), Vector3(0.03, 0.08, 0.06))
	k.box(METAL, Vector3(0, -0.082, -0.11), Vector3(0.034, 0.008, 0.064))
	k.box(BODY, Vector3(0, 0.048, -0.33), Vector3(0.05, 0.05, 0.3))
	for i in 5:
		k.box(DARK, Vector3(0.0255, 0.048, -0.22 - i * 0.05), Vector3(0.002, 0.016, 0.03))
		k.box(DARK, Vector3(-0.0255, 0.048, -0.22 - i * 0.05), Vector3(0.002, 0.016, 0.03))
	k.box(METAL, Vector3(0, 0.05, -0.56), Vector3(0.02, 0.02, 0.16))
	k.box(METAL, Vector3(0, 0.05, -0.65), Vector3(0.032, 0.026, 0.04))
	k.box(DARK, Vector3(0, 0.05, -0.6705), Vector3(0.012, 0.012, 0.002))
	k.box(DARK, Vector3(0, 0.018, -0.45), Vector3(0.05, 0.01, 0.03))
	k.box(DARK, Vector3(0, 0.122, -0.04), Vector3(0.036, 0.036, 0.18))
	k.box(DARK, Vector3(0, 0.122, -0.15), Vector3(0.048, 0.048, 0.05))
	k.box(METAL, Vector3(0, 0.095, -0.08), Vector3(0.04, 0.022, 0.014))
	k.box(METAL, Vector3(0, 0.095, 0.0), Vector3(0.04, 0.022, 0.014))
	k.box(LENS, Vector3(0, 0.122, -0.1765), Vector3(0.038, 0.038, 0.004))
	k.box(LENS, Vector3(0, 0.122, 0.0515), Vector3(0.028, 0.028, 0.004))
	k.box(DARK, Vector3(0, 0.05, 0.12), Vector3(0.026, 0.026, 0.06))
	k.box(BODY, Vector3(0, 0.035, 0.21), Vector3(0.044, 0.08, 0.16))
	k.box(DARK, Vector3(0, 0.07, 0.2), Vector3(0.03, 0.02, 0.1))
	k.box(DARK, Vector3(0, 0.03, 0.3), Vector3(0.048, 0.1, 0.02))
	_trigger(k, -0.022)
	return {"muzzle": Vector3(0, 0.05, -0.672), "sight": Vector3(0, 0.122, 0.055),
		"support": Vector3(0, 0.01, -0.33)}


## Burst rifle: bullpup-ish body, carry handle sight, angular handguard.
static func _gun_burst_rifle(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, -0.045, -0.06), Vector3(0.03, 0.095, 0.04), Vector3(-0.25, 0, 0))
	k.box(BODY, Vector3(0, 0.045, 0.02), Vector3(0.056, 0.075, 0.36))
	k.box(DARK, Vector3(0, -0.035, 0.09), Vector3(0.032, 0.09, 0.05), Vector3(0.15, 0, 0))
	k.box(METAL, Vector3(0, -0.083, 0.098), Vector3(0.034, 0.008, 0.052), Vector3(0.15, 0, 0))
	k.box(BODY, Vector3(0, 0.04, -0.25), Vector3(0.05, 0.06, 0.2))
	k.box(DARK, Vector3(0, 0.005, -0.25), Vector3(0.052, 0.012, 0.18))
	k.box(METAL, Vector3(0, 0.05, -0.41), Vector3(0.02, 0.02, 0.14))
	k.box(METAL, Vector3(0, 0.05, -0.475), Vector3(0.03, 0.03, 0.03))
	k.box(DARK, Vector3(0, 0.05, -0.4905), Vector3(0.012, 0.012, 0.002))
	k.box(DARK, Vector3(0, 0.1, -0.02), Vector3(0.012, 0.03, 0.012))
	k.box(DARK, Vector3(0, 0.1, -0.16), Vector3(0.012, 0.03, 0.012))
	k.box(BODY, Vector3(0, 0.122, -0.09), Vector3(0.024, 0.014, 0.18))
	k.box(METAL, Vector3(0, 0.138, -0.17), Vector3(0.006, 0.014, 0.008))
	k.box(RED, Vector3(0.029, 0.03, -0.02), Vector3(0.003, 0.012, 0.012))
	k.box(DARK, Vector3(0, 0.035, 0.205), Vector3(0.058, 0.09, 0.02))
	_trigger(k, -0.085)
	return {"muzzle": Vector3(0, 0.05, -0.492), "sight": Vector3(0, 0.15, -0.02),
		"support": Vector3(0, 0.0, -0.26)}

static func _gun_knife(k: MeshKit) -> Dictionary:
	k.box(DARK, Vector3(0, 0, 0.02), Vector3(0.025, 0.035, 0.11))
	for i in 3:
		k.box(DARK, Vector3(0, 0, -0.01 + i * 0.03), Vector3(0.027, 0.037, 0.008))
	k.box(METAL, Vector3(0, 0, 0.08), Vector3(0.03, 0.04, 0.012))
	k.box(METAL, Vector3(0, 0.005, -0.04), Vector3(0.03, 0.06, 0.012))
	k.box(BODY, Vector3(0, 0.006, -0.13), Vector3(0.006, 0.034, 0.17))
	k.box(METAL, Vector3(0, -0.0135, -0.125), Vector3(0.0065, 0.006, 0.16))
	k.box(BODY, Vector3(0, 0.012, -0.228), Vector3(0.006, 0.022, 0.026))
	k.box(METAL, Vector3(0, -0.0015, -0.225), Vector3(0.0065, 0.006, 0.02))
	k.box(BODY, Vector3(0, 0.014, -0.25), Vector3(0.006, 0.012, 0.02))
	k.box(METAL, Vector3(0, 0.012, -0.264), Vector3(0.0065, 0.006, 0.01))
	return {"muzzle": Vector3(0, 0.012, -0.27), "sight": Vector3(0, 0.04, 0.0), "support": null}


# --- Avatar texture painting -----------------------------------------------------------------

static func _outfit_style(outfit_id: String, o: Dictionary) -> String:
	if outfit_id in ["hazmat", "astronaut", "camper"]:
		return outfit_id
	return o.pattern


static func _face_rect(o: Vector2i, d: Vector3i, face: int) -> Rect2i:
	var w := d.x
	var h := d.y
	var dp := d.z
	match face:
		0: return Rect2i(o.x + dp, o.y + dp, w, h)
		1: return Rect2i(o.x + 2 * dp + w, o.y + dp, w, h)
		2: return Rect2i(o.x, o.y + dp, dp, h)
		3: return Rect2i(o.x + dp + w, o.y + dp, dp, h)
		4: return Rect2i(o.x + dp, o.y, w, dp)
	return Rect2i(o.x + dp + w, o.y, w, dp)


## Colour of one atlas texel. Returned alpha < 1 marks an emissive texel.
static func _paint(id: String, style: String, o: Dictionary, part: String, face: int,
		x: int, y: int, w: int, h: int, n: float) -> Color:
	match part:
		"head": return _paint_head(id, style, o, face, x, y, w, h, n)
		"torso": return _paint_torso(style, o, face, x, y, n)
		"arm_r", "arm_l": return _paint_arm(style, o, part == "arm_r", face, x, y, n)
		"thigh_r", "thigh_l": return _paint_thigh(style, o, part == "thigh_r", face, x, y, n)
	return _paint_shin(style, o, face, x, y, n)


static func _glow(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.5)


## True for the back half (+Z) of a side face (faces 2 and 3 run in opposite directions).
static func _back_half(face: int, x: int, w: int) -> bool:
	return (face == 2 and x < w / 2) or (face == 3 and x >= w / 2)


static func _paint_head(id: String, style: String, o: Dictionary, face: int, x: int, y: int,
		w: int, _h: int, n: float) -> Color:
	var skin: Color = o.skin
	var shirt: Color = o.shirt
	var accent: Color = o.accent
	var front := face == 0
	match style:
		"mask":
			if face != 4 and face != 5 and y == 1:
				return accent
			if face == 1 and y >= 2 and y <= 5 and (x == 3 or x == 4):
				return accent.darkened(0.15 * (y - 2))
			if front and y == 3:
				return skin
			if front and y == 4:
				if x == 1 or x == 6:
					return Color(0.95, 0.95, 0.95)
				if x == 2 or x == 5:
					return Color(0.1, 0.08, 0.06)
				return skin
			return shirt.lightened(0.06) if face == 4 and (x + y) % 3 == 0 else shirt
		"hazmat":
			if front:
				if y >= 1 and y <= 5 and x >= 1 and x <= 6:
					if y == 1 or y == 5 or x == 1 or x == 6:
						return accent.lightened(0.15)
					if (x == 2 and y <= 3) or (x == 3 and y == 2):
						return Color(0.6, 0.7, 0.75)
					return Color(0.12, 0.17, 0.22).lerp(Color(0.2, 0.28, 0.32), (y - 2) / 3.0)
				if y >= 6 and x >= 2 and x <= 5:
					return Color(0.2, 0.2, 0.22)
				if y >= 6 and (x == 1 or x == 6):
					return Color(0.35, 0.35, 0.37)
			if face != 4 and face != 5 and y == 0:
				return shirt.darkened(0.15)
			return shirt
		"astronaut":
			if front:
				if y >= 1 and y <= 6 and x >= 1 and x <= 6:
					if y == 1 or y == 6 or x == 1 or x == 6:
						return Color(0.62, 0.64, 0.68)
					if (x == 2 and y <= 3) or (x == 3 and y == 2):
						return Color(0.85, 0.9, 1.0)
					return Color(0.07, 0.1, 0.22).lerp(Color(0.85, 0.6, 0.2), (y - 2) / 3.0 * 0.45)
			if (face == 2 or face == 3) and y >= 3 and y <= 4 and x >= 2 and x <= 5:
				return Color(0.62, 0.64, 0.68) if x == 2 or x == 5 else accent
			return skin
		"armor":
			var plume := accent
			if face == 4 and (x == 3 or x == 4):
				return plume.lightened(0.1) if y % 2 == 0 else plume
			if face == 1 and y <= 2 and (x == 3 or x == 4):
				return plume
			if front:
				if y == 3 and x >= 1 and x <= 6:
					return Color(0.04, 0.04, 0.05)
				if (y == 5 or y == 6) and x >= 2 and x <= 5 and (x + y) % 2 == 0:
					return Color(0.08, 0.08, 0.09)
				if y <= 2 and (x == 3 or x == 4):
					return skin.lightened(0.18)
			if face != 4 and face != 5 and y == 7:
				return skin.darkened(0.25)
			if (face == 2 or face == 3) and y == 5 and (x == 1 or x == 6):
				return skin.lightened(0.3)
			return skin
		"robot":
			var dark := Color(0.07, 0.09, 0.11)
			if front:
				if y >= 2 and y <= 4 and x >= 1 and x <= 6:
					if y == 3 and (x == 2 or x == 5):
						return _glow(accent)
					if y == 3 and (x == 3 or x == 4):
						return _glow(accent.darkened(0.6))
					return dark
				if y == 6 and x >= 2 and x <= 5:
					return dark if x % 2 == 0 else skin.darkened(0.3)
			if (face == 2 or face == 3) and y >= 3 and y <= 4 and x >= 2 and x <= 5:
				return o.shoes if x == 2 or x == 5 or y == 3 else Color(o.shoes).lightened(0.2)
			if face == 4 and (x == 0 or x == 7 or y == 0 or y == 7):
				return skin.darkened(0.2)
			return skin
	# Plain faces with hair: classic, camper, tux, zombie.
	var hair: Color = _HAIR.get(id, Color("3a2614"))
	var zombie := style == "torn"
	if face == 4:
		return hair
	if face == 1 and y <= 5:
		return hair if y <= 4 or x % 3 != 1 else skin
	if (face == 2 or face == 3) and (y <= 1 or (y <= 3 and _back_half(face, x, w))):
		return hair
	if front:
		if y == 0 or (y == 1 and (x <= 1 or x >= 6 or (id == "tuxedo" and x <= 4))):
			return hair
		if y == 1:
			return hair if x % 2 == 0 and not zombie else skin
		if y == 4:
			if zombie:
				return Color(0.04, 0.06, 0.03) if x in [1, 2, 5, 6] else skin
			if x == 1 or x == 6:
				return Color(0.96, 0.96, 0.96)
			if x == 2 or x == 5:
				return _IRIS.get(id, Color("3a2a1a"))
		if y == 3 and not zombie and x in [1, 2, 5, 6]:
			return hair.lightened(0.1)
		if y == 5 and (x == 3 or x == 4):
			return skin.darkened(0.12)
		if y == 6:
			if zombie and x >= 2 and x <= 5:
				return Color(0.14, 0.05, 0.05) if x != 3 else Color(0.85, 0.85, 0.75)
			if x == 3 or x == 4:
				return Color(0.45, 0.2, 0.18) if not zombie else skin.darkened(0.4)
		if id == "camper" and y >= 6 and not (y == 6 and (x == 3 or x == 4)):
			return hair
	if zombie and n > 0.86:
		return skin.darkened(0.25)
	return skin


static func _paint_torso(style: String, o: Dictionary, face: int, x: int, y: int, n: float) -> Color:
	var skin: Color = o.skin
	var shirt: Color = o.shirt
	var accent: Color = o.accent
	var front := face == 0
	var band := face <= 3
	var belt := Color(0.24, 0.16, 0.09)
	match style:
		"plain":
			if band and y == 11:
				return Color(0.85, 0.68, 0.25) if front and (x == 3 or x == 4) else belt
			if front and y == 0 and (x == 3 or x == 4):
				return skin
			if front and y >= 3 and y <= 4 and x >= 5 and x <= 6:
				return accent
			if band and y == 10:
				return shirt.darkened(0.12)
			return shirt
		"camper":
			if band and y == 11:
				return Color(0.6, 0.6, 0.6) if front and (x == 3 or x == 4) else belt
			if front and y == 0 and x >= 2 and x <= 5:
				return accent
			if front and (x == 3 or x == 4) and y % 3 == 1:
				return accent.darkened(0.3)
			var plaid := shirt
			if x % 3 == 0:
				plaid = plaid.darkened(0.22)
			if y % 3 == 0:
				plaid = plaid.darkened(0.22)
			return plaid
		"torn":
			if band and y >= 9 and n > 0.45 + (11 - y) * 0.15:
				return skin
			if band and n > 0.965:
				return skin
			if band and y >= 4 and n < 0.035:
				return accent
			if front and y == 0 and x >= 2 and x <= 5:
				return skin
			return shirt
		"mask":
			if band and (y == 8 or y == 9):
				return accent if y == 8 or x % 4 != 0 else accent.darkened(0.25)
			if front and y >= 9 and y <= 10 and (x == 5 or x == 6):
				return accent
			if front and y <= 7 and x == 1 + y:
				return shirt.lightened(0.14)
			return shirt
		"hazmat":
			if band and (y == 7 or y == 8):
				return accent.lightened(0.1)
			if front and (x == 3) and y != 7 and y != 8:
				return shirt.darkened(0.25)
			if front and ((y == 2 and x == 6) or (y == 3 and x >= 5 and x <= 7) or (y == 4 and x >= 4 and x <= 7)):
				return accent
			if band and y == 11:
				return shirt.darkened(0.15)
			return shirt
		"astronaut":
			if band and y == 0:
				return accent
			if front and y >= 3 and y <= 6 and x >= 2 and x <= 5:
				if y == 4 and x == 3:
					return Color(0.9, 0.15, 0.1)
				if y == 4 and x == 4:
					return accent
				if y == 5 and x == 3:
					return _glow(Color(0.2, 0.55, 1.0))
				if y == 5 and x == 4:
					return _glow(Color(0.3, 1.0, 0.4))
				return Color(0.5, 0.52, 0.56)
			if band and y == 9:
				return shirt.darkened(0.18)
			return shirt
		"tux":
			var white := accent
			var v_width := 2.5 - y * 0.34
			if front and y <= 7 and absf(x - 3.5) <= v_width:
				if y == 1 and x >= 2 and x <= 5:
					return Color(0.04, 0.04, 0.05)
				if (x == 3 or x == 4) and (y == 3 or y == 5):
					return Color(0.82, 0.82, 0.84)
				return white
			if front and y <= 7 and absf(x - 3.5) <= v_width + 1.0:
				return shirt.lightened(0.1)
			if front and y == 3 and x == 6:
				return white
			if front and (y == 9 or y == 11) and (x == 3 or x == 4):
				return Color(0.3, 0.3, 0.32)
			return shirt
		"armor":
			if (front or face == 1) and x >= 2 and x <= 5 and y >= 1:
				if y >= 3 and y <= 5 and (x == 3 or x == 4):
					return Color(0.95, 0.78, 0.3)
				if y == 9:
					return belt
				return accent if y < 11 else accent.darkened(0.3)
			if band and (y == 4 or y == 8):
				return shirt.darkened(0.3)
			if band and (y == 1 or y == 6) and (x == 0 or x == 7 or (face >= 2 and x == 2)):
				return shirt.lightened(0.35)
			if band and y == 9:
				return belt
			return shirt
		"robot":
			if front and y >= 2 and y <= 7 and x >= 1 and x <= 6:
				if (y == 3 and (x == 2 or x == 4)) or (y == 5 and (x == 3 or x == 5)):
					return _glow(accent)
				if y == 2 or y == 7 or x == 1 or x == 6:
					return shirt.lightened(0.15)
				return shirt.darkened(0.35)
			if band and (y == 9 or y == 10) and x % 2 == 0:
				return shirt.darkened(0.4)
			if face >= 2 and band and (x == 0 or x == 3):
				return shirt.darkened(0.2)
			return shirt
	return shirt


static func _paint_arm(style: String, o: Dictionary, right: bool, face: int, x: int, y: int, n: float) -> Color:
	var skin: Color = o.skin
	var shirt: Color = o.shirt
	var accent: Color = o.accent
	var outer := (face == 2 and right) or (face == 3 and not right)
	if face == 4:
		return shirt
	var row := 12 if face == 5 else y
	match style:
		"plain", "camper":
			if row >= 9:
				return skin
			if row == 8:
				return shirt.darkened(0.2)
			if style == "camper":
				var plaid := shirt
				if x % 3 == 0:
					plaid = plaid.darkened(0.22)
				if y % 3 == 0:
					plaid = plaid.darkened(0.22)
				return plaid
			return shirt
		"torn":
			var cut := 4 + int(n * 3.5)
			if row >= cut:
				return accent if n > 0.93 and row < 11 else skin
			return shirt
		"mask":
			if row >= 9:
				return skin
			if row == 8:
				return accent
			return shirt
		"hazmat":
			if row >= 9:
				return accent.lightened(0.08)
			if row == 8:
				return accent.lightened(0.2)
			return shirt
		"astronaut":
			if row >= 9:
				return Color(0.82, 0.83, 0.86)
			if row == 8 or row == 2:
				return accent
			if outer and row >= 4 and row <= 5 and x >= 1 and x <= 2:
				return Color(0.2, 0.35, 0.8) if row == 4 else Color(0.85, 0.15, 0.15)
			return shirt
		"tux":
			if row >= 9:
				return skin
			if row == 8:
				return accent
			if row == 7 and x == 1 and face == 0:
				return Color(0.75, 0.62, 0.25)
			return shirt
		"armor":
			if row >= 9:
				return o.pants
			if row == 3 or row == 6:
				return shirt.darkened(0.3)
			if outer and row == 1 and (x == 0 or x == 3):
				return shirt.lightened(0.35)
			return shirt
		"robot":
			if row >= 9:
				return skin.darkened(0.25) if row == 9 or x % 2 == 1 else skin
			if row == 4:
				return Color(0.08, 0.09, 0.1)
			if outer and row == 1 and (x == 1 or x == 2):
				return _glow(accent)
			return shirt
	return shirt


static func _paint_thigh(style: String, o: Dictionary, right: bool, face: int, x: int, y: int, n: float) -> Color:
	var pants: Color = o.pants
	var outer := (face == 2 and right) or (face == 3 and not right)
	match style:
		"camper":
			if outer and y >= 2 and y <= 4 and x >= 1 and x <= 2:
				return pants.darkened(0.25) if y == 2 else pants.darkened(0.12)
		"torn":
			if face <= 3 and n > 0.93:
				return o.skin
		"tux":
			if outer and (x == 1 or x == 2):
				return pants.lightened(0.12)
		"armor":
			if face <= 3 and y == 3:
				return pants.darkened(0.3)
			if face == 0 and y == 1 and (x == 0 or x == 3):
				return pants.lightened(0.35)
		"robot":
			if face <= 3 and y == 5:
				return Color(0.08, 0.09, 0.1)
		"hazmat", "astronaut":
			if face <= 3 and y == 0:
				return pants.darkened(0.1)
		"plain":
			if face == 0 and (x == 1 or x == 2) and y == 0:
				return pants.darkened(0.2)
	if face <= 3 and x == (3 if right else 0) and face == 0:
		return pants.darkened(0.08)
	return pants


static func _paint_shin(style: String, o: Dictionary, face: int, x: int, y: int, n: float) -> Color:
	var pants: Color = o.pants
	var shoes: Color = o.shoes
	if face == 4:
		return pants
	if face == 5:
		return shoes.darkened(0.2)
	var boot_top := 4
	if style == "astronaut" or style == "hazmat" or style == "armor":
		boot_top = 3
	if y >= boot_top:
		if style == "astronaut" and y == boot_top:
			return o.accent
		if y == 5:
			return shoes.darkened(0.25)
		if face == 0 and y == boot_top and style in ["plain", "camper", "torn"] and (x == 1 or x == 2):
			return shoes.lightened(0.35)
		if style == "tux" and face == 0 and y == 4:
			return shoes.lightened(0.25)
		return shoes
	match style:
		"torn":
			if y >= 2 and n > 0.5:
				return o.skin
		"armor":
			if y == 1:
				return pants.darkened(0.3)
			if face == 0 and (x == 1 or x == 2):
				return pants.lightened(0.15)
		"robot":
			if face <= 3 and (x == 0 or x == 3):
				return pants.darkened(0.25)
		"tux":
			if (face == 2 or face == 3) and (x == 1 or x == 2):
				return pants.lightened(0.12)
	return pants


static func _part_mesh(part: String) -> ArrayMesh:
	var rects: Array[Rect2] = []
	var atlas_part := part
	var center: Vector3
	var size: Vector3
	match part:
		"head":
			center = Vector3(0, 4 * PX, 0)
			size = Vector3(8, 8, 8) * PX
		"torso":
			center = Vector3(0, 6 * PX, 0)
			size = Vector3(8, 12, 4) * PX
		"arm_r", "arm_l":
			center = Vector3(0, -4 * PX, 0)
			size = Vector3(4, 12, 4) * PX
		"forearm_r", "forearm_l":
			atlas_part = "arm_r" if part == "forearm_r" else "arm_l"
			center = Vector3(0, 0.2, 0)
			size = Vector3(0.08, 0.5, 0.08)
		_:
			center = Vector3(0, -3 * PX, 0)
			size = Vector3(4, 6, 4) * PX
	var origin: Vector2i = AVATAR_PARTS[atlas_part][0]
	var dims: Vector3i = AVATAR_PARTS[atlas_part][1]
	for face in 6:
		var r := Rect2(_face_rect(origin, dims, face))
		# Viewmodel forearms show the lower three quarters of the arm (sleeve, cuff, hand).
		if atlas_part != part and face < 4:
			r = Rect2(r.position.x, r.position.y + 3, r.size.x, r.size.y - 3)
		rects.append(r)
	var k := MeshKit.new()
	k.atlas_box(0, center, size, rects, Vector2(ATLAS_SIZE, ATLAS_SIZE))
	return k.build()


static func _extra_mesh(outfit_id: String, mount: String) -> ArrayMesh:
	if not CATALOG.OUTFITS.has(outfit_id):
		return null
	var o: Dictionary = CATALOG.OUTFITS[outfit_id]
	var k := MeshKit.new()
	var mats: Array = []
	match [outfit_id, mount]:
		["astronaut", "torso"]:
			mats = [flat_material(Color(0.88, 0.88, 0.9)), flat_material(o.accent), flat_material(Color(0.4, 0.42, 0.46), 0.5, 0.4)]
			k.box(0, Vector3(0, 0.36, 0.2), Vector3(0.38, 0.46, 0.16))
			k.box(1, Vector3(0, 0.5, 0.282), Vector3(0.3, 0.05, 0.01))
			k.box(2, Vector3(0.12, 0.62, 0.2), Vector3(0.06, 0.06, 0.12))
			k.box(2, Vector3(-0.12, 0.2, 0.282), Vector3(0.06, 0.12, 0.01))
		["hazmat", "head"]:
			mats = [flat_material(Color(0.2, 0.2, 0.22), 0.6), flat_material(Color(0.36, 0.36, 0.38), 0.5, 0.3)]
			k.box(0, Vector3(0, 0.07, -0.25), Vector3(0.16, 0.11, 0.06))
			k.box(1, Vector3(0, 0.07, -0.29), Vector3(0.1, 0.07, 0.03))
		["hazmat", "torso"]:
			mats = [flat_material(Color(0.25, 0.26, 0.28), 0.5, 0.3), flat_material(o.accent)]
			k.box(0, Vector3(0, 0.4, 0.17), Vector3(0.22, 0.36, 0.12))
			k.box(1, Vector3(0, 0.5, 0.232), Vector3(0.23, 0.04, 0.01))
		["robot", "head"]:
			mats = [flat_material(Color(0.4, 0.43, 0.47), 0.4, 0.6), flat_material(o.accent, 0.4, 0.0, 3.0)]
			k.box(0, Vector3(0.13, 0.52, 0.05), Vector3(0.035, 0.14, 0.035))
			k.box(1, Vector3(0.13, 0.61, 0.05), Vector3(0.07, 0.07, 0.07))
		["knight", "arm"]:
			mats = [flat_material(Color(o.shirt).darkened(0.1), 0.4, 0.6), flat_material(o.accent)]
			k.box(0, Vector3(0, 0.08, 0), Vector3(0.27, 0.1, 0.27))
			k.box(0, Vector3(0, 0.0, 0), Vector3(0.25, 0.06, 0.25))
		["ninja", "head"]:
			mats = [flat_material(o.accent)]
			k.box(0, Vector3(0.05, 0.3, 0.25), Vector3(0.04, 0.14, 0.02), Vector3(0.25, 0, 0.2))
			k.box(0, Vector3(-0.03, 0.28, 0.25), Vector3(0.04, 0.16, 0.02), Vector3(0.3, 0, -0.15))
		["camper", "torso"]:
			mats = [flat_material(Color(0.42, 0.32, 0.2)), flat_material(Color(0.28, 0.2, 0.12))]
			k.box(0, Vector3(0, 0.34, 0.19), Vector3(0.34, 0.42, 0.14))
			k.box(1, Vector3(0, 0.56, 0.19), Vector3(0.36, 0.06, 0.15))
			k.box(1, Vector3(0.13, 0.35, -0.0), Vector3(0.04, 0.6, 0.235))
			k.box(1, Vector3(-0.13, 0.35, -0.0), Vector3(0.04, 0.6, 0.235))
		_:
			return null
	return k.build(mats)


# --- Hats ------------------------------------------------------------------------------------

static func _hat_mesh(hat_id: String) -> ArrayMesh:
	var k := MeshKit.new()
	var mats: Array = []
	match hat_id:
		"cap":
			mats = [flat_material(Color("c8242c")), flat_material(Color("f2f2f2")), flat_material(Color("8e161c"))]
			k.box(0, Vector3(0, 0.025, 0.01), Vector3(0.48, 0.13, 0.47))
			k.box(2, Vector3(0, -0.03, -0.32), Vector3(0.42, 0.03, 0.2))
			k.box(1, Vector3(0, 0.07, -0.234), Vector3(0.14, 0.08, 0.01))
			k.box(1, Vector3(0, 0.095, 0.01), Vector3(0.05, 0.03, 0.05))
		"beanie":
			mats = [flat_material(Color("2c6bd1")), flat_material(Color("1d4c99")), flat_material(Color("f2f2f2"))]
			k.box(0, Vector3(0, 0.03, 0), Vector3(0.48, 0.16, 0.48))
			k.box(0, Vector3(0, 0.12, 0), Vector3(0.36, 0.05, 0.36))
			k.box(1, Vector3(0, -0.06, 0), Vector3(0.5, 0.07, 0.5))
			k.box(2, Vector3(0, 0.19, 0), Vector3(0.11, 0.1, 0.11))
		"headphones":
			mats = [flat_material(Color("18181c"), 0.5), flat_material(Color("29ffd4"), 0.5, 0.0, 2.0), flat_material(Color("3a3a42"), 0.4, 0.5)]
			k.box(0, Vector3(0, 0.03, 0), Vector3(0.5, 0.045, 0.08))
			k.box(2, Vector3(0.245, -0.07, 0), Vector3(0.04, 0.2, 0.06))
			k.box(2, Vector3(-0.245, -0.07, 0), Vector3(0.04, 0.2, 0.06))
			k.box(0, Vector3(0.26, -0.21, 0), Vector3(0.07, 0.16, 0.16))
			k.box(0, Vector3(-0.26, -0.21, 0), Vector3(0.07, 0.16, 0.16))
			k.box(1, Vector3(0.297, -0.21, 0), Vector3(0.005, 0.08, 0.08))
			k.box(1, Vector3(-0.297, -0.21, 0), Vector3(0.005, 0.08, 0.08))
		"party":
			mats = [flat_material(Color("ff4fa3")), flat_material(Color("ffd84a")), flat_material(Color("4ad0ff"))]
			var sizes := [0.3, 0.24, 0.18, 0.13, 0.08]
			for i in sizes.size():
				var s: float = sizes[i]
				k.box(i % 2, Vector3(0, 0.04 + i * 0.075, 0), Vector3(s, 0.075, s))
			k.box(2, Vector3(0, 0.43, 0), Vector3(0.08, 0.08, 0.08))
		"cone":
			mats = [flat_material(Color("ff6a13")), flat_material(Color("f4f4f4")), flat_material(Color("2a2a2a"))]
			k.box(2, Vector3(0, 0.02, 0), Vector3(0.54, 0.04, 0.54))
			var cone := [0.36, 0.31, 0.26, 0.21, 0.16, 0.11]
			for i in cone.size():
				var s: float = cone[i]
				k.box(1 if i == 2 or i == 4 else 0, Vector3(0, 0.08 + i * 0.07, 0), Vector3(s, 0.07, s))
		"tophat":
			mats = [flat_material(Color("17171b"), 0.6), flat_material(Color("b3202a"))]
			k.box(0, Vector3(0, 0.015, 0), Vector3(0.6, 0.03, 0.6))
			k.box(0, Vector3(0, 0.2, 0), Vector3(0.4, 0.34, 0.4))
			k.box(1, Vector3(0, 0.07, 0), Vector3(0.41, 0.06, 0.41))
		"viking":
			mats = [flat_material(Color("8c939c"), 0.4, 0.7), flat_material(Color("b07a2a"), 0.4, 0.6), flat_material(Color("efe6cf"))]
			k.box(0, Vector3(0, 0.01, 0), Vector3(0.5, 0.14, 0.5))
			k.box(0, Vector3(0, 0.11, 0), Vector3(0.36, 0.08, 0.36))
			k.box(1, Vector3(0, 0.17, 0), Vector3(0.06, 0.05, 0.38))
			k.box(1, Vector3(0, -0.07, 0), Vector3(0.52, 0.05, 0.52))
			k.box(1, Vector3(0, -0.15, -0.255), Vector3(0.06, 0.16, 0.03))
			for sx: float in [1.0, -1.0]:
				k.box(2, Vector3(0.29 * sx, 0.0, 0), Vector3(0.09, 0.09, 0.09))
				k.box(2, Vector3(0.36 * sx, 0.07, 0), Vector3(0.075, 0.075, 0.075))
				k.box(2, Vector3(0.4 * sx, 0.15, 0), Vector3(0.055, 0.09, 0.055))
				k.box(2, Vector3(0.405 * sx, 0.225, 0), Vector3(0.035, 0.06, 0.035))
		"halo":
			mats = [flat_material(Color("ffe27a"), 0.3, 0.4, 2.2)]
			k.box(0, Vector3(0, 0.16, 0.17), Vector3(0.4, 0.035, 0.06))
			k.box(0, Vector3(0, 0.16, -0.17), Vector3(0.4, 0.035, 0.06))
			k.box(0, Vector3(0.17, 0.16, 0), Vector3(0.06, 0.035, 0.28))
			k.box(0, Vector3(-0.17, 0.16, 0), Vector3(0.06, 0.035, 0.28))
		"crown":
			mats = [flat_material(Color("ffc531"), 0.25, 0.9), flat_material(Color("d81f3a"), 0.2, 0.2, 0.6), flat_material(Color("2d7cff"), 0.2, 0.2, 0.6)]
			k.box(0, Vector3(0, 0.03, -0.23), Vector3(0.5, 0.12, 0.04))
			k.box(0, Vector3(0, 0.03, 0.23), Vector3(0.5, 0.12, 0.04))
			k.box(0, Vector3(0.23, 0.03, 0), Vector3(0.04, 0.12, 0.42))
			k.box(0, Vector3(-0.23, 0.03, 0), Vector3(0.04, 0.12, 0.42))
			for i in 3:
				var t := (i - 1) * 0.19
				k.box(0, Vector3(t, 0.12, -0.23), Vector3(0.06, 0.07, 0.04))
				k.box(0, Vector3(t, 0.12, 0.23), Vector3(0.06, 0.07, 0.04))
				k.box(0, Vector3(0.23, 0.12, t), Vector3(0.04, 0.07, 0.06))
				k.box(0, Vector3(-0.23, 0.12, t), Vector3(0.04, 0.07, 0.06))
			k.box(1, Vector3(0, 0.03, -0.252), Vector3(0.07, 0.06, 0.01))
			k.box(2, Vector3(0.14, 0.03, -0.252), Vector3(0.05, 0.05, 0.01))
			k.box(2, Vector3(-0.14, 0.03, -0.252), Vector3(0.05, 0.05, 0.01))
			k.box(1, Vector3(0.252, 0.03, 0), Vector3(0.01, 0.06, 0.07))
			k.box(1, Vector3(-0.252, 0.03, 0), Vector3(0.01, 0.06, 0.07))
	return k.build(mats)


# --- Pickups and projectiles -----------------------------------------------------------------

static func _grenade_into(k: MeshKit, at: Vector3, body: int, groove: int, metal: int, ring: int) -> void:
	k.box(body, at, Vector3(0.07, 0.08, 0.07))
	k.box(groove, at + Vector3(0, 0.014, 0), Vector3(0.074, 0.008, 0.074))
	k.box(groove, at + Vector3(0, -0.014, 0), Vector3(0.074, 0.008, 0.074))
	k.box(groove, at, Vector3(0.008, 0.084, 0.074))
	k.box(groove, at, Vector3(0.074, 0.084, 0.008))
	k.box(metal, at + Vector3(0, 0.046, 0), Vector3(0.036, 0.014, 0.036))
	k.box(metal, at + Vector3(0, 0.058, 0), Vector3(0.024, 0.012, 0.024))
	k.box(metal, at + Vector3(0.042, 0.02, 0), Vector3(0.008, 0.07, 0.02), Vector3(0, 0, 0.12))
	k.box(ring, at + Vector3(-0.026, 0.062, 0), Vector3(0.022, 0.022, 0.005))


static func _grenade_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	_grenade_into(k, Vector3.ZERO, 0, 1, 2, 3)
	return k.build(_grenade_materials())


static func _grenade_materials() -> Array:
	return [flat_material(Color("4d5a2c")), flat_material(Color("2e361a")),
		flat_material(Color(0.42, 0.43, 0.46), 0.35, 0.7), flat_material(Color("c9a646"), 0.3, 0.8)]


static func _rocket_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	var mats := [flat_material(Color("56603a")), flat_material(Color("c8261c")),
		flat_material(Color(0.36, 0.37, 0.4), 0.35, 0.7), flat_material(Color("22261a")),
		flat_material(Color("ffb347"), 0.5, 0.0, 4.0)]
	k.box(0, Vector3(0, 0, 0), Vector3(0.06, 0.06, 0.3))
	k.box(1, Vector3(0, 0, -0.18), Vector3(0.07, 0.07, 0.06))
	k.box(1, Vector3(0, 0, -0.225), Vector3(0.05, 0.05, 0.03))
	k.box(1, Vector3(0, 0, -0.25), Vector3(0.026, 0.026, 0.02))
	k.box(2, Vector3(0, 0, -0.15), Vector3(0.064, 0.064, 0.012))
	k.box(3, Vector3(0, 0, 0.06), Vector3(0.062, 0.062, 0.02))
	k.box(3, Vector3(0, 0.055, 0.17), Vector3(0.008, 0.06, 0.08))
	k.box(3, Vector3(0, -0.055, 0.17), Vector3(0.008, 0.06, 0.08))
	k.box(3, Vector3(0.055, 0, 0.17), Vector3(0.06, 0.008, 0.08))
	k.box(3, Vector3(-0.055, 0, 0.17), Vector3(0.06, 0.008, 0.08))
	k.box(2, Vector3(0, 0, 0.2), Vector3(0.04, 0.04, 0.04))
	k.box(4, Vector3(0, 0, 0.225), Vector3(0.03, 0.03, 0.01))
	return k.build(mats)


static func _pickup_mesh(kind: String) -> ArrayMesh:
	var k := MeshKit.new()
	var mats: Array
	match kind:
		"health":
			mats = [flat_material(Color("f2f2ee"), 0.6), flat_material(Color("d4202a"), 0.6),
				flat_material(Color("b9bcc2"), 0.5, 0.3)]
			k.box(0, Vector3(0, 0.17, 0), Vector3(0.48, 0.34, 0.4))
			k.box(2, Vector3(0, 0.26, 0), Vector3(0.49, 0.02, 0.41))
			k.box(2, Vector3(0, 0.355, 0), Vector3(0.2, 0.03, 0.05))
			k.box(2, Vector3(0.09, 0.345, 0), Vector3(0.03, 0.03, 0.05))
			k.box(2, Vector3(-0.09, 0.345, 0), Vector3(0.03, 0.03, 0.05))
			k.box(1, Vector3(0, 0.341, 0), Vector3(0.24, 0.004, 0.08))
			k.box(1, Vector3(0, 0.341, 0), Vector3(0.08, 0.004, 0.24))
			for side: float in [-1.0, 1.0]:
				k.box(1, Vector3(0, 0.15, 0.2 * side + 0.003 * side), Vector3(0.18, 0.06, 0.006))
				k.box(1, Vector3(0, 0.15, 0.2 * side + 0.003 * side), Vector3(0.06, 0.18, 0.006))
				k.box(1, Vector3(0.24 * side + 0.003 * side, 0.15, 0), Vector3(0.006, 0.06, 0.18))
				k.box(1, Vector3(0.24 * side + 0.003 * side, 0.15, 0), Vector3(0.006, 0.18, 0.06))
				k.box(2, Vector3(0.15 * side, 0.26, -0.207), Vector3(0.04, 0.05, 0.015))
		"ammo":
			var olive := Color("4f5a2a")
			mats = [flat_material(olive), flat_material(olive.darkened(0.35)),
				flat_material(Color("c9a646"), 0.3, 0.8), flat_material(Color("b8693a"), 0.35, 0.7),
				flat_material(Color("e8d24a"))]
			k.box(0, Vector3(0, 0.15, 0), Vector3(0.54, 0.3, 0.36))
			k.box(1, Vector3(0, 0.29, 0), Vector3(0.56, 0.03, 0.38))
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					k.box(1, Vector3(0.255 * sx, 0.15, 0.165 * sz), Vector3(0.04, 0.3, 0.04))
				k.box(1, Vector3(0.28 * sx, 0.2, 0), Vector3(0.02, 0.035, 0.14))
			k.box(1, Vector3(0, 0.03, 0), Vector3(0.55, 0.04, 0.37))
			k.box(4, Vector3(-0.1, 0.17, -0.182), Vector3(0.22, 0.05, 0.004))
			k.box(4, Vector3(0.12, 0.17, -0.182), Vector3(0.06, 0.05, 0.004))
			for i in 5:
				var x := -0.16 + i * 0.08
				k.box(2, Vector3(x, 0.34, 0), Vector3(0.036, 0.07, 0.036))
				k.box(3, Vector3(x, 0.39, 0), Vector3(0.026, 0.03, 0.026))
				k.box(3, Vector3(x, 0.41, 0), Vector3(0.014, 0.014, 0.014))
		_:
			var green := Color("3c4a2a")
			mats = [flat_material(Color("4d5a2c")), flat_material(Color("2e361a")),
				flat_material(Color(0.42, 0.43, 0.46), 0.35, 0.7), flat_material(Color("c9a646"), 0.3, 0.8),
				flat_material(green), flat_material(green.darkened(0.35)), flat_material(Color("e8c21a"))]
			k.box(4, Vector3(0, 0.12, 0), Vector3(0.42, 0.24, 0.42))
			k.box(5, Vector3(0, 0.235, 0), Vector3(0.44, 0.03, 0.44))
			k.box(5, Vector3(0, 0.015, 0), Vector3(0.44, 0.03, 0.44))
			k.box(6, Vector3(0, 0.12, 0), Vector3(0.425, 0.04, 0.425))
			_grenade_into(k, Vector3(-0.09, 0.29, 0.02), 0, 1, 2, 3)
			_grenade_into(k, Vector3(0.09, 0.29, -0.04), 0, 1, 2, 3)
			_grenade_into(k, Vector3(0.0, 0.29, 0.12), 0, 1, 2, 3)
	return k.build(mats)
