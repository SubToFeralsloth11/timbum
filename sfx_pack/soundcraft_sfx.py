#!/usr/bin/env python3
"""Builds every Timbum sound effect in SoundCraft and bounces it into sfx_pack/sounds/.

Each sound is its own SoundCraft session: noise layers from the Signal Generator (shaped with clip
fades, EQ and automation), Subtractive Synth and Drum Synth instrument tracks playing MIDI, and a
bus of SoundCraft's built-in effects. The session is bounced to `sfx_pack/sounds/<name>.wav`
(`<name>_<take>.wav` for sounds with several takes) and saved to `build/sfx_sessions/` so it can
be opened and tweaked in the app.

Usage (SoundCraft must be running with its control server):
    /Applications/SoundCraft.app/Contents/MacOS/SoundCraft --no-audio --control 47123
    python3 sfx_pack/soundcraft_sfx.py [--port 47123] [--only name ...]

sfx_pack/README.md lists the sound names, takes and playback levels.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import socket
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "sfx_pack" / "sounds"
SESSION_DIR = ROOT / "build" / "sfx_sessions"
TICKS_PER_SECOND = 1920  # 960 ticks per quarter note at the session's default 120 BPM

# Subtractive Synth oscillator waves and Signal Generator waveforms.
SAW, SQUARE, SINE, TRIANGLE = 0, 1, 2, 3
WHITE, PINK = 4, 5
# EQ 1-Band filter types.
PEAK, LOW_SHELF, HIGH_SHELF, HIGH_PASS, LOW_PASS, NOTCH, BAND_PASS = range(7)
# Drum Synth notes.
KICK, RIM, SNARE, CLAP, TOM_LOW, HAT, TOM_MID, OPEN_HAT, TOM_HIGH, CRASH, RIDE = (
	36, 37, 38, 39, 41, 42, 45, 46, 48, 49, 51)


def hz(freq: float) -> int:
	"""The nearest MIDI note to `freq`."""
	return round(69 + 12 * math.log2(freq / 440.0))


def at(seconds: float) -> dict:
	return {"seconds": round(seconds, 6)}


# Effect chain shorthands: (plugin id, params).
def eq(kind: int, freq: float, q: float = 0.707, gain: float = 0.0) -> tuple:
	return ("eq_1band", {"type": kind, "freq": freq, "q": q, "gain": gain})


def hp(freq: float, q: float = 0.707) -> tuple:
	return eq(HIGH_PASS, freq, q)


def lp(freq: float, q: float = 0.707) -> tuple:
	return eq(LOW_PASS, freq, q)


def bp(freq: float, q: float = 1.0) -> tuple:
	return eq(BAND_PASS, freq, q)


def sat(drive: float, tone: float = 20000.0, mix: float = 100.0) -> tuple:
	return ("saturator", {"drive": drive, "tone": tone, "mix": mix})


def comp(threshold: float = -18.0, ratio: float = 4.0, attack: float = 1.0, release: float = 80.0,
		makeup: float = 0.0) -> tuple:
	return ("compressor", {"threshold": threshold, "ratio": ratio, "attack": attack,
		"release": release, "makeup": makeup})


def room(mix: float, decay: float = 0.8, size: float = 40.0, damping: float = 6000.0,
		pre_delay: float = 5.0) -> tuple:
	return ("room_reverb", {"mix": mix, "decay": decay, "size": size, "damping": damping,
		"pre_delay": pre_delay})


def plate(mix: float, decay: float = 1.5, damping: float = 8000.0, pre_delay: float = 10.0) -> tuple:
	return ("plate_reverb", {"mix": mix, "decay": decay, "damping": damping, "pre_delay": pre_delay})


def delay(ms: float, feedback: float, mix: float, lpf: float = 6000.0) -> tuple:
	return ("mod_delay", {"time": ms, "feedback": feedback, "mix": mix, "lpf": lpf})


def ring(freq: float, mix: float, effect: int = 0, resonance: float = 50.0) -> tuple:
	return ("ring_mod", {"effect": effect, "frequency": freq, "mix": mix, "resonance": resonance})


def sub(mix: float = 40.0, range_: int = 3) -> tuple:
	return ("subharmonic", {"mix": mix, "range": range_})


def limit(squash: float = 0.0, ceiling: float = -1.0) -> tuple:
	"""The Maximizer, last on the bus: `squash` dB of the mix's peak are limited away at bounce time
	(louder, denser hits); 0 only catches overs."""
	return ("maximizer", {"threshold": 0.0, "ceiling": ceiling, "release": 50.0, "squash": squash})


def synth(wave: int, decay_ms: float, *, wave2: int | None = None, semis: float = 0.0,
		detune: float = 0.0, mix: float = 0.0, attack_ms: float = 0.5, sustain: float = 0.0,
		release_ms: float | None = None, cutoff: float = 20000.0, resonance: float = 0.0,
		filter_env: float = 0.0, filter_decay_ms: float = 300.0, glide_ms: float = 0.0) -> dict:
	"""Subtractive Synth parameters. `mix` is the share of oscillator 2 (0 = osc 1 only)."""
	return {
		"osc1_wave": wave, "osc2_wave": wave if wave2 is None else wave2,
		"osc2_semitones": semis, "osc2_detune": detune, "osc_mix": mix,
		"cutoff": cutoff, "resonance": resonance, "filter_env_amount": filter_env,
		"filter_attack": 0.5, "filter_decay": filter_decay_ms, "filter_sustain": 0.0,
		"amp_attack": attack_ms, "amp_decay": decay_ms, "amp_sustain": sustain,
		"amp_release": decay_ms * 0.5 if release_ms is None else release_ms,
		"glide": glide_ms, "velocity": 40.0, "level": 0.0,
	}


class SoundCraft:
	"""JSON-lines client for SoundCraft's control server."""

	def __init__(self, port: int) -> None:
		self._sock = socket.create_connection(("127.0.0.1", port))
		self._sock.settimeout(120)
		self._io = self._sock.makefile("rwb")
		self._id = 0

	def call(self, method: str, params: dict | None = None) -> dict:
		self._id += 1
		request = {"id": self._id, "method": method, "params": params or {}}
		self._io.write((json.dumps(request) + "\n").encode())
		self._io.flush()
		line = self._io.readline()
		if not line:
			raise RuntimeError("SoundCraft closed the control connection")
		reply = json.loads(line)
		if not reply.get("ok"):
			raise RuntimeError(f"{method} {json.dumps(params)[:300]}: {reply.get('error')}")
		return reply.get("result")

	def run(self, command: str, **params) -> dict:
		return self.call("engine.execute", {"command": command, "params": params})


