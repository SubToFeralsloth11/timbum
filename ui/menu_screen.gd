class_name MenuScreen
extends Control
## Base for full-screen main-menu pages. The main menu fades/slides them in and out and
## routes Esc to `back_requested`.

signal back_requested


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Called each time the screen becomes visible.
func on_shown() -> void:
	pass


## Standard page header: BACK button, big title, optional subtitle.
func make_header(title: String, subtitle := "") -> HBoxContainer:
	var h := UIKit.hbox(18)
	var back := UIKit.button("< BACK")
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: back_requested.emit())
	h.add_child(back)
	var titles := UIKit.vbox(0)
	titles.add_child(UIKit.label(title, &"HeaderLabel"))
	if not subtitle.is_empty():
		titles.add_child(UIKit.label(subtitle, &"DimLabel"))
	h.add_child(titles)
	return h


## Root layout: margins that scale with the window, returning the content column.
func make_page() -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 40)
	m.add_theme_constant_override("margin_top", 28)
	m.add_theme_constant_override("margin_bottom", 28)
	add_child(m)
	var v := UIKit.vbox(18)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	return v
