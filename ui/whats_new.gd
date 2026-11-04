class_name WhatsNew
extends Control
## The update log, "WHAT'S NEW": one page per part of this version's update (`SECTIONS`), picked
## from a list on the left, with PREV / NEXT and GOT IT. The main menu opens it by itself once per
## game version (`should_show()`: Profile.seen_version differs from the project version; a new
## profile and a save from before the log have none) and from the home screen's version button.
## Closing it (GOT IT, Esc / B) records the version (`Profile.mark_version_seen`) and emits `closed`.
## When the update changes, edit HEADLINE, HIGHLIGHTS and SECTIONS.

signal closed

const HEADLINE := "TIMBUM 2.1"
const SUBTITLE := "CLIPS & GALLERY"
const HIGHLIGHTS: Array[String] = ["KILL CLIPS", "GALLERY", "CLIP STUDIO", "VIDEO EXPORT", "16 FILTERS"]
const PANEL_SIZE := Vector2(1080, 620)

## One page each: title, colour, pixel icon (11 x 11 rows, "#" filled), a one-line tagline and
## the bullets (RichTextLabel BBCode).
const SECTIONS: Array[Dictionary] = [
	{"title": "CLIPS & GALLERY", "color": Color("ffc531"), "tag": "Save your best kills, then turn them into videos.",
		"icon": ["###########", "#.#.#.#.#.#", "###########", "#.........#", "#......##.#", "#..#...##.#",
			"#.###.....#", "#######...#", "###########", "#.#.#.#.#.#", "###########"],
		"bullets": [
			"[b]Kill clips:[/b] switch on Clips in Settings > Gameplay, then [b]double-tap K[/b] after a kill to save it with the 10 seconds before it.",
			"[b]GALLERY:[/b] a new button on the home screen with every clip and photo you saved.",
			"[b]Clip studio:[/b] replay a clip from any angle (your eyes, chase, orbit or a drone you fly), at day, sunset or night, in any weather.",
			"[b]16 filters[/b] and 10 adjustments, trimming and slow motion.",
			"[b]Export[/b] MP4 videos up to 4K at 60 fps, rendered frame by frame so they are smooth whatever your frame rate, and pictures as PNG.",
			"Pick a page on the left, or press NEXT.",
		]},
	{"title": "KILL CLIPS", "color": Color("ff5a4f"), "tag": "Settings > Gameplay > Clips. Off until you switch it on.",
		"icon": [".....#.....", "...#####...", "..#..#..#..", ".#...#...#.", ".#...#...#.", "#####.#####",
			".#...#...#.", ".#...#...#.", "..#..#..#..", "...#####...", ".....#....."],
		"bullets": [
			"With Clips on, the game keeps the last 22 seconds of the match. After a kill, [b]double-tap K[/b] (up to 10 seconds later) to save that kill and the 10 seconds before it.",
			"A card says CLIP SAVED. A clip saved straight after the kill waits a moment to catch the victim falling.",
			"K still skips the kill cam while you are dead. Change the clip key in Settings > Controls: [b]Clip your last kill[/b]. It can also go on a controller button.",
			"A clip records everyone's moves, shots, grenades, rockets, explosions and hits, not a video, so it stays small and you can film it again from anywhere.",
			"Works in every mode with respawns, offline and online. Tactical has no clips.",
		]},
	{"title": "GALLERY", "color": Color("39d0ff"), "tag": "Home screen > GALLERY, beside LOCKER and SHOP.",
		"icon": ["...........", "###########", "#.........#", "#.........#", "#......##.#", "#..#...##.#",
			"#.###.....#", "#######...#", "###########", "...........", "..........."],
		"bullets": [
			"Every clip and photo as a card with a picture, newest first. Show ALL, CLIPS or PHOTOS.",
			"[b]OPEN[/b] loads it into the clip studio, [b]SHOW[/b] finds the file and [b]DELETE[/b] removes it.",
			"Photo mode (P in a match against bots) now also saves the scene around each photo: open it here to change the angle, time of day, weather and look of a photo you already took.",
			"Photos taken before 2.1 open too; only their look can change.",
			"VIDEO EXPORTS and PICTURE EXPORTS open the folders your exports go to (Movies/Timbum and Pictures/Timbum).",
		]},
	{"title": "CAMERAS", "color": Color("5bd15b"), "tag": "Film the clip from anywhere.",
		"icon": ["...........", "##.........", "#######..##", "#######.###", "###########", "###########",
			"###########", "#######.###", "#######..##", "...........", "..........."],
		"bullets": [
			"[b]POV:[/b] through the eyes, with the gun in hand, of you or any other player in the clip.",
			"[b]CHASE:[/b] behind the player you follow. [b]ORBIT:[/b] circling them; set its radius, angle and speed.",
			"[b]DRONE:[/b] hold the right mouse button on the picture and fly it like photo mode (WASD, Space and C, Shift faster, Q and E roll, the wheel zooms).",
			"Drone keys: move the playhead, place the drone, ADD KEY. The drone then flies smoothly through every key.",
			"Field of view and depth of field (the background blurs behind the player you follow).",
		]},
	{"title": "LOOK", "color": Color("ff5fd2"), "tag": "Time of day, weather and filters, on clips and photos.",
		"icon": ["....###....", "..##...##..", ".#..#.#..#.", "#.........#", "#..#...#..#", "#.........#",
			"#....##...#", ".#.......#.", "..##...##..", "....###....", "..........."],
		"bullets": [
			"[b]Time of day:[/b] day, sunset or night. [b]Weather:[/b] clear, rain, thunderstorm, snow, sandstorm or ash, whatever the match had.",
			"[b]16 filters:[/b] Cinematic, Black & white, Sepia, Noir, Vintage, Vibrant, Cool, Warm, Neon, Retro 8-bit, VHS, CRT, Thermal, Dream and Comic.",
			"[b]Adjustments:[/b] exposure, contrast, saturation, warmth, vignette, film grain, colour fringe, sharpen, pixelate and cinema bars.",
			"A TIMBUM watermark and a YOU tag over your player, if you want them. RESET LOOK puts everything back.",
		]},
	{"title": "TRIM & EXPORT", "color": Color("ff8a3d"), "tag": "Cut it, slow it down, save it.",
		"icon": ["...........", "#.........#", "##.......##", "###.....###", "####...####", "#####.#####",
			"####...####", "###.....###", "##.......##", "#.........#", "..........."],
		"bullets": [
			"The timeline shows the kill (red) and your drone keys. Drag the blue handles, or use SET IN / SET OUT (I / O), to trim.",
			"Play at 0.25x to 2x. Slow motion slows the effects and deepens the sound too. Space plays, the arrow keys step a frame.",
			"[b]EXPORT VIDEO:[/b] 720p, 1080p, 1440p or 4K at 30 or 60 fps, with the game's sound, as an MP4 in Movies/Timbum (on Windows an AVI unless ffmpeg is installed).",
			"Every frame is drawn at full quality however long it takes, so the video is smooth even if the game isn't. A small window shows it working and closes by itself.",
			"[b]SAVE FRAME / EXPORT PHOTO:[/b] a PNG of the picture with its look, in Pictures/Timbum.",
		]},
]

