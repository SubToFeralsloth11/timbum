class_name MenuBackdrop
extends Node3D
## Live 3D scenery behind the main menu: builds a map a couple of frames after the UI
## appears (so the menu never shows a frozen black window) and slowly orbits it.

signal built

const MAP_ID := "village"
const ORBIT_SPEED := 0.035

var _camera: Camera3D
var _fallback_env: WorldEnvironment
var _center := Vector3.ZERO
var _radius := 40.0
var _height := 22.0
var _angle := 0.6


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.far = 400.0
	_camera.current = true
	add_child(_camera)
	# Simple sky so the first frames look intentional while the map builds.
	_fallback_env = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3b7dd8")
	sky_mat.sky_horizon_color = Color("a9d4f5")
	sky_mat.ground_horizon_color = Color("a9d4f5")
	sky_mat.ground_bottom_color = Color("3b5b3b")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	_fallback_env.environment = env
	add_child(_fallback_env)
	_update_camera()
	_build()


func _build() -> void:
	# Two frames: one to lay out the UI, one to actually present it.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var started := Time.get_ticks_msec()
	var map_root := Node3D.new()
	map_root.name = "Map"
	_fallback_env.queue_free()
	remove_child(_fallback_env)
	add_child(map_root)
	var info := MapBuilder.build(MAP_ID, map_root, 0)
	var b := info.bounds
	_center = b.get_center()
	_center.y = b.position.y + b.size.y * 0.25
	_radius = maxf(b.size.x, b.size.z) * 0.42
	_height = b.size.y * 0.35 + _radius * 0.32
	_camera.far = _radius * 6.0
	_update_camera()
	print_verbose("Menu backdrop built in %d ms" % (Time.get_ticks_msec() - started))
	built.emit()


func _process(delta: float) -> void:
	_angle += ORBIT_SPEED * delta
	_update_camera()


func _update_camera() -> void:
	var p := _center + Vector3(cos(_angle) * _radius, _height, sin(_angle) * _radius)
	_camera.position = p
	_camera.look_at(_center, Vector3.UP)
