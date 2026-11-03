class_name FlagOverlay
extends CanvasLayer
## Capture the Flag's HUD layer (above the Hud): a marker on each flag, drawn through walls (on the
## screen edge when it is off screen) with what to do about it and its distance (TAKE, DEFEND,
## ESCORT, KILL CARRIER, RETURN with the seconds left on a dropped flag), a CAPTURE marker on your
## own stand while you carry the enemy flag, and the carrier banner at the bottom. The flags' states
## also show in the Hud's score card (CaptureTheFlag.hud_team_status) and as compass pips
## (CaptureTheFlag.compass_pips).

## Draws the markers where the flags are in the world.
class MarkerLayer extends Control:
	var ctf: CaptureTheFlag

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		var w := ctf.world
		if cam == null or w.match_over or ctf.stands.size() < 2:
			return
		var me := w.local_player
		var mine := Teams.of(me)
		var carrying := ctf.carried_by(me)
		for f in 2:
			if carrying == f:
				continue
			var state: int = ctf.flag_state[f]
			var label := ""
			if mine < 0:
				label = ["HOME", "TAKEN", "DROPPED %ds" % ceili(ctf.return_in(f))][state]
				label = "%s FLAG  %s" % [Teams.shape(f), label]
			elif f == mine:
				label = ["DEFEND", "KILL CARRIER", "RETURN  %ds" % ceili(ctf.return_in(f))][state]
			else:
				label = ["TAKE", "ESCORT", "TAKE  %ds" % ceili(ctf.return_in(f))][state]
			var height := 2.9 if state == CaptureTheFlag.State.CARRIED else 2.6
			_marker(cam, ctf.flag_world_pos(f), height, Teams.color(f), label, state != CaptureTheFlag.State.HOME)
		if carrying >= 0 and mine >= 0:
			var home: bool = ctf.flag_state[mine] == CaptureTheFlag.State.HOME
			_marker(cam, ctf.stands[mine], 1.2, Color(1, 0.85, 0.35), "CAPTURE" if home else "WAIT  ·  YOUR FLAG IS GONE", true)

	func _marker(cam: Camera3D, feet: Vector3, height: float, col: Color, label: String, pulse: bool) -> void:
		var font := get_theme_default_font()
		var view := get_viewport_rect().size
		var me := cam.global_position
		var at := UIKit.marker_point(cam, feet + Vector3.UP * height, view).clamp(Vector2(40, 80), view - Vector2(40, 70))
		var a := 0.65 + 0.35 * sin(World.now() * 7.0) if pulse else 1.0
		# A little flag: pole and pennant, outlined.
		var pole_top := at + Vector2(-7, -14)
		var pole_bottom := at + Vector2(-7, 12)
		var pennant := PackedVector2Array([pole_top, pole_top + Vector2(18, 6), pole_top + Vector2(0, 13)])
		draw_line(pole_top, pole_bottom, Color(0, 0, 0, 0.85), 5.0)
		draw_colored_polygon(pennant, Color(0, 0, 0, 0.85))
		draw_polyline(PackedVector2Array([pennant[0], pennant[1], pennant[2], pennant[0]]), Color(0, 0, 0, 0.85), 4.0)
		draw_line(pole_top, pole_bottom, Color(0.92, 0.92, 0.95, a), 2.5)
		draw_colored_polygon(pennant, Color(col, a))
		var text := "%s  %dm" % [label, roundi(Vector2(feet.x - me.x, feet.z - me.z).length())]
		var size := 15
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var tp := at + Vector2(-w * 0.5, 32)
		draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.9))
		draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col.lightened(0.35))

var ctf: CaptureTheFlag
var _markers: MarkerLayer
var _banner: PanelContainer
var _banner_title: Label
var _banner_line: Label


func setup(p_ctf: CaptureTheFlag) -> void:
	ctf = p_ctf


func _ready() -> void:
	layer = 11
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	_markers = MarkerLayer.new()
	_markers.ctf = ctf
	root.add_child(_markers)
	# The carrier banner: bottom centre, above the weapon and health cards.
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", UITheme.hud_card(0.55, 10, UITheme.CARD_RADIUS, Color(1, 0.85, 0.35, 0.6)))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_banner.offset_bottom = -150
	_banner.visible = false
	root.add_child(_banner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_banner.add_child(v)
	_banner_title = _label("", 20, Color(1, 0.88, 0.45))
	v.add_child(_banner_title)
	_banner_line = _label("Slower while carrying  ·  no grapple", 14, Color(0.85, 0.88, 0.95))
	v.add_child(_banner_line)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	var w := ctf.world
	var hidden := w.hud.markers_hidden() or w.killcam.is_playing()
	_markers.visible = not hidden
	_markers.queue_redraw()
	var me := w.local_player
	var carrying := ctf.carried_by(me) >= 0 and me.alive and not w.match_over
	_banner.visible = carrying and not hidden
	if _banner.visible:
		var mine := Teams.of(me)
		var home: bool = mine >= 0 and ctf.flag_state[mine] == CaptureTheFlag.State.HOME
		_banner_title.text = "YOU HAVE THE FLAG  ·  RUN IT HOME" if home else "YOU HAVE THE FLAG  ·  GET YOUR OWN FLAG BACK TO SCORE"
