class_name BlockHunt
extends MatchMode
## Block Hunt (`Net.config.mode == "blockhunt"`): hiders disguised as blocks against seekers.
## Everyone starts a Hider (team 0) disguised as a block: the server deals each hider CHOICES
## blocks from the map's own common surface blocks (`info.block_choices`) and the first is worn
## (`info.disguise`); until the seekers go looking a hider may switch between them (keys 1-4 or the
## weapon wheel; `_c_pick`). The hider's body is a 1 m block of that kind (`_disguise_nodes`) that
## turns in quarter turns and, once the hider holds still SETTLE_TIME s, settles onto the block grid
## so it lines up with the real blocks. START_DELAY s in, the server turns one player in every
## SEEKER_EVERY into a Seeker (team 1: their own melee weapon only, MAX_HP, SPEED), blindfolded and
## frozen for HIDE_TIME s while the hiders hide. A hider who dies turns Seeker. Hiders can't
## attack, see nobody through walls, and nobody has a nametag. No guns, pickups, mutators or
## killstreaks (Net.sanitize_config).
## **Balloons** (the hiders' only item): fire releases the picked size (1-3 / the weapon wheel) for
## its points: BALLOONS gives each size's points, the cooldown it starts (shared by all sizes) and how
## long its colour shows: the balloon rises from the hider in a burst of confetti and the hider's
## block glows its colour for that long, so a bigger balloon is more points, more risk and a longer
## wait. Seeker bots hear a balloon within BALLOON_HEAR m and go and look.
## Points: a hider scores a point every SURVIVE_EVERY s of seeking it lives through plus its
## balloons; a seeker CATCH_POINTS a catch. The Hiders win if any are left at the time limit, the
## Seekers as soon as none are. The server decides: `_s_start` (seekers, when seeking starts),
## `_s_role`, `_s_disguise`, `_s_balloon`, `_s_points`; joiners get `_s_state`.
## Bots: hiders pick the spot and disguise that blend in best (Hiding.spots / best_disguise) away
## from the seekers, hold still there, release balloons when no seeker is near or in sight (bigger
## the safer they are) and run when a seeker closes in or hits them; seekers only spot a hider they
## can make out (`bot_notices`): a moving or unsettled block, a glowing one, or one whose colour
## stands out against what lies behind it.

const HIDERS := 0
const SEEKERS := 1
const START_DELAY := 2.0
const HIDE_TIME := 30.0
const SEEKER_EVERY := 5
const MAX_HP := 150.0
const SPEED := 1.1
const CHOICES := 4
const SETTLE_TIME := 1.2
const SURVIVE_EVERY := 5.0
const CATCH_POINTS := 10
## Per balloon size: [name, points, cooldown s, colour s, balloon radius m, confetti].
const BALLOONS := [["SMALL", 1, 6.0, 3.0, 0.3, 24], ["MEDIUM", 3, 15.0, 6.0, 0.55, 60], ["BIG", 7, 30.0, 10.0, 0.9, 140]]
const BALLOON_HEAR := [16.0, 30.0, 55.0]
const BALLOON_RISE := 1.6
## Blocks that make no disguise (see-through, liquid, glowing, or none).
const NO_DISGUISE: Array[int] = [BlockAtlas.AIR, BlockAtlas.GLASS, BlockAtlas.WATER, BlockAtlas.LAVA, BlockAtlas.LAMP, BlockAtlas.MAGMA]
## Hider bots run when a seeker comes this close.
const PANIC_RANGE := 4.0

## Whether the seekers have been picked, and the match clock (`World.time_left`) at which they go
## looking (every peer).
var started := false
var seek_at := 0.0
## Entity id -> points / catches / balloons released (server values on every peer).
var points := {}
var catches := {}
var balloons := {}
## Entity id -> [World.now() until which its block glows, colour] (every peer).
var _glow := {}
## Entity id -> its disguise block node, and seconds it has held still (every peer).
var _disguise_nodes := {}
var _still := {}
var _last_pos := {}
var _overlay: SeekOverlay
var _block_mats := {}
## Entity id -> its block's balloon-glow overlay (every peer).
var _glow_mats := {}
## The local hider's picks: block choice and balloon size, and its balloon cooldown.
var _balloon_pick := 0
var _ready_at := 0.0
var _cool := 1.0

