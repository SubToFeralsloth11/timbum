class_name UITheme
## Builds the game-wide UI Theme in code: flat rounded buttons, soft translucent rounded panels
## with thin borders, bold system fonts. Everything is generated once and cached.
## Shared helpers keep every screen and the in-match HUD on one look: `round_box` (panels, cards),
## `hud_card` (translucent in-match cards), `bar_box` / `slim_bar` (rounded progress bars),
## `chip_box` (small pills).
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

## Size of one "pixel" of the procedural pixel icons, in UI pixels.
const PX := 3
## Corner radius of every button (flat rounded rectangles).
const BUTTON_RADIUS := 12
## Corner radius of big panels and of cards (menus and HUD).
const PANEL_RADIUS := 16
const CARD_RADIUS := 14

static var _theme: Theme
static var _heavy: SystemFont
static var _body: SystemFont
static var _spotlight: StyleBoxTexture


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

## Radial "studio spotlight" backdrop used behind 3D previews and item icons (shared): a soft
## radial gradient in a rounded rectangle (the corners keep their shape when it stretches).
static func spotlight_box() -> StyleBoxTexture:
	if _spotlight == null:
		const D := 128
		const R := 14.0
		var inner := Color(0.24, 0.3, 0.42, 0.95)
		var outer := Color(0.04, 0.05, 0.08, 0.95)
		var img := Image.create_empty(D, D, false, Image.FORMAT_RGBA8)
		var centre := Vector2(0.5, 0.42) * D
		for y in D:
			for x in D:
				var p := Vector2(x + 0.5, y + 0.5)
				var t := clampf(p.distance_to(centre) / (D * 0.85), 0.0, 1.0)
				var q := (p - Vector2(D, D) * 0.5).abs() - Vector2(D * 0.5 - R, D * 0.5 - R)
				var sd := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - R
				var c := inner.lerp(outer, t)
				c.a *= clampf(0.5 - sd, 0.0, 1.0)
				img.set_pixel(x, y, c)
		_spotlight = StyleBoxTexture.new()
		_spotlight.texture = ImageTexture.create_from_image(img)
		_spotlight.set_texture_margin_all(R + 2.0)
		_spotlight.set_content_margin_all(4)
	return _spotlight


## Smooth rounded panel / card face (anti-aliased curves, thin border, optional soft shadow).
static func round_box(bg: Color, border := Color(1, 1, 1, 0.08), border_w := 1, radius := CARD_RADIUS, pad := 16, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.corner_detail = 10
	s.anti_aliasing = true
	s.set_content_margin_all(pad)
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.5)
	return s


## Translucent in-match card (health, weapon, score, kill feed, toasts, death and results panels).
## `accent` tints the thin border (toasts, the active loadout preset).
static func hud_card(alpha := 0.5, pad := 10, radius := CARD_RADIUS, accent := Color(1, 1, 1, 0.07)) -> StyleBoxFlat:
	var s := round_box(Color(0.05, 0.06, 0.09, alpha), accent, 1, radius, pad)
	s.content_margin_left = pad + 4
	s.content_margin_right = pad + 4
	return s


## Rounded progress-bar track or fill (`ProgressBar` "background" / "fill" styles).
static func bar_box(color: Color, radius := 4) -> StyleBoxFlat:
	var s := round_box(color, Color(0, 0, 0, 0), 0, radius, 0)
	s.corner_detail = 6
	return s


## A slim ProgressBar (0..1) with a rounded track and fill.
static func slim_bar(color: Color, min_size: Vector2, track := Color(0, 0, 0, 0.45)) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = min_size
	b.max_value = 1.0
	b.step = 0.0
	b.show_percentage = false
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var r := maxi(2, int(min_size.y * 0.5))
	b.add_theme_stylebox_override("background", bar_box(track, r))
	b.add_theme_stylebox_override("fill", bar_box(color, r))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Small pill (tags, HUD chips, key hints).
static func chip_box(bg: Color, border := Color(1, 1, 1, 0.08), pad_h := 8, pad_v := 2) -> StyleBoxFlat:
	var s := round_box(bg, border, 1, 10, 0)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


static func _focus_box() -> StyleBoxFlat:
	var s := round_box(Color(0, 0, 0, 0), Color(ACCENT, 0.95), 2, BUTTON_RADIUS + 2, 0)
	s.draw_center = false
	s.set_expand_margin_all(2)
	return s


