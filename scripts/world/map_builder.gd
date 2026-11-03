class_name MapBuilder
extends RefCounted
## Builds a playable voxel map (meshes, collision, boundary walls, lighting,
## environment and a baked navigation mesh) deterministically from its id.
##
## Generators live in scripts/world/maps/. Each exposes `SIZE: Vector3i`,
## `KILL_Y: float`, `ATMOSPHERE: Dictionary` and
## `static func generate(g: VoxelGrid, info: MapInfo)`, which fills the grid
## and appends spawns/pickups in grid space; this builder moves them to world
## space (the grid is centred on the origin in X/Z, y = 0 is the grid floor).
## Custom maps (ids CustomMaps.PREFIX + name, from the Map Editor) come from CustomMaps.generate
## and use CustomMaps.ATMOSPHERE.

const GENERATORS := {
	"village": preload("res://scripts/world/maps/village_map.gd"),
	"desert": preload("res://scripts/world/maps/desert_map.gd"),
	"factory": preload("res://scripts/world/maps/factory_map.gd"),
	"sky": preload("res://scripts/world/maps/sky_map.gd"),
	"snow": preload("res://scripts/world/maps/snow_map.gd"),
	"harbor": preload("res://scripts/world/maps/harbor_map.gd"),
	"temple": preload("res://scripts/world/maps/temple_map.gd"),
	"rooftops": preload("res://scripts/world/maps/rooftops_map.gd"),
	"moon": preload("res://scripts/world/maps/moon_map.gd"),
	"volcano": preload("res://scripts/world/maps/volcano_map.gd"),
	"building": preload("res://scripts/world/maps/building_map.gd"),
	"range": preload("res://scripts/world/maps/range_map.gd"),
}

const NAV_CELL := 0.25
const PREVIEW_SCALE := 4
## Group holding each map's sun and WorldEnvironment, for live Video setting changes.
const GRAPHICS_GROUP := &"map_graphics"

static var _previews := {}
static var _space_shader: Shader

## Sky of `atm.sky == "space"` (Moon Base): near-black gradient, two layers of hashed stars and a
## faint galactic band (left out of the radiance cubemap, so ambient light stays smooth), the sun
## disc at `sun_dir`, and an Earth disc at `earth_dir` (`earth_radius` radians) with procedural
## oceans, land, clouds and ice caps, lit from `sun_dir` with a blue limb. No TIME, so the sky and
## its radiance render once.
const SPACE_SKY_SHADER := """
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.0);
uniform vec3 horizon_color : source_color = vec3(0.03);
uniform vec3 ground_color : source_color = vec3(0.0);
uniform float energy = 1.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0);
uniform float sun_disc = 1.0;
uniform vec3 earth_dir = vec3(0.0, 0.4, -1.0);
uniform float earth_radius = 0.09;
uniform float stars = 1.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

vec3 star_layer(vec3 d, float scale, float density, float size) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	if (hash13(cell) > density) {
		return vec3(0.0);
	}
	vec3 c = cell + 0.5 + (vec3(hash13(cell + 7.1), hash13(cell + 3.7), hash13(cell + 1.3)) - 0.5) * 0.5;
	float b = smoothstep(size, 0.0, length(p - c)) * (0.35 + 0.65 * hash13(cell + 11.0));
	return mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.88, 0.72), hash13(cell + 5.0)) * b;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = d.y >= 0.0 ? mix(horizon_color, top_color, pow(clamp(d.y, 0.0, 1.0), 0.35))
		: mix(horizon_color, ground_color, pow(clamp(-d.y, 0.0, 1.0), 0.35));
	if (!AT_CUBEMAP_PASS) {
		col += (star_layer(d, 190.0, 0.08, 0.32) + star_layer(d, 70.0, 0.03, 0.22) * 1.8) * stars;
		float band = exp(-pow(dot(d, normalize(vec3(0.3, 0.55, 0.78))) / 0.22, 2.0));
		if (band > 0.03) {
			col += vec3(0.22, 0.2, 0.3) * band * smoothstep(0.35, 0.8, fbm(d * 5.0)) * 0.35 * stars;
		}
	}
	float sd = dot(d, sun_dir);
	col += sun_color * sun_disc * (smoothstep(0.99975, 0.9999, sd) * 24.0 + pow(max(sd, 0.0), 900.0) * 2.0 + pow(max(sd, 0.0), 60.0) * 0.06);
	vec3 e = normalize(earth_dir);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), e));
	vec3 up = cross(e, right);
	vec2 uv = vec2(dot(d, right), dot(d, up)) / sin(earth_radius);
	float r2 = dot(uv, uv);
	if (dot(d, e) > 0.0 && r2 < 1.6) {
		if (r2 < 1.0) {
			vec3 local = vec3(uv, sqrt(1.0 - r2));
			vec3 n = right * uv.x + up * uv.y - e * local.z;
			float land = smoothstep(0.5, 0.56, fbm(local * 2.4 + vec3(3.1, 1.7, 0.4)));
			float cloud = smoothstep(0.52, 0.72, fbm(local * 4.5 + vec3(9.0, 2.0, 5.0)));
			float ice = smoothstep(0.78, 0.9, abs(uv.y));
			vec3 ground = mix(vec3(0.2, 0.42, 0.16), vec3(0.55, 0.45, 0.28), noise3(local * 7.0));
			vec3 surf = mix(vec3(0.04, 0.14, 0.42), ground, land);
			surf = mix(surf, vec3(0.95), max(cloud * 0.85, ice));
			float lit = clamp(dot(n, sun_dir) * 1.3 + 0.08, 0.0, 1.0);
			vec3 earth = surf * (0.025 + lit * 1.7) + vec3(0.3, 0.55, 1.0) * pow(r2, 4.0) * (0.1 + lit * 0.9);
			col = mix(col, earth, smoothstep(1.0, 0.96, r2));
		} else {
			col += vec3(0.3, 0.55, 1.0) * exp(-(sqrt(r2) - 1.0) * 28.0) * 0.12;
		}
	}
	COLOR = col * energy;
}
"""


