class_name UITheme
## Builds the game-wide UI Theme in code: chunky pixel-bevel buttons, dark translucent
## chamfered panels, bold system fonts. Everything is generated once and cached.
##
## Type variations (set `theme_type_variation` on a control):
##   Button: "PrimaryButton" (green), "GoldButton", "DangerButton", "TabButton" (toggle),
##           "CardButton" (flat selectable card), "IconButton" (small square)
##   Label: "TitleLabel", "HeaderLabel", "SubheaderLabel", "DimLabel", "SmallLabel", "ValueLabel"
##   PanelContainer: "CardPanel", "InsetPanel", "BadgePanel", "GoldBadgePanel", "GoodBadgePanel"
##   ProgressBar: "XPBar", "StatBar"

const ACCENT := Color("ffc531")
const ACCENT_2 := Color("39d0ff")
const GOOD := Color("5bd15b")
const BAD := Color("ff5a4f")
const TEXT := Color("f6f2e6")
const TEXT_DIM := Color("a6abb7")
const PANEL := Color(0.055, 0.065, 0.095, 0.86)
const PANEL_SOLID := Color(0.07, 0.08, 0.11, 0.97)
const INSET := Color(0.02, 0.025, 0.04, 0.6)
const OUTLINE := Color(0.02, 0.02, 0.035)

const BUTTON_SLATE := Color("3d4558")
const BUTTON_GREEN := Color("4aa83a")
const BUTTON_GOLD := Color("e3a21a")
const BUTTON_RED := Color("c23b30")

## Size of one "pixel" of the bevelled pixel-art styleboxes, in UI pixels.
const PX := 3

static var _theme: Theme
static var _heavy: SystemFont
static var _body: SystemFont


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Heavy display font (titles, buttons, numbers).
static func heavy_font() -> Font:
	if _heavy == null:
		_heavy = SystemFont.new()
		_heavy.font_names = PackedStringArray(["Arial Black", "Impact", "Helvetica Neue", "Arial", "sans-serif"])
		_heavy.font_weight = 900
		_heavy.hinting = TextServer.HINTING_LIGHT
	return _heavy


## Body font (descriptions, fields).
static func body_font() -> Font:
	if _body == null:
		_body = SystemFont.new()
		_body.font_names = PackedStringArray(["Helvetica Neue", "Arial", "Segoe UI", "Roboto", "sans-serif"])
		_body.font_weight = 700
		_body.hinting = TextServer.HINTING_LIGHT
	return _body


# ------------------------------------------------------------------ styleboxes

