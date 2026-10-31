extends Node
## Static game catalogs: weapons, cosmetics, maps. Pure data, no state.

const CATEGORIES: Array[String] = ["weapons", "skins", "hats", "outfits", "charms", "emotes", "draws", "sprays"]

## Weapon fields:
##   slot: "primary" | "secondary" | "melee"
##   damage: per bullet/pellet (rocket: direct-hit damage)
##   head_mult: headshot multiplier
##   rpm: rounds per minute; auto: hold to fire
##   mag / reserve: magazine size and starting reserve ammo
##   reload: seconds; reload_per_shell: shotgun loads shells one by one
##   pellets: bullets per shot
##   spread_hip / spread_ads: cone half-angle in degrees
##   recoil: camera pitch kick in degrees per shot
##   falloff_start / falloff_end: metres; min_mult: damage multiplier past falloff_end
##   ads_fov: field of view while aiming; scope: draws scope overlay (and hides the gun);
##     scope_style: "sniper" (default) or "marksman" (wider low-power lens, chevron)
##   move_mult: movement speed multiplier while held
##   projectile: fires a rocket instead of hitscan; splash_radius / speed
##   burst / burst_rpm: shots per trigger pull and their rate inside the burst (rpm stays the
##     average rate, which the server's fire-rate check enforces)
##   suppressed: no tracer or muzzle flash for other players, and a quiet report
##   sound: Sfx name; pitch: optional playback pitch for it
##   Melee (slot "melee", carried in the third slot and used for the quick melee): range (m of
##     reach), rpm (swing rate), damage per hit, move_mult; swing: "slash" (alternating fore- and
##     backhand), "chop" (overhead) or "sweep" (wide flat swing) picks the first- and third-person
##     animation. The knife is the default; Gun Game always ends on it.
const WEAPONS := {
	"pistol": {
		"name": "Block 9", "slot": "secondary", "price": 0,
		"desc": "Reliable sidearm. Quick to draw, quick to fire.",
		"damage": 26.0, "head_mult": 2.0, "rpm": 400.0, "auto": false,
		"mag": 12, "reserve": 72, "reload": 1.3, "pellets": 1,
		"spread_hip": 1.6, "spread_ads": 0.35, "recoil": 1.3,
		"falloff_start": 20.0, "falloff_end": 45.0, "min_mult": 0.6,
		"ads_fov": 62.0, "move_mult": 1.0, "sound": "shot_pistol",
	},
	"revolver": {
		"name": "Cuber .44", "slot": "secondary", "price": 450,
		"desc": "Heavy six-shooter. Two body shots or one to the head.",
		"damage": 55.0, "head_mult": 2.0, "rpm": 150.0, "auto": false,
		"mag": 6, "reserve": 36, "reload": 2.2, "pellets": 1,
		"spread_hip": 1.3, "spread_ads": 0.15, "recoil": 4.5,
		"falloff_start": 30.0, "falloff_end": 60.0, "min_mult": 0.7,
		"ads_fov": 55.0, "move_mult": 1.0, "sound": "shot_revolver",
	},
	"smg": {
		"name": "Bit-SMG", "slot": "primary", "price": 0,
		"desc": "Bullet hose for close quarters. Fast and mobile.",
		"damage": 18.0, "head_mult": 1.5, "rpm": 880.0, "auto": true,
		"mag": 32, "reserve": 192, "reload": 1.8, "pellets": 1,
		"spread_hip": 2.8, "spread_ads": 1.0, "recoil": 0.55,
		"falloff_start": 12.0, "falloff_end": 30.0, "min_mult": 0.55,
		"ads_fov": 60.0, "move_mult": 1.05, "sound": "shot_smg",
	},
	"rifle": {
		"name": "AR-Cube", "slot": "primary", "price": 600,
		"desc": "All-round assault rifle. Strong at every range.",
		"damage": 25.0, "head_mult": 1.8, "rpm": 640.0, "auto": true,
		"mag": 30, "reserve": 150, "reload": 2.0, "pellets": 1,
		"spread_hip": 2.2, "spread_ads": 0.45, "recoil": 0.9,
		"falloff_start": 35.0, "falloff_end": 70.0, "min_mult": 0.7,
		"ads_fov": 50.0, "move_mult": 0.97, "sound": "shot_rifle",
	},
	"shotgun": {
		"name": "Brick Buster", "slot": "primary", "price": 500,
		"desc": "Pump shotgun. Deletes anything within five blocks.",
		"damage": 13.0, "head_mult": 1.3, "rpm": 75.0, "auto": false,
		"mag": 6, "reserve": 36, "reload": 0.5, "reload_per_shell": true, "pellets": 9,
		"spread_hip": 5.5, "spread_ads": 4.2, "recoil": 5.0,
		"falloff_start": 7.0, "falloff_end": 18.0, "min_mult": 0.25,
		"ads_fov": 62.0, "move_mult": 1.0, "sound": "shot_shotgun",
	},
	"lmg": {
		"name": "Stacker LMG", "slot": "primary", "price": 800,
		"desc": "Hundred-round belt. Lock down a whole lane.",
		"damage": 22.0, "head_mult": 1.6, "rpm": 720.0, "auto": true,
		"mag": 100, "reserve": 200, "reload": 4.0, "pellets": 1,
		"spread_hip": 3.4, "spread_ads": 0.9, "recoil": 0.65,
		"falloff_start": 30.0, "falloff_end": 65.0, "min_mult": 0.65,
		"ads_fov": 52.0, "move_mult": 0.88, "sound": "shot_lmg",
	},
	"sniper": {
		"name": "Voxel Longshot", "slot": "primary", "price": 950,
		"desc": "Bolt-action sniper. One shot to the head, always.",
		"damage": 95.0, "head_mult": 2.5, "rpm": 46.0, "auto": false,
		"mag": 5, "reserve": 30, "reload": 2.8, "pellets": 1,
		"spread_hip": 7.0, "spread_ads": 0.0, "recoil": 6.0,
		"falloff_start": 200.0, "falloff_end": 300.0, "min_mult": 1.0,
		"ads_fov": 22.0, "scope": true, "move_mult": 0.9, "sound": "shot_sniper",
	},
	"rocket": {
		"name": "Boom Block", "slot": "primary", "price": 1500,
		"desc": "Rocket launcher. Big splash, slow reload.",
		"damage": 120.0, "head_mult": 1.0, "rpm": 55.0, "auto": false,
		"mag": 1, "reserve": 7, "reload": 2.3, "pellets": 1,
		"spread_hip": 0.5, "spread_ads": 0.0, "recoil": 7.0,
		"falloff_start": 999.0, "falloff_end": 999.0, "min_mult": 1.0,
		"ads_fov": 60.0, "move_mult": 0.9, "sound": "shot_rocket",
		"projectile": true, "splash_radius": 4.5, "speed": 38.0,
	},
	"machine_pistol": {
		"name": "Bitstorm MP", "slot": "secondary", "price": 500,
		"desc": "Full-auto sidearm. Shreds up close, sprays at range.",
		"damage": 15.0, "head_mult": 1.6, "rpm": 1050.0, "auto": true,
		"mag": 20, "reserve": 120, "reload": 1.5, "pellets": 1,
		"spread_hip": 3.0, "spread_ads": 1.4, "recoil": 0.5,
		"falloff_start": 8.0, "falloff_end": 22.0, "min_mult": 0.5,
		"ads_fov": 64.0, "move_mult": 1.05, "sound": "shot_smg", "pitch": 1.18,
	},
	"burst_pistol": {
		"name": "Tri-Tap", "slot": "secondary", "price": 550,
		"desc": "Three-round burst pistol. Land the whole burst for a fast kill.",
		"damage": 24.0, "head_mult": 1.9, "rpm": 300.0, "auto": false, "burst": 3, "burst_rpm": 1100.0,
		"mag": 18, "reserve": 108, "reload": 1.5, "pellets": 1,
		"spread_hip": 1.8, "spread_ads": 0.45, "recoil": 1.0,
		"falloff_start": 18.0, "falloff_end": 40.0, "min_mult": 0.65,
		"ads_fov": 60.0, "move_mult": 1.0, "sound": "shot_pistol", "pitch": 1.1,
	},
	"sawed_off": {
		"name": "Pocket Boomer", "slot": "secondary", "price": 600,
		"desc": "Double-barrel coach gun. Two shells for when a corner goes wrong.",
		"damage": 12.0, "head_mult": 1.3, "rpm": 240.0, "auto": false,
		"mag": 2, "reserve": 24, "reload": 1.7, "pellets": 9,
		"spread_hip": 7.0, "spread_ads": 5.5, "recoil": 6.5,
		"falloff_start": 5.0, "falloff_end": 13.0, "min_mult": 0.2,
		"ads_fov": 66.0, "move_mult": 1.0, "sound": "shot_shotgun", "pitch": 0.9,
	},
	"suppressed": {
		"name": "Whisper .22", "slot": "secondary", "price": 400,
		"desc": "Suppressed pistol. No tracer, no flash, barely a sound. Flank in peace.",
		"damage": 30.0, "head_mult": 2.2, "rpm": 330.0, "auto": false, "suppressed": true,
		"mag": 10, "reserve": 70, "reload": 1.4, "pellets": 1,
		"spread_hip": 1.3, "spread_ads": 0.25, "recoil": 1.0,
		"falloff_start": 15.0, "falloff_end": 35.0, "min_mult": 0.6,
		"ads_fov": 60.0, "move_mult": 1.02, "sound": "shot_suppressed",
	},
	"dmr": {
		"name": "Block Marksman", "slot": "primary", "price": 850,
		"desc": "Semi-auto marksman rifle. Two to the chest or one to the head.",
		"damage": 48.0, "head_mult": 2.1, "rpm": 280.0, "auto": false,
		"mag": 12, "reserve": 60, "reload": 2.3, "pellets": 1,
		"spread_hip": 3.5, "spread_ads": 0.1, "recoil": 2.6,
		"falloff_start": 50.0, "falloff_end": 100.0, "min_mult": 0.8,
		"ads_fov": 38.0, "scope": true, "scope_style": "marksman", "move_mult": 0.93, "sound": "shot_dmr",
	},
	"burst_rifle": {
		"name": "Tri-Cube", "slot": "primary", "price": 700,
		"desc": "Three-round burst rifle. Precise and punchy; rewards steady aim.",
		"damage": 30.0, "head_mult": 1.8, "rpm": 450.0, "auto": false, "burst": 3, "burst_rpm": 950.0,
		"mag": 30, "reserve": 150, "reload": 2.1, "pellets": 1,
		"spread_hip": 2.0, "spread_ads": 0.3, "recoil": 1.0,
		"falloff_start": 35.0, "falloff_end": 70.0, "min_mult": 0.7,
		"ads_fov": 48.0, "move_mult": 0.97, "sound": "shot_rifle", "pitch": 1.08,
	},
	"crossbow": {
		"name": "Bolt Driver", "slot": "primary", "price": 900,
		"desc": "Single-shot bolt rifle. One headshot kills at any range; body shots need two.",
		"damage": 65.0, "head_mult": 2.2, "rpm": 55.0, "auto": false,
		"mag": 1, "reserve": 10, "reload": 1.6, "pellets": 1,
		"spread_hip": 0.8, "spread_ads": 0.0, "recoil": 3.5,
		"falloff_start": 999.0, "falloff_end": 999.0, "min_mult": 1.0,
		"ads_fov": 28.0, "scope": true, "scope_style": "marksman", "move_mult": 0.92, "sound": "shot_crossbow",
	},
	"drum_shotgun": {
		"name": "Drum Buster", "slot": "primary", "price": 850,
		"desc": "Semi-auto drum-fed shotgun. Fast follow-ups, but the wide spread wants close range.",
		"damage": 11.0, "head_mult": 1.2, "rpm": 150.0, "auto": false,
		"mag": 12, "reserve": 48, "reload": 2.8, "pellets": 8,
		"spread_hip": 6.0, "spread_ads": 4.5, "recoil": 4.0,
		"falloff_start": 6.0, "falloff_end": 15.0, "min_mult": 0.2,
		"ads_fov": 60.0, "move_mult": 0.95, "sound": "shot_drum_shotgun",
	},
	"carbine": {
		"name": "Compact Carbine", "slot": "primary", "price": 650,
		"desc": "Light, snappy semi-auto. Three body shots up close, low recoil and quick to aim.",
		"damage": 34.0, "head_mult": 1.7, "rpm": 300.0, "auto": false,
		"mag": 20, "reserve": 100, "reload": 1.7, "pellets": 1,
		"spread_hip": 2.2, "spread_ads": 0.35, "recoil": 1.1,
		"falloff_start": 30.0, "falloff_end": 60.0, "min_mult": 0.7,
		"ads_fov": 52.0, "move_mult": 1.0, "sound": "shot_carbine",
	},
	"burst_smg": {
		"name": "Quad-Bit SMG", "slot": "primary", "price": 750,
		"desc": "Four-round burst SMG. Two bursts kill up close; keep the rhythm.",
		"damage": 21.0, "head_mult": 1.5, "rpm": 560.0, "auto": false, "burst": 4, "burst_rpm": 1400.0,
		"mag": 24, "reserve": 144, "reload": 2.0, "pellets": 1,
		"spread_hip": 2.5, "spread_ads": 0.6, "recoil": 0.7,
		"falloff_start": 14.0, "falloff_end": 32.0, "min_mult": 0.55,
		"ads_fov": 56.0, "move_mult": 1.03, "sound": "shot_burst_smg",
	},
	"minigun": {
		"name": "Stacker Minigun", "slot": "primary", "price": 1600,
		"desc": "Rotary gun with a 150-round box. A wall of lead, but heavy: you move slowly and reload for an age.",
		"damage": 15.0, "head_mult": 1.4, "rpm": 1000.0, "auto": true,
		"mag": 150, "reserve": 300, "reload": 5.5, "pellets": 1,
		"spread_hip": 4.5, "spread_ads": 1.5, "recoil": 0.4,
		"falloff_start": 25.0, "falloff_end": 55.0, "min_mult": 0.6,
		"ads_fov": 45.0, "move_mult": 0.75, "sound": "shot_minigun",
	},
	"knife": {
		"name": "Pixel Blade", "slot": "melee", "price": 0,
		"desc": "Always with you. Quick slashes, and the fastest feet. Two slashes to finish the job.",
		"damage": 55.0, "head_mult": 1.0, "rpm": 110.0, "auto": true,
		"mag": 0, "reserve": 0, "reload": 0.0, "pellets": 1,
		"spread_hip": 0.0, "spread_ads": 0.0, "recoil": 0.0,
		"falloff_start": 999.0, "falloff_end": 999.0, "min_mult": 1.0,
		"ads_fov": 75.0, "move_mult": 1.1, "sound": "knife_swing", "range": 2.4, "swing": "slash",
	},
	"brick_bat": {
		"name": "Brick Bat", "slot": "melee", "price": 450,
		"desc": "A plank with a brick on the end. Wide swings with a little more reach than the knife.",
		"damage": 60.0, "head_mult": 1.0, "rpm": 95.0, "auto": true,
		"mag": 0, "reserve": 0, "reload": 0.0, "pellets": 1,
		"spread_hip": 0.0, "spread_ads": 0.0, "recoil": 0.0,
		"falloff_start": 999.0, "falloff_end": 999.0, "min_mult": 1.0,
		"ads_fov": 75.0, "move_mult": 1.05, "sound": "swing_blunt", "pitch": 1.1, "range": 2.8, "swing": "sweep",
	},
	"block_axe": {
		"name": "Block Axe", "slot": "melee", "price": 600,
		"desc": "Overhead chops that hit hard. Two to finish anyone, but each one takes a moment.",
		"damage": 70.0, "head_mult": 1.0, "rpm": 75.0, "auto": true,
		"mag": 0, "reserve": 0, "reload": 0.0, "pellets": 1,
		"spread_hip": 0.0, "spread_ads": 0.0, "recoil": 0.0,
		"falloff_start": 999.0, "falloff_end": 999.0, "min_mult": 1.0,
		"ads_fov": 75.0, "move_mult": 1.02, "sound": "swing_heavy", "pitch": 1.08, "range": 2.6, "swing": "chop",
	},
	"cube_hammer": {
		"name": "Cube Hammer", "slot": "melee", "price": 900,
		"desc": "A sledge with a stone block for a head. One hit flattens anyone at full health, if it lands: slow swings, heavy steps.",
		"damage": 100.0, "head_mult": 1.0, "rpm": 45.0, "auto": true,
		"mag": 0, "reserve": 0, "reload": 0.0, "pellets": 1,
		"spread_hip": 0.0, "spread_ads": 0.0, "recoil": 0.0,
		"falloff_start": 999.0, "falloff_end": 999.0, "min_mult": 1.0,
		"ads_fov": 75.0, "move_mult": 0.94, "sound": "swing_heavy", "pitch": 0.85, "range": 2.5, "swing": "chop",
	},
	"pixel_katana": {
		"name": "Pixel Katana", "slot": "melee", "price": 1200,
		"desc": "The longest reach of any melee weapon. Lighter hits: two clean slashes, a beat slower than the knife.",
		"damage": 50.0, "head_mult": 1.0, "rpm": 100.0, "auto": true,
		"mag": 0, "reserve": 0, "reload": 0.0, "pellets": 1,
		"spread_hip": 0.0, "spread_ads": 0.0, "recoil": 0.0,
		"falloff_start": 999.0, "falloff_end": 999.0, "min_mult": 1.0,
		"ads_fov": 75.0, "move_mult": 1.08, "sound": "swing_blade", "range": 3.1, "swing": "slash",
	},
}

