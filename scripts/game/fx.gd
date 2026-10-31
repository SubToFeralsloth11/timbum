class_name Fx
extends Node3D
## Pooled combat effects: tracers, impact debris, bullet holes, blood cubes, muzzle flashes,
## explosions and death bursts. Every pool is a fixed-size ring so nothing allocates mid-fight.

const TRACER_POOL := 32
const IMPACT_POOL := 20
const DECAL_POOL := 64
const BLOOD_POOL := 12
const FLASH_POOL := 8
## A Block Bomber (Streaks) sets off five explosions within a second.
const EXPLOSION_POOL := 8
const BURST_POOL := 6
const TRACER_LIFE := 0.07
const SMOKE_POOL := 4
const SMOKE_PUFFS := 22
## Seconds a smoke cloud takes to billow out to full size, and to thin away at the end.
const SMOKE_GROW := 1.2
const SMOKE_FADE := 1.6
const FLASH_BURST_LIFE := 0.45
## Demolition: concurrent block-debris bursts (made on first use), and chunks per burst.
const BLOCK_DEBRIS_POOL := 4
const BLOCK_DEBRIS_AMOUNT := 48

## Soft billboarded smoke puff: value-noise blob with a round falloff; `fade` per instance.
const SMOKE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;
uniform vec3 tint : source_color = vec3(0.72, 0.73, 0.75);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void vertex() {
	// Face the camera, keeping the node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float n = vnoise(UV * 4.0 + seed + TIME * 0.15) * 0.6 + vnoise(UV * 9.0 - seed - TIME * 0.1) * 0.4;
	float a = smoothstep(1.0, 0.35, r + (n - 0.5) * 0.5);
	ALBEDO = tint * (0.8 + 0.25 * n) * (0.85 + 0.15 * (1.0 - UV.y));
	ALPHA = clamp(a * 0.95 * fade, 0.0, 1.0);
}
"""

var _tracers: Array[MeshInstance3D] = []
var _tracer_life: Array[float] = []
var _impacts: Array[CPUParticles3D] = []
var _decals: Array[Decal] = []
var _blood: Array[CPUParticles3D] = []
var _flashes: Array[OmniLight3D] = []
var _flash_life: Array[float] = []
var _explosions: Array[Node3D] = []
var _explosion_life: Array[float] = []
var _bursts: Array[CPUParticles3D] = []
var _i_tracer := 0
var _i_impact := 0
var _i_decal := 0
var _i_blood := 0
var _i_flash := 0
var _i_explosion := 0
var _i_burst := 0
var _tracer_mat: StandardMaterial3D
var _smokes: Array[Node3D] = []
## Per smoke cloud: [seconds since it popped, total duration]; duration 0 = idle.
var _smoke_time: Array[Vector2] = []
var _i_smoke := 0
var _flash_burst: OmniLight3D
var _flash_burst_life := 0.0
var _block_debris: Array[CPUParticles3D] = []
var _i_block_debris := 0


func _ready() -> void:
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.45, 0.85)
	_tracer_mat.disable_receive_shadows = true
	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.025, 0.025, 1.0)
	for i in TRACER_POOL:
		var t := MeshInstance3D.new()
		t.mesh = tracer_mesh
		t.material_override = _tracer_mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		add_child(t)
		_tracers.append(t)
		_tracer_life.append(0.0)

	var dust_mat := _cube_material(true)
	for i in IMPACT_POOL:
		_impacts.append(_make_particles(10, 0.35, 0.06, dust_mat, Color(0.55, 0.5, 0.45), 3.5, 9.0))
	var blood_mat := _cube_material(true)
	for i in BLOOD_POOL:
		_blood.append(_make_particles(14, 0.45, 0.07, blood_mat, Color(0.75, 0.05, 0.05), 3.0, 12.0))
	var burst_mat := _cube_material(true)
	for i in BURST_POOL:
		_bursts.append(_make_particles(28, 0.9, 0.12, burst_mat, Color.WHITE, 5.0, 14.0))

	var hole := _bullet_hole_texture()
	for i in DECAL_POOL:
		var d := Decal.new()
		d.texture_albedo = hole
		d.size = Vector3(0.14, 0.2, 0.14)
		d.cull_mask = 1
		d.upper_fade = 0.0
		d.lower_fade = 0.0
		d.visible = false
		add_child(d)
		_decals.append(d)

	for i in FLASH_POOL:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.35)
		l.omni_range = 4.0
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		_flashes.append(l)
		_flash_life.append(0.0)

	var fire_mat := _cube_material(false)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.55, 0.15)
	fire_mat.emission_energy_multiplier = 4.0
	var smoke_mat := _cube_material(true)
	for i in EXPLOSION_POOL:
		var root := Node3D.new()
		root.visible = false
		add_child(root)
		var fire := _make_particles(40, 0.45, 0.35, fire_mat, Color(1.0, 0.6, 0.2), 7.0, 2.0)
		fire.reparent(root)
		fire.name = "Fire"
		var smoke := _make_particles(26, 1.6, 0.5, smoke_mat, Color(0.25, 0.24, 0.23), 3.5, -1.5)
		smoke.reparent(root)
		smoke.name = "Smoke"
		var debris := _make_particles(24, 1.1, 0.12, _cube_material(true), Color(0.4, 0.35, 0.3), 9.0, 16.0)
		debris.reparent(root)
		debris.name = "Debris"
		var light := OmniLight3D.new()
		light.name = "Light"
		light.light_color = Color(1.0, 0.6, 0.25)
		light.omni_range = 12.0
		light.light_energy = 0.0
		root.add_child(light)
		_explosions.append(root)
		_explosion_life.append(0.0)

	var smoke_shader := Shader.new()
	smoke_shader.code = SMOKE_SHADER
	var smoke_puff_mat := ShaderMaterial.new()
	smoke_puff_mat.shader = smoke_shader
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = smoke_puff_mat
	for i in SMOKE_POOL:
		var cloud := Node3D.new()
		cloud.visible = false
		add_child(cloud)
		for j in SMOKE_PUFFS:
			var puff := MeshInstance3D.new()
			puff.mesh = quad
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			puff.set_instance_shader_parameter(&"seed", float(j) * 3.7 + i * 11.0)
			cloud.add_child(puff)
		_smokes.append(cloud)
		_smoke_time.append(Vector2.ZERO)
	_flash_burst = OmniLight3D.new()
	_flash_burst.light_color = Color(0.95, 0.97, 1.0)
	_flash_burst.omni_range = 18.0
	_flash_burst.light_energy = 0.0
	_flash_burst.visible = false
	add_child(_flash_burst)


func _cube_material(vertex_color: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = vertex_color
	m.roughness = 0.9
	return m


func _make_particles(amount: int, life: float, size: float, mat: Material, color: Color, speed: float, gravity: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * size
	cube.material = mat
	p.mesh = cube
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.color = color
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _bullet_hole_texture() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 8:
		for x in 8:
			var d := Vector2(x - 3.5, y - 3.5).length()
			if d < 2.0:
				img.set_pixel(x, y, Color(0.04, 0.04, 0.04, 0.95))
			elif d < 3.4:
				img.set_pixel(x, y, Color(0.12, 0.11, 0.1, 0.55))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	for i in TRACER_POOL:
		if _tracer_life[i] > 0.0:
			_tracer_life[i] -= delta
			if _tracer_life[i] <= 0.0:
				_tracers[i].visible = false
	for i in FLASH_POOL:
		if _flash_life[i] > 0.0:
			_flash_life[i] -= delta
			_flashes[i].light_energy = maxf(0.0, _flash_life[i] / 0.06) * 2.5
			if _flash_life[i] <= 0.0:
				_flashes[i].visible = false
	for i in EXPLOSION_POOL:
		if _explosion_life[i] > 0.0:
			_explosion_life[i] -= delta
			var light := _explosions[i].get_node("Light") as OmniLight3D
			light.light_energy = maxf(0.0, (_explosion_life[i] - 1.2) / 0.4) * 9.0
			if _explosion_life[i] <= 0.0:
				_explosions[i].visible = false
	for i in SMOKE_POOL:
		if _smoke_time[i].y > 0.0:
			_update_smoke(i, delta)
	if _flash_burst_life > 0.0:
		_flash_burst_life -= delta
		_flash_burst.light_energy = maxf(0.0, _flash_burst_life / FLASH_BURST_LIFE) * 16.0
		if _flash_burst_life <= 0.0:
			_flash_burst.visible = false


func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var t := _tracers[_i_tracer]
	_tracer_life[_i_tracer] = TRACER_LIFE
	_i_tracer = (_i_tracer + 1) % TRACER_POOL
	# Draw only a streak near the start so it reads as a moving bullet, not a laser.
	var streak := minf(length, 6.0)
	var dir := (to - from) / length
	var mid := from + dir * minf(length * 0.5, 2.0 + streak * 0.5)
	t.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT), mid)
	t.scale = Vector3(1.0, 1.0, streak)
	t.visible = true


func impact(pos: Vector3, normal: Vector3) -> void:
	var p := _impacts[_i_impact]
	_i_impact = (_i_impact + 1) % IMPACT_POOL
	p.global_position = pos + normal * 0.02
	p.direction = normal
	p.restart()
	var d := _decals[_i_decal]
	_i_decal = (_i_decal + 1) % DECAL_POOL
	var up := normal
	var side := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := side.cross(up).normalized()
	var z := x.cross(up).normalized()
	d.global_transform = Transform3D(Basis(x, up, z).rotated(up, randf() * TAU), pos)
	d.visible = true


func blood(pos: Vector3) -> void:
	var p := _blood[_i_blood]
	_i_blood = (_i_blood + 1) % BLOOD_POOL
	p.global_position = pos
	p.restart()


func muzzle_flash(pos: Vector3) -> void:
	var l := _flashes[_i_flash]
	_flash_life[_i_flash] = 0.06
	_i_flash = (_i_flash + 1) % FLASH_POOL
	l.global_position = pos
	l.visible = true
	l.light_energy = 2.5


func explosion(pos: Vector3) -> void:
	var root := _explosions[_i_explosion]
	_explosion_life[_i_explosion] = 1.6
	_i_explosion = (_i_explosion + 1) % EXPLOSION_POOL
	root.global_position = pos
	root.visible = true
	for child_name in ["Fire", "Smoke", "Debris"]:
		(root.get_node(child_name) as CPUParticles3D).restart()


func death_burst(pos: Vector3, color: Color) -> void:
	var p := _bursts[_i_burst]
	_i_burst = (_i_burst + 1) % BURST_POOL
	p.global_position = pos
	p.color = color
	p.restart()


## Demolition: chunky cubes in the removed blocks' `colors` burst out of the box `center` +-
## `extents` (the removed cells) and tumble down.
func block_debris(center: Vector3, extents: Vector3, colors: PackedColorArray) -> void:
	if colors.is_empty():
		return
	if _block_debris.is_empty():
		var mat := _cube_material(true)
		for i in BLOCK_DEBRIS_POOL:
			var made := _make_particles(BLOCK_DEBRIS_AMOUNT, 1.6, 0.26, mat, Color.WHITE, 8.0, 18.0)
			made.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			made.spread = 85.0
			_block_debris.append(made)
	var p := _block_debris[_i_block_debris]
	_i_block_debris = (_i_block_debris + 1) % BLOCK_DEBRIS_POOL
	# Each chunk picks one of the colours at random (constant-step gradient).
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / colors.size())
	ramp.offsets = offsets
	ramp.colors = colors
	p.color_initial_ramp = ramp
	p.emission_box_extents = extents
	p.global_position = center
	p.restart()


## A smoke grenade's cloud: puffs billow out from `pos` to `radius` over SMOKE_GROW seconds,
## hold, then thin away over the last SMOKE_FADE of `duration`.
func smoke_cloud(pos: Vector3, radius: float, duration: float) -> void:
	var cloud := _smokes[_i_smoke]
	_smoke_time[_i_smoke] = Vector2(0.0, duration)
	_i_smoke = (_i_smoke + 1) % SMOKE_POOL
	cloud.global_position = pos
	cloud.visible = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos)
	for puff: MeshInstance3D in cloud.get_children():
		# Spread through a squashed sphere sitting on the ground; remember the target offset.
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		var offset := dir * radius * sqrt(rng.randf()) * Vector3(1.0, 0.55, 1.0) + Vector3.UP * radius * 0.35
		puff.set_meta(&"offset", offset)
		puff.set_meta(&"size", radius * rng.randf_range(0.75, 1.15))
		puff.position = Vector3.ZERO
		puff.scale = Vector3.ONE * 0.1


func _update_smoke(i: int, delta: float) -> void:
	var t := _smoke_time[i]
	t.x += delta
	_smoke_time[i] = t
	var cloud := _smokes[i]
	if t.x >= t.y:
		_smoke_time[i] = Vector2.ZERO
		cloud.visible = false
		return
	var grow := 1.0 - pow(1.0 - clampf(t.x / SMOKE_GROW, 0.0, 1.0), 3.0)
	var fade := clampf((t.y - t.x) / SMOKE_FADE, 0.0, 1.0)
	for puff: MeshInstance3D in cloud.get_children():
		var offset: Vector3 = puff.get_meta(&"offset")
		# Drifts upward a little as it thins.
		puff.position = offset * grow + Vector3.UP * (1.0 - fade) * 0.6
		puff.scale = Vector3.ONE * float(puff.get_meta(&"size")) * (0.25 + 0.75 * grow) * (1.0 + (1.0 - fade) * 0.3)
		puff.set_instance_shader_parameter(&"fade", fade)


func flash_burst(pos: Vector3) -> void:
	_flash_burst.global_position = pos + Vector3.UP * 0.3
	_flash_burst.visible = true
	_flash_burst.light_energy = 16.0
	_flash_burst_life = FLASH_BURST_LIFE
