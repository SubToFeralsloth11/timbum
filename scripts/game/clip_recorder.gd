class_name ClipRecorder
extends Node
## Clips a kill: World's child "ClipRecorder" (`World.clips`). With the `clips` setting on
## (Settings > Gameplay, off by default) the kill cam's recording runs (KillCam) and every kill of
## the local player is remembered; a double tap of `save_clip` (K by default, sharing the key
## with `skip_killcam`, which only works while you are dead) up to Clips.SAVE_WINDOW seconds after
## it saves Clips.BEFORE seconds before that kill to Clips.AFTER past it as a clip (Clips.save_clip),
## with a thumbnail of the screen. When the tap comes before the AFTER tail has been recorded, the
## save waits for it. A card confirms it ("CLIP SAVED"), or says why not (no kill to clip, already
## clipped). The first kill of a match with clips on shows the key once. Clips open in the main
## menu's GALLERY (Studio). Modes without respawns (Tactical) record nothing, so they have no clips.

## A clip saved (checks): its path.
signal saved(path: String)

const HINT_COLOR := Color(0.55, 0.85, 1.0)

var world: World
## The last kill of the local player: {t, victim, wid, head} ({} none yet).
var last_kill := {}
## The last clip's path ("" before the first).
var last_path := ""

var _last_tap := -100.0
var _clipped_t := -100.0
## World.now() when the waiting save may be written (-1: none waiting).
var _save_at := -1.0
var _pending := {}
var _hinted := false


func _init() -> void:
	name = "ClipRecorder"


static func enabled() -> bool:
	return bool(Profile.get_setting("clips"))


## World._s_killed: the local player killed `victim_id` with `wid`.
func on_local_kill(victim_id: int, wid: String, head: bool) -> void:
	if not enabled() or not world.killcam.is_recording():
		return
	last_kill = {"t": World.now(), "victim": victim_id, "victim_name": world.display_name(victim_id), "wid": wid, "head": head}
	if not _hinted:
		_hinted = true
		world.hud.toast("CLIPS ON", "Double-tap %s to clip that kill." % Profile.key_text("save_clip"), HINT_COLOR, 4.0)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled() or event.is_echo() or not event.is_action_pressed(&"save_clip") or world.hud.is_blocking():
		return
	# K also skips the kill cam: while dead (or watching the replay) a double tap is a skip.
	var me := world.local_player
	if me == null or not me.alive or world.killcam.is_playing():
		return
	var now := World.now()
	if now - _last_tap > Clips.DOUBLE_TAP:
		_last_tap = now
		return
	_last_tap = -100.0
	get_viewport().set_input_as_handled()
	request()


## Clips the last kill (the double tap): now, or once its tail has been recorded.
func request() -> void:
	var now := World.now()
	if last_kill.is_empty() or now - float(last_kill.t) > Clips.SAVE_WINDOW:
		_say("NO KILL TO CLIP", "Clip a kill within %d seconds of it." % int(Clips.SAVE_WINDOW), UITheme.BAD)
		return
	if is_equal_approx(float(last_kill.t), _clipped_t) or _save_at >= 0.0:
		_say("ALREADY CLIPPED", "That kill is in your gallery.", UITheme.TEXT_DIM)
		return
	_pending = last_kill.duplicate()
	_clipped_t = float(last_kill.t)
	_save_at = float(last_kill.t) + Clips.AFTER
	Sfx.play(&"ui_click")
	if now < _save_at:
		_say("CLIPPING...", "Saving the last %d seconds." % int(Clips.BEFORE + Clips.AFTER), HINT_COLOR)


func _process(_delta: float) -> void:
	if _save_at >= 0.0 and (World.now() >= _save_at or world.match_over):
		_save_at = -1.0
		_save.call_deferred(_pending)


func _save(kill: Dictionary) -> void:
	var kill_t := float(kill.t)
	var tape := world.killcam.window(kill_t - Clips.BEFORE, kill_t + Clips.AFTER)
	if tape.count < 2:
		_say("CLIP FAILED", "Nothing was recorded.", UITheme.BAD)
		return
	var meta := Clips.match_meta(world)
	meta.merge({"kill_t": kill_t, "victim": int(kill.victim), "victim_name": str(kill.victim_name), "wid": str(kill.wid),
		"head": bool(kill.head)}, true)
	var thumb: Image = null
	if DisplayServer.get_name() != "headless":
		thumb = get_viewport().get_texture().get_image()
	var path := Clips.save_clip(tape, meta, thumb)
	if path.is_empty():
		_say("CLIP FAILED", "Couldn't write the clip file.", UITheme.BAD)
		return
	last_path = path
	Sfx.play(&"ui_buy", null, -4.0)
	_say("CLIP SAVED", "%s · %.0f s · open it in GALLERY" % [str(kill.victim_name), tape.span().y - tape.span().x], UITheme.ACCENT)
	saved.emit(path)


func _say(title: String, text: String, color: Color) -> void:
	world.hud.toast(title, text, color, 3.5)
