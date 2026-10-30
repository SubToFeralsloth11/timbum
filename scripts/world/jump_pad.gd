class_name JumpPad
extends Node3D
## A glowing jump pad (MapBuilder adds one per `jump_pads` mark of a deathmatch map). Feet that
## reach the pad's disc launch the player along a designed arc: from the pad centre up to `apex_y`
## and down onto `target` (the feet position the arc lands on). The launch velocity is solved for
## the player's gravity (`velocity_for`), so the arc lands on the same spot under Low Gravity.
## The pad itself has no collision and decides nothing: the peer that simulates a player (its own
## client for the local player, the server for bots) launches it (`Player._simulate`), and every
## peer plays the effects (`play_launch`) when a player's feet enter the disc. A NavigationLink3D
## from the pad to the landing spot lets bots route through it; a landing spot with no walkable way
## down (a market awning, a tower top) also gets a one-way drop link off its edge.

## Flat distance (m) from the centre at which feet trigger the pad.
const RADIUS := 0.95
## Feet at most this far above (or 0.2 m below) the pad's surface trigger it.
const TRIGGER_HEIGHT := 0.4
## Air steering a launched player keeps (m/s, see Player.pad_flight): a nudge, not a new course.
const STEER := 1.0
const COLOR := Color(0.25, 1.0, 0.85)
## Particles thrown up by a launch, and seconds before the same pad bursts again.
const BURST_AMOUNT := 26
const BURST_GAP := 0.25
## Glowing dashes along the flight path (spacing in metres, flow speed in m/s), so a pad shows
## where it throws you.
const ARC_SPACING := 0.45
const ARC_FLOW := 1.6

## Landing spot (feet, world space) and the arc's highest point (world y).
var target := Vector3.ZERO
var apex_y := 0.0
## [from, to] feet positions of the drop link, or empty.
var drop: Array = []

var _burst: CPUParticles3D
var _light: OmniLight3D
var _last_burst := -10.0
## The flight path in local space, sampled densely, with the cumulative length at each sample.
var _arc_pts := PackedVector3Array()
var _arc_len := PackedFloat32Array()
var _arc_dots: MultiMesh
var _arc_phase := 0.0

static var _mats := {}


## Sets up a pad at `pos` (feet on its centre) landing on `p_target` with its apex `rise` metres
## above the higher of the two, and an optional drop ([from, to], world space).
func setup(pos: Vector3, p_target: Vector3, rise: float, p_drop: Array = []) -> void:
	position = pos
	target = p_target
	apex_y = maxf(pos.y, p_target.y) + rise
	drop = p_drop


## Velocity that carries feet from `from` over `apex` (world y) down to `to` under `gravity`
## (m/s², positive).
static func launch_velocity(from: Vector3, to: Vector3, apex: float, gravity: float) -> Vector3:
	var up := sqrt(2.0 * gravity * maxf(0.1, apex - from.y))
	var t := up / gravity + sqrt(2.0 * maxf(0.0, apex - to.y) / gravity)
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return flat / t + Vector3.UP * up


func velocity_for(gravity: float) -> Vector3:
	return launch_velocity(global_position, target, apex_y, gravity)


## Seconds from launch to landing under `gravity`.
func flight_time(gravity: float) -> float:
	var up := sqrt(2.0 * gravity * maxf(0.1, apex_y - global_position.y))
	return up / gravity + sqrt(2.0 * maxf(0.0, apex_y - target.y) / gravity)


func contains(feet: Vector3) -> bool:
	var c := global_position
	var dy := feet.y - c.y
	return dy <= TRIGGER_HEIGHT and dy >= -0.2 and Vector2(feet.x - c.x, feet.z - c.z).length() <= RADIUS


## The pad whose disc `feet` stand on, or null.
static func find(pads: Array, feet: Vector3) -> JumpPad:
	for pad: JumpPad in pads:
		if pad.contains(feet):
			return pad
	return null


## A player just entered the pad (every peer): particles and the launch sound (flat for the
## local player).
func play_launch(local: bool) -> void:
	Sfx.play(&"jump_pad", null if local else global_position, -2.0 if local else 0.0)
	var t := Time.get_ticks_msec() * 0.001
	if t - _last_burst < BURST_GAP:
		return
	_last_burst = t
	_burst.restart()
	_light.light_energy = 4.0


