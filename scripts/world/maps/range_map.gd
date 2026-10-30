extends RefCounted
## Firing Range: an open practice field for the Firing Range and the tutorial (never in a
## rotation). A concrete shooting platform at the south end faces four gravel lanes going north,
## with the dummy posts at 10, 25, 50 and 75 m from the firing line (white floor stripes, signs
## from FiringRange), a cover lane on the east side with a low wall 20 m out, a tower with a
## gold-edged ledge to grapple onto, and the weapon console behind the line. The layout reaches
## FiringRange through MapInfo.marks: `line` (the player's spot on the firing line), `console`,
## `ledge` (AABB of the ledge top), `dummies` ([{kind, dist, pos}]) and `signs` ([{text, pos}]).

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")

const SIZE := Vector3i(52, 22, 100)
const KILL_Y := -10.0
const ATMOSPHERE := {
	"sky_top": Color("4f86c6"), "sky_horizon": Color("bcd6ea"), "ground_bottom": Color("5d5a50"),
	"sun_pitch": -50.0, "sun_yaw": 35.0, "sun_color": Color("fff0d6"), "sun_energy": 1.3,
	"fog_color": Color("b6c8d6"), "fog_density": 0.004, "ambient": 0.85, "exposure": 1.0,
	"saturation": 1.05, "fog_sky": 0.35, "ambient_color": Color("c2c8cc"),
}
## Floor height (standing y).
const F := 2
## Grid z of the firing line (the player's feet); every distance is measured from here.
const LINE_Z := 86.5
## The lanes' distances and centre columns (x), west to east.
const DISTANCES: Array[int] = [10, 25, 50, 75]
const LANE_X: Array[int] = [7, 17, 27, 37]
## The cover lane (crouching / peeking dummy behind a low wall).
const COVER_X := 46
const COVER_DIST := 20
## How far a strafing dummy's post sits from the static one (east), in metres.
const STRAFE_OFFSET := 4.0
## Grapple tower footprint (inclusive) and height of its top floor.
const TOWER_A := Vector2i(45, 77)
const TOWER_B := Vector2i(50, 82)
const TOWER_TOP := F + 7


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var hm := Kit.heightmap(g, F)
	g.apply_heightmap(hm, B.GRAVEL, B.DIRT, B.STONE)
	# Shooting platform behind the line, lane dividers, the line itself.
	Kit.paint_top(g, hm, 1, 84, 50, 98, B.CONCRETE)
	for x: int in [2, 12, 22, 32, 42]:
		Kit.paint_top(g, hm, x, 4, x, 83, B.CONCRETE)
	Kit.paint_top(g, hm, 1, 85, 50, 85, B.HAZARD)
	# Distance stripes under the dummies.
	var line := floori(LINE_Z)
	for d: int in DISTANCES:
		Kit.paint_top(g, hm, 3, line - d, 41, line - d, B.WHITE)
	Kit.paint_top(g, hm, 43, line - COVER_DIST, 50, line - COVER_DIST, B.WHITE)
	# Perimeter: walls round the field and a tall earth backstop behind the targets.
	g.walls(Vector3i(0, F, 0), Vector3i(SIZE.x - 1, F + 4, SIZE.z - 1), B.CONCRETE)
	g.fill(Vector3i(1, F, 1), Vector3i(SIZE.x - 2, F + 7, 2), B.DIRT)
	g.fill(Vector3i(1, F + 8, 1), Vector3i(SIZE.x - 2, F + 8, 2), B.GRASS)
	for x in range(4, SIZE.x - 2, 8):
		g.set_block(x, F + 4, SIZE.z - 1, B.LAMP)
	# Cover lane: a low wall the crouching / peeking dummy hides behind.
	var cover_z := line - COVER_DIST + 2
	g.fill(Vector3i(COVER_X - 3, F, cover_z), Vector3i(COVER_X + 3, F, cover_z), B.STONE_BRICK)
	# Grapple tower with a gold-edged ledge on top.
	g.fill(Vector3i(TOWER_A.x, F, TOWER_A.y), Vector3i(TOWER_B.x, TOWER_TOP - 1, TOWER_B.y), B.STONE_BRICK)
	g.walls(Vector3i(TOWER_A.x, TOWER_TOP - 1, TOWER_A.y), Vector3i(TOWER_B.x, TOWER_TOP - 1, TOWER_B.y), B.GOLD)
	for c: Vector2i in [TOWER_A, TOWER_B, Vector2i(TOWER_A.x, TOWER_B.y), Vector2i(TOWER_B.x, TOWER_A.y)]:
		g.set_block(c.x, TOWER_TOP - 1, c.y, B.LAMP)
	# Weapon console: a metal counter with a lamp, behind the line in the middle.
	g.fill(Vector3i(25, F, 95), Vector3i(27, F, 95), B.METAL)
	g.set_block(26, F + 1, 95, B.LAMP)

	for s: Vector2i in [Vector2i(26, 87), Vector2i(21, 89), Vector2i(31, 89), Vector2i(26, 91)]:
		Kit.spawn(g, hm, info, s.x, s.y)
	info.marks["line"] = Vector3(26.5, F, LINE_Z)
	info.marks["console"] = Vector3(26.5, F + 1, 95.5)
	info.marks["ledge"] = AABB(Vector3(TOWER_A.x, TOWER_TOP - 0.5, TOWER_A.y),
		Vector3(TOWER_B.x - TOWER_A.x + 1, 3.0, TOWER_B.y - TOWER_A.y + 1))
	var dummies: Array = []
	var signs: Array = []
	for i in DISTANCES.size():
		var d := DISTANCES[i]
		var x := LANE_X[i] - 2.0 + 0.5
		var z := LINE_Z - d
		dummies.append({"kind": "static", "dist": d, "pos": Vector3(x, F, z)})
		dummies.append({"kind": "strafe", "dist": d, "pos": Vector3(x + STRAFE_OFFSET, F, z)})
		signs.append({"text": "%d m" % d, "pos": Vector3(LANE_X[i] + 0.5, F + 3.4, z - 1.0)})
	dummies.append({"kind": "peek", "dist": COVER_DIST, "pos": Vector3(COVER_X + 0.5, F, LINE_Z - COVER_DIST)})
	signs.append({"text": "COVER  %d m" % COVER_DIST, "pos": Vector3(COVER_X + 0.5, F + 3.4, LINE_Z - COVER_DIST - 1.0)})
	signs.append({"text": "FIRING LINE", "pos": Vector3(14.5, F + 2.6, LINE_Z - 1.0)})
	signs.append({"text": "GRAPPLE LEDGE", "pos": Vector3((TOWER_A.x + TOWER_B.x + 1) * 0.5, TOWER_TOP + 2.4, (TOWER_A.y + TOWER_B.y + 1) * 0.5)})
	info.marks["dummies"] = dummies
	info.marks["signs"] = signs
