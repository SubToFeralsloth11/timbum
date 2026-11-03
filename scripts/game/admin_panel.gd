class_name AdminPanel
extends CanvasLayer
## Admin panel, World's child "AdminPanel" (`World.admin`), in every match, offline and online.
## Opened with `admin_panel` (F1) or the pause menu's ADMIN PANEL via `Hud.open_admin()`; an
## offline match freezes while it is open (online keeps running), and Esc / F1 / CLOSE shut it
## (back to the pause menu when it was opened from there: `closed(to_pause)`). Cheats stay on after
## the panel closes, for this match only: every World starts with a clean AdminPanel.
##
## Every cheat is a plain field. Player, World and BotBrain read them through the hook functions
## below, which return the neutral value for anyone but the local player. Client-side cheats
## (movement, aim, ESP, ammo, recoil, spread, wallbang, headshots, fake lag) work as a client;
## server-side ones (god mode, damage, one-shot, fire rate past the host's check, explosive
## bullets, bots, clock, kills, respawns) only on the machine running the match (offline or host).
## The ESP, radar, chams and the active-cheat line draw on this layer's overlay while the panel is
## closed; the panel itself is `_root`.

## Closed; `to_pause`: it was opened from the pause menu, which should come back.
signal closed(to_pause: bool)

const AIM_OFF := 0
const AIM_AIMING := 1
const AIM_FIRING := 2
const AIM_ALWAYS := 3
const AIM_MODES: Array[String] = ["Off", "While aiming", "While aiming or firing", "Always"]
const AIM_POINTS: Array[String] = ["Head", "Body"]
const RADAR_RANGE := 60.0
const RADAR_RADIUS := 90.0
## Explosive bullets: blasts per shot (shotgun pellets beyond this don't explode), radius, damage.
const BULLET_BLASTS := 3
const BULLET_BLAST_RADIUS := 3.5
const BULLET_BLAST_DAMAGE := 80.0
const CHAMS_REFRESH := 0.5
const INSTANT_RESPAWN_DELAY := 0.25

var world: World

# ---------------------------------------------------------------- cheats (see the hooks)
# Player
var god := false
var noclip := false
var fly := false
var air_jump := false
var speed := 1.0
var jump := 1.0
var gravity := 1.0
var no_grapple_cooldown := false
var invisible := false
var instant_respawn := false
var no_flash := false
## Field of view override in degrees; below 30 means the player's own setting.
var fov := 0.0
# Combat
var infinite_ammo := false
var instant_reload := false
var infinite_grenades := false
var full_auto := false
var fire_rate := 1.0
var no_recoil := false
var no_spread := false
var damage := 1.0
var one_shot := false
var always_head := false
var wallbang := false
var explosive := false
# Aim
var aimbot := AIM_OFF
var aim_head := 0
## Full cone of the aimbot / silent aim in degrees (360: anywhere).
var aim_fov := 40.0
var aim_smooth := 0.0
var silent_aim := false
var triggerbot := false
# ESP and visuals
var esp_boxes := false
var esp_names := false
var esp_health := false
var esp_distance := false
var esp_lines := false
var esp_team := false
var radar := false
var chams := false
var fullbright := false
var no_fog := false
# World
var freeze_bots := false
var passive_bots := false
var freeze_clock := false
var time_scale := 1.0
# Network-style cheats
## Fake lag in milliseconds: the local player's hitboxes (what bots' bullets hit) stay where they
## were and jump to the body only once per interval, like a choked connection.
var fake_lag := 0.0
## Freeze yourself in place (airstuck): no movement or gravity; you can still look and shoot.
var airstuck := false

const CHEATS: Array[StringName] = [
	&"god", &"noclip", &"fly", &"air_jump", &"speed", &"jump", &"gravity", &"no_grapple_cooldown",
	&"invisible", &"instant_respawn", &"no_flash", &"fov", &"infinite_ammo", &"instant_reload",
	&"infinite_grenades", &"full_auto", &"fire_rate", &"no_recoil", &"no_spread", &"damage", &"one_shot",
	&"always_head", &"wallbang", &"explosive", &"aimbot", &"aim_head", &"aim_fov", &"aim_smooth",
	&"silent_aim", &"triggerbot", &"esp_boxes", &"esp_names", &"esp_health", &"esp_distance",
	&"esp_lines", &"esp_team", &"radar", &"chams", &"fullbright", &"no_fog", &"freeze_bots",
	&"passive_bots", &"freeze_clock", &"time_scale", &"fake_lag", &"airstuck",
]
## Short names for the active-cheat line.
const TAGS := {
	&"god": "GOD", &"noclip": "NOCLIP", &"fly": "FLY", &"air_jump": "AIR JUMP", &"speed": "SPEED",
	&"jump": "JUMP", &"gravity": "GRAVITY", &"no_grapple_cooldown": "HOOK", &"invisible": "INVISIBLE",
	&"instant_respawn": "RESPAWN", &"no_flash": "NO FLASH", &"fov": "FOV", &"infinite_ammo": "AMMO",
	&"instant_reload": "RELOAD", &"infinite_grenades": "NADES", &"full_auto": "AUTO",
	&"fire_rate": "RATE", &"no_recoil": "NO RECOIL", &"no_spread": "NO SPREAD", &"damage": "DMG",
	&"one_shot": "1-SHOT", &"always_head": "HEADS", &"wallbang": "WALLBANG", &"explosive": "BOOM",
	&"aimbot": "AIMBOT", &"silent_aim": "SILENT", &"triggerbot": "TRIGGER", &"esp_boxes": "ESP",
	&"radar": "RADAR", &"chams": "CHAMS", &"fullbright": "BRIGHT", &"no_fog": "NO FOG",
	&"freeze_bots": "BOTS FROZEN", &"passive_bots": "BOTS PASSIVE", &"freeze_clock": "CLOCK",
	&"time_scale": "TIME", &"fake_lag": "FAKE LAG", &"airstuck": "FROZEN",
}

var _defaults := {}
var _open := false
var _from_pause := false
var _held_clock := 0.0
var _dead_since := -1.0
var _chams_timer := 0.0
var _chams_mat: StandardMaterial3D
## Player -> the tint their avatar had before chams.
var _chams_saved := {}
var _env: Environment
var _env_saved := {}
## Panic key (`admin_panic`, H): the cheats it switched off, to put back on the next press.
var _stash := {}
var _note := ""
var _note_until := -100.0
## Fake lag: where the hitboxes are held and when they next catch up.
var _lag_hold := Transform3D()
var _lag_next := 0.0
var _lagged: Player
var _send_next := 0.0