func _ready() -> void:
	# Dark metal base and a glowing rim; the dashed flight line shows the direction.
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = RADIUS - 0.05
	base_mesh.bottom_radius = RADIUS
	base_mesh.height = 0.08
	base_mesh.radial_segments = 16
	base_mesh.rings = 1
	base_mesh.material = _material("base")
	base.mesh = base_mesh
	base.position.y = 0.04
	add_child(base)
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = RADIUS - 0.12
	rim_mesh.outer_radius = RADIUS
	rim_mesh.rings = 16
	rim_mesh.ring_segments = 6
	rim_mesh.material = _material("glow")
	rim.mesh = rim_mesh
	rim.position.y = 0.08
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.light_energy = 1.2
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	_light.position.y = 0.5
	add_child(_light)
	# Motes drifting up all the time, so a pad reads from afar (and at night).
	var motes := _particles(10, 1.6, false)
	motes.direction = Vector3.UP
	motes.spread = 8.0
	motes.initial_velocity_min = 0.6
	motes.initial_velocity_max = 1.4
	motes.gravity = Vector3.ZERO
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = RADIUS - 0.1
	motes.emission_ring_inner_radius = RADIUS - 0.3
	motes.emission_ring_height = 0.0
	add_child(motes)
	_burst = _particles(BURST_AMOUNT, 0.7, true)
	_burst.direction = Vector3.UP
	_burst.spread = 25.0
	_burst.initial_velocity_min = 5.0
	_burst.initial_velocity_max = 10.0
	_burst.gravity = Vector3(0, -12.0, 0)
	_burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_burst.emission_sphere_radius = 0.6
	add_child(_burst)
	_add_link("NavLink", Vector3.ZERO, target - position)
	if drop.size() == 2:
		_add_link("DropLink", (drop[0] as Vector3) - position, (drop[1] as Vector3) - position)
	_build_arc()


## The trajectory's shape depends only on the start, apex and landing, not on gravity, so it is
## sampled with g = 1. Dots flow along it from the pad towards the landing, and a ring marks
## the landing spot.
func _build_arc() -> void:
	var v := launch_velocity(position, target, apex_y, 1.0)
	var time := flight_time(1.0)
	var total := 0.0
	var samples := 64
	for i in samples + 1:
		var t := time * float(i) / samples
		var p := v * t + Vector3.DOWN * 0.5 * t * t + Vector3.UP * 0.3
		if i > 0:
			total += p.distance_to(_arc_pts[i - 1])
		_arc_pts.append(p)
		_arc_len.append(total)
	var dot := BoxMesh.new()
	dot.size = Vector3(0.08, 0.08, 0.3)
	dot.material = _material("path")
	_arc_dots = MultiMesh.new()
	_arc_dots.transform_format = MultiMesh.TRANSFORM_3D
	_arc_dots.mesh = dot
	_arc_dots.instance_count = maxi(1, int(total / ARC_SPACING))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Arc"
	mmi.multimesh = _arc_dots
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.42
	ring_mesh.outer_radius = 0.5
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 4
	ring_mesh.material = _material("path")
	ring.mesh = ring_mesh
	ring.position = target - position + Vector3.UP * 0.06
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_place_arc_dots()


## Puts each dash at its distance along the path (shifted by the flow phase), lying along the
## path, and shrinks the dashes near both ends so the line fades in and out.
func _place_arc_dots() -> void:
	var total := _arc_len[_arc_len.size() - 1]
	var n := _arc_dots.instance_count
	for k in n:
		var d := fposmod(k * ARC_SPACING + _arc_phase, n * ARC_SPACING)
		if d > total:
			_arc_dots.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		var j := clampi(_arc_len.bsearch(d), 1, _arc_len.size() - 1)
		var seg := _arc_len[j] - _arc_len[j - 1]
		var f := 0.0 if seg <= 0.0 else (d - _arc_len[j - 1]) / seg
		var pos := _arc_pts[j - 1].lerp(_arc_pts[j], f)
		var tangent := (_arc_pts[j] - _arc_pts[j - 1]).normalized()
		var up := Vector3.RIGHT if absf(tangent.y) > 0.99 else Vector3.UP
		var s := clampf(minf(d, total - d) / 1.5, 0.25, 1.0)
		var basis := Basis.looking_at(tangent, up).scaled(Vector3.ONE * s)
		_arc_dots.set_instance_transform(k, Transform3D(basis, pos))


func _add_link(link_name: String, from: Vector3, to: Vector3) -> void:
	var link := NavigationLink3D.new()
	link.name = link_name
	link.bidirectional = false
	link.start_position = from
	link.end_position = to
	add_child(link)


func _process(delta: float) -> void:
	_light.light_energy = move_toward(_light.light_energy, 1.2, delta * 8.0)
	if _arc_dots != null:
		_arc_phase = fmod(_arc_phase + delta * ARC_FLOW, ARC_SPACING * _arc_dots.instance_count)
		_place_arc_dots()


func _particles(amount: int, life: float, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.emitting = not one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.local_coords = false
	p.position.y = 0.12
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var cube := BoxMesh.new()
	cube.size = Vector3(0.08, 0.08, 0.08)
	cube.material = _material("glow")
	p.mesh = cube
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _material(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	if kind == "base":
		m.albedo_color = Color(0.16, 0.19, 0.24)
		m.metallic = 0.6
		m.roughness = 0.35
		m.emission_enabled = true
		m.emission = COLOR.darkened(0.6)
		m.emission_energy_multiplier = 0.5
	elif kind == "path":
		# The flight line and landing ring: faint and see-through, so they guide without
		# blocking the view.
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(COLOR, 0.3)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		m.albedo_color = COLOR
		m.emission_enabled = true
		m.emission = COLOR
		m.emission_energy_multiplier = 2.5
	_mats[kind] = m
	return m