## `editable` (the Demolition mutator) keeps the block grid, the VoxelMesher and the navigation
## region in the MapInfo so blocks can be removed and the navmesh rebaked mid-match.
static func build(map_id: String, root: Node3D, quality: int, editable := false) -> MapInfo:
	var info := MapInfo.new()
	var grid := generate(map_id, info)
	var map_root := Node3D.new()
	map_root.name = "Map"
	root.add_child(map_root)
	var xform := map_root.global_transform if map_root.is_inside_tree() else Transform3D.IDENTITY
	var source := NavigationMeshSourceGeometryData3D.new()
	var mesher := VoxelMesher.build(grid, map_root, info.bounds.position, source, xform, Callable(), editable)
	_add_bounds(map_root, info.bounds)
	add_environment(map_root, atmosphere(info.id), quality)
	info.nav_map = _add_navigation(map_root, source, info.bounds)
	_add_jump_pads(map_root, info)
	_add_effects(map_root, info, atmosphere(info.id), quality)
	if editable:
		info.grid = grid
		info.mesher = mesher
		info.nav_region = map_root.get_node_or_null(^"Navigation")
	return info


## Runs map `map_id`'s generator: fills `info` (id, name, kill height, world-space spawns, pickups,
## marks and bounds) and returns the block grid, whose cell (0,0,0) sits at `info.bounds.position`.
static func generate(map_id: String, info: MapInfo) -> VoxelGrid:
	var grid: VoxelGrid = CustomMaps.generate(map_id, info) if CustomMaps.is_custom(map_id) else null
	if grid == null:
		if not GENERATORS.has(map_id):
			push_error("MapBuilder: unknown map '%s', using village" % map_id)
			map_id = "village"
		var gen: GDScript = GENERATORS[map_id]
		info.id = map_id
		info.display_name = Data.MAPS[map_id].name
		info.kill_y = gen.KILL_Y
		info.kill_cause = str(gen.get_script_constant_map().get("KILL_CAUSE", "fall"))
		grid = VoxelGrid.new(gen.SIZE)
		gen.generate(grid, info)

	var origin := Vector3(-grid.size.x / 2, 0, -grid.size.z / 2)
	for i in info.spawns.size():
		if not grid.standable(floori(info.spawns[i].x), floori(info.spawns[i].y), floori(info.spawns[i].z)):
			push_error("MapBuilder: %s spawn %d at %s is blocked" % [map_id, i, info.spawns[i]])
		info.spawns[i] += origin
	for p: Dictionary in info.pickups:
		p.pos += origin
	for key: String in info.marks:
		info.marks[key] = _offset_mark(info.marks[key], origin)
	info.bounds = AABB(origin, Vector3(grid.size))
	return grid