class Sound:
	"""One sound effect: a fresh SoundCraft session that layers are added to."""

	def __init__(self, sc: SoundCraft, name: str, length: float) -> None:
		self.sc = sc
		self.name = name
		self.length = length
		self._count = 0
		sc.run("session.new", name=name, sample_rate=48000)
		self._bus = sc.run("track.new", kind="master", name="Bus")["tracks"][0]
		self._bus_slots = 0
		self._squash: tuple | None = None  # (bus slot of the Maximizer, dB to squash)

	def _new_track(self, kind: str, label: str, fx, db: float, pan: float, **extra) -> int:
		self._count += 1
		track = self.sc.run("track.new", kind=kind, name=f"{label} {self._count}", **extra)["tracks"][0]
		for slot, (plugin, params) in enumerate(fx):
			self.sc.run("mix.insert", track=track, slot=slot, plugin=plugin, params=params)
		self.sc.run("mix.volume", tracks=[track], db=db)
		if pan:
			self.sc.run("mix.pan", tracks=[track], pan=pan)
		return track

	def _automate(self, track: int, auto: dict | None) -> None:
		"""`auto`: {"a:freq": [(seconds, value), ...]} for insert slot a's `freq`, or "volume"."""
		for param, points in (auto or {}).items():
			key = param if param == "volume" else f"plugin:{param}"
			for t, value in points:
				self.sc.run("automation.set_point", track=track, param=key, at=at(t), value=value)

	def noise(self, start: float, dur: float, *, color: int = WHITE, db: float = 0.0, fx=(),
			fade_in: float = 0.0005, fade_out: float | None = None, shape: str = "exponential",
			auto: dict | None = None, pan: float = 0.0) -> None:
		"""A Signal Generator noise burst from `start` for `dur` s, faded in and out."""
		track = self._new_track("audio", "Noise", fx, db, pan, format="mono")
		clip = self.sc.run("audiosuite.process", process="signal_generator",
			params={"waveform": color, "level": -6.0}, tracks=[track],
			start=at(start), end=at(start + dur))["clips"][0]
		total = int(dur * 48000)
		fin = max(1, int(fade_in * 48000))
		fout = min(total - fin, int((dur if fade_out is None else fade_out) * 48000))
		self.sc.run("edit.fades_create", clip=clip, side="in", length=fin, shape="linear")
		if fout > 0:
			self.sc.run("edit.fades_create", clip=clip, side="out", length=fout, shape=shape)
		self._automate(track, auto)

	def synth(self, params: dict, notes, *, db: float = 0.0, fx=(), auto: dict | None = None,
			pan: float = 0.0) -> None:
		"""Subtractive Synth notes: (pitch, start, dur[, velocity]); a (from, to) pitch glides
		from one note to the other over the synth's `glide` time."""
		track = self._new_track("instrument", "Synth", fx, db, pan, format="stereo",
			instrument="subtractive_synth")
		self.sc.run("mix.instrument", track=track, plugin="subtractive_synth", params=params)
		self._notes(track, notes)
		self._automate(track, auto)

	def drums(self, notes, *, db: float = 0.0, fx=(), pan: float = 0.0, **params) -> None:
		"""Drum Synth hits: (note, start[, velocity])."""
		track = self._new_track("instrument", "Drums", fx, db, pan, format="stereo",
			instrument="drum_synth")
		if params:
			self.sc.run("mix.instrument", track=track, plugin="drum_synth", params=params)
		self._notes(track, [(n[0], n[1], 0.05, n[2] if len(n) > 2 else 110) for n in notes])

	def _notes(self, track: int, notes) -> None:
		clip = self.sc.run("midi.new_clip", track=track, start=0, length=at(self.length + 1.0))["clip"]
		for note in notes:
			pitch, start, dur = note[0], note[1], note[2]
			vel = int(note[3]) if len(note) > 3 else 110
			t0 = int(start * TICKS_PER_SECOND)
			length = max(2, int(dur * TICKS_PER_SECOND))
			if isinstance(pitch, tuple):
				# A 2-tick note at the start pitch, then the target right after it: the synth glides
				# from one to the other.
				self.sc.run("midi.note_add", clip=clip, pitch=pitch[0], start_ticks=t0,
					length_ticks=2, velocity=vel)
				pitch, t0, length = pitch[1], t0 + 2, max(2, length - 2)
			self.sc.run("midi.note_add", clip=clip, pitch=pitch, start_ticks=t0,
				length_ticks=length, velocity=vel)

	def bus(self, *fx) -> None:
		"""Effects on the bus every layer plays through."""
		for plugin, params in fx:
			if "squash" in params:
				params = dict(params)
				self._squash = (self._bus_slots, params.pop("squash"))
			self.sc.run("mix.insert", track=self._bus, slot=self._bus_slots, plugin=plugin, params=params)
			self._bus_slots += 1

	def bounce(self, path: Path, session: Path | None) -> dict:
		if self._squash and self._squash[1] > 0:
			# Measure the mix's peak, then set the Maximizer's threshold that far below it.
			slot, squash = self._squash
			probe = self.sc.run("file.bounce_mix", path=str(path), format="wav", bit_depth=16,
				start=0, end=at(self.length), normalize=False)
			threshold = max(-30.0, min(0.0, probe["peak_db"] - squash))
			self.sc.run("mix.insert_param", track=self._bus, slot=slot, param="threshold", value=threshold)
		result = self.sc.run("file.bounce_mix", path=str(path), format="wav", bit_depth=16,
			start=0, end=at(self.length), normalize=True, dither=True)
		if session:
			self.sc.run("session.save_as", path=str(session), replace=True)
		self.sc.run("session.close")
		return result


# --- Recipes ---------------------------------------------------------------------------------
# Each recipe(s, take, rng) adds layers to a Sound. RECIPES: name -> (length s, takes, recipe).

RECIPES: dict = {}


def sfx(name: str, length: float, takes: int = 1):
	def register(fn):
		RECIPES[name] = (length, takes, fn)
		return fn
	return register


