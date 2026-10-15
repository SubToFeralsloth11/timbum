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

const GENERATORS := {
	"village": preload("res://scripts/world/maps/village_map.gd"),
	"desert": preload("res://scripts/world/maps/desert_map.gd"),
	"factory": preload("res://scripts/world/maps/factory_map.gd"),
	"sky": preload("res://scripts/world/maps/sky_map.gd"),
	"snow": preload("res://scripts/world/maps/snow_map.gd"),
}

const NAV_CELL := 0.25
const PREVIEW_SCALE := 4

static var _previews := {}


static func build(map_id: String, root: Node3D, quality: int) -> MapInfo:
	if not GENERATORS.has(map_id):
		push_error("MapBuilder: unknown map '%s', using village" % map_id)
		map_id = "village"
	var gen: GDScript = GENERATORS[map_id]
	var info := MapInfo.new()
	info.id = map_id
	info.display_name = Data.MAPS[map_id].name
	info.kill_y = gen.KILL_Y
	var grid := VoxelGrid.new(gen.SIZE)
	gen.generate(grid, info)

	var origin := Vector3(-grid.size.x / 2, 0, -grid.size.z / 2)
	for i in info.spawns.size():
		if not grid.standable(floori(info.spawns[i].x), floori(info.spawns[i].y), floori(info.spawns[i].z)):
			push_error("MapBuilder: %s spawn %d at %s is blocked" % [map_id, i, info.spawns[i]])
		info.spawns[i] += origin
	for p: Dictionary in info.pickups:
		p.pos += origin
	info.bounds = AABB(origin, Vector3(grid.size))

	var map_root := Node3D.new()
	map_root.name = "Map"
	root.add_child(map_root)
	var xform := map_root.global_transform if map_root.is_inside_tree() else Transform3D.IDENTITY
	var source := NavigationMeshSourceGeometryData3D.new()
	VoxelMesher.build(grid, map_root, origin, source, xform)
	_add_bounds(map_root, info.bounds)
	_add_environment(map_root, gen.ATMOSPHERE, quality)
	info.nav_map = _add_navigation(map_root, source, info.bounds)
	return info


## Top-down colour map of the top blocks, scaled up with nearest filtering.
static func preview(map_id: String) -> ImageTexture:
	if _previews.has(map_id):
		return _previews[map_id]
	if not GENERATORS.has(map_id):
		push_error("MapBuilder: unknown map '%s'" % map_id)
		return null
	var gen: GDScript = GENERATORS[map_id]
	var grid := VoxelGrid.new(gen.SIZE)
	gen.generate(grid, MapInfo.new())
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
	var tex := ImageTexture.create_from_image(img)
	_previews[map_id] = tex
	return tex


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


static func _add_environment(parent: Node3D, atm: Dictionary, quality: int) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = atm.sky_top
	sky_mat.sky_horizon_color = atm.sky_horizon
	sky_mat.ground_bottom_color = atm.ground_bottom
	sky_mat.ground_horizon_color = atm.sky_horizon.lerp(atm.ground_bottom, 0.3)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_curve = 0.04
	sky_mat.sun_angle_max = 20.0
	sky_mat.sky_energy_multiplier = atm.get("sky_energy", 1.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if quality == 0 else Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = atm.get("ambient", 1.0)
	# Mix a neutral tint into the sky light so shadows are not saturated blue.
	env.ambient_light_color = atm.get("ambient_color", atm.sky_horizon)
	env.ambient_light_sky_contribution = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = atm.get("exposure", 1.0)
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = atm.fog_color
	env.fog_density = atm.fog_density
	env.fog_sky_affect = atm.get("fog_sky", 0.3)
	env.fog_aerial_perspective = 0.15
	env.sdfgi_enabled = false
	env.ssao_enabled = quality >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_detail = 0.5
	env.glow_enabled = quality >= 1
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = atm.get("saturation", 1.1)
	env.adjustment_contrast = 1.05
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(atm.sun_pitch, atm.sun_yaw, 0.0)
	sun.light_color = atm.sun_color
	sun.light_energy = atm.sun_energy
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = [45.0, 80.0, 130.0][clampi(quality, 0, 2)]
	sun.directional_shadow_blend_splits = quality >= 2
	parent.add_child(sun)
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 8192][clampi(quality, 0, 2)], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([
		RenderingServer.SHADOW_QUALITY_HARD,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
	][clampi(quality, 0, 2)])


## Agent: radius 0.45 m, height 1.8 m, climb 0.3 m, slope 50 deg. Recast rounds
## these to whole 0.25 m voxels anyway (radius and height up, climb down), so
## the rounded values are set directly to keep the bake free of precision
## warnings.
static func _add_navigation(parent: Node3D, source: NavigationMeshSourceGeometryData3D, bounds: AABB) -> RID:
	var nm := NavigationMesh.new()
	nm.cell_size = NAV_CELL
	nm.cell_height = NAV_CELL
	nm.agent_radius = ceilf(0.45 / NAV_CELL) * NAV_CELL
	nm.agent_height = ceilf(1.8 / NAV_CELL) * NAV_CELL
	nm.agent_max_climb = floorf(0.3 / NAV_CELL) * NAV_CELL
	nm.agent_max_slope = 50.0
	nm.filter_baking_aabb = bounds.grow(1.0)
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
	# immediately. The map is static afterwards, so synchronous iterations
	# cost nothing later.
	NavigationServer3D.region_set_use_async_iterations(region.get_rid(), false)
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_force_update(map)
	return map
