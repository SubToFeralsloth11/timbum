extends Node
## Audio: sound effects from WAV files (pooled flat + positional voices) and music with
## crossfades. Every effect take (`audio/sfx/<name>.wav`, or `<name>_<take>.wav` for the sounds
## in VARIANTS) is loaded when the autoload starts. The menu, shop and match music are songs
## (`MUSIC_FILES`, MP3s that loop); the short results fanfare is a procedural chiptune rendered on
## a WorkerThreadPool task (AudioJob) whose result is polled in _process.
## Headless runs (dedicated servers, tests) skip all audio work: every call is a no-op.

const FLAT_VOICES := 12
const POSITIONAL_VOICES := 32
const CROSSFADE := 0.6
const PITCH_JITTER := 0.04
const MAX_DISTANCE := 90.0
const MUSIC_TRACKS: Array[StringName] = [&"menu", &"shop", &"match", &"results"]
const MENU_SONG := "res://audio/music/menu_blocksmith_daydream.mp3"
const SHOP_SONG := "res://audio/music/shop_coin_shop_spark.mp3"
const MATCH_SONGS: Array[String] = ["res://audio/music/match_arena_rush.mp3",
	"res://audio/music/match_combat_groove.mp3", "res://audio/music/match_arcade_arena.mp3"]
## Song tracks: the song each starts with ("" = any from its playlist) and the playlist that
## follows, song to song, for as long as the track stays on. Menu and shop run through all five
## songs; matches through the three match songs.
const MUSIC_FILES := {
	&"menu": {"first": MENU_SONG, "playlist": [MENU_SONG, SHOP_SONG] + MATCH_SONGS},
	&"shop": {"first": SHOP_SONG, "playlist": [MENU_SONG, SHOP_SONG] + MATCH_SONGS},
	&"match": {"first": "", "playlist": MATCH_SONGS},
}
const SFX_DIR := "res://audio/sfx/"

## Every sound name in the Sfx contract (cheap UI sounds first).
const NAMES: Array[StringName] = [
	&"ui_hover", &"ui_click", &"ui_buy", &"ui_error", &"hit_marker", &"headshot", &"kill_confirm",
	&"countdown", &"coins", &"level_up", &"match_start", &"match_end", &"spawn",
	&"footstep", &"jump", &"land", &"hurt", &"death", &"weapon_switch", &"reload", &"dry_fire",
	&"knife_swing", &"knife_hit", &"pickup_health", &"pickup_ammo", &"grenade_throw", &"grenade_bounce",
	&"bullet_impact", &"whizz", &"shot_pistol", &"shot_revolver", &"shot_smg", &"shot_rifle",
	&"shot_shotgun", &"shot_sniper", &"shot_lmg", &"shot_rocket", &"explosion",
	&"shot_suppressed", &"shot_dmr", &"slide", &"grapple_fire", &"smoke_pop", &"flashbang",
	&"streak_reward", &"radar_sweep", &"shield_hit", &"shield_break", &"bomber_warning",
	&"ping", &"ping_enemy", &"spray", &"jump_pad", &"pickup_grenade",
	&"shot_crossbow", &"shot_drum_shotgun", &"shot_carbine", &"shot_burst_smg", &"shot_minigun",
	&"swing_blunt", &"swing_heavy", &"swing_blade",
]

## Sounds with several takes; one is picked at random per play.
const VARIANTS := {&"footstep": 4, &"bullet_impact": 3, &"knife_hit": 2, &"grenade_bounce": 2}

## Sounds without a file of their own: they play another sound's takes at a fixed pitch factor.
## `pickup_grenade` = the frag's metal clink (`grenade_bounce`) a major third higher (x1.25), so a
## grenade pickup is told apart from the ammo-box `pickup_ammo`.
const ALIASES := {&"pickup_grenade": {"sound": &"grenade_bounce", "pitch": 1.25}}