## Flat rounded-rectangle button face for `state` ("normal", "hover", "pressed", "disabled"):
## a solid fill in `base` with a thin lighter edge, brightening on hover. Every themed button and
## the menu tiles use it.
static func flat_button(base: Color, state: String, pad_h := 16, pad_v := 8, radius := BUTTON_RADIUS) -> StyleBoxFlat:
	var fill := base
	var edge := Color(base.lightened(0.25), 0.55)
	match state:
		"hover":
			fill = base.lightened(0.1)
			edge = Color(base.lightened(0.45), 0.8)
		"pressed":
			fill = base.darkened(0.14)
			edge = Color(base.darkened(0.3), 0.6)
		"disabled":
			var l := base.get_luminance()
			fill = Color(Color(l, l, l).darkened(0.45), 0.8)
			edge = Color(1, 1, 1, 0.06)
	var s := round_box(fill, edge, 1, radius, 0)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
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


## Smooth filled circle (slider grabber), anti-aliased, with a soft dark rim.
static func _disc_icon(d: int, color: Color) -> ImageTexture:
	var img := Image.create_empty(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(c.x - dist, 0.0, 1.0)
			var rim := clampf(dist - (c.x - 2.5), 0.0, 1.0)
			var col := color.lerp(color.darkened(0.45), rim)
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)


