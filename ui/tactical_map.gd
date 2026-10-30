class_name TacticalMap
extends Control
## Tactical floor plan: a top-down plan of one storey of Block HQ at a time with the staging
## rooms, weapon spots, living teammates and the team's markers. Left click places an ATTACK
## marker, right click a HOLD marker, clicking a marker removes it; the wheel or the tabs
## change storey. Opened from TacticalOverlay ("tactical_map" key, and automatically while
## planning).

const Gen := preload("res://scripts/world/maps/building_map.gd")
const MARKER_COLORS := {"attack": Color(1.0, 0.36, 0.26), "hold": Color(0.3, 0.9, 1.0)}
## Clicks this close (metres) to a marker remove it instead of placing one.
const REMOVE_RADIUS := 2.5

static var _floor_textures: Array[ImageTexture] = []

var tactical: Tactical
var floor_index := 0
var _plan: Control
var _title: Label
var _tabs: Array[Button] = []


func setup(p_tactical: Tactical) -> void:
	tactical = p_tactical


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _floor_textures.is_empty():
		_build_textures()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 40
	v.offset_right = -40
	v.offset_top = 24
	v.offset_bottom = -20
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	_title = _label("", 28, Color(1, 0.85, 0.4))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	for i in Gen.FLOOR_NAMES.size():
		var b := Button.new()
		b.text = Gen.FLOOR_NAMES[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 36)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: show_floor(i))
		head.add_child(b)
		_tabs.append(b)
	_plan = Control.new()
	_plan.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan.draw.connect(_draw_plan)
	v.add_child(_plan)
	var legend := _label("LEFT CLICK  attack marker     RIGHT CLICK  hold marker     CLICK A MARKER  remove it     WHEEL  storey     %s / ESC  close" \
		% Profile.key_text("tactical_map"), 16, Color(0.85, 0.88, 0.95))
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(legend)
	var legend2 := _label("Teammates and bots see your markers on their HUD; bot squads go to ATTACK markers and dig in at HOLD markers.", 15, Color(0.7, 0.75, 0.85))
	legend2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(legend2)
	show_floor(floor_index)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func show_floor(i: int) -> void:
	floor_index = clampi(i, 0, Gen.FLOORS.size() - 1)
	for k in _tabs.size():
		_tabs[k].set_pressed_no_signal(k == floor_index)
	if _title != null:
		_title.text = "TACTICAL MAP  ·  %s" % Gen.FLOOR_NAMES[floor_index]
	if _plan != null:
		_plan.queue_redraw()


func _process(_delta: float) -> void:
	if visible and _plan != null:
		_plan.queue_redraw()


## One image per storey from the generator: walls light, floor dark, stairs amber, outside
## (ground floor alleys) green-grey; holes and roofless areas are left clear.
static func _build_textures() -> void:
	var g := VoxelGrid.new(Gen.SIZE)
	Gen.generate(g, MapInfo.new())
	for y: int in Gen.FLOORS:
		var img := Image.create(g.size.x, g.size.z, false, Image.FORMAT_RGBA8)
		for z in g.size.z:
			for x in g.size.x:
				var inside := x >= 4 and x <= 107 and z >= 6 and z <= 57
				var c := Color(0, 0, 0, 0)
				var ramp := (not g.is_air(x, y, z) and g.get_shape(x, y, z) != VoxelGrid.CUBE) \
					or (not g.is_air(x, y - 1, z) and g.get_shape(x, y - 1, z) != VoxelGrid.CUBE)
				if ramp:
					c = Color(0.95, 0.72, 0.25)
				elif not g.is_air(x, y + 1, z):
					c = Color(0.8, 0.82, 0.86)
				elif g.standable(x, y, z, 2):
					c = Color(0.2, 0.22, 0.27) if inside else Color(0.16, 0.2, 0.16)
				elif not g.is_air(x, y, z):
					c = Color(0.36, 0.33, 0.3)
				img.set_pixel(x, z, c)
		_floor_textures.append(ImageTexture.create_from_image(img))


## Map rect inside _plan keeping the building's aspect ratio.
func _plan_rect() -> Rect2:
	var avail := _plan.size
	var s := minf(avail.x / Gen.SIZE.x, avail.y / Gen.SIZE.z)
	var sz := Vector2(Gen.SIZE.x, Gen.SIZE.z) * s
	return Rect2((avail - sz) * 0.5, sz)


