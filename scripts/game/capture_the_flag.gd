class_name CaptureTheFlag
extends TeamDeathmatch
## Capture the Flag (`Net.config.mode == "ctf"`): two teams (Teams: ALPHA / BRAVO) on the
## deathmatch maps with respawns, each with a flag on a stand at its base (`flag_stands`: the map's
## `flags` mark: MapKit.flag_stands on the built-in maps, on its own half of the map, ALPHA the low
## end of the longer axis as TeamDeathmatch.along splits it; the Map Editor's FLAGS tool on a
## custom map, else the two spawns farthest apart, `spawn_stands`; a map with neither is not
## offered for the mode, CustomMaps.ctf_problems). Walk over the enemy flag to take it; carry it onto your
## own stand while your own flag is home to capture it (+1 team score, the flag goes home). The
## carrier is CARRIER_SPEED times as fast and can't grapple (MatchMode.move_mult / grapple_allowed).
## A carrier who dies or leaves drops the flag where they were (straight home if that is over the
## void or water); a dropped flag goes home after RETURN_TIME s of match clock, or at once when a
## player of its team touches it (a return). The first team to `Net.config.kill_limit` captures
## (setup offers LIMITS, default DEFAULT_CAPTURES) wins, otherwise the higher score at the time
## limit; equal is a draw. Kills score nothing. Teams spawn on their own side (own_side_bonus):
## nearer their own stand than the enemy's (on_own_side).
## The server decides everything and tells every peer with `_s_flag` (one flag's state plus the
## event that changed it); joiners get both flags with `_s_flags`, the score with TDM's `_s_score`.
## Every peer draws the stands and flags (the carried one on the carrier's back; in a kill cam
## replay each flag as the tape recorded it, replay_mark_*, a carried one on its carrier's ghost),
## the FlagOverlay
## (world markers through walls, the carrier banner), compass pips, the score card's flag states
## (hud_team_status) and the callouts. Bots split into attackers and defenders (_bot_plan).

const DEFAULT_CAPTURES := 3
## Capture limits offered in match setup.
const LIMITS: Array[int] = [1, 3, 5]
## Seconds of match clock before a dropped flag goes home by itself.
const RETURN_TIME := 20.0
## A player touches a flag (or their stand) with feet this close (flat metres) and within
## TOUCH_BELOW..TOUCH_ABOVE metres of its height.
const TOUCH_RADIUS := 1.6
const TOUCH_BELOW := 1.2
const TOUCH_ABOVE := 2.2
## The two stands must be at least this far apart (flat metres): well over the 2 x TOUCH_RADIUS at
## which one player could touch both at once, so every capture is a run (custom maps: the Map
## Editor's stands and the spawn pair standing in for them).
const MIN_STAND_GAP := 12.0
## The carrier's speed (walk, sprint and slide) as a fraction of normal.
const CARRIER_SPEED := 0.85
## Spawn ranking bonus for the own half: far above any other term, so a team always spawns there.
const SIDE_BONUS := 2000.0
## Bots: metres closer an enemy flag carrier counts when picking a target, the radius defenders
## patrol around their stand, how far an attacker goes to return its own dropped flag or chase the
## enemy carrier, and how far behind its own carrier an escort follows.
const CARRIER_BIAS := 30.0
const DEFEND_RADIUS := 9.0
const RETURN_RANGE := 35.0
const CHASE_RANGE := 30.0
const ESCORT_DIST := 4.0

enum State { HOME, CARRIED, DROPPED }

## Feet positions of the two stands [ALPHA, BRAVO] (every peer builds the same from the map).
var stands: Array[Vector3] = []
## Per flag (index = the team it belongs to): its State, the carrier's entity id (0: none), its
## feet position (the stand, the drop spot, or where the carrier was), and the match clock
## (`World.time_left`) at which a dropped flag goes home. Server values on every peer.
var flag_state: Array[int] = [State.HOME, State.HOME]
var carrier: Array[int] = [0, 0]
var flag_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var return_at: Array[float] = [0.0, 0.0]
## Entity id -> captures, and returns of their own team's flag (server values on every peer).
var captures := {}
var returns := {}

