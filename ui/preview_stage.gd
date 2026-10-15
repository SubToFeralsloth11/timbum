class_name PreviewStage
extends Node3D
## A small lit "photo studio" for item previews: three-point lighting, a camera that
## frames whatever model is shown, an optional blocky pedestal, and a slow turntable.
## Lives inside a SubViewport with `own_world_3d` so it never sees the menu backdrop.

## Turntable speed in radians per second (0 = still).
var spin_speed := 0.55
var pivot: Node3D
var camera: Camera3D
var model: Node3D

var _pedestal: MeshInstance3D
var _animated := false
var _hold_spin := 0.0


func _init() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.82)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.1
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.82)
	key.light_energy = 1.5
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-38, -32, 0)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.7, 1.0)
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-15, 125, 0)
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.85, 0.55)
	rim.light_energy = 0.9
	rim.rotation_degrees = Vector3(-10, 175, 0)
	add_child(rim)

	pivot = Node3D.new()
	add_child(pivot)

	_pedestal = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.18, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.18, 0.24)
	mat.roughness = 0.9
	box.material = mat
	_pedestal.mesh = box
	_pedestal.visible = false
	pivot.add_child(_pedestal)

	camera = Camera3D.new()
	camera.fov = 30.0
	camera.current = true
	add_child(camera)


## Replaces the shown model and frames it. `pedestal` puts a block under its base.
## `yaw` is the starting turntable angle; `zoom` > 1 moves the camera closer.
func show_model(node: Node3D, pedestal := false, yaw := -0.6, zoom := 1.0) -> void:
	if model != null:
		model.queue_free()
	model = node
	pivot.rotation.y = yaw
	if node == null:
		_pedestal.visible = false
		return
	pivot.add_child(node)
	_animated = node.has_method("animate")
	var box := model_aabb(node)
	var center := box.get_center()
	node.position = -center
	var radius := maxf(box.size.length() * 0.5, 0.05)
	_pedestal.visible = pedestal
	if pedestal:
		var w := maxf(box.size.x, box.size.z) * 1.25
		_pedestal.scale = Vector3(w, 1.0, w)
		_pedestal.position = Vector3(0, box.position.y - center.y - 0.09, 0)
		radius = maxf(radius, w * 0.6)
	var dist := radius / tan(deg_to_rad(camera.fov * 0.5)) / zoom
	camera.position = Vector3(0, radius * 0.28, dist)
	camera.look_at(Vector3(0, radius * 0.02, 0))
	camera.near = maxf(0.01, dist - radius * 3.0)
	camera.far = dist + radius * 4.0


## Stops the auto spin briefly (e.g. while the user drags the model).
func nudge(yaw_delta: float) -> void:
	pivot.rotate_y(yaw_delta)
	_hold_spin = 2.0


func _process(delta: float) -> void:
	if _hold_spin > 0.0:
		_hold_spin -= delta
	else:
		pivot.rotate_y(spin_speed * delta)
	if _animated and is_instance_valid(model):
		model.call(&"animate", delta, 0.0, true, false)


## Bounding box of every visual under `root`, in `root`'s local space.
static func model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var xf: Transform3D = entry[1]
		if n is GeometryInstance3D:
			var b: AABB = xf * (n as GeometryInstance3D).get_aabb()
			if b.size != Vector3.ZERO:
				out = b if first else out.merge(b)
				first = false
		for c in n.get_children():
			if c is Node3D and (c as Node3D).visible:
				stack.append([c, xf * (c as Node3D).transform])
	return out if not first else AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
