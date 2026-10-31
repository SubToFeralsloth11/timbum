# SFX PACK

**Status: not in the game yet.** These are new sound effects made in **SoundCraft**, waiting to
replace the procedural ones. The game still synthesises its effects with `SfxBank`
(`scripts/audio/sfx_bank.gd`). This folder has a `.gdignore`, so Godot doesn't parse, import or
export anything in it. The pack doesn't include music.

## What's here

| Path | What |
|---|---|
| `sounds/` | 68 WAVs (48 kHz, 16-bit stereo, peak-normalised to -0.1 dBFS): one file per sound in the `Sfx` contract, plus extra takes for 4 sounds. 8.6 MB total. |
| `soundcraft_sfx.py` | Builds every sound in SoundCraft through its control server, and rebuilds any of them after a change. |

Each sound is its own SoundCraft session, made from these parts:
- noise from the Signal Generator, shaped with clip fades, EQ and filter-sweep automation
- Subtractive Synth and Drum Synth tracks playing MIDI, with glides for pitch sweeps
- a bus of SoundCraft's built-in effects: saturator, compressor, slap delay, room/plate reverb,
  ring mod, and the Maximizer to make gunshots and explosions punchier

## Rebuilding / tweaking

```sh
/Applications/SoundCraft.app/Contents/MacOS/SoundCraft --no-audio --control 47123   # leave running
python3 sfx_pack/soundcraft_sfx.py                       # all sounds
python3 sfx_pack/soundcraft_sfx.py --only shot_rifle     # just one
```

Every build also saves the sessions to `build/sfx_sessions/<name>/<name>.scraft` (gitignored).
Open one in SoundCraft to tweak it by hand.

## Files ↔ sound names

Every name in `SfxBank.NAMES` has exactly one file, `sounds/<name>.wav`, except the sounds with
several takes. Those use `sounds/<name>_<take>.wav`, matching `SfxBank.VARIANTS`:

| Sound | Takes |
|---|---|
| `footstep` | `footstep_0` … `footstep_3` |
| `bullet_impact` | `bullet_impact_0` … `bullet_impact_2` |
| `knife_hit` | `knife_hit_0`, `knife_hit_1` |
| `grenade_bounce` | `grenade_bounce_0`, `grenade_bounce_1` |

## How to add it to the game (for whoever does it)

1. Move `sounds/*.wav` to `audio/sfx/` and run `godot --headless --path . --import` so Godot
   imports them. Consider setting `edit/trim=true` in the `.import` files so trailing silence is
   cut.
2. In `scripts/autoload/sfx.gd`:
   - When the autoload starts (not headless), `load()` every take into `_streams` (name → array
     of `AudioStream`).
   - In `play()`, drop the `_render_now` fallback and type the stream as `AudioStream`, not
     `AudioStreamWAV`. Warn once for an unknown name, as it does now.
   - Move `NAMES`, `VARIANTS`, `UNIT_SIZE`, `DEFAULT_UNIT_SIZE` and `JITTER` out of `SfxBank`
     unchanged, and swap in the **new `GAIN_DB`** below.
3. Stop rendering effects: create `AudioJob` for the results fanfare only, and remove its `sfx`
   path.
4. Delete `scripts/audio/sfx_bank.gd` (and its `.uid`). In `Synth`, `click`, `bell`, `lowpass`,
   `echo` and `drive` become unused (only `Chiptune` still uses `Synth`), so delete them too.
5. Update `docs/ARCHITECTURE.md` (the Audio row and the `Sfx` section) and the README line saying
   all sound effects are procedural.

### New `GAIN_DB`

These keep the old mix balance. Each new file was loudness-matched against the old synthesised
sound (an approximately K-weighted, 100 ms RMS measure). The values replace the old ones because
the new files are normalised differently. Gains are capped at 0 dB, so the heaviest guns (sniper,
minigun, LMG, revolver, DMR, crossbow) and the explosion come out 0.5 to 2 dB quieter than before.

```gdscript
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
	&"shot_crossbow": 0.0, &"shot_drum_shotgun": 0.0, &"shot_carbine": -1.0, &"shot_burst_smg": -4.0,
	&"shot_minigun": 0.0, &"swing_blunt": -10.0, &"swing_heavy": -11.0, &"swing_blade": -8.0,
}
```

If you rebuild the sounds after changing a recipe, measure the levels again.

## Not checked yet

- Nobody has listened to the sounds in a match. They were checked from spectrograms, envelopes and
  levels compared against the old synthesised sounds, not by ear.
- `whizz` pans from left to right inside the file, which suits the flat (UI) voice. On a
  positional 3D voice Godot mixes it down, so the pan is lost there.
