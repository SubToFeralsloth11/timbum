class_name Chiptune
extends RefCounted
## Procedural chiptune composer and renderer: two pulse channels (lead, arpeggio), a
## stepped triangle bass and a noise/drum channel. Each track is composed from a seeded
## RNG (so it is identical every run) and rendered as a seamlessly looping AudioStreamWAV:
## the loop end is exactly the bar grid length and note tails wrap around to the start.
## Thread-safe: intended to run on WorkerThreadPool tasks.

const RATE := Synth.RATE
const MAJOR: Array[int] = [0, 2, 4, 5, 7, 9, 11]
const MINOR: Array[int] = [0, 2, 3, 5, 7, 8, 10]

## style: "chill" (menu), "drive" (match), "fanfare" (results).
## prog: chord roots as scale degrees, one per bar; a phrase is one pass of the progression.
## plan: phrase sequence; "A2" repeats A with a new cadence bar, "B" is a higher answer phrase.
const TRACKS := {
	&"menu": {"bpm": 96.0, "root": 62, "scale": MAJOR, "prog": [0, 5, 3, 4], "plan": ["A", "A2", "B"],
		"style": "chill", "seed": 1107},
	&"match": {"bpm": 160.0, "root": 57, "scale": MINOR, "prog": [0, 5, 2, 6], "plan": ["A", "A2", "B", "B2", "A2"],
		"style": "drive", "seed": 4242},
	&"results": {"bpm": 144.0, "root": 60, "scale": MAJOR, "prog": [0, 3, 4, 0, 3, 4], "plan": ["A"],
		"style": "fanfare", "seed": 77},
}

## Rhythm cells in 16th-note steps (each sums to 16); negative values are rests.
const RHYTHMS := {
	"chill": [[4, 4, 4, 4], [6, 2, 4, 4], [4, 2, 2, 8], [8, 4, 4], [2, 2, 4, -4, 4], [6, 6, 4]],
	"drive": [[2, 2, 2, 2, 4, 4], [4, 2, 2, 4, 4], [2, 2, 4, 2, 2, 4], [3, 3, 2, 4, 4], [2, 2, 2, 2, 2, 2, 4], [4, 4, 8]],
	"fanfare": [[4, 4, 8], [3, 1, 4, 8], [2, 2, 4, 4, 4], [4, 2, 2, 8], [12, 4]],
}

enum Inst { LEAD, ARP, BASS }


## Composes and renders `track`; returns null for unknown tracks, or when `job` is
## cancelled mid-render (checked once per note and per bar).
static func render(track: StringName, job: AudioJob = null) -> AudioStreamWAV:
	if not TRACKS.has(track):
		return null
	var spec: Dictionary = TRACKS[track]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed)
	var style: String = spec.style
	var prog: Array = spec.prog
	var plan: Array = spec.plan
	var bars := prog.size() * plan.size()
	var step_len := 60.0 / float(spec.bpm) / 4.0 * RATE
	var total := int(round(bars * 16 * step_len))
	var buf := PackedFloat32Array()
	buf.resize(total)
	buf.fill(0.0)

	var notes := _compose_lead(spec, rng)
	var root: int = spec.root
	var scale: Array[int] = spec.scale
	for e in notes:
		if job and job.cancelled:
			return null
		_note(buf, Inst.LEAD, e[0], e[1], e[2], 0.2, step_len)
	for bar in bars:
		if job and job.cancelled:
			return null
		var deg: int = prog[bar % prog.size()]
		var chord: Array[int] = [
			_midi(root, scale, deg), _midi(root, scale, deg + 2), _midi(root, scale, deg + 4), _midi(root, scale, deg + 7)]
		_arp(buf, style, bar, chord, step_len)
		_bass(buf, style, bar, chord[0] - 24, _midi(root, scale, deg + 4) - 24, step_len)
	_drums(buf, rng, style, bars, prog.size(), step_len)
	return Synth.to_stream(buf, -3.0, true)


static func _midi(root: int, scale: Array[int], deg: int) -> int:
	var octave := floori(deg / 7.0)
	return root + 12 * octave + scale[deg - octave * 7]