def gun(s: Sound, rng: random.Random, *, crack_db: float, crack_s: float, body_lp: float,
		body_s: float, kick_tune: float, kick_decay: float, kick_db: float, snare_db: float,
		tail_s: float, tail_db: float, drive: float, room_mix: float, slap_ms: float,
		squash: float = 9.0) -> None:
	"""A gunshot: supersonic crack, muzzle blast body, kick-drum punch, snare snap and an outdoor
	tail, glued with saturation, compression and a short slap-back."""
	s.noise(0.0, crack_s, color=WHITE, db=crack_db, fx=[hp(2500), eq(PEAK, 6500, 1.2, 4)])
	s.noise(0.0, body_s, color=PINK, db=-3.0, fx=[lp(body_lp), eq(PEAK, 180, 1.0, 5)])
	s.drums([(KICK, 0.0, 127)], db=kick_db, kick_tune=kick_tune, kick_decay=kick_decay, level=0)
	s.drums([(SNARE, 0.0, 120)], db=snare_db, snare_tune=rng.uniform(-2, 2), snare_snappy=85,
		snare_decay=120, level=0)
	s.noise(0.01, tail_s, color=PINK, db=tail_db, fade_in=0.01, fx=[lp(1200), hp(120)])
	s.bus(eq(PEAK, 450, 1.0, -4), sat(drive, 9000), comp(-20, 6, 0.3, 120, 6), delay(slap_ms, 18, 18, 2500),
		room(room_mix, 1.1, 60, 4500), limit(squash))


@sfx("shot_pistol", 0.6)
def shot_pistol(s, v, rng):
	gun(s, rng, crack_db=-2, crack_s=0.07, body_lp=2600, body_s=0.25, kick_tune=4, kick_decay=160,
		kick_db=-3, snare_db=-6, tail_s=0.45, tail_db=-16, drive=12, room_mix=14, slap_ms=95)


@sfx("shot_revolver", 0.95)
def shot_revolver(s, v, rng):
	gun(s, rng, crack_db=0, crack_s=0.09, body_lp=1800, body_s=0.4, kick_tune=-2, kick_decay=300,
		kick_db=0, snare_db=-5, tail_s=0.8, tail_db=-12, drive=16, room_mix=18, slap_ms=130)


@sfx("shot_smg", 0.35)
def shot_smg(s, v, rng):
	gun(s, rng, crack_db=-3, crack_s=0.04, body_lp=3600, body_s=0.13, kick_tune=7, kick_decay=90,
		kick_db=-5, snare_db=-6, tail_s=0.25, tail_db=-18, drive=10, room_mix=8, slap_ms=60)


@sfx("shot_rifle", 0.75)
def shot_rifle(s, v, rng):
	gun(s, rng, crack_db=0, crack_s=0.06, body_lp=3000, body_s=0.28, kick_tune=2, kick_decay=200,
		kick_db=-2, snare_db=-5, tail_s=0.6, tail_db=-14, drive=14, room_mix=14, slap_ms=110)
	s.drums([(RIM, 0.035, 70)], db=-14)


@sfx("shot_carbine", 0.7)
def shot_carbine(s, v, rng):
	gun(s, rng, crack_db=-1, crack_s=0.055, body_lp=2800, body_s=0.24, kick_tune=3, kick_decay=180,
		kick_db=-3, snare_db=-6, tail_s=0.55, tail_db=-15, drive=12, room_mix=12, slap_ms=100)


@sfx("shot_burst_smg", 0.38)
def shot_burst_smg(s, v, rng):
	gun(s, rng, crack_db=-3, crack_s=0.035, body_lp=3800, body_s=0.12, kick_tune=8, kick_decay=80,
		kick_db=-6, snare_db=-6, tail_s=0.22, tail_db=-19, drive=9, room_mix=7, slap_ms=55)


@sfx("shot_lmg", 0.65)
def shot_lmg(s, v, rng):
	gun(s, rng, crack_db=0, crack_s=0.06, body_lp=2600, body_s=0.3, kick_tune=0, kick_decay=240,
		kick_db=0, snare_db=-5, tail_s=0.55, tail_db=-13, drive=16, room_mix=12, slap_ms=100)


@sfx("shot_minigun", 0.55)
def shot_minigun(s, v, rng):
	gun(s, rng, crack_db=-1, crack_s=0.04, body_lp=3200, body_s=0.2, kick_tune=1, kick_decay=150,
		kick_db=-1, snare_db=-5, tail_s=0.45, tail_db=-14, drive=15, room_mix=10, slap_ms=80, squash=10)
	# The barrels' rotary whir under each shot.
	s.synth(synth(SAW, 500, wave2=SQUARE, mix=40, detune=20, cutoff=900, glide_ms=400),
		[((hz(200), hz(80)), 0.0, 0.5)], db=-18)


@sfx("shot_dmr", 1.0)
def shot_dmr(s, v, rng):
	gun(s, rng, crack_db=1, crack_s=0.08, body_lp=2600, body_s=0.45, kick_tune=-1, kick_decay=320,
		kick_db=0, snare_db=-4, tail_s=0.85, tail_db=-11, drive=16, room_mix=18, slap_ms=140)
	s.drums([(RIM, 0.06, 60)], db=-15)


@sfx("shot_shotgun", 1.0)
def shot_shotgun(s, v, rng):
	gun(s, rng, crack_db=0, crack_s=0.12, body_lp=2000, body_s=0.55, kick_tune=-5, kick_decay=420,
		kick_db=2, snare_db=-3, tail_s=0.9, tail_db=-10, drive=18, room_mix=18, slap_ms=150)
	# Pellets smear the crack into a few tight transients.
	for k in range(3):
		s.noise(0.003 + k * 0.004, 0.03, db=-8, fx=[hp(3000)])


@sfx("shot_drum_shotgun", 1.0)
def shot_drum_shotgun(s, v, rng):
	gun(s, rng, crack_db=0, crack_s=0.1, body_lp=2100, body_s=0.5, kick_tune=-4, kick_decay=380,
		kick_db=1, snare_db=-3, tail_s=0.85, tail_db=-11, drive=17, room_mix=16, slap_ms=140)
	for k in range(2):
		s.noise(0.002 + k * 0.003, 0.025, db=-9, fx=[hp(2800)])


@sfx("shot_sniper", 1.8)
def shot_sniper(s, v, rng):
	gun(s, rng, crack_db=3, crack_s=0.05, body_lp=3000, body_s=0.6, kick_tune=-3, kick_decay=500,
		kick_db=2, snare_db=-3, tail_s=1.6, tail_db=-8, drive=18, room_mix=24, slap_ms=230, squash=11)
	# A long rolling echo off distant terrain.
	s.noise(0.2, 1.4, color=PINK, db=-16, fade_in=0.15, fx=[lp(700)])


