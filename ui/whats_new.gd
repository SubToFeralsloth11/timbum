class_name WhatsNew
extends Control
## The update log, "WHAT'S NEW": one page per part of this version's update (`SECTIONS`), picked
## from a list on the left, with PREV / NEXT and GOT IT. The main menu opens it by itself once per
## game version (`should_show()`: Profile.seen_version differs from the project version; a new
## profile and a save from before the log have none) and from the home screen's version button.
## Closing it (GOT IT, Esc / B) records the version (`Profile.mark_version_seen`) and emits `closed`.
## When the update changes, edit HEADLINE, HIGHLIGHTS and SECTIONS.

signal closed

const HEADLINE := "TIMBUM 2.0"
const SUBTITLE := "THE BIG BLOCK UPDATE"
const HIGHLIGHTS: Array[String] = ["3 NEW WEAPONS", "2 NEW MODES", "2 NEW MAPS", "WEATHER", "SEASON PASS"]
const PANEL_SIZE := Vector2(1080, 620)

## One page each: title, colour, pixel icon (11 x 11 rows, "#" filled), a one-line tagline and
## the bullets (RichTextLabel BBCode).
const SECTIONS: Array[Dictionary] = [
	{"title": "THE BIGGEST UPDATE YET", "color": Color("ffc531"), "tag": "Everything new in Timbum 2.0, at a glance.",
		"icon": [".....#.....", "....###....", "....###....", "###########", ".#########.", "..#######..",
			"...#####...", "..###.###..", "..##...##..", ".##.....##.", ".#.......#."],
		"bullets": [
			"[b]Three new weapons:[/b] the Rail Cube charge railgun, the Cube Lobber grenade launcher and the Pixel Scythe.",
			"[b]Two new modes:[/b] Capture the Flag and One in the Chamber. Timbum now has 8 modes.",
			"[b]Two new maps:[/b] Moon Base, floating in space, and Volcano Forge, around a lava lake.",
			"[b]Weather:[/b] rain, thunderstorms, snowfall, sandstorms and falling ash.",
			"[b]Season 1: Block Party:[/b] a free 30-tier pass with 12 exclusive cosmetics.",
			"Plus a pile of fixes and polish. Pick a page on the left, or press NEXT.",
		]},
	{"title": "NEW WEAPONS", "color": Color("39d0ff"), "tag": "Three new ways to win a fight. Find them in the shop.",
		"icon": ["...........", "...........", "###########", "###########", "#########..", "####.#.....",
			"###..#.....", "###........", "###........", "...........", "..........."],
		"bullets": [
			"[b]Rail Cube[/b] (900 coins): hold fire to charge, let go to fire a cyan beam that goes through up to [b]three players[/b] in a line. A full charge does 90 to the body and kills with a headshot.",
			"While you charge, the coils glow, a whine rises and a ring fills around your crosshair. Everyone else sees the glow and hears the whine too.",
			"[b]Cube Lobber[/b] (800 coins): a grenade launcher with a 6-round drum. Its grenades bounce and blow after 1.6 seconds, or straight away when they hit a player. In Demolition they break blocks.",
			"[b]Pixel Scythe[/b] (700 coins): a long, slow melee sweep with 2.9 m reach that catches players a little off your aim. Two hits kill.",
			"All three have their own models, sounds, kill-feed icons, skins, charms, mastery camos and stats. Try them at the Firing Range console.",
			"The Rail Cube and Cube Lobber join the Gun Game ladder (now 21 guns), and bots use all three.",
		]},
	{"title": "CAPTURE THE FLAG", "color": Color("5bd15b"), "tag": "New team mode on every deathmatch map.",
		"icon": [".#.........", ".########..", ".#########.", ".#########.", ".########..", ".#.........",
			".#.........", ".#.........", ".#.........", "###........", "###........"],
		"bullets": [
			"Grab the enemy flag and run it onto your own stand while your flag is home to score. First to [b]1, 3 or 5 captures[/b] wins.",
			"The carrier wears the flag on their back, runs a little slower and can't use the grapple hook. Kill them and the flag drops.",
			"Touch your own dropped flag to send it home, or it goes home by itself after 20 seconds.",
			"Markers through walls tell you what to do with each flag: TAKE, DEFEND, ESCORT, KILL CARRIER or RETURN. The compass and the score card show both flags.",
			"New medals (Flag Runner, Flag Defender), challenges and four achievements. Bots attack, defend, escort and hunt carriers.",
			"Works offline and online, also for players who join mid-match.",
		]},
	{"title": "ONE IN THE CHAMBER", "color": Color("ff5a4f"), "tag": "One round. Three lives. Make it count.",
		"icon": [".....#.....", "....###....", "...#####...", "...#####...", "...#####...", "...#####...",
			"...#####...", "...#####...", "...........", "..#######..", "..#######.."],
		"bullets": [
			"Everyone gets the [b]Cuber .44 with a single round[/b] and their own melee weapon. Any hit with it kills, head or body.",
			"Every kill, with the gun or your melee weapon, gives you a round. Rounds stack.",
			"You have [b]3 lives[/b] (pick 1, 3 or 5). Run out and you watch the rest of the match. The last player standing wins.",
			"A new card shows your lives as hearts, your rounds as cartridges and how many players are still in.",
			"No grenades, ammo crates, killstreaks or mutators. Health packs stay.",
			"New medals (Last One Standing, Dead Eye, Flawless) and the achievements One Shot Wonder and Untouchable. Match setup fits all eight mode cards.",
		]},
	{"title": "NEW MAPS", "color": Color("ff8a3d"), "tag": "Moon Base and Volcano Forge join the rotation.",
		"icon": ["...........", "...#.......", "..###......", ".#####..#..", "#######.##.", "#######.###",
			"###########", "###########", "###########", "...........", "..........."],
		"bullets": [
			"[b]Moon Base:[/b] a base floating in space under a starry sky with the Earth overhead: a command dome, habitats, hangars, launch towers around a rocket and craters. Step off the edge and you fall into space.",
			"[b]Volcano Forge:[/b] basalt forge halls and foundries around a glowing lava lake, with drifting embers and a smoky red sky. Lava kills.",
			"Both have their own sunset and night looks, jump pads, King of the Block zones and flag stands, and play every mode.",
			"Bots know their way around them, and no longer wander into lava or water.",
			"World Tour now needs a win on all 10 deathmatch maps. If you already have it, you keep it.",
			"The map editor has eight new blocks: regolith, moon rock, hull panel, solar panel, basalt, basalt brick, magma and lava.",
		]},
	{"title": "WEATHER", "color": Color("8fb8ff"), "tag": "Every match rolls its own weather.",
		"icon": ["...###.....", "..#####.##.", ".##########", "###########", "###########", ".#########.",
			"...........", ".#..#..#..#", "#..#..#..#.", "...........", ".#..#..#..."],
		"bullets": [
			"Rain and thunderstorms on most maps, [b]snowfall[/b] on Snow Fort, [b]sandstorms[/b] on Desert Ruins and [b]falling ash[/b] on Volcano Forge. Moon Base stays clear.",
			"Nothing falls under roofs or through floors. Fog, sky and sunlight change with the weather.",
			"Thunderstorms darken the sky and flash with lightning, with thunder a moment later. Rain, wind and thunder have their own sounds.",
			"Match setup has a new [b]WEATHER[/b] row (Auto, Clear or any weather the map allows), saved in presets.",
			"Settings > Video > Weather effects: Off, Low or High. Online, everyone gets the same weather.",
		]},
	{"title": "SEASON 1: BLOCK PARTY", "color": Color("ff5fd2"), "tag": "A free 30-tier season pass. Open SEASON on the home screen.",
		"icon": ["##.........", "#####......", "########...", "##########.", "########...", "#####......",
			"##.........", "#..........", "#..........", "#..........", "##........."],
		"bullets": [
			"[b]30 tiers[/b]: every 1,000 season XP unlocks one. Matches and challenges earn season XP, even at the level cap or after prestige.",
			"Coins on most tiers plus [b]12 exclusive cosmetics[/b] you can't buy: four skins (including the animated Disco Fever), three hats, two charms, two sprays and the Disco Star outfit.",
			"Scroll the tier track, preview any reward in 3D, CLAIM tiers one by one or CLAIM ALL, and equip them straight away.",
			"The results screen shows the season XP each match earned, and a toast pops when you reach a tier.",
			"The season ends on 31 December 2026, but every tier stays claimable afterwards. Two new achievements: Party Starter and Life of the Party.",
		]},
	{"title": "FIXES AND POLISH", "color": Color("a6abb7"), "tag": "Smaller changes all over the game.",
		"icon": ["......##...", ".....#..#..", ".....#...#.", "......#..##", ".....#####.", "....###....",
			"...###.....", "..###......", ".###.......", "###........", "##........."],
		"bullets": [
			"[b]Map Editor FLAGS tool:[/b] place the two Capture the Flag stands on your own maps. The editor's checks tell you when a stand is too close, boxed in or out of the bots' reach, and match setup says why a map can't host Capture the Flag.",
			"[b]This update log:[/b] it opens once after every update. The version button at the bottom left of the home screen (move down from the daily reward with a keyboard or controller) opens it again.",
			"The season screen works fully with a controller: down on a claimed cosmetic reaches EQUIP, and up from the tier cards reaches CLAIM ALL.",
			"The Tab scoreboard and the results screen name the match's weather along with the map, mutator and time of day.",
			"Bots no longer walk into lava or water while strafing, and no longer trip up when the player they chase leaves or starts spectating.",
			"Spectating a player who fires before holding a gun no longer breaks the view.",
			"The main menu counts the modes itself, so the tagline always matches.",
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