# Server only.
var _palette: Array[int] = []
var _balloon_ready := {}
var _survive_clock := 0.0
var _watch := Hiding.Watch.new()
## Hider bot entity id -> {spot, flee_until, settled_since, greed}; seeker bots' search points.
var _hide := {}
var _search := {}
var _visited := {}


func _init() -> void:
	name = "BlockHunt"


func _ready() -> void:
	_overlay = SeekOverlay.new()
	_overlay.name = "SeekOverlay"
	_overlay.setup(self)
	add_child(_overlay)
	if multiplayer.is_server():
		_palette = map_palette(world)


static func is_hider(p: Player) -> bool:
	return Teams.of(p) == HIDERS


static func is_seeker(p: Player) -> bool:
	return Teams.of(p) == SEEKERS


## A block's display name (the Map Editor's, else its tile's name).
static func block_name(b: int) -> String:
	var n := MapEditor.block_name(b)
	if not n.begins_with("Block "):
		return n
	var faces: Array = BlockAtlas._FACES[b] if b >= 0 and b < BlockAtlas._FACES.size() else ["", "block", ""]
	return str(faces[1]).replace("_", " ").capitalize()


## The surface blocks of `world`'s map that make a disguise, most common first (at most 12).
static func map_palette(w: World) -> Array[int]:
	var g := Hiding.grid_of(w)
	var counts := {}
	for x in g.size.x:
		for z in g.size.z:
			for y in range(1, g.size.y):
				if not g.is_air(x, y, z) or g.is_air(x, y - 1, z):
					continue
				# The block under an air cell: a floor somebody can stand next to or on.
				var b := g.get_block(x, y - 1, z)
				if not NO_DISGUISE.has(b):
					counts[b] = int(counts.get(b, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return int(counts[a]) > int(counts[b]))
	var out: Array[int] = []
	for b: int in ids.slice(0, 12):
		out.append(b)
	if out.size() < CHOICES:
		for b: int in [BlockAtlas.STONE, BlockAtlas.PLANKS, BlockAtlas.GRASS, BlockAtlas.BRICK]:
			if not out.has(b):
				out.append(b)
	return out


## Seconds until the seekers go looking (0 once they do, or before they are picked).
func hide_left() -> float:
	return maxf(0.0, world.time_left - seek_at) if started else 0.0


func seeking() -> bool:
	return started and hide_left() <= 0.0


## Whether a hider may still change its block.
func picking() -> bool:
	return not seeking()


func elapsed() -> float:
	return float(Net.config.time_limit) - world.time_left


# ================================================================ server

func _physics_process(delta: float) -> void:
	_track_stillness(delta)
	if not multiplayer.is_server() or world.match_over:
		return
	if not started:
		if elapsed() >= START_DELAY:
			_server_start()
		return
	if not seeking():
		return
	_survive_clock += delta
	if _survive_clock >= SURVIVE_EVERY:
		_survive_clock -= SURVIVE_EVERY
		for eid: int in world.entities:
			var p: Player = world.entities[eid]
			if p.alive and is_hider(p):
				points[eid] = int(points.get(eid, 0)) + 1
		_broadcast(&"_s_points", [points, catches, balloons])


func _server_start() -> void:
	var pool: Array[int] = []
	for eid: int in world.entities:
		if world.entities[eid].alive:
			pool.append(eid)
	if pool.size() < 2:
		return
	pool.shuffle()
	var n := clampi(ceili(pool.size() / float(SEEKER_EVERY)), 1, pool.size() - 1)
	var picked: Array = pool.slice(0, n)
	_broadcast(&"_s_start", [picked, world.time_left - HIDE_TIME])
	for eid: int in picked:
		world.server_set_health(eid, MAX_HP)


## CHOICES blocks for a new hider: drawn from the map palette, weighted to its most common blocks.
func _deal_choices() -> Array:
	if _palette.is_empty():
		_palette = map_palette(world)
	var pool := _palette.duplicate()
	var out: Array = []
	while out.size() < CHOICES and not pool.is_empty():
		# Earlier (more common) blocks are likelier: pick from the front half more often.
		var i := randi() % pool.size() if randf() < 0.4 else randi() % maxi(1, pool.size() / 2)
		out.append(pool[i])
		pool.remove_at(i)
	while out.size() < CHOICES:
		out.append(BlockAtlas.STONE)
	return out


func server_team_for(_is_bot: bool) -> int:
	return SEEKERS if seeking() else HIDERS


func prepare_info(info: Dictionary, team: int) -> Dictionary:
	var out := info.duplicate()
	out.team = team
	out.primary = ""
	out.secondary = ""
	out.knife_only = true
	if team == SEEKERS:
		out.max_hp = MAX_HP
		out.speed = SPEED
		out.erase("disguise")
		out.erase("block_choices")
	else:
		out.erase("max_hp")
		out.speed = 1.0
		if not out.has("block_choices") and multiplayer.is_server():
			out.block_choices = _deal_choices()
			out.disguise = out.block_choices[0]
	return out


func uses_loadout(_p: Player) -> bool:
	return false


func spawn_protection() -> bool:
	return false


func has_pickup(_kind: String) -> bool:
	return false


func bot_drop_team() -> int:
	var c := Teams.counts(world)
	if c[SEEKERS] > 1:
		return SEEKERS
	return HIDERS if c[HIDERS] > 1 else -1


func server_sync(pid: int) -> void:
	_s_state.rpc_id(pid, started, seek_at, points, catches, balloons)


func server_human_left(pid: int) -> void:
	super(pid)
	_server_check_end()


## Hiders hit nothing; a seeker's swing hurts as usual.
func hit_damage(shooter: Player, _target: Player, _wid: String, dmg: float) -> float:
	return dmg if is_seeker(shooter) and seeking() else 0.0


func server_on_kill(victim_id: int, killer_id: int, _wid: String) -> void:
	var victim: Player = world.entities.get(victim_id)
	if victim == null or not is_hider(victim) or not started:
		return
	if killer_id != victim_id and world.entities.has(killer_id):
		catches[killer_id] = int(catches.get(killer_id, 0)) + 1
		points[killer_id] = int(points.get(killer_id, 0)) + CATCH_POINTS
	_watch.forget(victim_id)
	_hide.erase(victim_id)
	_broadcast(&"_s_role", [victim_id, SEEKERS])
	_broadcast(&"_s_points", [points, catches, balloons])
	_server_check_end()


func _server_check_end() -> void:
	if not started or world.match_over:
		return
	var c := Teams.counts(world)
	if c[HIDERS] == 0:
		world.server_end_match()
	elif c[SEEKERS] == 0:
		var pool: Array[int] = []
		for eid: int in world.entities:
			if world.entities[eid].alive:
				pool.append(eid)
		if pool.size() >= 2:
			var eid: int = pool.pick_random()
			_broadcast(&"_s_role", [eid, SEEKERS])
			world.server_set_health(eid, MAX_HP)


func server_winner() -> int:
	return SEEKERS if started and Teams.counts(world)[HIDERS] == 0 else HIDERS


func server_finish(rows: Array) -> Dictionary:
	annotate_rows(rows)
	var winner := server_winner()
	for r: Dictionary in rows:
		r.won = int(r.team) == winner
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.team != b.team:
			return a.team == winner
		return int(a.points) > int(b.points))
	return {"winner": winner}