## Default playback gain (dB) that keeps the files at sensible relative levels. Each file was
## loudness-matched against the earlier synthesised sound (see sfx_pack/README.md).
const GAIN_DB := {
	&"ui_hover": -14.0, &"ui_click": -10.0, &"ui_buy": -3.0, &"ui_error": -8.0, &"hit_marker": -9.0,
	&"headshot": -4.0, &"kill_confirm": -3.0, &"countdown": -8.5, &"coins": -4.0, &"level_up": -8.0,
	&"match_start": -6.0, &"match_end": -6.5, &"spawn": -8.0, &"footstep": -11.5, &"jump": -11.5,
	&"land": -6.5, &"hurt": -4.0, &"death": -5.0, &"weapon_switch": -15.0, &"reload": -8.5,
	&"dry_fire": -10.0, &"knife_swing": -9.0, &"knife_hit": -1.0, &"pickup_health": -5.5,
	&"pickup_ammo": -7.0, &"grenade_throw": -12.5, &"grenade_bounce": -8.0, &"bullet_impact": -8.5,
	&"whizz": -5.5, &"shot_pistol": -1.5, &"shot_revolver": 0.0, &"shot_smg": -4.5,
	&"shot_rifle": -1.5, &"shot_shotgun": -0.5, &"shot_sniper": 0.0, &"shot_lmg": 0.0,
	&"shot_rocket": -5.0, &"explosion": 0.0, &"shot_suppressed": -4.5, &"shot_dmr": 0.0,
	&"slide": -10.0, &"grapple_fire": -10.0, &"smoke_pop": -4.5, &"flashbang": 0.0,
	&"streak_reward": -4.5, &"radar_sweep": -5.0, &"shield_hit": -4.5, &"shield_break": -1.5,
	&"bomber_warning": -5.5, &"ping": -7.5, &"ping_enemy": -8.0, &"spray": -13.0, &"jump_pad": -4.5,
	&"pickup_grenade": -6.0,
	&"shot_crossbow": 0.0, &"shot_drum_shotgun": 0.0, &"shot_carbine": -1.0, &"shot_burst_smg": -4.0,
	&"shot_minigun": 0.0, &"swing_blunt": -10.0, &"swing_heavy": -11.0, &"swing_blade": -8.0,
}

## Reference distance (m) for positional playback: loud sounds carry across a ~60 m map,
## small ones fade within a few metres.
const UNIT_SIZE := {
	&"shot_pistol": 14.0, &"shot_revolver": 16.0, &"shot_smg": 13.0, &"shot_rifle": 15.0,
	&"shot_shotgun": 16.0, &"shot_sniper": 24.0, &"shot_lmg": 16.0, &"shot_rocket": 16.0,
	&"explosion": 26.0, &"footstep": 4.0, &"jump": 4.0, &"land": 5.0, &"bullet_impact": 5.0,
	&"whizz": 3.0, &"grenade_bounce": 6.0, &"reload": 4.0, &"dry_fire": 3.0, &"weapon_switch": 3.0,
	&"shot_suppressed": 5.0, &"shot_dmr": 20.0, &"slide": 5.0, &"grapple_fire": 6.0,
	&"smoke_pop": 10.0, &"flashbang": 24.0, &"shield_hit": 6.0, &"shield_break": 8.0,
	&"bomber_warning": 30.0, &"spray": 4.0, &"jump_pad": 12.0,
	&"shot_crossbow": 20.0, &"shot_drum_shotgun": 18.0, &"shot_carbine": 16.0, &"shot_burst_smg": 14.0, &"shot_minigun": 22.0,
	&"swing_blunt": 4.0, &"swing_heavy": 5.0, &"swing_blade": 4.0,
}
const DEFAULT_UNIT_SIZE := 7.0

## Sounds that are pitch-jittered (±4 %) per play so repeats don't sound mechanical.
## Musical cues (UI, jingles, chimes) keep their exact pitch.
const JITTER := {
	&"footstep": true, &"jump": true, &"land": true, &"hurt": true, &"death": true,
	&"weapon_switch": true, &"reload": true, &"dry_fire": true, &"knife_swing": true, &"knife_hit": true,
	&"pickup_ammo": true, &"grenade_throw": true, &"grenade_bounce": true, &"bullet_impact": true,
	&"whizz": true, &"shot_pistol": true, &"shot_revolver": true, &"shot_smg": true, &"shot_rifle": true,
	&"shot_shotgun": true, &"shot_sniper": true, &"shot_lmg": true, &"shot_rocket": true, &"explosion": true,
	&"shot_suppressed": true, &"shot_dmr": true, &"slide": true, &"grapple_fire": true,
	&"shield_hit": true, &"shot_crossbow": true, &"shot_drum_shotgun": true, &"shot_carbine": true, &"shot_burst_smg": true, &"shot_minigun": true,
	&"swing_blunt": true, &"swing_heavy": true, &"swing_blade": true,
}

var _enabled := false
## name -> Array[AudioStream] (one entry per take).
var _streams := {}
## track -> AudioStreamWAV for procedural tracks, filled when the music worker finishes.
var _music := {}
## Per song track: the shuffled playlist order still to play.
var _song_queue := {}
## The song file playing now (so the next one never repeats it straight away).
var _song_path := ""
var _warned := {}
var _flat: Array[AudioStreamPlayer] = []
var _flat_started := PackedInt64Array()
var _pos: Array[AudioStreamPlayer3D] = []
var _pos_started := PackedInt64Array()
var _music_players: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_track := &""
var _music_tween: Tween
var _job: AudioJob
## Milliseconds the worker spent rendering each procedural music track. Read by tests and
## diagnostics.
var timings := {}


