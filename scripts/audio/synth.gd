class_name Synth
extends RefCounted
## Minimal offline DSP toolkit used to synthesise every sound in the game.
## Buffers are mono PackedFloat32Array at RATE Hz; helpers mix into them in place.
## Thread-safe: no shared state, so it may run on WorkerThreadPool tasks.

const RATE := 22050
const INV_RATE := 1.0 / RATE

enum Wave { SINE, SQUARE, TRIANGLE, SAW }

## Returns a silent buffer `seconds` long.
static func make(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(int(seconds * RATE), 1))
	b.fill(0.0)
	return b


## Mixes an oscillator into `b`. Pitch glides exponentially from `f0` to `f1` over `dur`.
## Envelope: linear attack, then exponential decay with time constant `decay` (0 = sustain),
## and a short linear release at the end so the note never clicks.
## `duty` only applies to SQUARE.
static func tone(b: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, amp: float,
		wave := Wave.SINE, attack := 0.002, decay := 0.0, duty := 0.5) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	if n <= 0:
		return
	var ratio := pow(f1 / f0, 1.0 / n)
	var f := f0
	var phase := 0.0
	var att_n := maxf(attack * RATE, 1.0)
	var rel_n := minf(0.004 * RATE, n * 0.5)
	var k := exp(-INV_RATE / decay) if decay > 0.0 else 1.0
	var env := 1.0
	var dc := 2.0 * duty - 1.0
	for j in n:
		var dt := f * INV_RATE
		var v: float
		if wave == Wave.SINE:
			v = sin(TAU * phase)
		elif wave == Wave.TRIANGLE:
			v = 1.0 - 4.0 * absf(phase - 0.5)
		elif wave == Wave.SQUARE:
			v = (1.0 if phase < duty else -1.0) - dc
			v += blep(phase, dt)
			var p2 := phase - duty
			if p2 < 0.0:
				p2 += 1.0
			v -= blep(p2, dt)
		else:
			v = 2.0 * phase - 1.0 - blep(phase, dt)
		var g := env
		if j < att_n:
			g *= j / att_n
		var left := n - j
		if left < rel_n:
			g *= left / rel_n
		b[i0 + j] += v * g * amp
		env *= k
		phase += dt
		if phase >= 1.0:
			phase -= 1.0
		f *= ratio


## Mixes white noise shaped by two cascaded one-pole low-passes whose cutoff glides from
## `lp0` to `lp1` Hz, an optional one-pole high-pass at `hp` Hz, and the same envelope as tone().
static func noise(b: PackedFloat32Array, rng: RandomNumberGenerator, start: float, dur: float, amp: float,
		lp0: float, lp1: float, hp := 0.0, attack := 0.001, decay := 0.0) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	if n <= 0:
		return
	var fc := lp0
	var ratio := pow(lp1 / lp0, 1.0 / n)
	var a_hp := 1.0 - exp(-TAU * hp * INV_RATE) if hp > 0.0 else 0.0
	var s1 := 0.0
	var s2 := 0.0
	var sh := 0.0
	var att_n := maxf(attack * RATE, 1.0)
	var rel_n := minf(0.004 * RATE, n * 0.5)
	var k := exp(-INV_RATE / decay) if decay > 0.0 else 1.0
	var env := 1.0
	# Two one-poles lose power as the cutoff drops; scaling by 1/sqrt(a) keeps bright and
	# dark noise at comparable loudness so `amp` means roughly the same thing everywhere.
	var w := TAU * INV_RATE
	for j in n:
		var a := minf(fc * w, 1.0)
		s1 += a * (rng.randf_range(-1.0, 1.0) - s1)
		s2 += a * (s1 - s2)
		var v := s2 * 0.5 / sqrt(a)
		if a_hp > 0.0:
			sh += a_hp * (v - sh)
			v -= sh
		var g := env
		if j < att_n:
			g *= j / att_n
		var left := n - j
		if left < rel_n:
			g *= left / rel_n
		b[i0 + j] += v * g * amp
		env *= k
		fc *= ratio


## A tiny metallic click: a band-limited noise tick plus a high sine ping.
static func click(b: PackedFloat32Array, rng: RandomNumberGenerator, start: float, amp: float, ping_hz := 3200.0) -> void:
	noise(b, rng, start, 0.012, amp * 2.2, 9000.0, 5000.0, 1800.0, 0.0003, 0.0025)
	tone(b, start, 0.04, ping_hz, ping_hz * 0.97, amp * 0.35, Wave.SINE, 0.0005, 0.007)


