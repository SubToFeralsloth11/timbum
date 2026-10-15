class_name Projectile
extends Node3D
## A rocket or grenade. Every peer simulates the same deterministic flight for visuals;
## only the server decides when and where it explodes (World.server_explode).

const GRENADE_GRAVITY := 18.0
const GRENADE_BOUNCE := 0.42
const GRENADE_FRICTION := 0.75
const ROCKET_MAX_LIFE := 6.0
## Clients hide a projectile that hit something; this frees it if the server's explode never arrives.
const ORPHAN_TIMEOUT := 2.0

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


func setup(p_world: World, p_pid: int, p_kind: String, p_owner: int, origin: Vector3, velocity: Vector3) -> void:
	world = p_world
	pid = p_pid
	kind = p_kind
	owner_id = p_owner
	vel = velocity
	position = origin
	name = "Projectile%d" % pid


func _ready() -> void:
	_model = Models.build_rocket() if kind == "rocket" else Models.build_grenade()
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
	else:
		_step_grenade(delta, space)


func _step_rocket(delta: float, space: PhysicsDirectSpaceState3D) -> void:
	var from := global_position
	var to := from + vel * delta
	var exclude: Array[RID] = []
	var owner_player: Player = world.entities.get(owner_id)
	if owner_player != null:
		exclude = owner_player.exclude_rids()
	var q := PhysicsRayQueryParameters3D.create(from, to, Player.MASK_WORLD | Player.MASK_HITBOX, exclude)
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
	var from := global_position
	var to := from + vel * delta
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
	if age >= float(Data.GRENADE.fuse):
		_detonate(global_position + Vector3.UP * 0.1)


func _detonate(pos: Vector3) -> void:
	global_position = pos
	if multiplayer.is_server():
		world.server_explode(self, pos)
	else:
		_stopped = true
		visible = false