## Rounded check box, 22 px: a dark rounded square, or a green one with a white tick.
static func _check_icon(on: bool) -> ImageTexture:
	const D := 22
	const R := 6.0
	var img := Image.create_empty(D, D, false, Image.FORMAT_RGBA8)
	var fill := GOOD if on else Color("1b2030")
	var edge := GOOD.lightened(0.2) if on else Color("59627a")
	var a1 := Vector2(5.5, 11.5)
	var a2 := Vector2(9.5, 15.5)
	var a3 := Vector2(16.5, 6.5)
	for y in D:
		for x in D:
			var p := Vector2(x + 0.5, y + 0.5)
			# Signed distance to a rounded square.
			var q := (p - Vector2(D, D) * 0.5).abs() - Vector2(D * 0.5 - R, D * 0.5 - R)
			var sd := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - R
			var a := clampf(0.5 - sd, 0.0, 1.0)
			var col := fill.lerp(edge, clampf(sd + 2.0, 0.0, 1.0))
			if on:
				var tick := minf(_seg_dist(p, a1, a2), _seg_dist(p, a2, a3))
				col = col.lerp(Color.WHITE, clampf(2.0 - tick, 0.0, 1.0))
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return p.distance_to(a + (b - a) * t)


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
	t.set_stylebox("panel", "Panel", round_box(PANEL, Color(1, 1, 1, 0.08), 1, PANEL_RADIUS))
	t.set_stylebox("panel", "PanelContainer", round_box(PANEL, Color(1, 1, 1, 0.08), 1, PANEL_RADIUS))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", round_box(Color(0.1, 0.115, 0.16, 0.92), Color(1, 1, 1, 0.07), 1, CARD_RADIUS, 12))
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", round_box(INSET, Color(1, 1, 1, 0.05), 1, 12, 10))
	for pair: Array in [["BadgePanel", Color("2c3346")], ["GoldBadgePanel", Color("b07a10")], ["GoodBadgePanel", Color("2f7d2a")]]:
		t.set_type_variation(pair[0], "PanelContainer")
		t.set_stylebox("panel", pair[0], chip_box(pair[1], Color(1, 1, 1, 0.1)))

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
	t.set_stylebox("pressed", "TabButton", flat_button(BUTTON_GOLD, "normal", 14, 6))
	t.set_stylebox("hover_pressed", "TabButton", flat_button(BUTTON_GOLD, "hover", 14, 6))
	t.set_color("font_pressed_color", "TabButton", Color("2a1c00"))
	t.set_color("font_hover_pressed_color", "TabButton", Color("2a1c00"))
	t.set_color("font_hover_color", "TabButton", TEXT)
	# Small toggle chip (setup rule choices, preset actions, shop sub-tabs): pressed = selected (gold).
	t.set_type_variation("ChipButton", "Button")
	_button_type(t, "ChipButton", Color("2b3142"), 14, TEXT_DIM, 8, 6)
	t.set_stylebox("pressed", "ChipButton", flat_button(BUTTON_GOLD, "normal", 8, 6))
	t.set_stylebox("hover_pressed", "ChipButton", flat_button(BUTTON_GOLD, "hover", 8, 6))
	t.set_color("font_pressed_color", "ChipButton", Color("2a1c00"))
	t.set_color("font_hover_pressed_color", "ChipButton", Color("2a1c00"))
	t.set_color("font_hover_color", "ChipButton", TEXT)
	# Selectable flat card used by shop/locker/map lists.
	t.set_type_variation("CardButton", "Button")
	var cn := round_box(Color(0.1, 0.115, 0.16, 0.9), Color(1, 1, 1, 0.07), 1, CARD_RADIUS, 10)
	var ch := cn.duplicate() as StyleBoxFlat
	ch.bg_color = Color(0.15, 0.17, 0.23, 0.95)
	ch.border_color = Color(1, 1, 1, 0.22)
	var cp := cn.duplicate() as StyleBoxFlat
	cp.bg_color = Color(0.21, 0.18, 0.08, 0.95)
	cp.border_color = ACCENT
	cp.set_border_width_all(2)
	t.set_stylebox("normal", "CardButton", cn)
	t.set_stylebox("hover", "CardButton", ch)
	t.set_stylebox("pressed", "CardButton", cp)
	t.set_stylebox("hover_pressed", "CardButton", cp)
	t.set_stylebox("disabled", "CardButton", cn)
	t.set_stylebox("focus", "CardButton", _focus_box())

	# Line edits
	var le := round_box(Color(0.02, 0.025, 0.04, 0.7), Color(1, 1, 1, 0.08), 1, 10, 12)
	le.content_margin_top = 8
	le.content_margin_bottom = 8
	var lef := le.duplicate() as StyleBoxFlat
	lef.border_color = ACCENT
	lef.set_border_width_all(2)
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
	var track := bar_box(Color(0.02, 0.025, 0.04, 0.85), 4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := bar_box(ACCENT.darkened(0.1), 4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	t.set_icon("grabber", "HSlider", _disc_icon(20, Color("eeeae0")))
	t.set_icon("grabber_highlight", "HSlider", _disc_icon(20, ACCENT.lightened(0.3)))
	t.set_icon("grabber_disabled", "HSlider", _disc_icon(20, Color("9a968c")))
	t.set_constant("center_grabber", "HSlider", 1)

	# Check boxes
	var unchecked := _check_icon(false)
	var checked := _check_icon(true)
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
	var pop := round_box(PANEL_SOLID, Color(1, 1, 1, 0.1), 1, 12, 8)
	t.set_stylebox("panel", "PopupMenu", pop)
	var pop_hover := round_box(Color(ACCENT, 0.22), Color(ACCENT, 0.7), 1, 8, 4)
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
	t.set_stylebox("panel", "TooltipPanel", round_box(PANEL_SOLID, Color(ACCENT, 0.5), 1, 10, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# Progress bars
	var pb_bg := bar_box(Color(0.02, 0.025, 0.04, 0.85), 6)
	var pb_fill := bar_box(ACCENT_2, 6)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_font("font", "ProgressBar", heavy_font())
	t.set_font_size("font_size", "ProgressBar", 12)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_color("font_outline_color", "ProgressBar", OUTLINE)
	t.set_constant("outline_size", "ProgressBar", 4)
	t.set_type_variation("XPBar", "ProgressBar")
	t.set_stylebox("fill", "XPBar", bar_box(ACCENT_2, 6))
	t.set_type_variation("StatBar", "ProgressBar")
	t.set_stylebox("fill", "StatBar", bar_box(ACCENT, 6))

	# Scrollbars
	var sb_bg := bar_box(Color(0, 0, 0, 0.25), 4)
	sb_bg.content_margin_left = 6
	sb_bg.content_margin_right = 6
	var sb_grab := bar_box(Color(1, 1, 1, 0.22), 4)
	var sb_grab_hl := bar_box(Color(ACCENT, 0.75), 4)
	t.set_stylebox("scroll", "VScrollBar", sb_bg)
	t.set_stylebox("grabber", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_grab_hl)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_grab_hl)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# Separators
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.1)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)

	# Color picker button: a small flat rounded button.
	t.set_stylebox("normal", "ColorPickerButton", flat_button(Color("2b3142"), "normal", 6, 4))
	t.set_stylebox("hover", "ColorPickerButton", flat_button(Color("2b3142"), "hover", 6, 4))
	t.set_stylebox("pressed", "ColorPickerButton", flat_button(Color("2b3142"), "pressed", 6, 4))
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
	t.set_stylebox("normal", type, flat_button(base, "normal", pad_h, pad_v))
	t.set_stylebox("hover", type, flat_button(base, "hover", pad_h, pad_v))
	t.set_stylebox("pressed", type, flat_button(base, "pressed", pad_h, pad_v))
	t.set_stylebox("hover_pressed", type, flat_button(base, "pressed", pad_h, pad_v))
	t.set_stylebox("disabled", type, flat_button(base, "disabled", pad_h, pad_v))
	t.set_font("font", type, heavy_font())
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, font_color)
	t.set_color("font_hover_color", type, font_color if font_color != TEXT else Color.WHITE)
	t.set_color("font_pressed_color", type, font_color)
	t.set_color("font_hover_pressed_color", type, font_color)
	t.set_color("font_focus_color", type, font_color)
	t.set_color("font_disabled_color", type, Color(TEXT_DIM, 0.55))
	t.set_color("font_outline_color", type, Color(0, 0, 0, 0.55) if font_color == TEXT else Color(1, 1, 1, 0.2))
	t.set_constant("outline_size", type, 2 if font_color == TEXT else 0)
	t.set_constant("h_separation", type, 8)