# Every peer: the look.
var _stand_nodes: Array[Node3D] = []
var _flag_nodes: Array[Node3D] = []
## Per flag: its cloth segments (waving), team-coloured materials, light, beam (shown when
## dropped) and every GeometryInstance3D (shadow-only on a first-person carrier).
var _cloth: Array = [[], []]
var _team_mats: Array = [[], []]
var _lights: Array[OmniLight3D] = []
var _beams: Array[Node3D] = []
var _geoms: Array = [[], []]
var _stand_mats: Array = [[], []]
var _palette := -1
var _first_person: Array[bool] = [false, false]
var _overlay: FlagOverlay
## Entity id -> its avatar's torso node (_torso_of); kill cam ghost instance id -> its torso.
var _torsos := {}
var _ghost_torsos := {}


func _init() -> void:
	name = "CaptureTheFlag"
	# The flags follow avatars and kill cam ghosts posed this frame: place them after those.
	process_priority = 1


func _ready() -> void:
	stands = flag_stands(world.map_info)
	# Net.load_map never starts the mode on a map without stands (CustomMaps.ctf_problems); the
	# server loop and the look skip it all the same.
	if stands.size() < 2:
		push_error("CaptureTheFlag: %s has no flag stands" % world.map_info.id)
		return
	for t in 2:
		flag_pos[t] = stands[t]
		_stand_nodes.append(_build_stand(t))
		_flag_nodes.append(_build_flag(t))
	_recolor()
	_overlay = FlagOverlay.new()
	_overlay.name = "FlagOverlay"
	_overlay.setup(self)
	add_child(_overlay)


## The two stands' feet positions [ALPHA, BRAVO]: the map's `flags` mark (every deathmatch map,
## MapKit.flag_stands; a custom map's FLAGS stands, CustomMaps.generate), else spawn_stands();
## empty when there is no such pair.
static func flag_stands(info: MapInfo) -> Array[Vector3]:
	var marks: Array = info.marks.get("flags", [])
	if marks.size() == 2:
		var out: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
		for m: Dictionary in marks:
			out[clampi(int(m.get("team", 0)), 0, 1)] = m.pos
		return out
	return spawn_stands(info.spawns)