## Returns lead events [start_step, len_steps, midi].
static func _compose_lead(spec: Dictionary, rng: RandomNumberGenerator) -> Array:
	var style: String = spec.style
	var prog: Array = spec.prog
	var root: int = spec.root
	var scale: Array[int] = spec.scale
	var cells: Array = RHYTHMS[style]
	var phrases := {}
	var events: Array = []
	var bar_offset := 0
	for name: String in spec.plan:
		if not phrases.has(name):
			var base := name.substr(0, 1)
			if name.length() > 1 and phrases.has(base):
				# Variation: keep the theme, rewrite the final bar as a fresh cadence.
				var theme: Array = phrases[base].duplicate()
				theme[theme.size() - 1] = _bar(rng, cells, prog, prog.size() - 1, 7 if base == "A" else 9, true)
				phrases[name] = theme
			else:
				var shift := 0 if base == "A" else 2
				var phrase: Array = []
				for i in prog.size():
					phrase.append(_bar(rng, cells, prog, i, 7 + shift, i == prog.size() - 1))
				phrases[name] = phrase
		var bars_notes: Array = phrases[name]
		for i in bars_notes.size():
			for n: Array in bars_notes[i]:
				events.append([(bar_offset + i) * 16 + n[0], n[1], _midi(root, scale, n[2])])
		bar_offset += prog.size()
	return events


## One bar of melody as [step_in_bar, len, scale_degree] around degree `centre`. Beats land
## on chord tones (avoiding repeats), off-beats walk by step with a persistent direction, and
## a cadence bar ends on the nearest tonic.
static func _bar(rng: RandomNumberGenerator, cells: Array, prog: Array, bar: int, centre: int, cadence: bool) -> Array:
	var cell: Array = cells[rng.randi_range(0, cells.size() - 1)]
	var chord_root: int = prog[bar]
	var out: Array = []
	var step := 0
	var deg := centre + rng.randi_range(-2, 3)
	var dir := 1 if rng.randf() < 0.5 else -1
	for d: int in cell:
		var dur := absi(d)
		if d > 0:
			if step % 4 == 0:
				var best := deg
				var best_score := 1e9
				for cand in range(centre - 4, centre + 6):
					var rel := posmod(cand - chord_root, 7)
					if rel == 0 or rel == 2 or rel == 4:
						var score := absf(cand - deg) * 0.6 + rng.randf() * 3.0 + (3.0 if cand == deg else 0.0)
						if score < best_score:
							best_score = score
							best = cand
				deg = best
			else:
				if rng.randf() < 0.3 or deg + dir > centre + 5 or deg + dir < centre - 4:
					dir = -dir
				deg += dir * (2 if rng.randf() < 0.25 else 1)
			if cadence and step + dur >= 16:
				deg = int(round(deg / 7.0)) * 7
			out.append([step, dur, deg])
		step += dur
	return out


static func _arp(buf: PackedFloat32Array, style: String, bar: int, chord: Array[int], step_len: float) -> void:
	var base := bar * 16
	match style:
		"chill":
			var order := [0, 1, 2, 3, 2, 1, 0, 1]
			for k in 8:
				_note(buf, Inst.ARP, base + k * 2, 2, chord[order[k]], 0.075, step_len)
		"drive":
			var order := [0, 2, 1, 3]
			for k in 16:
				_note(buf, Inst.ARP, base + k, 1, chord[order[k % 4]], 0.06 if k % 2 == 1 else 0.08, step_len)
		_:
			for k in 4:
				for c in 3:
					_note(buf, Inst.ARP, base + k * 4, 3, chord[c], 0.045, step_len)


static func _bass(buf: PackedFloat32Array, style: String, bar: int, root: int, fifth: int, step_len: float) -> void:
	var base := bar * 16
	match style:
		"chill":
			_note(buf, Inst.BASS, base, 6, root, 0.4, step_len)
			_note(buf, Inst.BASS, base + 6, 2, root + 12, 0.3, step_len)
			_note(buf, Inst.BASS, base + 8, 6, fifth, 0.4, step_len)
			_note(buf, Inst.BASS, base + 14, 2, root, 0.3, step_len)
		"drive":
			for k in 8:
				_note(buf, Inst.BASS, base + k * 2, 2, root + 12 * (k % 2), 0.4, step_len)
		_:
			for k in 4:
				_note(buf, Inst.BASS, base + k * 4, 4, root if k % 2 == 0 else fifth, 0.42, step_len)


