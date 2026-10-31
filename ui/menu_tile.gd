class_name MenuTile
extends Button
## Big main-menu button: a code-drawn pixel icon, the label, an optional badge on the right
## (claimable challenges, ...) and a hover/focus animation (accent bar, glow, the tile nudges
## right and grows a little) with the hover sound for mouse and controller alike. `selected`
## keeps it lit while its sub-panel is open.

## 11x11 pixel icons, "#" = filled.
const ICONS := {
	"play": ["...#.......", "...##......", "...###.....", "...####....", "...#####...", "...######..",
		"...#####...", "...####....", "...###.....", "...##......", "...#......."],
	"locker": ["..###.###..", ".#########.", "###########", "###########", "##.#####.##", "...#####...",
		"...#####...", "...#####...", "...#####...", "...#####...", "...#####..."],
	"shop": ["...#####...", "..#.....#..", "..#.....#..", "###########", "###########", "###.###.###",
		"###########", "###########", "###########", "###########", ".#########."],
	"progress": ["###########", "#.#######.#", "#.#######.#", ".#.#####.#.", "...#####...", "....###....",
		".....#.....", ".....#.....", "....###....", "...#####...", "...#####..."],
	"settings": ["....###....", ".#.#####.#.", "..#######..", ".####.####.", "####...####", "###.....###",
		"####...####", ".####.####.", "..#######..", ".#.#####.#.", "....###...."],
	"quit": ["##.......##", "###.....###", ".###...###.", "..###.###..", "...#####...", "....###....",
		"...#####...", "..###.###..", ".###...###.", "###.....###", "##.......##"],
	"bots": [".....#.....", ".....#.....", ".#########.", ".#.......#.", ".#.##.##.#.", "##.##.##.##",
		".#.......#.", ".#.#####.#.", ".#.......#.", ".#########.", "..........."],
	"host": ["#.........#", "#..#...#..#", "#.#..#..#.#", "#.#.###.#.#", "#..#.#.#..#", "#....#....#",
		".....#.....", "....###....", "....#.#....", "...#...#...", "..#.....#.."],
	"join": ["...........", "......#####", "....#.....#", "....##....#", "#######...#", "########..#",
		"#######...#", "....##....#", "....#.....#", "......#####", "..........."],
	"range": ["...#####...", "..#.....#..", ".#..###..#.", "#..#...#..#", "#.#..#..#.#", "#.#.###.#.#",
		"#.#..#..#.#", "#..#...#..#", ".#..###..#.", "..#.....#..", "...#####..."],
	"tutorial": ["...#####...", "..##...##..", "..##...##..", ".......##..", "......##...", ".....##....",
		"....##.....", "....##.....", "...........", "....##.....", "....##....."],
	"stats": ["........##.", "........##.", "....##..##.", "....##..##.", "....##..##.", "##..##..##.",
		"##..##..##.", "##..##..##.", "##..##..##.", "...........", "###########"],
	"challenges": ["###########", "#.........#", "#.......#.#", "#......##.#", "#.#...##..#", "#.##.##...#",
		"#..###....#", "#...#.....#", "#.........#", "#.........#", "###########"],
	"achievements": [".....#.....", ".....#.....", "....###....", "###########", ".#########.", "..#######..",
		"...#####...", "..#######..", "..###.###..", ".##.....##.", ".#.......#."],
	"back": ["...........", "....#......", "...##......", "..###......", ".##########", "###########",
		".##########", "..###......", "...##......", "....#......", "..........."],
}
const ICON_SCALE := 3
const NUDGE := 8.0
const GROW := 0.025
## Face colour per theme variation (the theme's button colours).
const BASES := {&"PrimaryButton": UITheme.BUTTON_GREEN, &"GoldButton": UITheme.BUTTON_GOLD,
	&"DangerButton": UITheme.BUTTON_RED}

## Lit while the sub-panel this tile opens is showing.
var selected := false:
	set(value):
		selected = value
		_animate()

var _hot := 0.0
var _tween: Tween
var _badge: PanelContainer
var _badge_label: Label
var _accent: Color
var _glow: StyleBoxFlat
var _pill: StyleBoxFlat

static var _icons := {}