## Extra reach (m) the server allows a melee hit beyond the weapon's `range`, measured between
## the two players' feet (lag, the sweep's radius and the target's body). The knife: 2.4 + 2.1.
const MELEE_SERVER_SLACK := 2.1

## Frag grenades explode on impact (with the world or a player); `fuse` only caps a throw that
## never hits anything.
const GRENADE := {
	"damage": 150.0, "radius": 5.5, "fuse": 4.0, "per_life": 2, "throw_speed": 19.0,
}

## Tactical grenades: everyone carries TACTICAL_PER_LIFE of the one picked in the locker. They
## bounce and go off after `fuse` seconds. Smoke blocks sight (bots can't see through it);
## a flash blinds anyone who can see it, more the closer they are and the more they face it.
const TACTICALS := {
	"smoke": {"name": "Smoke Block", "price": 0, "desc": "A thick cloud for 10 seconds. Cross open ground or blind a sniper's lane.",
		"fuse": 1.3, "radius": 4.6, "duration": 10.0},
	"flash": {"name": "Flash Cube", "price": 0, "desc": "Blinds anyone looking at it for up to 3.5 seconds. Bounce it round a corner, then push.",
		"fuse": 1.0, "radius": 16.0, "duration": 3.5},
}
const TACTICAL_PER_LIFE := 1

