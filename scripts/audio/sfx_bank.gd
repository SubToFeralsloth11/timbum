class_name SfxBank
extends RefCounted
## Recipes for every sound effect, rendered with Synth into normalised 16-bit streams.
## Thread-safe: each render uses its own RandomNumberGenerator.

const W := Synth.Wave

## Every sound name in the Sfx contract, in render order (cheap UI sounds first).
const NAMES: Array[StringName] = [
	&"ui_hover", &"ui_click", &"ui_buy", &"ui_error", &"hit_marker", &"headshot", &"kill_confirm",
	&"countdown", &"coins", &"level_up", &"match_start", &"match_end", &"spawn",
	&"footstep", &"jump", &"land", &"hurt", &"death", &"weapon_switch", &"reload", &"dry_fire",
	&"knife_swing", &"knife_hit", &"pickup_health", &"pickup_ammo", &"grenade_throw", &"grenade_bounce",
	&"bullet_impact", &"whizz", &"shot_pistol", &"shot_revolver", &"shot_smg", &"shot_rifle",
	&"shot_shotgun", &"shot_sniper", &"shot_lmg", &"shot_rocket", &"explosion",
	&"shot_suppressed", &"shot_dmr", &"slide", &"grapple_fire", &"smoke_pop", &"flashbang",
]

## Sounds rendered in several takes; one is picked at random per play.
const VARIANTS := {&"footstep": 4, &"bullet_impact": 3, &"knife_hit": 2, &"grenade_bounce": 2}

## Default playback gain (dB) so the normalised streams sit at sensible relative levels.
const GAIN_DB := {
	&"ui_hover": -16.0, &"ui_click": -9.0, &"ui_buy": -6.0, &"ui_error": -8.0,
	&"hit_marker": -7.0, &"headshot": -5.0, &"kill_confirm": -5.0, &"countdown": -7.0,
	&"coins": -7.0, &"level_up": -5.0, &"match_start": -4.0, &"match_end": -4.0, &"spawn": -8.0,
	&"footstep": -12.0, &"jump": -12.0, &"land": -9.0, &"hurt": -5.0, &"death": -4.0,
	&"weapon_switch": -9.0, &"reload": -7.0, &"dry_fire": -8.0, &"knife_swing": -7.0,
	&"knife_hit": -5.0, &"pickup_health": -6.0, &"pickup_ammo": -6.0, &"grenade_throw": -8.0,
	&"grenade_bounce": -7.0, &"bullet_impact": -9.0, &"whizz": -8.0,
	&"shot_pistol": -3.0, &"shot_revolver": -1.5, &"shot_smg": -4.0, &"shot_rifle": -2.5,
	&"shot_shotgun": -1.0, &"shot_sniper": 0.0, &"shot_lmg": -2.0, &"shot_rocket": -2.0, &"explosion": 0.0,
	&"shot_suppressed": -6.0, &"shot_dmr": -1.0, &"slide": -9.0, &"grapple_fire": -6.0,
	&"smoke_pop": -5.0, &"flashbang": 0.0,
}

## Reference distance (m) for positional playback: loud sounds carry across a ~60 m map,
## small ones fade within a few metres.
const UNIT_SIZE := {
	&"shot_pistol": 14.0, &"shot_revolver": 16.0, &"shot_smg": 13.0, &"shot_rifle": 15.0,
	&"shot_shotgun": 16.0, &"shot_sniper": 24.0, &"shot_lmg": 16.0, &"shot_rocket": 16.0,
	&"explosion": 26.0, &"footstep": 4.0, &"jump": 4.0, &"land": 5.0, &"bullet_impact": 5.0,
	&"whizz": 3.0, &"grenade_bounce": 6.0, &"reload": 4.0, &"dry_fire": 3.0, &"weapon_switch": 3.0,
	&"shot_suppressed": 5.0, &"shot_dmr": 20.0, &"slide": 5.0, &"grapple_fire": 6.0,
	&"smoke_pop": 10.0, &"flashbang": 24.0,
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
}