var _page := 0
var _tabs: Array[Button] = []
var _icon: TextureRect
var _title: Label
var _tag: Label
var _body: VBoxContainer
var _scroll: ScrollContainer
var _count: Label
var _prev: Button
var _next: Button
var _got_it: Button
var _panel: PanelContainer
var _page_tween: Tween


## The version this log belongs to (the project's).
static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## True until the player has closed the log of this version.
static func should_show() -> bool:
	return Profile.seen_version != current_version()


static func icon_for(index: int, scale := 3) -> Texture2D:
	var s: Dictionary = SECTIONS[index]
	return UITheme._pixel_icon(PackedStringArray(s.icon), {"#": s.color}, scale)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = UIKit.panel()
	_panel.add_theme_stylebox_override("panel",
		UITheme.round_box(UITheme.PANEL_SOLID, Color(UITheme.ACCENT, 0.45), 2, 22, 22, 12))
	_panel.custom_minimum_size = PANEL_SIZE
	center.add_child(_panel)
	var v := UIKit.vbox(14)
	_panel.add_child(v)
	v.add_child(_build_header())
	v.add_child(_build_highlights())
	var body := UIKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	body.add_child(_build_tabs())
	body.add_child(_build_page())
	v.add_child(_build_footer())
	show_page(0, false)
	_tabs[0].grab_focus.call_deferred()
	# Pop in.
	_panel.pivot_offset = PANEL_SIZE * 0.5
	_panel.scale = Vector2(0.94, 0.94)
	modulate.a = 0.0
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.25)
	t.tween_property(_panel, "scale", Vector2.ONE, 0.35)