## Weapon skins apply to every gun. pattern: solid | camo | stripes | sparkle | glow | gradient
const SKINS := {
	"default": {"name": "Factory", "price": 0, "pattern": "solid",
		"a": Color("3a3d44"), "b": Color("23252a"), "glow": 0.0},
	"crimson": {"name": "Crimson", "price": 150, "pattern": "solid",
		"a": Color("b3202a"), "b": Color("4a0c10"), "glow": 0.0},
	"forest": {"name": "Forest Camo", "price": 250, "pattern": "camo",
		"a": Color("4f6b2f"), "b": Color("2b3a1a"), "glow": 0.0},
	"desert": {"name": "Desert Camo", "price": 250, "pattern": "camo",
		"a": Color("c8a96a"), "b": Color("8a6a3a"), "glow": 0.0},
	"tiger": {"name": "Tiger", "price": 350, "pattern": "stripes",
		"a": Color("e8871e"), "b": Color("1a1a1a"), "glow": 0.0},
	"ice": {"name": "Ice", "price": 450, "pattern": "gradient",
		"a": Color("dff6ff"), "b": Color("5ab4e5"), "glow": 0.15},
	"lava": {"name": "Lava", "price": 650, "pattern": "camo",
		"a": Color("ff5a00"), "b": Color("2a0a00"), "glow": 0.8},
	"neon": {"name": "Neon", "price": 750, "pattern": "stripes",
		"a": Color("29ffd4"), "b": Color("150a2e"), "glow": 1.0},
	"gold": {"name": "Gold", "price": 1000, "pattern": "sparkle",
		"a": Color("ffcc33"), "b": Color("b8860b"), "glow": 0.1},
	"diamond": {"name": "Diamond", "price": 1500, "pattern": "sparkle",
		"a": Color("8ef0ff"), "b": Color("3fc6e0"), "glow": 0.3},
	"galaxy": {"name": "Galaxy", "price": 2000, "pattern": "sparkle",
		"a": Color("7a3cff"), "b": Color("0b0626"), "glow": 0.6},
	"carbon": {"name": "Carbon Camo", "price": 500, "pattern": "camo",
		"a": Color("1e1e22"), "b": Color("0f0f12"), "glow": 0.0},
	"candy": {"name": "Candy Stripes", "price": 550, "pattern": "stripes",
		"a": Color("ff6fa3"), "b": Color("1a0a12"), "glow": 0.0},
	"pearl": {"name": "Pearl Fade", "price": 650, "pattern": "gradient",
		"a": Color("f0f0f5"), "b": Color("3a3a4a"), "glow": 0.0},
	"sunset": {"name": "Sunset Fade", "price": 800, "pattern": "gradient",
		"a": Color("ff8a3a"), "b": Color("4a1a0a"), "glow": 0.2},
}