## A custom map without stands: the two spawns farthest apart (flat distance) [ALPHA, BRAVO],
## ALPHA the lower end of the axis the pair spreads over most (x on a tie, z when they share an x),
## or empty when no two spawns are MIN_STAND_GAP apart. Same answer on every peer.
static func spawn_stands(spawns: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var best := MIN_STAND_GAP - 0.001
	for i in spawns.size():
		var a: Vector3 = spawns[i]
		for j in range(i + 1, spawns.size()):
			var b: Vector3 = spawns[j]
			var d := Vector2(a.x - b.x, a.z - b.z).length()
			if d > best:
				best = d
				out = [a, b]
	if out.is_empty():
		return out
	var gap := out[1] - out[0]
	var flip := gap.x < 0.0 if absf(gap.x) >= absf(gap.z) else gap.z < 0.0
	if flip:
		out.reverse()
	return out


## Which flag `p` carries (-1: none).
func carried_by(p: Player) -> int:
	if p == null:
		return -1
	for f in 2:
		if flag_state[f] == State.CARRIED and carrier[f] == p.id:
			return f
	return -1


## Where flag `f` is now: on its stand, where it was dropped, or with its carrier.
func flag_world_pos(f: int) -> Vector3:
	if flag_state[f] == State.CARRIED:
		var p: Player = world.entities.get(carrier[f])
		if p != null:
			return p.global_position
	return flag_pos[f]


## Seconds until dropped flag `f` goes home by itself.
func return_in(f: int) -> float:
	return maxf(0.0, world.time_left - return_at[f])


static func _touches(feet: Vector3, spot: Vector3) -> bool:
	var dy := feet.y - spot.y
	return Vector2(feet.x - spot.x, feet.z - spot.z).length() <= TOUCH_RADIUS and dy >= -TOUCH_BELOW and dy <= TOUCH_ABOVE


# ================================================================ server

func own_side_bonus() -> float:
	return SIDE_BONUS


## A team's side is where its own stand is nearer than the enemy's (a custom map's stands may lie
## along any line; on the built-in maps this is the TeamDeathmatch.along half).
func on_own_side(pos: Vector3, team: int) -> bool:
	if stands.size() < 2:
		return super(pos, team)
	var mine := Vector2(pos.x - stands[team].x, pos.z - stands[team].z).length()
	var theirs := Vector2(pos.x - stands[1 - team].x, pos.z - stands[1 - team].z).length()
	return mine < theirs


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or world.match_over or stands.size() < 2:
		return
	for f in 2:
		match flag_state[f]:
			State.CARRIED:
				# A carrier who left (or died without a kill event) drops it where they were last.
				var p: Player = world.entities.get(carrier[f])
				if p == null or not p.alive:
					_server_drop(f, flag_pos[f], 0)
				else:
					flag_pos[f] = p.global_position
			State.DROPPED:
				if world.time_left <= return_at[f]:
					_server_return(f, 0)
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		var t := Teams.of(p)
		if not p.alive or t < 0:
			continue
		var feet := p.global_position
		var e := 1 - t
		if flag_state[t] == State.DROPPED and _touches(feet, flag_pos[t]):
			_server_return(t, eid)
		if flag_state[e] != State.CARRIED and carried_by(p) < 0 and _touches(feet, flag_pos[e]):
			_broadcast(&"_s_flag", [e, State.CARRIED, eid, feet, 0.0, "taken", eid, 0])
		if carrier[e] == eid and flag_state[e] == State.CARRIED and flag_state[t] == State.HOME and _touches(feet, stands[t]):
			_server_capture(p, e)
		if world.match_over:
			return


## Flag `f` falls where its carrier was (`at`), onto the floor below; over the void or water it
## goes straight home. `by`: who killed the carrier (0: nobody).
func _server_drop(f: int, at: Vector3, by: int) -> void:
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 40.0, Player.MASK_WORLD)
	var hit := space.intersect_ray(q)
	var kill_y := world.map_info.kill_y
	if at.y < kill_y or hit.is_empty() or (hit.position as Vector3).y < kill_y + 0.5:
		_broadcast(&"_s_flag", [f, State.HOME, 0, stands[f], 0.0, "reset", 0, 0])
		return
	_broadcast(&"_s_flag", [f, State.DROPPED, 0, hit.position, world.time_left - RETURN_TIME, "dropped", by, 0])


## Flag `f` goes home: returned by `by` (its team's player), or 0 when its timer ran out.
func _server_return(f: int, by: int) -> void:
	var total := 0
	if by != 0:
		total = int(returns.get(by, 0)) + 1
	_broadcast(&"_s_flag", [f, State.HOME, 0, stands[f], 0.0, "returned", by, total])


func _server_capture(p: Player, f: int) -> void:
	var t := 1 - f
	_broadcast(&"_s_flag", [f, State.HOME, 0, stands[f], 0.0, "captured", p.id, int(captures.get(p.id, 0)) + 1])
	score[t] += 1
	_broadcast(&"_s_score", [score[0], score[1]])
	if score[t] >= int(Net.config.kill_limit):
		world.server_end_match()


func server_sync(pid: int) -> void:
	super(pid)
	_s_flags.rpc_id(pid, flag_state, carrier, flag_pos, return_at, captures, returns)


func server_human_left(pid: int) -> void:
	var p: Player = world.entities.get(pid)
	var f := carried_by(p)
	if f >= 0:
		_server_drop(f, p.global_position, 0)
	super(pid)


## Kills score nothing; a carrier's death drops the flag where they fell.
func server_on_kill(victim_id: int, killer_id: int, _wid: String) -> void:
	var victim: Player = world.entities.get(victim_id)
	var f := carried_by(victim)
	if f >= 0:
		_server_drop(f, victim.global_position, killer_id if killer_id != victim_id else 0)