@sfx("shot_suppressed", 0.3)
def shot_suppressed(s, v, rng):
	# A suppressed .22: a dull puff and the action clacking, no crack.
	s.noise(0.0, 0.12, color=PINK, db=0, fx=[lp(1400), lp(1400)])
	s.drums([(TOM_LOW, 0.0, 100)], db=-6, tom_tune=-4, tom_decay=80)
	s.drums([(RIM, 0.03, 90)], db=-8)
	s.bus(sat(4, 6000), comp(-18, 4, 0.5, 60, 3), limit())


@sfx("shot_crossbow", 1.2)
def shot_crossbow(s, v, rng):
	# The string slamming forward: a low thwump, a snap and a decaying twang.
	s.drums([(KICK, 0.0, 127)], db=0, kick_tune=-8, kick_decay=350)
	s.noise(0.0, 0.03, db=-3, fx=[hp(3000)])
	s.synth(synth(SAW, 450, wave2=TRIANGLE, mix=50, cutoff=1400, filter_env=40, glide_ms=60),
		[((hz(110), hz(82)), 0.0, 0.5)], db=-8)
	s.drums([(RIM, 0.0, 120)], db=-6)
	s.bus(sat(8, 7000), comp(-20, 5, 0.5, 100, 4), delay(180, 20, 15, 2500), room(12, 0.9, 50, 5000),
		limit(9))


@sfx("shot_rocket", 1.3)
def shot_rocket(s, v, rng):
	s.drums([(KICK, 0.0, 127)], db=0, kick_tune=-9, kick_decay=500)
	s.noise(0.0, 0.08, db=-4, fx=[lp(3000)])
	# Motor whoosh: a rushing band of noise that brightens as it leaves.
	s.noise(0.01, 1.25, color=PINK, db=0, fade_in=0.06, fade_out=0.9,
		fx=[bp(500, 1.2)], auto={"a:freq": [(0.01, 400), (1.26, 2800)]})
	s.noise(0.02, 1.0, db=-12, fade_in=0.04, fx=[hp(5000)])
	s.bus(sat(10, 8000), comp(-20, 4, 1, 150, 4), delay(130, 25, 18, 2000), room(15, 1.2, 60, 4500),
		limit())


@sfx("explosion", 2.6)
def explosion(s, v, rng):
	s.drums([(KICK, 0.0, 127)], db=2, kick_tune=-12, kick_decay=1600, fx=[sub(50, 3)])
	s.drums([(TOM_LOW, 0.005, 127)], db=-2, tom_tune=-12, tom_decay=900)
	s.noise(0.0, 2.5, color=PINK, db=0, fade_in=0.004, fx=[lp(420), lp(600)])
	s.noise(0.0, 0.25, db=-4, fx=[hp(1200)])
	# Debris pattering down after the blast.
	for k in range(14):
		t = rng.uniform(0.08, 1.3)
		s.noise(t, 0.04, db=-28 + 10 * (1.3 - t) / 1.3 + rng.uniform(-3, 0),
			fx=[bp(rng.uniform(1200, 3000), 2.0), lp(4000)])
	s.bus(sat(14, 6000), comp(-22, 5, 2, 300, 6), room(22, 2.2, 80, 3500, 20), limit(10))


@sfx("flashbang", 1.6)
def flashbang(s, v, rng):
	s.noise(0.0, 0.04, db=3, fx=[hp(4000)])
	s.drums([(SNARE, 0.0, 127)], db=-2, snare_snappy=100, snare_decay=200)
	s.noise(0.0, 0.6, color=PINK, db=-2, fx=[lp(3000)])
	s.drums([(KICK, 0.0, 127)], db=-2, kick_tune=-6, kick_decay=300)
	# The ear-ringing tone left behind.
	s.synth(synth(SINE, 1500, sustain=0, release_ms=600), [(hz(3900), 0.05, 1.4, 90)], db=-20)
	s.bus(sat(16, 12000), comp(-20, 6, 0.3, 200, 6), plate(15, 1.6), limit(3))


@sfx("smoke_pop", 2.0)
def smoke_pop(s, v, rng):
	s.drums([(TOM_LOW, 0.0, 120)], db=0, tom_tune=-6, tom_decay=180)
	s.noise(0.0, 0.08, color=PINK, db=-4, fx=[lp(2000)])
	# A long hiss of smoke pouring out.
	s.noise(0.05, 1.9, db=-16, fade_in=0.15, fade_out=1.2, fx=[hp(1200), lp(7000)],
		auto={"a:freq": [(0.05, 2500), (1.95, 900)]})
	s.bus(comp(-20, 3, 2, 150, 3), room(10, 0.8, 40), limit())


@sfx("grapple_fire", 0.45)
def grapple_fire(s, v, rng):
	# Spring launch, then the line whirring out.
	s.drums([(RIM, 0.0, 127)], db=-2)
	s.drums([(KICK, 0.0, 110)], db=-4, kick_tune=6, kick_decay=60)
	s.noise(0.02, 0.4, db=-8, fade_in=0.01, fade_out=0.3, fx=[bp(2600, 2.0)],
		auto={"a:freq": [(0.02, 3600), (0.42, 1800)]})
	s.synth(synth(TRIANGLE, 380, sustain=60, release_ms=80, glide_ms=350),
		[((hz(900), hz(520)), 0.02, 0.36, 80)], db=-14, fx=[("phaser", {"rate": 4.0, "mix": 40})])
	s.bus(comp(-18, 4, 0.5, 60, 3), limit())


@sfx("slide", 0.6)
def slide(s, v, rng):
	# Fabric and grit scraping along the floor.
	s.noise(0.0, 0.55, color=PINK, db=0, fade_in=0.03, fade_out=0.3, fx=[bp(900, 0.8)],
		auto={"a:freq": [(0.0, 1300), (0.55, 700)]})
	s.noise(0.0, 0.4, db=-10, fade_in=0.02, fade_out=0.2, fx=[bp(3500, 1.2)])
	s.bus(("auto_pan", {"rate": 960, "width": 15}), comp(-20, 3, 5, 100, 2), limit())