## A hider asks for block `index` of its choices.
@rpc("any_peer", "call_remote", "reliable")
func _c_pick(index: int) -> void:
	if multiplayer.is_server():
		server_pick(multiplayer.get_remote_sender_id(), index)


func server_pick(eid: int, index: int) -> void:
	var p: Player = world.entities.get(eid)
	if p == null or not p.alive or not is_hider(p) or not picking():
		return
	var choices: Array = p.info.get("block_choices", [])
	if index < 0 or index >= choices.size() or int(choices[index]) == int(p.info.get("disguise", -1)):
		return
	_broadcast(&"_s_disguise", [eid, int(choices[index])])


## A hider releases a balloon of `size`.
@rpc("any_peer", "call_remote", "reliable")
func _c_balloon(size: int) -> void:
	if multiplayer.is_server():
		server_balloon(multiplayer.get_remote_sender_id(), size)


func server_balloon(eid: int, size: int) -> void:
	var p: Player = world.entities.get(eid)
	if p == null or not p.alive or not is_hider(p) or not seeking() or world.match_over:
		return
	if size < 0 or size >= BALLOONS.size() or World.now() < float(_balloon_ready.get(eid, 0.0)):
		return
	var b: Array = BALLOONS[size]
	_balloon_ready[eid] = World.now() + float(b[2])
	points[eid] = int(points.get(eid, 0)) + int(b[1])
	balloons[eid] = int(balloons.get(eid, 0)) + 1
	var pos := p.global_position + Vector3.UP * 1.1
	_broadcast(&"_s_balloon", [eid, size, pos, randf()])
	_broadcast(&"_s_points", [points, catches, balloons])
	# Seeker bots that hear it (or see it go up) go and look.
	for sid: int in world.entities:
		var s: Player = world.entities[sid]
		if s.brain == null or not s.alive or not is_seeker(s):
			continue
		var d := s.global_position.distance_to(pos)
		if d < float(BALLOON_HEAR[size]) or (d < 70.0 and s.brain.can_see(p, false)):
			s.brain.investigate(p.global_position)


