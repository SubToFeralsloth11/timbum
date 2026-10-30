class_name GunCharm
extends Node3D
## A small trinket on a chain that hangs from a gun (Data.CHARMS) and swings with the gun's
## motion: the trinket is a point mass on a rigid rod (Verlet), pulled by world gravity, so
## turning, firing, reloading and draw animations all set it swinging. The node sits at the
## hanging point; its "Swing" child turns so the chain points from there to the mass.

## Chain length (gun space, metres) from the hanging point to the trinket's centre.
const LENGTH := 0.05
const GRAVITY := 9.8
## Fraction of the velocity kept per 1/60 s; lower settles faster.
const DAMPING := 0.94

static var _meshes: Dictionary = {}

var charm_id := ""
var _swing: Node3D
var _tip := Vector3.ZERO
var _prev_tip := Vector3.ZERO
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


func _ready() -> void:
	_started = false


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_started = false
		return
	var gx := global_transform
	var anchor := gx.origin
	var length := LENGTH * gx.basis.get_scale().y
	if not _started or length <= 0.0:
		_tip = anchor + Vector3.DOWN * length
		_prev_tip = _tip
		_started = true
	var dt := minf(delta, 1.0 / 30.0)
	var keep := pow(DAMPING, dt * 60.0)
	var vel := (_tip - _prev_tip) * keep
	_prev_tip = _tip
	_tip += vel + Vector3.DOWN * GRAVITY * dt * dt
	var rod := _tip - anchor
	if rod.length_squared() < 1e-10:
		rod = Vector3.DOWN * length
	_tip = anchor + rod.normalized() * length
	# Point the chain (local -Y) at the mass, in this node's own space.
	var local_dir := (gx.basis.inverse() * (_tip - anchor)).normalized()
	if local_dir.dot(Vector3.DOWN) > -0.999:
		_swing.basis = Basis(Quaternion(Vector3.DOWN, local_dir))