@sfx("reload", 1.1)
def reload(s, v, rng):
	# Mag release, mag out, rattle, mag seated, bolt back and forward.
	s.drums([(RIM, 0.03, 110), (RIM, 0.07, 80), (RIM, 0.48, 127), (HAT, 0.5, 90), (RIM, 0.74, 120),
		(RIM, 0.83, 127)], db=0)
	s.drums([(HAT, 0.031, 70), (HAT, 0.741, 70), (HAT, 0.832, 90)], db=-8, hat_decay=40)
	s.drums([(TOM_HIGH, 0.48, 120)], db=-6, tom_tune=-2, tom_decay=60)
	s.noise(0.2, 0.15, color=PINK, db=-14, fade_in=0.03, fx=[bp(2000, 1.5)])
	s.noise(0.7, 0.05, db=-16, fade_in=0.01, fx=[bp(3000, 1.5)])
	s.bus(eq(PEAK, 2800, 1.0, 3), comp(-18, 4, 0.3, 50, 3), room(8, 0.3, 15, 8000), limit())


@sfx("dry_fire", 0.16)
def dry_fire(s, v, rng):
	s.drums([(RIM, 0.0, 120), (HAT, 0.018, 80)], db=0, hat_decay=25)
	s.bus(hp(600), eq(PEAK, 3400, 1.5, 4), limit())


def whoosh(s: Sound, *, dur: float, f0: float, f1: float, q: float, db: float = 0.0,
		color: int = PINK, peak_at: float = 0.6) -> None:
	"""A swing: band-passed noise sweeping from f0 to f1, swelling then dying."""
	s.noise(0.0, dur, color=color, db=db, fade_in=dur * peak_at, fade_out=dur * (1 - peak_at),
		shape="s-curve", fx=[bp(f0, q)], auto={"a:freq": [(0.0, f0), (dur, f1)]})


@sfx("knife_swing", 0.32)
def knife_swing(s, v, rng):
	whoosh(s, dur=0.3, f0=900, f1=3800, q=2.0)
	whoosh(s, dur=0.2, f0=5000, f1=7000, q=2.0, db=-10, color=WHITE)
	s.bus(limit())


@sfx("swing_blunt", 0.35)
def swing_blunt(s, v, rng):
	whoosh(s, dur=0.32, f0=600, f1=2500, q=1.5)
	whoosh(s, dur=0.22, f0=4000, f1=6000, q=2.0, db=-12, color=WHITE)
	s.bus(limit())


@sfx("swing_heavy", 0.45)
def swing_heavy(s, v, rng):
	whoosh(s, dur=0.42, f0=350, f1=1500, q=1.2, peak_at=0.65)
	s.synth(synth(SINE, 250, attack_ms=40, glide_ms=200), [((hz(80), hz(40)), 0.05, 0.25, 90)], db=-16)
	whoosh(s, dur=0.25, f0=5000, f1=7000, q=2.0, db=-14, color=WHITE)
	s.bus(limit())


@sfx("swing_blade", 0.32)
def swing_blade(s, v, rng):
	whoosh(s, dur=0.25, f0=1200, f1=4500, q=2.5, color=WHITE, peak_at=0.5)
	# The edge singing as it cuts the air.
	s.synth(synth(SINE, 220, wave2=SINE, semis=7, detune=12, mix=40), [(hz(3150), 0.08, 0.2, 60)],
		db=-22, fx=[ring(2400, 25)])
	s.bus(plate(8, 0.6), limit())


@sfx("knife_hit", 0.3, takes=2)
def knife_hit(s, v, rng):
	s.drums([(TOM_LOW, 0.0, 127)], db=0, tom_tune=-2 - 3 * v, tom_decay=110)
	s.drums([(KICK, 0.0, 110)], db=-4, kick_tune=4 - 2 * v, kick_decay=90)
	s.noise(0.0, 0.12, color=PINK, db=-3, fx=[lp(1300)])
	s.noise(0.0, 0.03, db=-10, fx=[bp(4000, 1.5)])
	s.bus(sat(10, 6000), comp(-18, 5, 0.3, 80, 4), limit(5))


@sfx("hit_marker", 0.09)
def hit_marker(s, v, rng):
	s.synth(synth(SINE, 70, wave2=TRIANGLE, semis=12, mix=20), [(hz(2700), 0.0, 0.07, 120)], db=0)
	s.drums([(HAT, 0.0, 90)], db=-12, hat_decay=20)
	s.bus(limit())


@sfx("headshot", 0.6)
def headshot(s, v, rng):
	# A bright metallic "dink".
	s.synth(synth(SINE, 450, wave2=SINE, semis=19, detune=30, mix=35), [(hz(1760), 0.0, 0.5, 120)],
		db=0, fx=[ring(2470, 35)])
	s.drums([(HAT, 0.0, 100), (RIM, 0.0, 90)], db=-14, hat_decay=30)
	s.bus(plate(10, 0.8, 9000), limit())


@sfx("kill_confirm", 0.8)
def kill_confirm(s, v, rng):
	bell = synth(SINE, 420, wave2=SINE, semis=12, mix=30)
	s.synth(bell, [(hz(1318.5), 0.0, 0.3, 110), (hz(1975.5), 0.09, 0.6, 120)], db=0,
		fx=[ring(2900, 18)])
	s.synth(synth(TRIANGLE, 300), [(hz(659.3), 0.0, 0.25, 90), (hz(987.8), 0.09, 0.45, 100)], db=-6)
	s.bus(plate(14, 1.0, 9000), limit())


@sfx("hurt", 0.32)
def hurt(s, v, rng):
	s.drums([(KICK, 0.0, 120)], db=0, kick_tune=5, kick_decay=120)
	s.synth(synth(TRIANGLE, 180, cutoff=1500, glide_ms=150), [((hz(280), hz(150)), 0.0, 0.2, 100)], db=-6)
	s.noise(0.0, 0.1, color=PINK, db=-6, fx=[lp(1500)])
	s.bus(sat(8, 5000), comp(-16, 4, 0.5, 60, 3), limit())


@sfx("death", 1.1)
def death(s, v, rng):
	s.synth(synth(SQUARE, 900, wave2=TRIANGLE, semis=-12, mix=55, cutoff=2200, sustain=20,
		release_ms=200, glide_ms=800), [((hz(360), hz(70)), 0.0, 0.9, 110)], db=0)
	s.drums([(KICK, 0.0, 120)], db=-4, kick_tune=-4, kick_decay=300)
	s.noise(0.0, 0.2, color=PINK, db=-8, fx=[lp(1200)])
	s.bus(sat(6, 4000), room(18, 1.0, 50, 4000), limit())


