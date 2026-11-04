class_name Studio
extends Node
## The clip and photo editor (scene `scenes/studio.tscn`), opened from the main menu's GALLERY with
## `Studio.pending` set to a gallery item (Clips.gallery). Three kinds of item:
##
## - **Clip** (Clips.save_clip): the map is built again and the recorded kill plays back through a
##   ReplayView: every player a ghost avatar at their recorded pose, the shots, tracers, explosions,
##   blood and sounds. A timeline scrubs it, trims it (IN / OUT handles) and plays it at 0.25x-2x
##   (slow motion slows the effects and lowers the sound with Engine.time_scale).
## - **Photo scene** (a photo-mode PNG with its scene file): the same, for the one frame the photo
##   was taken at, starting from the photo's camera.
## - **Picture** (a PNG without a scene, from before 2.1): only the look can change.
##
## **Cameras** (clips and scenes): POV (the target's eyes, gun in hand), CHASE (behind them), ORBIT
## (circling them) and DRONE: hold the right mouse button on the picture to fly it (photo mode's
## controls); ADD KEY keeps the drone's view at the playhead and the drone then flies through the
## keys (Catmull-Rom path, eased turns, FOV between keys). The target is any recorded player (YOU
## by default). The scene's time of day and weather can be changed, and depth of field blurs what
## is far from the target. **Look**: StudioLook's filters and adjustments, plus an optional
## watermark and the YOU tag.
##
## **Export.** Pictures render at the chosen resolution in this process and are saved as PNG in
## Pictures/Timbum (Clips.export_dir). Videos render in a second game process
## (Clips "Render process"): this one writes the job (`user://clips/render_job.bin`: the item, the
## edit, size, fps, format and output path), starts the game with `--fixed-fps` and Movie Maker's
## audio driver, shows its progress (`user://clips/render_progress.json`) and can cancel it. That
## process opens this scene in render mode: it plays the trimmed span frame by frame at the
## export's fps (every frame drawn at full quality however long it takes), grabs each frame from
## the SubViewport at the export's size, records the game's own mix with an AudioEffectCapture
## on the Master bus, and writes them with VideoWriter (Motion-JPEG and PCM in a QuickTime .mov on
## macOS, .avi elsewhere). Then it converts that to an H.264 .mp4 when it can (macOS's avconvert,
## else an installed ffmpeg), keeping the .mov / .avi when it can't, and quits. Exports go to
## Movies/Timbum.

const SCENE := "res://scenes/studio.tscn"
const CAMERAS: Array = [["pov", "POV"], ["chase", "CHASE"], ["orbit", "ORBIT"], ["drone", "DRONE"]]
const TIMES: Array = [["day", "DAY"], ["sunset", "SUNSET"], ["night", "NIGHT"]]
const RESOLUTIONS: Array = [[1280, 720, "720p"], [1920, 1080, "1080p"], [2560, 1440, "1440p"], [3840, 2160, "4K"]]
const FPS_CHOICES: Array[int] = [30, 60]
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0]
## Seconds played (not recorded) before an export's first frame, so poses and effects have settled.
const PREROLL := 0.5
const JPEG_QUALITY := 0.92
const JOB_PATH := "user://clips/render_job.bin"
const PROGRESS_PATH := "user://clips/render_progress.json"
const SCRATCH_MOVIE := "user://clips/render_scratch.avi"
## The render's own video while it is written (+ "mov" or "avi"), moved to Movies/Timbum when whole.
const SCRATCH_VIDEO := "user://clips/render_video."
## Graphics settings for a render (the High preset plus full render scale, no frame cap).
const RENDER_SETTINGS := {"quality": 2, "shadow_quality": 3, "ssao_quality": 3, "ssil": true, "bloom": true,
	"reflections": true, "anti_aliasing": 3, "anisotropic": 4, "weather_fx": 2, "block_detail": true,
	"render_scale": 1.0, "dynamic_resolution": 0, "window_mode": 0, "vsync_mode": 0, "fps_limit": 0,
	"background_fps": false, "mute_unfocused": false, "master_volume": 1.0, "sfx_volume": 1.0, "music_volume": 0.0}

## The gallery item to open: {kind, path, scene, thumb} (Clips.gallery).
static var pending := {}

## The map, replay and cameras are built (a clip or photo scene).
signal stage_ready

var item := {}
## "clip", "scene" (a photo with its scene) or "picture" (a plain image).
var kind := ""
var meta := {}
var tape: KillCam.Tape
## Everything the user changed (see _default_edit); also the render job's edit.
var edit := {}
## Clip time (0 = the tape's first frame) of the playhead, and the clip's length.
var time := 0.0
var length := 0.0
var playing := false
## Why the item couldn't open ("" when it did).
var error := ""

var _t0 := 0.0
var _view: SubViewport
var _container: SubViewportContainer
var _aspect: AspectRatioContainer
var _map_root: Node3D
var _map_info: MapInfo
var _base_atm := {}
var _weather: Weather
var _post: PostProcess
var _fx: Fx
var _replay: ReplayView
var _drone: FreeCam
var _shot: Camera3D
var _look: StudioLook
var _picture: TextureRect
var _picture_size := Vector2i.ZERO
var _attrs: CameraAttributesPractical
var _flying := false
var _render := {}
var _render_pid := -1
var _render_poll := 0.0
## The export being written ("" when none, or once it finished): removed if the render stops.
var _render_out := ""

# UI
var _ui: Control
var _title: Label
var _info: Label
var _status: Label
var _side: VBoxContainer
var _timeline: StudioTimeline
var _play_btn: Button
var _time_label: Label
var _speed_btn: OptionButton
var _rows := {}
var _keys_label: Label
var _busy: Control
var _busy_label: Label
var _busy_bar: ProgressBar
var _busy_cancel: Button
var _busy_show: Button
var _last_export := ""


