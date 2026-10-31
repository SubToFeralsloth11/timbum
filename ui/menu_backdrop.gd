class_name MenuBackdrop
extends SubViewportContainer
## Live 3D scenery behind the main menu: part of a deathmatch map at golden hour with the
## player's avatar in the foreground (equipped outfit, hat, primary gun with its skin and charm),
## idling and now and then doing the equipped emote, drifting leaves and dust motes, and a camera
## that sways slowly around the avatar.
##
## Kept cheap: the map is built as scenery only (MapBuilder.build_scenery: block meshes of the
## chunks in front of the camera, no collision, boundary walls or navmesh) with the lowest shadow
## and sky quality, rendered into its own SubViewport (own world, no MSAA, FXAA) at the UI's base
## resolution and redrawn at most REDRAW_FPS times a second. Built a couple of frames after the
## UI appears so the menu never shows a frozen black window; freed with the menu scene when a
## match starts.

signal built

## The map shown (MapBuilder id; a deathmatch map with an open view from one of its spawns).
const MAP_ID := "snow"
## Golden hour: a low warm sun, an orange horizon and haze (keys override the map's ATMOSPHERE;
## the sun's yaw is set from the camera direction in _build).
const SUNSET := {
	"sky_top": Color("3d5f9e"), "sky_horizon": Color("f2a66a"), "ground_bottom": Color("4a3a30"),
	"sun_pitch": -11.0, "sun_color": Color("ffb36b"), "sun_energy": 1.5,
	"fog_color": Color("e9a77a"), "fog_density": 0.0055, "fog_sky": 0.3, "ambient": 0.62,
	"ambient_color": Color("b48a7c"), "exposure": 1.05, "saturation": 1.15, "sky_energy": 1.1,
}
const REDRAW_FPS := 40.0
## Camera rest distance and height from the avatar's feet; it sways SWAY radians either side.
const CAM_DISTANCE := 5.5
const CAM_HEIGHT := 0.9
const SWAY := 0.3
const SWAY_SPEED := 0.08
## Sideways camera shift (metres, negative = avatar right of centre); the menu keeps the middle clear.
const FRAME_SHIFT := 0.0
const EMOTE_EVERY := 16.0
const EMOTE_LENGTH := 4.5

var viewport: SubViewport
var avatar: Avatar
## Map to build; set before the backdrop enters the tree.
var map_id := MAP_ID

var _scene: Node3D
var _camera: Camera3D
var _fallback_env: WorldEnvironment
## Avatar feet, and the horizontal direction from it to the camera's rest position.
var _spot := Vector3.ZERO
var _out := Vector3.BACK
var _t := 0.0
var _since_draw := 1.0
var _next_emote := EMOTE_EVERY * 0.5
var _emote_end := -1.0
## The equipped look the avatar was built for (Profile.changed rebuilds it when this differs).
var _look := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	_scene = Node3D.new()
	viewport.add_child(_scene)
	_camera = Camera3D.new()
	_camera.fov = 48.0
	_camera.far = 300.0
	_camera.h_offset = FRAME_SHIFT
	_camera.current = true
	_scene.add_child(_camera)
	# Plain dusk sky so the first frames look intentional while the map builds.
	_fallback_env = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SUNSET.sky_top
	sky_mat.sky_horizon_color = SUNSET.sky_horizon
	sky_mat.ground_horizon_color = SUNSET.sky_horizon
	sky_mat.ground_bottom_color = SUNSET.ground_bottom
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	_fallback_env.environment = env
	_scene.add_child(_fallback_env)
	Profile.changed.connect(_on_profile_changed)
	_build()


func _build() -> void:
	# Two frames: one to lay out the UI, one to actually present it.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var started := Time.get_ticks_msec()
	var info := MapInfo.new()
	var grid := MapBuilder.generate(map_id, info)
	_pick_spot(grid, info)
	var cam := _spot + _out * CAM_DISTANCE
	var fwd := -_out
	var atm := SUNSET.duplicate()
	# Light from behind the camera's left shoulder, raking across the scene.
	var light := fwd.rotated(Vector3.UP, deg_to_rad(-55.0))
	atm.sun_yaw = rad_to_deg(atan2(-light.x, -light.z))
	_scene.remove_child(_fallback_env)
	_fallback_env.queue_free()
	var origin := info.bounds.position
	var half := VoxelMesher.CHUNK * 0.5
	# Only the chunks in front of the camera (with room for the sway).
	MapBuilder.build_scenery(grid, info, _scene, 0, atm, func(cx: int, cz: int) -> bool:
		var c := origin + Vector3(cx + half, 0.0, cz + half)
		return Vector3(c.x - cam.x, 0.0, c.z - cam.z).dot(fwd) > -VoxelMesher.CHUNK * 1.2)
	_build_avatar()
	_add_particles()
	_update_camera()
	print_verbose("Menu backdrop built in %d ms" % (Time.get_ticks_msec() - started))
	built.emit()


