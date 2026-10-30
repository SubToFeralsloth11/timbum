class_name FreeCam
extends Camera3D
## Free-fly camera shared by spectating (Spectator, free view) and photo mode (PhotoMode). It
## flies through walls, stays inside the map's bounds (grown by MARGIN) and reads the player's
## own bindings: the move actions fly along the view, `jump` rises, `crouch` / `prone` sink,
## `sprint` flies FAST_MULT faster; the mouse (while captured) and the right stick (`look_*`,
## Profile.pad_stick with the pad sensitivity and invert settings) turn it. Photo mode also rolls
## it (`roll_input`) and scales the speed (`speed_scale`). The owner turns it on with `active`
## and feeds extra input through `up_input` / `roll_input` (pad triggers and bumpers in photo
## mode). Runs while the tree is paused, so a frozen offline match can still be flown through.

const BASE_SPEED := 9.0
const FAST_MULT := 3.0
const ROLL_SPEED := 1.2
const MAX_ROLL := deg_to_rad(60.0)
const MARGIN := 30.0

## Reads input and moves while true (and current).
var active := false
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
## Photo mode's speed slider (0.25-4).
var speed_scale := 1.0
## Whether roll_input turns the camera (photo mode).
var allow_roll := false
## Extra input the owner sets each frame: -1..1 rise / sink, -1..1 roll (left negative).
var up_input := 0.0
var roll_input := 0.0
## Where the camera may fly (the map's bounds grown by MARGIN); empty AABB: anywhere.
var bounds := AABB()
## Keeps flying while the tree is paused (photo mode in a frozen match); otherwise a paused
## match (the offline pause menu) holds it still.
var fly_when_paused := false


func _init() -> void:
	name = "FreeCam"
	near = 0.05
	far = 400.0
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS


## Starts from `from` (another camera's view): position, look and field of view.
func place(from: Transform3D, p_fov: float) -> void:
	var e := from.basis.get_euler()
	pitch = clampf(e.x, -Player.MAX_PITCH, Player.MAX_PITCH)
	yaw = e.y
	roll = e.z if allow_roll else 0.0
	fov = p_fov
	global_position = _clamped(from.origin)
	_apply_rotation()


func set_bounds(map_bounds: AABB) -> void:
	bounds = map_bounds.grow(MARGIN)


## Mouse motion while the mouse is captured turns the view (the owner forwards it).
func look_mouse(rel: Vector2) -> void:
	var sens := Player.MOUSE_SCALE * float(Profile.get_setting("mouse_sens")) * (fov / float(Profile.get_setting("fov")))
	var invert := -1.0 if Profile.get_setting("invert_y") else 1.0
	yaw = wrapf(yaw - rel.x * sens, -PI, PI)
	pitch = clampf(pitch - rel.y * sens * invert, -Player.MAX_PITCH, Player.MAX_PITCH)
	_apply_rotation()


func _process(delta: float) -> void:
	if not active or not current or (get_tree().paused and not fly_when_paused):
		return
	# Real time, so a frozen (paused) match still flies at the normal speed.
	delta = minf(delta, 0.1)
	var stick := Profile.pad_stick(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick != Vector2.ZERO:
		var rate := Player.PAD_LOOK_SPEED * float(Profile.get_setting("pad_sens")) * delta * (fov / float(Profile.get_setting("fov")))
		var invert := -1.0 if Profile.get_setting("pad_invert_y") else 1.0
		yaw = wrapf(yaw - stick.x * rate, -PI, PI)
		pitch = clampf(pitch - stick.y * rate * Player.PAD_PITCH_SCALE * invert, -Player.MAX_PITCH, Player.MAX_PITCH)
	if allow_roll:
		var r := Input.get_action_strength("lean_right") - Input.get_action_strength("lean_left") + roll_input
		roll = clampf(roll - clampf(r, -1.0, 1.0) * ROLL_SPEED * delta, -MAX_ROLL, MAX_ROLL)
	_apply_rotation()
	var move := Input.get_vector("move_left", "move_right", "move_back", "move_forward", float(Profile.get_setting("pad_deadzone")))
	var rise := Input.get_action_strength("jump") - maxf(Input.get_action_strength("crouch"), Input.get_action_strength("prone")) + up_input
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var dir := b * Vector3(move.x, 0.0, -move.y) + Vector3.UP * clampf(rise, -1.0, 1.0)
	if dir == Vector3.ZERO:
		return
	var speed := BASE_SPEED * speed_scale * (FAST_MULT if Input.is_action_pressed("sprint") else 1.0)
	global_position = _clamped(global_position + dir.limit_length(1.0) * speed * delta)


func _apply_rotation() -> void:
	global_basis = Basis.from_euler(Vector3(pitch, yaw, roll))


func _clamped(pos: Vector3) -> Vector3:
	if bounds.size == Vector3.ZERO:
		return pos
	var lo := bounds.position
	var hi := bounds.end
	return Vector3(clampf(pos.x, lo.x, hi.x), clampf(pos.y, lo.y, hi.y), clampf(pos.z, lo.z, hi.z))
