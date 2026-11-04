class_name VideoWriter
extends RefCounted
## Writes Motion-JPEG video (plus optional 16-bit stereo PCM audio) straight to a playable file,
## without any external encoder. Two containers, picked from the path's extension:
## - ".mov": QuickTime ('jpeg' Photo-JPEG video, 'sowt' PCM audio), media data streamed into
##   'mdat' and the 'moov' index written at the end. Plays in QuickTime / AVFoundation.
## - ".avi": RIFF AVI ('MJPG' video, PCM audio) with an 'idx1' index (no OpenDML, keep < 1 GB).
## Frames and audio chunks are written to disk as they arrive, in call order (callers interleave
## roughly sample_rate / fps samples after each frame); only the per-chunk size/offset tables
## stay in memory. `close()` writes the index and patches the header sizes.

enum Format { NONE, MOV, AVI }

## Movie timescale of the MOV 'mvhd' / 'tkhd' durations (units per second).
const MOV_TIMESCALE := 1000
## Seconds between 1904-01-01 (QuickTime epoch) and 1970-01-01.
const MOV_EPOCH_OFFSET := 2082844800
const AVIIF_KEYFRAME := 0x10
const AVIF_HASINDEX := 0x10
const AVIF_ISINTERLEAVED := 0x100
const BYTES_PER_AUDIO_FRAME := 4 # 16-bit stereo

## Video frames written so far.
var frames := 0

var _file: FileAccess
var _format := Format.NONE
var _width := 0
var _height := 0
var _fps := 30
var _sample_rate := 0
var _audio_frames := 0
var _created := 0
## MOV: file position of the 'mdat' size field. AVI: file position of the 'movi' fourcc.
var _data_start := 0
var _max_video := 0
var _max_audio := 0
## Per chunk, in file order: data offset (MOV) or chunk header offset (AVI), payload size, and
## 1 for audio / 0 for video.
var _chunk_offsets := PackedInt64Array()
var _chunk_sizes := PackedInt32Array()
var _chunk_audio := PackedByteArray()


## The container the current platform plays natively: "mov" on macOS, "avi" elsewhere.
static func native_extension() -> String:
	return "mov" if OS.get_name() == "macOS" else "avi"


## Creates the file at the absolute OS `path` (".mov" or ".avi") and writes the header.
## `sample_rate` 0 makes a video-only file; otherwise a 16-bit stereo PCM track is added.
func open(path: String, width: int, height: int, fps: int, sample_rate := 0) -> Error:
	if _file:
		return ERR_ALREADY_IN_USE
	var format := Format.NONE
	match path.get_extension().to_lower():
		"mov":
			format = Format.MOV
		"avi":
			format = Format.AVI
	if format == Format.NONE or width <= 0 or height <= 0 or fps <= 0:
		return ERR_INVALID_PARAMETER
	# The MOV sound description stores the rate as unsigned 16.16 fixed point.
	if sample_rate < 0 or sample_rate > 65535:
		return ERR_INVALID_PARAMETER
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	_file = file
	_format = format
	_width = width
	_height = height
	_fps = fps
	_sample_rate = sample_rate
	_audio_frames = 0
	_max_video = 0
	_max_audio = 0
	_created = int(Time.get_unix_time_from_system()) + MOV_EPOCH_OFFSET
	_chunk_offsets.clear()
	_chunk_sizes.clear()
	_chunk_audio.clear()
	frames = 0
	if format == Format.MOV:
		_file.big_endian = true
		var ftyp := _be()
		ftyp.put_data("qt  ".to_ascii_buffer())
		ftyp.put_u32(0x20050300)
		ftyp.put_data("qt  ".to_ascii_buffer())
		_file.store_buffer(_atom("ftyp", ftyp.data_array))
		_data_start = _file.get_position()
		_file.store_32(8) # 'mdat' size, patched in close()
		_file.store_buffer("mdat".to_ascii_buffer())
	else:
		_file.big_endian = false
		var header := _avi_header(0, 0)
		_file.store_buffer(header)
		_data_start = header.size() - 4
	return _file.get_error()


## Appends one Motion-JPEG frame (baseline JPEG bytes, e.g. from Image.save_jpg_to_buffer).
func add_frame(jpeg: PackedByteArray) -> void:
	if not _file:
		return
	_write_chunk(jpeg, false)
	_max_video = maxi(_max_video, jpeg.size())
	frames += 1