func _ready() -> void:
	var job_path := Clips.render_job_path()
	if not job_path.is_empty():
		_start_render(job_path)
		return
	Sfx.stop_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	item = pending.duplicate()
	_open(item)
	_build_ui()
	if not error.is_empty():
		_status.text = error
		return
	_apply_edit()
	_seek(edit.trim_in if kind == "clip" else 0.0)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	if _render_pid > 0 and OS.is_process_running(_render_pid):
		OS.kill(_render_pid)


# ================================================================ opening

## Loads `it` and builds what it needs to show; sets `error` when it can't.
func _open(it: Dictionary) -> void:
	_view = SubViewport.new()
	_view.name = "View"
	_view.size = Vector2i(1280, 720)
	_view.audio_listener_enable_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.use_debanding = true
	_view.positional_shadow_atlas_size = 4096
	_view.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var scene := str(it.get("scene", ""))
	if scene.is_empty():
		kind = "picture"
		var img := Image.load_from_file(ProjectSettings.globalize_path(str(it.get("path", ""))))
		if img == null or img.is_empty():
			error = "Couldn't open this picture."
			return
		_picture = TextureRect.new()
		_picture.texture = ImageTexture.create_from_image(img)
		_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_picture.stretch_mode = TextureRect.STRETCH_SCALE
		var layer := CanvasLayer.new()
		layer.layer = 0
		layer.add_child(_picture)
		_view.add_child(layer)
		_picture_size = img.get_size()
		_view.size = _picture_size
		edit = _default_edit()
		_add_look()
		return
	var data := Clips.load_file(scene)
	if data.is_empty():
		error = "This file is damaged or from another version of Timbum."
		return
	kind = "clip" if data.kind == "clip" else "scene"
	meta = data.meta
	tape = data.tape
	_t0 = tape.times[tape.at(0)]
	length = maxf(tape.span().y - _t0, 0.0)
	var map := str(meta.get("map", ""))
	if not (Data.MAPS.has(map) or (CustomMaps.is_custom(map) and FileAccess.file_exists(CustomMaps.path_for(CustomMaps.name_of(map))))):
		error = "The map of this %s (%s) isn't on this computer." % ["clip" if kind == "clip" else "photo", map]
		return
	edit = _default_edit()
	_build_stage(map)


## Builds the map, effects, replay and cameras under the SubViewport (which must be in the tree
## first: MapBuilder needs it).
func _build_stage(map: String) -> void:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	_view.add_child(_map_root)
	_fx = Fx.new()
	_fx.name = "Fx"
	_view.add_child(_fx)
	_replay = ReplayView.new()
	_replay.fx = _fx
	_replay.info_of = func(eid: int) -> Dictionary: return (meta.players as Dictionary).get(eid, {})
	_replay.look_of = _dress
	_view.add_child(_replay)
	_shot = Camera3D.new()
	_shot.name = "ShotCam"
	_shot.near = 0.05
	_shot.far = 400.0
	_view.add_child(_shot)
	_drone = FreeCam.new()
	_drone.name = "Drone"
	_drone.allow_roll = true
	_drone.fly_when_paused = true
	_view.add_child(_drone)
	_attrs = CameraAttributesPractical.new()
	for cam: Camera3D in [_shot, _drone, _replay.camera]:
		cam.attributes = _attrs
	_add_look()
	# The map is built once the viewport is in the tree (MapBuilder needs it), after the tree has
	# finished adding the viewport's children.
	_map_root.ready.connect(_finish_stage.bind(map), CONNECT_ONE_SHOT | CONNECT_DEFERRED)


func _finish_stage(map: String) -> void:
	_map_info = MapBuilder.build(map, _map_root, int(Profile.get_setting("quality")), false)
	_drone.set_bounds(_map_info.bounds)
	var envs := _map_root.find_children("*", "WorldEnvironment", true, false)
	if not envs.is_empty():
		_base_atm = (envs[0] as WorldEnvironment).get_meta(&"atmosphere", {})
	_set_scene_look()
	_replay.begin(tape, _t0, 0)
	# A render job carries the drone's view (a drone shot without keys); a photo its camera.
	var start: Transform3D = edit.get("drone", meta.get("camera", Transform3D(Basis.IDENTITY, _map_info.bounds.get_center())))
	_drone.place(start, float(edit.get("drone_fov", edit.fov)))
	if kind == "scene":
		_drone.make_current()
	_apply_edit()
	_seek(time)
	stage_ready.emit()


func _add_look() -> void:
	_look = StudioLook.new()
	_view.add_child(_look)


## A fresh edit for the open item.
func _default_edit() -> Dictionary:
	var e := StudioLook.defaults()
	e.merge({"camera": "pov" if kind == "clip" else "drone", "target": int(meta.get("me", 0)),
		"fov": float(meta.get("fov", Profile.get_setting("fov"))), "time_of_day": str(meta.get("time_of_day", "day")),
		"weather": str(meta.get("weather", "clear")), "dof": 0.0, "chase_dist": 3.5, "orbit_speed": 0.35,
		"orbit_radius": 4.5, "orbit_angle": 0.0, "keys": [], "trim_in": 0.0, "trim_out": length, "speed": 1.0, "tag": false,
		"resolution": 1, "fps": 1}, true)
	if kind == "scene":
		e.filter = clampi(int(meta.get("filter", 0)), 0, StudioLook.FILTERS.size() - 1)
	if kind == "clip" and meta.has("kill_t"):
		# Start a little before the kill's run-up rather than at the very first frame.
		e.trim_in = clampf(float(meta.kill_t) - _t0 - 6.0, 0.0, maxf(length - 1.0, 0.0))
	return e


