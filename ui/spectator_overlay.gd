class_name SpectatorOverlay
extends CanvasLayer
## Spectator's screen (owned by Spectator, canvas layer 11 like Tactical's overlay): a banner at
## the bottom centre (SPECTATING + the followed player's name in their team colour, or FREE
## CAMERA, and the keys from the player's own bindings) and, while following, a card at the
## bottom right in place of the Hud's weapon card: name, health bar (Palette.health) with the
## Overshield, held weapon and score (`Spectator.score_line`). A dead Tactical player gets only
## the card; Tactical's own spectator bar names the teammate.

var spectator: Spectator

var _banner: PanelContainer
var _title: Label
var _name: Label
var _keys: Label
var _card: PanelContainer
var _card_name: Label
var _hp_label: Label
var _hp_bar: ProgressBar
var _hp_fill: StyleBoxFlat
var _weapon: Label
var _score: Label


func _ready() -> void:
	layer = 11
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	_banner = _panel()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_banner.position.y -= 24
	root.add_child(_banner)
	var bv := VBoxContainer.new()
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_theme_constant_override("separation", 2)
	_banner.add_child(bv)
	_title = _label("SPECTATING", 16, Color(1.0, 0.85, 0.4))
	bv.add_child(_title)
	_name = _label("", 26)
	bv.add_child(_name)
	_keys = _label("", 15, Color(0.8, 0.84, 0.92))
	bv.add_child(_keys)

	# Bottom right, where a player's weapon card sits (a spectator has none); clear of the chat.
	_card = _panel()
	_card.custom_minimum_size.x = 300
	_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_right = -24
	_card.offset_bottom = -24
	root.add_child(_card)
	var cv := VBoxContainer.new()
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_theme_constant_override("separation", 4)
	_card.add_child(cv)
	_card_name = _label("", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	cv.add_child(_card_name)
	var hp_row := HBoxContainer.new()
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_theme_constant_override("separation", 10)
	cv.add_child(hp_row)
	_hp_label = _label("100", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_hp_label.custom_minimum_size.x = 64
	hp_row.add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.max_value = 1.0
	_hp_bar.step = 0.0
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(200, 12)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	_hp_fill = StyleBoxFlat.new()
	_hp_bar.add_theme_stylebox_override("background", bg)
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	hp_row.add_child(_hp_bar)
	_weapon = _label("", 17, Color(1.0, 0.92, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	cv.add_child(_weapon)
	_score = _label("", 15, Color(0.82, 0.86, 0.94), HORIZONTAL_ALIGNMENT_LEFT)
	cv.add_child(_score)


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.6)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _label(text: String, size: int, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Called by Spectator every frame it shows.
func refresh() -> void:
	var w := spectator.watched()
	var following := w.has("id")
	var dead_mode := bool(w.dead_mode)
	_banner.visible = not dead_mode
	_card.visible = following
	var k := Profile.key_text
	if int(w.view) == Spectator.View.FREE:
		_title.text = "SPECTATING"
		_name.text = "FREE CAMERA"
		_name.add_theme_color_override("font_color", Color.WHITE)
		var move := "LEFT STICK" if Profile.using_pad else "%s%s%s%s" % [k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right")]
		_keys.text = "%s fly  ·  %s / %s up / down  ·  %s fast  ·  %s follow a player  ·  %s follow view  ·  %s menu" % [
			move, k.call("jump"), k.call("crouch"), k.call("sprint"), k.call("fire"), k.call("spectate_view"), k.call("pause")]
	else:
		_title.text = "SPECTATING"
		_name.text = str(w.get("name", "NOBODY TO FOLLOW")).to_upper()
		var t := int(w.get("team", -1))
		_name.add_theme_color_override("font_color", Teams.color(t) if t >= 0 else Color.WHITE)
		_keys.text = "%s next player  ·  %s previous  ·  %s free camera  ·  %s menu" % [
			k.call("fire"), k.call("aim"), k.call("spectate_view"), k.call("pause")]
	if not following:
		return
	var team := int(w.team)
	_card_name.text = str(w.name)
	_card_name.add_theme_color_override("font_color", Teams.color(team) if team >= 0 else Color.WHITE)
	var frac := clampf(float(w.health) / maxf(1.0, float(w.max_hp)), 0.0, 1.0)
	_hp_bar.value = frac
	_hp_fill.bg_color = Palette.health(frac)
	_hp_label.text = str(int(ceil(float(w.health)))) if bool(w.alive) else "KO"
	if float(w.shield) > 0.0:
		_hp_label.text += " +%d" % ceili(float(w.shield))
	_weapon.text = str(w.weapon).to_upper() if bool(w.alive) else "DOWN"
	_score.text = str(w.score)
