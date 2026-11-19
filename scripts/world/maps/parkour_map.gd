extends RefCounted
## Parkour Run: the course Parkour mode always plays (Data.PARKOUR_MAP). A floating obstacle
## course over a lava sea that snakes back and forth across the map in ROWS, two stages a row,
## climbing as it goes. Each stage is a run of obstacles picked for its difficulty (stepping
## stones, stairs, beams, hurdles, 1x1 pillars, zigzag ladders, long jumps, jump pads and pad
## towers), and ends on a gold checkpoint; later stages get smaller footholds, wider gaps and more
## height. Fixed SEED, so every peer builds the same course.
## Marks for ParkourMode: `checkpoints` [{pos (feet, platform centre), wp, name}] (index 0 is the
## start pad, the last the finish), `course` [{pos}] (every platform centre in order, for bots;
## a checkpoint's `wp` is its index here) and `jump_pads`.
## Jump reach (Player: JUMP_VELOCITY 7.2, GRAVITY 21, SPRINT_SPEED 7.6): about 1.2 m up, and a
## sprinting jump clears a 4-block gap on the level or a 3-block gap one block up. Nothing here
## asks for more.

const Kit := preload("res://scripts/world/maps/map_kit.gd")
const B := preload("res://scripts/world/block_atlas.gd")

const SIZE := Vector3i(104, 128, 104)
## Backstop only: ParkourMode puts a fallen player back on their checkpoint long before this.
const KILL_Y := 3.0
const KILL_CAUSE := "lava"
const SEED := 7310
const ATMOSPHERE := {
	"sky_top": Color("2f6fd0"), "sky_horizon": Color("ffd9b0"), "ground_bottom": Color("ff9a5c"),
	"sun_pitch": -35.0, "sun_yaw": -140.0, "sun_color": Color("fff0d6"), "sun_energy": 1.4,
	"fog_color": Color("f6d2b4"), "fog_density": 0.002, "ambient": 0.9, "exposure": 1.0,
	"fog_sky": 0.1, "ambient_color": Color("d6d0e0"), "sky_energy": 1.1,
}
## The course's rows run along x at these z; each row holds two stages.
const ROWS := [8, 22, 36, 50, 64, 78, 92]
const ROW_X0 := 7
const ROW_X1 := 96
## Platforms stay within this many cells of their row's line (rows are 14 apart).
const BAND := 3
const START_Y := 12
const MAX_Y := 112
## Floor block of each stage, easy (white) to hard (red).
const STAGE_BLOCKS := [B.WHITE, B.WHITE, B.GREEN, B.GREEN, B.TEAL, B.TEAL, B.BLUE, B.BLUE,
	B.YELLOW, B.YELLOW, B.ORANGE, B.ORANGE, B.RED, B.RED]
const STAGE_NAMES := ["Warm-up", "First Steps", "Launch Pads", "Balance Beams", "Hurdles",
	"Pillar Hop", "Pad Tower", "Zigzag Ladder", "Thin Air", "Pad Chain", "Long Jumps",
	"Needle Peaks", "Leap of Faith", "Summit"]