## Renders every take of `sound` as normalised streams (empty if the name is unknown).
static func render(sound: StringName) -> Array[AudioStreamWAV]:
	var out: Array[AudioStreamWAV] = []
	if not NAMES.has(sound):
		return out
	for v in int(VARIANTS.get(sound, 1)):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(sound)) + v * 7919
		out.append(Synth.to_stream(_render_one(sound, v, rng)))
	return out


static func _render_one(sound: StringName, v: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	match sound:
		&"shot_suppressed":
			# A suppressed .22: no crack, a dull puff and the action clacking.
			var b := Synth.make(0.28)
			Synth.noise(b, rng, 0.0, 0.12, 0.9, 1400.0, 500.0, 120.0, 0.001, 0.035)
			Synth.tone(b, 0.0, 0.08, 160.0, 90.0, 0.35, W.SINE, 0.001, 0.03)
			Synth.click(b, rng, 0.03, 0.45, 2900.0)
			return b
		&"shot_dmr":
			var b := _gun(rng, 1.0, 1.0, 0.012, 2600.0, 0.07, 120.0, 1.15, 0.1, 0.14, 0.38, 2.4)
			Synth.click(b, rng, 0.06, 0.15, 2200.0)
			return b
		&"slide":
			# Fabric and grit scraping along the floor.
			var b := Synth.make(0.6)
			Synth.noise(b, rng, 0.0, 0.55, 0.8, 2600.0, 900.0, 300.0, 0.03, 0.25)
			Synth.noise(b, rng, 0.0, 0.4, 0.35, 6000.0, 3000.0, 1800.0, 0.02, 0.15)
			return b
		&"grapple_fire":
			# Spring launch, then the line whirring out.
			var b := Synth.make(0.45)
			Synth.click(b, rng, 0.0, 0.9, 1800.0)
			Synth.tone(b, 0.0, 0.06, 240.0, 110.0, 0.6, W.SINE, 0.001, 0.025)
			Synth.noise(b, rng, 0.02, 0.4, 0.45, 5200.0, 2600.0, 1600.0, 0.01, 0.16)
			Synth.tone(b, 0.02, 0.38, 900.0, 520.0, 0.12, W.TRIANGLE, 0.01, 0.15)
			return b
		&"smoke_pop":
			# A muffled pop and a long hiss of smoke pouring out.
			var b := Synth.make(2.0)
			Synth.tone(b, 0.0, 0.12, 180.0, 70.0, 0.7, W.SINE, 0.001, 0.04)
			Synth.noise(b, rng, 0.0, 0.08, 0.6, 2000.0, 600.0, 0.0, 0.001, 0.03)
			Synth.noise(b, rng, 0.05, 1.9, 0.5, 7000.0, 3500.0, 1200.0, 0.15, 0.9)
			return b
		&"flashbang":
			# Very sharp bang with a bright ringing tail.
			var b := Synth.make(1.6)
			Synth.noise(b, rng, 0.0, 0.04, 1.6, 12000.0, 6000.0, 1500.0, 0.0002, 0.01)
			Synth.noise(b, rng, 0.0, 0.6, 1.0, 3000.0, 400.0, 0.0, 0.002, 0.12)
			Synth.tone(b, 0.0, 0.3, 110.0, 45.0, 0.9, W.SINE, 0.001, 0.08)
			Synth.tone(b, 0.05, 1.5, 3900.0, 3850.0, 0.08, W.SINE, 0.01, 0.6)
			Synth.drive(b, 2.2)
			return b
		&"shot_pistol":
			return _gun(rng, 0.55, 1.0, 0.012, 2600.0, 0.05, 180.0, 0.9, 0.06, 0.09, 0.3, 2.0)
		&"shot_revolver":
			return _gun(rng, 0.9, 1.0, 0.016, 1800.0, 0.09, 120.0, 1.2, 0.11, 0.12, 0.35, 2.4)
		&"shot_smg":
			return _gun(rng, 0.32, 0.9, 0.007, 3600.0, 0.022, 230.0, 0.55, 0.03, 0.06, 0.2, 1.8)
		&"shot_rifle":
			var b := _gun(rng, 0.7, 1.0, 0.01, 3000.0, 0.045, 150.0, 0.9, 0.07, 0.11, 0.33, 2.2)
			Synth.click(b, rng, 0.035, 0.12, 2400.0)
			return b
		&"shot_shotgun":
			var b := _gun(rng, 1.0, 0.8, 0.02, 2000.0, 0.12, 90.0, 1.3, 0.15, 0.14, 0.4, 2.6)
			# Pellet spread smears the crack into a few tight transients.
			for k in 3:
				Synth.noise(b, rng, 0.003 + k * 0.004, 0.03, 0.35, 8000.0, 3000.0, 1500.0, 0.0005, 0.006)
			return b
		&"shot_sniper":
			var b := Synth.make(1.7)
			# Supersonic crack: a near-instant bright transient ahead of the muzzle blast.
			Synth.noise(b, rng, 0.0, 0.05, 1.6, 11000.0, 6000.0, 2500.0, 0.0002, 0.006)
			_gun_layers(b, rng, 1.0, 0.02, 3000.0, 0.08, 110.0, 1.3, 0.13)
			Synth.echo(b, 0.23, 0.5, 0.35, 1400.0)
			Synth.drive(b, 2.8)
			return b
		&"shot_lmg":
			return _gun(rng, 0.6, 1.0, 0.01, 2600.0, 0.06, 130.0, 1.2, 0.085, 0.1, 0.3, 2.4)
		&"shot_rocket":
			var b := Synth.make(1.3)
			Synth.tone(b, 0.0, 0.3, 85.0, 40.0, 1.0, W.SINE, 0.002, 0.09)
			Synth.noise(b, rng, 0.0, 0.08, 0.6, 3000.0, 900.0, 0.0, 0.001, 0.03)
			# Motor whoosh: a rushing band of noise that brightens as it leaves.
			Synth.noise(b, rng, 0.01, 1.25, 0.9, 500.0, 2600.0, 250.0, 0.06, 0.45)
			Synth.noise(b, rng, 0.02, 1.0, 0.25, 6000.0, 8000.0, 3000.0, 0.04, 0.3)
			Synth.echo(b, 0.13, 0.3, 0.25, 1800.0)
			Synth.drive(b, 1.6)
			return b
		&"explosion":
			var b := Synth.make(2.6)
			Synth.tone(b, 0.0, 1.2, 75.0, 24.0, 1.4, W.SINE, 0.002, 0.35)
			Synth.noise(b, rng, 0.0, 2.5, 1.3, 420.0, 70.0, 0.0, 0.004, 0.6)
			Synth.noise(b, rng, 0.0, 0.25, 0.8, 6000.0, 1200.0, 300.0, 0.0005, 0.045)
			# Debris crackle settling after the blast.
			for k in 14:
				var t := rng.randf_range(0.08, 1.3)
				Synth.noise(b, rng, t, 0.04, rng.randf_range(0.08, 0.2) * (1.4 - t), 4500.0, 2000.0, 800.0, 0.0005, 0.008)
			Synth.echo(b, 0.21, 0.35, 0.3, 900.0)
			Synth.drive(b, 2.4)
			return b
		&"reload":
			var b := Synth.make(0.95)
			# Mag release, mag out, rattle, mag seated, bolt back and forward.
			Synth.click(b, rng, 0.03, 0.6, 2600.0)
			Synth.click(b, rng, 0.07, 0.4, 2100.0)
			Synth.noise(b, rng, 0.2, 0.15, 0.15, 3000.0, 2000.0, 600.0, 0.03, 0.05)
			Synth.tone(b, 0.48, 0.08, 160.0, 100.0, 0.4, W.SINE, 0.001, 0.02)
			Synth.click(b, rng, 0.48, 0.8, 2300.0)
			Synth.click(b, rng, 0.5, 0.4, 3000.0)
			Synth.noise(b, rng, 0.7, 0.05, 0.12, 4000.0, 2500.0, 900.0, 0.01, 0.02)
			Synth.click(b, rng, 0.74, 0.7, 2800.0)
			Synth.click(b, rng, 0.83, 0.9, 2400.0)
			return b
		&"dry_fire":
			var b := Synth.make(0.16)
			Synth.click(b, rng, 0.0, 0.8, 3400.0)
			Synth.click(b, rng, 0.018, 0.4, 2600.0)
			return b
		&"knife_swing":
			var b := Synth.make(0.32)
			Synth.noise(b, rng, 0.0, 0.3, 1.0, 900.0, 3800.0, 450.0, 0.09, 0.05)
			Synth.noise(b, rng, 0.04, 0.2, 0.3, 5000.0, 7000.0, 2500.0, 0.05, 0.04)
			return b
		&"knife_hit":
			var b := Synth.make(0.3)
			var f := 150.0 if v == 0 else 125.0
			Synth.tone(b, 0.0, 0.2, f, f * 0.4, 1.0, W.SINE, 0.001, 0.045)
			Synth.noise(b, rng, 0.0, 0.12, 0.7, 1300.0, 300.0, 0.0, 0.001, 0.03)
			Synth.noise(b, rng, 0.0, 0.03, 0.3, 4000.0, 2000.0, 1000.0, 0.0005, 0.006)
			Synth.drive(b, 1.5)
			return b
		&"hit_marker":
			var b := Synth.make(0.09)
			Synth.tone(b, 0.0, 0.08, 2700.0, 2500.0, 0.8, W.SINE, 0.0005, 0.014)
			Synth.noise(b, rng, 0.0, 0.01, 0.4, 9000.0, 7000.0, 3000.0, 0.0003, 0.003)
			return b
		&"headshot":
			var b := Synth.make(0.55)
			Synth.bell(b, 0.0, 0.55, 1760.0, 0.8, 0.14)
			Synth.tone(b, 0.0, 0.06, 3500.0, 3300.0, 0.25, W.SINE, 0.0005, 0.01)
			return b
		&"kill_confirm":
			var b := Synth.make(0.75)
			Synth.bell(b, 0.0, 0.3, 1318.5, 0.7, 0.12)
			Synth.tone(b, 0.0, 0.25, 659.3, 659.3, 0.18, W.TRIANGLE, 0.002, 0.1)
			Synth.bell(b, 0.09, 0.65, 1975.5, 0.8, 0.22)
			Synth.tone(b, 0.09, 0.5, 987.8, 987.8, 0.2, W.TRIANGLE, 0.002, 0.18)
			return b
		&"hurt":
			var b := Synth.make(0.32)
			Synth.tone(b, 0.0, 0.2, 280.0, 150.0, 0.6, W.TRIANGLE, 0.004, 0.08)
			Synth.tone(b, 0.0, 0.16, 140.0, 80.0, 0.8, W.SINE, 0.002, 0.05)
			Synth.noise(b, rng, 0.0, 0.1, 0.5, 1500.0, 400.0, 0.0, 0.001, 0.025)
			return b
		&"death":
			var b := Synth.make(1.0)
			Synth.tone(b, 0.0, 0.9, 360.0, 70.0, 0.35, W.SQUARE, 0.004, 0.35, 0.3)
			Synth.tone(b, 0.0, 0.9, 180.0, 40.0, 0.6, W.TRIANGLE, 0.004, 0.4)
			Synth.noise(b, rng, 0.0, 0.2, 0.6, 1200.0, 250.0, 0.0, 0.001, 0.05)
			Synth.lowpass(b, 2200.0)
			return b
		&"footstep":
			var b := Synth.make(0.17)
			var f := rng.randf_range(80.0, 110.0)
			Synth.tone(b, 0.0, 0.08, f, f * 0.6, 0.5, W.SINE, 0.002, 0.02)
			Synth.noise(b, rng, 0.0, 0.12, 0.8, rng.randf_range(800.0, 1200.0), 250.0, 60.0, 0.002, 0.025)
			# Grit/grass crunch, slightly delayed like a heel-to-toe roll.
			Synth.noise(b, rng, rng.randf_range(0.005, 0.02), 0.07, 0.25, 6000.0, 3500.0, 1800.0, 0.003, 0.015)
			return b
		&"jump":
			var b := Synth.make(0.28)
			Synth.noise(b, rng, 0.0, 0.08, 0.6, 900.0, 300.0, 60.0, 0.002, 0.02)
			Synth.noise(b, rng, 0.02, 0.24, 0.5, 500.0, 1600.0, 200.0, 0.05, 0.05)
			return b
		&"land":
			var b := Synth.make(0.32)
			Synth.tone(b, 0.0, 0.2, 115.0, 45.0, 1.0, W.SINE, 0.002, 0.06)
			Synth.noise(b, rng, 0.0, 0.18, 0.9, 800.0, 200.0, 40.0, 0.001, 0.045)
			Synth.noise(b, rng, 0.005, 0.08, 0.2, 5000.0, 3000.0, 1500.0, 0.002, 0.02)
			return b
		&"pickup_health":
			var b := Synth.make(0.5)
			var notes := [523.25, 659.25, 783.99, 1046.5]
			for k in notes.size():
				var t := k * 0.055
				Synth.tone(b, t, 0.3, notes[k], notes[k], 0.45, W.TRIANGLE, 0.002, 0.1)
				Synth.tone(b, t, 0.2, notes[k] * 2.0, notes[k] * 2.0, 0.12, W.SINE, 0.002, 0.05)
			Synth.echo(b, 0.07, 0.25, 0.2, 5000.0)
			return b
		&"pickup_ammo":
			var b := Synth.make(0.38)
			Synth.click(b, rng, 0.0, 0.7, 2200.0)
			Synth.click(b, rng, 0.06, 0.6, 2700.0)
			Synth.bell(b, 0.1, 0.27, 1850.0, 0.35, 0.05)
			Synth.noise(b, rng, 0.0, 0.16, 0.3, 2500.0, 1500.0, 400.0, 0.01, 0.04)
			return b
		&"grenade_throw":
			var b := Synth.make(0.38)
			Synth.click(b, rng, 0.0, 0.5, 3600.0)
			Synth.tone(b, 0.0, 0.12, 2400.0, 2200.0, 0.15, W.SINE, 0.001, 0.03)
			Synth.noise(b, rng, 0.06, 0.3, 0.9, 700.0, 2600.0, 300.0, 0.07, 0.05)
			return b
		&"grenade_bounce":
			var b := Synth.make(0.26)
			var f := 880.0 if v == 0 else 760.0
			Synth.tone(b, 0.0, 0.25, f, f * 0.98, 0.4, W.SINE, 0.0005, 0.035)
			Synth.tone(b, 0.0, 0.2, f * 1.63, f * 1.6, 0.25, W.SINE, 0.0005, 0.02)
			Synth.tone(b, 0.0, 0.1, f * 2.61, f * 2.6, 0.15, W.SINE, 0.0005, 0.012)
			Synth.noise(b, rng, 0.0, 0.05, 0.6, 1600.0, 500.0, 80.0, 0.0005, 0.012)
			return b
		&"weapon_switch":
			var b := Synth.make(0.36)
			Synth.noise(b, rng, 0.0, 0.2, 0.35, 2200.0, 1400.0, 300.0, 0.03, 0.05)
			Synth.click(b, rng, 0.12, 0.7, 2500.0)
			Synth.click(b, rng, 0.2, 0.5, 3100.0)
			return b
		&"ui_click":
			var b := Synth.make(0.08)
			Synth.tone(b, 0.0, 0.07, 1300.0, 950.0, 0.8, W.SINE, 0.0005, 0.018)
			Synth.tone(b, 0.0, 0.03, 2600.0, 1900.0, 0.2, W.TRIANGLE, 0.0005, 0.008)
			return b
		&"ui_hover":
			var b := Synth.make(0.05)
			Synth.tone(b, 0.0, 0.045, 1900.0, 2100.0, 0.7, W.SINE, 0.001, 0.012)
			return b
		&"ui_buy":
			var b := Synth.make(0.5)
			# Classic two-step coin: B5 blip then a ringing E6.
			Synth.tone(b, 0.0, 0.07, 987.8, 987.8, 0.4, W.SQUARE, 0.001, 0.0, 0.5)
			Synth.tone(b, 0.07, 0.42, 1318.5, 1318.5, 0.4, W.SQUARE, 0.001, 0.16, 0.5)
			Synth.bell(b, 0.07, 0.42, 2637.0, 0.2, 0.12)
			Synth.lowpass(b, 6000.0)
			return b
		&"ui_error":
			var b := Synth.make(0.3)
			Synth.tone(b, 0.0, 0.09, 196.0, 190.0, 0.6, W.SQUARE, 0.002, 0.0, 0.5)
			Synth.tone(b, 0.12, 0.13, 147.0, 140.0, 0.6, W.SQUARE, 0.002, 0.0, 0.5)
			Synth.lowpass(b, 1800.0)
			return b
		&"level_up":
			var b := Synth.make(1.15)
			var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]
			for k in notes.size():
				Synth.tone(b, k * 0.075, 0.12, notes[k], notes[k], 0.35, W.SQUARE, 0.002, 0.08, 0.25)
			for f in [1046.5, 1318.5, 1568.0]:
				Synth.tone(b, 0.4, 0.72, f, f, 0.22, W.SQUARE, 0.003, 0.3, 0.25)
			Synth.tone(b, 0.4, 0.72, 261.6, 261.6, 0.5, W.TRIANGLE, 0.003, 0.35)
			Synth.lowpass(b, 6500.0)
			Synth.echo(b, 0.11, 0.25, 0.2, 4000.0)
			return b
		&"coins":
			var b := Synth.make(0.65)
			for k in 5:
				var f := rng.randf_range(1900.0, 2600.0)
				Synth.bell(b, k * 0.07 + rng.randf_range(0.0, 0.03), 0.3, f, 0.4, 0.06)
			return b
		&"countdown":
			var b := Synth.make(0.2)
			Synth.tone(b, 0.0, 0.16, 880.0, 880.0, 0.5, W.SQUARE, 0.002, 0.0, 0.5)
			Synth.tone(b, 0.0, 0.16, 1760.0, 1760.0, 0.15, W.SINE, 0.002, 0.08)
			Synth.lowpass(b, 4000.0)
			return b
		&"match_start":
			var b := Synth.make(1.25)
			# Brass-like horn chord: detuned saws with a slow attack, darkened by a low-pass.
			for f in [220.0, 329.6, 440.0]:
				Synth.tone(b, 0.0, 1.1, f, f, 0.3, W.SAW, 0.06, 0.9)
				Synth.tone(b, 0.0, 1.1, f * 1.004, f * 1.004, 0.25, W.SAW, 0.07, 0.9)
			Synth.tone(b, 0.0, 1.1, 110.0, 110.0, 0.4, W.TRIANGLE, 0.05, 1.0)
			Synth.lowpass(b, 1700.0)
			Synth.echo(b, 0.15, 0.3, 0.25, 2000.0)
			return b
		&"match_end":
			var b := Synth.make(1.9)
			var t := 0.0
			for k in 3:
				Synth.tone(b, t, 0.11, 392.0, 392.0, 0.35, W.SQUARE, 0.002, 0.08, 0.25)
				Synth.tone(b, t, 0.11, 196.0, 196.0, 0.4, W.TRIANGLE, 0.002, 0.1)
				t += 0.12
			for f in [523.25, 659.25, 784.0]:
				Synth.tone(b, t, 1.3, f, f, 0.24, W.SQUARE, 0.004, 0.6, 0.25)
			Synth.tone(b, t, 1.3, 130.8, 130.8, 0.5, W.TRIANGLE, 0.004, 0.7)
			Synth.lowpass(b, 5500.0)
			Synth.echo(b, 0.14, 0.3, 0.22, 3000.0)
			return b
		&"bullet_impact":
			var b := Synth.make(0.3)
			var f := rng.randf_range(260.0, 360.0)
			Synth.noise(b, rng, 0.0, 0.05, 0.9, 4500.0, 900.0, 200.0, 0.0003, 0.012)
			Synth.tone(b, 0.0, 0.08, f, f * 0.4, 0.6, W.SINE, 0.0005, 0.02)
			Synth.noise(b, rng, 0.01, 0.25, 0.3, 1600.0, 500.0, 100.0, 0.005, 0.06)
			return b
		&"whizz":
			var b := Synth.make(0.26)
			# Flyby: a narrow noise band and a faint tone that both drop in pitch (doppler).
			Synth.noise(b, rng, 0.0, 0.25, 0.8, 4200.0, 1300.0, 900.0, 0.07, 0.05)
			Synth.tone(b, 0.0, 0.24, 1900.0, 800.0, 0.12, W.SINE, 0.07, 0.05)
			return b
		&"spawn":
			var b := Synth.make(0.8)
			Synth.tone(b, 0.0, 0.5, 260.0, 1040.0, 0.45, W.SINE, 0.03, 0.25)
			var notes := [1046.5, 1318.5, 1568.0, 2093.0]
			for k in notes.size():
				Synth.bell(b, 0.12 + k * 0.06, 0.3, notes[k], 0.25, 0.08)
			Synth.echo(b, 0.09, 0.35, 0.3, 5000.0)
			return b
	return Synth.make(0.01)