## Dark chamfered panel (corner_detail 1 gives cut, pixel-like corners).
static func panel_box(bg := PANEL, border := Color(1, 1, 1, 0.08), border_w := 2, radius := 4, pad := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.corner_detail = 1
	s.anti_aliasing = false
	s.set_content_margin_all(pad)
	return s


## Pixel-art bevelled button texture: dark outline, light top/left, dark bottom/right,
## subtle dithered noise in the face. `pressed` inverts the bevel.
static func bevel_box(base: Color, outline := OUTLINE, pressed := false, pad_h := 16, pad_v := 8) -> StyleBoxTexture:
	const U := 16
	var img := Image.create_empty(U * PX, U * PX, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hi := base.lightened(0.28)
	var hi_side := base.lightened(0.14)
	var lo := base.darkened(0.42)
	var lo_side := base.darkened(0.22)
	for y in U:
		for x in U:
			var c: Color
			if x == 0 or y == 0 or x == U - 1 or y == U - 1:
				c = outline
			elif pressed:
				if y <= 2:
					c = lo
				elif x == 1:
					c = lo_side
				elif y == U - 2:
					c = hi_side
				else:
					c = base.darkened(0.08)
			else:
				if y == 1:
					c = hi
				elif y >= U - 3:
					c = lo
				elif x == 1:
					c = hi_side
				elif x == U - 2:
					c = lo_side
				else:
					c = base
			if c != outline:
				var n := rng.randf_range(-0.035, 0.035)
				c = Color(clampf(c.r + n, 0, 1), clampf(c.g + n, 0, 1), clampf(c.b + n, 0, 1), c.a)
			img.fill_rect(Rect2i(x * PX, y * PX, PX, PX), c)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	s.texture_margin_left = 2 * PX
	s.texture_margin_right = 2 * PX
	s.texture_margin_top = (3 if pressed else 2) * PX
	s.texture_margin_bottom = (2 if pressed else 3) * PX
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v + (3 if pressed else 0)
	s.content_margin_bottom = pad_v + (0 if pressed else 3)
	return s


static func _focus_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = Color(ACCENT, 0.9)
	s.set_border_width_all(2)
	s.set_expand_margin_all(3)
	s.corner_detail = 1
	s.set_corner_radius_all(3)
	return s


static func _pixel_icon(rows: PackedStringArray, palette: Dictionary, scale := PX) -> ImageTexture:
	var h := rows.size()
	var w := rows[0].length()
	var img := Image.create_empty(w * scale, h * scale, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var ch := rows[y][x]
			if palette.has(ch):
				img.fill_rect(Rect2i(x * scale, y * scale, scale, scale), palette[ch])
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ theme

static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 17

	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 2)
	_label_variation(t, "TitleLabel", heavy_font(), 64, TEXT, 10)
	_label_variation(t, "HeaderLabel", heavy_font(), 34, TEXT, 6)
	_label_variation(t, "SubheaderLabel", heavy_font(), 20, ACCENT, 4)
	_label_variation(t, "ValueLabel", heavy_font(), 22, TEXT, 4)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", TEXT_DIM)
	t.set_font_size("font_size", "DimLabel", 15)
	t.set_type_variation("SmallLabel", "Label")
	t.set_color("font_color", "SmallLabel", TEXT_DIM)
	t.set_font_size("font_size", "SmallLabel", 13)
	t.set_font("font", "SmallLabel", heavy_font())

	# Panels
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_type_variation("CardPanel", "PanelContainer")
	var card := panel_box(Color(0.1, 0.115, 0.16, 0.92), Color(1, 1, 1, 0.06), 2, 4, 12)
	card.border_width_bottom = 5
	card.border_color = Color(0, 0, 0, 0.45)
	t.set_stylebox("panel", "CardPanel", card)
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", panel_box(INSET, Color(0, 0, 0, 0.35), 2, 3, 10))
	for pair: Array in [["BadgePanel", Color("2c3346")], ["GoldBadgePanel", Color("b07a10")], ["GoodBadgePanel", Color("2f7d2a")]]:
		t.set_type_variation(pair[0], "PanelContainer")
		var b := panel_box(pair[1], Color(0, 0, 0, 0.5), 2, 3, 0)
		b.content_margin_left = 8
		b.content_margin_right = 8
		b.content_margin_top = 2
		b.content_margin_bottom = 2
		t.set_stylebox("panel", pair[0], b)

	# Buttons
	_button_type(t, "Button", BUTTON_SLATE, 19, TEXT)
	t.set_stylebox("focus", "Button", _focus_box())
	for v: Array in [["PrimaryButton", BUTTON_GREEN, TEXT], ["GoldButton", BUTTON_GOLD, Color("2a1c00")], ["DangerButton", BUTTON_RED, TEXT]]:
		t.set_type_variation(v[0], "Button")
		_button_type(t, v[0], v[1], 19, v[2])
	t.set_type_variation("IconButton", "Button")
	_button_type(t, "IconButton", BUTTON_SLATE, 17, TEXT, 10, 4)
	# Toggle tab buttons: pressed = selected (gold).
	t.set_type_variation("TabButton", "Button")
	_button_type(t, "TabButton", Color("2b3142"), 17, TEXT_DIM, 14, 6)
	t.set_stylebox("pressed", "TabButton", bevel_box(BUTTON_GOLD, OUTLINE, false, 14, 6))
	t.set_stylebox("hover_pressed", "TabButton", bevel_box(BUTTON_GOLD.lightened(0.1), OUTLINE, false, 14, 6))
	t.set_color("font_pressed_color", "TabButton", Color("2a1c00"))
	t.set_color("font_hover_pressed_color", "TabButton", Color("2a1c00"))
	t.set_color("font_hover_color", "TabButton", TEXT)
	# Selectable flat card used by shop/locker/map lists.
	t.set_type_variation("CardButton", "Button")
	var cn := panel_box(Color(0.1, 0.115, 0.16, 0.92), Color(0, 0, 0, 0.45), 2, 4, 10)
	cn.border_width_bottom = 5
	var ch := cn.duplicate() as StyleBoxFlat
	ch.bg_color = Color(0.15, 0.17, 0.23, 0.95)
	ch.border_color = Color(1, 1, 1, 0.25)
	var cp := cn.duplicate() as StyleBoxFlat
	cp.bg_color = Color(0.2, 0.17, 0.06, 0.95)
	cp.border_color = ACCENT
	cp.set_border_width_all(3)
	cp.border_width_bottom = 5
	t.set_stylebox("normal", "CardButton", cn)
	t.set_stylebox("hover", "CardButton", ch)
	t.set_stylebox("pressed", "CardButton", cp)
	t.set_stylebox("hover_pressed", "CardButton", cp)
	t.set_stylebox("disabled", "CardButton", cn)
	t.set_stylebox("focus", "CardButton", _focus_box())

	# Line edits
	var le := panel_box(Color(0.02, 0.025, 0.04, 0.75), Color(0, 0, 0, 0.6), 2, 3, 10)
	le.border_width_top = 4
	le.content_margin_top = 8
	le.content_margin_bottom = 8
	var lef := le.duplicate() as StyleBoxFlat
	lef.border_color = ACCENT
	lef.set_border_width_all(2)
	lef.border_width_top = 4
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_font("font", "LineEdit", heavy_font())
	t.set_font_size("font_size", "LineEdit", 18)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_constant("caret_width", "LineEdit", 3)

	# Sliders
	var track := panel_box(Color(0.02, 0.025, 0.04, 0.85), Color(0, 0, 0, 0.6), 2, 2, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := panel_box(ACCENT.darkened(0.1), Color(0, 0, 0, 0.6), 2, 2, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	var grab_rows := PackedStringArray(["oooooo", "ohhhho", "ohffdo", "ohffdo", "ohffdo", "ohffdo", "oddddo", "oooooo"])
	var grab_pal := {"o": OUTLINE, "h": Color.WHITE, "f": Color("e8e3d6"), "d": Color("9a968c")}
	var grab_hl := {"o": OUTLINE, "h": Color.WHITE, "f": ACCENT.lightened(0.4), "d": ACCENT.darkened(0.2)}
	t.set_icon("grabber", "HSlider", _pixel_icon(grab_rows, grab_pal))
	t.set_icon("grabber_highlight", "HSlider", _pixel_icon(grab_rows, grab_hl))
	t.set_icon("grabber_disabled", "HSlider", _pixel_icon(grab_rows, grab_pal))
	t.set_constant("center_grabber", "HSlider", 1)

	# Check boxes
	var box_pal := {"o": OUTLINE, "g": Color("59627a"), "i": Color("1b2030"), "s": Color("10131c"),
		"c": GOOD, "h": GOOD.lightened(0.45), "d": GOOD.darkened(0.35), "w": Color.WHITE}
	var unchecked := _pixel_icon(PackedStringArray([
		"oooooooooo", "oggggggggo", "ogssssssgo", "ogsiiiiigo", "ogsiiiiigo", "ogsiiiiigo", "ogsiiiiigo",
		"ogsiiiiigo", "oggggggggo", "oooooooooo"]), box_pal)
	var checked := _pixel_icon(PackedStringArray([
		"oooooooooo", "ohhhhhhhho", "ohcccccwco", "ohccccwwco", "ohwccwwcco", "ohwwwwccco",
		"ohcwwcccco", "ohccccccco", "oddddddddo", "oooooooooo"]), box_pal)
	for type in ["CheckBox", "CheckButton"]:
		t.set_icon("unchecked", type, unchecked)
		t.set_icon("checked", type, checked)
		t.set_icon("unchecked_disabled", type, unchecked)
		t.set_icon("checked_disabled", type, checked)
		t.set_icon("unchecked_mirrored", type, unchecked)
		t.set_icon("checked_mirrored", type, checked)
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(4)
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(st, type, empty)
		t.set_stylebox("focus", type, _focus_box())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, ACCENT)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, ACCENT)
		t.set_constant("h_separation", type, 10)

	# Option buttons + popups
	_button_type(t, "OptionButton", Color("2b3142"), 17, TEXT, 14, 6)
	t.set_icon("arrow", "OptionButton", _pixel_icon(PackedStringArray(["fffffff", ".fffff.", "..fff..", "...f..."]),
		{"f": ACCENT}, 2))
	t.set_constant("arrow_margin", "OptionButton", 10)
	t.set_stylebox("focus", "OptionButton", _focus_box())
	var pop := panel_box(PANEL_SOLID, Color(0, 0, 0, 0.8), 2, 3, 6)
	t.set_stylebox("panel", "PopupMenu", pop)
	var pop_hover := panel_box(Color(ACCENT, 0.25), Color(ACCENT, 0.8), 1, 2, 4)
	t.set_stylebox("hover", "PopupMenu", pop_hover)
	t.set_font("font", "PopupMenu", heavy_font())
	t.set_font_size("font_size", "PopupMenu", 16)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT)
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 10)
	t.set_icon("radio_checked", "PopupMenu", _pixel_icon(PackedStringArray(["ffff", "ffff", "ffff", "ffff"]), {"f": ACCENT}, 2))
	t.set_icon("radio_unchecked", "PopupMenu", _pixel_icon(PackedStringArray(["oooo", "o..o", "o..o", "oooo"]), {"o": TEXT_DIM}, 2))
	t.set_icon("checked", "PopupMenu", t.get_icon("radio_checked", "PopupMenu"))
	t.set_icon("unchecked", "PopupMenu", t.get_icon("radio_unchecked", "PopupMenu"))
	t.set_stylebox("panel", "TooltipPanel", panel_box(PANEL_SOLID, Color(ACCENT, 0.6), 2, 3, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# Progress bars
	var pb_bg := panel_box(Color(0.02, 0.025, 0.04, 0.85), Color(0, 0, 0, 0.7), 2, 2, 0)
	var pb_fill := panel_box(ACCENT_2, Color(0, 0, 0, 0), 0, 1, 0)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_font("font", "ProgressBar", heavy_font())
	t.set_font_size("font_size", "ProgressBar", 12)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_color("font_outline_color", "ProgressBar", OUTLINE)
	t.set_constant("outline_size", "ProgressBar", 4)
	t.set_type_variation("XPBar", "ProgressBar")
	var xp_fill := panel_box(ACCENT_2, Color(1, 1, 1, 0.0), 0, 1, 0)
	xp_fill.border_width_top = 3
	xp_fill.border_color = ACCENT_2.lightened(0.45)
	t.set_stylebox("fill", "XPBar", xp_fill)
	t.set_type_variation("StatBar", "ProgressBar")
	var stat_fill := panel_box(ACCENT, Color(0, 0, 0, 0), 0, 1, 0)
	stat_fill.border_width_top = 2
	stat_fill.border_color = ACCENT.lightened(0.4)
	t.set_stylebox("fill", "StatBar", stat_fill)

	# Scrollbars
	var sb_bg := panel_box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 2, 0)
	sb_bg.content_margin_left = 6
	sb_bg.content_margin_right = 6
	var sb_grab := panel_box(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 0, 2, 0)
	var sb_grab_hl := panel_box(Color(ACCENT, 0.75), Color(0, 0, 0, 0), 0, 2, 0)
	t.set_stylebox("scroll", "VScrollBar", sb_bg)
	t.set_stylebox("grabber", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_grab_hl)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_grab_hl)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# Separators
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.1)
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)

	# Color picker button keeps the bevel look.
	t.set_stylebox("normal", "ColorPickerButton", bevel_box(Color("2b3142"), OUTLINE, false, 6, 4))
	t.set_stylebox("hover", "ColorPickerButton", bevel_box(Color("3b4256"), Color(ACCENT, 0.9), false, 6, 4))
	t.set_stylebox("pressed", "ColorPickerButton", bevel_box(Color("2b3142"), OUTLINE, true, 6, 4))
	t.set_stylebox("focus", "ColorPickerButton", _focus_box())
	t.set_stylebox("panel", "PopupPanel", pop)
	return t