const HATS := {
	"none": {"name": "No Hat", "price": 0},
	"cap": {"name": "Baseball Cap", "price": 100},
	"beanie": {"name": "Beanie", "price": 150},
	"headphones": {"name": "Headphones", "price": 200},
	"bandana": {"name": "Bandana", "price": 200},
	"party": {"name": "Party Hat", "price": 250},
	"beret": {"name": "Beret", "price": 250},
	"cone": {"name": "Traffic Cone", "price": 300},
	"hard_hat": {"name": "Hard Hat", "price": 300},
	"tophat": {"name": "Top Hat", "price": 400},
	"wizard": {"name": "Wizard Hat", "price": 500},
	"viking": {"name": "Viking Helmet", "price": 600},
	"halo": {"name": "Halo", "price": 800},
	"crown": {"name": "Crown", "price": 1200},
}

## Outfit colours: skin, shirt, pants, shoes, accent. pattern adds detail.
const OUTFITS := {
	"classic": {"name": "Classic", "price": 0, "pattern": "plain",
		"skin": Color("e0ac7e"), "shirt": Color("2f8fd8"), "pants": Color("2e3a7a"),
		"shoes": Color("3b3b3b"), "accent": Color("ffffff")},
	"camper": {"name": "Camper", "price": 0, "pattern": "plain",
		"skin": Color("8d5a3b"), "shirt": Color("4c7a34"), "pants": Color("5b4a32"),
		"shoes": Color("2a2118"), "accent": Color("d8c48a")},
	"zombie": {"name": "Zombie", "price": 400, "pattern": "torn",
		"skin": Color("6fa35a"), "shirt": Color("3d7f8c"), "pants": Color("3a3a6a"),
		"shoes": Color("2a2a2a"), "accent": Color("7a1010")},
	"ninja": {"name": "Ninja", "price": 300, "pattern": "mask",
		"skin": Color("e0ac7e"), "shirt": Color("16161c"), "pants": Color("16161c"),
		"shoes": Color("0c0c10"), "accent": Color("c0202a")},
	"hazmat": {"name": "Hazmat", "price": 500, "pattern": "suit",
		"skin": Color("f1d23a"), "shirt": Color("f1d23a"), "pants": Color("f1d23a"),
		"shoes": Color("2a2a2a"), "accent": Color("1a1a1a")},
	"tuxedo": {"name": "Tuxedo", "price": 700, "pattern": "tux",
		"skin": Color("e8be96"), "shirt": Color("15151a"), "pants": Color("15151a"),
		"shoes": Color("0a0a0a"), "accent": Color("ffffff")},
	"knight": {"name": "Knight", "price": 650, "pattern": "armor",
		"skin": Color("a7adb5"), "shirt": Color("a7adb5"), "pants": Color("7d838c"),
		"shoes": Color("5a5f66"), "accent": Color("b3202a")},
	"robot": {"name": "Robot", "price": 850, "pattern": "robot",
		"skin": Color("9aa3ad"), "shirt": Color("6d7885"), "pants": Color("4c5560"),
		"shoes": Color("30363d"), "accent": Color("29ffd4")},
	"astronaut": {"name": "Astronaut", "price": 1100, "pattern": "suit",
		"skin": Color("f2f2f2"), "shirt": Color("f2f2f2"), "pants": Color("e6e6e6"),
		"shoes": Color("9a9a9a"), "accent": Color("ff7a1a")},
}