@sfx("footstep", 0.17, takes=4)
def footstep(s, v, rng):
	s.drums([(TOM_LOW, 0.0, 100 + 8 * v)], db=0, tom_tune=-8 + rng.uniform(-2, 2), tom_decay=60)
	s.noise(0.0, 0.12, color=PINK, db=-2, fx=[lp(rng.uniform(800, 1300)), hp(60)])
	# Grit crunch, slightly delayed like a heel-to-toe roll.
	s.noise(rng.uniform(0.005, 0.02), 0.07, db=-12, fade_in=0.003, fx=[bp(rng.uniform(3000, 4500), 1.2)])
	s.bus(comp(-18, 3, 1, 50, 2), limit())


@sfx("jump", 0.28)
def jump(s, v, rng):
	s.noise(0.0, 0.08, color=PINK, db=0, fx=[lp(900)])
	s.noise(0.02, 0.24, color=PINK, db=-3, fade_in=0.05, fx=[bp(500, 1.2)],
		auto={"a:freq": [(0.02, 400), (0.26, 1600)]})
	s.bus(limit())


@sfx("land", 0.32)
def land(s, v, rng):
	s.drums([(KICK, 0.0, 120)], db=0, kick_tune=-2, kick_decay=160)
	s.noise(0.0, 0.18, color=PINK, db=-1, fx=[lp(800)])
	s.noise(0.005, 0.08, db=-14, fade_in=0.002, fx=[bp(3000, 1.2)])
	s.bus(comp(-18, 4, 1, 80, 3), limit())


@sfx("pickup_health", 0.6)
def pickup_health(s, v, rng):
	notes = [523.25, 659.25, 783.99, 1046.5]
	s.synth(synth(TRIANGLE, 260, wave2=SINE, semis=12, mix=25),
		[(hz(f), k * 0.055, 0.25, 100) for k, f in enumerate(notes)], db=0)
	s.bus(delay(70, 25, 20, 5000), plate(14, 1.0), limit())


@sfx("pickup_ammo", 0.4)
def pickup_ammo(s, v, rng):
	s.drums([(RIM, 0.0, 110), (RIM, 0.06, 100)], db=0)
	s.synth(synth(SINE, 200, wave2=SINE, semis=19, mix=30), [(hz(1850), 0.1, 0.25, 90)], db=-8,
		fx=[ring(2600, 25)])
	s.noise(0.0, 0.16, color=PINK, db=-14, fade_in=0.01, fx=[bp(2500, 1.5)])
	s.bus(room(8, 0.3, 15), limit())


@sfx("grenade_throw", 0.38)
def grenade_throw(s, v, rng):
	s.drums([(RIM, 0.0, 100), (HAT, 0.0, 70)], db=0, hat_decay=30)  # pin out
	whoosh(s, dur=0.3, f0=700, f1=2600, q=1.5, db=0)
	s.bus(limit())


@sfx("grenade_bounce", 0.3, takes=2)
def grenade_bounce(s, v, rng):
	f = 880.0 if v == 0 else 760.0
	# A hollow metal clank: inharmonic partials from the ring modulator.
	s.synth(synth(SINE, 180, wave2=SINE, semis=8, detune=30, mix=40), [(hz(f), 0.0, 0.2, 110)],
		db=0, fx=[ring(f * 1.63, 40)])
	s.drums([(TOM_HIGH, 0.0, 100)], db=-6, tom_tune=4 - 3 * v, tom_decay=60)
	s.noise(0.0, 0.05, color=PINK, db=-10, fx=[lp(1600)])
	s.bus(room(8, 0.4, 20), limit())


@sfx("weapon_switch", 0.42)
def weapon_switch(s, v, rng):
	s.noise(0.0, 0.2, color=PINK, db=-6, fade_in=0.03, fx=[bp(1600, 1.2)])
	s.drums([(RIM, 0.12, 120), (RIM, 0.2, 100), (HAT, 0.2, 70)], db=0, hat_decay=30)
	s.bus(comp(-18, 4, 0.3, 50, 3), room(6, 0.3, 15), limit())


@sfx("ui_click", 0.08)
def ui_click(s, v, rng):
	s.synth(synth(SINE, 70, glide_ms=40), [((hz(1300), hz(950)), 0.0, 0.07, 120)], db=0)
	s.synth(synth(TRIANGLE, 8), [(hz(2600), 0.0, 0.02, 100)], db=-12)
	s.bus(limit())


@sfx("ui_hover", 0.06)
def ui_hover(s, v, rng):
	s.synth(synth(SINE, 30, attack_ms=2, glide_ms=30), [((hz(1900), hz(2100)), 0.0, 0.04, 100)], db=0)
	s.bus(limit())


@sfx("ui_buy", 0.55)
def ui_buy(s, v, rng):
	# Classic two-step coin: B5 blip then a ringing E6.
	s.synth(synth(SQUARE, 380, sustain=0, cutoff=6000), [(hz(987.8), 0.0, 0.07, 110),
		(hz(1318.5), 0.07, 0.45, 110)], db=0)
	s.synth(synth(SINE, 300), [(hz(2637), 0.07, 0.4, 90)], db=-12)
	s.bus(plate(10, 0.8), limit())


@sfx("ui_error", 0.32)
def ui_error(s, v, rng):
	s.synth(synth(SQUARE, 120, wave2=SAW, detune=15, mix=40, sustain=80, release_ms=20, cutoff=1800),
		[(hz(196), 0.0, 0.09, 110), (hz(147), 0.12, 0.13, 110)], db=0)
	s.bus(sat(4, 3000), limit())


@sfx("level_up", 1.2)
def level_up(s, v, rng):
	lead = synth(SQUARE, 120, sustain=30, release_ms=60, cutoff=6500, wave2=SQUARE, detune=8, mix=30)
	s.synth(lead, [(hz(f), k * 0.075, 0.1, 110) for k, f in enumerate([523.25, 659.25, 783.99, 1046.5, 1318.5])],
		db=0)
	s.synth(synth(SQUARE, 700, sustain=0, release_ms=300, cutoff=6500, wave2=SQUARE, detune=8, mix=30),
		[(hz(f), 0.4, 0.72, 100) for f in (1046.5, 1318.5, 1568.0)], db=-4)
	s.synth(synth(TRIANGLE, 700), [(hz(261.6), 0.4, 0.72, 110)], db=-2)
	s.drums([(CRASH, 0.4, 70)], db=-18, cymbal_decay=900)
	s.bus(delay(110, 25, 20, 4000), plate(14, 1.2), limit())