func _build_header() -> Control:
	var h := UIKit.hbox(16)
	var words := UIKit.vbox(0)
	words.add_child(UIKit.label("WHAT'S NEW", &"SubheaderLabel"))
	var title := UIKit.label("%s  ·  %s" % [HEADLINE, SUBTITLE], &"HeaderLabel")
	words.add_child(title)
	h.add_child(words)
	h.add_child(UIKit.spacer())
	var version := UIKit.badge("VERSION %s" % current_version())
	version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(version)
	return h


func _build_highlights() -> Control:
	var h := UIKit.hbox(8)
	for text: String in HIGHLIGHTS:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme.chip_box(Color(UITheme.ACCENT, 0.16), Color(UITheme.ACCENT, 0.5), 12, 4))
		var l := UIKit.label(text, &"SmallLabel")
		l.add_theme_color_override("font_color", UITheme.ACCENT)
		chip.add_child(l)
		h.add_child(chip)
	return h


func _build_tabs() -> Control:
	var col := UIKit.vbox(6)
	col.custom_minimum_size.x = 286
	var group := ButtonGroup.new()
	for i: int in SECTIONS.size():
		var b := UIKit.button(str(SECTIONS[i].title), &"TabButton")
		b.toggle_mode = true
		b.button_group = group
		b.icon = icon_for(i)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 42
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_constant_override("h_separation", 10)
		b.name = "Tab%d" % i
		b.pressed.connect(show_page.bind(i))
		# Moving through the list with the keyboard or a controller turns the pages.
		b.focus_entered.connect(func() -> void:
			if _page != i:
				show_page(i))
		col.add_child(b)
		_tabs.append(b)
	return col


func _build_page() -> Control:
	var card := UIKit.panel()
	card.add_theme_stylebox_override("panel", UITheme.round_box(UITheme.INSET, Color(1, 1, 1, 0.08), 1, 16, 20))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(12)
	card.add_child(v)
	var head := UIKit.hbox(16)
	v.add_child(head)
	_icon = TextureRect.new()
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_icon.custom_minimum_size = Vector2(60, 60)
	head.add_child(_icon)
	var words := UIKit.vbox(2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(words)
	_title = UIKit.label("", &"HeaderLabel")
	_title.add_theme_font_size_override("font_size", 30)
	words.add_child(_title)
	_tag = UIKit.label("", &"DimLabel")
	_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(_tag)
	_scroll = UIKit.pad_friendly(ScrollContainer.new())
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	# One row per bullet: a square in the page's colour beside the wrapped text (hanging indent).
	_body = UIKit.vbox(12)
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	return card


func _bullet_row(text: String, color: Color) -> Control:
	var row := UIKit.hbox(12)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dot.add_theme_stylebox_override("panel", UITheme.bar_box(color, 2))
	# Drop the square to the middle of the first line.
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", 9)
	holder.add_child(dot)
	row.add_child(holder)
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.selection_enabled = false
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_font_size_override("normal_font_size", 17)
	line.add_theme_font_size_override("bold_font_size", 17)
	line.add_theme_font_override("bold_font", UITheme.heavy_font())
	line.add_theme_color_override("default_color", UITheme.TEXT)
	line.text = text
	row.add_child(line)
	return row


func _build_footer() -> Control:
	var h := UIKit.hbox(10)
	_count = UIKit.label("", &"DimLabel")
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_count)
	h.add_child(UIKit.spacer())
	_prev = UIKit.button("PREV")
	_prev.custom_minimum_size = Vector2(120, 46)
	MenuTile.round_styles(_prev, UITheme.BUTTON_SLATE)
	_prev.pressed.connect(func() -> void: show_page(_page - 1))
	h.add_child(_prev)
	_next = UIKit.button("NEXT")
	_next.custom_minimum_size = Vector2(120, 46)
	MenuTile.round_styles(_next, UITheme.BUTTON_SLATE)
	_next.pressed.connect(func() -> void: show_page(_page + 1))
	h.add_child(_next)
	_got_it = UIKit.button("GOT IT", &"PrimaryButton")
	_got_it.name = "GotIt"
	_got_it.custom_minimum_size = Vector2(200, 46)
	MenuTile.round_styles(_got_it, UITheme.BUTTON_GREEN)
	_got_it.pressed.connect(close)
	h.add_child(_got_it)
	return h