## Scenery only, for the menu backdrop: the block meshes of the chunks `keep_chunk(cx, cz)` accepts
## (VoxelMesher.build) plus sky, sun and fog, with `atmosphere` keys overriding the map's own (a
## sunset, say). No collision, boundary walls, navigation or jump pads.
static func build_scenery(grid: VoxelGrid, info: MapInfo, root: Node3D, quality: int, atmosphere: Dictionary, keep_chunk: Callable) -> void:
	var map_root := Node3D.new()
	map_root.name = "Map"
	root.add_child(map_root)
	VoxelMesher.build(grid, map_root, info.bounds.position, null, Transform3D.IDENTITY, keep_chunk)
	var atm: Dictionary = MapBuilder.atmosphere(info.id).duplicate()
	atm.merge(atmosphere, true)
	add_environment(map_root, atm, quality)


## One JumpPad per entry of the generator's `jump_pads` mark (MapKit.jump_pads: feet on the pad
## centre, the landing feet, the apex height above the higher of the two, an optional drop), after
## the navmesh so each pad's navigation links join it.
static func _add_jump_pads(parent: Node3D, info: MapInfo) -> void:
	for m: Dictionary in info.marks.get("jump_pads", []):
		var pad := JumpPad.new()
		pad.name = "JumpPad%d" % info.jump_pads.size()
		pad.setup(m.pos, m.target, float(m.rise), [m.drop_from, m.drop_to] if m.has("drop_from") else [])
		parent.add_child(pad)
		info.jump_pads.append(pad)


## A MapInfo mark moved from grid space to world space (see MapInfo.marks).
static func _offset_mark(mark: Variant, origin: Vector3) -> Variant:
	if mark is Vector3:
		return mark + origin
	if mark is AABB:
		return AABB((mark as AABB).position + origin, (mark as AABB).size)
	if mark is Array:
		for entry: Dictionary in mark:
			entry.pos += origin
			for key: String in ["target", "drop_from", "drop_to"]:
				if entry.has(key):
					entry[key] += origin
	return mark


## On-screen name of a map id: its Data.MAPS name, or a custom map's own name.
static func map_name(map_id: String) -> String:
	if Data.MAPS.has(map_id):
		return str(Data.MAPS[map_id].name)
	return CustomMaps.name_of(map_id) if CustomMaps.is_custom(map_id) else map_id


## The sky, sun and fog settings of map `map_id` (before its time of day).
static func atmosphere(map_id: String) -> Dictionary:
	return GENERATORS[map_id].ATMOSPHERE if GENERATORS.has(map_id) else CustomMaps.ATMOSPHERE


## Top-down colour map of the top blocks, scaled up with nearest filtering (null for an unknown
## map or a custom map this peer doesn't have).
static func preview(map_id: String) -> ImageTexture:
	if _previews.has(map_id):
		return _previews[map_id]
	var grid: VoxelGrid
	if CustomMaps.is_custom(map_id):
		grid = CustomMaps.generate(map_id, MapInfo.new())
	elif GENERATORS.has(map_id):
		var gen: GDScript = GENERATORS[map_id]
		grid = VoxelGrid.new(gen.SIZE)
		gen.generate(grid, MapInfo.new())
	if grid == null:
		if not CustomMaps.is_custom(map_id):
			push_error("MapBuilder: unknown map '%s'" % map_id)
		return null
	var tex := render_preview(grid)
	_previews[map_id] = tex
	return tex


