class_name AudioJob
extends RefCounted
## One background render (the effect bank and/or music tracks) run on the WorkerThreadPool.
## The task callable is the static `run` with the job bound as an argument, so the worker
## never touches the Sfx node (which may be freed while a render is in flight). Results are
## handed over through `take()`, polled by the main thread; `cancelled` makes the worker
## stop within one sound or one bar of music.

var sfx := false
var music: Array[StringName] = []
var task_id := -1
var cancelled := false
var started := false
var done := false
var _mutex := Mutex.new()
var _sfx := {}
var _music := {}
var _timings := {}


func _init(render_sfx: bool, tracks: Array[StringName]) -> void:
	sfx = render_sfx
	music = tracks


static func run(job: AudioJob) -> void:
	job.started = true
	if job.sfx:
		var t := Time.get_ticks_usec()
		for sound in SfxBank.NAMES:
			if job.cancelled:
				break
			var takes := SfxBank.render(sound)
			job._mutex.lock()
			job._sfx[sound] = takes
			job._mutex.unlock()
		job._put_timing("sfx", t)
	for track in job.music:
		if job.cancelled:
			break
		var t := Time.get_ticks_usec()
		var stream := Chiptune.render(track, job)
		if stream:
			job._mutex.lock()
			job._music[track] = stream
			job._mutex.unlock()
			job._put_timing(String(track), t)
	job._mutex.lock()
	job.done = true
	job._mutex.unlock()


## Returns and clears finished results: `{sfx: {name: takes}, music: {track: stream},
## timings: {key: ms}, done: bool}`.
func take() -> Dictionary:
	_mutex.lock()
	var out := {"sfx": _sfx, "music": _music, "timings": _timings, "done": done}
	_sfx = {}
	_music = {}
	_timings = {}
	_mutex.unlock()
	return out


func _put_timing(key: String, start_usec: int) -> void:
	_mutex.lock()
	_timings[key] = (Time.get_ticks_usec() - start_usec) / 1000.0
	_mutex.unlock()