var _root: Control
var _overlay: Overlay
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _refreshers: Array[Callable] = []
var _status: Label
var _coins_label: Label
var _primary: OptionButton
var _secondary: OptionButton
var _melee: OptionButton


## Draws the ESP, radar and active-cheat line (AdminPanel._draw_overlay).
class Overlay extends Control:
	var admin: AdminPanel

	func _draw() -> void:
		admin._draw_overlay(self)


func _init() -> void:
	name = "AdminPanel"


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -1
	for prop in CHEATS:
		_defaults[prop] = get(prop)
	_overlay = Overlay.new()
	_overlay.admin = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	var envs := world.find_children("*", "WorldEnvironment", true, false)
	if not envs.is_empty():
		_env = (envs[0] as WorldEnvironment).environment
	_build_ui()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## Whether the panel may open now: in a running match, no photo mode or kill cam replay.
func can_open() -> bool:
	return not _open and not world.match_over and not world.photo.is_open() \
		and not world.killcam.is_playing()


func is_open() -> bool:
	return _open


## Opens the panel and freezes the match; `from_pause`: closing goes back to the pause menu.
func open(from_pause := false) -> void:
	if not can_open():
		return
	_open = true
	_from_pause = from_pause
	world.set_frozen(true)
	_refresh_all()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play(&"ui_click")


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	closed.emit(_from_pause)


## Every cheat back to off / 1x.
func reset_all() -> void:
	_set_cheats(_defaults)
	_stash.clear()
	_say("Every cheat is off.")


## Sets every cheat in `values` (others to their defaults) with its side effects.
func _set_cheats(values: Dictionary) -> void:
	for prop in CHEATS:
		set(prop, values.get(prop, _defaults[prop]))
	for prop in [&"chams", &"fullbright", &"no_fog", &"time_scale", &"freeze_clock"]:
		_apply(prop)
	_refresh_all()


## Cheats that differ from their defaults: prop -> value.
func _active() -> Dictionary:
	var out := {}
	for prop in CHEATS:
		if get(prop) != _defaults[prop]:
			out[prop] = get(prop)
	return out


## Panic key: with cheats on, switches them all off and remembers them; pressed again with none
## on, puts the remembered ones back. Returns false when there is nothing to switch either way
## (the key then does its normal job: throwing the tactical grenade).
func panic_toggle() -> bool:
	var on := _active()
	if not on.is_empty():
		_stash = on
		_set_cheats({})
		_flash_note("CHEATS OFF")
		return true
	if not _stash.is_empty():
		_set_cheats(_stash)
		_stash.clear()
		_flash_note("CHEATS ON")
		return true
	return false


func _flash_note(text: String) -> void:
	_note = "%s  [%s]" % [text, Profile.key_text("admin_panic")]
	_note_until = Time.get_ticks_msec() * 0.001 + 1.2


# ================================================================ hooks (Player, World, BotBrain)

func _mine(p: Player) -> bool:
	return p != null and p == world.local_player


## 0 walks, 1 flies (collides, no gravity), 2 noclips (through walls along the view), 3 is frozen
## in place (airstuck).
func flight(p: Player) -> int:
	if not _mine(p):
		return 0
	if airstuck:
		return 3
	return 2 if noclip else (1 if fly else 0)


func move_mult(p: Player) -> float:
	return speed if _mine(p) else 1.0


func jump_mult(p: Player) -> float:
	return jump if _mine(p) else 1.0


func gravity_mult(p: Player) -> float:
	return gravity if _mine(p) else 1.0


func air_jump_for(p: Player) -> bool:
	return air_jump and _mine(p)


func grapple_cooldown_mult(p: Player) -> float:
	return 0.0 if no_grapple_cooldown and _mine(p) else 1.0


func fov_for(p: Player, base: float) -> float:
	return fov if fov >= 30.0 and _mine(p) else base


func ammo_free(p: Player) -> bool:
	return infinite_ammo and _mine(p)


func reload_free(p: Player) -> bool:
	return instant_reload and _mine(p)


func fire_rate_for(p: Player) -> float:
	return fire_rate if _mine(p) else 1.0


func auto_for(p: Player) -> bool:
	return full_auto and _mine(p)


func recoil_mult(p: Player) -> float:
	return 0.0 if no_recoil and _mine(p) else 1.0


func spread_mult(p: Player) -> float:
	return 0.0 if no_spread and _mine(p) else 1.0


func pierce_for(p: Player) -> bool:
	return wallbang and _mine(p)


func head_for(p: Player) -> bool:
	return always_head and _mine(p)


func flash_proof(p: Player) -> bool:
	return no_flash and _mine(p)


## Bots skip this player when picking a target.
func hidden_from_bots(p: Player) -> bool:
	return invisible and _mine(p)


func bots_frozen() -> bool:
	return freeze_bots


func bots_passive() -> bool:
	return passive_bots


## Server: the local player's shots skip the fire-rate budget while they fire faster than a gun can.
func skip_rate_check(shooter: Player) -> bool:
	return (fire_rate > 1.0 or full_auto) and _mine(shooter)


## Server: what a hit of `amount` from `attacker_id` does to `target` (god mode, damage
## multiplier, one-shot kills).
func damage_for(target: Player, amount: float, attacker_id: int) -> float:
	if not multiplayer.is_server():
		return amount
	var me := world.local_player
	if me == null:
		return amount
	if target == me:
		return 0.0 if god else amount
	if attacker_id != me.id:
		return amount
	return 1e6 if one_shot else amount * damage


## Server: `p` fell below the map's kill height. True when a cheat saves them (noclip lets them fly
## anywhere; god mode puts them back on a spawn) instead of the fall killing them.
func saves_from_fall(p: Player) -> bool:
	if not _mine(p):
		return false
	if noclip:
		return true
	if not god:
		return false
	p.global_position = world.pick_spawn(p.id, Teams.of(p))[0]
	p.velocity = Vector3.ZERO
	return true


