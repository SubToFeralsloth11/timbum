class_name Clips
## Saved clips and photo scenes, the gallery's list, export folders and the video render process
## (static).
##
## **Files.** A clip is `user://clips/clip_<date>_<time>.tclip` with a JPEG thumbnail beside it
## (same name, `.jpg`); a photo taken in photo mode is its PNG in `PhotoMode.DIR` plus, beside it,
## the scene it was taken in (same name, `.tclip`). Both `.tclip` kinds are one `store_var`
## Dictionary in a zstd-compressed file: `{version, kind ("clip" | "photo"), meta, tape}`, where
## `tape` is KillCam.Tape.to_dict() (a clip: BEFORE seconds before the kill to AFTER past it; a
## photo: one frame) and `meta` says where and who: `map`, `time_of_day`, `weather`, `mutator`,
## `mode`, `me` (the recording player's entity id), `players` (entity id -> look: `name`, `outfit`,
## `hat`, `skin`, `charm`, `draw`, `camos`, `band` (team armband colour, "" none), `tint`
## ("infected" or "")), `created` (Unix time) and, for a clip, `kill_t`, `victim`, `victim_name`
## and `wid`; for a photo, `camera` (Transform3D) and `fov`. Studio opens both.
##
## **Render process.** Studio exports a video by starting the game again with
## `--fixed-fps <fps> --write-movie <scratch.avi> <Studio.SCENE> -- --timbum-render=<job.json>`:
## fixed time steps make every frame, effect and sound land exactly on the video's clock however
## long a frame takes to draw, and Movie Maker's audio driver mixes the sound in step with them. That
## process (is_render_process) never saves the profile, never updates, plays no music and renders
## the job's frames into its own file (Studio.RenderJob).

const DIR := "user://clips"
const EXT := "tclip"
const VERSION := 1
## Seconds of a clip before the kill, and after it (the victim falls).
const BEFORE := 10.0
const AFTER := 1.5
## A double tap of `save_clip` up to this long after a kill clips that kill.
const SAVE_WINDOW := 10.0
## Two presses of `save_clip` at most this far apart are a double tap.
const DOUBLE_TAP := 0.4
const THUMB_SIZE := Vector2i(384, 216)
const RENDER_ARG := "--timbum-render="


## Whether this process is Studio's video render (see "Render process").
static func is_render_process() -> bool:
	return not render_job_path().is_empty()


## The render job file this process was started for ("" for a normal start).
static func render_job_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(RENDER_ARG):
			return arg.trim_prefix(RENDER_ARG)
	return ""


## A fresh path in `dir` named `<prefix>_<YYYY-MM-DD>_<HH-MM-SS>.<ext>` (numbered when taken).
static func dated_path(dir: String, prefix: String, ext: String) -> String:
	var d := Time.get_datetime_dict_from_system()
	var base := "%s/%s_%04d-%02d-%02d_%02d-%02d-%02d" % [dir, prefix, d.year, d.month, d.day, d.hour, d.minute, d.second]
	var path := "%s.%s" % [base, ext]
	var n := 2
	while FileAccess.file_exists(path):
		path = "%s_%d.%s" % [base, n, ext]
		n += 1
	return path


## The look of every player in `world` for a clip's meta: entity id -> {name, outfit, ...}.
static func player_looks(world: World) -> Dictionary:
	var out := {}
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		var team := Teams.of(p)
		out[eid] = {"name": world.display_name(eid), "outfit": str(p.info.get("outfit", "classic")),
			"hat": str(p.info.get("hat", "none")), "skin": str(p.info.get("skin", "default")),
			"charm": str(p.info.get("charm", "none")), "draw": str(p.info.get("draw", "standard")),
			"camos": (p.info.get("camos", []) as Array).duplicate() if typeof(p.info.get("camos")) == TYPE_ARRAY else [],
			"band": Teams.color(team).to_html(false) if team >= 0 else "",
			"tint": "infected" if p.avatar != null and p.avatar.get_tint() != null else ""}
	return out


## Where and who of the match `world` is playing (the shared part of a clip's or photo's meta).
static func match_meta(world: World) -> Dictionary:
	return {"map": Net.current_map, "time_of_day": str(Net.config.get("time_of_day", "day")),
		"weather": str(Net.config.get("weather", "clear")), "mutator": str(Net.config.get("mutator", "")),
		"mode": str(Net.config.get("mode", "ffa")), "me": world.my_id(), "players": player_looks(world),
		"created": int(Time.get_unix_time_from_system())}


