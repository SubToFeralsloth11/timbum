class_name PingOverlay
extends CanvasLayer
## Quick ping markers (above the Hud), owned by Pings: one marker per teammate's ping where it
## is in the world (on the screen edge when off screen), labelled ENEMY or with the pinger's
## name and the distance, fading out over its last second. Compass pips come from
## Pings.compass_pips.


class MarkerLayer extends Control:
	var pings: Pings

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or pings.world.match_over:
			return
		var t := World.now()
		for e: Dictionary in pings.pings:
			var enemy := int(e.target) != 0
			var col := Palette.color("ping_enemy" if enemy else "ping_spot")
			col.a = clampf(float(e.until) - t, 0.0, 1.0)
			var who := "ENEMY" if enemy else pings.world.display_name(int(e.owner)).to_upper()
			_marker(cam, e.pos, col, who, enemy)

	func _marker(cam: Camera3D, spot: Vector3, col: Color, label: String, enemy: bool) -> void:
		var font := get_theme_default_font()
		var view := get_viewport_rect().size
		var me := cam.global_position
		var pos := spot + Vector3.UP * (1.2 if enemy else 0.6)
		var at: Vector2
		if cam.is_position_behind(pos):
			at = cam.unproject_position(me * 2.0 - pos)
			at = Vector2(view.x - at.x, view.y - 40.0)
		else:
			at = cam.unproject_position(pos)
		at = at.clamp(Vector2(40, 80), view - Vector2(40, 70))
		var outline := Color(0, 0, 0, 0.8 * col.a)
		if enemy:
			# A downward triangle over the enemy.
			var tri := PackedVector2Array([at + Vector2(-11, -14), at + Vector2(11, -14), at + Vector2(0, 4)])
			draw_colored_polygon(tri, col)
			tri.append(tri[0])
			draw_polyline(tri, outline, 2.0)
		else:
			# A pin: a ring with a dot on a short stem.
			draw_line(at + Vector2(0, -2), at + Vector2(0, 8), col, 3.0)
			draw_arc(at + Vector2(0, -10), 8.0, 0.0, TAU, 20, outline, 5.0)
			draw_arc(at + Vector2(0, -10), 8.0, 0.0, TAU, 20, col, 3.0)
			draw_circle(at + Vector2(0, -10), 3.0, col)
		var text := "%s  %dm" % [label, roundi(me.distance_to(spot))]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var tp := at + Vector2(-w * 0.5, 24)
		draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.9 * col.a))
		draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(col.lightened(0.3), col.a))

var pings: Pings
var _markers: MarkerLayer


func setup(p_pings: Pings) -> void:
	pings = p_pings


func _ready() -> void:
	layer = 11
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	_markers = MarkerLayer.new()
	_markers.pings = pings
	root.add_child(_markers)


func _process(_delta: float) -> void:
	_markers.visible = not pings.world.hud.markers_hidden()
	_markers.queue_redraw()