## Drops a cached preview (a custom map saved again).
static func forget_preview(map_id: String) -> void:
	_previews.erase(map_id)


## The preview() picture of `grid`.
static func render_preview(grid: VoxelGrid) -> ImageTexture:
	var s := grid.size
	var img := Image.create(s.x, s.z, false, Image.FORMAT_RGBA8)
	var heights := PackedInt32Array()
	heights.resize(s.x * s.z)
	for z in s.z:
		for x in s.x:
			var top := -1
			for y in range(s.y - 1, -1, -1):
				if grid.blocks[grid.index(x, y, z)] != BlockAtlas.AIR:
					top = y
					break
			heights[z * s.x + x] = top
	for z in s.z:
		for x in s.x:
			var top := heights[z * s.x + x]
			if top < 0:
				img.set_pixel(x, z, Color(0.05, 0.07, 0.12, 0.0))
				continue
			var c := BlockAtlas.top_color(grid.blocks[grid.index(x, top, z)])
			c = c.darkened(0.35 * (1.0 - float(top) / float(s.y)))
			# Light from the north-west for relief.
			var nw := heights[maxi(z - 1, 0) * s.x + maxi(x - 1, 0)]
			if nw > top:
				c = c.darkened(0.2)
			elif nw < top:
				c = c.lightened(0.12)
			c.a = 1.0
			img.set_pixel(x, z, c)
	img.resize(s.x * PREVIEW_SCALE, s.z * PREVIEW_SCALE, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


## Invisible walls around the grid so nobody can leave the play area.
static func _add_bounds(parent: Node3D, bounds: AABB) -> void:
	var body := StaticBody3D.new()
	body.name = "Bounds"
	body.collision_layer = 1
	body.collision_mask = 0
	var low := -60.0
	var high := bounds.size.y + 40.0
	var center := bounds.get_center()
	var t := 2.0
	for side in 4:
		var horizontal := side < 2
		var shape := BoxShape3D.new()
		shape.size = Vector3(bounds.size.x + t * 2.0, high - low, t) if horizontal else Vector3(t, high - low, bounds.size.z + t * 2.0)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var sign := -1.0 if side % 2 == 0 else 1.0
		if horizontal:
			cs.position = Vector3(center.x, (high + low) * 0.5, center.z + sign * (bounds.size.z * 0.5 + t * 0.5))
		else:
			cs.position = Vector3(center.x + sign * (bounds.size.x * 0.5 + t * 0.5), (high + low) * 0.5, center.z)
		body.add_child(cs)
	var lid := BoxShape3D.new()
	lid.size = Vector3(bounds.size.x, t, bounds.size.z)
	var lid_cs := CollisionShape3D.new()
	lid_cs.shape = lid
	lid_cs.position = Vector3(center.x, high, center.z)
	body.add_child(lid_cs)
	parent.add_child(body)


## Sky, WorldEnvironment and sun under `parent` from atmosphere settings `atm` (also the Map
## Editor's, which rebuilds them when the time of day changes). `atm.sky == "space"` draws the
## SPACE_SKY shader (black, stars, an Earth) instead of the procedural sky. The WorldEnvironment
## keeps `atm` as its "atmosphere" meta, so World._apply_time_of_day can apply a map's own
## `times` overrides (apply_atmosphere).
static func add_environment(parent: Node3D, atm: Dictionary, quality: int) -> void:
	var sky := Sky.new()
	if str(atm.get("sky", "")) == "space":
		var mat := ShaderMaterial.new()
		if _space_shader == null:
			_space_shader = Shader.new()
			_space_shader.code = SPACE_SKY_SHADER
		mat.shader = _space_shader
		sky.sky_material = mat
	else:
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_curve = 0.12
		sky_mat.ground_curve = 0.04
		sky_mat.sun_angle_max = 20.0
		sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if quality == 0 else Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_aerial_perspective = 0.15
	env.sdfgi_enabled = false
	# SSAO, SSIL, bloom, SSR, brightness and sun shadows follow the Video settings
	# (apply_graphics), live.
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_detail = 0.5
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.7
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	world_env.set_meta(&"atmosphere", atm)
	world_env.add_to_group(GRAPHICS_GROUP)
	_apply_graphics_to(world_env)
	parent.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.add_to_group(GRAPHICS_GROUP)
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	_apply_graphics_to(sun)
	parent.add_child(sun)
	apply_atmosphere(world_env, sun, atm)


## Sets the sky colours, ambient light, fog, exposure and sun of an add_environment pair from
## `atm` (a map's ATMOSPHERE, or that merged with one of its `times` entries).
static func apply_atmosphere(world_env: WorldEnvironment, sun: DirectionalLight3D, atm: Dictionary) -> void:
	var env := world_env.environment
	var horizon: Color = atm.sky_horizon
	sun.rotation_degrees = Vector3(atm.sun_pitch, atm.sun_yaw, 0.0)
	sun.light_color = atm.sun_color
	sun.light_energy = atm.sun_energy
	if env.sky.sky_material is ProceduralSkyMaterial:
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		sky_mat.sky_top_color = atm.sky_top
		sky_mat.sky_horizon_color = horizon
		sky_mat.ground_bottom_color = atm.ground_bottom
		sky_mat.ground_horizon_color = horizon.lerp(atm.ground_bottom, 0.3)
		sky_mat.sky_energy_multiplier = atm.get("sky_energy", 1.0)
	else:
		var mat := env.sky.sky_material as ShaderMaterial
		mat.set_shader_parameter("top_color", atm.sky_top)
		mat.set_shader_parameter("horizon_color", horizon)
		mat.set_shader_parameter("ground_color", atm.ground_bottom)
		mat.set_shader_parameter("energy", atm.get("sky_energy", 1.0))
		# The sun disc sits where the light comes from unless `space_sun_dir` moves it (night:
		# the light is earthshine and the sun is behind the moon, lighting the Earth full).
		mat.set_shader_parameter("sun_dir", (atm.get("space_sun_dir", sun.basis.z) as Vector3).normalized())
		mat.set_shader_parameter("sun_color", atm.sun_color)
		mat.set_shader_parameter("sun_disc", atm.get("sun_disc", 1.0))
		mat.set_shader_parameter("earth_dir", (atm.get("earth_dir", Vector3(0.0, 0.4, -1.0)) as Vector3).normalized())
		mat.set_shader_parameter("earth_radius", atm.get("earth_radius", 0.09))
		mat.set_shader_parameter("stars", atm.get("stars", 1.0))
	env.ambient_light_energy = atm.get("ambient", 1.0)
	# Mix a neutral tint into the sky light so shadows are not saturated blue.
	env.ambient_light_color = atm.get("ambient_color", horizon)
	env.tonemap_exposure = atm.get("exposure", 1.0)
	env.fog_light_color = atm.fog_color
	env.fog_density = atm.fog_density
	env.fog_sky_affect = atm.get("fog_sky", 0.3)
	env.adjustment_saturation = atm.get("saturation", 1.1)


## Map effects from the atmosphere and the generator's marks: the `glow_lights` mark ([{pos,
## color, range, energy}]: OmniLight3Ds without shadows, e.g. over lava) and, with `atm.embers`,
## rising ember particles over the whole map plus a denser plume at each glow light. Particle
## counts drop at quality 0 (the Low preset).
static func _add_effects(parent: Node3D, info: MapInfo, atm: Dictionary, quality: int) -> void:
	for m: Dictionary in info.marks.get("glow_lights", []):
		var light := OmniLight3D.new()
		light.position = m.pos
		light.light_color = m.color
		light.omni_range = m.range
		light.light_energy = m.energy
		light.shadow_enabled = false
		parent.add_child(light)
	if not atm.get("embers", false):
		return
	var low := quality == 0
	var b := info.bounds
	var floor_y := b.position.y + float(atm.get("ember_floor", 2.0))
	_add_ember_emitter(parent, Vector3(b.get_center().x, floor_y + 5.0, b.get_center().z),
		Vector3(b.size.x * 0.5, 5.0, b.size.z * 0.5), 70 if low else 200, Vector2(0.3, 0.9))
	for m: Dictionary in info.marks.get("glow_lights", []):
		_add_ember_emitter(parent, Vector3(m.pos.x, floor_y, m.pos.z), Vector3(4.0, 0.5, 4.0), 16 if low else 40, Vector2(1.0, 2.6))


static func _add_ember_emitter(parent: Node3D, pos: Vector3, extents: Vector3, amount: int, speed: Vector2) -> void:
	var p := GPUParticles3D.new()
	p.name = "Embers"
	p.position = pos
	p.amount = amount
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.visibility_aabb = AABB(-extents - Vector3(2, 2, 2), extents * 2.0 + Vector3(4, 22, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = Vector3(0.25, 0.35, 0.12)
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(4.0, 1.6, 0.35, 0.0))
	ramp.set_color(1, Color(1.2, 0.2, 0.05, 0.0))
	ramp.add_point(0.12, Color(4.0, 1.5, 0.3, 1.0))
	ramp.add_point(0.7, Color(2.4, 0.6, 0.1, 0.8))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	tex.use_hdr = true
	pm.color_ramp = tex
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)


## Applies the Video settings (shadow quality, ambient occlusion, indirect light, bloom,
## reflections, brightness) to every built map's sun and environment. Video.apply calls it
## whenever a setting changes; the shadow atlas and filter quality are global (Video.apply).
static func apply_graphics(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group(GRAPHICS_GROUP):
		_apply_graphics_to(node)


static func _apply_graphics_to(node: Node) -> void:
	if node is DirectionalLight3D:
		var sun := node as DirectionalLight3D
		var shadow := int(Profile.get_setting("shadow_quality"))
		sun.shadow_enabled = shadow > 0
		if shadow > 0:
			var level: Array = Video.SHADOW_LEVELS[shadow]
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(level[0]) == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = level[1]
			sun.directional_shadow_blend_splits = level[4]
	elif node is WorldEnvironment and (node as WorldEnvironment).environment != null:
		var env := (node as WorldEnvironment).environment
		env.ssao_enabled = int(Profile.get_setting("ssao_quality")) > 0
		env.ssil_enabled = bool(Profile.get_setting("ssil"))
		env.glow_enabled = bool(Profile.get_setting("bloom"))
		env.ssr_enabled = bool(Profile.get_setting("reflections"))
		env.adjustment_brightness = float(Profile.get_setting("brightness"))


## Agent: radius 0.45 m, height 1.8 m, climb 0.3 m, slope 50 deg. Recast rounds
## these to whole 0.25 m voxels anyway (radius and height up, climb down), so
## the rounded values are set directly to keep the bake free of precision
## warnings.
static func _add_navigation(parent: Node3D, source: NavigationMeshSourceGeometryData3D, bounds: AABB) -> RID:
	var nm := navigation_mesh(bounds)
	NavigationServer3D.bake_from_source_geometry_data(nm, source)
	if not parent.is_inside_tree():
		push_error("MapBuilder: build() root must be inside the scene tree for navigation")
		return RID()
	var map := parent.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, NAV_CELL)
	NavigationServer3D.map_set_cell_height(map, NAV_CELL)
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = nm
	parent.add_child(region)
	# Sync region and map now (not on a worker thread) so bots can path
	# immediately. The map only changes when Demolition swaps in a rebaked
	# navmesh, so synchronous iterations cost nothing otherwise.
	NavigationServer3D.region_set_use_async_iterations(region.get_rid(), false)
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_force_update(map)
	return map


## An empty NavigationMesh with the map's bake settings (see _add_navigation); Demolition bakes
## its rebakes into one.
static func navigation_mesh(bounds: AABB) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = NAV_CELL
	nm.cell_height = NAV_CELL
	nm.agent_radius = ceilf(0.45 / NAV_CELL) * NAV_CELL
	nm.agent_height = ceilf(1.8 / NAV_CELL) * NAV_CELL
	nm.agent_max_climb = floorf(0.3 / NAV_CELL) * NAV_CELL
	nm.agent_max_slope = 50.0
	nm.filter_baking_aabb = bounds.grow(1.0)
	return nm
