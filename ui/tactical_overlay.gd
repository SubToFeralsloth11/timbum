class_name TacticalOverlay
extends CanvasLayer
## Tactical mode HUD layer (above the Hud): planning countdown, the player's team, team markers
## in the world, the pick-up/swap prompt, pick-up toasts, the spectator bar and the floor plan
## (TacticalMap). Team alive counters and compass marker pips live in the Hud itself.

const MARKER_COLORS := TacticalMap.MARKER_COLORS

## Draws team markers where they are in the world (clamped to the screen edge when off screen).
class MarkerLayer extends Control:
	var tactical: Tactical

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or tactical.world.match_over:
			return
		var font := get_theme_default_font()
		var view := get_viewport_rect().size
		var me := cam.global_position
		var my_floor := tactical.floor_of(me - Vector3.UP * 1.5)
		for m: Dictionary in tactical.team_markers:
			var pos: Vector3 = m.pos + Vector3.UP * 1.3
			var col: Color = MARKER_COLORS.get(str(m.kind), Color.WHITE)
			var at: Vector2
			var behind := cam.is_position_behind(pos)
			if behind:
				# Mirror behind-the-camera points onto the bottom edge.
				at = cam.unproject_position(me * 2.0 - pos)
				at = Vector2(view.x - at.x, view.y - 40.0)
			else:
				at = cam.unproject_position(pos)
			at = at.clamp(Vector2(30, 70), view - Vector2(30, 60))
			var d := 10.0
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0)]), col)
			draw_polyline(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0), at + Vector2(0, -d)]), Color(0, 0, 0, 0.8), 2.0)
			var floor_diff := tactical.floor_of(m.pos) - my_floor
			var arrow := "  ▲" if floor_diff > 0 else ("  ▼" if floor_diff < 0 else "")
			var text := "%s %dm%s" % ["ATTACK" if str(m.kind) == "attack" else "HOLD", roundi(me.distance_to(pos)), arrow]
			draw_string_outline(font, at + Vector2(-34, 26), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
			draw_string(font, at + Vector2(-34, 26), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.3))

var tactical: Tactical
var map: TacticalMap
var _root: Control
var _markers: MarkerLayer
var _banner: PanelContainer
var _banner_time: Label
var _team_label: Label
var _prompt: Label
var _toast: Label
var _toast_t := 0.0
var _spectate: PanelContainer
var _spectate_label: Label
var _auto_opened := false


func setup(p_tactical: Tactical) -> void:
	tactical = p_tactical