## Team armband, Infected tint and Big Heads on a ghost, from the clip's player looks.
func _dress(eid: int, g: Avatar) -> void:
	if g.has_meta(&"dressed"):
		return
	g.set_meta(&"dressed", true)
	var look: Dictionary = (meta.players as Dictionary).get(eid, {})
	if not str(look.get("band", "")).is_empty():
		Teams.set_avatar_armbands(g, Color.html(str(look.band)))
	if str(look.get("tint", "")) == "infected":
		g.set_tint(Models.infected_overlay_material())
	if str(meta.get("mutator", "")) == "big_heads":
		g.grow_head(Player.BIG_HEAD)


## The map's sky, light and weather for the edit's time of day and weather (from the map's own
## atmosphere each time, so any switch looks like a match that rolled it).
func _set_scene_look() -> void:
	if _map_root == null or _base_atm.is_empty():
		return
	var envs := _map_root.find_children("*", "WorldEnvironment", true, false)
	var suns := _map_root.find_children("*", "DirectionalLight3D", true, false)
	if envs.is_empty() or suns.is_empty():
		return
	MapBuilder.apply_atmosphere(envs[0], suns[0], _base_atm)
	var tod := str(edit.time_of_day)
	World._apply_time_of_day(_map_root, tod)
	if _weather != null:
		_weather.queue_free()
	_weather = Weather.new()
	_weather.setup(_map_root, str(edit.weather), tod)
	_view.add_child(_weather)
	if _post != null:
		_post.queue_free()
	_post = PostProcess.new()
	_post.name = "PostProcess"
	_view.add_child(_post)
	_post.setup(tod)


# ================================================================ playback

func _process(delta: float) -> void:
	if not _render.is_empty():
		return
	_poll_render(delta)
	if _replay == null or _replay.tape == null or _map_info == null:
		return
	if playing and kind == "clip":
		var next := time + delta
		if next >= float(edit.trim_out):
			_seek(float(edit.trim_in))
		else:
			time = next
			_replay.step(_t0 + time, delta)
	else:
		_replay.step(_t0 + time, 0.0)
	_place_camera(time, delta)
	_refresh_time()


func _seek(t: float) -> void:
	time = clampf(t, 0.0, length)
	if _replay != null and _replay.tape != null:
		_replay.seek(_t0 + time)
		_replay.step(_t0 + time, 0.0)
		_place_camera(time, 0.0)
	_refresh_time()


func set_playing(on: bool) -> void:
	playing = on and kind == "clip"
	Engine.time_scale = float(edit.speed) if playing else 1.0
	AudioServer.playback_speed_scale = Engine.time_scale
	if _play_btn != null:
		_play_btn.text = "❚❚" if playing else "▶"


## Points the camera of the edit's mode at clip time `t`.
func _place_camera(t: float, _delta: float) -> void:
	if _map_info == null:
		return
	var mode := str(edit.camera)
	var target := int(edit.target)
	if mode == "pov":
		if _replay.pov != target:
			_replay.set_pov(target)
		_replay.base_fov = float(edit.fov)
		if not _replay.camera.current:
			_replay.camera.make_current()
		_set_dof(2.5)
		return
	if _replay.pov != 0:
		_replay.set_pov(0)
	var has_pose := _replay.sample(target, _t0 + t)
	var eye := _replay.s_eye
	var feet := _replay.s_pos
	match mode:
		"chase":
			if not has_pose:
				return
			var yaw := _smooth_yaw(target, _t0 + t)
			var back := Basis(Vector3.UP, yaw) * Vector3(0.55, 0.0, float(edit.chase_dist))
			var want := feet + Vector3.UP * 1.95 + back
			_shot.global_transform = Transform3D(Basis.IDENTITY, _clear_of_walls(eye, want))
			_shot.look_at(eye + Basis(Vector3.UP, yaw) * Vector3(0, 0, -2.0), Vector3.UP)
			_shot.fov = float(edit.fov)
			_use(_shot)
			_set_dof(eye.distance_to(_shot.global_position))
		"orbit":
			if not has_pose:
				return
			var a := deg_to_rad(float(edit.orbit_angle)) + float(edit.orbit_speed) * t
			var r := float(edit.orbit_radius)
			var want := eye + Vector3(sin(a) * r, r * 0.35, cos(a) * r)
			_shot.global_transform = Transform3D(Basis.IDENTITY, _clear_of_walls(eye, want))
			_shot.look_at(eye, Vector3.UP)
			_shot.fov = float(edit.fov)
			_use(_shot)
			_set_dof(eye.distance_to(_shot.global_position))
		_:
			var keys: Array = edit.keys
			if not keys.is_empty() and not _flying:
				var k := key_view(t)
				_drone.place(k[0], k[1])
			elif not _flying:
				_drone.fov = float(edit.fov)
			_use(_drone)
			_set_dof(eye.distance_to(_drone.global_position) if has_pose else 10.0)


func _use(cam: Camera3D) -> void:
	if not cam.current:
		cam.make_current()


## The target's heading averaged over the last half second, so the chase camera doesn't twitch
## with every flick of the mouse.
func _smooth_yaw(eid: int, t: float) -> float:
	var v := Vector2.ZERO
	for i in 6:
		if _replay.sample(eid, t - i * 0.1):
			v += Vector2(sin(_replay.s_yaw), cos(_replay.s_yaw))
	_replay.sample(eid, t)
	return atan2(v.x, v.y)


## `want` pulled toward `from` until no block is in between (a camera never sits inside a wall).
func _clear_of_walls(from: Vector3, want: Vector3) -> Vector3:
	var space := _view.world_3d.direct_space_state if _view.world_3d != null else _map_root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, want, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return want
	var p: Vector3 = hit.position
	return p + (from - want).normalized() * 0.3