# ================================================================ every peer

@rpc("authority", "call_remote", "reliable")
func _s_start(seekers: Array, at: float) -> void:
	started = true
	seek_at = at
	for eid: int in seekers:
		_set_role(eid, SEEKERS)
	var me := world.local_player
	if me != null and is_seeker(me):
		world.hud.announce("YOU SEEK  ·  WAIT FOR THEM TO HIDE")
	else:
		world.hud.announce("SEEKERS PICKED  ·  HIDE!")
	Sfx.play(&"countdown", null, -4.0)
	world.hud.refresh_scores()


@rpc("authority", "call_remote", "reliable")
func _s_role(eid: int, role: int) -> void:
	_set_role(eid, role)
	if eid == world.my_id():
		world.hud.announce("FOUND!  NOW YOU SEEK")
		Sfx.play(&"hurt", null, -8.0)
	world.hud.refresh_scores()


func _set_role(eid: int, role: int) -> void:
	var p: Player = world.entities.get(eid)
	if p == null:
		return
	p.apply_info(prepare_info(p.info, role))
	_apply_look(p)
	Teams.refresh_tags(world)


@rpc("authority", "call_remote", "reliable")
func _s_disguise(eid: int, block: int) -> void:
	var p: Player = world.entities.get(eid)
	if p == null:
		return
	var info := p.info.duplicate()
	info.disguise = block
	p.info = info
	_apply_look(p)


@rpc("authority", "call_remote", "reliable")
func _s_balloon(eid: int, size: int, pos: Vector3, hue: float) -> void:
	var b: Array = BALLOONS[clampi(size, 0, BALLOONS.size() - 1)]
	var col := Color.from_hsv(hue, 0.75, 1.0)
	_glow[eid] = [World.now() + float(b[3]), col]
	_spawn_balloon(pos, col, float(b[4]), float(b[3]), int(b[5]))
	Sfx.play(&"smoke_pop", pos, -6.0 + size * 4.0, 1.4 - size * 0.25)
	if eid == world.my_id():
		_ready_at = World.now() + float(b[2])
		_cool = float(b[2])
		world.hud.announce("+%d  %s BALLOON" % [int(b[1]), str(b[0])])


@rpc("authority", "call_remote", "reliable")
func _s_points(all_points: Dictionary, all_catches: Dictionary, all_balloons: Dictionary) -> void:
	points = all_points
	catches = all_catches
	balloons = all_balloons
	world.hud.refresh_scores()


@rpc("authority", "call_remote", "reliable")
func _s_state(on: bool, at: float, all_points: Dictionary, all_catches: Dictionary, all_balloons: Dictionary) -> void:
	started = on
	seek_at = at
	_s_points(all_points, all_catches, all_balloons)


func on_player_added(p: Player) -> void:
	super(p)
	_apply_look(p)


func shows_nametags() -> bool:
	return false


func can_attack(p: Player) -> bool:
	return is_seeker(p) and seeking()


func move_mult(p: Player) -> float:
	return 0.0 if is_seeker(p) and started and not seeking() else 1.0


func grapple_allowed(p: Player) -> bool:
	return not (is_seeker(p) and started and not seeking())


## Hiders: the avatar hides behind the block disguise; seekers look like themselves.
func _apply_look(p: Player) -> void:
	var hider := is_hider(p)
	p.avatar.visible = not hider
	var node: MeshInstance3D = _disguise_nodes.get(p.id)
	if not hider:
		if node != null and is_instance_valid(node):
			node.queue_free()
		_disguise_nodes.erase(p.id)
		if p == world.local_player and p.viewmodel != null and p.alive:
			p.viewmodel.visible = true
		return
	if node == null or not is_instance_valid(node):
		node = MeshInstance3D.new()
		node.name = "Disguise"
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.98
		node.mesh = box
		node.top_level = true
		p.add_child(node)
		node.global_position = p.global_position + Vector3.UP * 0.5
		_disguise_nodes[p.id] = node
	node.material_override = _block_material(int(p.info.get("disguise", BlockAtlas.STONE)))