## Weapon charms dangle from a short chain on the left of every gun (except the knife) and
## swing with its motion. shape: cube | die | skull | star | heart | duck | coin | ghost | gem |
## crown | creeper. a: main colour, b: detail colour.
const CHARMS := {
	"none": {"name": "No Charm", "price": 0, "desc": "A clean gun.", "shape": "", "a": Color.WHITE, "b": Color.WHITE},
	"cube": {"name": "Lucky Cube", "price": 150, "desc": "A little grass block for luck.", "shape": "cube",
		"a": Color("5aa83a"), "b": Color("7a5232")},
	"die": {"name": "Pixel Die", "price": 200, "desc": "Roll the dice on every peek.", "shape": "die",
		"a": Color("f2f2f2"), "b": Color("15151a")},
	"heart": {"name": "Block Heart", "price": 250, "desc": "Wear it on your sleeve. Or your gun.", "shape": "heart",
		"a": Color("e8304a"), "b": Color("ff8a9c")},
	"duck": {"name": "Rubber Duck", "price": 300, "desc": "Squeak. Squeak.", "shape": "duck",
	"pirate": {"name": "Pirate", "price": 600, "pattern": "pirate",
		"desc": "Polka-dot bandana, eyepatch, beard, striped sailor shirt, red sash and tall boots.",
		"skin": Color("c98d5e"), "shirt": Color("f0e8d8"), "pants": Color("2a2a33"),
		"shoes": Color("3a2414"), "accent": Color("b51f24")},
	"skier": {"name": "Ski Suit", "price": 450, "pattern": "skier",
		"desc": "Ribbed beanie with a bobble, mirrored goggles, a zipped red jacket and white ski boots.",
		"skin": Color("e8be96"), "shirt": Color("e8402a"), "pants": Color("1f2733"),
		"shoes": Color("e2e2e6"), "accent": Color("ffd23a")},
	"firefighter": {"name": "Firefighter", "price": 550, "pattern": "firefighter",
		"desc": "Red helmet with a gold shield and a turnout coat with silver and lime reflective bands.",
		"skin": Color("8d5a3b"), "shirt": Color("c9a46a"), "pants": Color("c9a46a"),
		"shoes": Color("1a1a1a"), "accent": Color("c8f03a")},
	"chef": {"name": "Chef", "price": 350, "pattern": "chef",
		"desc": "Pleated toque, curly moustache, double-breasted whites, red neckerchief and check trousers.",
		"skin": Color("f0c8a0"), "shirt": Color("f4f4f0"), "pants": Color("2b2b2b"),
		"shoes": Color("141414"), "accent": Color("c0202a")},
	"diver": {"name": "Scuba Diver", "price": 750, "pattern": "diver",
		"desc": "Wetsuit with blue panels, a yellow-framed mask, regulator, air tank and yellow fins.",
		"skin": Color("24272d"), "shirt": Color("1c1f26"), "pants": Color("1c1f26"),
		"shoes": Color("f0c020"), "accent": Color("1fa8d8")},
	"cowboy": {"name": "Cowboy", "price": 500, "pattern": "cowboy",
		"desc": "Handlebar moustache, leather vest with a sheriff star, red neckerchief, big buckle and boots.",
		"skin": Color("c98d5e"), "shirt": Color("4a6fa5"), "pants": Color("33435f"),
		"shoes": Color("5a3518"), "accent": Color("c42a2a")},
	"inmate": {"name": "Inmate", "price": 250, "pattern": "inmate",
		"desc": "Orange jumpsuit with a numbered ID patch, stencilled back and white sneakers.",
		"skin": Color("e0ac7e"), "shirt": Color("ec6a1c"), "pants": Color("ec6a1c"),
		"shoes": Color("e8e8e8"), "accent": Color("1a1a1a")},
	"mummy": {"name": "Mummy", "price": 900, "pattern": "mummy",
		"desc": "Wrapped head to toe in old bandages, with glowing green eyes.",
		"skin": Color("d9cfae"), "shirt": Color("d9cfae"), "pants": Color("cfc4a0"),
		"shoes": Color("b8ac88"), "accent": Color("6dff6a")},
		"a": Color("ffd23a"), "b": Color("ff8a1a")},
	"star": {"name": "Gold Star", "price": 350, "desc": "For good behaviour.", "shape": "star",
		"a": Color("ffcc33"), "b": Color("b8860b")},
	"skull": {"name": "Bone Skull", "price": 450, "desc": "A tiny trophy.", "shape": "skull",
		"a": Color("e8e2cf"), "b": Color("1a1a1a")},
	"coin": {"name": "Big Coin", "price": 500, "desc": "Show off your savings.", "shape": "coin",
		"a": Color("ffcc33"), "b": Color("c89212")},
	"ghost": {"name": "Pixel Ghost", "price": 600, "desc": "Boo.", "shape": "ghost",
		"a": Color("dfe8ff"), "b": Color("2a2a44")},
	"creeper": {"name": "Hiss Block", "price": 700, "desc": "Keep it away from the walls.", "shape": "creeper",
		"a": Color("4fbf3a"), "b": Color("10230c")},
	"gem": {"name": "Diamond", "price": 900, "desc": "Shiny, glowing and completely useless.", "shape": "gem",
		"a": Color("8ef0ff"), "b": Color("3fc6e0")},
	"crown": {"name": "Tiny Crown", "price": 1200, "desc": "For the king of the lobby.", "shape": "crown",
		"a": Color("ffcc33"), "b": Color("e8304a")},
}

## Win emotes: the match winner's character performs theirs at the end of the match while
## every player's camera shows them. Bots pick one at random.
const EMOTES := {
	"wave": {"name": "Wave", "price": 0, "desc": "A friendly wave to the losers."},
	"flex": {"name": "Flex", "price": 200, "desc": "Both arms up. Look at those blocks."},
	"dance": {"name": "Block Boogie", "price": 350, "desc": "Side-to-side shuffle with swinging arms."},
	"salute": {"name": "Salute", "price": 300, "desc": "Sharp, proper, respectful."},
	"dab": {"name": "Dab", "price": 400, "desc": "A timeless classic."},
	"spin": {"name": "Victory Spin", "price": 500, "desc": "Arms out, spinning on the spot."},
	"jumps": {"name": "Jumping Jacks", "price": 600, "desc": "Get those steps in."},
	"backflip": {"name": "Backflip", "price": 900, "desc": "Full backflip, landed every time."},
	"chicken": {"name": "Chicken Dance", "price": 750, "desc": "Flap, flap, flap, clap."},
}

## Draw animations play when a gun is taken out. They are purely cosmetic: every one fits in
## the same switch time (Player.switch_time()), so the gun is ready at exactly the same moment.
const DRAWS := {
	"standard": {"name": "Standard", "price": 0, "desc": "Swings up from below with a twist."},
	"twirl": {"name": "Twirl", "price": 300, "desc": "Spun once around the trigger finger, cowboy style."},
	"flip": {"name": "Barrel Roll", "price": 400, "desc": "Rolled a full turn on its way up."},
	"slam": {"name": "Drop In", "price": 450, "desc": "Drops in from above and bounces into place."},
	"sidewinder": {"name": "Sidewinder", "price": 500, "desc": "Sweeps in from the side."},
	"toss": {"name": "Toss & Catch", "price": 750, "desc": "Thrown up end over end and caught."},
}

## Sprays: pixel-art stickers a player paints on a wall with the `spray` key (Sprays, art in
## SprayArt.ART). The free one is the default.
const SPRAYS := {
	"gg": {"name": "GG", "price": 0, "desc": "Good game. Say it on the wall."},
	"heart": {"name": "Heart", "price": 150, "desc": "A little love for the map."},
	"smile": {"name": "Smiley", "price": 150, "desc": "Have a nice day."},
	"star": {"name": "Gold Star", "price": 200, "desc": "For a job well done."},
	"bolt": {"name": "Bolt", "price": 250, "desc": "Fast in, fast out."},
	"skull": {"name": "Skull", "price": 300, "desc": "Marks a spot nobody should walk through."},
	"ghost": {"name": "Ghost", "price": 300, "desc": "You never saw who left it."},
	"flame": {"name": "Flame", "price": 350, "desc": "On fire."},
	"crown": {"name": "Crown", "price": 450, "desc": "King of the block."},
	"cube": {"name": "Timbum Cube", "price": 600, "desc": "The block everything is built from."},
}