@sfx("coins", 0.7)
def coins(s, v, rng):
	notes = [(hz(rng.uniform(1900, 2600)), k * 0.07 + rng.uniform(0, 0.03), 0.25, rng.randint(80, 120))
		for k in range(5)]
	s.synth(synth(SINE, 180, wave2=SINE, semis=19, detune=20, mix=35), notes, db=0, fx=[ring(3100, 30)])
	s.bus(room(10, 0.4, 20, 9000), limit())


@sfx("countdown", 0.22)
def countdown(s, v, rng):
	s.synth(synth(SQUARE, 160, sustain=60, release_ms=30, cutoff=4000), [(hz(880), 0.0, 0.16, 110)], db=0)
	s.synth(synth(SINE, 120), [(hz(1760), 0.0, 0.16, 100)], db=-8)
	s.bus(limit())


@sfx("match_start", 1.7)
def match_start(s, v, rng):
	# A brass horn chord: detuned saws with a slow attack, darkened by the filter.
	horn = synth(SAW, 900, detune=12, mix=50, attack_ms=60, sustain=80, release_ms=250,
		cutoff=1700, filter_env=30, filter_decay_ms=400)
	s.synth(horn, [(hz(f), 0.0, 1.0, 110) for f in (220.0, 329.6, 440.0)], db=0)
	s.synth(synth(TRIANGLE, 1000, attack_ms=50, sustain=80, release_ms=200), [(hz(110), 0.0, 1.0, 110)], db=-2)
	s.drums([(KICK, 0.0, 110), (CRASH, 0.0, 70)], db=-8, kick_tune=-5, kick_decay=600, cymbal_decay=1200)
	s.bus(delay(150, 25, 18, 2000), plate(18, 1.6), limit())


@sfx("match_end", 1.9)
def match_end(s, v, rng):
	lead = synth(SQUARE, 110, sustain=40, release_ms=40, cutoff=5500, wave2=SQUARE, detune=8, mix=30)
	s.synth(lead, [(hz(392), k * 0.12, 0.1, 110) for k in range(3)], db=-2)
	s.synth(synth(TRIANGLE, 110, sustain=40, release_ms=40), [(hz(196), k * 0.12, 0.1, 110) for k in range(3)], db=-4)
	s.synth(synth(SQUARE, 1300, sustain=30, release_ms=400, cutoff=5500, wave2=SQUARE, detune=8, mix=30),
		[(hz(f), 0.36, 1.2, 100) for f in (523.25, 659.25, 784.0)], db=-4)
	s.synth(synth(TRIANGLE, 1400, sustain=30, release_ms=400), [(hz(130.8), 0.36, 1.2, 110)], db=-2)
	s.drums([(CRASH, 0.36, 80)], db=-14, cymbal_decay=1500)
	s.bus(delay(140, 25, 18, 3000), plate(16, 1.5), limit())


@sfx("bullet_impact", 0.3, takes=3)
def bullet_impact(s, v, rng):
	s.noise(0.0, 0.05, db=0, fx=[hp(rng.uniform(800, 1400)), lp(rng.uniform(4000, 6000))])
	s.drums([(TOM_HIGH, 0.0, 110)], db=-4, tom_tune=rng.uniform(-6, 2), tom_decay=60)
	s.noise(0.01, 0.25, color=PINK, db=-10, fade_in=0.005, fx=[lp(rng.uniform(1200, 2000))])
	# A few chips of debris.
	for k in range(2 + v):
		s.noise(rng.uniform(0.03, 0.16), 0.02, db=-18, fx=[bp(rng.uniform(2500, 5000), 2.0)])
	s.bus(sat(6, 7000), comp(-18, 4, 0.3, 60, 3), limit())


@sfx("whizz", 0.28)
def whizz(s, v, rng):
	# Flyby: a narrow noise band and a faint tone that both drop in pitch, panning past.
	s.noise(0.0, 0.25, db=0, fade_in=0.15, fade_out=0.1, shape="s-curve", fx=[bp(4200, 3.0)],
		auto={"a:freq": [(0.0, 4200), (0.25, 1300)]})
	s.synth(synth(SINE, 250, attack_ms=60, glide_ms=220), [((hz(1900), hz(800)), 0.0, 0.24, 80)], db=-14)
	s.bus(("auto_pan", {"rate": 960, "width": 70, "trigger": 1, "waveform": 0}), limit())


@sfx("spawn", 0.85)
def spawn(s, v, rng):
	s.synth(synth(SINE, 500, attack_ms=30, glide_ms=450), [((hz(260), hz(1040)), 0.0, 0.5, 100)], db=-2)
	s.synth(synth(SINE, 280, wave2=SINE, semis=12, mix=30),
		[(hz(f), 0.12 + k * 0.06, 0.25, 100) for k, f in enumerate([1046.5, 1318.5, 1568.0, 2093.0])],
		db=-2, fx=[ring(3500, 12)])
	s.bus(delay(90, 35, 22, 5000), plate(20, 1.4), limit())


@sfx("streak_reward", 1.6)
def streak_reward(s, v, rng):
	# A rising brass fanfare over a snare roll.
	brass = synth(SAW, 200, detune=10, mix=50, sustain=40, release_ms=80, cutoff=3800, filter_env=30)
	s.synth(brass, [(hz(f), k * 0.09, 0.15, 110) for k, f in enumerate([392.0, 523.25, 659.25, 784.0])], db=0)
	s.synth(synth(SAW, 900, detune=10, mix=50, attack_ms=10, sustain=40, release_ms=300, cutoff=3800),
		[(hz(f), 0.36, 0.8, 100) for f in (523.25, 659.25, 784.0, 1046.5)], db=-3)
	s.drums([(SNARE, k * 0.045, 60 + 7 * k) for k in range(8)] + [(CRASH, 0.36, 90)], db=-8,
		snare_decay=90, cymbal_decay=1000)
	s.bus(delay(120, 25, 18, 3000), plate(16, 1.4), limit())