class Course:
	var g: VoxelGrid
	var info: MapInfo
	var rng := RandomNumberGenerator.new()
	## Feet cell at the centre of the platform last placed, its half length along `dir` and the
	## row line (z) the platforms keep to.
	var cur := Vector3i.ZERO
	var half := 0
	var dir := Vector3i(1, 0, 0)
	var row_z := 0
	var block := B.WHITE
	var course: Array = []
	var checkpoints: Array = []
	var pads: Array = []

	func lat() -> Vector3i:
		return Vector3i(0, 0, 1) if dir.x != 0 else Vector3i(1, 0, 0)

	## Places a platform `gap` cells past the current one: `ha` / `hl` half sizes along and across
	## the run, `dy` up, `off` cells off the row line (clamped to the band).
	func hop(gap: int, ha: int, hl: int, dy: int, off: int, b := -1, pillar := 0) -> void:
		var c := cur + dir * (half + gap + ha + 1)
		c.y = mini(cur.y + dy, MAX_Y)
		if dir.x != 0:
			c.z = row_z + clampi(off, -BAND + hl, BAND - hl)
		place(c, ha, hl, block if b < 0 else b, pillar)

	func place(c: Vector3i, ha: int, hl: int, b: int, pillar := 0) -> void:
		var hx := ha if dir.x != 0 else hl
		var hz := hl if dir.x != 0 else ha
		g.fill(Vector3i(c.x - hx, c.y - 1 - pillar, c.z - hz), Vector3i(c.x + hx, c.y - 1, c.z + hz), b)
		if pillar == 0 and hx + hz >= 2:
			# A thin dark underside so big platforms don't look like paper.
			g.fill(Vector3i(c.x - hx + 1, c.y - 2, c.z - hz + 1), Vector3i(c.x + hx - 1, c.y - 2, c.z + hz - 1), B.DARK_PLANKS)
		cur = c
		half = ha
		course.append({"pos": Vector3(c.x + 0.5, c.y, c.z + 0.5), "half": ha})

	func room_left(limit: int) -> int:
		return (limit - cur.x) * dir.x - half

	func checkpoint(stage_name: String, finish := false) -> void:
		var gap := 2
		var c := cur + dir * (half + gap + 3)
		if dir.x != 0:
			c.z = row_z
		place(c, 2, 2, B.GOLD)
		# Lamp posts on the two back corners, clear of the way on (straight ahead, or sideways
		# into the turn at a row's end).
		for s: int in [-1, 1]:
			var post := c - dir * 2 + lat() * 2 * s
			g.fill(post, post + Vector3i(0, 1, 0), B.LOG if not finish else B.GOLD)
			g.set_block(post.x, post.y + 2, post.z, B.LAMP)
		if finish:
			var a := c + lat() * -2 + Vector3i(0, 3, 0)
			g.fill(a, c + lat() * 2 + Vector3i(0, 3, 0), B.GOLD)
			g.set_block(c.x, c.y + 4, c.z, B.LAMP)
		checkpoints.append({"pos": Vector3(c.x + 0.5, c.y, c.z + 0.5), "wp": course.size() - 1, "name": stage_name})

	func pad_jump(gap: int, dy: int, rise: float) -> void:
		hop(1, 1, 1, 0, 0, B.METAL)
		var from := cur
		hop(gap, 1, 1, dy, int(rng.randi_range(-1, 1)), B.METAL)
		pads.append([from, cur, rise])


static func generate(g: VoxelGrid, info: MapInfo) -> void:
	var c := Course.new()
	c.g = g
	c.info = info
	c.rng.seed = SEED
	# The lava sea.
	g.fill(Vector3i(0, 0, 0), Vector3i(SIZE.x - 1, 0, SIZE.z - 1), B.BASALT)
	g.fill(Vector3i(0, 1, 0), Vector3i(SIZE.x - 1, 1, SIZE.z - 1), B.LAVA)
	# The start pad: 7x7 with spawns all over it.
	c.row_z = ROWS[0]
	c.dir = Vector3i(1, 0, 0)
	c.place(Vector3i(ROW_X0 + 3, START_Y, ROWS[0]), 3, 3, B.STONE_BRICK)
	c.checkpoints.append({"pos": c.course[0].pos, "wp": 0, "name": "Start"})
	var hm := Kit.heightmap(g, START_Y)
	for dz in [-2, 0, 2]:
		for dx in [-2, 0, 2]:
			Kit.spawn(g, hm, info, c.cur.x + dx, c.cur.z + dz, START_Y)
	var stage := 0
	for r in ROWS.size():
		var forward := r % 2 == 0
		c.dir = Vector3i(1 if forward else -1, 0, 0)
		c.row_z = ROWS[r]
		var row_end := ROW_X1 if forward else ROW_X0
		var mid := (ROW_X0 + ROW_X1) / 2
		for half_row in 2:
			var limit := mid + (6 if forward else -6) if half_row == 0 else row_end
			_stage(c, stage, limit)
			var last := stage == ROWS.size() * 2 - 1
			c.checkpoint(STAGE_NAMES[stage], last)
			stage += 1
		if r + 1 < ROWS.size():
			_turn(c, ROWS[r + 1], stage)
	Kit.jump_pads(g, info, c.pads)
	info.marks["checkpoints"] = c.checkpoints
	info.marks["course"] = c.course


## One stage: obstacles drawn for its difficulty until the row runs out before `limit`, leaving
## room for the checkpoint (7 cells).
static func _stage(c: Course, stage: int, limit: int) -> void:
	c.block = STAGE_BLOCKS[stage]
	var d := float(stage) / 13.0
	var pool := _pool(stage)
	var tries := 0
	while tries < 40:
		tries += 1
		var kind: String = pool[c.rng.randi() % pool.size()]
		if c.room_left(limit) < _length(kind) + 8:
			if c.room_left(limit) < 13:
				break
			kind = "one"
		_obstacle(c, kind, d)