func _set_dof(focus: float) -> void:
	var amount := float(edit.get("dof", 0.0))
	_attrs.dof_blur_far_enabled = amount > 0.0
	_attrs.dof_blur_near_enabled = amount > 0.0
	_attrs.dof_blur_amount = 0.04 + amount * 0.16
	_attrs.dof_blur_far_distance = focus + 1.5
	_attrs.dof_blur_far_transition = maxf(focus * 0.6, 2.0)
	_attrs.dof_blur_near_distance = maxf(focus - 1.2, 0.1)
	_attrs.dof_blur_near_transition = maxf(focus * 0.3, 0.3)


## The drone's view at clip time `t` from the keys: [Transform3D, fov]. Positions follow a
## Catmull-Rom curve through the keys, turns and FOV ease between neighbouring keys.
func key_view(t: float) -> Array:
	var keys: Array = edit.keys
	if keys.size() == 1 or t <= float(keys[0][0]):
		return [keys[0][1], float(keys[0][2])]
	var last: Array = keys[keys.size() - 1]
	if t >= float(last[0]):
		return [last[1], float(last[2])]
	var i := 0
	while i < keys.size() - 2 and t > float(keys[i + 1][0]):
		i += 1
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var u := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
	var p0: Vector3 = (keys[maxi(i - 1, 0)][1] as Transform3D).origin
	var p1: Vector3 = (a[1] as Transform3D).origin
	var p2: Vector3 = (b[1] as Transform3D).origin
	var p3: Vector3 = (keys[mini(i + 2, keys.size() - 1)][1] as Transform3D).origin
	var pos := 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)
	var e := u * u * (3.0 - 2.0 * u)
	var rot := Quaternion((a[1] as Transform3D).basis.orthonormalized()).slerp(Quaternion((b[1] as Transform3D).basis.orthonormalized()), e)
	return [Transform3D(Basis(rot), pos), lerpf(float(a[2]), float(b[2]), e)]


## Keeps the drone's current view as a key at the playhead (replacing one within a frame of it).
func add_key() -> void:
	var keys: Array = edit.keys
	for i in range(keys.size() - 1, -1, -1):
		if absf(float(keys[i][0]) - time) < 0.05:
			keys.remove_at(i)
	keys.append([time, _drone.global_transform, _drone.fov])
	keys.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	set_edit("camera", "drone")
	Sfx.play(&"ui_click")
	_refresh_keys()


func clear_keys() -> void:
	(edit.keys as Array).clear()
	_refresh_keys()


# ================================================================ editing

## Changes one edit value and applies it.
func set_edit(key: String, value: Variant) -> void:
	edit[key] = value
	if key == "speed":
		set_playing(playing)
	_apply_edit()
	if key in ["time_of_day", "weather"]:
		_set_scene_look()
	_seek(time) if key in ["camera", "target"] else null


## Applies the whole edit (look, tag, timeline, the side panel's state).
func _apply_edit() -> void:
	if _look != null:
		_look.apply(edit, float(_view.size.y))
	if _replay != null:
		_replay.tag_eid = int(meta.get("me", 0)) if edit.get("tag", false) else 0
	_refresh_rows()
	_refresh_keys()


# ================================================================ export

## Saves the picture (a clip's current frame, a photo scene or a picture with its look) as a PNG
## in Clips.export_dir(false) at the chosen resolution (a picture: its own size).
func export_photo() -> String:
	if _busy != null and _busy.visible:
		return ""
	set_playing(false)
	var res: Array = RESOLUTIONS[int(edit.resolution)]
	var size := _picture_size if kind == "picture" else Vector2i(int(res[0]), int(res[1]))
	_show_busy("Rendering the picture...", false)
	_container.stretch = false
	_view.size = size
	_look.apply(edit, float(size.y))
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := _view.get_texture().get_image()
	_container.stretch = true
	_look.apply(edit, float(_view.size.y))
	var path := Clips.dated_path(Clips.export_dir(false), "timbum", "png")
	var err := img.save_png(path) if img != null and not img.is_empty() else ERR_CANT_CREATE
	if err != OK:
		_finish_busy("Couldn't save the picture (%s)." % error_string(err), "")
		return ""
	Sfx.play(&"ui_buy")
	_finish_busy("Saved %s" % path, path)
	return path


## Starts the video render process for the trimmed clip (see "Export").
func export_video() -> void:
	if kind != "clip" or (_busy != null and _busy.visible):
		return
	set_playing(false)
	var res: Array = RESOLUTIONS[int(edit.resolution)]
	var native := VideoWriter.native_extension()
	var mp4 := not Clips.find_avconvert().is_empty() if native == "mov" else not Clips.find_ffmpeg().is_empty()
	var out := Clips.dated_path(Clips.export_dir(true), "timbum_clip", "mp4" if mp4 else native)
	var e := edit.duplicate(true)
	e.drone = _drone.global_transform
	e.drone_fov = _drone.fov
	# The video is written to a scratch file and only moved to `out` once it is whole.
	var job := {"item": item, "edit": e, "width": int(res[0]), "height": int(res[1]),
		"fps": FPS_CHOICES[int(edit.fps)], "out": out, "native": ProjectSettings.globalize_path(SCRATCH_VIDEO + native), "mp4": mp4}
	_render_out = out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Clips.DIR))
	var f := FileAccess.open(JOB_PATH, FileAccess.WRITE)
	if f == null:
		_show_busy("", false)
		_finish_busy("Couldn't start the export (%s)." % error_string(FileAccess.get_open_error()), "")
		return
	f.store_var(job)
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))
	var args := PackedStringArray()
	if not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	# Release builds refuse a scene on the command line: the main menu sends a render process
	# here instead (Clips.is_render_process).
	args.append_array(["--fixed-fps", str(job.fps), "--write-movie", ProjectSettings.globalize_path(SCRATCH_MOVIE),
		"--disable-vsync", "--windowed", "--resolution", "640x360", "--",
		Clips.RENDER_ARG + ProjectSettings.globalize_path(JOB_PATH)])
	_render_pid = OS.create_process(OS.get_executable_path(), args)
	if _render_pid <= 0:
		_show_busy("", false)
		_finish_busy("Couldn't start the export.", "")
		return
	_render_poll = 0.0
	_show_busy("Exporting %s at %s, %d fps..." % [_clip_name(), res[2], job.fps], true)