## The local player's shot direction: silent aim turns it at the aimbot's target.
func aim_for(p: Player, aim: Transform3D) -> Transform3D:
	if not silent_aim or not _mine(p):
		return aim
	var target: Variant = _aim_target(p, aim)
	if target == null:
		return aim
	return Transform3D(Basis.looking_at((target as Vector3) - aim.origin), aim.origin)


## Triggerbot: the local player's crosshair rests on a living enemy (through walls with wallbang).
func trigger_for(p: Player) -> bool:
	if not triggerbot or not _mine(p) or not p.alive or p.current_slot == 2:
		return false
	var aim := p.aim_transform()
	var mask := Player.MASK_HITBOX if wallbang else Player.MASK_WORLD | Player.MASK_HITBOX
	var q := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * Player.HITSCAN_RANGE, mask, p.exclude_rids())
	q.collide_with_areas = true
	var r := p.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty() or not (r.collider is Area3D) or not (r.collider as Area3D).has_meta("player"):
		return false
	var target: Player = (r.collider as Area3D).get_meta("player")
	return target.alive and world.is_enemy(p, target)


## Server, after a hitscan shot of the local player: explosive bullets blow up where it landed.
func after_shot(shooter: Player, wid: String, ends: PackedVector3Array) -> void:
	if not explosive or not _mine(shooter) or Data.is_melee(wid):
		return
	var eye := shooter.head.global_position
	for i in mini(ends.size(), BULLET_BLASTS):
		var pos := ends[i]
		# A miss into the sky ends at the hitscan reach; nothing to blow up there.
		if eye.distance_to(pos) >= Player.HITSCAN_RANGE - 1.0:
			continue
		world.fx.explosion(pos)
		Sfx.play(&"explosion", pos, -4.0)
		world.server_blast(pos, BULLET_BLAST_RADIUS, BULLET_BLAST_DAMAGE, shooter.id, wid, 0.0)


# ================================================================ per frame

func _physics_process(delta: float) -> void:
	if world.is_frozen() or world.match_over or not world.net_live():
		return
	if freeze_clock:
		world.time_left = _held_clock
	var me := world.local_player
	if me == null:
		return
	_tick_fake_lag(me)
	if not me.alive:
		if instant_respawn and multiplayer.is_server():
			if _dead_since < 0.0:
				_dead_since = World.now()
			elif World.now() - _dead_since >= INSTANT_RESPAWN_DELAY:
				_dead_since = -1.0
				world.server_respawn_now(me.id)
		return
	_dead_since = -1.0
	if infinite_grenades and multiplayer.is_server():
		world.server_admin_equipment(me.id)
	if aimbot != AIM_OFF and not world.input_blocked():
		_run_aimbot(me, delta)


## Fake lag: the hitboxes (top level while it runs) catch up with the body every `fake_lag` ms.
func _tick_fake_lag(me: Player) -> void:
	if fake_lag <= 0.0 or not me.alive:
		_release_hitboxes()
		return
	if _lagged != me:
		_release_hitboxes()
		_lagged = me
		for area: Area3D in [me._hit_head, me._hit_body]:
			area.top_level = true
		_lag_next = 0.0
	var t := World.now()
	if t >= _lag_next:
		_lag_next = t + fake_lag * 0.001
		_lag_hold = me.global_transform
	for area: Area3D in [me._hit_head, me._hit_body]:
		area.global_transform = _lag_hold


func _release_hitboxes() -> void:
	if _lagged == null:
		return
	if is_instance_valid(_lagged):
		for area: Area3D in [_lagged._hit_head, _lagged._hit_body]:
			area.top_level = false
			area.transform = Transform3D()
	_lagged = null


func _run_aimbot(me: Player, delta: float) -> void:
	var wanted := aimbot == AIM_ALWAYS or Input.is_action_pressed(&"aim") \
		or (aimbot == AIM_FIRING and Input.is_action_pressed(&"fire"))
	if not wanted:
		return
	var aim := me.aim_transform()
	var target: Variant = _aim_target(me, aim)
	if target == null:
		return
	var dir := ((target as Vector3) - aim.origin).normalized()
	var want_yaw := atan2(-dir.x, -dir.z)
	var want_pitch := clampf(asin(dir.y) - deg_to_rad(me.recoil), -Player.MAX_PITCH, Player.MAX_PITCH)
	# Smoothing 0 snaps; higher values ease in (frame-rate independent).
	var t := 1.0 if aim_smooth <= 0.0 else 1.0 - pow(aim_smooth, delta * 60.0)
	me.yaw = wrapf(lerp_angle(me.yaw, want_yaw, t), -PI, PI)
	me.pitch = lerpf(me.pitch, want_pitch, t)


## The point the aimbot locks onto: the living enemy nearest the middle of `aim`'s view within
## `aim_fov`, in sight unless wallbang is on.
func _aim_target(p: Player, aim: Transform3D) -> Variant:
	var fwd := -aim.basis.z
	var best: Variant = null
	var best_angle := deg_to_rad(aim_fov) * 0.5
	var space := p.get_world_3d().direct_space_state
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if not o.alive or not world.is_enemy(p, o):
			continue
		var point := o.head.global_position if aim_head == 0 else o.global_position + Vector3.UP * o.body_center_height()
		var angle := fwd.angle_to(point - aim.origin)
		if angle > best_angle:
			continue
		if not wallbang:
			var q := PhysicsRayQueryParameters3D.create(aim.origin, point, Player.MASK_WORLD)
			if not space.intersect_ray(q).is_empty():
				continue
		best_angle = angle
		best = point
	return best


func _process(delta: float) -> void:
	if chams:
		_chams_timer -= delta
		if _chams_timer <= 0.0:
			_chams_timer = CHAMS_REFRESH
			_refresh_chams()
	if _open and _coins_label != null:
		_coins_label.text = "Coins %s  ·  Level %d  ·  Prestige %d" % [UIKit.format_int(Profile.coins), Profile.level, Profile.prestige]
	_overlay.visible = not _open
	if _overlay.visible:
		_overlay.queue_redraw()


# ================================================================ overlay

func _esp_on() -> bool:
	return esp_boxes or esp_names or esp_health or esp_distance or esp_lines


func _active_tags() -> PackedStringArray:
	var out := PackedStringArray()
	for prop: StringName in TAGS:
		if get(prop) != _defaults[prop]:
			out.append(TAGS[prop])
	return out


