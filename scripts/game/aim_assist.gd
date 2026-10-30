class_name AimAssist
extends RefCounted
## Controller aim assist for the local player (Settings > Controls > Aim assist: Off / Low /
## Standard). It only works in offline matches against bots, with the controller in use: online it
## is always off, so a pad never has an edge over a mouse in multiplayer. Near an enemy the right
## stick turns slower (slowdown), and while either stick is pushed the view follows part of the
## target's movement across the screen (tracking). It never snaps onto a target or fires.

const LEVEL_NAMES: Array[String] = ["Off", "Low", "Standard"]
## Per level: the share of the stick's turn speed taken away with the crosshair on the target's
## centre (fading out toward the edge of the assist area).
const SLOWDOWN: Array[float] = [0.0, 0.3, 0.5]
const TRACKING: Array[float] = [0.0, 0.35, 0.6]
## The assist area: within RADIUS metres of the target's chest as seen from the camera, as an
## angle clamped to MIN_ANGLE..MAX_ANGLE (a distant target still gets a small area).
const RADIUS := 1.1
const MIN_ANGLE := 1.5
const MAX_ANGLE := 9.0
## Targets further away than this (m) get no assist.
const RANGE := 80.0

## Entity id of the target assisted last frame (0 none).
var target_id := 0
## Last frame's numbers, for tests: {target, strength, slowdown, track_yaw, track_pitch}.
var last := {}
var _last_yaw := 0.0
var _last_pitch := 0.0


static func level() -> int:
	return clampi(int(Profile.get_setting("aim_assist")), 0, LEVEL_NAMES.size() - 1)


## Whether aim assist works right now: switched on, the controller in use and the match offline.
static func active() -> bool:
	return Net.offline and Profile.using_pad and level() > 0


## This frame's stick turn `turn` (radians; x turns right, y looks down) after the assist.
## `sticks_pushed`: either stick is in use (tracking only follows while the player is playing).
func apply(p: Player, turn: Vector2, sticks_pushed: bool) -> Vector2:
	last = {}
	if not active() or p.camera == null:
		target_id = 0
		return turn
	var pick := _pick_target(p)
	if pick.is_empty():
		target_id = 0
		return turn
	var lvl := level()
	var strength: float = pick.strength
	var out := turn * (1.0 - SLOWDOWN[lvl] * strength)
	var track := Vector2.ZERO
	if int(pick.id) == target_id and sticks_pushed:
		# Follow part of how far the target moved across the view since the last frame (its own
		# movement and the player's), never more than a small step.
		track = Vector2(-angle_difference(_last_yaw, float(pick.yaw)), -(float(pick.pitch) - _last_pitch)) * TRACKING[lvl] * strength
		track = track.limit_length(deg_to_rad(2.0))
		out += track
	target_id = int(pick.id)
	_last_yaw = pick.yaw
	_last_pitch = pick.pitch
	last = {"target": target_id, "strength": strength, "slowdown": SLOWDOWN[lvl] * strength,
		"track_yaw": track.x, "track_pitch": track.y}
	return out


## The living enemy closest to the crosshair inside its assist area, in sight (no wall or smoke
## between): {id, strength (1 at the centre .. 0 at the edge), yaw, pitch (the direction to it)}.
func _pick_target(p: Player) -> Dictionary:
	var cam := p.camera.global_transform
	var forward := -cam.basis.z
	var space := p.get_world_3d().direct_space_state
	var best := {}
	for eid: int in p.world.entities:
		var e: Player = p.world.entities[eid]
		if not e.alive or not p.world.is_enemy(p, e):
			continue
		var aim := e.global_position + Vector3.UP * (0.45 if e.prone else (1.0 if e.crouching else 1.35))
		var to := aim - cam.origin
		var dist := to.length()
		if dist < 0.5 or dist > RANGE:
			continue
		var limit := clampf(rad_to_deg(atan(RADIUS / dist)), MIN_ANGLE, MAX_ANGLE)
		var off := rad_to_deg(forward.angle_to(to))
		if off > limit:
			continue
		# Full strength over the middle of the area, fading out toward its edge.
		var strength := 1.0 - pow(off / limit, 2.0)
		if not best.is_empty() and strength <= float(best.strength):
			continue
		var ray := PhysicsRayQueryParameters3D.create(cam.origin, aim, Player.MASK_WORLD)
		if not space.intersect_ray(ray).is_empty() or p.world.smoke_blocks(cam.origin, aim):
			continue
		var dir := to / dist
		best = {"id": eid, "strength": strength, "yaw": atan2(-dir.x, -dir.z), "pitch": asin(clampf(dir.y, -1.0, 1.0))}
	return best