## The avatar's spot and camera direction: a spawn and one of 8 directions with open air between
## it and the camera (wherever the sway takes it, h_offset included), nothing right in front of
## the lens, clear left and right thirds of the view (no trunks or foliage filling the sides) and
## an open view past it into the map; higher spots score better.
func _pick_spot(grid: VoxelGrid, info: MapInfo) -> void:
	var center := info.bounds.get_center()
	var best := -INF
	# Half the horizontal view, as a slope (FOV 48 vertical at 16:9 is about 80 degrees across).
	var half_w := tan(deg_to_rad(40.0))
	for s: Vector3 in info.spawns:
		var inward := Vector3(s.x - center.x, 0.0, s.z - center.z)
		if inward.length() < 4.0:
			continue
		inward = inward.normalized()
		for turn in 8:
			var out := inward.rotated(Vector3.UP, turn * PI * 0.25)
			var score := s.y * 0.4 - (0.0 if turn == 0 else 1.0)
			for a: float in [-SWAY, 0.0, SWAY]:
				var dir := out.rotated(Vector3.UP, a)
				var fwd := -dir
				var right := fwd.cross(Vector3.UP)
				var cam := s + dir * CAM_DISTANCE + Vector3.UP * CAM_HEIGHT + right * FRAME_SHIFT
				var chest := s + Vector3.UP * 1.2
				for i in range(1, 11):
					for h: float in [-0.6, 0.0, 0.6]:
						if _solid(grid, info, chest.lerp(cam, i / 10.0) + Vector3.UP * h):
							score -= 10.0
				for k: float in [0.5, 1.5, 2.5, 3.5]:
					for side: float in [-2.5, -1.2, 0.0, 1.2, 2.5]:
						for h: float in [-0.5, 0.5, 1.5]:
							if _solid(grid, info, cam + fwd * k + right * side + Vector3.UP * h):
								score -= 2.0
				# The side thirds of the view, 3 to 15 m out: anything solid there frames the
				# shot with trunks and leaves.
				for k: float in [3.0, 5.0, 7.5, 10.0, 12.5, 15.0]:
					for f: float in [-0.95, -0.65, -0.4, 0.4, 0.65, 0.95]:
						for h: float in [0.0, 1.5, 3.0, 4.5, 6.0]:
							if _solid(grid, info, cam + fwd * k + right * (f * half_w * k) + Vector3.UP * h):
								score -= 0.6
			# The view past the avatar, up to tree-top height.
			for k in range(1, 14):
				for h: float in [1.8, 3.5, 5.5]:
					if _solid(grid, info, s - out * k + Vector3.UP * h):
						score -= 1.0
			if score > best:
				best = score
				_spot = s
				_out = out


func _solid(grid: VoxelGrid, info: MapInfo, p: Vector3) -> bool:
	var c := Vector3i((p - info.bounds.position).floor())
	return grid.in_bounds(c.x, c.y, c.z) and not grid.is_air(c.x, c.y, c.z)


func _look_key() -> String:
	var gun: String = Profile.loadout.primary
	return "|".join([Profile.equipped.outfit, Profile.equipped.hat, gun, Profile.gun_skin(gun),
		Profile.equipped.charm, Profile.equipped.emote])


func _on_profile_changed() -> void:
	if avatar != null and _look_key() != _look:
		_build_avatar()


## (Re)builds the avatar in the equipped look, turned a little to the camera's left.
func _build_avatar() -> void:
	if avatar != null:
		avatar.queue_free()
	_look = _look_key()
	avatar = Models.build_avatar(Profile.equipped.outfit, Profile.equipped.hat)
	avatar.charm_id = Profile.equipped.charm
	avatar.hold_weapon(Profile.loadout.primary, Profile.gun_skin(Profile.loadout.primary))
	_scene.add_child(avatar)
	avatar.position = _spot
	var face := _out.rotated(Vector3.UP, -0.3)
	avatar.rotation.y = atan2(-face.x, -face.z)
	_emote_end = -1.0
	_next_emote = _t + EMOTE_EVERY * 0.5


## Falling leaves and sunlit dust motes around the avatar.
func _add_particles() -> void:
	var leaves := _particles(36, 9.0, Vector3(4.0, 2.5, 4.0), 0.09, Vector3(0.25, -0.35, 0.1))
	var ramp := Gradient.new()
	ramp.set_color(0, Color("e0782a"))
	ramp.set_color(1, Color("b9c43f"))
	ramp.add_point(0.5, Color("f0b03a"))
	leaves.color_initial_ramp = ramp
	leaves.angular_velocity_min = -120.0
	leaves.angular_velocity_max = 120.0
	leaves.angle_max = 360.0
	# Kept a few metres behind the avatar so no leaf drifts right past the lens.
	leaves.position = _spot + Vector3.UP * 3.0 - _out * 3.0
	var dust := _particles(48, 7.0, Vector3(4.0, 2.0, 4.0), 0.035, Vector3(0.05, 0.03, 0.0))
	dust.color = Color(1.0, 0.86, 0.6, 0.7)
	dust.position = _spot + Vector3.UP * 1.8 - _out * 2.5


func _particles(amount: int, lifetime: float, extents: Vector3, size: float, drift: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.DOWN
	p.spread = 180.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.gravity = drift
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	p.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color.WHITE)
	fade.add_point(0.85, Color.WHITE)
	p.color_ramp = fade
	_scene.add_child(p)
	return p


func _process(delta: float) -> void:
	_t += delta
	if avatar != null:
		# Breathing: the aim drifts a little (an emote poses the whole body itself).
		if avatar.emote.is_empty():
			avatar.set_look_pitch(sin(_t * 1.3) * 0.04 - 0.05)
		if _emote_end > 0.0 and _t >= _emote_end:
			avatar.stop_emote()
			_emote_end = -1.0
			_next_emote = _t + EMOTE_EVERY
		elif _emote_end < 0.0 and _t >= _next_emote:
			avatar.play_emote(Profile.equipped.emote)
			_emote_end = _t + EMOTE_LENGTH
	_update_camera()
	_since_draw += delta
	if _since_draw >= 1.0 / REDRAW_FPS:
		_since_draw = 0.0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _update_camera() -> void:
	var dir := _out.rotated(Vector3.UP, sin(_t * SWAY_SPEED) * SWAY)
	_camera.position = _spot + dir * CAM_DISTANCE + Vector3.UP * (CAM_HEIGHT + sin(_t * 0.13) * 0.12)
	_camera.look_at(_spot + Vector3.UP * 1.4, Vector3.UP)
