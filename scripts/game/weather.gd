class_name Weather
extends Node3D
## The match's weather (`Net.config.weather`, a Data.WEATHERS id) on every peer: World's child
## "Weather", built in World._ready after the time of day, so every look below works from that
## sky (night rain stays dark). Purely cosmetic and local: nothing here goes over the network.
##
## - Atmosphere (`LOOKS`): fog density raised to the weather's floor and tinted at the scene's own
##   brightness, the sky greyed (or tinted) and dimmed, sun and ambient light dimmed. Always on,
##   whatever the "weather_fx" setting.
## - Particles: one camera-following GPUParticles3D (rain streaks, snow flakes, sand, ash) on
##   visual layer PARTICLE_LAYER, sized by the "weather_fx" setting (0 off: no particles, 1 low,
##   2 high; Video.WEATHER_FX_NAMES). A GPUParticlesCollisionHeightField3D follows the camera and
##   renders the map from above, and the particles die on contact with it, so nothing falls under
##   a roof or through a floor. Built at load (World._ready) and warmed with `preprocess`.
## - Storm: lightning every STORM_GAP seconds (sun, sky, ambient and fog flash in a double
##   flicker, FLASH_TIME long) and thunder STORM_THUNDER seconds later, quieter when farther.
## - Sound: rain and wind loops (Sfx.stream) on the "Ambience" bus (sent to SFX, so the effects
##   volume applies), faded in at the start, a few dB quieter under a roof. The node pauses with
##   the match (World.set_frozen), and the loops, particles and lightning with it.

const GROUP := &"weather"
## Visual layer 20: only the weather particles, so the roof heightfield affects nothing else.
const PARTICLE_LAYER := 1 << 19
## The heightfield around the camera (m): covers every emitter's box.
const ROOF_SIZE := Vector3(48.0, 64.0, 48.0)
## A camera jump farther than this (respawn, spectating someone else) restarts the particles there.
const JUMP_RESTART := 16.0
const STORM_GAP := Vector2(7.0, 18.0)
const STORM_THUNDER := Vector2(0.4, 2.8)
const FLASH_TIME := 0.6
## Seconds between the "under a roof" checks of the sound.
const COVER_EVERY := 0.3
## Per weather: `fog` density floor, `fog_tint` and how far the fog colour moves to it
## (`fog_mix`), the sky moved toward grey or `sky_tint` (`sky_mix`) and dimmed (`sky_dim`), sun
## and ambient light factors, `fog_sky` (how much fog covers the sky, at least) and the sound
## loops [sound, dB].
const LOOKS := {
	"rain": {"fog": 0.011, "fog_tint": Color(0.62, 0.66, 0.72), "fog_mix": 0.55, "sky_mix": 0.55,
		"sky_dim": 0.82, "sun": 0.65, "ambient": 0.9, "fog_sky": 0.35, "loops": [[&"rain_loop", 0.0]]},
	"storm": {"fog": 0.016, "fog_tint": Color(0.4, 0.43, 0.5), "fog_mix": 0.7, "sky_mix": 0.8,
		"sky_dim": 0.55, "sun": 0.38, "ambient": 0.75, "fog_sky": 0.5,
		"loops": [[&"rain_loop", 2.0], [&"wind_loop", -5.0]]},
	"snow": {"fog": 0.014, "fog_tint": Color(0.86, 0.9, 0.96), "fog_mix": 0.6, "sky_mix": 0.5,
		"sky_dim": 0.95, "sun": 0.72, "ambient": 1.0, "fog_sky": 0.4, "loops": [[&"wind_loop", -6.0]]},
	"sandstorm": {"fog": 0.028, "fog_tint": Color(0.86, 0.66, 0.4), "fog_mix": 0.85,
		"sky_tint": Color(0.82, 0.64, 0.42), "sky_mix": 0.75, "sky_dim": 0.9, "sun": 0.55,
		"ambient": 0.95, "fog_sky": 0.75, "loops": [[&"wind_loop", 3.0]]},
	"ash": {"fog": 0.014, "fog_tint": Color(0.42, 0.36, 0.33), "fog_mix": 0.45,
		"sky_tint": Color(0.38, 0.32, 0.3), "sky_mix": 0.4, "sky_dim": 0.8, "sun": 0.75,
		"ambient": 0.95, "fog_sky": 0.4, "loops": [[&"wind_loop", -9.0]]},
}
## Particle brightness per time of day (the particles are unshaded, so they follow the light by hand).
const LIGHT := {"day": 1.0, "sunset": 0.8, "night": 0.45}
## Particles per weather_fx level [low, high].
const AMOUNTS := {"rain": [1300, 3600], "storm": [1800, 5000], "snow": [1100, 3000],
	"sandstorm": [1200, 3200], "ash": [700, 1900]}