## Writes a clip (and its thumbnail when `thumb` isn't null); returns its path ("" on failure).
static func save_clip(tape: KillCam.Tape, meta: Dictionary, thumb: Image) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := dated_path(DIR, "clip", EXT)
	if not _write(path, "clip", tape, meta):
		return ""
	if thumb != null and not thumb.is_empty():
		var small := thumb.duplicate() as Image
		small.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_BILINEAR)
		small.save_jpg(thumb_path(path), 0.85)
	return path


## Writes the scene of the photo at `png_path` beside it; false on failure.
static func save_photo_scene(png_path: String, tape: KillCam.Tape, meta: Dictionary) -> bool:
	return _write(scene_path(png_path), "photo", tape, meta)


static func _write(path: String, kind: String, tape: KillCam.Tape, meta: Dictionary) -> bool:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("Clips: could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_var({"version": VERSION, "kind": kind, "meta": meta, "tape": tape.to_dict()})
	var ok := f.get_error() == OK
	f.close()
	return ok


## A saved clip or photo scene: {kind, meta, tape: KillCam.Tape}; {} when missing or unreadable.
static func load_file(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var data: Variant = f.get_var()
	f.close()
	if typeof(data) != TYPE_DICTIONARY or int((data as Dictionary).get("version", 0)) != VERSION:
		return {}
	var d: Dictionary = data
	if typeof(d.get("meta")) != TYPE_DICTIONARY or typeof(d.get("tape")) != TYPE_DICTIONARY:
		return {}
	var tape := KillCam.Tape.from_dict(d.tape)
	if tape == null:
		return {}
	return {"kind": str(d.get("kind", "clip")), "meta": d.meta, "tape": tape}


static func thumb_path(clip_path: String) -> String:
	return clip_path.get_basename() + ".jpg"


## The scene file beside a photo (it may not exist: photos from before 2.1, or a failed write).
static func scene_path(png_path: String) -> String:
	return png_path.get_basename() + "." + EXT


## Every clip and photo, newest first: {kind ("clip" | "photo"), path (the .tclip or the .png),
## thumb (an image path), scene (a photo's scene file, "" without one), time (Unix)}.
static func gallery() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for name in _files(DIR, EXT):
		var path := DIR.path_join(name)
		items.append({"kind": "clip", "path": path, "thumb": thumb_path(path), "scene": path,
			"time": FileAccess.get_modified_time(path)})
	for name in _files(PhotoMode.DIR, "png"):
		var path := PhotoMode.DIR.path_join(name)
		var scene := scene_path(path)
		items.append({"kind": "photo", "path": path, "thumb": path, "scene": scene if FileAccess.file_exists(scene) else "",
			"time": FileAccess.get_modified_time(path)})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.time) > int(b.time))
	return items


static func _files(dir: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for name in da.get_files():
		if name.get_extension().to_lower() == ext:
			out.append(name)
	return out


## Deletes a gallery item and its thumbnail / scene file.
static func delete_item(item: Dictionary) -> void:
	for key: String in ["path", "thumb", "scene"]:
		var p := str(item.get(key, ""))
		if not p.is_empty() and FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## The folder exports go to: Movies/Timbum or Pictures/Timbum (the user folder's `exports` when the
## system has no such folder). Made if missing.
static func export_dir(video: bool) -> String:
	var base := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES if video else OS.SYSTEM_DIR_PICTURES)
	var dir := base.path_join("Timbum") if not base.is_empty() else ProjectSettings.globalize_path("user://exports")
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		dir = ProjectSettings.globalize_path("user://exports")
		DirAccess.make_dir_recursive_absolute(dir)
	return dir


## An ffmpeg binary to turn a video into MP4 ("" when none is installed). Apps started from the Dock
## don't get the shell's PATH, so the usual install folders are tried first.
static func find_ffmpeg() -> String:
	var candidates := ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
	for c: String in candidates:
		if FileAccess.file_exists(c):
			return c
	var out: Array = []
	var finder := "where" if OS.get_name() == "Windows" else "which"
	if OS.execute(finder, ["ffmpeg"], out) == 0 and not out.is_empty():
		var first := str(out[0]).strip_edges().split("\n")[0].strip_edges()
		if not first.is_empty() and FileAccess.file_exists(first):
			return first
	return ""


## macOS's own converter (AVFoundation), which turns a QuickTime .mov into an H.264 .mp4.
static func find_avconvert() -> String:
	return "/usr/bin/avconvert" if OS.get_name() == "macOS" and FileAccess.file_exists("/usr/bin/avconvert") else ""
