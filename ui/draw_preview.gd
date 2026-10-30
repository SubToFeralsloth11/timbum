class_name DrawPreview
extends Node3D
## Shop preview of a draw animation: a gun that keeps replaying the draw (Viewmodel.draw_pose),
## slowed down a little so the move reads, with a pause between takes.

## Seconds one draw takes in the preview (in a match it fits Player.switch_time()).
const DRAW_TIME := 0.55
const CYCLE := 1.6
## Draw offsets are tuned for first person; scale them down to stay in the preview frame.
const OFFSET_SCALE := 0.6

var style := "standard"
var _pivot: Node3D
var _gun: Node3D
var _t := DRAW_TIME
var _frozen := false


## `frozen_d` >= 0 holds the pose at that point of the draw (1 = start) instead of looping.
static func create(p_style: String, weapon_id: String, skin_id: String, charm_id: String, frozen_d := -1.0) -> DrawPreview:
	var p := DrawPreview.new()
	p.name = "DrawPreview"
	p.style = p_style
	p._pivot = Node3D.new()
	p.add_child(p._pivot)
	p._gun = Models.build_gun(weapon_id, skin_id, charm_id)
	p._pivot.add_child(p._gun)
	if frozen_d >= 0.0:
		p._apply(frozen_d)
		p._frozen = true
	return p


func _apply(d: float) -> void:
	var pose := Viewmodel.draw_pose(style, d)
	_pivot.position = (pose[0] as Vector3) * OFFSET_SCALE
	_pivot.rotation = pose[1]
	_gun.transform = pose[2]


func _process(delta: float) -> void:
	if _frozen:
		return
	_t = fmod(_t + delta, CYCLE)
	_apply(1.0 - clampf(_t / DRAW_TIME, 0.0, 1.0))