var kind := "clear"
var time_of_day := "day"
## The emitter (null when the weather is clear or "weather_fx" is off) and its roof heightfield.
var particles: GPUParticles3D
var roof: GPUParticlesCollisionHeightField3D
var _fx_level := -1
var _placed := false
var _env: Environment
var _sun: DirectionalLight3D
var _sky: ProceduralSkyMaterial
## Lightning: the lit values it flashes from.
var _base := {}
var _bolt_in := 0.0
var _flash_t := -1.0
var _thunder_in := -1.0
var _thunder_db := 0.0
## Sound loops [player, dB] and the roof check.
var _loops: Array = []
var _covered := false
var _cover_in := 0.0


## Applies `weather` to the map built under `map_root` (already lit for `tod`).
func setup(map_root: Node3D, weather: String, tod: String) -> void:
	name = "Weather"
	kind = weather if LOOKS.has(weather) else "clear"
	time_of_day = tod
	add_to_group(GROUP)
	if kind == "clear":
		set_process(false)
		return
	var envs := map_root.find_children("*", "WorldEnvironment", true, false)
	var suns := map_root.find_children("*", "DirectionalLight3D", true, false)
	if not envs.is_empty():
		_env = (envs[0] as WorldEnvironment).environment
		if _env.sky != null:
			_sky = _env.sky.sky_material as ProceduralSkyMaterial
	if not suns.is_empty():
		_sun = suns[0] as DirectionalLight3D
	_apply_look(LOOKS[kind])
	if _env != null and _sun != null:
		_base = {"sun": _sun.light_energy, "sun_color": _sun.light_color, "ambient": _env.ambient_light_energy,
			"fog": _env.fog_light_color, "sky": _sky.sky_energy_multiplier if _sky != null else 1.0}
	_bolt_in = randf_range(3.0, STORM_GAP.x)
	for loop: Array in LOOKS[kind].loops:
		_add_loop(loop[0], loop[1])
	apply_setting()


## The "weather_fx" setting changed (Video.apply calls the group): rebuilds the particles at the
## new level, or removes them when off.
func apply_setting() -> void:
	var level := int(Profile.get_setting("weather_fx"))
	if level == _fx_level or kind == "clear":
		return
	_fx_level = level
	if particles != null:
		particles.queue_free()
		roof.queue_free()
		particles = null
		roof = null
	if level > 0:
		_build_particles(level == 1)


## A short readable name of a weather for the HUD ("RAIN"; Data.WEATHERS name).
static func label(weather: String) -> String:
	return str(Data.WEATHERS.get(weather, Data.WEATHERS.clear).name).to_upper()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var pos := cam.global_position
		var jump := not _placed or global_position.distance_to(pos) > JUMP_RESTART
		global_position = pos
		_placed = true
		if jump and particles != null:
			particles.restart()
		_cover_in -= delta
		if _cover_in <= 0.0 and not _loops.is_empty():
			_cover_in = COVER_EVERY
			var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.UP * 40.0, Player.MASK_WORLD)
			_covered = not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	for loop: Array in _loops:
		var p: AudioStreamPlayer = loop[0]
		var target: float = loop[1] - (8.0 if _covered else 0.0)
		p.volume_db = move_toward(p.volume_db, target, delta * 14.0)
	if kind == "storm" and not _base.is_empty():
		_tick_storm(delta)