## Attachment upgrades apply to every gun and are bought one level at a time; each level costs
## more than the last (Profile.upgrade_price). `per_level` is the fraction each level adds (or
## takes away for reductions); `max` levels. Effects are read through Player.mod().
const ATTACHMENTS := {
	"laser": {"name": "Laser Sight", "desc": "Tighter hip-fire spread. Puts a visible laser on your gun.",
		"stat": "Hip-fire spread", "per_level": -0.08, "max": 5, "base_price": 200},
	"grip": {"name": "Recoil Grip", "desc": "Less recoil kick on every shot.",
		"stat": "Recoil", "per_level": -0.07, "max": 5, "base_price": 220},
	"stabilizer": {"name": "Bloom Stabilizer", "desc": "Spread grows less while you keep firing.",
		"stat": "Spread bloom", "per_level": -0.09, "max": 5, "base_price": 200},
	"mag": {"name": "Extended Mag", "desc": "Bigger magazines (guns holding three or more rounds).",
		"stat": "Magazine size", "per_level": 0.07, "max": 5, "base_price": 260},
	"speed_loader": {"name": "Speed Loader", "desc": "Faster reloads.",
		"stat": "Reload time", "per_level": -0.06, "max": 5, "base_price": 240},
	"optic": {"name": "Quick Optic", "desc": "Aim down sights faster.",
		"stat": "Aim-in time", "per_level": -0.08, "max": 5, "base_price": 180},
	"barrel": {"name": "Long Barrel", "desc": "Damage holds up over longer distances.",
		"stat": "Damage range", "per_level": 0.08, "max": 5, "base_price": 240},
	"stock": {"name": "Light Stock", "desc": "Move faster while aiming down sights.",
		"stat": "Aiming move speed", "per_level": 0.05, "max": 5, "base_price": 180},
	"holster": {"name": "Quick Holster", "desc": "Switch weapons faster.",
		"stat": "Switch time", "per_level": -0.05, "max": 5, "base_price": 160},
	"grapple_motor": {"name": "Grapple Motor", "desc": "Your grapple hook recharges faster.",
		"stat": "Grapple cooldown", "per_level": -0.06, "max": 5, "base_price": 200},
}
## Each attachment level costs base_price * ATTACHMENT_GROWTH^level (level = levels owned).
const ATTACHMENT_GROWTH := 1.75

const MAPS := {
	"village": {"name": "Village", "desc": "Cottages, a mill and a market square on rolling hills."},
	"desert": {"name": "Desert Ruins", "desc": "Sun-bleached temple ruins and long sightlines."},
	"factory": {"name": "Factory", "desc": "Catwalks, conveyor halls and tight corridors."},
	"sky": {"name": "Sky Islands", "desc": "Floating islands joined by bridges. Mind the drop."},
	"snow": {"name": "Snow Fort", "desc": "Two frozen forts and a pine forest in between."},
	"harbor": {"name": "Harbor Docks", "desc": "Stacked containers, cranes and warehouses by the water."},
	"temple": {"name": "Jungle Temple", "desc": "A stepped pyramid, vine-choked ruins and a river gorge."},
	"rooftops": {"name": "City Rooftops", "desc": "High-rise roofs linked by bridges. Mind the drop."},
	"building": {"name": "Block HQ", "desc": "A three-storey office block: room lattice, stairwells, an atrium and flanking alleys."},
	"range": {"name": "Firing Range", "desc": "Practice lanes at 10, 25, 50 and 75 m with target dummies and a weapon console."},
}
## Match modifiers. When mutators are on, each match rolls one (or none) so matches feel different.
const MUTATORS := {
	"none": {"name": "Classic", "desc": "Standard free-for-all."},
	"low_gravity": {"name": "Low Gravity", "desc": "Moon jumps! Gravity is cut by more than half."},
	"speed": {"name": "Turbo", "desc": "Everyone moves 30% faster."},
	"big_heads": {"name": "Big Heads", "desc": "Huge heads, huge headshot targets."},
	"vampire": {"name": "Vampire", "desc": "Every kill heals you to full."},
	"rocket_party": {"name": "Rocket Party", "desc": "Everyone spawns with the Boom Block. Your own primary is the backup."},
	"snipers": {"name": "Snipers Only", "desc": "Everyone spawns with the Voxel Longshot. Your own primary is the backup."},
	"glass_cannon": {"name": "Glass Cannon", "desc": "All damage is doubled. Think fast."},
}
const TIMES_OF_DAY: Array[String] = ["day", "day", "sunset", "night"]

const MAP_ROTATION: Array[String] = ["village", "desert", "factory", "sky", "snow", "harbor", "temple", "rooftops"]

## Game modes (`Net.config.mode`), in match-setup order. `short` labels the setup button;
## `teams` marks the two-team modes (Teams.is_team_mode), which may name and colour their sides
## (`team_names`, else ALPHA / BRAVO; `team_colors`: Palette roles, else team_a / team_b). Each mode's rules are a
## MatchMode subclass (MatchMode.create). Tactical always plays TACTICAL_MAP, outside the rotation.
const MODES := {
	"ffa": {"name": "Deathmatch", "short": "DEATHMATCH", "desc": "Free-for-all. First to the kill limit wins."},
	"tdm": {"name": "Team Deathmatch", "short": "TEAM DM", "teams": true,
		"desc": "Two teams. First team to the kill limit wins."},
	"gungame": {"name": "Gun Game", "short": "GUN GAME",
		"desc": "Every kill gives you the next gun. A knife kill on the last step wins; a knife kill sets the victim back."},
	"koth": {"name": "King of the Block", "short": "KING", "desc": "Stand alone in the glowing zone to score. It moves every minute."},
	"infected": {"name": "Infected", "short": "INFECTED", "teams": true,
		"team_names": ["SURVIVORS", "INFECTED"], "team_colors": ["survivors", "infected"],
		"desc": "One player turns. Every survivor they knife joins them. Survive the clock."},
	"tactical": {"name": "Tactical", "short": "TACTICAL", "teams": true,
		"desc": "25 v 25 in an office block. Plan, find your weapons, one life each."},
}
const TACTICAL_MAP := "building"
## The Firing Range and the tutorial's map (in MAPS, never in a rotation or match setup).
const RANGE_MAP := "range"
## `Net.config.session`: a normal match, or an offline practice session on RANGE_MAP (FiringRange,
## Tutorial) where no coins, XP, stats, challenges or achievements count.
const SESSIONS: Array[String] = ["match", "range", "tutorial"]
## Coins paid once, the first time the tutorial is finished.
const TUTORIAL_REWARD := 200

const BOT_NAMES: Array[String] = [
	"Blocky", "Cubert", "Pixel Pete", "Voxelina", "Sir Squares", "Brickle",
	"Chunk", "Minty", "Dot Matrix", "Grid Lock", "Tetra", "Sprout", "Hexa", "Byte",
]

const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]

const MAX_HEALTH := 100.0
const RESPAWN_TIME := 3.0
const MAX_PLAYERS := 12

## Economy
const COINS_PER_KILL := 10
const COINS_PER_HEADSHOT := 5
const COINS_PLACEMENT: Array[int] = [100, 60, 40]
const COINS_PARTICIPATION := 20
const COINS_PER_LEVEL := 100
const DAILY_REWARD := 150
const XP_PER_KILL := 100
const XP_PER_HEADSHOT := 25
const XP_MATCH := 150

## Weapon mastery: lifetime kills with one weapon (Profile.weapon_stats) that reach each tier, and
## the coins it pays once (Profile.mastery_paid). Gold unlocks the gun's mastery camo.
const MASTERY_TIERS: Array[Dictionary] = [
	{"name": "Bronze", "kills": 25, "coins": 250, "color": Color("d08a4a")},
	{"name": "Silver", "kills": 75, "coins": 500, "color": Color("c9d2dc")},
	{"name": "Gold", "kills": 150, "coins": 1000, "color": Color("ffcc33")},
]
## Kill sources tracked in the per-weapon stats besides Data.WEAPONS: frag grenades and the Block
## Bomber (Streaks.WEAPON). They have kills, headshots and damage but no shots.
const STAT_EXTRA_SOURCES: Array[String] = ["grenade", "bomber"]

