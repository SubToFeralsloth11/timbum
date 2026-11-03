class_name ChamberCard
extends CanvasLayer
## One in the Chamber's card (top left, above the Hud): the local player's lives as hearts (lost
## ones as outlines), their rounds as cartridges (the chambered one first) and how many players
## are still in. Out of lives it says so instead.

const HEART := Color(1.0, 0.33, 0.38)
const BRASS := Color(1.0, 0.8, 0.35)
## Cartridges drawn before the count switches to "+N".
const MAX_ROUNDS_DRAWN := 6


## A row of hearts: `full` filled out of `total`.
class Hearts extends Control:
	var total := 3
	var full := 3

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size.y
		for i in total:
			var c := Vector2(i * (s + 6.0) + s * 0.5, s * 0.5)
			_heart(c, s * 0.5, HEART if i < full else Color(1, 1, 1, 0.22), i < full)

	func _heart(c: Vector2, r: float, col: Color, filled: bool) -> void:
		var pts := PackedVector2Array()
		for k in 33:
			# The classic heart curve, scaled to radius r.
			var t := TAU * k / 32.0
			var x := 16.0 * pow(sin(t), 3)
			var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
			pts.append(c + Vector2(x, y + 2.0) * (r / 17.0))
		if filled:
			draw_colored_polygon(pts, col)
			draw_polyline(pts, col.darkened(0.45), 1.5, true)
		else:
			draw_polyline(pts, col, 2.0, true)


## Cartridges: the chambered round (if any) first, then the reserve.
class Rounds extends Control:
	var chamber := 1
	var reserve := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := size.y
		var w := h * 0.42
		var n := mini(chamber + reserve, MAX_ROUNDS_DRAWN)
		if chamber + reserve == 0:
			_round(Vector2.ZERO, w, h, Color(1, 1, 1, 0.2), false)
			return
		for i in n:
			_round(Vector2(i * (w + 5.0), 0.0), w, h, BRASS if i < chamber else BRASS.darkened(0.35), true)

	func _round(at: Vector2, w: float, h: float, col: Color, filled: bool) -> void:
		var tip := h * 0.36
		var body := Rect2(at + Vector2(0, tip), Vector2(w, h - tip))
		var nose := PackedVector2Array([at + Vector2(0, tip), at + Vector2(w * 0.5, 0), at + Vector2(w, tip)])
		if filled:
			draw_rect(body, col)
			draw_colored_polygon(nose, Color(0.78, 0.5, 0.3) if col == BRASS else Color(0.55, 0.38, 0.25))
			draw_rect(Rect2(body.position + Vector2(0, body.size.y - 3.0), Vector2(w, 3.0)), col.darkened(0.3))
		else:
			draw_rect(body, col, false, 1.5)
			draw_polyline(nose, col, 1.5)

var game: OneInTheChamber
var _panel: PanelContainer
var _hearts: Hearts
var _rounds: Rounds
var _rounds_label: Label
var _left: Label
var _status: Label


func setup(p_game: OneInTheChamber) -> void:
	game = p_game


func _ready() -> void:
	layer = 11
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.hud_card(0.5, 10, UITheme.CARD_RADIUS, Color(HEART, 0.35)))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(16, 40)
	_panel.custom_minimum_size = Vector2(250, 0)
	_panel.theme = UITheme.get_theme()
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	_panel.add_child(v)
	v.add_child(_label("ONE IN THE CHAMBER", 14, Color(0.7, 0.75, 0.85)))
	var lives_row := HBoxContainer.new()
	lives_row.add_theme_constant_override("separation", 10)
	v.add_child(lives_row)
	lives_row.add_child(_fixed(_label("LIVES", 13, Color(0.75, 0.8, 0.9))))
	_hearts = Hearts.new()
	_hearts.custom_minimum_size = Vector2(0, 22)
	_hearts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lives_row.add_child(_hearts)
	var rounds_row := HBoxContainer.new()
	rounds_row.add_theme_constant_override("separation", 10)
	v.add_child(rounds_row)
	rounds_row.add_child(_fixed(_label("ROUNDS", 13, Color(0.75, 0.8, 0.9))))
	_rounds = Rounds.new()
	_rounds.custom_minimum_size = Vector2(0, 24)
	_rounds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rounds_row.add_child(_rounds)
	_rounds_label = _label("", 18, BRASS)
	rounds_row.add_child(_rounds_label)
	var left_row := HBoxContainer.new()
	left_row.add_theme_constant_override("separation", 10)
	v.add_child(left_row)
	left_row.add_child(_fixed(_label("PLAYERS", 13, Color(0.75, 0.8, 0.9))))
	_left = _label("", 16, Color.WHITE)
	left_row.add_child(_left)
	_status = _label("", 14, HEART)
	v.add_child(_status)


func _fixed(l: Label) -> Label:
	l.custom_minimum_size.x = 62
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


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
	var w := game.world
	_panel.visible = not w.match_over and not w.rules.is_practice()
	if not _panel.visible:
		return
	var n := game.players_in().size()
	_left.text = "%d still in" % n
	var p := w.local_player
	var lives := OneInTheChamber.lives_of(p)
	var out := p == null or lives <= 0
	_hearts.get_parent().visible = p != null
	_rounds.get_parent().visible = not out
	if _hearts.total != game.start_lives() or _hearts.full != lives:
		_hearts.total = game.start_lives()
		_hearts.full = lives
		_hearts.queue_redraw()
	if not out:
		var a: Vector2i = p.ammo.get(OneInTheChamber.GUN, Vector2i.ZERO)
		if _rounds.chamber != a.x or _rounds.reserve != a.y:
			_rounds.chamber = a.x
			_rounds.reserve = a.y
			_rounds.queue_redraw()
		_rounds_label.text = str(a.x + a.y)
	if p == null:
		_status.text = "SPECTATING"
	elif out:
		_status.text = "OUT  ·  SPECTATING THE REST"
	elif lives == 1:
		_status.text = "LAST LIFE"
	else:
		_status.text = ""
	_status.visible = not _status.text.is_empty()
