extends Node
## Static game catalogs: weapons, cosmetics, maps. Pure data, no state.

const CATEGORIES: Array[String] = ["weapons", "skins", "hats", "outfits", "charms", "emotes", "draws"]

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
	"knife": {
		"name": "Pixel Blade", "slot": "melee", "price": 0,
		"desc": "Always with you. Two slashes to finish the job.",
		"damage": 55.0, "head_mult": 1.0, "rpm": 110.0, "auto": true,
		"mag": 0, "reserve": 0, "reload": 0.0, "pellets": 1,
		"spread_hip": 0.0, "spread_ads": 0.0, "recoil": 0.0,
		"falloff_start": 999.0, "falloff_end": 999.0, "min_mult": 1.0,
		"ads_fov": 75.0, "move_mult": 1.1, "sound": "knife_swing", "range": 2.4,
	},
}

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
}

const HATS := {
	"none": {"name": "No Hat", "price": 0},
	"cap": {"name": "Baseball Cap", "price": 100},
	"beanie": {"name": "Beanie", "price": 150},
	"headphones": {"name": "Headphones", "price": 200},
	"party": {"name": "Party Hat", "price": 250},
	"cone": {"name": "Traffic Cone", "price": 300},
	"tophat": {"name": "Top Hat", "price": 400},
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
## (`team_names` / `team_colors`, else ALPHA / BRAVO in Teams.COLORS). Each mode's rules are a
## MatchMode subclass (MatchMode.create). Tactical always plays TACTICAL_MAP, outside the rotation.
const MODES := {
	"ffa": {"name": "Deathmatch", "short": "DEATHMATCH", "desc": "Free-for-all. First to the kill limit wins."},
	"tdm": {"name": "Team Deathmatch", "short": "TEAM DM", "teams": true,
		"desc": "Two teams. First team to the kill limit wins."},
	"infected": {"name": "Infected", "short": "INFECTED", "teams": true,
		"team_names": ["SURVIVORS", "INFECTED"], "team_colors": [Color(0.45, 0.78, 1.0), Color(0.45, 0.95, 0.3)],
		"desc": "One player turns. Every survivor they knife joins them. Survive the clock."},
	"tactical": {"name": "Tactical", "short": "TACTICAL", "teams": true,
		"desc": "25 v 25 in an office block. Plan, find your weapons, one life each."},
}
const TACTICAL_MAP := "building"

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