## Prestige: XP stops at LEVEL_CAP; prestiging there resets the level to 1, raises the rank (up to
## PRESTIGE_MAX) and pays PRESTIGE_COINS times the new rank.
const LEVEL_CAP := 50
const PRESTIGE_MAX := 10
const PRESTIGE_COINS := 500

## Daily and weekly challenges (Challenges generates them, Profile.challenges keeps them). Each
## template: `text` [one, many] with {n} (the target or threshold) and {p} (the param's name);
## `key` the MatchFacts.tally counter that advances it ("%s" is the param id); `param` what fills
## {p}: "gun" (a gun the player owns), "gun_hs" (an owned gun that can land headshots), "mode", "map"
## or ""; `group` the slot it may fill (CHALLENGE_SLOTS); `daily` / `weekly` the [min, max] target
## (missing: not offered for that kind). `per_match`: the rolled number is a threshold the counter
## must reach in one match, and the challenge needs that once. Every template can be done offline vs
## bots (Gun Game hands out every gun, match setup picks any mode and map).
const CHALLENGE_TEMPLATES := {
	"kills": {"text": ["Get a kill", "Get {n} kills"], "key": "kills", "param": "", "group": "combat",
		"daily": [15, 30], "weekly": [100, 150]},
	"headshots": {"text": ["Get a headshot kill", "Get {n} headshot kills"], "key": "headshots", "param": "", "group": "combat",
		"daily": [4, 8], "weekly": [30, 50]},
	"gun_kills": {"text": ["Get a kill with the {p}", "Get {n} kills with the {p}"], "key": "w_kills:%s", "param": "gun", "group": "combat",
		"daily": [8, 15], "weekly": [40, 60]},
	"gun_heads": {"text": ["Get a headshot kill with the {p}", "Get {n} headshot kills with the {p}"], "key": "w_heads:%s", "param": "gun_hs",
		"group": "combat", "daily": [2, 4], "weekly": [12, 20]},
	"slide_kills": {"text": ["Slide-kill a player", "Slide-kill {n} players"], "key": "slide_kills", "param": "", "group": "style",
		"daily": [2, 3], "weekly": [10, 15]},
	"prone_kills": {"text": ["Get a kill while prone", "Get {n} kills while prone"], "key": "prone_kills", "param": "", "group": "style",
		"daily": [2, 3], "weekly": [8, 12]},
	"grapple_kills": {"text": ["Get a kill while grappling", "Get {n} kills while grappling"], "key": "grapple_kills", "param": "",
		"group": "style", "daily": [1, 2], "weekly": [5, 8]},
	"air_kills": {"text": ["Get a kill in mid-air", "Get {n} kills in mid-air"], "key": "air_kills", "param": "", "group": "style",
		"daily": [2, 4], "weekly": [10, 15]},
	"knife_kills": {"text": ["Get a knife kill", "Get {n} knife kills"], "key": "w_kills:knife", "param": "", "group": "style",
		"daily": [2, 4], "weekly": [12, 20]},
	"grenade_kills": {"text": ["Get a frag grenade kill", "Get {n} frag grenade kills"], "key": "w_kills:grenade", "param": "",
		"group": "style", "daily": [2, 3], "weekly": [8, 12]},
	"long_kills": {"text": ["Get a kill from 40 m or more", "Get {n} kills from 40 m or more"], "key": "long_kills", "param": "",
		"group": "style", "daily": [2, 4], "weekly": [10, 15]},
	"streak": {"text": ["Get a {n}-kill streak in one match", "Get a {n}-kill streak in one match"], "key": "best_streak", "param": "",
		"group": "style", "per_match": true, "daily": [4, 6], "weekly": [7, 9]},
	"mode_kills": {"text": ["Get a kill in {p}", "Get {n} kills in {p}"], "key": "mode_kills:%s", "param": "mode", "group": "mode",
		"daily": [10, 20], "weekly": [60, 100]},
	"mode_play": {"text": ["Play a match of {p}", "Play {n} matches of {p}"], "key": "mode_matches:%s", "param": "mode", "group": "mode",
		"daily": [2, 3], "weekly": [6, 10]},
	"mode_win": {"text": ["Win a match of {p}", "Win {n} matches of {p}"], "key": "wins_mode:%s", "param": "mode", "group": "mode",
		"daily": [1, 1], "weekly": [2, 4]},
	"map_win": {"text": ["Win a match on {p}", "Win {n} matches on {p}"], "key": "wins_map:%s", "param": "map", "group": "mode",
		"daily": [1, 1], "weekly": [2, 3]},
	"map_kills": {"text": ["Get a kill on {p}", "Get {n} kills on {p}"], "key": "map_kills:%s", "param": "map", "group": "mode",
		"daily": [10, 20], "weekly": [60, 90]},
	"wins": {"text": ["Win a match", "Win {n} matches"], "key": "wins", "param": "", "group": "mode",
		"daily": [1, 2], "weekly": [5, 8]},
}
## Groups each challenge slot draws from, so every set mixes guns, movement and modes/maps.
const CHALLENGE_SLOTS := {
	"daily": [["combat"], ["style"], ["mode"]],
	"weekly": [["mode"], ["combat", "style"]],
}
## What claiming a challenge pays (no XP at LEVEL_CAP, like matches).
const CHALLENGE_REWARDS := {
	"daily": {"coins": 150, "xp": 400},
	"weekly": {"coins": 600, "xp": 1500},
}
## Distance at or above which a kill counts for "long_kills".
const LONG_KILL_DISTANCE := 40.0

## Medals: the results screen's match highlights (MatchMode.highlights), counted for life in
## Profile.feats ("medal:<id>"). `mode`: the mode that awards it ("" every mode).
const MEDALS := {
	"best_streak": {"name": "Best Streak", "desc": "Longest kill streak of the match.", "mode": ""},
	"sharpshooter": {"name": "Sharpshooter", "desc": "Most headshot kills of the match.", "mode": ""},
	"survivor": {"name": "Survivor", "desc": "Fewest deaths of the match (with a kill).", "mode": ""},
	"team_top": {"name": "Team MVP", "desc": "Most kills on your team.", "mode": "tdm"},
	"knife_finish": {"name": "Blade Finish", "desc": "Won Gun Game with the knife.", "mode": "gungame"},
	"setbacks": {"name": "Setback Artist", "desc": "Most knife setbacks dealt in Gun Game.", "mode": "gungame"},
	"survived": {"name": "Still Standing", "desc": "Survived Infected to the end.", "mode": "infected"},
	"top_infector": {"name": "Patient Zero", "desc": "Most survivors infected.", "mode": "infected"},
	"longest_hold": {"name": "Zone Keeper", "desc": "Longest hold of the zone.", "mode": "koth"},
}