# Setup runs in _init so play_music() calls made by scripts that run before this autoload's
# _ready are remembered, and the fanfare render starts as early as possible.
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
		p.finished.connect(_on_song_finished.bind(p))
		add_child(p)
		_music_players.append(p)
	_load_effects()
	_job = AudioJob.new([&"results"])
	_job.task_id = WorkerThreadPool.add_task(AudioJob.run.bind(_job), true, "Sfx render")


## Loads every take of every effect into `_streams`.
func _load_effects() -> void:
	for sound in NAMES:
		if ALIASES.has(sound):
			continue
		var takes: Array[AudioStream] = []
		var count := int(VARIANTS.get(sound, 1))
		for v in count:
			var path := "%s%s.wav" % [SFX_DIR, sound] if count == 1 else "%s%s_%d.wav" % [SFX_DIR, sound, v]
			var stream := load(path) as AudioStream
			if stream:
				takes.append(stream)
			else:
				push_warning("Sfx: missing sound file '%s'" % path)
		_streams[sound] = takes
	for sound: StringName in ALIASES:
		_streams[sound] = _streams.get(ALIASES[sound].sound, [])


## Cancels the fanfare render. It is only waited on if it already started (it stops within one
## bar): during engine shutdown the pool may never pick up a queued task, and waiting on one
## would hang forever.
func _exit_tree() -> void:
	if _job:
		_job.cancelled = true
		if _job.started:
			WorkerThreadPool.wait_for_task_completion(_job.task_id)
		_job = null


func _process(_delta: float) -> void:
	if not _job:
		set_process(false)
		return
	var res := _job.take()
	timings.merge(res.timings, true)
	for track: StringName in res.music:
		_music[track] = res.music[track]
		if track == _music_track:
			_crossfade_to(res.music[track])
	if res.done:
		WorkerThreadPool.wait_for_task_completion(_job.task_id)
		_job = null
		set_process(false)


## Plays `sound`. `pos` = Vector3 for positional 3D audio, null for a flat (UI) sound.
func play(sound: StringName, pos: Variant = null, volume_db := 0.0, pitch := 1.0) -> void:
	if not _enabled or not is_inside_tree():
		return
	var takes: Array = _streams.get(sound, [])
	if takes.is_empty():
		if not _warned.has(sound):
			_warned[sound] = true
			push_warning("Sfx: unknown sound '%s'" % sound)
		return
	var stream: AudioStream = takes[randi() % takes.size()]
	var vol := volume_db + float(GAIN_DB.get(sound, 0.0))
	if ALIASES.has(sound):
		pitch *= float(ALIASES[sound].pitch)
	if JITTER.has(sound):
		pitch *= randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	if pos is Vector3:
		var i := _pick_voice(_pos, _pos_started)
		var p := _pos[i]
		p.stream = stream
		p.unit_size = float(UNIT_SIZE.get(sound, DEFAULT_UNIT_SIZE))
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
## then play their playlist song to song; a procedural track still being rendered starts as soon
## as it is ready.
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
		var first: String = MUSIC_FILES[track].first
		_crossfade_to(_song(first if first != "" else _next_song_path(track)))
	elif _music.has(track):
		_crossfade_to(_music[track])


## The active song ended: the next one of the track's playlist follows.
func _on_song_finished(player: AudioStreamPlayer) -> void:
	if player == _music_players[_music_active] and MUSIC_FILES.has(_music_track):
		_crossfade_to(_song(_next_song_path(_music_track)))


## The next song of `track`'s shuffled playlist, never the one that just played.
func _next_song_path(track: StringName) -> String:
	var queue: Array = _song_queue.get(track, [])
	if queue.is_empty() or (queue.size() == 1 and queue[0] == _song_path):
		queue = (MUSIC_FILES[track].playlist as Array).duplicate()
		queue.shuffle()
		if queue.size() > 1 and queue[0] == _song_path:
			queue.push_back(queue.pop_front())
		_song_queue[track] = queue
	var path: String = queue.pop_front()
	if path == _song_path and not queue.is_empty():
		queue.push_back(path)
		path = queue.pop_front()
	return path


## Loads a song; it plays once (the playlist moves on when it ends).
func _song(path: String) -> AudioStream:
	_song_path = path
	var stream := load(path) as AudioStreamMP3
	stream.loop = false
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