## Appends stereo float samples (-1..1) to the audio track as 16-bit PCM. Ignored for
## video-only files.
func add_audio(samples: PackedVector2Array) -> void:
	if not _file or _sample_rate == 0 or samples.is_empty():
		return
	var count := samples.size()
	var pcm := PackedByteArray()
	pcm.resize(count * BYTES_PER_AUDIO_FRAME)
	for i in count:
		var s: Vector2 = samples[i]
		pcm.encode_s16(i * 4, int(clampf(s.x, -1.0, 1.0) * 32767.0))
		pcm.encode_s16(i * 4 + 2, int(clampf(s.y, -1.0, 1.0) * 32767.0))
	_write_chunk(pcm, true)
	_max_audio = maxi(_max_audio, pcm.size())
	_audio_frames += count


## Writes the index, patches the header sizes and closes the file.
func close() -> Error:
	if not _file:
		return ERR_FILE_CANT_WRITE
	var end := _file.get_position()
	var err := OK
	if _format == Format.MOV:
		if end > 0xFFFFFFFF:
			err = ERR_FILE_CANT_WRITE # stco offsets and the 'mdat' size are 32-bit
		_file.seek(_data_start)
		_file.store_32(end - _data_start)
		_file.seek(end)
		_file.store_buffer(_mov_moov())
	else:
		_file.store_buffer(_avi_index())
		var file_end := _file.get_position()
		if file_end > 0xFFFFFFFF:
			err = ERR_FILE_CANT_WRITE
		_file.seek(0)
		_file.store_buffer(_avi_header(file_end - 8, end - _data_start))
		_file.seek(file_end)
	if err == OK:
		err = _file.get_error()
	_file.close()
	_file = null
	_format = Format.NONE
	_chunk_offsets.clear()
	_chunk_sizes.clear()
	_chunk_audio.clear()
	return err


func _write_chunk(data: PackedByteArray, audio: bool) -> void:
	var pos := _file.get_position()
	if _format == Format.AVI:
		_file.store_buffer(("01wb" if audio else "00dc").to_ascii_buffer())
		_file.store_32(data.size())
		_file.store_buffer(data)
		if data.size() % 2 == 1:
			_file.store_8(0)
	else:
		_file.store_buffer(data)
	_chunk_offsets.append(pos)
	_chunk_sizes.append(data.size())
	_chunk_audio.append(1 if audio else 0)


# --- MOV ---------------------------------------------------------------------------------------


static func _be() -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	return b


static func _atom(type: String, payload: PackedByteArray) -> PackedByteArray:
	var b := _be()
	b.put_u32(payload.size() + 8)
	b.put_data(type.to_ascii_buffer())
	b.put_data(payload)
	return b.data_array


## Atom whose payload is the concatenation of `children`.
static func _container_atom(type: String, children: Array[PackedByteArray]) -> PackedByteArray:
	var payload := PackedByteArray()
	for child in children:
		payload.append_array(child)
	return _atom(type, payload)


static func _put_matrix(b: StreamPeerBuffer) -> void:
	for v: int in [0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000]:
		b.put_u32(v)


## Duration of `units` media units at `timescale` in the movie timescale.
static func _movie_duration(units: int, timescale: int) -> int:
	return roundi(float(units) * MOV_TIMESCALE / float(timescale))