func _ready() -> void:
	layer = 11
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_markers = MarkerLayer.new()
	_markers.tactical = tactical
	_root.add_child(_markers)

	_banner = _panel()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y = 170
	_root.add_child(_banner)
	var bv := VBoxContainer.new()
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(bv)
	_banner_time = _label("", 30, Color(1, 0.85, 0.4))
	_banner_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_banner_time)
	var hint := _label("Plan your attack. The barriers drop when the timer runs out.\n%s  floor plan: place ATTACK / HOLD markers for your team" \
		% Profile.key_text("tactical_map"), 16, Color(0.88, 0.9, 0.95))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(hint)

	_team_label = _label("", 20)
	_team_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_team_label.position = Vector2(16, 34)
	_root.add_child(_team_label)

	_prompt = _label("", 20, Color(1, 0.92, 0.6))
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position.y += 40
	_root.add_child(_prompt)

	_toast = _label("", 22, Color(0.7, 1.0, 0.7))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position.y -= 160
	_root.add_child(_toast)

	_spectate = _panel()
	_spectate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_spectate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_spectate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_spectate.position.y -= 24
	_spectate.visible = false
	_root.add_child(_spectate)
	var sv := VBoxContainer.new()
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectate.add_child(sv)
	var out := _label("YOU ARE OUT  ·  ONE LIFE PER MATCH", 16, Color(1, 0.45, 0.4))
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(out)
	_spectate_label = _label("", 26)
	_spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(_spectate_label)
	var keys := _label("%s  next teammate   ·   %s  previous   ·   %s  floor plan   ·   ESC  leave to the menu" \
		% [Profile.key_text("fire"), Profile.key_text("aim"), Profile.key_text("tactical_map")], 15, Color(0.8, 0.84, 0.92))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(keys)

	map = TacticalMap.new()
	map.setup(tactical)
	map.visible = false
	add_child(map)


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.62)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _process(delta: float) -> void:
	var w := tactical.world
	var over := w.match_over
	_markers.visible = not over and not map.visible
	_markers.queue_redraw()
	_banner.visible = tactical.is_planning() and not over
	if _banner.visible:
		var left := ceili(tactical.planning_left())
		_banner_time.text = "PLANNING PHASE  0:%02d" % left
		# Open the floor plan once at the start of the match so planning starts there.
		if not _auto_opened and w.local_player != null and not w.hud.is_blocking():
			_auto_opened = true
			open_map(true)
	var team := tactical.my_team()
	_team_label.visible = team >= 0 and not over
	if team >= 0:
		_team_label.text = "TEAM %s" % Teams.label(team)
		_team_label.add_theme_color_override("font_color", Teams.color(team))
	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_prompt.text = _prompt_text()
	_spectate.visible = tactical.is_spectating() and not over and not map.visible
	if _spectate.visible and tactical.spectating != null:
		var s := tactical.spectating
		_spectate_label.text = "SPECTATING  %s  ·  %s" % [w.display_name(s.id).to_upper(), Teams.label(Teams.of(s))]
		_spectate_label.add_theme_color_override("font_color", Teams.color(Teams.of(s)))


## "Swap" prompt when standing at a weapon your slot already holds something for; a reminder
## to find a gun while carrying only the knife.
func _prompt_text() -> String:
	var p := tactical.world.local_player
	if p == null or not p.alive or tactical.world.match_over or map.visible:
		return ""
	var i := tactical.spot_near(p.global_position, Tactical.INTERACT_RADIUS)
	if i >= 0:
		var wid: String = tactical.spots[i].wid
		var held := p.slots[Tactical.slot_of(wid)]
		if held.is_empty():
			return "%s  ·  walk over it to pick it up" % str(Data.WEAPONS[wid].name).to_upper()
		if held != wid:
			return "[%s]  SWAP %s FOR %s" % [Profile.key_text("interact"), str(Data.WEAPONS[held].name).to_upper(),
				str(Data.WEAPONS[wid].name).to_upper()]
		return ""
	if p.slots[0].is_empty() and p.slots[1].is_empty() and tactical.fighting():
		return "KNIFE ONLY  ·  FIND A WEAPON IN THE ROOMS"
	return ""


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.0


func phase_changed() -> void:
	if not tactical.is_planning() and map != null and map.visible and _auto_opened:
		close_map()


func markers_changed() -> void:
	if _markers != null:
		_markers.queue_redraw()


func spectate_changed() -> void:
	pass


func is_blocking() -> bool:
	return map != null and map.visible


func open_map(auto := false) -> void:
	var p := tactical.world.local_player
	var focus: Vector3 = p.global_position if p != null and p.alive else (tactical.spectating.global_position if tactical.spectating != null else Vector3.ZERO)
	map.show_floor(tactical.floor_of(focus))
	map.visible = true
	_auto_opened = _auto_opened or auto
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Closes the floor plan; returns whether it was open (Esc handling).
func close_map() -> bool:
	if map == null or not map.visible:
		return false
	map.visible = false
	if not tactical.world.hud.is_blocking():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return true


func _unhandled_input(event: InputEvent) -> void:
	var w := tactical.world
	if event.is_action_pressed("tactical_map"):
		if map.visible:
			close_map()
		elif not w.match_over and not w.hud.is_blocking():
			open_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not w.input_blocked():
		var p := w.local_player
		if p != null and p.alive:
			tactical.request_interact()
			get_viewport().set_input_as_handled()