func _to_map(pos: Vector3, r: Rect2) -> Vector2:
	var g := pos - tactical.origin
	return r.position + Vector2(g.x / Gen.SIZE.x, g.z / Gen.SIZE.z) * r.size


func _to_world(at: Vector2, r: Rect2) -> Vector3:
	var uv := (at - r.position) / r.size
	return tactical.origin + Vector3(uv.x * Gen.SIZE.x, Gen.FLOORS[floor_index] + 0.1, uv.y * Gen.SIZE.z)


func _draw_plan() -> void:
	var r := _plan_rect()
	_plan.draw_rect(r.grow(6), Color(0, 0, 0, 0.5))
	_plan.draw_texture_rect(_floor_textures[floor_index], r, false)
	var font := get_theme_default_font()
	var cell := r.size.x / Gen.SIZE.x
	# Staging rooms (ground and first floor).
	if floor_index < 2:
		for team in 2:
			var a := Gen.SPAWN_ROOM[0]
			var b := Gen.SPAWN_ROOM[1]
			var x0 := a.x if team == 0 else Gen.SIZE.x - 1 - b.x
			var rect := Rect2(r.position + Vector2(x0, a.z) * cell, Vector2(b.x - a.x + 1, b.z - a.z + 1) * cell)
			_plan.draw_rect(rect, Color(Teams.color(team), 0.18))
			_plan.draw_string(font, rect.get_center() + Vector2(-34, 6), Teams.label(team), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Teams.color(team))
	# Weapon spots on this storey.
	for s: Dictionary in tactical.spots:
		if str(s.wid).is_empty() or tactical.floor_of(s.pos) != floor_index:
			continue
		var at := _to_map(s.pos, r)
		_plan.draw_rect(Rect2(at - Vector2(2.5, 2.5), Vector2(5, 5)), Color(1.0, 0.9, 0.45, 0.85))
	# Living teammates (this storey bright, others faint), the local player as an arrow.
	var mine := tactical.my_team()
	for eid: int in tactical.world.entities:
		var p: Player = tactical.world.entities[eid]
		if not p.alive or Teams.of(p) != mine:
			continue
		var on_floor := tactical.floor_of(p.global_position) == floor_index
		var at := _to_map(p.global_position, r)
		var col := Teams.color(mine)
		if p == tactical.world.local_player:
			var fwd := Vector2(-sin(p.yaw), -cos(p.yaw))
			var side := Vector2(fwd.y, -fwd.x)
			var pts := PackedVector2Array([at + fwd * 11.0, at - fwd * 6.0 + side * 6.0, at - fwd * 6.0 - side * 6.0])
			_plan.draw_colored_polygon(pts, Color.WHITE if on_floor else Color(1, 1, 1, 0.35))
		else:
			_plan.draw_circle(at, 4.5 if on_floor else 3.0, Color(col, 1.0 if on_floor else 0.3))
	# Markers.
	for m: Dictionary in tactical.team_markers:
		var on_floor := tactical.floor_of(m.pos) == floor_index
		var at := _to_map(m.pos, r)
		var col: Color = MARKER_COLORS.get(str(m.kind), Color.WHITE)
		col.a = 1.0 if on_floor else 0.35
		var d := 9.0
		_plan.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0)]), col)
		var letter := "A" if str(m.kind) == "attack" else "H"
		_plan.draw_string(font, at + Vector2(-5, 5), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, col.a))
		if on_floor:
			_plan.draw_string(font, at + Vector2(12, 5), str(m.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	accept_event()
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			show_floor(floor_index + 1)
			return
		MOUSE_BUTTON_WHEEL_DOWN:
			show_floor(floor_index - 1)
			return
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			pass
		_:
			return
	var r := _plan_rect()
	var at := _plan.get_local_mouse_position()
	if not r.has_point(at):
		return
	var pos := _to_world(at, r)
	for m: Dictionary in tactical.team_markers:
		var mp: Vector3 = m.pos
		if tactical.floor_of(mp) == floor_index and Vector2(mp.x - pos.x, mp.z - pos.z).length() < REMOVE_RADIUS:
			tactical.request_marker_remove(int(m.id))
			Sfx.play(&"ui_click")
			return
	tactical.request_marker("attack" if mb.button_index == MOUSE_BUTTON_LEFT else "hold", pos)
	Sfx.play(&"ui_click", null, 0.0, 1.2)
