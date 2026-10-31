extends Node
## Audio: synthesised sound effects (pooled flat + positional voices) and music with
## crossfades. The menu, shop and match music are songs (`MUSIC_FILES`, MP3s that loop); the
## short results fanfare is a procedural chiptune. All synthesis runs on WorkerThreadPool tasks
## (AudioJob) whose results are polled in _process; a sound requested before its worker result
## arrives is rendered on the spot (a few ms).
## Headless runs (dedicated servers, tests) skip all audio work: every call is a no-op.

const FLAT_VOICES := 12
const POSITIONAL_VOICES := 32
const CROSSFADE := 0.6
const PITCH_JITTER := 0.04
const MAX_DISTANCE := 90.0
const MUSIC_TRACKS: Array[StringName] = [&"menu", &"shop", &"match", &"results"]
## Song files per track. A track with several songs plays a different one each time it starts
## (each match gets the next song of a shuffled cycle).
const MUSIC_FILES := {
	&"menu": ["res://audio/music/menu_blocksmith_daydream.mp3"],
	&"shop": ["res://audio/music/shop_coin_shop_spark.mp3"],
	&"match": ["res://audio/music/match_arena_rush.mp3", "res://audio/music/match_combat_groove.mp3",
		"res://audio/music/match_arcade_arena.mp3"],
}

var _enabled := false
## name -> Array[AudioStreamWAV] (one entry per take).
var _streams := {}
## track -> AudioStreamWAV for procedural tracks, filled as music workers finish.
var _music := {}
## Song cycle for tracks with several files: the order still to play.
var _song_queue := {}
var _warned := {}
var _flat: Array[AudioStreamPlayer] = []
var _flat_started := PackedInt64Array()
var _pos: Array[AudioStreamPlayer3D] = []
var _pos_started := PackedInt64Array()
var _music_players: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_track := &""
var _music_tween: Tween
var _jobs: Array[AudioJob] = []
## Milliseconds spent synthesising, keyed "sfx" / track name (worker time) and "sfx_main"
## (main-thread on-demand renders). Read by tests and diagnostics.
var timings := {"sfx_main": 0.0}


# Setup runs in _init so play_music() calls made by scripts that run before this autoload's
# _ready are remembered, and rendering starts as early as possible.
func _init() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in FLAT_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_flat.append(p)
	_flat_started.resize(FLAT_VOICES)
	for i in POSITIONAL_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		p.max_distance = MAX_DISTANCE
		p.max_db = 3.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.attenuation_filter_cutoff_hz = 9000.0
		p.attenuation_filter_db = -12.0
		# World sounds stop with a frozen (paused) offline match and resume with it; the rest of
		# Sfx keeps running so pause-menu clicks and music still play.
		p.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(p)
		_pos.append(p)
	_pos_started.resize(POSITIONAL_VOICES)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_linear = 0.0
		add_child(p)
		_music_players.append(p)
	# Two parallel jobs: the results fanfare alone, and the effects bank.
	_start_job(AudioJob.new(false, [&"results"]))
	_start_job(AudioJob.new(true, [] as Array[StringName]))


func _start_job(job: AudioJob) -> void:
	job.task_id = WorkerThreadPool.add_task(AudioJob.run.bind(job), true, "Sfx render")
	_jobs.append(job)


## Cancels in-flight renders. Only jobs that already started are waited on (they stop within
## one sound or bar): during engine shutdown the pool may never pick up a queued task, and
## waiting on one would hang forever.
func _exit_tree() -> void:
	for job in _jobs:
		job.cancelled = true
	for job in _jobs:
		if job.started:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
	_jobs.clear()


func _process(_delta: float) -> void:
	for i in range(_jobs.size() - 1, -1, -1):
		var job := _jobs[i]
		var res := job.take()
		timings.merge(res.timings, true)
		for sound: StringName in res.sfx:
			if not _streams.has(sound):
				_streams[sound] = res.sfx[sound]
		for track: StringName in res.music:
			_music[track] = res.music[track]
			if track == _music_track:
				_crossfade_to(res.music[track])
		if res.done:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			_jobs.remove_at(i)
	if _jobs.is_empty():
		set_process(false)


