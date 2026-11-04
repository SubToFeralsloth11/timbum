extends Node
## Self-updates an exported game from the GitHub releases, so a new version never has to be sent
## around as a file.
##
## A release (tools/release.py) carries `update.json` (version, RUNTIME, per-platform .pck URL,
## SHA-256 and size), `update.json.sig` (the owner's signature of MANIFEST_PREFIX + the manifest,
## checked with DevTag.signed_by_owner) and one game-data .pck per platform. A few seconds after
## start this node fetches the latest manifest; when it is newer and its RUNTIME matches this
## build's (same Godot engine and native plugins), it downloads the .pck to user://updates/,
## checks its size and hash and records it in STATE (status READY).
##
## The installed game data is one file next to the engine (installed_pck(): the app's
## Resources/Timbum.pck on macOS, Timbum.pck beside Timbum.exe on Windows). It can't change while
## the game runs, so when the game closes (or RESTART in the main menu) a detached helper (sh on
## macOS, PowerShell on Windows) waits for this process to exit, moves the downloaded pack over
## it, re-signs the macOS app ad hoc (the pack is a sealed resource) and, for RESTART, starts the
## game again. The next start runs the new version; finding its own version at or past STATE's,
## it clears STATE.
##
## A release with another RUNTIME (new engine or plugins), or an install whose pack can't be
## written (a read-only folder, a Windows build with the pack inside the .exe), gets status FULL:
## the menu links to the release page for the full app. Only release exports update (`template`
## feature), never the editor or a debug run.

signal status_changed

const OWNER_REPO := "SubToFeralsloth11/timbum"
const FEED := "https://github.com/%s/releases/latest/download/" % OWNER_REPO
const RELEASES_PAGE := "https://github.com/%s/releases/latest" % OWNER_REPO
const MANIFEST := "update.json"
const MANIFEST_PREFIX := "timbum-update\n"
## Engine and native-plugin fingerprint of this build. tools/release.py computes it and keeps it
## current; a pack is only installed by a build with the same value.
const RUNTIME := "e610386ceea7d68c"
const DIR := "user://updates/"
const STATE := DIR + "state.json"
const CHECK_DELAY := 3.0
const MAX_MANIFEST_BYTES := 65536

enum Status { OFF, IDLE, CHECKING, UP_TO_DATE, DOWNLOADING, READY, FULL, FAILED }

var status := Status.OFF
## The version on offer (DOWNLOADING, READY, FULL).
var new_version := ""
## 0..1 while DOWNLOADING.
var progress := 0.0
## Where FULL sends the player: the release page.
var full_url := RELEASES_PAGE

var _feed := FEED
var _http: HTTPRequest
var _download_size := 0
## The helper that installs the update has been started (once per run).
var _installing := false


func _ready() -> void:
	if not enabled():
		return
	status = Status.IDLE
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--update-feed="):
			_feed = arg.trim_prefix("--update-feed=")
			if not _feed.ends_with("/"):
				_feed += "/"
	_tidy()
	_http = HTTPRequest.new()
	add_child(_http)
	get_tree().create_timer(CHECK_DELAY, true).timeout.connect(check)


func _process(_delta: float) -> void:
	if status == Status.DOWNLOADING and _download_size > 0:
		var p := clampf(float(_http.get_downloaded_bytes()) / _download_size, 0.0, 1.0)
		if not is_equal_approx(p, progress):
			progress = p
			status_changed.emit()


## The game is shutting down: install a downloaded update now, so the next start runs it.
func _exit_tree() -> void:
	if status == Status.READY:
		_install(false)


static func enabled() -> bool:
	return OS.has_feature("template") and not platform().is_empty()


static func platform() -> String:
	match OS.get_name():
		"macOS": return "macos"
		"Windows": return "windows"
	return ""


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


## -1, 0 or 1 for dotted numeric versions ("2.0.10" > "2.0.9"); missing parts count as 0.
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


## The game-data pack this executable loads at start ("" when there is none to replace, e.g. a
## Windows build with the pack embedded in the .exe).
static func installed_pck() -> String:
	var exe := OS.get_executable_path()
	var path := ""
	match platform():
		"macos":
			path = exe.get_base_dir().get_base_dir().path_join("Resources").path_join(exe.get_file().get_basename() + ".pck")
		"windows":
			path = exe.get_basename() + ".pck"
	return path if not path.is_empty() and FileAccess.file_exists(path) else ""