func _poll_render(delta: float) -> void:
	if _render_pid <= 0:
		return
	_render_poll -= delta / maxf(Engine.time_scale, 0.01)
	if _render_poll > 0.0:
		return
	_render_poll = 0.25
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_PATH)) if FileAccess.file_exists(PROGRESS_PATH) else null
	var progress: Dictionary = p if typeof(p) == TYPE_DICTIONARY else {}
	if progress.get("done", false):
		_render_pid = -1
		if progress.get("ok", false):
			_render_out = ""
			_tidy_render()
			Sfx.play(&"ui_buy")
			_finish_busy("Saved %s" % str(progress.out), str(progress.out))
		else:
			_tidy_render()
			_finish_busy("Export failed: %s" % str(progress.get("error", "unknown error")), "")
		return
	if not OS.is_process_running(_render_pid):
		_render_pid = -1
		_tidy_render()
		_finish_busy("The export stopped before it finished.", "")
		return
	var frames := int(progress.get("frames", 0))
	if frames > 0:
		_busy_bar.value = float(progress.get("frame", 0)) / frames * 100.0
		_busy_label.text = "%s  %d / %d frames" % [str(progress.get("stage", "Rendering")), int(progress.frame), frames]


func cancel_export() -> void:
	if _render_pid > 0:
		OS.kill(_render_pid)
		_render_pid = -1
		_tidy_render()
	_finish_busy("Export cancelled.", "")


## Removes the render's job, progress and scratch files, and a half-written export when it
## didn't finish (`_render_out` is cleared once it did).
func _tidy_render() -> void:
	for p: String in [SCRATCH_MOVIE, PROGRESS_PATH, JOB_PATH, SCRATCH_VIDEO + "mov", SCRATCH_VIDEO + "avi"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if not _render_out.is_empty() and FileAccess.file_exists(_render_out):
		DirAccess.remove_absolute(_render_out)
	_render_out = ""


# ================================================================ render process

## Render mode: this process was started by export_video with the job at `job_path`.
func _start_render(job_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Clips.DIR))
	var f := FileAccess.open(job_path, FileAccess.READ)
	var job: Variant = f.get_var() if f != null else null
	if typeof(job) != TYPE_DICTIONARY:
		_report({"done": true, "ok": false, "error": "no render job"})
		get_tree().quit(1)
		return
	_render = job
	get_window().title = "Timbum — exporting a clip"
	_open(_render.item)
	if not error.is_empty() or kind != "clip":
		_report({"done": true, "ok": false, "error": error if not error.is_empty() else "not a clip"})
		get_tree().quit(1)
		return
	edit.merge(_render.edit, true)
	_view.size = Vector2i(int(_render.width), int(_render.height))
	var shown := TextureRect.new()
	shown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(shown)
	var note := Label.new()
	note.text = "Exporting your clip. This window closes by itself."
	note.position = Vector2(12, 8)
	layer.add_child(note)
	stage_ready.connect(func() -> void:
		shown.texture = _view.get_texture()
		_render_frames.call_deferred(), CONNECT_ONE_SHOT)
	add_child(_view)


func _report(state: Dictionary) -> void:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(state))


