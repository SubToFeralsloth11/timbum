class_name Tutorial
extends FiringRange
## The first-run tutorial (`Net.config.session` "tutorial", offline): the Firing Range with a
## guided list of steps (STEPS) shown by TutorialCard. Each prompt names the player's own bindings
## (Profile.key_text: keyboard, or the controller's buttons when the pad was used last), the step
## checks the local player's state every physics frame (`_check`) and moves on by itself
## DONE_PAUSE after it is done. The pause menu has SKIP STEP and SKIP TUTORIAL (back to the main
## menu, no reward). Reaching the end (skipped steps included) calls Profile.finish_tutorial: the
## first time it pays Data.TUTORIAL_REWARD with a toast, a replay pays nothing. Everything else is
## the Firing Range (dummies, console, nothing counts), without its readout card.
##
## The grapple step puts the player on a glowing floor ring GRAPPLE_START metres in front of the
## tower, facing a glowing target on the gold ledge's face. A hook that lands on the marked ledge
## area (the ledge's box grown by LEDGE_HOOK_MARGIN) ends in a short auto-mantle onto the top once
## the pull has brought the player up beside the edge (MANTLE_REACH below the top, MANTLE_SIDE
## out from the tower); a missed attempt (the player back on the ground) puts them back on the
## ring with a "try again" line.

## [id, title]; the prompt for each is `prompt()`.
const STEPS: Array = [
	["move", "MOVE"], ["look", "LOOK AROUND"], ["jump", "JUMP"], ["sprint", "SPRINT"], ["slide", "SLIDE"],
	["crouch", "CROUCH"], ["prone", "GO PRONE"], ["peek_left", "PEEK LEFT"], ["peek_right", "PEEK RIGHT"],
	["aim", "AIM DOWN SIGHTS"], ["shoot", "SHOOT A DUMMY"], ["reload", "RELOAD"], ["switch", "SWITCH WEAPONS"],
	["melee", "QUICK MELEE"], ["frag", "FRAG GRENADE"], ["tactical", "TACTICAL GRENADE"], ["grapple", "GRAPPLE"],
]
## Seconds the ✓ shows before the next step.
const DONE_PAUSE := 0.9
const MOVE_DISTANCE := 4.0
const LOOK_ANGLE := 1.6
const SPRINT_TIME := 1.0
const CROUCH_TIME := 0.5
## Grapple step: start spot distance in front of the ledge face, the hook area around the ledge,
## how far below the top / out from the tower the auto-mantle reaches, its length, and how long a
## failed attempt stands on the ground before the player goes back to the ring.
const GRAPPLE_START := 6.0
const LEDGE_HOOK_MARGIN := 0.6
const MANTLE_REACH := 2.6
const MANTLE_SIDE := 1.6
const MANTLE_TIME := 0.35
const RETRY_DELAY := 0.6
const RETRY_NOTE_TIME := 3.0

## Index into STEPS (STEPS.size() once finished).
var step := 0
var finished := false
## Coins Profile.finish_tutorial paid (0 on a replay; -1 before the end).
var reward := -1
## [[step id, seconds since the tutorial started, "done" | "skipped"], ...].
var timeline: Array = []
var card: TutorialCard
## Counting down while the finished step's ✓ shows (negative: the step is running).
var done_left := -1.0
## The running step's progress toward its goal (0-1, for the card's bar).
var progress := 0.0
var _acc := 0.0
var _started := -1.0
var _last_pos := Vector3.ZERO
var _last_yaw := 0.0
var _last_pitch := 0.0
var _start_slot := 0
var _grappled := false
## Shot / throw kinds and dummy hits seen since the step began.
var _shot_kinds := {}
var _hit := false
## Grapple step: the hook landed on the marked ledge, the mantle in progress ([from, edge, to],
## seconds into it; empty when none), time on the ground after a failed try, the retry note's
## countdown, and the ring / ledge target meshes (shown during the step only).
var _hooked_ledge := false
var _mantle: Array = []
var _mantle_t := 0.0
var _fail_t := 0.0
var _retry_note := 0.0
var _grapple_marks: Array[Node3D] = []


func _init() -> void:
	super()
	name = "Tutorial"


func _ready() -> void:
	super()
	overlay.show_readout = false
	card = TutorialCard.new()
	card.name = "TutorialCard"
	card.setup(self)
	add_child(card)
	_build_grapple_marks()


