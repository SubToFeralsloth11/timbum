class_name PadScroll
extends Node
## Lets the right stick scroll its parent ScrollContainer, for menu lists whose rows have nothing
## to focus (achievements, stats). Added by UIKit.pad_friendly.

## Pixels per second at full push.
const SPEED := 900.0


func _process(delta: float) -> void:
	var scroll := get_parent() as ScrollContainer
	if scroll == null or not scroll.is_visible_in_tree():
		return
	var push := Profile.pad_stick(&"look_left", &"look_right", &"look_up", &"look_down").y
	if push != 0.0:
		scroll.scroll_vertical += roundi(push * SPEED * delta)
