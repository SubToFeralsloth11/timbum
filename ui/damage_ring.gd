class_name DamageRing
extends Control
## Red arcs around the crosshair pointing toward whoever just hurt the local player.

const LIFE := 1.6
const MAX_HITS := 6

var _hits: Array = []
var _player_pos := Vector3.ZERO
var _player_yaw := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_hit(from_pos: Vector3) -> void:
	_hits.append([from_pos, LIFE])
	if _hits.size() > MAX_HITS:
		_hits.pop_front()


func update_view(p: Player) -> void:
	_player_pos = p.global_position
	_player_yaw = p.yaw
	if _hits.is_empty():
		return
	var delta := get_process_delta_time()
	for h: Array in _hits:
		h[1] -= delta
	_hits = _hits.filter(func(h: Array) -> bool: return h[1] > 0.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.16
	for h: Array in _hits:
		var dir: Vector3 = h[0] - _player_pos
		if Vector2(dir.x, dir.z).length() < 0.5:
			continue
		var rel := Basis(Vector3.UP, -_player_yaw) * dir
		var a := atan2(rel.x, -rel.z)
		var col := Color(1, 0.15, 0.1, clampf(h[1] / LIFE, 0.0, 1.0) * 0.9)
		draw_arc(c, radius, a - PI * 0.5 - 0.35, a - PI * 0.5 + 0.35, 16, col, 7.0)
