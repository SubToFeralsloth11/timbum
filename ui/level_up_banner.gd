class_name LevelUpBanner
extends Control
## The every-MILESTONE-levels celebration: a banner that drops in at the top of the screen with a
## big LevelBadge, a burst of flame rays and sparks behind it and "LEVEL 25", plays for LIFE
## seconds and frees itself. It never takes input (everything ignores the mouse) and sits at the
## top edge, so it is only shown on screens without a crosshair (the results screen).

## Every this many levels is celebrated.
const MILESTONE := 5
const LIFE := 3.2
const RAYS := 14
## Banner size and its distance from the top edge, in px.
const WIDTH := 440.0
const HEIGHT := 120.0
const TOP := 8.0

var _level := 1
var _t := 0.0
var _badge: LevelBadge


## The milestone level reached going from `before` to `after` (the highest multiple of MILESTONE
## in (before, after]), 0 when none was.
static func milestone(before: int, after: int) -> int:
	var m := (after / MILESTONE) * MILESTONE
	return m if m > before and m >= MILESTONE else 0


## Plays the banner for `lvl` on top of `parent` (a full-screen control).
static func play(parent: Control, lvl: int) -> LevelUpBanner:
	var b := LevelUpBanner.new()
	b._level = lvl
	parent.add_child(b)
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centred on the top edge: anchors at the top centre, offsets half the width either side.
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	_place(0.0)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	_badge = LevelBadge.make(_level, 1.35)
	row.add_child(_badge)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", -6)
	row.add_child(words)
	var top := UIKit.label("LEVEL UP!", &"SmallLabel")
	top.add_theme_color_override("font_color", LevelBadge.flame_colors(_level)[2])
	words.add_child(top)
	var big := UIKit.label("LEVEL %d" % _level, &"TitleLabel")
	big.add_theme_font_size_override("font_size", 44)
	big.add_theme_color_override("font_color", Color.WHITE)
	big.add_theme_color_override("font_outline_color", LevelBadge.flame_colors(_level)[0].darkened(0.4))
	big.add_theme_constant_override("outline_size", 10)
	words.add_child(big)
	modulate.a = 0.0


func _process(delta: float) -> void:
	_t += delta
	# In for 0.3 s (dropping from above), hold, out over the last 0.5 s.
	var a := clampf(_t / 0.3, 0.0, 1.0) * clampf((LIFE - _t) / 0.5, 0.0, 1.0)
	modulate.a = a
	_place(1.0 - clampf(_t / 0.3, 0.0, 1.0))
	queue_redraw()
	if _t >= LIFE:
		queue_free()


## Top edge TOP px down, raised by `lift` (0..1) x 40 px while it drops in.
func _place(lift: float) -> void:
	offset_top = TOP - 40.0 * lift
	offset_bottom = offset_top + HEIGHT


func _draw() -> void:
	if _badge == null:
		return
	# Rays and sparks bursting from behind the badge, fastest in the first second.
	var c := _badge.position + _badge.get_parent_control().position + _badge.size * 0.5
	var colors := LevelBadge.flame_colors(_level, _t)
	var burst := 1.0 - pow(1.0 - clampf(_t / 0.9, 0.0, 1.0), 3.0)
	for i in RAYS:
		var ang := TAU * i / RAYS + _t * 0.6
		var inner := 30.0 + burst * 10.0
		var outer := inner + burst * (60.0 + 25.0 * sin(i * 1.7 + _t * 5.0))
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x) * 5.0
		draw_colored_polygon(PackedVector2Array([c + dir * inner + side, c + dir * outer, c + dir * inner - side]),
			Color(colors[1], 0.55 * (1.0 - clampf((_t - 1.5) / 1.2, 0.0, 1.0))))
	for i in 18:
		var ang := TAU * i / 18.0 + i * 0.4
		var d := burst * (70.0 + 30.0 * sin(i * 3.1))
		draw_circle(c + Vector2(cos(ang), sin(ang)) * d, maxf(1.0, 3.5 * (1.0 - burst * 0.7)), Color(colors[2], 1.0 - burst * 0.8))
