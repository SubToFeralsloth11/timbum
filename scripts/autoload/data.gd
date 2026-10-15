extends Node
## Static game catalogs: weapons, cosmetics, maps. Pure data, no state.

const CATEGORIES: Array[String] = ["weapons", "skins", "hats", "outfits"]

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
##   ads_fov: field of view while aiming; scope: draws scope overlay
##   move_mult: movement speed multiplier while held
##   projectile: fires a rocket instead of hitscan; splash_radius / speed
##   sound: Sfx name
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

const GRENADE := {
	"damage": 110.0, "radius": 5.0, "fuse": 2.4, "per_life": 2, "throw_speed": 17.0,
}

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

const MAPS := {
	"village": {"name": "Village", "desc": "Cottages, a mill and a market square on rolling hills."},
	"desert": {"name": "Desert Ruins", "desc": "Sun-bleached temple ruins and long sightlines."},
	"factory": {"name": "Factory", "desc": "Catwalks, conveyor halls and tight corridors."},
	"sky": {"name": "Sky Islands", "desc": "Floating islands joined by bridges. Mind the drop."},
	"snow": {"name": "Snow Fort", "desc": "Two frozen forts and a pine forest in between."},
}
## Match modifiers. When mutators are on, each match rolls one (or none) so matches feel different.
const MUTATORS := {
	"none": {"name": "Classic", "desc": "Standard free-for-all."},
	"low_gravity": {"name": "Low Gravity", "desc": "Moon jumps! Gravity is cut by more than half."},
	"speed": {"name": "Turbo", "desc": "Everyone moves 30% faster."},
	"big_heads": {"name": "Big Heads", "desc": "Huge heads, huge headshot targets."},
	"vampire": {"name": "Vampire", "desc": "Every kill heals you to full."},
	"rocket_party": {"name": "Rocket Party", "desc": "Everyone's primary is the Boom Block."},
	"snipers": {"name": "Snipers Only", "desc": "Everyone's primary is the Voxel Longshot."},
	"glass_cannon": {"name": "Glass Cannon", "desc": "All damage is doubled. Think fast."},
}
const TIMES_OF_DAY: Array[String] = ["day", "day", "sunset", "night"]

const MAP_ROTATION: Array[String] = ["village", "desert", "factory", "sky", "snow"]

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
	push_error("Unknown catalog category: %s" % category)
	return {}


func weapon_ids_for_slot(slot: String) -> Array[String]:
	var ids: Array[String] = []
	for id: String in WEAPONS:
		if WEAPONS[id].slot == slot:
			ids.append(id)
	return ids