func server_finish(rows: Array) -> Dictionary:
	annotate_rows(rows)
	var winner := server_winner()
	for r: Dictionary in rows:
		r.won = winner >= 0 and int(r.team) == winner
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.team != b.team:
			return a.team == winner or (winner < 0 and a.team < b.team)
		return _better(a, b))
	return {"winner": winner, "score": [score[0], score[1]]}


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a.captures) != int(b.captures):
		return int(a.captures) > int(b.captures)
	if int(a.returns) != int(b.returns):
		return int(a.returns) > int(b.returns)
	return a.kills > b.kills if a.kills != b.kills else a.deaths < b.deaths


# ================================================================ every peer: state

## Flag `team` is now `p_state` (carried by `who`, at `pos`, going home at clock `ret_at`) because
## of `event` ("taken", "dropped", "returned", "captured", "reset": home from the void; "" for
## none) by `by`, whose captures or returns are now `total`.
@rpc("authority", "call_remote", "reliable")
func _s_flag(team: int, p_state: int, who: int, pos: Vector3, ret_at: float, event: String, by: int, total: int) -> void:
	if team < 0 or team > 1:
		return
	flag_state[team] = p_state
	carrier[team] = who
	flag_pos[team] = pos
	return_at[team] = ret_at
	var me := world.my_id()
	if event == "captured" and by != 0:
		captures[by] = total
		if by == me:
			world.my_facts.on_objective("captures")
	elif event == "returned" and by != 0:
		returns[by] = total
		if by == me:
			world.my_facts.on_objective("flag_returns")
	# The peer that moves the new carrier makes them let go of a held hook.
	var p: Player = world.entities.get(who)
	if p != null and p.mode != Player.Mode.REMOTE and p.grappling:
		p.release_grapple()
	if not world.match_over and not event.is_empty():
		_announce(team, event, by)
		if by == me and event in ["captured", "returned"]:
			world.check_live_feats()
	world.hud.refresh_scores()


## Both flags and every capture and return so far, for a peer that just loaded the match.
@rpc("authority", "call_remote", "reliable")
func _s_flags(states: Array, carriers: Array, positions: Array, rets: Array, all_captures: Dictionary, all_returns: Dictionary) -> void:
	for t in 2:
		flag_state[t] = int(states[t])
		carrier[t] = int(carriers[t])
		flag_pos[t] = positions[t]
		return_at[t] = float(rets[t])
	captures = all_captures
	returns = all_returns
	world.hud.refresh_scores()


## The callout and sound for an event on flag `team`, worded for the local player's side.
func _announce(team: int, event: String, by: int) -> void:
	var mine := Teams.of(world.local_player)
	var me := world.my_id()
	var who := "YOU" if by == me else world.display_name(by).to_upper()
	var own := team == mine
	var flag := "%s FLAG" % Teams.label(team)
	var text := ""
	var sound := &"ping"
	match event:
		"taken":
			if by == me:
				text = "YOU HAVE THE FLAG!  TAKE IT HOME"
				sound = &"pickup_ammo"
			elif own:
				text = "%s TOOK YOUR FLAG" % who
				sound = &"ping_enemy"
			elif mine >= 0:
				text = "%s HAS THE ENEMY FLAG" % who
			else:
				text = "%s TOOK THE %s" % [who, flag]
		"dropped":
			if own:
				text = "YOUR FLAG IS DOWN  ·  RETURN IT"
			elif mine >= 0:
				text = "ENEMY FLAG DROPPED"
			else:
				text = "%s DROPPED" % flag
			if by == me:
				text = "YOU STOPPED THE FLAG CARRIER"
		"returned", "reset":
			sound = &"spawn"
			if by == me:
				text = "YOU RETURNED YOUR FLAG"
			elif own:
				text = "YOUR FLAG IS BACK" if by == 0 else "%s RETURNED YOUR FLAG" % who
			elif mine >= 0:
				text = "ENEMY FLAG RETURNED"
			else:
				text = "%s RETURNED" % flag
		"captured":
			if by == me:
				text = "YOU CAPTURED THE FLAG!"
				sound = &"level_up"
			elif mine >= 0 and not own:
				text = "%s CAPTURED THE FLAG!" % who
				sound = &"streak_reward"
			elif own:
				text = "%s CAPTURED YOUR FLAG" % who
				sound = &"radar_sweep"
			else:
				text = "%s CAPTURED THE %s" % [who, flag]
				sound = &"streak_reward"
	if text.is_empty():
		return
	world.hud.callout(text, "flag", Teams.color(team).lightened(0.2))
	Sfx.play(sound, null, -4.0)