func practice_intro() -> Array:
	return ["TUTORIAL", "Follow the card at the top  ·  %s: skip a step or the tutorial" % Profile.key_text("pause")]


func shows_controls_hint() -> bool:
	return false


func pause_actions() -> Array:
	if finished:
		return super()
	return [["SKIP STEP", skip_step], ["SKIP TUTORIAL", skip_tutorial]]


func step_id() -> String:
	return "" if finished else str(STEPS[step][0])


func step_title() -> String:
	return "" if finished else str(STEPS[step][1])


# ================================================================ prompts

## What the player presses for `action`, as on screen: the bound key, or the pad's button while
## the controller is in use (a pad without that button says which key does it).
static func key(action: String) -> String:
	if Profile.using_pad and Profile.get_pad_binding(action).is_empty():
		return "%s (no controller button: bind one in Settings > Controls)" % Profile.key_text(action)
	return Profile.key_text(action)


## The current step's instruction with the player's bindings (read every frame, so a switch
## between keyboard and controller shows at once).
func prompt() -> String:
	var p := world.local_player
	var get_up := ""
	if p != null and p.prone and step_id() not in ["prone", "move", "look"]:
		get_up = "Get up with [%s], then: " % key("prone")
	var text := ""
	match step_id():
		"move":
			text = "Walk around with the LEFT STICK" if Profile.using_pad else "Walk around with [%s] [%s] [%s] [%s]" % [
				key("move_forward"), key("move_left"), key("move_back"), key("move_right")]
		"look":
			text = "Look around with the RIGHT STICK" if Profile.using_pad else "Move the mouse to look around"
		"jump":
			text = "Press [%s] to jump" % key("jump")
		"sprint":
			text = "Hold [%s] while moving forward to sprint" % key("sprint")
		"slide":
			text = "Sprint, then press [%s] to slide" % key("crouch")
		"crouch":
			text = "Hold [%s] to crouch" % key("crouch")
		"prone":
			text = "Press [%s] to lie down (prone)" % key("prone")
		"peek_left":
			text = "Hold [%s] to peek left" % key("lean_left")
		"peek_right":
			text = "Hold [%s] to peek right" % key("lean_right")
		"aim":
			text = "Hold [%s] to aim down the sights" % key("aim")
		"shoot":
			text = "Shoot a dummy downrange with [%s]" % key("fire")
		"reload":
			text = "Press [%s] to reload" % key("reload")
		"switch":
			text = "Press [%s] to switch weapons" % key("next_weapon") if Profile.using_pad \
				else "Press [%s] for your secondary (or [%s] / the mouse wheel)" % [key("weapon_2"), key("weapon_1")]
		"melee":
			text = "Press [%s] for a quick melee" % key("melee")
		"frag":
			text = "Press [%s] to throw a frag grenade" % key("grenade")
		"tactical":
			text = "Press [%s] to throw your tactical grenade" % key("tactical")
		"grapple":
			text = "Stand on the glowing ring, put your crosshair on the glowing target on the gold ledge and press [%s]: the hook pulls you up and you climb onto it" % key("grapple")
			if _retry_note > 0.0:
				text = "Missed: back on the ring, try again. " + text
	return get_up + text


# ================================================================ steps

func _physics_process(delta: float) -> void:
	super(delta)
	if world.is_frozen() or finished:
		return
	var p := world.local_player
	if p == null or not p.alive:
		return
	if _started < 0.0:
		_started = World.now()
		_begin_step(p)
	if done_left >= 0.0:
		done_left -= delta
		if done_left < 0.0:
			_advance()
		return
	if _check(p, delta):
		progress = 1.0
		_complete("done")