func _render_frames() -> void:
	_apply_edit()
	var fps := int(_render.fps)
	var speed := float(edit.speed)
	var step := speed / fps
	Engine.time_scale = speed
	AudioServer.playback_speed_scale = speed
	var t_in := float(edit.trim_in)
	var t_out := float(edit.trim_out)
	var frames := maxi(1, ceili((t_out - t_in) / step))
	var master := AudioServer.get_bus_index("Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(master, capture)
	var rate := roundi(AudioServer.get_mix_rate())
	var writer := VideoWriter.new()
	var native := str(_render.native)
	var err := writer.open(native, int(_render.width), int(_render.height), fps, rate)
	if err != OK:
		_report({"done": true, "ok": false, "error": "couldn't write %s (%s)" % [native, error_string(err)]})
		get_tree().quit(1)
		return
	# Pre-roll: play into the first frame so the poses, viewmodel and effects are already moving.
	var t := maxf(t_in - PREROLL, 0.0)
	_replay.seek(_t0 + t)
	while t < t_in - step * 0.5:
		t += step
		time = t
		_replay.step(_t0 + t, step)
		_place_camera(t, step)
		await RenderingServer.frame_post_draw
	capture.clear_buffer()
	for i in frames:
		time = t_in + i * step
		_replay.step(_t0 + time, step)
		_place_camera(time, step)
		await RenderingServer.frame_post_draw
		var img := _view.get_texture().get_image()
		if img.get_size() != Vector2i(int(_render.width), int(_render.height)):
			img.resize(int(_render.width), int(_render.height))
		writer.add_frame(img.save_jpg_to_buffer(JPEG_QUALITY))
		var avail := capture.get_frames_available()
		if avail > 0:
			writer.add_audio(capture.get_buffer(avail))
		if i % 10 == 0:
			_report({"frame": i, "frames": frames, "stage": "Rendering"})
	err = writer.close()
	AudioServer.remove_bus_effect(master, AudioServer.get_bus_effect_count(master) - 1)
	if err != OK:
		_report({"done": true, "ok": false, "error": "couldn't finish the video (%s)" % error_string(err)})
		get_tree().quit(1)
		return
	var want := str(_render.out)
	var out := ""
	if bool(_render.mp4):
		_report({"frame": frames, "frames": frames, "stage": "Converting to MP4"})
		await get_tree().process_frame
		if _convert_mp4(native, want):
			out = want
		elif FileAccess.file_exists(want):
			DirAccess.remove_absolute(want)
	if out.is_empty():
		# No MP4 (no converter, or it failed): keep the .mov / .avi itself.
		out = want.get_basename() + "." + native.get_extension()
		if DirAccess.rename_absolute(native, out) != OK and DirAccess.copy_absolute(native, out) != OK:
			_report({"done": true, "ok": false, "error": "couldn't move the video to %s" % out.get_base_dir()})
			get_tree().quit(1)
			return
	if FileAccess.file_exists(native):
		DirAccess.remove_absolute(native)
	_report({"done": true, "ok": true, "out": out})
	get_tree().quit()


## Turns the native video into an H.264 .mp4 at `mp4` (macOS avconvert, else ffmpeg).
func _convert_mp4(src: String, mp4: String) -> bool:
	var output: Array = []
	var code := -1
	if src.ends_with(".mov") and not Clips.find_avconvert().is_empty():
		code = OS.execute(Clips.find_avconvert(), ["--source", src, "--output", mp4, "--preset", "PresetHighestQuality", "--replace"], output, true)
	if code != 0 and not Clips.find_ffmpeg().is_empty():
		code = OS.execute(Clips.find_ffmpeg(), ["-y", "-v", "error", "-i", src, "-c:v", "libx264", "-preset", "medium", "-crf", "18",
			"-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", mp4], output, true)
	return code == 0 and FileAccess.file_exists(mp4)


# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if not _render.is_empty():
		return
	if event.is_action_pressed(&"ui_cancel") and not _flying:
		get_viewport().set_input_as_handled()
		if _busy != null and _busy.visible:
			if _render_pid <= 0:
				_busy.visible = false
			return
		back()
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo() or _flying or kind != "clip":
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE: set_playing(not playing)
		KEY_LEFT: _step_frames(-1)
		KEY_RIGHT: _step_frames(1)
		KEY_I: _trim(time, float(edit.trim_out))
		KEY_O: _trim(float(edit.trim_in), time)
		_: return
	get_viewport().set_input_as_handled()


func _step_frames(n: int) -> void:
	set_playing(false)
	_seek(time + n / KillCam.RATE)


func _trim(t_in: float, t_out: float) -> void:
	if t_out - t_in < StudioTimeline.MIN_TRIM:
		return
	edit.trim_in = clampf(t_in, 0.0, length)
	edit.trim_out = clampf(t_out, 0.0, length)
	_refresh_time()


## Right mouse on the picture flies the drone (mouse captured while held).
func _on_view_input(event: InputEvent) -> void:
	if kind == "picture" or _map_info == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		var down := (event as InputEventMouseButton).pressed
		if down and str(edit.camera) != "drone":
			var cam := _view.get_camera_3d()
			if cam != null:
				_drone.place(cam.global_transform, cam.fov)
			edit.camera = "drone"
			_apply_edit()
		_flying = down
		_drone.active = down
		_drone.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if down else Input.MOUSE_MODE_VISIBLE
		get_viewport().gui_release_focus()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			set_edit("fov", clampf(float(edit.fov) + (-4.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 4.0), 20.0, 110.0))
			if str(edit.camera) == "drone":
				_drone.fov = float(edit.fov)


func _input(event: InputEvent) -> void:
	if _flying and event is InputEventMouseMotion:
		_drone.look_mouse((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
	elif _flying and event is InputEventMouseButton and not (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_on_view_input(event)


func back() -> void:
	if _render_pid > 0:
		cancel_export()
	GalleryScreen.reopen = true
	get_tree().change_scene_to_file(Net.MENU_SCENE)


func _clip_name() -> String:
	if kind == "clip":
		return "the kill on %s" % str(meta.get("victim_name", "?"))
	return "the photo"


# ================================================================ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	_ui = Control.new()
	_ui.theme = UITheme.get_theme()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	var bg := ColorRect.new()
	bg.color = Color("0b0f1a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_ui.add_child(margin)
	var root := UIKit.vbox(10)
	margin.add_child(root)

	var top := UIKit.hbox(12)
	root.add_child(top)
	var back_btn := _btn("< GALLERY", &"", back)
	top.add_child(back_btn)
	var titles := UIKit.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = UIKit.label(_heading(), &"HeaderLabel")
	_title.add_theme_font_size_override("font_size", 26)
	titles.add_child(_title)
	_info = UIKit.label(_subheading(), &"DimLabel")
	titles.add_child(_info)
	top.add_child(titles)
	if error.is_empty() and kind == "clip":
		top.add_child(_btn("SAVE FRAME", &"", export_photo))
		top.add_child(_btn("EXPORT VIDEO", &"PrimaryButton", export_video))
	elif error.is_empty():
		top.add_child(_btn("EXPORT PHOTO", &"PrimaryButton", export_photo))

	var mid := UIKit.hbox(12)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var frame := UIKit.panel(&"InsetPanel")
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(frame)
	_aspect = AspectRatioContainer.new()
	_aspect.ratio = float(_view.size.x) / maxf(_view.size.y, 1.0) if kind == "picture" else 16.0 / 9.0
	frame.add_child(_aspect)
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_container.gui_input.connect(_on_view_input)
	_aspect.add_child(_container)
	_container.add_child(_view)
	if not error.is_empty():
		_status = UIKit.label("", &"SubheaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
		_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		frame.add_child(_status)
		return

	var scroll := UIKit.pad_friendly(ScrollContainer.new())
	scroll.custom_minimum_size.x = 340
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(scroll)
	_side = UIKit.vbox(8)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_side)
	_build_side()

	_status = UIKit.label("", &"DimLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if kind == "clip":
		var bar := UIKit.hbox(10)
		root.add_child(bar)
		_play_btn = _btn("▶", &"", func() -> void: set_playing(not playing))
		_play_btn.custom_minimum_size.x = 56
		bar.add_child(_play_btn)
		_time_label = UIKit.label("", &"SmallLabel")
		_time_label.custom_minimum_size.x = 120
		bar.add_child(_time_label)
		_timeline = StudioTimeline.new()
		_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_timeline.length = length
		_timeline.kill_t = float(meta.kill_t) - _t0 if meta.has("kill_t") else -1.0
		_timeline.seeked.connect(func(t: float) -> void:
			set_playing(false)
			_seek(t))
		_timeline.trim_changed.connect(func(a: float, b: float) -> void: _trim(a, b))
		bar.add_child(_timeline)
		bar.add_child(_btn("SET IN", &"", func() -> void: _trim(time, float(edit.trim_out))))
		bar.add_child(_btn("SET OUT", &"", func() -> void: _trim(float(edit.trim_in), time)))
		_speed_btn = OptionButton.new()
		_speed_btn.focus_mode = Control.FOCUS_NONE
		for s in SPEEDS:
			_speed_btn.add_item("%sx" % str(s))
		_speed_btn.select(SPEEDS.find(1.0))
		_speed_btn.item_selected.connect(func(i: int) -> void: set_edit("speed", SPEEDS[i]))
		bar.add_child(_speed_btn)
		_status.text = "Space play / pause · ← → step a frame · I / O trim · hold right mouse on the picture to fly the drone (WASD, Space / C up and down, Shift faster, Q / E roll, wheel zoom)"
	elif kind == "scene":
		_status.text = "Hold right mouse on the picture to fly the camera (WASD, Space / C up and down, Shift faster, Q / E roll, wheel zoom)."
	else:
		_status.text = "This photo was taken before Timbum 2.1, so only its look can change."
	root.add_child(_status)
	_build_busy()


func _heading() -> String:
	match kind:
		"clip": return "%s  ·  %s" % [World.weapon_label(str(meta.get("wid", ""))).to_upper(), str(meta.get("victim_name", "?")).to_upper()]
		"scene": return "PHOTO"
		"picture": return "PICTURE"
	return "GALLERY"


func _subheading() -> String:
	if meta.is_empty():
		return str(item.get("path", "")).get_file()
	var mode: Dictionary = Data.MODES.get(str(meta.get("mode", "")), {})
	var when := Time.get_datetime_string_from_unix_time(int(meta.get("created", 0)) + _utc_offset(), true)
	return "%s  ·  %s  ·  %s" % [MapBuilder.map_name(str(meta.map)), str(mode.get("name", meta.get("mode", ""))), when]


static func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _btn(text: String, variation: StringName, action: Callable) -> Button:
	var b := UIKit.button(text, variation)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func _section(text: String) -> void:
	var l := UIKit.label(text, &"SubheaderLabel")
	_side.add_child(l)


## A row of toggle buttons for `key`: [value, label] pairs.
func _choice(key: String, label: String, options: Array) -> void:
	if not label.is_empty():
		_side.add_child(UIKit.label(label, &"SmallLabel"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_side.add_child(flow)
	var buttons: Array[Button] = []
	for opt: Array in options:
		var b := UIKit.button(str(opt[1]), &"ChipButton")
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		var value: Variant = opt[0]
		b.pressed.connect(func() -> void: set_edit(key, value))
		b.set_meta(&"value", value)
		flow.add_child(b)
		buttons.append(b)
	_rows[key] = func() -> void:
		for b in buttons:
			b.set_pressed_no_signal(b.get_meta(&"value") == edit.get(key))


func _slider(key: String, label: String, lo: float, hi: float, fmt: String) -> void:
	var head := UIKit.hbox(6)
	var name_label := UIKit.label(label, &"SmallLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value_label := UIKit.label("", &"SmallLabel")
	head.add_child(value_label)
	_side.add_child(head)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void: set_edit(key, v))
	_side.add_child(s)
	_rows[key] = func() -> void:
		var v := float(edit.get(key, 0.0))
		s.set_value_no_signal(v)
		match fmt:
			"pct": value_label.text = "%+d%%" % roundi(v * 100.0) if lo < 0.0 else "%d%%" % roundi(v * 100.0)
			"stops": value_label.text = "%+.1f" % v
			_: value_label.text = fmt % v


func _toggle(key: String, label: String) -> void:
	var c := CheckBox.new()
	c.text = label
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool) -> void: set_edit(key, on))
	_side.add_child(c)
	_rows[key] = func() -> void: c.set_pressed_no_signal(bool(edit.get(key, false)))


func _build_side() -> void:
	if kind != "picture":
		_section("CAMERA")
		var cams := CAMERAS.duplicate()
		if kind == "scene":
			cams = CAMERAS.filter(func(c: Array) -> bool: return c[0] != "pov")
		_choice("camera", "", cams)
		var targets: Array = []
		var me := int(meta.get("me", 0))
		var ids: Array = (meta.players as Dictionary).keys()
		ids.sort_custom(func(a: int, b: int) -> bool: return (a == me) or (b != me and a < b))
		for eid: int in ids:
			if tape.slot_of(eid) >= 0:
				targets.append([eid, "YOU" if eid == me else str(meta.players[eid].get("name", "?"))])
		_choice("target", "Follow", targets)
		_slider("fov", "Field of view", 20.0, 110.0, "%d°")
		_slider("chase_dist", "Chase distance", 1.5, 10.0, "%.1f m")
		_slider("orbit_radius", "Orbit radius", 2.0, 14.0, "%.1f m")
		_slider("orbit_angle", "Orbit angle", -180.0, 180.0, "%d°")
		if kind == "clip":
			_slider("orbit_speed", "Orbit speed", -1.5, 1.5, "%.2f")
			var tip := UIKit.label("Drone keys: fly the drone, move the playhead, ADD KEY. The drone flies through every key.", &"DimLabel")
			tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_side.add_child(tip)
			var keys_row := UIKit.hbox(6)
			_side.add_child(keys_row)
			keys_row.add_child(_btn("ADD KEY", &"", add_key))
			keys_row.add_child(_btn("CLEAR", &"", clear_keys))
			_keys_label = UIKit.label("", &"SmallLabel")
			keys_row.add_child(_keys_label)
		_slider("dof", "Depth of field", 0.0, 1.0, "pct")

		_section("SCENE")
		_choice("time_of_day", "Time of day", TIMES)
		var weathers: Array = []
		for id: String in Data.WEATHERS:
			weathers.append([id, Weather.label(id)])
		_choice("weather", "Weather", weathers)
		_toggle("tag", "YOU tag over your player")

	_section("LOOK")
	var filters: Array = []
	for i in StudioLook.FILTERS.size():
		filters.append([i, str(StudioLook.FILTERS[i][0]).to_upper()])
	_choice("filter", "Filter", filters)
	for a: Array in StudioLook.ADJUSTMENTS:
		_slider(a[0], a[1], a[2], a[3], a[5])
	_toggle("watermark", "TIMBUM watermark")
	_side.add_child(_btn("RESET LOOK", &"DangerButton", func() -> void:
		edit.merge(StudioLook.defaults(), true)
		_apply_edit()))

	_section("EXPORT")
	if kind != "picture":
		var res: Array = []
		for i in RESOLUTIONS.size():
			res.append([i, RESOLUTIONS[i][2]])
		_choice("resolution", "Resolution", res)
	if kind == "clip":
		var fps: Array = []
		for i in FPS_CHOICES.size():
			fps.append([i, "%d FPS" % FPS_CHOICES[i]])
		_choice("fps", "Frame rate", fps)
		var native := VideoWriter.native_extension()
		var mp4 := not Clips.find_avconvert().is_empty() if native == "mov" else not Clips.find_ffmpeg().is_empty()
		var note := UIKit.label("Videos are saved as %s in %s. Frames render at full quality, so the export runs smoothly whatever your frame rate in game." % [
			"MP4 (H.264)" if mp4 else native.to_upper(), Clips.export_dir(true)], &"DimLabel")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side.add_child(note)
	var pnote := UIKit.label("Pictures are saved as PNG in %s." % Clips.export_dir(false), &"DimLabel")
	pnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(pnote)


func _refresh_rows() -> void:
	for key: String in _rows:
		(_rows[key] as Callable).call()


func _refresh_keys() -> void:
	if _keys_label != null:
		_keys_label.text = "%d key%s" % [(edit.keys as Array).size(), "" if (edit.keys as Array).size() == 1 else "s"]
	if _timeline != null:
		var times := PackedFloat32Array()
		for k: Array in edit.keys:
			times.append(float(k[0]))
		_timeline.keys = times
		_timeline.queue_redraw()


func _refresh_time() -> void:
	if _timeline == null:
		return
	_timeline.set_state(time, float(edit.trim_in), float(edit.trim_out), _timeline.keys)
	_time_label.text = "%05.2f / %05.2f s" % [time - float(edit.trim_in), float(edit.trim_out) - float(edit.trim_in)]


func _build_busy() -> void:
	_busy = ColorRect.new()
	(_busy as ColorRect).color = Color(0, 0, 0, 0.6)
	_busy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_busy.visible = false
	_ui.add_child(_busy)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_busy.add_child(center)
	var card := UIKit.panel()
	card.custom_minimum_size.x = 560
	center.add_child(card)
	var v := UIKit.vbox(12)
	card.add_child(v)
	_busy_label = UIKit.label("", &"SubheaderLabel")
	_busy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_busy_label)
	_busy_bar = ProgressBar.new()
	_busy_bar.custom_minimum_size.y = 20
	_busy_bar.show_percentage = false
	v.add_child(_busy_bar)
	var row := UIKit.hbox(8)
	v.add_child(row)
	row.add_child(UIKit.spacer())
	_busy_show = _btn("SHOW FILE", &"", func() -> void: OS.shell_show_in_file_manager(_last_export))
	row.add_child(_busy_show)
	_busy_cancel = _btn("CANCEL", &"DangerButton", cancel_export)
	row.add_child(_busy_cancel)
	row.add_child(_btn("OK", &"PrimaryButton", func() -> void:
		if _render_pid <= 0:
			_busy.visible = false))


func _show_busy(text: String, cancellable: bool) -> void:
	_busy.visible = true
	_busy_label.text = text
	_busy_bar.visible = true
	_busy_bar.value = 0.0
	_busy_cancel.visible = cancellable
	_busy_show.visible = false


func _finish_busy(text: String, path: String) -> void:
	_busy.visible = true
	_busy_label.text = text
	_busy_bar.visible = false
	_busy_cancel.visible = false
	_last_export = path
	_busy_show.visible = not path.is_empty()
	_status.text = text