static func _drums(buf: PackedFloat32Array, rng: RandomNumberGenerator, style: String, bars: int,
		phrase_bars: int, step_len: float) -> void:
	var kick := Synth.make(0.2)
	Synth.tone(kick, 0.0, 0.2, 150.0, 42.0, 1.0, Synth.Wave.TRIANGLE, 0.001, 0.07)
	Synth.noise(kick, rng, 0.0, 0.01, 0.3, 5000.0, 2000.0, 0.0, 0.0003, 0.003)
	var snare := Synth.make(0.18)
	Synth.noise(snare, rng, 0.0, 0.18, 0.75, 7000.0, 3500.0, 600.0, 0.0005, 0.05)
	Synth.tone(snare, 0.0, 0.08, 220.0, 160.0, 0.4, Synth.Wave.TRIANGLE, 0.0005, 0.03)
	var hat := Synth.make(0.05)
	Synth.noise(hat, rng, 0.0, 0.05, 0.6, 11000.0, 9000.0, 6000.0, 0.0003, 0.012)
	for bar in bars:
		var base := bar * 16
		var fill := style != "chill" and bar % phrase_bars == phrase_bars - 1
		match style:
			"chill":
				_hit(buf, kick, base, 0.3, step_len)
				_hit(buf, kick, base + 10, 0.22, step_len)
				_hit(buf, snare, base + 4, 0.12, step_len)
				_hit(buf, snare, base + 12, 0.12, step_len)
				for k in 8:
					_hit(buf, hat, base + k * 2, 0.07 if k % 2 == 0 else 0.045, step_len)
			"drive":
				for k in 4:
					_hit(buf, kick, base + k * 4, 0.34, step_len)
				_hit(buf, snare, base + 4, 0.2, step_len)
				_hit(buf, snare, base + 12, 0.2, step_len)
				for k in 16:
					_hit(buf, hat, base + k, 0.07 if k % 2 == 0 else 0.04, step_len)
			_:
				_hit(buf, kick, base, 0.32, step_len)
				_hit(buf, kick, base + 8, 0.28, step_len)
				_hit(buf, snare, base + 4, 0.18, step_len)
				_hit(buf, snare, base + 12, 0.18, step_len)
				for k in 8:
					_hit(buf, hat, base + k * 2, 0.06, step_len)
		if fill:
			for k in 3:
				_hit(buf, snare, base + 13 + k, 0.1 + k * 0.04, step_len)


## Mixes a pre-rendered drum hit at `step`, wrapping past the loop end.
static func _hit(buf: PackedFloat32Array, sample: PackedFloat32Array, step: int, amp: float, step_len: float) -> void:
	var total := buf.size()
	var p := int(round(step * step_len)) % total
	for j in sample.size():
		buf[p] += sample[j] * amp
		p += 1
		if p == total:
			p = 0


## Renders one note on a pulse (LEAD/ARP) or stepped-triangle (BASS) voice, wrapping at the loop end.
static func _note(buf: PackedFloat32Array, inst: Inst, step: int, len_steps: int, midi: int, amp: float, step_len: float) -> void:
	var total := buf.size()
	var p := int(round(step * step_len)) % total
	var gate := int(len_steps * step_len * (0.92 if inst == Inst.BASS else 0.85))
	var release := int(0.025 * RATE)
	var n := gate + release
	var f := 440.0 * pow(2.0, (midi - 69) / 12.0)
	var dt := f / RATE
	var duty := 0.25 if inst == Inst.LEAD else 0.125
	var dc := 2.0 * duty - 1.0
	var attack := 0.004 * RATE
	var sustain := 0.55 if inst == Inst.LEAD else (0.25 if inst == Inst.ARP else 0.85)
	var decay_k := exp(-1.0 / ((0.14 if inst == Inst.LEAD else 0.05) * RATE))
	var vib_start := int(0.15 * RATE)
	var vib_rate := 5.5 / RATE
	var phase := 0.0
	var lfo := 0.0
	var env := 1.0
	for j in n:
		var v: float
		if inst == Inst.BASS:
			# NES-style 4-bit stepped triangle.
			v = round((1.0 - 4.0 * absf(phase - 0.5)) * 7.5) / 7.5
		else:
			v = (1.0 if phase < duty else -1.0) - dc + Synth.blep(phase, dt)
			var p2 := phase - duty
			if p2 < 0.0:
				p2 += 1.0
			v -= Synth.blep(p2, dt)
		var g := sustain + (1.0 - sustain) * env
		if j < attack:
			g *= j / attack
		if j >= gate:
			g *= float(n - j) / release
		buf[p] += v * g * amp
		env *= decay_k
		var step_dt := dt
		if inst == Inst.LEAD and j > vib_start:
			lfo += vib_rate
			if lfo >= 1.0:
				lfo -= 1.0
			step_dt *= 1.0 + 0.005 * (1.0 - 4.0 * absf(lfo - 0.5))
		phase += step_dt
		if phase >= 1.0:
			phase -= 1.0
		p += 1
		if p == total:
			p = 0
