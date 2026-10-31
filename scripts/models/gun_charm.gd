class_name GunCharm
extends Node3D
## A small trinket on a chain that hangs from a gun (Data.CHARMS) and sways with the gun's
## motion. The chain direction (in the gun's own space) is a damped spring pulled toward
## where gravity plus the gun's acceleration (capped) would hang it, and it never swings more
## than MAX_SWING from straight down, so fast turns, recoil, grapples and spinning draw
## animations make it sway instead of flailing. The node sits at the hanging point; its "Swing"
## child turns so the chain points along that direction.

## Chain length (gun space, metres) from the hanging point to the trinket's centre.
const LENGTH := 0.05
const GRAVITY := 9.8
## Spring stiffness (1/s^2) and damping (1/s) of the swing.
const STIFFNESS := 160.0
const DAMPING := 9.0
## How strongly the gun's acceleration (in g) tips the target, and the cap on that acceleration.
const INERTIA := 0.5
const MAX_ACCEL := 25.0
## Largest angle (radians) from hanging straight down.
const MAX_SWING := deg_to_rad(70.0)
## Anchor jumps longer than this in one frame (respawn, teleport) reset the swing.
const TELEPORT := 1.5

static var _meshes: Dictionary = {}

var charm_id := ""
var _swing: Node3D
## Chain direction and its rate of change, in this node's own (unscaled) space.
var _dir := Vector3.DOWN
var _dir_vel := Vector3.ZERO
var _prev_anchor := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _started := false


static func create(id: String) -> GunCharm:
	var c := GunCharm.new()
	c.name = "Charm"
	c.charm_id = id
	c._swing = Node3D.new()
	c._swing.name = "Swing"
	c.add_child(c._swing)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh_for(id)
	c._swing.add_child(mi)
	return c


