class_name UIKit
## Small factory helpers so every menu builds widgets the same way (theme variations,
## hover/click sounds, pixel icons).

static var _coin: ImageTexture


## Creates a themed button. `click` false lets the caller play its own sound (buy/error).
static func button(text: String, variation: StringName = &"", click := true) -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	wire(b, click)
	return b


## Adds hover and click sounds to any button.
static func wire(b: BaseButton, click := true) -> void:
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Sfx.play(&"ui_hover"))
	if click:
		b.pressed.connect(func() -> void: Sfx.play(&"ui_click"))


static func label(text: String, variation: StringName = &"", align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	if variation != &"":
		l.theme_type_variation = variation
	return l


static func vbox(separation := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func panel(variation: StringName = &"") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != &"":
		p.theme_type_variation = variation
	return p


static func spacer(horizontal := true) -> Control:
	var c := Control.new()
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Pill-shaped tag ("OWNED", "EQUIPPED", ...).
static func badge(text: String, variation: StringName = &"BadgePanel") -> PanelContainer:
	var p := panel(variation)
	var l := label(text, &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_color", UITheme.TEXT)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Pixel-art coin icon.
static func coin_icon() -> Texture2D:
	if _coin == null:
		var rows := PackedStringArray([
			"..oooo..",
			".oyyyyo.",
			"oywyyyyo",
			"oywyddyo",
			"oyyyddyo",
			"oyyyyyyo",
			".oddddo.",
			"..oooo..",
		])
		var pal := {"o": Color("6b4300"), "y": Color("ffc531"), "w": Color("fff2b0"), "d": Color("d48d0a")}
		var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		for y in 8:
			for x in 8:
				var ch := rows[y][x]
				if pal.has(ch):
					img.set_pixel(x, y, pal[ch])
		_coin = ImageTexture.create_from_image(img)
	return _coin


## Coin icon + amount, used for balances and prices.
static func coin_amount(amount: int, size := 20) -> HBoxContainer:
	var h := hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = coin_icon()
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var l := label(format_int(amount), &"ValueLabel")
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UITheme.ACCENT)
	l.name = "Amount"
	h.add_child(l)
	return h


## 12345 -> "12,345"
static func format_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Row of solid colour blocks, e.g. a skin or outfit palette.
static func swatch(colors: Array[Color], block := 14) -> HBoxContainer:
	var h := hbox(2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in colors:
		var r := ColorRect.new()
		r.color = c
		r.custom_minimum_size = Vector2(block, block)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(r)
	return h


## Labelled stat bar: name, fill fraction 0..1, value text.
static func stat_bar(stat_name: String, fraction: float, value_text: String) -> HBoxContainer:
	var h := hbox(10)
	var n := label(stat_name.to_upper(), &"SmallLabel")
	n.custom_minimum_size.x = 92
	h.add_child(n)
	var bar := ProgressBar.new()
	bar.theme_type_variation = &"StatBar"
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = clampf(fraction, 0.04, 1.0)
	bar.custom_minimum_size = Vector2(120, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	var v := label(value_text, &"SmallLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_theme_color_override("font_color", UITheme.TEXT)
	v.custom_minimum_size.x = 56
	h.add_child(v)
	return h


## Normalised weapon stats for shop bars: [[name, fraction, text], ...].
static func weapon_stats(id: String) -> Array:
	var w: Dictionary = Data.WEAPONS[id]
	var pellets := int(w.get("pellets", 1))
	var dmg := float(w.damage) * pellets
	var dmg_text := "%d" % roundi(float(w.damage)) if pellets == 1 else "%dx%d" % [roundi(float(w.damage)), pellets]
	var reach: float = float(w.get("range", 0.0)) if w.slot == "melee" else minf(float(w.falloff_end), 120.0)
	var reach_text := "%.1fm" % reach if w.slot == "melee" else ("%dm" % roundi(reach) if reach < 120.0 else "MAX")
	var mag := int(w.mag)
	return [
		["Damage", dmg / 120.0, dmg_text],
		["Fire rate", float(w.rpm) / 900.0, "%d rpm" % roundi(float(w.rpm))],
		["Range", reach / 120.0, reach_text],
		["Mobility", (float(w.move_mult) - 0.8) / 0.32, "%d%%" % roundi(float(w.move_mult) * 100.0)],
		["Magazine", sqrt(mag / 100.0), "-" if mag == 0 else str(mag)],
	]


## Readable one-liner for catalog items that have no "desc" field.
static func item_description(category: String, id: String) -> String:
	var item: Dictionary = Data.catalog(category)[id]
	if item.has("desc"):
		return item.desc
	match category:
		"skins":
			var pattern: String = item.pattern
			var glow := " Glows in the dark." if float(item.glow) >= 0.5 else ""
			return "%s weapon finish. Applies to every gun you carry.%s" % [pattern.capitalize(), glow]
		"hats":
			return "Bare-headed and proud." if id == "none" else "Headwear everyone will see across the map."
		"outfits":
			return "%s style outfit with a matching blocky look." % String(item.pattern).capitalize()
	return ""


## Colours that best represent an item, for list swatches.
static func item_colors(category: String, id: String) -> Array[Color]:
	var item: Dictionary = Data.catalog(category)[id]
	match category:
		"skins":
			return [item.a, item.b]
		"outfits":
			return [item.skin, item.shirt, item.pants]
	return []
