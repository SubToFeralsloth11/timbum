class_name GunGameCard
extends CanvasLayer
## Gun Game's ladder card (top left, above the Hud): the local player's level out of the ladder,
## the gun they hold now and the next one, and a strip with one pip per step (climbed steps
## filled, the current one highlighted, the knife step last).

const GOLD := Color(1.0, 0.82, 0.3)
const KNIFE := Color(1.0, 0.45, 0.35)


## One pip per ladder step.
class LadderStrip extends Control:
	var count := 1
	var step := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var gap := 3.0
		var w := (size.x - gap * (count - 1)) / float(count)
		for i in count:
			var r := Rect2(Vector2(i * (w + gap), 0.0), Vector2(w, size.y))
			var col := Color(1, 1, 1, 0.14)
			if i < step:
				col = GOLD.darkened(0.15)
			elif i == step:
				col = KNIFE if i == count - 1 else Color.WHITE
			elif i == count - 1:
				col = Color(KNIFE, 0.35)
			draw_rect(r, col)

var game: GunGame
var _panel: PanelContainer
var _level: Label
var _now: Label
var _next: Label
var _strip: LadderStrip
var _shown := -1


func setup(p_game: GunGame) -> void:
	game = p_game


func _ready() -> void:
	layer = 11
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.6)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.border_color = Color(GOLD, 0.35)
	sb.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(16, 40)
	_panel.custom_minimum_size = Vector2(250, 0)
	_panel.theme = UITheme.get_theme()
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(_label("GUN GAME", 14, Color(0.7, 0.75, 0.85)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_level = _label("", 24, GOLD)
	head.add_child(_level)
	_now = _label("", 18, Color.WHITE)
	v.add_child(_now)
	_next = _label("", 15, Color(0.75, 0.85, 1.0))
	v.add_child(_next)
	_strip = LadderStrip.new()
	_strip.custom_minimum_size = Vector2(0, 8)
	_strip.count = game.steps.size()
	v.add_child(_strip)


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
	var p := game.world.local_player
	_panel.visible = p != null and not game.world.match_over
	if p == null:
		return
	var step := GunGame.step_of(p)
	if step == _shown:
		return
	_shown = step
	var last := game.last_step()
	_level.text = "LEVEL %d / %d" % [step + 1, last + 1]
	_now.text = "NOW   %s" % game.weapon_name(step).to_upper()
	if step >= last:
		_next.text = "A KNIFE KILL WINS"
		_next.add_theme_color_override("font_color", KNIFE)
	else:
		_next.text = "NEXT  %s" % game.weapon_name(step + 1).to_upper()
		_next.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_strip.step = step
	_strip.queue_redraw()