func _block_material(block: int) -> StandardMaterial3D:
	if not _block_mats.has(block):
		var m := StandardMaterial3D.new()
		m.albedo_texture = BlockAtlas.icon(block, 1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.roughness = 0.9
		_block_mats[block] = m
	return _block_mats[block]


## Every peer: how long each player has held still (the disguise settles; seeker bots read it).
func _track_stillness(delta: float) -> void:
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		var pos := p.global_position
		var last: Vector3 = _last_pos.get(eid, pos)
		_last_pos[eid] = pos
		_still[eid] = float(_still.get(eid, 0.0)) + delta if pos.distance_to(last) < 0.01 else 0.0


## Whether `p` has held still long enough to settle onto the grid.
func settled(p: Player) -> bool:
	return float(_still.get(p.id, 0.0)) >= SETTLE_TIME


func _process(delta: float) -> void:
	var origin := world.map_info.bounds.position
	var now := World.now()
	for eid: int in _disguise_nodes.keys():
		var node: MeshInstance3D = _disguise_nodes[eid]
		var p: Player = world.entities.get(eid)
		if p == null or not is_instance_valid(node):
			_disguise_nodes.erase(eid)
			continue
		node.visible = p.alive
		var feet := p.global_position
		var want := feet + Vector3.UP * 0.5
		var turn := snappedf(p.yaw, PI * 0.5)
		if settled(p):
			# Line up with the real blocks: the cell the feet stand in.
			var cell := ((feet + Vector3.UP * 0.05) - origin).floor()
			want = origin + cell + Vector3(0.5, 0.5, 0.5)
			turn = 0.0
		node.global_position = node.global_position.lerp(want, minf(1.0, delta * 14.0))
		node.global_rotation = Vector3(0.0, lerp_angle(node.global_rotation.y, turn, minf(1.0, delta * 14.0)), 0.0)
		var g: Array = _glow.get(eid, [])
		if not g.is_empty() and now < float(g[0]):
			var pulse := 0.35 + 0.25 * sin(now * 10.0)
			var m: StandardMaterial3D = _glow_mats.get(eid)
			if m == null:
				m = StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_glow_mats[eid] = m
			m.albedo_color = Color(g[1] as Color, pulse)
			node.material_overlay = m
		else:
			node.material_overlay = null
	var me := world.local_player
	if me != null and me.alive and me.viewmodel != null and is_hider(me):
		me.viewmodel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var me := world.local_player
	if me == null or not me.alive or not is_hider(me) or world.input_blocked() or world.match_over:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Profile.using_pad:
		return
	var slot := -1
	for i in 3:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			slot = i
	if event.is_action_pressed("streak_reward"):
		slot = 3
	var step := 1 if event.is_action_pressed("next_weapon") else (-1 if event.is_action_pressed("prev_weapon") else 0)
	if picking():
		var choices: Array = me.info.get("block_choices", [])
		if choices.is_empty():
			return
		var cur := choices.find(int(me.info.get("disguise", -1)))
		var want := slot if slot >= 0 else (wrapi(cur + step, 0, choices.size()) if step != 0 else -1)
		if want >= 0 and want < choices.size():
			_request_pick(want)
		return
	if slot >= 0 and slot < BALLOONS.size():
		_balloon_pick = slot
	elif step != 0:
		_balloon_pick = wrapi(_balloon_pick + step, 0, BALLOONS.size())
	elif event.is_action_pressed("fire"):
		if World.now() >= _ready_at:
			if multiplayer.is_server():
				server_balloon(me.id, _balloon_pick)
			else:
				_c_balloon.rpc_id(1, _balloon_pick)
		else:
			Sfx.play(&"dry_fire", null, -8.0)


func _request_pick(index: int) -> void:
	if multiplayer.is_server():
		server_pick(world.my_id(), index)
	else:
		_c_pick.rpc_id(1, index)


# ================================================================ balloons (every peer)

## A balloon of `radius` rising from `pos` for `life` s on a string, after a burst of `confetti`.
func _spawn_balloon(pos: Vector3, col: Color, radius: float, life: float, confetti: int) -> void:
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	root.global_position = pos
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.3
	sphere.radial_segments = 16
	sphere.rings = 8
	ball.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.5
	mat.roughness = 0.25
	ball.material_override = mat
	ball.position.y = radius + 0.6
	root.add_child(ball)
	var string := MeshInstance3D.new()
	var line := BoxMesh.new()
	line.size = Vector3(0.015, 0.6, 0.015)
	string.mesh = line
	string.material_override = Models.flat_material(Color(0.95, 0.95, 0.95), 0.9)
	string.position.y = 0.3
	root.add_child(string)
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.emitting = true
	burst.amount = confetti
	burst.lifetime = 2.5
	burst.explosiveness = 0.9
	burst.direction = Vector3.UP
	burst.spread = 70.0
	burst.initial_velocity_min = 2.0
	burst.initial_velocity_max = 3.0 + radius * 5.0
	burst.gravity = Vector3(0, -3.0, 0)
	burst.damping_min = 1.0
	burst.damping_max = 2.0
	burst.color = col
	burst.hue_variation_min = -1.0
	burst.hue_variation_max = 1.0
	var bit := BoxMesh.new()
	bit.size = Vector3(0.07, 0.07, 0.01)
	var bit_mat := StandardMaterial3D.new()
	bit_mat.vertex_color_use_as_albedo = true
	bit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bit.material = bit_mat
	burst.mesh = bit
	burst.angle_max = 180.0
	burst.top_level = true
	root.add_child(burst)
	burst.global_position = pos + Vector3.UP * 0.3
	var tw := root.create_tween()
	tw.tween_property(root, "global_position", pos + Vector3.UP * BALLOON_RISE * life, life)
	tw.tween_property(ball, "scale", Vector3.ZERO, 0.12)
	tw.tween_callback(root.queue_free)


# ================================================================ HUD and results

func overlay_state() -> Dictionary:
	var me := world.local_player
	if me == null:
		return {}
	var hl := hide_left()
	if is_seeker(me):
		var card := {"title": "SEEKER", "color": Teams.color(SEEKERS),
			"lines": ["Some of these blocks are players.", "Hit them with your melee weapon.", "Watch for moving blocks and balloons."]}
		if hl > 0.0:
			card.blind = "%d" % ceili(hl)
			card.blind_sub = "YOU SEEK  ·  THE HIDERS ARE TURNING INTO BLOCKS"
		return card
	var block := int(me.info.get("disguise", BlockAtlas.STONE))
	var out := {"title": "HIDER  ·  %s" % block_name(block).to_upper(), "color": Teams.color(HIDERS), "lines": []}
	if picking():
		out.lines = ["Pick your block: 1-4 or scroll", "Hide where it blends in" if not started else "Seekers look in %d" % ceili(hl),
			"Hold still to snap onto the grid"]
		out.choices = me.info.get("block_choices", [])
		out.choice = (out.choices as Array).find(block)
		return out
	out.lines = ["Fire: balloon for points (1-3 / scroll size)", "Bigger = more points, more colour, longer wait",
		"Still: %s" % ("settled on the grid" if settled(me) else "moving!")]
	var sizes: Array = []
	var ready := 1.0 if World.now() >= _ready_at else clampf(1.0 - (_ready_at - World.now()) / maxf(0.1, _cool), 0.0, 0.99)
	for b: Array in BALLOONS:
		sizes.append([b[0], b[1], ready])
	out.balloons = sizes
	out.balloon = _balloon_pick
	return out


func hud_bars() -> Array:
	var c := Teams.counts(world)
	var total := maxf(1.0, float(c[0] + c[1]))
	return [[c[HIDERS] / total, str(c[HIDERS])], [c[SEEKERS] / total, str(c[SEEKERS])]]


func hud_goal() -> String:
	if not started:
		return "Seekers picked in %d  ·  pick a block and hide" % ceili(maxf(0.0, START_DELAY - elapsed()))
	if hide_left() > 0.0:
		return "Seekers look in %d" % ceili(hide_left())
	return "You SEEK  ·  find the blocks that move" if is_seeker(world.local_player) else "You HIDE  ·  stay still, pop balloons"


func hud_rank() -> String:
	var n := Teams.counts(world)[HIDERS]
	return "%d hider%s left" % [n, "" if n == 1 else "s"] if started else ""


func annotate_rows(rows: Array) -> void:
	super(rows)
	for r: Dictionary in rows:
		r.points = int(points.get(int(r.id), 0))
		r.catches = int(catches.get(int(r.id), 0))
		r.balloons = int(balloons.get(int(r.id), 0))


func sort_rows(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("team", -1)) != int(b.get("team", -1)):
			return int(a.get("team", -1)) < int(b.get("team", -1))
		return int(a.get("points", 0)) > int(b.get("points", 0)))


