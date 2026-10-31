# SFX PACK

**Status: in the game.** These sound effects were made in **SoundCraft** and replaced the
procedural ones. The WAVs live in `audio/sfx/`, and the `Sfx` autoload (`scripts/autoload/sfx.gd`)
loads them all at startup. This folder holds only the build script and this README. It has a
`.gdignore`, so Godot doesn't parse, import or export anything in it. The pack doesn't include
music.

## What's here

| Path | What |
|---|---|
| `../audio/sfx/` | 68 WAVs (48 kHz, 16-bit stereo, peak-normalised to -0.1 dBFS): one file per sound in the `Sfx` contract, plus extra takes for 4 sounds. 8.6 MB total. |
| `soundcraft_sfx.py` | Builds every sound in SoundCraft through its control server and bounces it into `audio/sfx/`. Also rebuilds any of them after a change. |

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
Open one in SoundCraft to tweak it by hand. After a rebuild, run `godot --headless --path . --import`
so Godot reimports the changed files.

## Files ↔ sound names

Every name in `Sfx.NAMES` has exactly one file, `audio/sfx/<name>.wav`, except the sounds with
several takes. Those use `audio/sfx/<name>_<take>.wav`, matching `Sfx.VARIANTS`:

| Sound | Takes |
|---|---|
| `footstep` | `footstep_0` … `footstep_3` |
| `bullet_impact` | `bullet_impact_0` … `bullet_impact_2` |
| `knife_hit` | `knife_hit_0`, `knife_hit_1` |
| `grenade_bounce` | `grenade_bounce_0`, `grenade_bounce_1` |

## How it is wired into the game

- The `.import` files set `edit/trim=true`, so Godot cuts trailing silence on import.
- When `Sfx` starts (not headless), it `load()`s every take into `_streams` (name → array of
  `AudioStream`). `play()` picks a random take and warns once for an unknown name.
- `Sfx.NAMES`, `VARIANTS`, `UNIT_SIZE`, `DEFAULT_UNIT_SIZE` and `JITTER` came over unchanged from
  the old `SfxBank`. `Sfx.GAIN_DB` holds the levels described below.
- Only the results fanfare (a chiptune) is still rendered, by one `AudioJob`.

To add a sound, add a recipe to `soundcraft_sfx.py`, build it, put its name in `Sfx.NAMES`
(and in `Sfx.VARIANTS` if it has several takes), and give it a `Sfx.GAIN_DB` entry.

### Levels (`Sfx.GAIN_DB`)

These keep the old mix balance. Each file was loudness-matched against the old synthesised sound
(an approximately K-weighted, 100 ms RMS measure). The values differ from the old ones because the
files are normalised differently. Gains are capped at 0 dB, so the heaviest guns (sniper, minigun,
LMG, revolver, DMR, crossbow) and the explosion come out 0.5 to 2 dB quieter than the old
synthesised sounds.

If you rebuild the sounds after changing a recipe, measure the levels again.

## Not checked yet

- Nobody has listened to the sounds in a match. They were checked from spectrograms, envelopes and
  levels compared against the old synthesised sounds, not by ear.
- `whizz` pans from left to right inside the file, which suits the flat (UI) voice. On a
  positional 3D voice Godot mixes it down, so the pan is lost there.