func _tick_storm(delta: float) -> void:
	_bolt_in -= delta
	if _bolt_in <= 0.0:
		_bolt_in = randf_range(STORM_GAP.x, STORM_GAP.y)
		_flash_t = 0.0
		_thunder_in = randf_range(STORM_THUNDER.x, STORM_THUNDER.y)
		# Farther strikes (longer delay) rumble quieter.
		_thunder_db = -4.0 * (_thunder_in - STORM_THUNDER.x)
	if _flash_t >= 0.0:
		_flash_t += delta
		if _flash_t >= FLASH_TIME:
			_flash_t = -1.0
			_flash(0.0)
		else:
			_flash(flash_curve(_flash_t))
	if _thunder_in >= 0.0:
		_thunder_in -= delta
		if _thunder_in < 0.0:
			Sfx.play(&"thunder", null, _thunder_db)


## Lightning brightness (0-1) `t` seconds into a strike: a flash, a dip, a second flash, a fade.
static func flash_curve(t: float) -> float:
	if t < 0.07:
		return 1.0
	if t < 0.14:
		return 0.2
	if t < 0.22:
		return 0.75
	return 0.75 * clampf(1.0 - (t - 0.22) / (FLASH_TIME - 0.22), 0.0, 1.0)


func _flash(f: float) -> void:
	_sun.light_energy = _base.sun + f * 2.2
	_sun.light_color = (_base.sun_color as Color).lerp(Color(0.82, 0.88, 1.0), f)
	_env.ambient_light_energy = _base.ambient + f * 1.1
	_env.fog_light_color = (_base.fog as Color).lerp(Color(0.72, 0.78, 0.9), f * 0.6)
	if _sky != null:
		_sky.sky_energy_multiplier = _base.sky * (1.0 + f * 2.5)


## Fog, sky and light for the weather, from the values the time of day left.
func _apply_look(look: Dictionary) -> void:
	if _env != null:
		_env.fog_density = maxf(_env.fog_density, look.fog)
		_env.fog_light_color = _env.fog_light_color.lerp(_at_brightness(look.fog_tint, _env.fog_light_color), look.fog_mix)
		_env.fog_sky_affect = maxf(_env.fog_sky_affect, look.fog_sky)
		_env.ambient_light_energy *= look.ambient
	if _sun != null:
		_sun.light_energy *= look.sun
	if _sky != null:
		_sky.sky_top_color = _sky_color(_sky.sky_top_color, look)
		_sky.sky_horizon_color = _sky_color(_sky.sky_horizon_color, look)
		_sky.ground_horizon_color = _sky_color(_sky.ground_horizon_color, look)
		_sky.ground_bottom_color = _sky_color(_sky.ground_bottom_color, look)


static func _sky_color(c: Color, look: Dictionary) -> Color:
	var g := c.get_luminance()
	var target: Color = _at_brightness(look.sky_tint, c) if look.has("sky_tint") else Color(g, g, g)
	var out := c.lerp(target, look.sky_mix) * float(look.sky_dim)
	out.a = 1.0
	return out


## `tint` scaled to the luminance of `like`, so a tint keeps the scene's own brightness (night).
static func _at_brightness(tint: Color, like: Color) -> Color:
	var scale := like.get_luminance() / maxf(tint.get_luminance(), 0.01)
	var out := tint * scale
	out.a = 1.0
	return out


func _add_loop(sound: StringName, db: float) -> void:
	var stream := Sfx.stream(sound)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = &"Ambience"
	p.volume_db = -40.0
	add_child(p)
	_loops.append([p, db + float(Sfx.GAIN_DB.get(sound, 0.0))])


## The loops start once the World is in the tree, each at a random point of its file.
func _ready() -> void:
	for loop: Array in _loops:
		var p: AudioStreamPlayer = loop[0]
		p.play(randf() * p.stream.get_length())