func score_columns() -> Array:
	return ["POINTS", "CATCHES", "BALLOONS"]


func row_cells(r: Dictionary) -> Array:
	return [int(r.get("points", 0)), int(r.get("catches", 0)), int(r.get("balloons", 0))]


func row_tag(r: Dictionary) -> String:
	return "SEEKER" if int(r.get("team", -1)) == SEEKERS else "HIDER"


func group_header(team: int, rows: Array) -> String:
	var n := 0
	for r: Dictionary in rows:
		if int(r.get("team", -1)) == team:
			n += 1
	return "%s  ·  %d" % [Teams.label(team), n]


func results_title(rows: Array, next: Dictionary) -> Array:
	var winner := int(next.get("winner", HIDERS))
	var text := "THE BLOCKS STAY HIDDEN" if winner == HIDERS else "EVERY BLOCK FOUND"
	var mine := _my_row(rows)
	if not mine.is_empty():
		text = ("VICTORY!  " if bool(mine.get("won", false)) else "DEFEAT  ·  ") + text
	return [text, Teams.color(winner)]


func win_banner(next: Dictionary) -> String:
	return "HIDERS WIN!" if int(next.get("winner", HIDERS)) == HIDERS else "SEEKERS WIN!"


func hides_award(_stat: String) -> bool:
	return true