## Whether installed_pck() can be replaced: it exists and its folder takes a new file.
static func can_install() -> bool:
	var pck := installed_pck()
	if pck.is_empty():
		return false
	var probe := pck.get_base_dir().path_join(".timbum-write-test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


## Fetches the latest manifest and, when it is a usable newer version, downloads its pack.
func check() -> void:
	if status in [Status.OFF, Status.CHECKING, Status.DOWNLOADING, Status.READY]:
		return
	_set_status(Status.CHECKING)
	var manifest_text := await _get_text(_feed + MANIFEST)
	var sig_text := await _get_text(_feed + MANIFEST + ".sig")
	if manifest_text.is_empty() or sig_text.is_empty():
		_set_status(Status.FAILED)
		return
	if not DevTag.signed_by_owner((MANIFEST_PREFIX + manifest_text).to_utf8_buffer(), sig_text):
		push_warning("Updater: the update manifest isn't signed by the owner; ignoring it")
		_set_status(Status.FAILED)
		return
	var m: Variant = JSON.parse_string(manifest_text)
	if typeof(m) != TYPE_DICTIONARY or typeof(m.get("version")) != TYPE_STRING:
		_set_status(Status.FAILED)
		return
	var version: String = m.version
	if compare_versions(version, current_version()) <= 0:
		_set_status(Status.UP_TO_DATE)
		return
	new_version = version
	if typeof(m.get("page")) == TYPE_STRING:
		full_url = m.page
	var files: Variant = m.get("files")
	var file: Variant = files.get(platform()) if typeof(files) == TYPE_DICTIONARY else null
	if str(m.get("runtime", "")) != RUNTIME or typeof(file) != TYPE_DICTIONARY or not can_install():
		_set_status(Status.FULL)
		return
	var st := _read_state()
	if st.get("version") == version and FileAccess.file_exists(DIR + str(st.file)):
		_set_status(Status.READY)
		return
	_download(version, file)


## RESTART in the main menu: installs the downloaded update and starts the game again.
func restart_now() -> void:
	if status == Status.READY and _install(true):
		get_tree().quit()


# ---------------------------------------------------------------- install

## Starts the detached helper that, once this process has exited, moves the downloaded pack over
## installed_pck() (macOS: then re-signs the app) and, with `relaunch`, starts the game again.
func _install(relaunch: bool) -> bool:
	if _installing:
		return true
	var st := _read_state()
	var target := installed_pck()
	if st.is_empty() or target.is_empty():
		return false
	var source := ProjectSettings.globalize_path(DIR + str(st.file))
	if not FileAccess.file_exists(source):
		return false
	var pid := OS.get_process_id()
	var exe := OS.get_executable_path()
	var helper := -1
	match platform():
		"macos":
			var app := exe.get_base_dir().get_base_dir().get_base_dir()
			var script := "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; " \
				+ "cp -f \"$2\" \"$3.new\" && mv -f \"$3.new\" \"$3\" && rm -f \"$2\"; " \
				+ "codesign --force --sign - \"$4\" >/dev/null 2>&1; " \
				+ "if [ \"$5\" = 1 ]; then open -n \"$4\"; fi"
			helper = OS.create_process("/bin/sh", ["-c", script, "sh", str(pid), source, target, app, "1" if relaunch else "0"])
		"windows":
			var q := func(s: String) -> String: return "'" + s.replace("'", "''") + "'"
			var ps := "Wait-Process -Id %d -ErrorAction SilentlyContinue; " % pid \
				+ "for ($i = 0; $i -lt 50; $i++) { try { Move-Item -LiteralPath %s -Destination %s -Force -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 200 } }; " % [q.call(source), q.call(target)] \
				+ ("Start-Process -FilePath %s" % q.call(exe) if relaunch else "")
			helper = OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", ps])
	if helper <= 0:
		push_warning("Updater: couldn't start the update helper")
		return false
	_installing = true
	print("Updater: installing %s into %s when the game closes" % [st.version, target])
	return true


## At start: drop STATE once the running game is at or past its version (the update went in, or a
## newer full app was installed), and every downloaded pack STATE doesn't name.
func _tidy() -> void:
	var st := _read_state()
	if not st.is_empty() and compare_versions(str(st.version), current_version()) <= 0:
		DirAccess.remove_absolute(DIR + str(st.file))
		DirAccess.remove_absolute(STATE)
		st = {}
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		if f.get_extension() in ["pck", "part"] and f != str(st.get("file", "")):
			DirAccess.remove_absolute(DIR + f)


# ---------------------------------------------------------------- download

func _download(version: String, file: Dictionary) -> void:
	var url := str(file.get("url", ""))
	var sha := str(file.get("sha256", "")).to_lower()
	_download_size = int(file.get("size", 0))
	if url.is_empty() or sha.length() != 64 or _download_size <= 0:
		_set_status(Status.FAILED)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var name := "Timbum-%s-%s.pck" % [version.validate_filename(), platform()]
	var part := DIR + name + ".part"
	progress = 0.0
	_set_status(Status.DOWNLOADING)
	_http.download_file = part
	_http.timeout = 0.0
	_http.body_size_limit = _download_size + 1024
	if _http.request(url) != OK:
		_http.download_file = ""
		_set_status(Status.FAILED)
		return
	var res: Array = await _http.request_completed
	_http.download_file = ""
	_http.body_size_limit = -1
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200 \
			or FileAccess.get_size(part) != _download_size or FileAccess.get_sha256(part) != sha:
		push_warning("Updater: download of %s failed (result %d, HTTP %d)" % [version, res[0], res[1]])
		DirAccess.remove_absolute(part)
		_set_status(Status.FAILED)
		return
	DirAccess.remove_absolute(DIR + name)
	if DirAccess.rename_absolute(part, DIR + name) != OK:
		DirAccess.remove_absolute(part)
		_set_status(Status.FAILED)
		return
	_write_state({"version": version, "file": name})
	print("Updater: downloaded update %s" % version)
	_set_status(Status.READY)


## GET `url` as text ("" on any failure).
func _get_text(url: String) -> String:
	_http.body_size_limit = MAX_MANIFEST_BYTES
	_http.timeout = 30.0
	if _http.request(url) != OK:
		return ""
	var res: Array = await _http.request_completed
	_http.body_size_limit = -1
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return ""
	return (res[3] as PackedByteArray).get_string_from_utf8()


# ---------------------------------------------------------------- state

func _set_status(s: Status) -> void:
	status = s
	status_changed.emit()


func _read_state() -> Dictionary:
	if not FileAccess.file_exists(STATE):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE))
	if typeof(d) != TYPE_DICTIONARY or typeof(d.get("version")) != TYPE_STRING or typeof(d.get("file")) != TYPE_STRING \
			or (d.file as String).get_file() != d.file:
		return {}
	return d


func _write_state(st: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(st))
