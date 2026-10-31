class_name ZoneOverlay
extends CanvasLayer
## King of the Block's HUD layer (above the Hud): a marker on the zone with its distance (on the
## screen edge when it is off screen, plus the next spot during the move warning) and a card
## (top left) with who holds the zone, a CONTESTED warning, the capture progress toward the next
## point, your points and when the zone moves. The compass pip comes from
## KingOfTheBlock.compass_pips.

## Draws the zone markers where they are in the world.
class MarkerLayer extends Control:
	var koth: KingOfTheBlock

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or koth.zone < 0 or koth.world.match_over:
			return
		if koth._next_node.visible:
			_marker(cam, koth.next_pos(), Palette.color("zone_next").darkened(0.15), "NEXT")
		# The state in words too, so colour is never the only cue.
		var label := "ZONE"
		if koth.contested:
			label = "CONTESTED"
		elif koth.holder != 0:
			label = "YOUR ZONE" if koth.holder == koth.world.my_id() else "TAKEN"
		_marker(cam, koth.zone_pos(), koth.zone_color(), label)

	func _marker(cam: Camera3D, feet: Vector3, col: Color, label: String) -> void:
		var font := get_theme_default_font()
		var view := get_viewport_rect().size
		var me := cam.global_position
		var pos := feet + Vector3.UP * 2.6
		var at := UIKit.marker_point(cam, pos, view).clamp(Vector2(40, 80), view - Vector2(40, 70))
		var d := 12.0
		var outline := PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0), at + Vector2(0, -d)])
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0)]), Color(col, 0.85))
		draw_polyline(outline, Color(0, 0, 0, 0.8), 2.0)
		var text := "%s  %dm" % [label, roundi(Vector2(feet.x - me.x, feet.z - me.z).length())]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var tp := at + Vector2(-w * 0.5, 30)
		draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.9))
		draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col.lightened(0.3))

var koth: KingOfTheBlock
var _markers: MarkerLayer
var _card: PanelContainer
var _status: Label
var _bar: ProgressBar
var _bar_fill: StyleBoxFlat
var _mine: Label
var _move: Label


func setup(p_koth: KingOfTheBlock) -> void:
	koth = p_koth


func _ready() -> void:
	layer = 11
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	_markers = MarkerLayer.new()
	_markers.koth = koth
	root.add_child(_markers)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.hud_card(0.5, 10, UITheme.CARD_RADIUS, Color(Palette.color("zone_free"), 0.35)))
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.position = Vector2(16, 40)
	_card.custom_minimum_size = Vector2(260, 0)
	root.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_card.add_child(v)
	v.add_child(_label("KING OF THE BLOCK", 14, Color(0.7, 0.75, 0.85)))
	_status = _label("", 20, Color.WHITE)
	v.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_fill = UITheme.bar_box(Palette.color("zone_free"), 4)
	_bar.add_theme_stylebox_override("background", UITheme.bar_box(Color(0, 0, 0, 0.5), 4))
	_bar.add_theme_stylebox_override("fill", _bar_fill)
	v.add_child(_bar)
	_mine = _label("", 15, Color(1, 0.88, 0.45))
	v.add_child(_mine)
	_move = _label("", 15, Color.WHITE)
	v.add_child(_move)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	var w := koth.world
	var p := w.local_player
	_card.visible = p != null and koth.zone >= 0 and not w.match_over
	_markers.visible = not w.hud.markers_hidden()
	_markers.queue_redraw()
	if not _card.visible:
		return
	var me := w.my_id()
	var col := koth.zone_color()
	# self_modulate tints without the re-layout a theme override triggers.
	var alpha := 0.6 + 0.4 * sin(World.now() * 8.0) if koth.contested else 1.0
	if koth.contested:
		_status.text = "CONTESTED" if koth.in_zone(p.global_position) and p.alive else "ZONE CONTESTED"
	elif koth.holder == me:
		_status.text = "HOLDING  ·  +1 / s"
	elif koth.holder != 0:
		_status.text = "%s HOLDS IT" % w.display_name(koth.holder).to_upper()
	else:
		_status.text = "ZONE FREE  ·  GET IN"
	_status.self_modulate = Color(col.lightened(0.2), alpha)
	_bar_fill.bg_color = col
	_bar.value = koth.progress if koth.holder != 0 and not koth.contested else 0.0
	_mine.text = "YOU  %d / %d points" % [int(koth.points.get(me, 0)), koth.race_limit()]
	var left := koth.move_in()
	_move.self_modulate = Color(0.75, 0.85, 1.0)
	if koth.move_at <= 0.0:
		_move.text = "Zone stays until the end"
	elif left <= KingOfTheBlock.WARNING:
		_move.text = "ZONE MOVING IN %d" % ceili(left)
		_move.self_modulate = Color(1, 0.5, 0.4)
	else:
		var s := ceili(left)
		_move.text = "Zone moves in %d:%02d" % [s / 60, s % 60]
