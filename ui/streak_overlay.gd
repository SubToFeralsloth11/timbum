class_name StreakOverlay
extends CanvasLayer
## Killstreak HUD layer (above the Hud), owned by Streaks: a toast in the Hud's toast column for
## each reward this player earns (and a teammate's Radar Sweep), a rounded status card above the
## health card (current streak and the next reward, radar time left, an enemy radar warning, the
## bomber-ready prompt with its key), the bomber targeting help under the crosshair, markers on
## enemies a Radar Sweep shows, an AIRSTRIKE label with a countdown over every called strike, and
## a warning chip when the local player stands in one. The ground warnings themselves are 3D marks
## (Streaks). Compass pips come from Streaks.compass_pips.

const TOAST_LIFE := 3.5


## Radar markers on enemies and the AIRSTRIKE labels, drawn where they are in the world.
class MarkerLayer extends Control:
	var streaks: Streaks

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or streaks.world.match_over:
			return
		var font := get_theme_default_font()
		for p: Player in streaks.radar_targets():
			var pos := p.global_position + Vector3.UP * 2.1
			if cam.is_position_behind(pos):
				continue
			var at := cam.unproject_position(pos)
			var d := 7.0
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0)]), Color(Palette.color("radar"), 0.85))
			draw_polyline(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0), at + Vector2(0, -d)]), Color(0, 0, 0, 0.8), 1.5)
		var t := World.now()
		for s: Dictionary in streaks.strikes:
			var pos := Streaks.strike_center(s) + Vector3.UP * 3.0
			if cam.is_position_behind(pos):
				continue
			var at := cam.unproject_position(pos)
			var left := float(s.land_at) - t
			var text := "AIRSTRIKE  %.1f" % left if left > 0.0 else "AIRSTRIKE"
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var tp := at + Vector2(-w * 0.5, 0)
			draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.9))
			draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.color("warning").lightened(0.35))

var streaks: Streaks
var _markers: MarkerLayer
var _danger_chip: PanelContainer
var _card: PanelContainer
var _streak_line: Label
var _radar_line: Label
var _radar_bar: ProgressBar
var _enemy_line: Label
var _bomber_line: Label
var _target_help: Label
var _danger: Label


func setup(p_streaks: Streaks) -> void:
	streaks = p_streaks


func _ready() -> void:
	layer = 11
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	_markers = MarkerLayer.new()
	_markers.streaks = streaks
	root.add_child(_markers)

	# Status card above the Hud's health card (bottom left).
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.hud_card(0.5, 7, 12))
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.position = Vector2(18, -104)
	_card.custom_minimum_size = Vector2(260, 0)
	root.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_card.add_child(v)
	_streak_line = _label("", 12, Color(0.8, 0.84, 0.92))
	v.add_child(_streak_line)
	_radar_line = _label("", 13, Streaks.REWARDS.radar.color)
	v.add_child(_radar_line)
	_radar_bar = UITheme.slim_bar(Streaks.REWARDS.radar.color, Vector2(0, 5))
	v.add_child(_radar_bar)
	_enemy_line = _label("ENEMY RADAR  ·  YOU ARE SPOTTED", 12, Palette.color("radar"))
	v.add_child(_enemy_line)
	_bomber_line = _label("", 14, Streaks.REWARDS.bomber.color)
	v.add_child(_bomber_line)

	_target_help = _label("", 15, Streaks.PREVIEW_COLOR)
	_target_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_target_help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_target_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_help.position.y += 45
	root.add_child(_target_help)

	# Standing in a called strike: a red chip below the crosshair (clear of the score card and
	# its callouts).
	_danger = _label("AIRSTRIKE INCOMING  ·  MOVE!", 18, Color.WHITE)
	_danger.add_theme_constant_override("outline_size", 0)
	_danger_chip = PanelContainer.new()
	_danger_chip.add_theme_stylebox_override("panel", UITheme.chip_box(Color(Palette.color("warning"), 0.85), Color(1, 1, 1, 0.2), 14, 6))
	_danger_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_chip.add_child(_danger)
	_danger_chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_danger_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_danger_chip.position.y += 120
	root.add_child(_danger_chip)

	streaks.rewarded.connect(_on_rewarded)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_font_override("font", UITheme.heavy_font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _on_rewarded(eid: int, kind: String, streak: int) -> void:
	var w := streaks.world
	var me := w.local_player
	var r: Dictionary = Streaks.REWARDS[kind]
	if me != null and eid == me.id:
		var sub := "%d KILL STREAK  ·  %s" % [streak, r.desc]
		if kind == "bomber":
			sub = "%d KILL STREAK  ·  [%s] to call it in" % [streak, Profile.key_text("streak_reward")]
		toast(str(r.name), sub, r.color)
	elif kind == "radar" and me != null and Teams.same(w.entities.get(eid), me):
		toast("TEAM RADAR", "%s's Radar Sweep shows enemies for 8 s" % w.display_name(eid), r.color)


## A reward toast in the Hud's toast column (with the challenge and achievement toasts).
func toast(title: String, sub: String, color: Color) -> void:
	streaks.world.hud.toast(title, sub, color, TOAST_LIFE)


func _process(_delta: float) -> void:
	var w := streaks.world
	var p := w.local_player
	_markers.queue_redraw()
	var live := p != null and p.alive and not w.match_over
	_target_help.visible = live and streaks.targeting
	if _target_help.visible:
		var key := Profile.key_text("streak_reward")
		_target_help.text = ("CALL IN BLOCK BOMBER\n[%s] or [%s]   ·   [%s] cancel" % [Profile.key_text("fire"), key, Profile.key_text("aim")]) \
			if streaks.aim_point(p) != null else "BLOCK BOMBER\nAIM AT THE GROUND (WITHIN %d m)" % int(Streaks.BOMBER_RANGE)
	_danger_chip.visible = live and not streaks.danger_near(p.global_position).is_empty()
	if _danger_chip.visible:
		_danger_chip.modulate.a = 0.7 + 0.3 * sin(World.now() * 14.0)
	if not live:
		_card.visible = false
		return
	var streak := int(w.scores.get(p.id, {}).get("streak", 0))
	var next := ""
	for kind: String in Streaks.REWARDS:
		if int(Streaks.REWARDS[kind].at) > streak:
			next = "  ·  %s at %d" % [str(Streaks.REWARDS[kind].name), int(Streaks.REWARDS[kind].at)]
			break
	_streak_line.text = "STREAK %d%s" % [streak, next]
	var radar := streaks.radar_left(p)
	_radar_line.visible = radar > 0.0
	_radar_bar.visible = radar > 0.0
	if radar > 0.0:
		_radar_line.text = "RADAR SWEEP  %.1f s" % radar
		_radar_bar.value = radar / Streaks.RADAR_TIME
	_enemy_line.visible = streaks.enemy_radar_left(p) > 0.0
	_bomber_line.visible = streaks.has_bomber(p.id)
	if _bomber_line.visible:
		_bomber_line.text = "[%s] BLOCK BOMBER READY" % Profile.key_text("streak_reward") if not streaks.targeting else "BLOCK BOMBER: TARGETING"
		_bomber_line.modulate.a = 0.7 + 0.3 * sin(World.now() * 6.0)
	# Nothing to say before the first kill of a life.
	_card.visible = streak > 0 or radar > 0.0 or _enemy_line.visible or _bomber_line.visible