# ================================================================ every peer: the look

func _process(_delta: float) -> void:
	if stands.size() < 2:
		return
	if Palette.mode() != _palette:
		_recolor()
	var t := World.now()
	var kc := world.killcam
	var replay := kc.is_playing()
	for f in 2:
		var node := _flag_nodes[f]
		var state := flag_state[f]
		var at := flag_pos[f]
		var torso: Node3D = null
		var first_person := false
		if state == State.CARRIED:
			var p: Player = world.entities.get(carrier[f])
			if p != null and p.alive and p.avatar != null:
				# Every peer keeps the carried flag's position (markers, drops) with its carrier.
				flag_pos[f] = p.global_position
				torso = _torso_of(p)
				first_person = _is_first_person(p)
		if replay:
			# The kill cam replay shows each flag as it was then (KillCam tape): home, dropped where
			# it lay, or on its carrier's ghost; one the killer carried rides with the replay's own
			# eyes, so (like a first-person carrier's) it isn't drawn.
			var rs := kc.replay_mark_state(f)
			state = rs if rs >= 0 else state
			at = kc.replay_mark_pos(f)
			torso = null
			first_person = false
			if state == State.CARRIED:
				var ghost := kc.replay_ghost(kc.replay_mark_carrier(f))
				torso = _ghost_torso(ghost) if ghost != null else null
		node.visible = true
		match state:
			State.HOME:
				node.global_transform = Transform3D(Basis(Vector3.UP, t * 0.4), stands[f] + Vector3.UP * 0.18)
			State.DROPPED:
				var bob := 0.12 + 0.08 * sin(t * 3.0)
				node.global_transform = Transform3D(Basis(Vector3.UP, t * 1.2) * Basis(Vector3.RIGHT, 0.35), at + Vector3.UP * bob)
			State.CARRIED:
				if torso == null:
					node.visible = false
					first_person = false
				else:
					# On the back (the avatar faces -Z), leaning back, at 65 % size, with the cloth
					# above the head.
					var on_back := Transform3D(Basis(Vector3.RIGHT, 0.3).scaled(Vector3.ONE * 0.65), Vector3(0.0, 0.3, 0.2))
					node.global_transform = torso.global_transform.orthonormalized() * on_back
		_beams[f].visible = state == State.DROPPED
		if first_person != _first_person[f]:
			_first_person[f] = first_person
			var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for g: GeometryInstance3D in _geoms[f]:
				g.cast_shadow = mode
			_lights[f].visible = not first_person
		# The cloth waves (faster when carried), the stand's rim pulses while its flag is away.
		var speed := 9.0 if state == State.CARRIED else 4.0
		var segs: Array = _cloth[f]
		for i in segs.size():
			# Each piece shifts and turns a little behind the one before: a ripple with no gaps.
			var seg := segs[i] as Node3D
			var phase := t * speed - i * 0.9
			seg.position.z = sin(phase) * 0.018 * (i + 1)
			seg.rotation.y = cos(phase) * 0.18
		var away := state != State.HOME
		var pulse := 0.55 + 0.45 * sin(t * 6.0) if away else 1.0
		var col := Teams.color(f)
		for m: StandardMaterial3D in _stand_mats[f]:
			m.albedo_color = Color(col, float(m.get_meta(&"alpha")) * pulse)