static func _label_variation(t: Theme, name: StringName, font: Font, size: int, color: Color, outline: int) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)
	t.set_color("font_outline_color", name, OUTLINE)
	t.set_constant("outline_size", name, outline)
	t.set_color("font_shadow_color", name, Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_y", name, maxi(2, outline / 2))


static func _button_type(t: Theme, type: StringName, base: Color, size: int, font_color: Color, pad_h := 18, pad_v := 8) -> void:
	t.set_stylebox("normal", type, bevel_box(base, OUTLINE, false, pad_h, pad_v))
	t.set_stylebox("hover", type, bevel_box(base.lightened(0.14), Color(0.95, 0.92, 0.82), false, pad_h, pad_v))
	t.set_stylebox("pressed", type, bevel_box(base.darkened(0.1), OUTLINE, true, pad_h, pad_v))
	t.set_stylebox("hover_pressed", type, bevel_box(base, OUTLINE, true, pad_h, pad_v))
	var grey := Color(base.get_luminance(), base.get_luminance(), base.get_luminance()).darkened(0.35)
	t.set_stylebox("disabled", type, bevel_box(Color(grey, 0.85), Color(OUTLINE, 0.7), false, pad_h, pad_v))
	t.set_font("font", type, heavy_font())
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, font_color)
	t.set_color("font_hover_color", type, font_color if font_color != TEXT else Color.WHITE)
	t.set_color("font_pressed_color", type, font_color)
	t.set_color("font_hover_pressed_color", type, font_color)
	t.set_color("font_focus_color", type, font_color)
	t.set_color("font_disabled_color", type, Color(TEXT_DIM, 0.55))
	t.set_color("font_outline_color", type, Color(0, 0, 0, 0.55) if font_color == TEXT else Color(1, 1, 1, 0.2))
	t.set_constant("outline_size", type, 4 if font_color == TEXT else 0)
	t.set_constant("h_separation", type, 8)