## Whether the running step is done; updates `progress`.
func _check(p: Player, delta: float) -> bool:
	var on_floor := p.is_on_floor()
	var done := false
	match step_id():
		"move":
			var moved := Vector2(p.global_position.x - _last_pos.x, p.global_position.z - _last_pos.z).length()
			if on_floor and p.in_move != Vector2.ZERO and moved < 2.0:
				_acc += moved
			progress = _acc / MOVE_DISTANCE
		"look":
			_acc += absf(wrapf(p.yaw - _last_yaw, -PI, PI)) + absf(p.pitch - _last_pitch)
			progress = _acc / LOOK_ANGLE
		"jump":
			done = not on_floor and p.velocity.y > 2.0 and not p.grappling
		"sprint":
			if p.sprinting:
				_acc += delta
			progress = _acc / SPRINT_TIME
		"slide":
			done = p.sliding
		"crouch":
			if p.crouching and not p.sliding and not p.prone:
				_acc += delta
			progress = _acc / CROUCH_TIME
		"prone":
			done = p.prone
		"peek_left":
			progress = clampf(-p.lean / 0.6, 0.0, 1.0)
		"peek_right":
			progress = clampf(p.lean / 0.6, 0.0, 1.0)
		"aim":
			progress = p.aim_blend / 0.95
		"shoot":
			done = _hit
		"reload":
			done = p.reloading
		"switch":
			done = p.current_slot != _start_slot
		"melee":
			done = _shot_kinds.has(p.melee_id())
		"frag":
			done = _shot_kinds.has("grenade")
		"tactical":
			done = _shot_kinds.has("smoke") or _shot_kinds.has("flash")
		"grapple":
			done = _grapple_check(p, delta, on_floor)
	_last_pos = p.global_position
	_last_yaw = p.yaw
	_last_pitch = p.pitch
	progress = clampf(progress, 0.0, 1.0)
	return done or progress >= 1.0


## Sets the running step up: fresh counters, and what it needs (a gun with a part-empty magazine
## to reload, a gun to aim or shoot, grenades, a ready hook).
func _begin_step(p: Player) -> void:
	_acc = 0.0
	progress = 0.0
	_shot_kinds.clear()
	_hit = false
	_grappled = false
	_last_pos = p.global_position
	_last_yaw = p.yaw
	_last_pitch = p.pitch
	match step_id():
		"aim", "shoot", "reload":
			if p.current_slot == 2:
				p.switch_to(0 if not p.slots[0].is_empty() else 1)
			if step_id() == "reload":
				var wid := p.slots[0] if not p.slots[0].is_empty() else p.slots[1]
				var a: Vector2i = p.ammo[wid]
				a.x = mini(a.x, maxi(1, p.mag_size(wid) / 2))
				p.ammo[wid] = a
		"frag", "tactical":
			world.refill_equipment(p.id)
		"grapple":
			_reset_grapple(p)
			_retry_note = 0.0
	for m: Node3D in _grapple_marks:
		m.visible = step_id() == "grapple"
	_start_slot = p.current_slot


# ================================================================ grapple step

func _ledge() -> AABB:
	return world.map_info.marks.ledge


## Where the grapple step starts (the floor ring): GRAPPLE_START in front of the ledge's south face.
func grapple_start() -> Vector3:
	var l := _ledge()
	return Vector3(l.get_center().x, (world.map_info.marks.line as Vector3).y, l.end.z + GRAPPLE_START)


## The glowing target on the ledge face (the gold edge, mid-face).
func grapple_target() -> Vector3:
	var l := _ledge()
	return Vector3(l.get_center().x, l.position.y, l.end.z)


## The ledge's walkable top height (ray down onto the tower; the box bottom + 0.5 if none).
func _ledge_top(at: Vector3) -> float:
	var l := _ledge()
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, l.end.y, at.z), Vector3(at.x, l.position.y - 1.0, at.z), Player.MASK_WORLD)
	var r := world.get_world_3d().direct_space_state.intersect_ray(q)
	return (r.position as Vector3).y if not r.is_empty() else l.position.y + 0.5


## Puts the player on the ring facing the target with a ready hook.
func _reset_grapple(p: Player) -> void:
	p.release_grapple()
	p.grapple_cooldown = 0.0
	p.global_position = grapple_start()
	p.velocity = Vector3.ZERO
	var d := grapple_target() - p.head.global_position
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	_grappled = false
	_hooked_ledge = false
	_mantle = []
	_fail_t = 0.0