func _build_particles(low: bool) -> void:
	var light: float = LIGHT.get(time_of_day, 1.0)
	var p := GPUParticles3D.new()
	p.name = "Precipitation"
	p.amount = AMOUNTS[kind][0 if low else 1]
	p.layers = PARTICLE_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	var color := Color.WHITE
	match kind:
		"rain", "storm":
			var storm := kind == "storm"
			p.lifetime = 0.8
			pm.emission_box_extents = Vector3(20, 6, 20)
			pm.emission_shape_offset = Vector3(0, 11, 0)
			pm.direction = Vector3(0.22, -1, 0.08) if storm else Vector3(0.05, -1, 0.02)
			pm.spread = 2.0
			pm.initial_velocity_min = 26.0 if storm else 22.0
			pm.initial_velocity_max = 30.0 if storm else 25.0
			pm.gravity = Vector3.ZERO
			quad.size = Vector2(0.03, 0.9 if storm else 0.7)
			# Streaks stay upright and turn only around their length to face the camera.
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			color = Color(0.8, 0.85, 0.94, 0.45 if storm else 0.4)
		"snow":
			p.lifetime = 6.0
			p.fixed_fps = 20
			pm.emission_box_extents = Vector3(22, 6, 22)
			pm.emission_shape_offset = Vector3(0, 8, 0)
			pm.direction = Vector3(0.25, -1, 0.1)
			pm.spread = 25.0
			pm.initial_velocity_min = 1.3
			pm.initial_velocity_max = 2.0
			pm.gravity = Vector3(0, -0.15, 0)
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.angular_velocity_min = -90.0
			pm.angular_velocity_max = 90.0
			pm.scale_min = 0.6
			pm.scale_max = 1.3
			quad.size = Vector2(0.08, 0.08)
			color = Color(0.95, 0.97, 1.0, 0.9)
		"sandstorm":
			p.lifetime = 1.6
			var wind := Vector3(1.0, -0.08, 0.35).normalized()
			pm.emission_box_extents = Vector3(20, 4, 20)
			pm.emission_shape_offset = Vector3(0, 3.0, 0) - wind * 11.0
			pm.direction = wind
			pm.spread = 8.0
			pm.initial_velocity_min = 12.0
			pm.initial_velocity_max = 17.0
			pm.gravity = Vector3(0, -0.6, 0)
			pm.scale_min = 0.5
			pm.scale_max = 1.4
			quad.size = Vector2(0.09, 0.09)
			# Darker than the fog, or the grains vanish into it.
			color = Color(0.6, 0.45, 0.28, 0.8)
		"ash":
			p.lifetime = 6.0
			p.fixed_fps = 20
			pm.emission_box_extents = Vector3(22, 6, 22)
			pm.emission_shape_offset = Vector3(0, 8, 0)
			pm.direction = Vector3(0.3, -1, 0.2)
			pm.spread = 30.0
			pm.initial_velocity_min = 0.8
			pm.initial_velocity_max = 1.4
			pm.gravity = Vector3(0, -0.1, 0)
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.angular_velocity_min = -60.0
			pm.angular_velocity_max = 60.0
			pm.scale_min = 0.6
			pm.scale_max = 1.4
			quad.size = Vector2(0.07, 0.07)
			# Mostly grey flakes; one in ten still glows (HDR, so it blooms and stays lit at night).
			var ramp := Gradient.new()
			ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			ramp.set_color(0, Color(0.34 * light, 0.31 * light, 0.3 * light, 0.9))
			ramp.set_color(1, Color(0.48 * light, 0.44 * light, 0.42 * light, 0.85))
			ramp.set_offset(1, 0.5)
			ramp.add_point(0.9, Color(3.2, 1.2, 0.3, 1.0))
			var tex := GradientTexture1D.new()
			tex.gradient = ramp
			tex.use_hdr = true
			pm.color_initial_ramp = tex
	if kind != "ash":
		pm.color = Color(color.r * light, color.g * light, color.b * light, color.a)
	p.process_material = pm
	p.preprocess = p.lifetime
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	particles = p
	roof = GPUParticlesCollisionHeightField3D.new()
	roof.name = "Roofs"
	roof.size = ROOF_SIZE
	# Godot's smallest heightfield: 256 x 256 texels, about 19 cm over ROOF_SIZE.
	roof.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	roof.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	roof.follow_camera_enabled = true
	roof.cull_mask = PARTICLE_LAYER
	# Everything but the weather particles themselves (the map, and bodies, which hardly matter).
	roof.heightfield_mask = 0xFFFFF & ~PARTICLE_LAYER
	add_child(roof)
	_placed = false