func extra_highlights(rows: Array) -> Array:
	var out: Array = []
	var me := world.my_id()
	var hidden: Array[String] = []
	var mine := false
	for r: Dictionary in rows:
		if int(r.get("team", -1)) == HIDERS:
			hidden.append(str(r.name))
			mine = mine or int(r.id) == me
	if not hidden.is_empty():
		out.append(["Never found:  %s" % ", ".join(hidden), mine, "never_found"])
	var best: Dictionary = {}
	for r: Dictionary in rows:
		if int(r.get("balloons", 0)) > 0 and (best.is_empty() or int(r.balloons) > int(best.balloons)):
			best = r
	if not best.is_empty():
		out.append(["Party animal:  %s  (%d balloons)" % [best.name, int(best.balloons)], int(best.id) == me, "party_animal"])
	return out


# ================================================================ bots

## A seeker makes out a block only by what gives it away (Hiding.Watch): moving, not yet settled
## on the grid, glowing from a balloon, or a colour that stands out against what's behind it.
func bot_notices(p: Player, other: Player) -> bool:
	if not is_seeker(p) or not seeking():
		return false
	var eye := p.head.global_position
	var center := other.global_position + Vector3.UP * 0.5
	var d := eye.distance_to(center)
	if d < Hiding.BUMP_RANGE:
		return true
	var block := int(other.info.get("disguise", BlockAtlas.STONE))
	var bg: Array = Hiding.backdrop(world, eye, center)
	var c := Hiding.contrast(BlockAtlas.top_color(block), bg[0])
	if int(bg[1]) == block:
		c *= 0.2
	var moving := Hiding.speed_of(other) > Hiding.MOVING
	var g: Array = _glow.get(other.id, [])
	var glowing := not g.is_empty() and World.now() < float(g[0])
	var base := 4.0 if moving else (0.08 + 1.6 * c) * (1.0 if settled(other) else 3.0)
	var near := clampf(1.0 - d / 50.0, 0.1, 1.0)
	var rate := (base + (3.0 if glowing else 0.0)) * near * Hiding.light() * 2.0 \
		* float(Hiding.SKILL[p.brain.difficulty if p.brain != null else 1])
	return _watch.see(p, other, rate)