## The grapple step's check: a hook on the marked ledge area ends in an auto-mantle onto the top
## once the pull has the player up beside the edge; done when they stand on the ledge. A failed try
## (back on the ground below) returns them to the ring after RETRY_DELAY.
func _grapple_check(p: Player, delta: float, on_floor: bool) -> bool:
	var l := _ledge()
	_retry_note = maxf(0.0, _retry_note - delta)
	if p.grappling:
		_grappled = true
		if l.grow(LEDGE_HOOK_MARGIN).has_point(p.grapple_point):
			_hooked_ledge = true
	if not _mantle.is_empty():
		_mantle_t += delta
		var k := clampf(_mantle_t / MANTLE_TIME, 0.0, 1.0)
		# Up the face first (first half), then in over the edge.
		var pos: Vector3 = (_mantle[0] as Vector3).lerp(_mantle[1], minf(1.0, k * 2.0)) if k < 0.5 \
			else (_mantle[1] as Vector3).lerp(_mantle[2], k * 2.0 - 1.0)
		p.global_position = pos
		p.velocity = Vector3.ZERO
		if k >= 1.0:
			_mantle = []
		return false
	var pos := p.global_position
	var inside := Vector3(clampf(pos.x, l.position.x, l.end.x), pos.y, clampf(pos.z, l.position.z, l.end.z))
	var side := Vector2(pos.x - inside.x, pos.z - inside.z).length()
	if _hooked_ledge and side <= MANTLE_SIDE and not l.has_point(pos + Vector3.UP * 0.1):
		var to := Vector3(clampf(pos.x, l.position.x + 0.8, l.end.x - 0.8), 0.0, clampf(pos.z, l.position.z + 0.8, l.end.z - 0.8))
		var top := _ledge_top(to)
		if pos.y >= top - MANTLE_REACH:
			p.release_grapple()
			to.y = top + 0.05
			_mantle = [pos, Vector3(pos.x, top + 0.15, pos.z), to]
			_mantle_t = 0.0
			return false
	if on_floor and not p.grappling and l.has_point(pos + Vector3.UP * 0.1):
		return _grappled
	if _grappled and on_floor and not p.grappling:
		_fail_t += delta
		if _fail_t >= RETRY_DELAY:
			_reset_grapple(p)
			_retry_note = RETRY_NOTE_TIME
	else:
		_fail_t = 0.0
	return false


## The floor ring at the start spot and the target on the ledge face (glowing, gold; hidden
## outside the grapple step).
func _build_grapple_marks() -> void:
	if not world.map_info.marks.has("ledge"):
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.82, 0.25, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.82, 0.25)
	# The ring on the floor.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.95
	torus.rings = 32
	torus.ring_segments = 4
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.position = grapple_start() + Vector3.UP * 0.04
	# The target on the face: two rings (bull's-eye) standing on the face, just in front of it.
	var target := Node3D.new()
	target.position = grapple_target() + Vector3(0.0, 0.0, 0.03)
	for r: Vector2 in [Vector2(0.55, 0.75), Vector2(0.12, 0.26)]:
		var m := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = r.x
		t.outer_radius = r.y
		t.rings = 32
		t.ring_segments = 4
		m.mesh = t
		m.rotation.x = PI * 0.5
		m.scale = Vector3(1.0, 0.1, 1.0)
		target.add_child(m)
	for n: Node3D in [ring, target]:
		n.visible = false
		world.add_child(n)
		_grapple_marks.append(n)
	for n: Node in [ring] + target.get_children():
		(n as MeshInstance3D).material_override = mat
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _complete(how: String) -> void:
	timeline.append([step_id(), snappedf(World.now() - _started, 0.01), how])
	if how == "done":
		done_left = DONE_PAUSE
		Sfx.play(&"pickup_ammo", null, -4.0)
	else:
		_advance()


func _advance() -> void:
	done_left = -1.0
	step += 1
	if step >= STEPS.size():
		_finish()
		return
	if world.local_player != null:
		_begin_step(world.local_player)


## Pause menu SKIP STEP.
func skip_step() -> void:
	if finished:
		return
	_complete("skipped")


## Pause menu SKIP TUTORIAL: back to the main menu, no reward.
func skip_tutorial() -> void:
	timeline.append(["(tutorial)", snappedf(World.now() - _started, 0.01), "skipped"])
	Net.leave()


func _finish() -> void:
	finished = true
	step = STEPS.size()
	for m: Node3D in _grapple_marks:
		m.visible = false
	reward = Profile.finish_tutorial()
	if reward > 0:
		world.hud.feat_toast("TUTORIAL COMPLETE", "+%d COINS" % reward)
		Sfx.play(&"coins")
	else:
		world.hud.feat_toast("TUTORIAL COMPLETE", "Replay: the coin bonus was paid the first time")
	# The range's readout is back for practice.
	overlay.show_readout = true


func on_local_shot(p: Player, wid: String, ends: PackedVector3Array, hits: Dictionary) -> void:
	super(p, wid, ends, hits)
	_shot_kinds[wid] = true


func on_local_hit(head: bool, killed: bool, amount: float, pos: Vector3, wid: String) -> void:
	super(head, killed, amount, pos, wid)
	_hit = true
