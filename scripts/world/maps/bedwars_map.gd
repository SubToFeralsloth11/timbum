extends RefCounted
## Bed Islands: the map Bedwars always plays (Data.BEDWARS_MAP). Two team islands over the void at
## the ends of the map (BLUE at low z, ORANGE at high z), each with its bed at the front, its
## resource forge at the back, the item shop on the left and the team upgrades on the right; a
## diamond island off each team's flank and the emerald island in the middle, raised a little and
## crowned with a small tower. Nothing joins them: players bridge across with blocks.
## Every built block here is part of the map and can't be broken (BedWars only lets players break
## blocks that players placed, and beds).
## Marks for BedWars: `bw_teams` [{spawn, bed, bed_dir, forge, shop, upgrades}] (team 0, 1; bed is
## the centre of the two bed cells at floor level, bed_dir the unit step from foot to head),
## `bw_diamonds` [{pos}], `bw_emeralds` [{pos}].

const B := preload("res://scripts/world/block_atlas.gd")

const SIZE := Vector3i(72, 56, 132)
const KILL_Y := 12.0
const KILL_CAUSE := "void"
const ATMOSPHERE := {
	"sky_top": Color("4a86e8"), "sky_horizon": Color("cfe7ff"), "ground_bottom": Color("9cc4ee"),
	"sun_pitch": -48.0, "sun_yaw": -130.0, "sun_color": Color("fff3dc"), "sun_energy": 1.45,
	"fog_color": Color("d6ebff"), "fog_density": 0.0022, "ambient": 0.9, "exposure": 1.0,
	"fog_sky": 0.1, "ambient_color": Color("cfdcec"), "sky_energy": 1.15,
}
## Top block row of every island floor (feet stand at FLOOR + 1).
const FLOOR := 30
const MID_X := 36
## Team island centres (z) and the side of the map each faces (+1: toward higher z).
const TEAM_Z := [20, 111]
const TEAM_HALF := 7
const DIAMOND := [Vector2i(13, 50), Vector2i(59, 81)]
const DIAMOND_HALF := 3
const EMERALD := Vector2i(MID_X, 66)
const EMERALD_HALF := 7
const TEAM_WOOL := [B.BLUE, B.ORANGE]


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var teams: Array = []
	for t in 2:
		var cz: int = TEAM_Z[t]
		var face := 1 if t == 0 else -1
		_island(g, MID_X, cz, TEAM_HALF, FLOOR, B.GRASS, B.DIRT)
		# A team-coloured rim so you always know whose island you're on.
		for i in range(-TEAM_HALF, TEAM_HALF + 1):
			for edge in [-TEAM_HALF, TEAM_HALF]:
				g.set_block(MID_X + i, FLOOR, cz + edge, TEAM_WOOL[t])
				g.set_block(MID_X + edge, FLOOR, cz + i, TEAM_WOOL[t])
		# The forge at the back: a raised iron pad under a little canopy.
		var fz := cz - face * 5
		g.fill(Vector3i(MID_X - 1, FLOOR, fz - 1), Vector3i(MID_X + 1, FLOOR, fz + 1), B.METAL)
		for corner: Vector2i in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
			g.fill(Vector3i(MID_X + corner.x, FLOOR + 1, fz + corner.y), Vector3i(MID_X + corner.x, FLOOR + 3, fz + corner.y), B.STONE_BRICK)
		g.fill(Vector3i(MID_X - 2, FLOOR + 4, fz - 2), Vector3i(MID_X + 2, FLOOR + 4, fz + 2), B.STONE_BRICK)
		g.fill(Vector3i(MID_X - 1, FLOOR + 4, fz - 1), Vector3i(MID_X + 1, FLOOR + 4, fz + 1), TEAM_WOOL[t])
		# Shop (left of the forge, seen from the bed) and upgrades (right): a stand under an awning.
		var shop_x := MID_X - 5 * face
		var upg_x := MID_X + 5 * face
		for sx: int in [shop_x, upg_x]:
			g.fill(Vector3i(sx - 1, FLOOR, cz - 1), Vector3i(sx + 1, FLOOR, cz + 1), B.PLANKS)
		# Spawn pad in the middle.
		g.fill(Vector3i(MID_X - 1, FLOOR, cz - 1), Vector3i(MID_X + 1, FLOOR, cz + 1), B.STONE_BRICK)
		var spawn := Vector3(MID_X + 0.5, FLOOR + 1, cz + 0.5)
		for dx in [-1, 0, 1]:
			info.spawns.append(Vector3(MID_X + dx + 0.5, FLOOR + 1, cz + 0.5))
		# The bed sits at the front, two cells long, pointing at the enemy.
		var bed_foot := Vector3i(MID_X, FLOOR + 1, cz + face * 4)
		var bed := Vector3(bed_foot.x + 0.5, FLOOR + 1, bed_foot.z + 0.5 + face * 0.5)
		teams.append({
			"spawn": spawn,
			"bed": bed,
			"bed_dir": Vector3(0, 0, face),
			"forge": Vector3(MID_X + 0.5, FLOOR + 1, fz + 0.5),
			"shop": Vector3(shop_x + 0.5, FLOOR + 1, cz + 0.5),
			"upgrades": Vector3(upg_x + 0.5, FLOOR + 1, cz + 0.5),
		})
	var diamonds: Array = []
	for d: Vector2i in DIAMOND:
		_island(g, d.x, d.y, DIAMOND_HALF, FLOOR, B.STONE, B.COBBLE)
		g.fill(Vector3i(d.x - 1, FLOOR, d.y - 1), Vector3i(d.x + 1, FLOOR, d.y + 1), B.TEAL)
		diamonds.append({"pos": Vector3(d.x + 0.5, FLOOR + 1, d.y + 0.5)})
		info.spawns.append(Vector3(d.x + 2.5, FLOOR + 1, d.y + 0.5))
	# The emerald island: a raised plaza with a ring wall and a small tower over the forge.
	var e := EMERALD
	_island(g, e.x, e.y, EMERALD_HALF, FLOOR + 2, B.STONE_BRICK, B.STONE)
	for i in range(-EMERALD_HALF, EMERALD_HALF + 1):
		for edge in [-EMERALD_HALF, EMERALD_HALF]:
			if absi(i) > 1:
				g.set_block(e.x + i, FLOOR + 3, e.y + edge, B.MOSSY_BRICK)
				g.set_block(e.x + edge, FLOOR + 3, e.y + i, B.MOSSY_BRICK)
	g.fill(Vector3i(e.x - 1, FLOOR + 2, e.y - 1), Vector3i(e.x + 1, FLOOR + 2, e.y + 1), B.GREEN)
	for corner: Vector2i in [Vector2i(-3, -3), Vector2i(3, -3), Vector2i(-3, 3), Vector2i(3, 3)]:
		g.fill(Vector3i(e.x + corner.x, FLOOR + 3, e.y + corner.y), Vector3i(e.x + corner.x, FLOOR + 7, e.y + corner.y), B.STONE_BRICK)
	g.fill(Vector3i(e.x - 3, FLOOR + 8, e.y - 3), Vector3i(e.x + 3, FLOOR + 8, e.y + 3), B.STONE_BRICK)
	g.fill(Vector3i(e.x - 2, FLOOR + 8, e.y - 2), Vector3i(e.x + 2, FLOOR + 8, e.y + 2), B.GLASS)
	var emeralds: Array = [{"pos": Vector3(e.x + 0.5, FLOOR + 3, e.y + 0.5)}]
	for c: Vector2i in [Vector2i(-5, 0), Vector2i(5, 0)]:
		info.spawns.append(Vector3(e.x + c.x + 0.5, FLOOR + 3, e.y + c.y + 0.5))
	info.marks["bw_teams"] = teams
	info.marks["bw_diamonds"] = diamonds
	info.marks["bw_emeralds"] = emeralds


## A floating island: a square top `half` cells out from (cx, cz) at height `top`, with the layers
## under it shrinking to a rough point so it reads as a chunk of land hanging in the sky.
static func _island(g: VoxelGrid, cx: int, cz: int, half: int, top: int, surface: int, under: int) -> void:
	g.fill(Vector3i(cx - half, top, cz - half), Vector3i(cx + half, top, cz + half), surface)
	var depth := half + 2
	for d in range(1, depth):
		var r := half - (d * half) / depth
		var block := under if d < 3 else B.STONE
		for z in range(cz - r, cz + r + 1):
			for x in range(cx - r, cx + r + 1):
				# Ragged underside: corners drop out first.
				if absi(x - cx) + absi(z - cz) > r * 2 - (d % 2):
					continue
				g.set_block(x, top - d, z, block)