func _draw_overlay(c: Control) -> void:
	if world.photo.is_open():
		return
	var font := UITheme.heavy_font()
	var me := world.local_player
	var cam := c.get_viewport().get_camera_3d()
	if cam != null and _esp_on():
		for eid: int in world.entities:
			var o: Player = world.entities[eid]
			if o == me or not o.alive:
				continue
			var enemy := me == null or world.is_enemy(me, o)
			if enemy or esp_team:
				_draw_esp(c, cam, font, me, o, enemy)
	if radar and me != null:
		_draw_radar(c, me)
	if fake_lag > 0.0 and cam != null and _lagged != null and is_instance_valid(_lagged):
		_draw_lag_ghost(c, cam, font)
	var tags := _active_tags()
	if not tags.is_empty():
		var text := "ADMIN  ·  " + "  ·  ".join(tags)
		c.draw_string_outline(font, Vector2(16, 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8))
		c.draw_string(font, Vector2(16, 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.ACCENT)
	if Time.get_ticks_msec() * 0.001 < _note_until:
		var pos := Vector2(0, c.size.y * 0.3)
		c.draw_string_outline(font, pos, _note, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22, 6, Color(0, 0, 0, 0.8))
		c.draw_string(font, pos, _note, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22, UITheme.ACCENT)


## Fake lag: an outline where the held hitboxes stand (where bots' bullets land).
func _draw_lag_ghost(c: Control, cam: Camera3D, font: Font) -> void:
	var feet := _lag_hold.origin
	var top := feet + Vector3.UP * Player.STAND_HEIGHT
	if cam.is_position_behind(feet) or cam.is_position_behind(top):
		return
	var a := cam.unproject_position(top)
	var b := cam.unproject_position(feet)
	var h := maxf(absf(b.y - a.y), 6.0)
	var rect := Rect2(Vector2(b.x - h * 0.25, b.y - h), Vector2(h * 0.5, h))
	var col := Color(0.6, 0.9, 1.0, 0.8)
	c.draw_rect(rect, col, false, 1.5)
	c.draw_string(font, Vector2(b.x - 60.0, rect.position.y - 4.0), "LAG HITBOX", HORIZONTAL_ALIGNMENT_CENTER, 120, 11, col)


func _draw_esp(c: Control, cam: Camera3D, font: Font, me: Player, o: Player, enemy: bool) -> void:
	var feet := o.global_position
	var height := lerpf(lerpf(Player.STAND_HEIGHT, Player.CROUCH_HEIGHT, o.crouch_blend), Player.PRONE_HEIGHT, o.prone_blend)
	var top := feet + Vector3.UP * (height + 0.15)
	if cam.is_position_behind(feet) or cam.is_position_behind(top):
		return
	var a := cam.unproject_position(top)
	var b := cam.unproject_position(feet)
	var h := maxf(absf(b.y - a.y), 6.0)
	var w := maxf(h * 0.5, 4.0)
	var rect := Rect2(Vector2(b.x - w * 0.5, b.y - h), Vector2(w, h))
	var col := Palette.color("ping_enemy") if enemy else Teams.color(Teams.of(o))
	var shadow := Color(0, 0, 0, 0.7)
	if esp_lines:
		c.draw_line(Vector2(c.size.x * 0.5, c.size.y), Vector2(b.x, b.y), Color(col, 0.6), 1.5)
	if esp_boxes:
		c.draw_rect(rect.grow(1.0), shadow, false, 3.0)
		c.draw_rect(rect, col, false, 1.5)
	if esp_health:
		var frac := clampf(o.health / maxf(o.max_health(), 1.0), 0.0, 1.0)
		var bar := Rect2(rect.position.x - 6.0, rect.position.y, 3.0, h)
		c.draw_rect(bar.grow(1.0), shadow)
		c.draw_rect(Rect2(bar.position.x, bar.end.y - h * frac, 3.0, h * frac), Palette.health(frac))
		if o.shield > 0.0:
			var sfrac := clampf(o.shield / Streaks.SHIELD, 0.0, 1.0)
			c.draw_rect(Rect2(bar.position.x - 5.0, bar.end.y - h * sfrac, 3.0, h * sfrac), Palette.color("shield"))
	var label_x := b.x - 120.0
	if esp_names:
		var text := "%s  %d" % [world.display_name(o.id), ceili(o.health)] if esp_health else world.display_name(o.id)
		c.draw_string_outline(font, Vector2(label_x, rect.position.y - 5.0), text, HORIZONTAL_ALIGNMENT_CENTER, 240, 13, 4, shadow)
		c.draw_string(font, Vector2(label_x, rect.position.y - 5.0), text, HORIZONTAL_ALIGNMENT_CENTER, 240, 13, col)
	if esp_distance:
		var from := me.global_position if me != null else cam.global_position
		var dist := "%d m" % roundi(from.distance_to(feet))
		var wid := o.weapon_id() if not o.slots.is_empty() else ""
		if Data.WEAPONS.has(wid):
			dist += "  ·  " + str(Data.WEAPONS[wid].name)
		c.draw_string_outline(font, Vector2(label_x, rect.end.y + 14.0), dist, HORIZONTAL_ALIGNMENT_CENTER, 240, 12, 4, shadow)
		c.draw_string(font, Vector2(label_x, rect.end.y + 14.0), dist, HORIZONTAL_ALIGNMENT_CENTER, 240, 12, Color.WHITE)


## A top-down radar on the left edge: up is where the local player looks.
func _draw_radar(c: Control, me: Player) -> void:
	var center := Vector2(RADAR_RADIUS + 16.0, c.size.y * 0.5)
	c.draw_circle(center, RADAR_RADIUS, Color(0.02, 0.03, 0.06, 0.55))
	c.draw_arc(center, RADAR_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 1.5)
	c.draw_arc(center, RADAR_RADIUS * 0.5, 0.0, TAU, 32, Color(1, 1, 1, 0.15), 1.0)
	c.draw_line(center - Vector2(RADAR_RADIUS, 0), center + Vector2(RADAR_RADIUS, 0), Color(1, 1, 1, 0.12))
	c.draw_line(center - Vector2(0, RADAR_RADIUS), center + Vector2(0, RADAR_RADIUS), Color(1, 1, 1, 0.12))
	var to_local := Basis(Vector3.UP, me.yaw).inverse()
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if o == me or not o.alive:
			continue
		var rel := to_local * (o.global_position - me.global_position)
		var pos := Vector2(rel.x, rel.z) * (RADAR_RADIUS / RADAR_RANGE)
		if pos.length() > RADAR_RADIUS - 4.0:
			pos = pos.normalized() * (RADAR_RADIUS - 4.0)
		var col := Palette.color("ping_enemy") if world.is_enemy(me, o) else Teams.color(Teams.of(o))
		c.draw_circle(center + pos, 4.0, Color(0, 0, 0, 0.7))
		c.draw_circle(center + pos, 3.0, col)
	c.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -7), center + Vector2(5, 5), center + Vector2(-5, 5)]), Color.WHITE)


