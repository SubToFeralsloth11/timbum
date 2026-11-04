class_name GalleryScreen
extends MenuScreen
## The main menu's GALLERY: every saved clip and photo (Clips.gallery), newest first, as cards with
## a thumbnail. ALL / CLIPS / PHOTOS filter them. OPEN loads one into Studio (clips and photos
## with their scene: cameras, time of day, weather, look, trim, export; older photos: the look
## only), SHOW shows it in the file manager and DELETE removes it after a confirmation. VIDEO
## EXPORTS and PICTURE EXPORTS open the folders exports go to. Thumbnails (and a clip's weapon and victim)
## load a few per frame, so a big gallery opens at once.

## Studio's BACK sets this so the main menu opens straight to the gallery.
static var reopen := false

const THUMB := Vector2(272, 153)
const LOADS_PER_FRAME := 2

var _filter := "all"
var _grid: GridContainer
var _empty: Label
var _tabs: Array[Button] = []
var _confirm: ConfirmationDialog
var _to_delete := {}
## [TextureRect, Label, item] waiting for their thumbnail and title.
var _queue: Array = []


func _ready() -> void:
	var page := make_page()
	page.add_child(make_header("GALLERY", "Your clips and photos. Open one to film it from any angle, change its look and export it."))
	var tab_row := UIKit.hbox(6)
	page.add_child(tab_row)
	var group := ButtonGroup.new()
	for t: Array in [["all", "ALL"], ["clip", "CLIPS"], ["photo", "PHOTOS"]]:
		var b := UIKit.button(t[1], &"TabButton")
		b.toggle_mode = true
		b.button_group = group
		var id: String = t[0]
		b.pressed.connect(func() -> void:
			_filter = id
			_rebuild())
		tab_row.add_child(b)
		_tabs.append(b)
	_tabs[0].button_pressed = true
	tab_row.add_child(UIKit.spacer())
	for e: Array in [["VIDEO EXPORTS", true], ["PICTURE EXPORTS", false]]:
		var b := UIKit.button(e[0], &"IconButton")
		var video: bool = e[1]
		b.tooltip_text = "Open %s." % Clips.export_dir(video)
		b.pressed.connect(func() -> void: OS.shell_open(Clips.export_dir(video)))
		tab_row.add_child(b)
	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var col := UIKit.vbox(12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	col.add_child(_grid)
	_empty = UIKit.label("", &"SubheaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_empty)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Delete"
	_confirm.ok_button_text = "Delete"
	_confirm.confirmed.connect(func() -> void:
		Clips.delete_item(_to_delete)
		Sfx.play(&"ui_click")
		_rebuild())
	add_child(_confirm)
	resized.connect(_fit_columns)


func on_shown() -> void:
	_rebuild()


func _fit_columns() -> void:
	_grid.columns = maxi(1, int((size.x - 80.0 + 14.0) / (THUMB.x + 24.0 + 14.0)))


func _rebuild() -> void:
	_fit_columns()
	_queue.clear()
	for c in _grid.get_children():
		c.queue_free()
	var items := Clips.gallery().filter(func(it: Dictionary) -> bool: return _filter == "all" or it.kind == _filter)
	for it: Dictionary in items:
		_grid.add_child(_card(it))
	_empty.visible = items.is_empty()
	_empty.text = "Nothing here yet.\n\nClips: turn on Clips in Settings > Gameplay, then double-tap K up to %d seconds after a kill.\nPhotos: press P in a match against bots (photo mode) and take one." % int(Clips.SAVE_WINDOW)


func _card(it: Dictionary) -> Control:
	var card := UIKit.panel(&"CardPanel")
	var v := UIKit.vbox(6)
	card.add_child(v)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = THUMB
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.clip_contents = true
	v.add_child(thumb)
	var title := UIKit.label("CLIP" if it.kind == "clip" else "PHOTO", &"SubheaderLabel")
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = THUMB.x
	v.add_child(title)
	var when := Time.get_datetime_string_from_unix_time(int(it.time) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60, true)
	var tag := "" if it.kind == "clip" or not str(it.scene).is_empty() else "  ·  look only"
	v.add_child(UIKit.label(when + tag, &"SmallLabel"))
	var row := UIKit.hbox(6)
	v.add_child(row)
	var open := UIKit.button("OPEN", &"PrimaryButton")
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.pressed.connect(func() -> void:
		Studio.pending = it
		get_tree().change_scene_to_file(Studio.SCENE))
	row.add_child(open)
	var show := UIKit.button("SHOW", &"IconButton")
	show.tooltip_text = "Show the file in your file manager."
	show.pressed.connect(func() -> void: OS.shell_show_in_file_manager(ProjectSettings.globalize_path(str(it.path))))
	row.add_child(show)
	var del := UIKit.button("DELETE", &"DangerButton")
	del.pressed.connect(func() -> void:
		_to_delete = it
		_confirm.dialog_text = "Delete this %s? This can't be undone." % ("clip" if it.kind == "clip" else "photo")
		_confirm.popup_centered())
	row.add_child(del)
	_queue.append([thumb, title, it])
	return card


func _process(_delta: float) -> void:
	for i in mini(LOADS_PER_FRAME, _queue.size()):
		var job: Array = _queue.pop_front()
		var thumb := job[0] as TextureRect
		if not is_instance_valid(thumb):
			continue
		var it: Dictionary = job[2]
		var img := Image.load_from_file(ProjectSettings.globalize_path(str(it.thumb))) if FileAccess.file_exists(str(it.thumb)) else null
		if img != null and not img.is_empty():
			if img.get_width() > THUMB.x * 2:
				img.resize(int(THUMB.x * 2), int(THUMB.x * 2 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
			thumb.texture = ImageTexture.create_from_image(img)
		if it.kind == "clip":
			var data := Clips.load_file(str(it.path))
			var title := job[1] as Label
			if data.is_empty():
				title.text = "CLIP (DAMAGED)"
			else:
				var m: Dictionary = data.meta
				var span: Vector2 = (data.tape as KillCam.Tape).span()
				title.text = "%s  ·  %s  ·  %.0fs" % [World.weapon_label(str(m.get("wid", ""))).to_upper(),
					str(m.get("victim_name", "?")).to_upper(), span.y - span.x]
				title.tooltip_text = MapBuilder.map_name(str(m.get("map", "")))