## The avatar's torso of `p` (the carried flag rides on it), looked up once per avatar.
func _torso_of(p: Player) -> Node3D:
	var cached: Variant = _torsos.get(p.id)
	if is_instance_valid(cached) and p.avatar.is_ancestor_of(cached):
		return cached
	var torso := p.avatar.find_child("Torso", true, false) as Node3D
	_torsos[p.id] = torso
	return torso


## The torso of a kill cam ghost (KillCam.replay_ghost), looked up once per ghost.
func _ghost_torso(ghost: Avatar) -> Node3D:
	var key := ghost.get_instance_id()
	var cached: Variant = _ghost_torsos.get(key)
	if is_instance_valid(cached) and ghost.is_ancestor_of(cached):
		return cached
	var torso := ghost.find_child("Torso", true, false) as Node3D
	_ghost_torsos[key] = torso
	return torso


## Whether `p` is seen from their own eyes here: the local player, or the player a spectator follows.
func _is_first_person(p: Player) -> bool:
	if p == world.local_player:
		return true
	var s := world.spectator
	return s != null and s.view == Spectator.View.FOLLOW and s.target == p


## Re-tints both flags and stands in the current colour mode (Palette).
func _recolor() -> void:
	_palette = Palette.mode()
	for f in 2:
		var col := Teams.color(f)
		for m: StandardMaterial3D in _team_mats[f]:
			m.albedo_color = col
			m.emission = col
		_lights[f].light_color = col
		for m: StandardMaterial3D in _stand_mats[f]:
			m.albedo_color = Color(col, float(m.get_meta(&"alpha")))


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, geoms: Array) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	geoms.append(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## A glowing see-through material in the team colour (`alpha` of it; tinted by _recolor).
func _glow_mat(f: int, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.set_meta(&"alpha", alpha)
	_stand_mats[f].append(m)
	return m


## The stand: a dark stone slab with a glowing rim and pad in the team colour and a faint disc
## showing how close you must get.
func _build_stand(f: int) -> Node3D:
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	root.global_position = stands[f]
	var unused: Array = []
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.2, 0.21, 0.24)
	stone.roughness = 0.85
	_mesh(root, _box(Vector3(1.8, 0.16, 1.8)), Vector3(0, 0.08, 0), stone, unused)
	var rim := _glow_mat(f, 0.95)
	for side: Array in [[Vector3(1.86, 0.07, 0.1), Vector3(0, 0.17, 0.88)], [Vector3(1.86, 0.07, 0.1), Vector3(0, 0.17, -0.88)],
			[Vector3(0.1, 0.07, 1.86), Vector3(0.88, 0.17, 0)], [Vector3(0.1, 0.07, 1.86), Vector3(-0.88, 0.17, 0)]]:
		_mesh(root, _box(side[0]), side[1], rim, unused)
	_mesh(root, _box(Vector3(1.1, 0.02, 1.1)), Vector3(0, 0.17, 0), _glow_mat(f, 0.45), unused)
	var disc := CylinderMesh.new()
	disc.top_radius = TOUCH_RADIUS
	disc.bottom_radius = TOUCH_RADIUS
	disc.height = 0.02
	disc.radial_segments = 32
	disc.rings = 1
	_mesh(root, disc, Vector3(0, 0.03, 0), _glow_mat(f, 0.14), unused)
	for mi: MeshInstance3D in root.get_children():
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mi.material_override != stone else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root


## The flag: a metal pole with a gold cap, a four-piece cloth in the team colour (glowing) with the
## team's shape in white on it (▲ ALPHA, ◼ BRAVO: colour is never the only cue), a small light, and
## a tall beam shown while it lies dropped. Origin at the foot of the pole.
func _build_flag(f: int) -> Node3D:
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	var geoms: Array = _geoms[f]
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.78, 0.8, 0.85)
	metal.metallic = 0.6
	metal.roughness = 0.35
	_mesh(root, _box(Vector3(0.07, 2.0, 0.07)), Vector3(0, 1.0, 0), metal, geoms)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.8, 0.25)
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.75, 0.2)
	gold.emission_energy_multiplier = 0.6
	_mesh(root, _box(Vector3(0.15, 0.15, 0.15)), Vector3(0, 2.05, 0), gold, geoms)
	var cloth := StandardMaterial3D.new()
	cloth.emission_enabled = true
	cloth.emission_energy_multiplier = 0.9
	cloth.roughness = 0.9
	_team_mats[f].append(cloth)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.97, 0.97, 1.0)
	white.emission_enabled = true
	white.emission = Color(1, 1, 1)
	white.emission_energy_multiplier = 0.4
	for i in 4:
		var seg := Node3D.new()
		seg.position = Vector3(0.14 + i * 0.2, 1.68, 0)
		root.add_child(seg)
		_cloth[f].append(seg)
		_mesh(seg, _box(Vector3(0.23, 0.55, 0.05)), Vector3.ZERO, cloth, geoms)
		if i == 1:
			var emblem: Mesh
			if f == 0:
				var prism := PrismMesh.new()
				prism.size = Vector3(0.24, 0.22, 0.07)
				emblem = prism
			else:
				emblem = _box(Vector3(0.2, 0.2, 0.07))
			_mesh(seg, emblem, Vector3(0.1, 0.0, 0.0), white, geoms)
	var light := OmniLight3D.new()
	light.position = Vector3(0.4, 1.6, 0)
	light.light_energy = 1.6
	light.omni_range = 5.0
	light.shadow_enabled = false
	root.add_child(light)
	_lights.append(light)
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.12
	beam_mesh.bottom_radius = 0.3
	beam_mesh.height = 30.0
	beam_mesh.radial_segments = 10
	beam_mesh.rings = 1
	var beam := _mesh(root, beam_mesh, Vector3(0, 15.0, 0), _glow_mat(f, 0.3), [])
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	_beams.append(beam)
	for g: GeometryInstance3D in geoms:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