# ================================================================ visuals

func _refresh_chams() -> void:
	if _chams_mat == null:
		_chams_mat = StandardMaterial3D.new()
		_chams_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_chams_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_chams_mat.no_depth_test = true
		_chams_mat.render_priority = 10
	var c := Palette.color("ping_enemy")
	_chams_mat.albedo_color = Color(c, 0.45)
	var me := world.local_player
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if o == me or o.avatar == null:
			continue
		var want := me == null or world.is_enemy(me, o) or esp_team
		var tint := o.avatar.get_tint()
		if want and tint != _chams_mat:
			_chams_saved[o] = tint
			o.avatar.set_tint(_chams_mat)
		elif not want and tint == _chams_mat:
			o.avatar.set_tint(_chams_saved.get(o))
			_chams_saved.erase(o)


func _clear_chams() -> void:
	for o: Variant in _chams_saved:
		if is_instance_valid(o) and (o as Player).avatar.get_tint() == _chams_mat:
			(o as Player).avatar.set_tint(_chams_saved[o])
	_chams_saved.clear()


## Side effects of a cheat that changed.
func _apply(prop: StringName) -> void:
	match prop:
		&"chams":
			if chams:
				_chams_timer = 0.0
			else:
				_clear_chams()
		&"fullbright":
			if _env == null:
				return
			if fullbright and not _env_saved.has("ambient_light_source"):
				for key in ["ambient_light_source", "ambient_light_color", "ambient_light_energy", "ambient_light_sky_contribution"]:
					_env_saved[key] = _env.get(key)
				_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				_env.ambient_light_color = Color.WHITE
				_env.ambient_light_energy = 1.1
				_env.ambient_light_sky_contribution = 0.0
			elif not fullbright and _env_saved.has("ambient_light_source"):
				for key in ["ambient_light_source", "ambient_light_color", "ambient_light_energy", "ambient_light_sky_contribution"]:
					_env.set(key, _env_saved[key])
					_env_saved.erase(key)
		&"no_fog":
			if _env == null:
				return
			if no_fog and not _env_saved.has("fog_enabled"):
				_env_saved["fog_enabled"] = _env.fog_enabled
				_env_saved["volumetric_fog_enabled"] = _env.volumetric_fog_enabled
				_env.fog_enabled = false
				_env.volumetric_fog_enabled = false
			elif not no_fog and _env_saved.has("fog_enabled"):
				_env.fog_enabled = _env_saved["fog_enabled"]
				_env.volumetric_fog_enabled = _env_saved["volumetric_fog_enabled"]
				_env_saved.erase("fog_enabled")
				_env_saved.erase("volumetric_fog_enabled")
		&"time_scale":
			Engine.time_scale = time_scale
		&"freeze_clock":
			_held_clock = world.time_left


# ================================================================ actions

func _say(text: String) -> void:
	if _status != null:
		_status.text = text


func _me_alive() -> Player:
	var me := world.local_player
	if me == null:
		_say("You are spectating: nobody to apply that to.")
		return null
	if not me.alive:
		_say("You are dead: respawn first.")
		return null
	return me


func _enemies() -> Array[Player]:
	var me := world.local_player
	var out: Array[Player] = []
	for eid: int in world.entities:
		var o: Player = world.entities[eid]
		if o.alive and o != me and (me == null or world.is_enemy(me, o)):
			out.append(o)
	return out


func _kill_weapon() -> String:
	var me := world.local_player
	if me != null and not me.slots.is_empty() and not me.weapon_id().is_empty():
		return me.weapon_id()
	return "fall"


## Server-side cheats (kills, health, bots, clock, respawns) need this machine to run the match:
## offline or hosting. A client gets told so.
func _host() -> bool:
	if multiplayer.is_server():
		return true
	_say("Host only: that one runs on the host's machine.")
	return false


## Fake lag online, client side: the local player's position goes out only once per interval.
func lag_send(p: Player) -> bool:
	if fake_lag <= 0.0 or not _mine(p):
		return true
	var t := World.now()
	if t < _send_next:
		return false
	_send_next = t + fake_lag * 0.001
	return true


## Fake lag online, host side: the host's own position in snapshots is the held hitbox spot.
func net_position(p: Player) -> Vector3:
	if fake_lag > 0.0 and _lagged == p and is_instance_valid(p):
		return _lag_hold.origin
	return p.global_position


func _kill_all() -> void:
	if not _host():
		return
	var list := _enemies()
	var me := world.local_player
	for o in list:
		world.server_admin_kill(o, me.id if me != null else o.id, _kill_weapon())
	_say("Killed %d enem%s." % [list.size(), "y" if list.size() == 1 else "ies"])


func _kill_nearest() -> void:
	if not _host():
		return
	var me := _me_alive()
	if me == null:
		return
	var best: Player = null
	for o in _enemies():
		if best == null or me.global_position.distance_squared_to(o.global_position) < me.global_position.distance_squared_to(best.global_position):
			best = o
	if best == null:
		_say("No enemy left alive.")
		return
	world.server_admin_kill(best, me.id, _kill_weapon())
	_say("Killed %s." % world.display_name(best.id))


func _heal() -> void:
	if not _host():
		return
	var me := _me_alive()
	if me != null:
		world.server_set_health(me.id, me.max_health())
		_say("Health full.")