## Permanent achievements (Profile.achievements: id -> unlock time). `key` is a lifetime value
## Profile.achievement_value reads (stats, weapon_stats, Profile.feats or a count over them);
## `target` the value that unlocks it, ACHIEVE_ALL meaning "every one" (every gun, deathmatch map
## or mode; Profile.achievement_target).
const ACHIEVE_ALL := -1
const ACHIEVEMENTS := {
	"first_blood": {"name": "First Blood", "desc": "Get your first kill.", "key": "kills", "target": 1},
	"centurion": {"name": "Centurion", "desc": "Get 100 kills.", "key": "kills", "target": 100},
	"block_buster": {"name": "Block Buster", "desc": "Get 1,000 kills.", "key": "kills", "target": 1000},
	"headhunter": {"name": "Headhunter", "desc": "Get 100 headshot kills.", "key": "headshots", "target": 100},
	"rampage": {"name": "Rampage", "desc": "Get a 5-kill streak.", "key": "best_streak", "target": 5},
	"godlike": {"name": "Godlike", "desc": "Get a 10-kill streak.", "key": "best_streak", "target": 10},
	"triple": {"name": "Triple Threat", "desc": "Get a triple kill (three kills within a few seconds).", "key": "best_multi", "target": 3},
	"arsenal": {"name": "Full Arsenal", "desc": "Get a kill with every gun (Gun Game hands them all out).", "key": "guns_with_kill", "target": ACHIEVE_ALL},
	"world_tour": {"name": "World Tour", "desc": "Win a match on every deathmatch map.", "key": "maps_won", "target": ACHIEVE_ALL},
	"all_rounder": {"name": "All-Rounder", "desc": "Win a match in every mode.", "key": "modes_won", "target": ACHIEVE_ALL},
	"slide_in": {"name": "Slide In", "desc": "Get a kill while sliding.", "key": "slide_kills", "target": 1},
	"hooked": {"name": "Hooked", "desc": "Get a kill while grappling.", "key": "grapple_kills", "target": 1},
	"snake": {"name": "Snake in the Grass", "desc": "Get a kill while prone.", "key": "prone_kills", "target": 1},
	"airborne": {"name": "Airborne", "desc": "Get 10 kills in mid-air.", "key": "air_kills", "target": 10},
	"long_shot": {"name": "Long Shot", "desc": "Get 25 kills from 40 m or more.", "key": "long_kills", "target": 25},
	"cutthroat": {"name": "Cutthroat", "desc": "Get 25 knife kills.", "key": "w_kills:knife", "target": 25},
	"demolition": {"name": "Demolition Expert", "desc": "Get 25 frag grenade kills.", "key": "w_kills:grenade", "target": 25},
	"air_support": {"name": "Air Support", "desc": "Get a kill with the Block Bomber.", "key": "w_kills:bomber", "target": 1},
	"dm_win": {"name": "Last Block Standing", "desc": "Win a Deathmatch.", "key": "wins_mode:ffa", "target": 1},
	"tdm_win": {"name": "Team Player", "desc": "Win a Team Deathmatch.", "key": "wins_mode:tdm", "target": 1},
	"gungame_win": {"name": "Top of the Ladder", "desc": "Win a Gun Game.", "key": "wins_mode:gungame", "target": 1},
	"koth_win": {"name": "King of the Block", "desc": "Win King of the Block.", "key": "wins_mode:koth", "target": 1},
	"infected_win": {"name": "Outbreak", "desc": "Win a game of Infected (either side).", "key": "wins_mode:infected", "target": 1},
	"tactical_win": {"name": "Breach and Clear", "desc": "Win a Tactical match.", "key": "wins_mode:tactical", "target": 1},
	"regular": {"name": "Regular", "desc": "Play 50 matches.", "key": "matches", "target": 50},
	"champion": {"name": "Champion", "desc": "Win 25 matches.", "key": "wins", "target": 25},
	"decorated": {"name": "Decorated", "desc": "Earn 25 medals (match highlights).", "key": "medals", "target": 25},
	"gold_standard": {"name": "Gold Standard", "desc": "Reach Gold mastery with a gun.", "key": "gold_guns", "target": 1},
	"grinder": {"name": "Daily Grinder", "desc": "Complete 10 challenges.", "key": "challenges_done", "target": 10},
}


## True for melee weapon ids (the knife and the other melee weapons).
static func is_melee(wid: String) -> bool:
	return WEAPONS.has(wid) and WEAPONS[wid].slot == "melee"


## Badge shown before a prestiged player's name (scoreboard, kill feed, nametags); "" at rank 0.
static func prestige_badge(rank: int) -> String:
	return "★%d" % rank if rank > 0 else ""


## `player_name` with the prestige badge in front when `rank` > 0.
static func badged_name(player_name: String, rank: int) -> String:
	return player_name if rank <= 0 else "%s %s" % [prestige_badge(rank), player_name]


## Mastery tier reached with `kills` (0 none, 1 Bronze, 2 Silver, 3 Gold).
static func mastery_tier_for(kills: int) -> int:
	var tier := 0
	for t: Dictionary in MASTERY_TIERS:
		if kills >= int(t.kills):
			tier += 1
	return tier


## Weapon-skin id of `wid`'s mastery camo (Models.skin_material builds it).
static func mastery_skin(wid: String) -> String:
	return "mastery_" + wid


## True for skin ids a gun can wear: a catalog skin or a known gun's mastery camo.
static func is_gun_skin(skin_id: String) -> bool:
	return SKINS.has(skin_id) or (skin_id.begins_with("mastery_") and WEAPONS.has(skin_id.trim_prefix("mastery_")))


## The skin `wid` wears for a player whose peer_info is `info`: their mastery camo when they
## switched it on for that gun, else their equipped weapon skin.
static func gun_skin_for(info: Dictionary, wid: String) -> String:
	var camos: Variant = info.get("camos", [])
	if typeof(camos) == TYPE_ARRAY and (camos as Array).has(wid):
		return mastery_skin(wid)
	return str(info.get("skin", "default"))


func catalog(category: String) -> Dictionary:
	match category:
		"weapons": return WEAPONS
		"skins": return SKINS
		"hats": return HATS
		"outfits": return OUTFITS
		"tacticals": return TACTICALS
		"charms": return CHARMS
		"emotes": return EMOTES
		"draws": return DRAWS
		"sprays": return SPRAYS
	push_error("Unknown catalog category: %s" % category)
	return {}


## Multiplier an attachment at `level` applies to its stat (1.0 at level 0).
func attachment_mult(id: String, level: int) -> float:
	var a: Dictionary = ATTACHMENTS[id]
	return 1.0 + float(a.per_level) * clampi(level, 0, int(a.max))


func weapon_ids_for_slot(slot: String) -> Array[String]:
	var ids: Array[String] = []
	for id: String in WEAPONS:
		if WEAPONS[id].slot == slot:
			ids.append(id)
	return ids
