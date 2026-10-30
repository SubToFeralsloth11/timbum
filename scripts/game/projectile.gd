class_name Projectile
extends Node3D
## A rocket, frag grenade or tactical grenade (smoke/flash). Every peer simulates the same
## deterministic flight for visuals; only the server decides when and where it goes off
## (World.server_explode). Rockets and frags explode on contact; tacticals bounce until their fuse.

const GRENADE_GRAVITY := 18.0
const GRENADE_BOUNCE := 0.42
const GRENADE_FRICTION := 0.75
const ROCKET_MAX_LIFE := 6.0
## Clients hide a projectile that hit something; this frees it if the server's explode never arrives.
const ORPHAN_TIMEOUT := 2.0
## Players launch projectiles ~0.5-0.6 m ahead of the eye, which can be inside a wall they are
## hugging. The first step's sweep starts this far back along the flight path (near the eye).
const LAUNCH_BACKTRACK := 0.6

var world: World
var pid := 0
var kind := "rocket"
var owner_id := 0
var vel := Vector3.ZERO
var age := 0.0
var _stopped := false
var _stopped_for := 0.0
var _model: Node3D
var _trail: CPUParticles3D
var _bounce_sound_cd := 0.0
var _first_step := true


func setup(p_world: World, p_pid: int, p_kind: String, p_owner: int, origin: Vector3, velocity: Vector3) -> void:
	world = p_world
	pid = p_pid
	kind = p_kind
	owner_id = p_owner
	vel = velocity
	position = origin
	name = "Projectile%d" % pid


func _ready() -> void:
	match kind:
		"rocket": _model = Models.build_rocket()
		"grenade": _model = Models.build_grenade()
		_: _model = Models.build_tactical(kind)
	add_child(_model)
	_orient()
	if kind == "rocket":
		_trail = CPUParticles3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 0.18
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		cube.material = mat
		_trail.mesh = cube
		_trail.amount = 40
		_trail.lifetime = 0.7
		_trail.local_coords = false
		_trail.direction = Vector3.ZERO
		_trail.spread = 180.0
		_trail.initial_velocity_max = 0.6
		_trail.gravity = Vector3(0.0, 0.8, 0.0)
		_trail.color = Color(0.75, 0.75, 0.75)
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.6))
		curve.add_point(Vector2(1.0, 1.4))
		_trail.scale_amount_curve = curve
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_trail)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.6, 0.25)
		glow.omni_range = 4.0
		glow.light_energy = 1.5
		add_child(glow)


## False once it has hit something and waits (hidden) for the server's explosion.
func in_flight() -> bool:
	return not _stopped


func _orient() -> void:
	if kind == "rocket" and vel.length_squared() > 0.01:
		var dir := vel.normalized()
		_model.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	if _stopped:
		_stopped_for += delta
		if _stopped_for > ORPHAN_TIMEOUT and not multiplayer.is_server():
			world.projectiles.erase(pid)
			queue_free()
		return
	age += delta
	_bounce_sound_cd -= delta
	var space := get_world_3d().direct_space_state
	if kind == "rocket":
		_step_rocket(delta, space)
	elif kind == "grenade":
		_step_grenade(delta, space)
	else:
		_step_tactical(delta, space)


func _step_rocket(delta: float, space: PhysicsDirectSpaceState3D) -> void:
	var from := _sweep_start()
	var to := global_position + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, Player.MASK_WORLD | Player.MASK_HITBOX, _owner_exclude())
	q.collide_with_areas = true
	var r := space.intersect_ray(q)
	if not r.is_empty():
		_detonate(r.position - vel.normalized() * 0.15)
		return
	global_position = to
	if age > ROCKET_MAX_LIFE:
		_detonate(global_position)


func _step_grenade(delta: float, space: PhysicsDirectSpaceState3D) -> void:
	vel.y -= GRENADE_GRAVITY * delta
	var from := _sweep_start()
	var to := global_position + vel * delta
	# Frags go off on the first thing they touch: a wall, the floor or another player.
	var q := PhysicsRayQueryParameters3D.create(from, to, Player.MASK_WORLD | Player.MASK_HITBOX, _owner_exclude())
	q.collide_with_areas = true
	var r := space.intersect_ray(q)
	if not r.is_empty():
		var n: Vector3 = r.normal if not (r.collider is Area3D) else -vel.normalized()
		_detonate(r.position + n * 0.15)
		return
	global_position = to
	_model.rotate_x(delta * vel.length() * 2.0)
	if age >= float(Data.GRENADE.fuse):
		_detonate(global_position)


## Smoke and flash grenades bounce off the world and go off when their fuse runs out.
func _step_tactical(delta: float, space: PhysicsDirectSpaceState3D) -> void:
	vel.y -= GRENADE_GRAVITY * delta
	var from := _sweep_start()
	var to := global_position + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, Player.MASK_WORLD)
	var r := space.intersect_ray(q)
	if r.is_empty():
		global_position = to
	else:
		var n: Vector3 = r.normal
		global_position = r.position + n * 0.06
		vel = vel.bounce(n) * GRENADE_BOUNCE
		if n.y > 0.6:
			vel.x *= GRENADE_FRICTION
			vel.z *= GRENADE_FRICTION
		if vel.length() > 1.5 and _bounce_sound_cd <= 0.0:
			_bounce_sound_cd = 0.15
			Sfx.play(&"grenade_bounce", global_position, -4.0)
	_model.rotate_x(delta * vel.length() * 2.0)
	if age >= float(Data.TACTICALS[kind].fuse):
		_detonate(global_position + Vector3.UP * 0.1)


func _owner_exclude() -> Array[RID]:
	var owner_player: Player = world.entities.get(owner_id)
	if owner_player != null:
		return owner_player.exclude_rids()
	return []


## Where this step's collision sweep starts: the current position, except on the first step.
func _sweep_start() -> Vector3:
	if not _first_step:
		return global_position
	_first_step = false
	if vel.length_squared() < 0.0001:
		return global_position
	return global_position - vel.normalized() * LAUNCH_BACKTRACK


func _detonate(pos: Vector3) -> void:
	global_position = pos
	if multiplayer.is_server():
		world.server_explode(self, pos)
	else:
		_stopped = true
		visible = false