func _reward(kind: String) -> void:
	if not _host():
		return
	var me := _me_alive()
	if me == null:
		return
	if kind == "bomber" and not Streaks.enabled():
		_say("Killstreaks are off in this match: no Block Bomber to call.")
		return
	world.streaks.server_admin_reward(me.id, kind)
	_say({"shield": "Overshield on.", "radar": "Radar Sweep running.", "bomber": "Block Bomber ready: press %s." % Profile.key_text("streak_reward")}[kind])


func _respawn_me() -> void:
	if not _host():
		return
	var me := world.local_player
	if me == null:
		_say("You are spectating: press PLAY in the pause menu.")
		return
	if me.alive:
		_say("You are alive already.")
		return
	world.server_respawn_now(me.id)
	_say("Respawned.")


func _suicide() -> void:
	if not _host():
		return
	var me := _me_alive()
	if me != null:
		world.server_admin_kill(me, me.id, "fall")
		_say("You died.")


func _teleport(pos: Vector3, what: String) -> void:
	var me := _me_alive()
	if me == null:
		return
	me.release_grapple()
	me.global_position = pos
	me.velocity = Vector3.ZERO
	me.pad_flight = false
	_say("Teleported %s." % what)


func _teleport_crosshair() -> void:
	var me := _me_alive()
	if me == null:
		return
	var aim := me.aim_transform()
	var q := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * 1000.0, Player.MASK_WORLD, me.exclude_rids())
	var r := me.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		_say("Nothing under the crosshair to stand on.")
		return
	var n: Vector3 = r.normal
	# Onto a floor; off a wall or ceiling by a body's width (and below a ceiling by a body's height).
	var pos: Vector3 = r.position + (Vector3.UP * 0.05 if n.y > 0.5 else n * (Player.RADIUS + 0.1) - Vector3.UP * (Player.STAND_HEIGHT if n.y < -0.5 else 0.0))
	_teleport(pos, "to the crosshair")


func _teleport_spawn() -> void:
	var me := _me_alive()
	if me != null:
		_teleport(world.pick_spawn(me.id, Teams.of(me))[0], "to a spawn")


func _teleport_enemy() -> void:
	var me := _me_alive()
	if me == null:
		return
	var list := _enemies()
	if list.is_empty():
		_say("No enemy left alive.")
		return
	var o: Player = list.pick_random()
	var back := Basis(Vector3.UP, o.yaw) * Vector3(0.0, 0.0, 2.2)
	_teleport(o.global_position + back, "behind %s" % world.display_name(o.id))
	me.yaw = o.yaw


func _bring_bots() -> void:
	if not _host():
		return
	var me := _me_alive()
	if me == null:
		return
	var n := 0
	for o in _enemies():
		if not o.is_bot:
			continue
		var ring := Basis(Vector3.UP, TAU * n / 8.0) * Vector3(0.0, 0.0, -4.0 - 1.5 * floorf(n / 8.0))
		o.global_position = me.global_position + Basis(Vector3.UP, me.yaw) * ring + Vector3.UP * 0.2
		o.velocity = Vector3.ZERO
		n += 1
	_say("Brought %d bot%s in front of you." % [n, "" if n == 1 else "s"])


func _add_bot() -> void:
	if not _host():
		return
	world.server_add_bot(world.rules.server_team_for(true))
	_say("A bot joined.")


func _remove_bot() -> void:
	if not _host():
		return
	for eid: int in world.entities:
		if (world.entities[eid] as Player).is_bot:
			var who := world.display_name(eid)
			world.server_remove_bot(eid)
			_say("%s left." % who)
			return
	_say("No bots left.")


func _clock(seconds: float) -> void:
	if not _host():
		return
	world.time_left = maxf(5.0, world.time_left + seconds)
	_held_clock = world.time_left
	_say("Clock: %d:%02d left." % [int(world.time_left) / 60, int(world.time_left) % 60])


func _add_kills(n: int) -> void:
	if not _host():
		return
	var me := world.local_player
	if me == null:
		_say("You are spectating.")
		return
	world.server_admin_add_kills(me.id, n)
	_say("+%d kills on the scoreboard." % n)


func _end_match() -> void:
	if not _host():
		return
	close()
	world.server_end_match()


func _give(slot: int, o: OptionButton) -> void:
	var me := _me_alive()
	if me == null:
		return
	var wid := str(o.get_item_metadata(o.selected))
	me.give_weapon(slot, wid)
	_say("Gave you the %s." % str(Data.WEAPONS[wid].name))


func _coins(n: int) -> void:
	Profile.coins += n
	Profile.save()
	Profile.changed.emit()
	_say("+%s coins." % UIKit.format_int(n))


func _level_up() -> void:
	if Profile.level >= Data.LEVEL_CAP:
		_say("Level %d is the cap: prestige to go on." % Data.LEVEL_CAP)
		return
	var levels := Profile._grant(0, Profile.xp_for_level(Profile.level) - Profile.xp)
	Profile.save()
	Profile.changed.emit()
	_say("Level %d (+%d)." % [Profile.level, levels])


func _max_level() -> void:
	Profile.level = Data.LEVEL_CAP
	Profile.xp = 0
	Profile.save()
	Profile.changed.emit()
	_say("Level %d." % Data.LEVEL_CAP)


func _prestige_up() -> void:
	if Profile.prestige >= Data.PRESTIGE_MAX:
		_say("Prestige %d is the top rank." % Data.PRESTIGE_MAX)
		return
	Profile.prestige += 1
	Profile.save()
	Profile.changed.emit()
	_say("Prestige %d." % Profile.prestige)


func _unlock_everything() -> void:
	var added := 0
	for cat: String in ["weapons", "skins", "hats", "outfits", "tacticals", "charms", "emotes", "draws", "sprays"]:
		var list: Array = Profile.owned.get(cat, [])
		for id: String in Data.catalog(cat):
			if not Profile.is_owned(cat, id):
				list.append(id)
				added += 1
		Profile.owned[cat] = list
	Profile.save()
	Profile.changed.emit()
	_say("Unlocked %d items (every gun, skin, hat, outfit, charm, emote, draw and spray)." % added)


func _max_attachments() -> void:
	for id: String in Data.ATTACHMENTS:
		Profile.upgrades[id] = int(Data.ATTACHMENTS[id].max)
	Profile.save()
	Profile.changed.emit()
	_say("Every attachment at its top level (from your next spawn).")