# ================================================================ every peer: movement hooks

func move_mult(p: Player) -> float:
	return CARRIER_SPEED if carried_by(p) >= 0 else 1.0


func grapple_allowed(p: Player) -> bool:
	return carried_by(p) < 0


# ================================================================ HUD and results

func annotate_rows(rows: Array) -> void:
	super(rows)
	for r: Dictionary in rows:
		if not r.has("captures"):
			r.captures = int(captures.get(int(r.id), 0))
		if not r.has("returns"):
			r.returns = int(returns.get(int(r.id), 0))


## Grouped by team, then captures, returns and kills.
func sort_rows(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("team", -1)) != int(b.get("team", -1)):
			return int(a.get("team", -1)) < int(b.get("team", -1))
		return _better(a, b))


func score_columns() -> Array:
	return ["CAPS", "RETURNS", "KILLS"]


func row_cells(r: Dictionary) -> Array:
	return [int(r.get("captures", 0)), int(r.get("returns", 0)), r.kills]


func hud_goal() -> String:
	var mine := Teams.of(world.local_player)
	var n := int(Net.config.kill_limit)
	var goal := "First team to %d capture%s" % [n, "" if n == 1 else "s"]
	return goal if mine < 0 else "Your team: %s  ·  %s" % [Teams.label(mine), goal.to_lower()]


## The kill cam records both flags: state, carrier and position (flag_pos).
func replay_mark_count() -> int:
	return 2 if stands.size() == 2 else 0


func replay_mark_state(k: int) -> int:
	return flag_state[k]


func replay_mark_carrier(k: int) -> int:
	return carrier[k] if flag_state[k] == State.CARRIED else 0


func replay_mark_pos(k: int) -> Vector3:
	return flag_pos[k]


func hud_team_status(team: int) -> String:
	match flag_state[team]:
		State.CARRIED:
			var who := "YOU" if carrier[team] == world.my_id() else world.display_name(carrier[team])
			return "TAKEN · %s" % who
		State.DROPPED:
			return "DROPPED · %d s" % ceili(return_in(team))
	return "FLAG HOME"


