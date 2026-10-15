class_name Thumbnailer
extends Node
## Renders item icons off-screen, one per frame, and caches them for the whole session.
## Usage: add a Thumbnailer to the tree, then `request(key, builder, on_ready)` where
## `builder` returns a fresh Node3D and `on_ready(texture)` receives the icon.

## Wide icons suit guns; tall items are simply height-limited.
const SIZE := Vector2i(256, 128)

static var _cache := {}

var _viewport: SubViewport
var _stage: PreviewStage
var _queue: Array[Dictionary] = []
var _busy := false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = PreviewStage.new()
	_stage.spin_speed = 0.0
	_viewport.add_child(_stage)


static func cached(key: String) -> Texture2D:
	return _cache.get(key)


## `yaw` turns the model before the shot (see PreviewStage.show_model).
func request(key: String, builder: Callable, on_ready: Callable, yaw := -0.75) -> void:
	if _cache.has(key):
		on_ready.call(_cache[key])
		return
	for job in _queue:
		if job.key == key:
			job.callbacks.append(on_ready)
			return
	_queue.append({"key": key, "builder": builder, "callbacks": [on_ready], "yaw": yaw})


func _process(_delta: float) -> void:
	if _busy or _queue.is_empty():
		return
	_render(_queue.pop_front())


func _render(job: Dictionary) -> void:
	_busy = true
	var node: Node3D = job.builder.call()
	_stage.show_model(node, false, job.yaw, 1.0)
	await get_tree().process_frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var tex := ImageTexture.create_from_image(_viewport.get_texture().get_image())
	_cache[job.key] = tex
	for cb: Callable in job.callbacks:
		if cb.is_valid():
			cb.call(tex)
	_busy = false
