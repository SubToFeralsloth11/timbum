class_name BlockTitle
extends Control
## The "TIMBUM" logo drawn from voxel-style blocks: gold faces with a dark extruded
## side, each letter gently bobbing on its own phase.

## 5x7 glyphs, "#" = block.
const GLYPHS := {
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
}
const DEPTH := 4
const FACE_TOP := Color("ffe27a")
const FACE_BOTTOM := Color("f08a1c")
const SIDE := Color("6a2e08")
## Total extrusion depth as a fraction of the block size.
const EXTRUDE := 0.6
const OUTLINE := Color("1a0c04")

@export var text := "TIMBUM"
## Edge length of one block in UI pixels.
@export var block := 13.0
@export var bob_height := 5.0

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = _content_size()


func _content_size() -> Vector2:
	var cols := text.length() * 6 - 1
	var extrude := block * EXTRUDE
	return Vector2(cols * block + extrude + 4, 7 * block + extrude + bob_height * 2 + 4)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var origin := Vector2((size.x - _content_size().x) * 0.5, bob_height + 2)
	var step := block * EXTRUDE / DEPTH
	for li in text.length():
		var glyph: Array = GLYPHS.get(text[li], [])
		if glyph.is_empty():
			continue
		var bob := sin(_time * 2.2 + li * 0.7) * bob_height
		var base := origin + Vector2(li * 6 * block, bob)
		# Extrusion: darker copies stepping down-right, back to front.
		for d in range(DEPTH, 0, -1):
			var off := Vector2(d, d) * step
			_draw_glyph(glyph, base + off, SIDE.darkened(0.1 * d / DEPTH), false)
		_draw_glyph(glyph, base, Color.WHITE, true)


func _draw_glyph(glyph: Array, pos: Vector2, color: Color, face: bool) -> void:
	for y in 7:
		var row: String = glyph[y]
		for x in 5:
			if row[x] != "#":
				continue
			var r := Rect2(pos + Vector2(x, y) * block, Vector2(block, block))
			if not face:
				draw_rect(r.grow(1.5), OUTLINE)
				draw_rect(r, color)
				continue
			var c := FACE_TOP.lerp(FACE_BOTTOM, y / 6.0)
			draw_rect(r.grow(1.5), OUTLINE)
			draw_rect(r, c)
			# Per-block bevel: light top-left, dark bottom-right.
			var e := maxf(2.0, block * 0.16)
			draw_rect(Rect2(r.position, Vector2(r.size.x, e)), c.lightened(0.35))
			draw_rect(Rect2(r.position, Vector2(e, r.size.y)), c.lightened(0.15))
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - e), Vector2(r.size.x, e)), c.darkened(0.25))
			draw_rect(Rect2(r.position + Vector2(r.size.x - e, 0), Vector2(e, r.size.y)), c.darkened(0.15))