func _gold_mastery() -> void:
	for wid: String in Data.WEAPONS:
		var s: Dictionary = Profile.weapon_stats.get(wid, {})
		for key in Profile.WEAPON_STAT_KEYS:
			if not s.has(key):
				s[key] = 0
		s.kills = maxi(int(s.kills), 150)
		Profile.weapon_stats[wid] = s
		# Paid already: the next match must not pay 1750 coins per gun for it.
		Profile.mastery_paid[wid] = 3
	Profile.save()
	Profile.changed.emit()
	_say("Gold mastery on every weapon: switch camos on in the locker.")


# ================================================================ input

func _input(event: InputEvent) -> void:
	if not _open:
		# H (admin_panic) with cheats on or remembered: switch them off / on, and don't throw the
		# tactical grenade that shares the key.
		if event.is_action_pressed(&"admin_panic") and not event.is_echo() \
				and not world.hud.is_chatting() and not world.hud.is_blocking() and panic_toggle():
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"admin_panel"):
		get_viewport().set_input_as_handled()
		close()


func _unhandled_input(event: InputEvent) -> void:
	if _open or not event.is_action_pressed(&"admin_panel"):
		return
	if can_open() and not world.hud.is_chatting():
		get_viewport().set_input_as_handled()
		world.hud.open_admin()


# ================================================================ panel

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := UIKit.panel()
	panel.custom_minimum_size = Vector2(1060, 620)
	center.add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)

	var head := UIKit.hbox(12)
	v.add_child(head)
	head.add_child(UIKit.label("ADMIN PANEL", &"HeaderLabel"))
	var sub := UIKit.label("Online too (god, damage, bots: host only) · %s or Esc closes · %s switches every cheat off / back on" \
		% [Profile.key_text("admin_panel"), Profile.key_text("admin_panic")], &"DimLabel")
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 320
	head.add_child(sub)
	var reset := UIKit.button("RESET ALL", &"DangerButton")
	reset.pressed.connect(reset_all)
	head.add_child(reset)
	var close_b := UIKit.button("CLOSE", &"PrimaryButton")
	close_b.pressed.connect(close)
	head.add_child(close_b)

	var tab_row := UIKit.hbox(8)
	v.add_child(tab_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UIKit.pad_friendly(scroll)
	v.add_child(scroll)
	var stack := UIKit.vbox(0)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Room on the right for the scroll bar.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 16)
	scroll.add_child(margin)
	margin.add_child(stack)
	_status = UIKit.label("", &"SmallLabel")
	_status.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(_status)

	var group := ButtonGroup.new()
	for title in ["PLAYER", "COMBAT", "AIM & ESP", "WORLD & BOTS", "PROFILE"]:
		var b := UIKit.button(title, &"TabButton")
		b.toggle_mode = true
		b.button_group = group
		var index := _tabs.size()
		b.pressed.connect(_show_page.bind(index))
		tab_row.add_child(b)
		_tabs.append(b)
		var page := GridContainer.new()
		page.columns = 2
		page.add_theme_constant_override("h_separation", 28)
		page.add_theme_constant_override("v_separation", 8)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(page)
		_pages.append(page)
	_build_player(_pages[0])
	_build_combat(_pages[1])
	_build_aim(_pages[2])
	_build_world(_pages[3])
	_build_profile(_pages[4])
	_show_page(0)


func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index
		_tabs[i].set_pressed_no_signal(i == index)


func _build_player(p: Control) -> void:
	_check(p, "God mode (no damage, saved from falls)", &"god")
	_check(p, "Noclip (fly through walls)", &"noclip")
	_check(p, "Fly (jump up, crouch down)", &"fly")
	_check(p, "Freeze myself (airstuck)", &"airstuck")
	_slider(p, "Fake lag (hitbox lags behind you)", &"fake_lag", 0.0, 1000.0, 25.0, "lag")
	_check(p, "Infinite jump (jump in mid-air)", &"air_jump")
	_slider(p, "Move speed", &"speed", 0.25, 6.0, 0.25, "%.2fx")
	_slider(p, "Jump height", &"jump", 0.5, 5.0, 0.25, "%.2fx")
	_slider(p, "Gravity", &"gravity", 0.0, 2.0, 0.05, "%.2fx")
	_check(p, "No grapple cooldown", &"no_grapple_cooldown")
	_check(p, "Invisible to bots", &"invisible")
	_check(p, "Instant respawn", &"instant_respawn")
	_check(p, "Flashbang immunity", &"no_flash")
	_slider(p, "Field of view (0: your setting)", &"fov", 0.0, 150.0, 1.0, "fov")
	_action(p, "FULL HEAL", _heal)
	_action(p, "OVERSHIELD", _reward.bind("shield"))
	_action(p, "RESPAWN NOW", _respawn_me)
	_action(p, "KILL MYSELF", _suicide, &"DangerButton")
	_action(p, "TELEPORT TO CROSSHAIR", _teleport_crosshair)
	_action(p, "TELEPORT TO A SPAWN", _teleport_spawn)
	_action(p, "TELEPORT BEHIND AN ENEMY", _teleport_enemy)


func _build_combat(p: Control) -> void:
	_check(p, "Infinite ammo (no reloads)", &"infinite_ammo")
	_check(p, "Instant reload", &"instant_reload")
	_check(p, "Infinite grenades and tacticals", &"infinite_grenades")
	_check(p, "Every gun full auto", &"full_auto")
	_slider(p, "Fire rate", &"fire_rate", 1.0, 10.0, 0.5, "%.1fx")
	_check(p, "No recoil", &"no_recoil")
	_check(p, "No spread (laser accurate)", &"no_spread")
	_slider(p, "Damage", &"damage", 0.25, 10.0, 0.25, "%.2fx")
	_check(p, "One-shot kills", &"one_shot")
	_check(p, "Every hit a headshot", &"always_head")
	_check(p, "Shoot through walls", &"wallbang")
	_check(p, "Explosive bullets", &"explosive")
	_primary = _weapon_pick(p, "Give primary", "primary", 0)
	_secondary = _weapon_pick(p, "Give secondary", "secondary", 1)
	_melee = _weapon_pick(p, "Give melee weapon", "melee", 2)
	_action(p, "RADAR SWEEP", _reward.bind("radar"))
	_action(p, "BLOCK BOMBER READY", _reward.bind("bomber"))