## Generic gunshot: crack + body + low thump, then an outdoor slap echo and saturation.
static func _gun(rng: RandomNumberGenerator, length: float, crack: float, crack_tau: float, body_lp: float,
		body_tau: float, thump_hz: float, thump_amp: float, thump_tau: float, echo_s: float, echo_fb: float,
		drv: float) -> PackedFloat32Array:
	var b := Synth.make(length)
	_gun_layers(b, rng, crack, crack_tau, body_lp, body_tau, thump_hz, thump_amp, thump_tau)
	Synth.echo(b, echo_s, echo_fb, 0.28, 1600.0)
	Synth.drive(b, drv)
	return b


static func _gun_layers(b: PackedFloat32Array, rng: RandomNumberGenerator, crack: float, crack_tau: float,
		body_lp: float, body_tau: float, thump_hz: float, thump_amp: float, thump_tau: float) -> void:
	var len_s := b.size() * Synth.INV_RATE
	Synth.noise(b, rng, 0.0, crack_tau * 6.0, crack, 9500.0, 3500.0, 700.0, 0.0003, crack_tau)
	Synth.noise(b, rng, 0.0, minf(body_tau * 7.0, len_s), 0.9, body_lp, body_lp * 0.25, 60.0, 0.0008, body_tau)
	Synth.tone(b, 0.0, minf(thump_tau * 6.0, len_s), thump_hz, thump_hz * 0.32, thump_amp, W.SINE, 0.001, thump_tau)