## Plays `sound`. `pos` = Vector3 for positional 3D audio, null for a flat (UI) sound.
func play(sound: StringName, pos: Variant = null, volume_db := 0.0, pitch := 1.0) -> void:
	if not _enabled or not is_inside_tree():
		return
	var takes: Array = _streams.get(sound, [])
	if takes.is_empty():
		takes = _render_now(sound)
		if takes.is_empty():
			return
	var stream: AudioStreamWAV = takes[randi() % takes.size()]
	var vol := volume_db + float(SfxBank.GAIN_DB.get(sound, 0.0))
	if SfxBank.JITTER.has(sound):
		pitch *= randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	if pos is Vector3:
		var i := _pick_voice(_pos, _pos_started)
		var p := _pos[i]
		p.stream = stream
		p.unit_size = float(SfxBank.UNIT_SIZE.get(sound, SfxBank.DEFAULT_UNIT_SIZE))
		p.volume_db = vol
		p.pitch_scale = pitch
		p.global_position = pos
		p.play()
	else:
		var i := _pick_voice(_flat, _flat_started)
		var p := _flat[i]
		p.stream = stream
		p.volume_db = vol
		p.pitch_scale = pitch
		p.play()


## Crossfades to `track` (&"menu", &"shop", &"match", &"results"). Song tracks start at once and
## loop; a procedural track still being rendered starts as soon as it is ready.
func play_music(track: StringName) -> void:
	if not _enabled:
		return
	if not MUSIC_TRACKS.has(track):
		push_warning("Sfx: unknown music track '%s'" % track)
		return
	if track == _music_track:
		return
	_music_track = track
	if MUSIC_FILES.has(track):
		_crossfade_to(_next_song(track))
	elif _music.has(track):
		_crossfade_to(_music[track])


## The next song of `track`'s shuffled cycle, loaded and set to loop.
func _next_song(track: StringName) -> AudioStream:
	var queue: Array = _song_queue.get(track, [])
	if queue.is_empty():
		queue = (MUSIC_FILES[track] as Array).duplicate()
		queue.shuffle()
		_song_queue[track] = queue
	var stream := load(queue.pop_front()) as AudioStreamMP3
	stream.loop = true
	return stream


func stop_music() -> void:
	if not _enabled:
		return
	_music_track = &""
	_crossfade_to(null)


func _crossfade_to(stream: AudioStream) -> void:
	if _music_tween:
		_music_tween.kill()
	var old := _music_players[_music_active]
	var other := _music_players[1 - _music_active]
	_music_tween = create_tween().set_parallel()
	_music_tween.tween_property(old, ^"volume_linear", 0.0, CROSSFADE)
	if stream:
		# The incoming player may still be fading out from an interrupted switch.
		other.stop()
		other.stream = stream
		other.volume_linear = 0.0
		other.play()
		_music_tween.tween_property(other, ^"volume_linear", 1.0, CROSSFADE)
		_music_active = 1 - _music_active
		_music_tween.chain().tween_callback(old.stop)
	else:
		_music_tween.tween_property(other, ^"volume_linear", 0.0, CROSSFADE)
		_music_tween.chain().tween_callback(old.stop)
		_music_tween.tween_callback(other.stop)


## Returns a free voice, or steals the one that started longest ago.
func _pick_voice(pool: Array, started: PackedInt64Array) -> int:
	var oldest := 0
	for i in pool.size():
		if not pool[i].playing:
			oldest = i
			break
		if started[i] < started[oldest]:
			oldest = i
	started[oldest] = Time.get_ticks_usec()
	return oldest


func _render_now(sound: StringName) -> Array:
	var t := Time.get_ticks_usec()
	var takes := SfxBank.render(sound)
	if takes.is_empty():
		if not _warned.has(sound):
			_warned[sound] = true
			push_warning("Sfx: unknown sound '%s'" % sound)
		return takes
	timings.sfx_main += (Time.get_ticks_usec() - t) / 1000.0
	_streams[sound] = takes
	return takes