func compass_pips(cam: Camera3D) -> Array:
	var out: Array = []
	for f in 2:
		out.append([KingOfTheBlock._heading(cam, flag_world_pos(f)), Teams.color(f)])
	var mine := Teams.of(world.local_player)
	if mine >= 0 and carried_by(world.local_player) >= 0:
		out.append([KingOfTheBlock._heading(cam, stands[mine]), Color(1, 0.85, 0.35)])
	return out


## Flag Runner (most captures) and Flag Defender (most returns).
func extra_highlights(rows: Array) -> Array:
	var out: Array = []
	for a: Array in [["captures", "flag_runner", "capture", "captures"], ["returns", "flag_defender", "return", "returns"]]:
		var best: Dictionary = {}
		for r: Dictionary in rows:
			if int(r.get(a[0], 0)) > 0 and (best.is_empty() or int(r[a[0]]) > int(best[a[0]])):
				best = r
		if best.is_empty():
			continue
		var n := int(best[a[0]])
		out.append(["%s:  %s  (%d %s)" % [Data.MEDALS[a[1]].name, best.name, n, a[2] if n == 1 else a[3]], int(best.id) == world.my_id(), a[1]])
	return out


# ================================================================ bots

## Every bot of a team is an attacker except every third (by id), a defender.
func _is_defender(p: Player) -> bool:
	var t := Teams.of(p)
	var ids: Array[int] = []
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if o.is_bot and Teams.of(o) == t:
			ids.append(eid)
	ids.sort()
	ids.reverse()
	return ids.find(p.id) % 3 == 1


## A bot's job now: [goal, hold radius] (radius 0: fight and chase freely on the way).
## The carrier runs home (and holds there while its own flag is away); a dropped own flag is
## returned by defenders and anyone near; the enemy carrier is chased by defenders, by anyone near,
## and by everyone while their own team holds the enemy flag; defenders otherwise patrol their stand;
## attackers escort their own carrier or go for the enemy flag.
func _bot_plan(p: Player) -> Array:
	var t := Teams.of(p)
	if t < 0 or stands.size() < 2:
		return []
	var e := 1 - t
	if carrier[e] == p.id and flag_state[e] == State.CARRIED:
		return [stands[t], 1.0]
	var defender := _is_defender(p)
	var me := p.global_position
	if flag_state[t] == State.DROPPED and (defender or me.distance_to(flag_pos[t]) < RETURN_RANGE):
		return [flag_pos[t], 1.0]
	if flag_state[t] == State.CARRIED:
		var thief := flag_world_pos(t)
		if defender or me.distance_to(thief) < CHASE_RANGE or flag_state[e] == State.CARRIED:
			return [thief, 0.0]
	if defender:
		var ang := float(p.id) * 2.1 + World.now() * 0.12
		return [stands[t] + Vector3(cos(ang), 0.0, sin(ang)) * 4.0, DEFEND_RADIUS]
	if flag_state[e] == State.CARRIED:
		var runner: Player = world.entities.get(carrier[e])
		if runner != null:
			var ang := float(p.id) * 2.4
			return [runner.global_position + Vector3(cos(ang), 0.0, sin(ang)) * ESCORT_DIST, 0.0]
	return [flag_pos[e], 1.0]


func bot_roam_goal(p: Player) -> Variant:
	var plan := _bot_plan(p)
	return null if plan.is_empty() else plan[0]


func bot_hold_area(p: Player) -> Array:
	var plan := _bot_plan(p)
	if plan.is_empty() or float(plan[1]) <= 0.0:
		return []
	# A defender's area is its stand; the patrol point only moves the bot around inside it.
	var t := Teams.of(p)
	if float(plan[1]) == DEFEND_RADIUS:
		return [stands[t], DEFEND_RADIUS]
	return [plan[0], plan[1]]


func bot_target_bias(p: Player, other: Player) -> float:
	var f := carried_by(other)
	return CARRIER_BIAS if f >= 0 and f == Teams.of(p) else 0.0