## Bell-like strike: a sine fundamental plus inharmonic partials.
static func bell(b: PackedFloat32Array, start: float, dur: float, freq: float, amp: float, decay: float) -> void:
	tone(b, start, dur, freq, freq, amp, Wave.SINE, 0.001, decay)
	tone(b, start, dur, freq * 2.76, freq * 2.76, amp * 0.35, Wave.SINE, 0.001, decay * 0.45)
	tone(b, start, dur, freq * 5.4, freq * 5.4, amp * 0.12, Wave.SINE, 0.001, decay * 0.2)


## In-place two-pole (cascaded one-pole) low-pass.
static func lowpass(b: PackedFloat32Array, cutoff: float) -> void:
	var a := 1.0 - exp(-TAU * cutoff * INV_RATE)
	var s1 := 0.0
	var s2 := 0.0
	for i in b.size():
		s1 += a * (b[i] - s1)
		s2 += a * (s1 - s2)
		b[i] = s2


## In-place feedback delay with a darkening low-pass in the loop: cheap outdoor slap/tail.
static func echo(b: PackedFloat32Array, delay: float, feedback: float, mix: float, damp_hz := 2500.0) -> void:
	var d := int(delay * RATE)
	var n := b.size()
	if d <= 0 or d >= n:
		return
	var line := PackedFloat32Array()
	line.resize(d)
	line.fill(0.0)
	var a := 1.0 - exp(-TAU * damp_hz * INV_RATE)
	var s := 0.0
	var p := 0
	for i in n:
		var out := line[p]
		s += a * (out - s)
		line[p] = b[i] + s * feedback
		b[i] += s * mix
		p += 1
		if p == d:
			p = 0


## In-place tanh saturation, normalised so a full-scale input stays full scale.
static func drive(b: PackedFloat32Array, amount: float) -> void:
	var norm := 1.0 / tanh(amount)
	for i in b.size():
		b[i] = tanh(b[i] * amount) * norm


## Removes DC, trims trailing silence, fades both ends, normalises the peak to `peak_db`
## and encodes as 16-bit mono PCM. Loops keep their exact length and are only re-centred,
## so the seam stays continuous.
static func to_stream(b: PackedFloat32Array, peak_db := -1.5, loop := false) -> AudioStreamWAV:
	var n := b.size()
	if loop:
		_subtract_mean(b)
	else:
		_remove_dc(b)
		n = _trimmed_size(b)
		var fade_in := mini(int(0.0015 * RATE), n >> 2)
		for i in fade_in:
			b[i] *= float(i) / fade_in
		var fade_out := mini(int(0.012 * RATE), int(n / 3.0))
		for i in fade_out:
			b[n - 1 - i] *= float(i) / fade_out
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(b[i]))
	var g := db_to_linear(peak_db) / peak * 32767.0 if peak > 0.0 else 0.0
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(round(b[i] * g)))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	return s


static func _remove_dc(b: PackedFloat32Array) -> void:
	# A gentle one-pole high-pass (~20 Hz) removes the slow offsets from asymmetric
	# envelopes; the mean subtraction catches whatever is left.
	var a := 1.0 - exp(-TAU * 20.0 * INV_RATE)
	var s := 0.0
	for i in b.size():
		s += a * (b[i] - s)
		b[i] -= s
	_subtract_mean(b)


static func _subtract_mean(b: PackedFloat32Array) -> void:
	var sum := 0.0
	for v in b:
		sum += v
	var mean := sum / b.size()
	if absf(mean) > 1e-6:
		for i in b.size():
			b[i] -= mean


## Length up to the last sample above -60 dB relative to the peak, plus a few ms.
static func _trimmed_size(b: PackedFloat32Array) -> int:
	var peak := 0.0
	for i in b.size():
		peak = maxf(peak, absf(b[i]))
	var floor_v := peak * 0.001
	var last := b.size() - 1
	while last > 0 and absf(b[last]) < floor_v:
		last -= 1
	return mini(last + int(0.01 * RATE), b.size())


## PolyBLEP residual that band-limits the step at phase 0 of a unit-phase oscillator.
static func blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0