## Seekers search spots they haven't checked lately (balloons pull them via BotBrain.investigate).
func bot_roam_goal(p: Player) -> Variant:
	if not is_seeker(p) or not seeking():
		return null
	var now := World.now()
	var goal: Variant = _search.get(p.id)
	if goal != null and p.global_position.distance_to(goal) > 2.5:
		return goal
	if goal != null:
		_visited[Vector2i(floori(goal.x / 9.0), floori(goal.z / 9.0))] = now
	var best: Variant = null
	var best_s := -INF
	for s: Array in Hiding.spots(world, p, [], []):
		var pos: Vector3 = s[1]
		var seen_at := float(_visited.get(Vector2i(floori(pos.x / 9.0), floori(pos.z / 9.0)), -INF))
		var score := float(s[0]) - (30.0 if now - seen_at < 50.0 else 0.0) - pos.distance_to(p.global_position) * 0.08
		if score > best_s:
			best_s = score
			best = pos
	_search[p.id] = best
	return best


func bot_drive(p: Player, brain: BotBrain, delta: float) -> bool:
	if is_seeker(p):
		# Blindfolded while the hiders hide: turn on the spot.
		if not seeking():
			brain.look_toward(p.global_position + Basis(Vector3.UP, p.yaw + 0.6) * Vector3.FORWARD * 5.0 + Vector3.UP * 1.5, delta, 0.3)
			return true
		return false
	return _drive_hider(p, brain, delta)


func _seeker_positions() -> Array:
	var out: Array = []
	for eid: int in world.entities:
		var s: Player = world.entities[eid]
		if s.alive and is_seeker(s):
			out.append(s.global_position)
	if out.is_empty():
		for sp: Vector3 in world.map_info.spawns:
			out.append(sp)
	return out


## A hider bot: picks the spot and block that blend in best, goes there and holds still; when
## safe it releases balloons (the safer, the bigger); hit or with a seeker on top of it, it runs.
func _drive_hider(p: Player, brain: BotBrain, delta: float) -> bool:
	var now := World.now()
	var plan: Dictionary = _hide.get(p.id, {})
	var threats := _seeker_positions()
	var nearest := INF
	var watched := false
	for eid: int in world.entities:
		var s: Player = world.entities[eid]
		if not s.alive or not is_seeker(s) or not seeking():
			continue
		var d := s.global_position.distance_to(p.global_position)
		nearest = minf(nearest, d)
		if not watched and d < 30.0 and Hiding.exposure(world, s.head.global_position, p) > 0.0:
			watched = true
	var hurt := now - p.last_hurt_time < 1.5
	var panic := hurt or nearest < PANIC_RANGE
	if plan.is_empty() or (panic and now > float(plan.get("flee_until", 0.0))):
		var blocks: Array = p.info.get("block_choices", []) if picking() else [int(p.info.get("disguise", BlockAtlas.STONE))]
		var spot := _pick_spot(p, threats, blocks)
		plan = {"spot": spot[0], "flee_until": now + 3.0 if panic else 0.0, "greed": randf_range(0.7, 1.3)}
		_hide[p.id] = plan
		brain.drop_route()
		var choices: Array = p.info.get("block_choices", [])
		if picking() and choices.has(spot[1]):
			server_pick(p.id, choices.find(spot[1]))
	var spot_pos: Vector3 = plan.spot
	if p.global_position.distance_to(spot_pos) > 1.0:
		brain.move_to(spot_pos, delta, panic or not seeking())
		return true
	# At the spot: stand still (the block settles onto the grid) and maybe release a balloon.
	if seeking() and settled(p) and not watched and now >= float(_balloon_ready.get(p.id, 0.0)):
		var safe := nearest / float(plan.greed)
		var size := 2 if safe > 45.0 else (1 if safe > 28.0 else (0 if safe > 14.0 else -1))
		if size >= 0:
			server_balloon(p.id, size)
	return true


## [spot, block]: the best place for `p` to hide away from `threats`, not one another hider bot
## took, with the disguise of `blocks` that blends in there.
func _pick_spot(p: Player, threats: Array, blocks: Array) -> Array:
	var taken: Array[Vector3] = []
	for eid: int in _hide:
		if eid != p.id:
			taken.append(_hide[eid].spot)
	var ranked := Hiding.spots(world, p, threats, blocks)
	for s: Array in ranked.slice(0, 6):
		var ok := true
		for t in taken:
			if t.distance_to(s[1]) < 3.0:
				ok = false
				break
		if ok:
			return [s[1], s[2]]
	return [ranked[0][1], ranked[0][2]] if not ranked.is_empty() else [p.global_position, -1]