func _mov_moov() -> PackedByteArray:
	var video_duration := _movie_duration(frames, _fps)
	var audio_duration := _movie_duration(_audio_frames, _sample_rate) if _sample_rate > 0 else 0
	var mvhd := _be()
	mvhd.put_u32(0) # version + flags
	mvhd.put_u32(_created)
	mvhd.put_u32(_created)
	mvhd.put_u32(MOV_TIMESCALE)
	mvhd.put_u32(maxi(video_duration, audio_duration))
	mvhd.put_u32(0x10000) # preferred rate 1.0
	mvhd.put_u16(0x100) # preferred volume 1.0
	mvhd.put_data(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	_put_matrix(mvhd)
	for i in 6: # preview time/duration, poster time, selection time/duration, current time
		mvhd.put_u32(0)
	mvhd.put_u32(3 if _sample_rate > 0 else 2) # next track ID
	var children: Array[PackedByteArray] = [_atom("mvhd", mvhd.data_array), _mov_video_trak(video_duration)]
	if _sample_rate > 0:
		children.append(_mov_audio_trak(audio_duration))
	return _container_atom("moov", children)


func _mov_tkhd(track_id: int, duration: int, audio: bool) -> PackedByteArray:
	var b := _be()
	b.put_u32(0xF) # version 0, flags: enabled | in movie | in preview | in poster
	b.put_u32(_created)
	b.put_u32(_created)
	b.put_u32(track_id)
	b.put_u32(0)
	b.put_u32(duration)
	b.put_u32(0)
	b.put_u32(0)
	b.put_u16(0) # layer
	b.put_u16(0) # alternate group
	b.put_u16(0x100 if audio else 0) # volume
	b.put_u16(0)
	_put_matrix(b)
	b.put_u32(0 if audio else _width << 16)
	b.put_u32(0 if audio else _height << 16)
	return _atom("tkhd", b.data_array)


func _mov_mdhd(timescale: int, duration: int) -> PackedByteArray:
	var b := _be()
	b.put_u32(0)
	b.put_u32(_created)
	b.put_u32(_created)
	b.put_u32(timescale)
	b.put_u32(duration)
	b.put_u16(0) # language (English)
	b.put_u16(0) # quality
	return _atom("mdhd", b.data_array)


static func _mov_hdlr(component: String, subtype: String, name: String) -> PackedByteArray:
	var b := _be()
	b.put_u32(0)
	b.put_data(component.to_ascii_buffer())
	b.put_data(subtype.to_ascii_buffer())
	b.put_data("appl".to_ascii_buffer())
	b.put_u32(0)
	b.put_u32(0)
	b.put_u8(name.length())
	b.put_data(name.to_ascii_buffer())
	return _atom("hdlr", b.data_array)


static func _mov_dinf() -> PackedByteArray:
	var alis := _be()
	alis.put_u32(1) # flags: media data is in this file
	var dref := _be()
	dref.put_u32(0)
	dref.put_u32(1)
	dref.put_data(_atom("alis", alis.data_array))
	return _atom("dinf", _atom("dref", dref.data_array))


## stts with every sample lasting one media unit.
static func _mov_stts(count: int) -> PackedByteArray:
	var b := _be()
	b.put_u32(0)
	if count > 0:
		b.put_u32(1)
		b.put_u32(count)
		b.put_u32(1)
	else:
		b.put_u32(0)
	return _atom("stts", b.data_array)


static func _mov_stsd(entry: PackedByteArray) -> PackedByteArray:
	var b := _be()
	b.put_u32(0)
	b.put_u32(1)
	b.put_data(entry)
	return _atom("stsd", b.data_array)


## Chunk offset table (stco) for the chunks of one track.
func _mov_stco(audio: bool) -> PackedByteArray:
	var flag := 1 if audio else 0
	var b := _be()
	b.put_u32(0)
	var count_pos := b.get_position()
	b.put_u32(0)
	var count := 0
	for i in _chunk_offsets.size():
		if _chunk_audio[i] == flag:
			b.put_u32(_chunk_offsets[i])
			count += 1
	b.seek(count_pos)
	b.put_u32(count)
	return _atom("stco", b.data_array)


func _mov_video_trak(duration: int) -> PackedByteArray:
	var entry := _be()
	entry.put_u32(86)
	entry.put_data("jpeg".to_ascii_buffer())
	entry.put_data(PackedByteArray([0, 0, 0, 0, 0, 0]))
	entry.put_u16(1) # data reference index
	entry.put_u16(0) # version
	entry.put_u16(0) # revision
	entry.put_data("appl".to_ascii_buffer())
	entry.put_u32(0) # temporal quality
	entry.put_u32(0x200) # spatial quality: codecNormalQuality
	entry.put_u16(_width)
	entry.put_u16(_height)
	entry.put_u32(72 << 16)
	entry.put_u32(72 << 16)
	entry.put_u32(0) # data size
	entry.put_u16(1) # frames per sample
	var compressor := PackedByteArray()
	compressor.resize(32)
	var label := "Photo - JPEG".to_ascii_buffer()
	compressor[0] = label.size()
	for i in label.size():
		compressor[i + 1] = label[i]
	entry.put_data(compressor)
	entry.put_u16(24) # depth
	entry.put_u16(0xFFFF) # color table ID: none

	var stsc := _be()
	stsc.put_u32(0)
	stsc.put_u32(1)
	stsc.put_u32(1) # first chunk
	stsc.put_u32(1) # samples per chunk
	stsc.put_u32(1) # sample description

	var stsz := _be()
	stsz.put_u32(0)
	stsz.put_u32(0) # sizes differ: table follows
	stsz.put_u32(frames)
	for i in _chunk_sizes.size():
		if _chunk_audio[i] == 0:
			stsz.put_u32(_chunk_sizes[i])

	var stbl: Array[PackedByteArray] = [
		_mov_stsd(entry.data_array), _mov_stts(frames), _atom("stsc", stsc.data_array),
		_atom("stsz", stsz.data_array), _mov_stco(false),
	]
	var vmhd := _be()
	vmhd.put_u32(1) # flags: no lean ahead
	vmhd.put_u16(0x40) # graphics mode: copy
	vmhd.put_u16(0x8000)
	vmhd.put_u16(0x8000)
	vmhd.put_u16(0x8000)
	var media_info: Array[PackedByteArray] = [
		_atom("vmhd", vmhd.data_array), _mov_hdlr("dhlr", "alis", "DataHandler"), _mov_dinf(),
		_container_atom("stbl", stbl),
	]
	var mdia: Array[PackedByteArray] = [
		_mov_mdhd(_fps, frames), _mov_hdlr("mhlr", "vide", "VideoHandler"),
		_container_atom("minf", media_info),
	]
	var trak: Array[PackedByteArray] = [_mov_tkhd(1, duration, false), _container_atom("mdia", mdia)]
	return _container_atom("trak", trak)


func _mov_audio_trak(duration: int) -> PackedByteArray:
	var entry := _be()
	entry.put_u32(36)
	entry.put_data("sowt".to_ascii_buffer()) # 16-bit little-endian signed PCM
	entry.put_data(PackedByteArray([0, 0, 0, 0, 0, 0]))
	entry.put_u16(1) # data reference index
	entry.put_u16(0) # version
	entry.put_u16(0) # revision
	entry.put_u32(0) # vendor
	entry.put_u16(2) # channels
	entry.put_u16(16) # sample size
	entry.put_u16(0) # compression ID
	entry.put_u16(0) # packet size
	entry.put_u32(_sample_rate << 16)

	# One stsc entry per run of chunks holding the same number of samples.
	var stsc := _be()
	stsc.put_u32(0)
	stsc.put_u32(0)
	var runs := 0
	var chunk := 0
	var last := -1
	for i in _chunk_sizes.size():
		if _chunk_audio[i] == 0:
			continue
		chunk += 1
		var count := _chunk_sizes[i] >> 2 # bytes / BYTES_PER_AUDIO_FRAME
		if count != last:
			stsc.put_u32(chunk)
			stsc.put_u32(count)
			stsc.put_u32(1)
			runs += 1
			last = count
	stsc.seek(4)
	stsc.put_u32(runs)

	var stsz := _be()
	stsz.put_u32(0)
	stsz.put_u32(BYTES_PER_AUDIO_FRAME) # every sample (stereo frame) is the same size
	stsz.put_u32(_audio_frames)

	var stbl: Array[PackedByteArray] = [
		_mov_stsd(entry.data_array), _mov_stts(_audio_frames), _atom("stsc", stsc.data_array),
		_atom("stsz", stsz.data_array), _mov_stco(true),
	]
	var smhd := _be()
	smhd.put_u32(0)
	smhd.put_u16(0) # balance
	smhd.put_u16(0)
	var media_info: Array[PackedByteArray] = [
		_atom("smhd", smhd.data_array), _mov_hdlr("dhlr", "alis", "DataHandler"), _mov_dinf(),
		_container_atom("stbl", stbl),
	]
	var mdia: Array[PackedByteArray] = [
		_mov_mdhd(_sample_rate, _audio_frames), _mov_hdlr("mhlr", "soun", "SoundHandler"),
		_container_atom("minf", media_info),
	]
	var trak: Array[PackedByteArray] = [_mov_tkhd(2, duration, true), _container_atom("mdia", mdia)]
	return _container_atom("trak", trak)


# --- AVI ---------------------------------------------------------------------------------------


static func _riff_chunk(id: String, payload: PackedByteArray) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_data(id.to_ascii_buffer())
	b.put_u32(payload.size())
	b.put_data(payload)
	if payload.size() % 2 == 1:
		b.put_u8(0)
	return b.data_array


static func _riff_list(type: String, children: Array[PackedByteArray]) -> PackedByteArray:
	var payload := type.to_ascii_buffer()
	for child in children:
		payload.append_array(child)
	return _riff_chunk("LIST", payload)


static func _avi_strh(type: String, handler: String, scale: int, rate: int, length: int,
		buffer_size: int, sample_size: int, width: int, height: int) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_data(type.to_ascii_buffer())
	if handler.is_empty():
		b.put_u32(0)
	else:
		b.put_data(handler.to_ascii_buffer())
	b.put_u32(0) # flags
	b.put_u16(0) # priority
	b.put_u16(0) # language
	b.put_u32(0) # initial frames
	b.put_u32(scale)
	b.put_u32(rate)
	b.put_u32(0) # start
	b.put_u32(length)
	b.put_u32(buffer_size)
	b.put_u32(0xFFFFFFFF) # quality: default
	b.put_u32(sample_size)
	b.put_u16(0)
	b.put_u16(0)
	b.put_u16(width)
	b.put_u16(height)
	return _riff_chunk("strh", b.data_array)


## Everything up to and including the 'movi' fourcc. Same size whatever the values, so close()
## rewrites it in place with the final counts and sizes.
func _avi_header(riff_size: int, movi_size: int) -> PackedByteArray:
	var streams := 2 if _sample_rate > 0 else 1
	var avih := StreamPeerBuffer.new()
	avih.put_u32(roundi(1000000.0 / _fps)) # microseconds per frame
	avih.put_u32(_max_video * _fps + _sample_rate * BYTES_PER_AUDIO_FRAME) # max bytes per second
	avih.put_u32(0) # padding granularity
	avih.put_u32(AVIF_HASINDEX | (AVIF_ISINTERLEAVED if streams > 1 else 0))
	avih.put_u32(frames)
	avih.put_u32(0) # initial frames
	avih.put_u32(streams)
	avih.put_u32(maxi(_max_video, _max_audio) + 8) # suggested buffer size
	avih.put_u32(_width)
	avih.put_u32(_height)
	for i in 4:
		avih.put_u32(0)

	var bih := StreamPeerBuffer.new() # BITMAPINFOHEADER
	bih.put_u32(40)
	bih.put_32(_width)
	bih.put_32(_height)
	bih.put_u16(1) # planes
	bih.put_u16(24) # bit count
	bih.put_data("MJPG".to_ascii_buffer())
	bih.put_u32(_width * _height * 3)
	bih.put_32(0)
	bih.put_32(0)
	bih.put_u32(0)
	bih.put_u32(0)
	var video_strl: Array[PackedByteArray] = [
		_avi_strh("vids", "MJPG", 1, _fps, frames, _max_video, 0, _width, _height),
		_riff_chunk("strf", bih.data_array),
	]
	var hdrl: Array[PackedByteArray] = [
		_riff_chunk("avih", avih.data_array), _riff_list("strl", video_strl),
	]
	if _sample_rate > 0:
		var wfx := StreamPeerBuffer.new() # WAVEFORMATEX
		wfx.put_u16(1) # WAVE_FORMAT_PCM
		wfx.put_u16(2)
		wfx.put_u32(_sample_rate)
		wfx.put_u32(_sample_rate * BYTES_PER_AUDIO_FRAME)
		wfx.put_u16(BYTES_PER_AUDIO_FRAME) # block align
		wfx.put_u16(16)
		wfx.put_u16(0) # extra size
		var audio_strl: Array[PackedByteArray] = [
			_avi_strh("auds", "", 1, _sample_rate, _audio_frames,
					_max_audio, BYTES_PER_AUDIO_FRAME, 0, 0),
			_riff_chunk("strf", wfx.data_array),
		]
		hdrl.append(_riff_list("strl", audio_strl))

	var b := StreamPeerBuffer.new()
	b.put_data("RIFF".to_ascii_buffer())
	b.put_u32(riff_size)
	b.put_data("AVI ".to_ascii_buffer())
	b.put_data(_riff_list("hdrl", hdrl))
	b.put_data("LIST".to_ascii_buffer())
	b.put_u32(movi_size)
	b.put_data("movi".to_ascii_buffer())
	return b.data_array


## The 'idx1' chunk; offsets are relative to the 'movi' fourcc.
func _avi_index() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	var count := _chunk_offsets.size()
	b.put_data("idx1".to_ascii_buffer())
	b.put_u32(count * 16)
	for i in count:
		b.put_data(("01wb" if _chunk_audio[i] == 1 else "00dc").to_ascii_buffer())
		b.put_u32(AVIIF_KEYFRAME)
		b.put_u32(_chunk_offsets[i] - _data_start)
		b.put_u32(_chunk_sizes[i])
	return b.data_array