@sfx("radar_sweep", 1.6)
def radar_sweep(s, v, rng):
	# Sonar: a pinging sine with a long, bright tail, then a fainter second ping.
	ping = synth(SINE, 900, wave2=SINE, semis=12, mix=15, release_ms=500)
	s.synth(ping, [(hz(1320), 0.0, 1.0, 120), (hz(1320), 0.45, 0.8, 70)], db=0)
	s.bus(delay(180, 45, 30, 4000), plate(25, 2.0), limit())


@sfx("shield_hit", 0.3)
def shield_hit(s, v, rng):
	# A glassy shimmer where a hit lands on the Overshield.
	s.synth(synth(TRIANGLE, 200, glide_ms=180), [((hz(1900), hz(1500)), 0.0, 0.2, 110)], db=0,
		fx=[("chorus", {"rate": 3.0, "depth": 60, "mix": 50})])
	s.synth(synth(SINE, 200, wave2=SINE, semis=19, mix=30), [(hz(2700), 0.0, 0.22, 100)], db=-6,
		fx=[ring(3700, 25)])
	s.drums([(HAT, 0.0, 90)], db=-10, hat_decay=30)
	s.bus(plate(12, 0.8, 12000), limit())


@sfx("shield_break", 0.85)
def shield_break(s, v, rng):
	# The Overshield shattering: a falling glassy sweep and tinkling shards.
	s.synth(synth(TRIANGLE, 450, glide_ms=420), [((hz(2200), hz(500)), 0.0, 0.45, 110)], db=0,
		fx=[("flanger", {"rate": 2.0, "mix": 40})])
	s.noise(0.0, 0.3, db=-4, fx=[hp(2500)])
	s.drums([(CRASH, 0.0, 90)], db=-10, cymbal_decay=500)
	shards = [(hz(rng.uniform(2500, 4200)), 0.05 + k * 0.06 + rng.uniform(0, 0.03), 0.2, rng.randint(70, 110))
		for k in range(6)]
	s.synth(synth(SINE, 160, wave2=SINE, semis=19, detune=25, mix=35), shards, db=-6, fx=[ring(4400, 30)])
	s.bus(plate(16, 1.0, 12000), limit())


@sfx("bomber_warning", 2.4)
def bomber_warning(s, v, rng):
	# Incoming airstrike: two siren wails and the whistle of falling bombs.
	siren = synth(SQUARE, 600, wave2=SAW, detune=10, mix=40, attack_ms=30, sustain=100, release_ms=40,
		cutoff=3000, glide_ms=500)
	s.synth(siren, [((hz(520), hz(880)), k * 0.6, 0.58, 110) for k in range(2)], db=0)
	s.synth(synth(SINE, 800, attack_ms=50, sustain=100, release_ms=50, glide_ms=750),
		[((hz(2400), hz(700)), 1.2, 0.78, 100)], db=-4)
	s.bus(delay(200, 30, 25, 2500), room(18, 1.4, 70), limit())


@sfx("ping", 0.45)
def ping(s, v, rng):
	# A teammate marked a spot: two soft rising blips.
	bell = synth(SINE, 220, wave2=SINE, semis=12, mix=20)
	s.synth(bell, [(hz(1174.7), 0.0, 0.18, 100), (hz(1568.0), 0.09, 0.3, 110)], db=0)
	s.bus(plate(14, 0.9), limit())


@sfx("ping_enemy", 0.45)
def ping_enemy(s, v, rng):
	# A teammate marked an enemy: a sharper falling double beep.
	beep = synth(SQUARE, 110, sustain=50, release_ms=30, cutoff=5000, glide_ms=90)
	s.synth(beep, [((hz(1760), hz(1480)), k * 0.13, 0.11, 110) for k in range(2)], db=0)
	s.bus(room(8, 0.4, 20), limit())


@sfx("spray", 0.62)
def spray(s, v, rng):
	# A can rattled twice, then a short hiss of paint.
	s.drums([(RIM, 0.0, 90), (HAT, 0.0, 80), (RIM, 0.07, 100), (HAT, 0.07, 80)], db=0, hat_decay=40)
	s.noise(0.15, 0.45, db=-10, fade_in=0.02, fade_out=0.15, shape="linear", fx=[hp(5000), lp(11000)])
	s.bus(comp(-18, 3, 1, 80, 2), limit())


@sfx("jump_pad", 0.5)
def jump_pad(s, v, rng):
	# A springy thump and a rising whoosh.
	s.drums([(KICK, 0.0, 127)], db=0, kick_tune=3, kick_decay=150)
	s.synth(synth(TRIANGLE, 300, glide_ms=250), [((hz(300), hz(900)), 0.0, 0.3, 100)], db=-6,
		fx=[("phaser", {"rate": 3.0, "mix": 40})])
	s.noise(0.02, 0.4, color=PINK, db=-6, fade_in=0.03, fade_out=0.15, fx=[bp(1500, 1.5)],
		auto={"a:freq": [(0.02, 1500), (0.42, 5000)]})
	s.bus(comp(-18, 4, 1, 80, 3), room(8, 0.5, 30), limit())


# --- Runner ------------------------------------------------------------------------------------


def take_paths(name: str, takes: int) -> list[str]:
	return [name] if takes == 1 else [f"{name}_{k}" for k in range(takes)]


def build(sc: SoundCraft, name: str, keep_sessions: bool) -> list[dict]:
	length, takes, recipe = RECIPES[name]
	results = []
	for take, stem in enumerate(take_paths(name, takes)):
		rng = random.Random(f"{name}:{take}")
		s = Sound(sc, stem, length)
		recipe(s, take, rng)
		session = SESSION_DIR / stem / f"{stem}.scraft" if keep_sessions else None
		if session:
			session.parent.mkdir(parents=True, exist_ok=True)
		results.append(s.bounce(OUT_DIR / f"{stem}.wav", session))
		print(f"{stem}: {results[-1]['seconds']:.2f}s peak {results[-1]['peak_db']:.1f} dB", flush=True)
	return results


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--port", type=int, default=47123)
	ap.add_argument("--only", nargs="*", help="sound names to build (default: all)")
	ap.add_argument("--no-sessions", action="store_true", help="don't save the SoundCraft sessions")
	args = ap.parse_args()
	names = args.only or list(RECIPES)
	unknown = [n for n in names if n not in RECIPES]
	if unknown:
		print(f"unknown sounds: {', '.join(unknown)}", file=sys.stderr)
		return 2
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	sc = SoundCraft(args.port)
	for name in names:
		build(sc, name, not args.no_sessions)
	return 0


if __name__ == "__main__":
	sys.exit(main())