## `accent` colours the hover bar and glow; `icon_color` should match the variation's text.
func _init(label: String, icon_id: String, variation: StringName = &"", height := 58.0, font_size := 22,
		accent := UITheme.ACCENT, icon_color := UITheme.TEXT) -> void:
	text = label
	name = "Tile_" + icon_id
	if variation != &"":
		theme_type_variation = variation
	icon = icon_texture(icon_id)
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size.y = height
	_accent = accent
	add_theme_font_size_override("font_size", font_size)
	add_theme_constant_override("h_separation", 14)
	for key: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color",
			"icon_hover_pressed_color"]:
		add_theme_color_override(key, icon_color)
	round_styles(self, BASES.get(variation, UITheme.BUTTON_SLATE), int(height * 0.32))
	_badge = UIKit.badge("", &"GoldBadgePanel")
	_badge_label = _badge.get_child(0) as Label
	var pill := UITheme.round_box(Color("d99a12"), Color(0, 0, 0, 0.45), 2, 12, 2)
	pill.content_margin_left = 10
	pill.content_margin_right = 10
	_badge.add_theme_stylebox_override("panel", pill)
	_badge_label.add_theme_font_size_override("font_size", 15)
	_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge.grow_vertical = Control.GROW_DIRECTION_BOTH
	_badge.offset_right = -14
	_badge.visible = false
	add_child(_badge)
	mouse_entered.connect(func() -> void:
		if not disabled:
			Sfx.play(&"ui_hover")
		_animate())
	mouse_exited.connect(_animate)
	focus_entered.connect(func() -> void:
		if not is_hovered():
			Sfx.play(&"ui_hover")
		_animate())
	focus_exited.connect(_animate)
	pressed.connect(func() -> void: Sfx.play(&"ui_click"))
	resized.connect(func() -> void: pivot_offset = Vector2(0.0, size.y * 0.5))


## Gives button `b` smooth rounded faces in colour `base` instead of the theme's pixel bevel.
static func round_styles(b: Button, base: Color, radius: int) -> void:
	var pad := 16
	var normal := UITheme.round_box(Color(base, 0.94), base.darkened(0.45), 2, radius, pad, 4)
	normal.border_width_bottom = 4
	var hover := UITheme.round_box(base.lightened(0.12), Color(1, 1, 1, 0.75), 2, radius, pad, 6)
	hover.border_width_bottom = 4
	var pressed := UITheme.round_box(base.darkened(0.12), base.darkened(0.5), 2, radius, pad, 2)
	pressed.content_margin_top = pad + 2
	var focus := UITheme.round_box(Color(0, 0, 0, 0), Color(UITheme.ACCENT, 0.95), 3, radius + 3, pad)
	focus.draw_center = false
	focus.set_expand_margin_all(3)
	var off := UITheme.round_box(Color(base.darkened(0.5), 0.8), Color(0, 0, 0, 0.4), 2, radius, pad)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", off)


## Shows `value` in a gold pill on the right edge ("" hides it).
func set_badge(value: String) -> void:
	_badge.visible = not value.is_empty()
	_badge_label.text = value


func badge_text() -> String:
	return _badge_label.text if _badge.visible else ""


static func icon_texture(icon_id: String) -> Texture2D:
	if not _icons.has(icon_id):
		var rows := PackedStringArray(ICONS.get(icon_id, ICONS.play))
		_icons[icon_id] = UITheme._pixel_icon(rows, {"#": Color.WHITE}, ICON_SCALE)
	return _icons[icon_id]


func _animate() -> void:
	var target := 1.0 if selected or has_focus() or is_hovered() else 0.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_hot, _hot, target, 0.16)


func _set_hot(value: float) -> void:
	_hot = value
	# Containers own `position`; growing from the left-edge pivot pushes the tile to the right.
	scale = Vector2.ONE * (1.0 + GROW * value)
	queue_redraw()


func _draw() -> void:
	if _hot <= 0.0:
		return
	# Soft glow and a rounded accent pill sliding in from the left edge.
	if _glow == null:
		_glow = UITheme.round_box(Color(0, 0, 0, 0), Color.WHITE, 3, int(size.y * 0.32) + 4, 0)
		_glow.draw_center = false
		_pill = UITheme.round_box(Color.WHITE, Color(0, 0, 0, 0), 0, 4, 0)
	_glow.border_color = Color(_accent, 0.18 * _hot)
	draw_style_box(_glow, Rect2(Vector2.ZERO, size).grow(4.0))
	_pill.bg_color = Color(_accent, _hot)
	draw_style_box(_pill, Rect2(Vector2(-NUDGE * _hot - 2.0, size.y * 0.2), Vector2(6.0 * _hot, size.y * 0.6)))
	# Chevron on the right, unless a badge sits there.
	if not _badge.visible:
		var x := size.x - 24.0 + 6.0 * (1.0 - _hot)
		var y := size.y * 0.5
		var c := Color(get_theme_color(&"font_color"), _hot)
		draw_polyline(PackedVector2Array([Vector2(x, y - 8.0), Vector2(x + 8.0, y), Vector2(x, y + 8.0)]), c, 3.0, true)