func _build_aim(p: Control) -> void:
	_option(p, "Aimbot", &"aimbot", AIM_MODES)
	_option(p, "Aim at", &"aim_head", AIM_POINTS)
	_slider(p, "Aimbot field of view", &"aim_fov", 5.0, 360.0, 5.0, "%d°")
	_slider(p, "Aimbot smoothing", &"aim_smooth", 0.0, 0.95, 0.05, "pct")
	_check(p, "Silent aim (shots bend to the target)", &"silent_aim")
	_check(p, "Triggerbot (fires on enemies)", &"triggerbot")
	_check(p, "ESP boxes", &"esp_boxes")
	_check(p, "ESP names", &"esp_names")
	_check(p, "ESP health and shield", &"esp_health")
	_check(p, "ESP distance and weapon", &"esp_distance")
	_check(p, "ESP snaplines", &"esp_lines")
	_check(p, "ESP and chams on teammates", &"esp_team")
	_check(p, "Radar", &"radar")
	_check(p, "Chams (bodies through walls)", &"chams")
	_check(p, "Fullbright", &"fullbright")
	_check(p, "No fog", &"no_fog")


func _build_world(p: Control) -> void:
	_check(p, "Freeze bots", &"freeze_bots")
	_check(p, "Passive bots (never attack)", &"passive_bots")
	_slider(p, "Game speed", &"time_scale", 0.1, 3.0, 0.05, "%.2fx")
	_check(p, "Freeze the match clock", &"freeze_clock")
	_action(p, "KILL ALL ENEMIES", _kill_all, &"DangerButton")
	_action(p, "KILL NEAREST ENEMY", _kill_nearest)
	_action(p, "BRING BOTS TO ME", _bring_bots)
	_action(p, "RESPAWN EVERY PICKUP", func() -> void:
		if not _host():
			return
		world.server_reset_pickups()
		_say("Every pickup is back."))
	_action(p, "ADD A BOT", _add_bot)
	_action(p, "REMOVE A BOT", _remove_bot)
	_action(p, "+1 MINUTE", _clock.bind(60.0))
	_action(p, "-1 MINUTE", _clock.bind(-60.0))
	_action(p, "+5 KILLS", _add_kills.bind(5))
	_action(p, "END MATCH NOW", _end_match, &"DangerButton")


func _build_profile(p: Control) -> void:
	_coins_label = UIKit.label("", &"ValueLabel")
	p.add_child(_coins_label)
	var note := UIKit.label("Saved to your profile at once.", &"DimLabel")
	p.add_child(note)
	_action(p, "+1,000 COINS", _coins.bind(1000))
	_action(p, "+100,000 COINS", _coins.bind(100000), &"GoldButton")
	_action(p, "+1 LEVEL", _level_up)
	_action(p, "MAX LEVEL", _max_level)
	_action(p, "PRESTIGE +1", _prestige_up)
	_action(p, "UNLOCK EVERYTHING", _unlock_everything, &"GoldButton")
	_action(p, "MAX EVERY ATTACHMENT", _max_attachments)
	_action(p, "GOLD MASTERY ON EVERY GUN", _gold_mastery)


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := UIKit.hbox(10)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.custom_minimum_size.x = 490
	var l := UIKit.label(text)
	l.add_theme_font_override("font", UITheme.heavy_font())
	l.add_theme_font_size_override("font_size", 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	parent.add_child(h)
	return h


func _check(parent: Control, text: String, prop: StringName) -> void:
	var h := _row(parent, text)
	var c := CheckBox.new()
	c.add_theme_font_override("font", UITheme.heavy_font())
	c.custom_minimum_size.x = 80
	UIKit.wire(c)
	var paint := func() -> void: c.text = "ON" if c.button_pressed else "OFF"
	c.toggled.connect(func(on: bool) -> void:
		set(prop, on)
		paint.call()
		_apply(prop)
		_say("%s %s." % [text.get_slice(" (", 0), "on" if on else "off"]))
	h.add_child(c)
	_refreshers.append(func() -> void:
		c.set_pressed_no_signal(bool(get(prop)))
		paint.call())


func _slider(parent: Control, text: String, prop: StringName, lo: float, hi: float, step: float, fmt: String) -> void:
	var h := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(180, 26)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var value := UIKit.label("", &"ValueLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	value.add_theme_font_size_override("font_size", 15)
	value.custom_minimum_size.x = 64
	h.add_child(value)
	var paint := func(x: float) -> void:
		match fmt:
			"pct": value.text = "%d%%" % roundi(x * 100.0)
			"fov": value.text = "OFF" if x < 30.0 else "%d°" % roundi(x)
			"lag": value.text = "OFF" if x <= 0.0 else "%d ms" % roundi(x)
			_: value.text = fmt % x
	s.value_changed.connect(func(x: float) -> void:
		set(prop, x)
		paint.call(x)
		_apply(prop))
	_refreshers.append(func() -> void:
		s.set_value_no_signal(float(get(prop)))
		paint.call(s.value))


func _option(parent: Control, text: String, prop: StringName, names: Array[String]) -> void:
	var h := _row(parent, text)
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.custom_minimum_size.x = 250
	UIKit.wire(o)
	o.item_selected.connect(func(i: int) -> void:
		set(prop, i)
		_say("%s: %s." % [text, names[i]]))
	h.add_child(o)
	_refreshers.append(func() -> void: o.select(int(get(prop))))


func _action(parent: Control, text: String, on_press: Callable, variation: StringName = &"") -> void:
	var b := UIKit.button(text, variation)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 40
	b.pressed.connect(on_press)
	parent.add_child(b)


## A weapon picker for `slot` (0 primary, 1 secondary, 2 melee) with its GIVE button.
func _weapon_pick(parent: Control, text: String, slot_name: String, slot: int) -> OptionButton:
	var h := _row(parent, text)
	var o := OptionButton.new()
	for wid in Data.weapon_ids_for_slot(slot_name):
		o.add_item(str(Data.WEAPONS[wid].name))
		o.set_item_metadata(o.item_count - 1, wid)
	o.custom_minimum_size.x = 200
	UIKit.wire(o)
	h.add_child(o)
	var give := UIKit.button("GIVE")
	give.pressed.connect(func() -> void: _give(slot, o))
	h.add_child(give)
	return o


func _refresh_all() -> void:
	for r in _refreshers:
		r.call()
