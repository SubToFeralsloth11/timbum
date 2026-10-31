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
			text = "Aim at the gold ledge on the tower and press [%s] to grapple up onto it" % key("grapple")
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
			_grappled = _grappled or p.grappling
			var ledge: AABB = world.map_info.marks.ledge
			done = _grappled and on_floor and not p.grappling and ledge.has_point(p.global_position + Vector3.UP * 0.1)
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
			p.grapple_cooldown = 0.0
	_start_slot = p.current_slot


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