## Shared mesh for a charm: a ring and chain from the origin down to the trinket around
## (0, -LENGTH, 0). Cached per id.
static func mesh_for(id: String) -> ArrayMesh:
	if id == "dev_core":
		return DevPack.charm_mesh(LENGTH)
	if _meshes.has(id):
		return _meshes[id]
	var spec: Dictionary = Models.CATALOG.CHARMS.get(id, Models.CATALOG.CHARMS.cube)
	var k := MeshKit.new()
	const A := 0
	const B := 1
	const CHAIN := 2
	k.box(CHAIN, Vector3(0, -0.003, 0), Vector3(0.006, 0.006, 0.006))
	for i in 3:
		k.box(CHAIN, Vector3(0, -0.01 - i * 0.009, 0), Vector3(0.0025, 0.007, 0.0025), Vector3(0, i * 1.57, 0))
	var c := Vector3(0, -LENGTH, 0)
	match str(spec.shape):
		"cube":
			k.box(A, c + Vector3(0, 0.006, 0), Vector3(0.026, 0.012, 0.026))
			k.box(B, c - Vector3(0, 0.007, 0), Vector3(0.026, 0.014, 0.026))
		"die":
			k.box(A, c, Vector3(0.026, 0.026, 0.026))
			const PIP := 0.005
			const FACE := 0.0131
			k.box(B, c + Vector3(0, 0, FACE), Vector3(PIP, PIP, 0.001))
			for s: float in [-1.0, 1.0]:
				k.box(B, c + Vector3(FACE, s * 0.006, s * 0.006), Vector3(0.001, PIP, PIP))
				k.box(B, c + Vector3(-FACE, s * 0.006, s * 0.006), Vector3(0.001, PIP, PIP))
				k.box(B, c + Vector3(-FACE, s * 0.006, -s * 0.006), Vector3(0.001, PIP, PIP))
				k.box(B, c + Vector3(s * 0.006, FACE, 0), Vector3(PIP, 0.001, PIP))
		"heart":
			k.box(A, c + Vector3(-0.007, 0.006, 0), Vector3(0.013, 0.013, 0.01))
			k.box(A, c + Vector3(0.007, 0.006, 0), Vector3(0.013, 0.013, 0.01))
			k.box(A, c + Vector3(0, -0.004, 0), Vector3(0.02, 0.012, 0.01))
			k.box(A, c + Vector3(0, -0.012, 0), Vector3(0.008, 0.008, 0.01))
			k.box(B, c + Vector3(-0.008, 0.009, 0.0052), Vector3(0.004, 0.004, 0.001))
		"duck":
			k.box(A, c + Vector3(0, -0.004, 0.002), Vector3(0.02, 0.016, 0.026))
			k.box(A, c + Vector3(0, 0.01, -0.006), Vector3(0.014, 0.014, 0.014))
			k.box(B, c + Vector3(0, 0.008, -0.016), Vector3(0.008, 0.004, 0.008))
			k.box(CHAIN, c + Vector3(0.0072, 0.013, -0.009), Vector3(0.002, 0.003, 0.003))
			k.box(CHAIN, c + Vector3(-0.0072, 0.013, -0.009), Vector3(0.002, 0.003, 0.003))
		"star":
			k.box(A, c, Vector3(0.012, 0.03, 0.007))
			k.box(A, c + Vector3(0, 0.003, 0), Vector3(0.03, 0.01, 0.007))
			k.box(A, c + Vector3(-0.007, -0.009, 0), Vector3(0.008, 0.014, 0.007), Vector3(0, 0, 0.5))
			k.box(A, c + Vector3(0.007, -0.009, 0), Vector3(0.008, 0.014, 0.007), Vector3(0, 0, -0.5))
			k.box(B, c, Vector3(0.008, 0.008, 0.008))
		"skull":
			k.box(A, c + Vector3(0, 0.003, 0), Vector3(0.024, 0.02, 0.022))
			k.box(A, c + Vector3(0, -0.01, -0.002), Vector3(0.016, 0.008, 0.016))
			k.box(B, c + Vector3(-0.005, 0.004, -0.0112), Vector3(0.006, 0.006, 0.001))
			k.box(B, c + Vector3(0.005, 0.004, -0.0112), Vector3(0.006, 0.006, 0.001))
			k.box(B, c + Vector3(0, -0.004, -0.0112), Vector3(0.003, 0.004, 0.001))
		"coin":
			k.box(A, c, Vector3(0.03, 0.03, 0.004))
			k.box(B, c, Vector3(0.022, 0.022, 0.006))
			k.box(A, c, Vector3(0.006, 0.014, 0.008))
		"ghost":
			k.box(A, c + Vector3(0, 0.004, 0), Vector3(0.024, 0.024, 0.018))
			for i in 3:
				k.box(A, c + Vector3(-0.008 + i * 0.008, -0.011, 0), Vector3(0.006, 0.006, 0.018))
			k.box(B, c + Vector3(-0.005, 0.008, -0.0092), Vector3(0.004, 0.006, 0.001))
			k.box(B, c + Vector3(0.005, 0.008, -0.0092), Vector3(0.004, 0.006, 0.001))
		"creeper":
			k.box(A, c, Vector3(0.026, 0.026, 0.026))
			k.box(B, c + Vector3(-0.0055, 0.005, -0.0131), Vector3(0.006, 0.006, 0.001))
			k.box(B, c + Vector3(0.0055, 0.005, -0.0131), Vector3(0.006, 0.006, 0.001))
			k.box(B, c + Vector3(0, -0.003, -0.0131), Vector3(0.005, 0.008, 0.001))
			k.box(B, c + Vector3(0, -0.008, -0.0131), Vector3(0.011, 0.004, 0.001))
		"gem":
			k.box(A, c + Vector3(0, 0.004, 0), Vector3(0.016, 0.016, 0.016), Vector3(0, 0.785, 0))
			k.box(A, c + Vector3(0, -0.006, 0), Vector3(0.01, 0.012, 0.01), Vector3(0, 0.785, 0.4))
			k.box(B, c + Vector3(0, 0.011, 0), Vector3(0.012, 0.004, 0.012), Vector3(0, 0.785, 0))
		"crown":
			k.box(A, c - Vector3(0, 0.004, 0), Vector3(0.026, 0.012, 0.026))
			for p: Vector3 in [Vector3(-0.0105, 0.007, -0.0105), Vector3(0.0105, 0.007, -0.0105), Vector3(-0.0105, 0.007, 0.0105), Vector3(0.0105, 0.007, 0.0105)]:
				k.box(A, c + p, Vector3(0.005, 0.01, 0.005))
			k.box(B, c + Vector3(0, -0.004, -0.0135), Vector3(0.006, 0.006, 0.002))
		_:
			k.box(A, c, Vector3(0.024, 0.024, 0.024))
	var a: Color = spec.a
	var b: Color = spec.b
	var glow := 0.6 if id == "gem" else 0.0
	_meshes[id] = k.build([
		Models.flat_material(a, 0.5, 0.3 if id in ["coin", "star", "crown"] else 0.0, glow),
		Models.flat_material(b, 0.6),
		Models.flat_material(Color(0.72, 0.74, 0.78), 0.3, 0.8),
	])
	return _meshes[id]


func _process(delta: float) -> void:
	if not is_visible_in_tree() or delta <= 0.0:
		_started = false
		return
	var gx := global_transform
	var inv := gx.basis.orthonormalized().inverse()
	var anchor := gx.origin
	var down := (inv * Vector3.DOWN).normalized()
	var dt := minf(delta, 1.0 / 30.0)
	if not _started or anchor.distance_to(_prev_anchor) > TELEPORT:
		_started = true
		_prev_anchor = anchor
		_prev_vel = Vector3.ZERO
		_dir = down
		_dir_vel = Vector3.ZERO
		_apply()
		return
	var vel := (anchor - _prev_anchor) / dt
	var accel := ((vel - _prev_vel) / dt).limit_length(MAX_ACCEL)
	_prev_anchor = anchor
	_prev_vel = vel
	# The mass lags behind the gun's acceleration, like a real pendant.
	var target := (down - inv * accel * (INERTIA / GRAVITY)).normalized()
	_dir_vel += (target - _dir) * STIFFNESS * dt
	_dir_vel *= exp(-DAMPING * dt)
	_dir = (_dir + _dir_vel * dt).normalized()
	var angle := _dir.angle_to(down)
	if angle > MAX_SWING:
		var axis := down.cross(_dir)
		if axis.length_squared() > 1e-8:
			_dir = down.rotated(axis.normalized(), MAX_SWING)
			_dir_vel *= 0.3
	_apply()


func _apply() -> void:
	if _dir.dot(Vector3.DOWN) > -0.999:
		_swing.basis = Basis(Quaternion(Vector3.DOWN, _dir))