## Shows page `index` (clamped), marks its tab and rewires the focus neighbours (_wire_focus).
func show_page(index: int, animate := true) -> void:
	_page = clampi(index, 0, SECTIONS.size() - 1)
	var s: Dictionary = SECTIONS[_page]
	for j: int in _tabs.size():
		_tabs[j].set_pressed_no_signal(j == _page)
	_icon.texture = icon_for(_page, 5)
	_title.text = str(s.title)
	_title.add_theme_color_override("font_color", s.color)
	_tag.text = str(s.tag)
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for line: String in s.bullets:
		_body.add_child(_bullet_row(line, s.color))
	_scroll.scroll_vertical = 0
	_count.text = "%d / %d" % [_page + 1, SECTIONS.size()]
	_prev.disabled = _page == 0
	_next.disabled = _page == SECTIONS.size() - 1
	_wire_focus()
	if animate:
		if _page_tween != null:
			_page_tween.kill()
		_body.modulate.a = 0.0
		_page_tween = create_tween()
		_page_tween.tween_property(_body, "modulate:a", 1.0, 0.18)


## Keeps keyboard / controller focus inside the log: down the tab list (the last tab down, and
## any tab right, goes to the footer: NEXT, or GOT IT on the last page), along the footer's
## enabled buttons (left from the first goes back to the current tab, up from any of them too).
## A footer button that this page disables hands its focus on (PREV to NEXT, NEXT to GOT IT).
func _wire_focus() -> void:
	var foot: Button = _got_it if _next.disabled else _next
	var tab := _tabs[_page]
	for j: int in _tabs.size():
		var t := _tabs[j]
		t.focus_neighbor_left = t.get_path_to(t)
		t.focus_neighbor_right = t.get_path_to(foot)
		t.focus_neighbor_top = t.get_path_to(_tabs[j - 1] if j > 0 else t)
		t.focus_neighbor_bottom = t.get_path_to(_tabs[j + 1] if j + 1 < _tabs.size() else foot)
	var row: Array[Button] = []
	for b: Button in [_prev, _next, _got_it]:
		if not b.disabled:
			row.append(b)
	for b: Button in [_prev, _next, _got_it]:
		var k := row.find(b)
		b.focus_neighbor_top = b.get_path_to(tab)
		b.focus_neighbor_bottom = b.get_path_to(b)
		b.focus_neighbor_left = b.get_path_to(row[k - 1] if k > 0 else tab)
		b.focus_neighbor_right = b.get_path_to(row[k + 1] if k >= 0 and k + 1 < row.size() else b)
	if _prev.disabled and _prev.has_focus() or _next.disabled and _next.has_focus():
		foot.grab_focus.call_deferred()


func page() -> int:
	return _page


## GOT IT, Esc / B: remembers the version and goes away.
func close() -> void:
	if is_queued_for_deletion():
		return
	Profile.mark_version_seen(current_version())
	closed.emit()
	queue_free()