## The obstacles a stage may use; each stage leads with its own new one.
static func _pool(stage: int) -> Array:
	match stage:
		0: return ["stones"]
		1: return ["stones", "stairs"]
		2: return ["pad", "stones", "stairs"]
		3: return ["beams", "stairs"]
		4: return ["hurdles", "beams", "stones"]
		5: return ["pillars", "beams", "stairs"]
		6: return ["tower", "pillars", "beams"]
		7: return ["ladder", "pillars", "hurdles"]
		8: return ["pillars", "ladder", "beams", "long"]
		9: return ["pad", "tower", "pillars", "ladder"]
		10: return ["long", "pillars", "hurdles", "ladder"]
		11: return ["pillars", "ladder", "long", "tower"]
		_: return ["long", "pillars", "ladder", "pad", "beams"]


## Cells an obstacle needs along the run, at most.
static func _length(kind: String) -> int:
	match kind:
		"pad": return 16
		"tower": return 10
		"hurdles": return 14
		"ladder": return 10
		"beams": return 22
		"long": return 26
		"one": return 5
		_: return 18


static func _obstacle(c: Course, kind: String, d: float) -> void:
	var rng := c.rng
	var up := 1 if c.cur.y < MAX_Y - 10 else 0
	match kind:
		"one":
			c.hop(1, 1, 1, 0, 0)
		"stones":
			# 3x3 stepping stones, small gaps, the odd step up.
			for i in 3:
				c.hop(1 + int(rng.randf() < d), 1, 1, up if rng.randf() < 0.35 else 0, rng.randi_range(-1, 1))
		"stairs":
			# Rising 3x3 steps, one block up each.
			for i in 4:
				c.hop(1, 1, 1, up, rng.randi_range(-1, 1))
		"beams":
			# 5x1 beams, shifted sideways: land on a strip one block wide.
			var off := clampi(c.cur.z - c.row_z + rng.randi_range(-1, 1), -BAND, BAND)
			for i in 3:
				off = clampi(off + rng.randi_range(-1, 1), -BAND, BAND)
				c.hop(1 + int(rng.randf() < d), 2, 0, 0, off)
		"hurdles":
			# A 3-wide strip with knee-high walls to jump while running.
			c.hop(1, 6, 1, 0, 0)
			var a := c.cur - c.dir * 6
			for k: int in [3, 6, 9]:
				var w: Vector3i = a + c.dir * k
				c.g.fill(w - c.lat(), w + c.lat(), B.HAZARD)
		"pillars":
			# 1x1 pillar tops, gaps growing with the stage.
			var gap := 1 + int(d * 2.2)
			var off := clampi(c.cur.z - c.row_z, -BAND, BAND)
			for i in 4:
				off = clampi(off + rng.randi_range(-1, 1), -BAND, BAND)
				var dy := up if rng.randf() < 0.3 and gap < 3 else 0
				c.hop(gap if dy == 0 else mini(gap, 2), 0, 0, dy, off, -1, 3)
		"ladder":
			# Zigzag 1x1 steps climbing one block each, side to side.
			var side := 1 if rng.randf() < 0.5 else -1
			for i in 4:
				side = -side
				c.hop(1, 0, 0, up, side, -1, 2)
		"long":
			# Sprint jumps between 3x3 stones: 3, then 4 blocks late on.
			for i in 3:
				c.hop(3 + int(d > 0.7 and rng.randf() < 0.6), 1, 1, 0, rng.randi_range(-1, 1))
			c.hop(1, 1, 1, 0, 0)
		"pad":
			# A jump pad over a wide gap and up onto a higher landing.
			c.pad_jump(6 + rng.randi_range(0, 3), 2 + rng.randi_range(0, 3) * up, 2.5)
		"tower":
			# A pad throwing you straight up a wall onto a ledge.
			c.pad_jump(1, 6 * up, 1.5)


## From a row's end checkpoint across to the next row: stepping stones along +z, then a corner
## platform on the new row's line.
static func _turn(c: Course, next_z: int, stage: int) -> void:
	c.block = STAGE_BLOCKS[mini(stage, STAGE_BLOCKS.size() - 1)]
	c.dir = Vector3i(0, 0, 1)
	var x := c.cur.x
	# Checkpoint centre to corner centre is 14 cells: 2 + gap + 3 + gap + 3 + gap + 3, so the
	# three gaps are one cell each.
	c.hop(1, 1, 1, 0, 0)
	c.hop(1, 1, 1, 0, 0)
	var corner := Vector3i(x, c.cur.y, next_z)
	c.place(corner, 2, 2, B.STONE_BRICK)
