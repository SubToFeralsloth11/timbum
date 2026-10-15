class_name ModelPreview
extends SubViewportContainer
## Interactive 3D item preview: a transparent SubViewport with its own world holding a
## PreviewStage. Drag with the mouse to turn the model.

var stage: PreviewStage
var viewport: SubViewport


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	stage = PreviewStage.new()
	viewport.add_child(stage)
	resized.connect(func() -> void: stage.reframe.call_deferred())


func show_model(node: Node3D, pedestal := false, yaw := -0.6, zoom := 1.0) -> void:
	stage.show_model(node, pedestal, yaw, zoom)


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		stage.nudge(motion.relative.x * 0.012)
		accept_event()
