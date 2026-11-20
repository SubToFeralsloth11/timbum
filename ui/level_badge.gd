class_name LevelBadge
extends Control
## A player's level drawn inside a procedural, flickering flame (Duolingo-streak style; no image
## files). The higher the level, the healthier the flame: a dull ember at level 1, orange, then
## gold, white-hot, blue, violet and finally a slowly shifting rainbow (flame_colors), and a little
## taller (up to MAX_GROW at level GROW_LEVEL). Level 30 and up throws sparks. Used on the main
## menu player card, the results screen, the stats screen, the scoreboard and the lobby (small).
## Never takes the mouse.

## Height of the flame at level 1 for `px` 1 (the control's height is px * this).
const GROW_LEVEL := 100
const MAX_GROW := 0.25
## Flame bands: [first level, outer, body, core]. The last band whose level is reached is used.
const BANDS: Array = [
	[1, Color("5a1d10"), Color("a3401c"), Color("e08a3a")],
	[5, Color("8a2a0c"), Color("e8601c"), Color("ffb347")],
	[10, Color("b8320a"), Color("ff7a1a"), Color("ffd45c")],
	[20, Color("d24a08"), Color("ffa21f"), Color("fff0a0")],
	[30, Color("e86a10"), Color("ffcf3a"), Color("ffffff")],
	[50, Color("1b4fd8"), Color("3fa9ff"), Color("e6fbff")],
	[75, Color("6a1fd8"), Color("c05cff"), Color("fbe6ff")],
]
## From this level the flame's hue keeps turning (the rainbow band).
const RAINBOW_LEVEL := 100
## Teardrop outline resolution.
const POINTS := 28

## The level shown.
var level := 1:
	set(v):
		level = maxi(1, v)
		_resize()
		queue_redraw()
## Size of the badge: 1.0 is the main menu card (about 64 px tall); 0.35 fits a scoreboard row.
var px := 1.0:
	set(v):
		px = v
		_resize()
		queue_redraw()

var _t := 0.0


## A badge for `lvl` at size `badge_px` (see px).
static func make(lvl: int, badge_px := 1.0) -> LevelBadge:
	var b := LevelBadge.new()
	b.px = badge_px
	b.level = lvl
	return b


## [outer, body, core] flame colours for `lvl`.
static func flame_colors(lvl: int, t := 0.0) -> Array[Color]:
	var band: Array = BANDS[0]
	for b: Array in BANDS:
		if lvl >= int(b[0]):
			band = b
	var out: Array[Color] = [band[1], band[2], band[3]]
	if lvl >= RAINBOW_LEVEL:
		var h := fposmod(t * 0.08, 1.0)
		out[0] = Color.from_hsv(h, 0.85, 0.75)
		out[1] = Color.from_hsv(fposmod(h + 0.08, 1.0), 0.7, 1.0)
		out[2] = Color.from_hsv(fposmod(h + 0.16, 1.0), 0.15, 1.0)
	return out


## How much taller than level 1 the flame is (0..MAX_GROW).
static func grow(lvl: int) -> float:
	return MAX_GROW * clampf(float(lvl - 1) / float(GROW_LEVEL - 1), 0.0, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t = randf() * 10.0
	_resize()


func _resize() -> void:
	var h := 64.0 * px * (1.0 + grow(level))
	custom_minimum_size = Vector2(roundf(h * 0.82), roundf(h))


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var colors := flame_colors(level, _t)
	# Healthier flames burn a little faster and steadier.
	var speed := 7.0 + minf(level, 60) * 0.06
	var base := Vector2(w * 0.5, h * 0.97)
	var big := minf(w / 0.82, h)
	_flame(base, big * 0.96, big * 0.40, colors[0], 1.0, speed, 0.0)
	_flame(base - Vector2(0, big * 0.04), big * 0.74, big * 0.31, colors[1], 0.8, speed * 1.2, 1.7)
	_flame(base - Vector2(0, big * 0.07), big * 0.48, big * 0.20, colors[2], 0.6, speed * 1.5, 3.1)
	if level >= 30:
		_sparks(base, big, colors[2])
	# The number, white with a dark outline, in the flame's belly.
	var font := UITheme.heavy_font()
	var text := str(level)
	var fs := int(big * (0.36 if text.length() <= 2 else (0.29 if text.length() == 3 else 0.23)))
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := Vector2(base.x - ts.x * 0.5, base.y - big * 0.22 + font.get_ascent(fs) * 0.5 - font.get_descent(fs) * 0.3)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(big * 0.07)), Color(0.12, 0.03, 0.0, 0.95))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## One teardrop layer standing on `base`: `tall` high, `wide` across its belly. The tip sways and
## the sides ripple with `speed`; `wobble` scales both, `phase` keeps the layers out of step.
func _flame(base: Vector2, tall: float, wide: float, color: Color, wobble: float, speed: float, phase: float) -> void:
	var pts := PackedVector2Array()
	var belly := base - Vector2(0, wide * 0.95)
	var sway := sin(_t * speed * 0.55 + phase) * wide * 0.22 * wobble
	var stretch := 1.0 + sin(_t * speed + phase * 1.3) * 0.05 * wobble
	for i in POINTS:
		# t runs round the outline; 0 is the tip. sin(t/2)^2 pinches the top into a point.
		var t := TAU * float(i) / POINTS
		var pinch := pow(absf(sin(t * 0.5)), 1.6)
		var x := sin(t) * pinch * wide
		var up := (cos(t) + 1.0) * 0.5
		var y := -cos(t) * wide
		if cos(t) > 0.0:
			y = -cos(t) * (tall - wide) * stretch
		var ripple := sin(_t * speed * 1.7 + up * 6.0 + phase) * wide * 0.07 * wobble * up
		pts.append(Vector2(belly.x + x + sway * up * up + ripple, belly.y + y))
	draw_colored_polygon(pts, color)


## A few embers rising off a hot flame.
func _sparks(base: Vector2, big: float, color: Color) -> void:
	for i in 5:
		var life := fposmod(_t * 0.9 + i * 0.37, 1.0)
		var x := base.x + sin(i * 2.3 + _t * 1.3) * big * 0.28
		var y := base.y - big * (0.55 + life * 0.5)
		draw_circle(Vector2(x, y), maxf(1.0, big * 0.025 * (1.0 - life)), Color(color, 1.0 - life))
