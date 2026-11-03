class_name Season
extends RefCounted
## The season pass: Season 1 "Block Party", free, TIERS tiers of XP_PER_TIER season XP each.
## Season XP is the XP a match pays (counted before the level cap stops it, so capped and
## prestiged players still earn it) plus the XP of claimed challenges (Profile.record_match,
## claim_challenge, refresh_challenges). Every tier has one reward (REWARDS): coins, or one of
## the season's exclusive cosmetics (Data catalog entries with `season: true` and price -1:
## never sold, owned once their tier is claimed). Progress lives in Profile (season_id,
## season_xp, season_claimed). After END_DATE the pass stays open: XP still counts and every
## tier stays claimable, so nobody loses anything.

const ID := "s1"
const NUMBER := 1
const NAME := "Block Party"
## Last day of the season (local calendar, inclusive).
const END_DATE := {"year": 2026, "month": 12, "day": 31}
const TIERS := 30
const XP_PER_TIER := 1000
const MAX_XP := TIERS * XP_PER_TIER
## The season's colour (party magenta): shop SEASON tags and cards, the season screen, toasts.
const COLOR := Color("ff4fd8")
## Reward of tier i + 1: {coins: n} or {item: [Data catalog category, id]}. The 12 exclusive
## cosmetics are spread out; the animated skin and the outfit, the best two, are tiers 25 and 30.
const REWARDS: Array[Dictionary] = [
	{"coins": 200},
	{"coins": 250},
	{"item": ["sprays", "bp_popper"]},
	{"coins": 300},
	{"item": ["charms", "bp_gift"]},
	{"coins": 300},
	{"item": ["skins", "bp_confetti"]},
	{"coins": 350},
	{"coins": 350},
	{"item": ["hats", "bp_balloon_dog"]},
	{"coins": 400},
	{"coins": 400},
	{"item": ["sprays", "bp_boombox"]},
	{"coins": 450},
	{"item": ["skins", "bp_giftwrap"]},
	{"coins": 450},
	{"item": ["charms", "bp_balloon"]},
	{"coins": 500},
	{"coins": 500},
	{"item": ["hats", "bp_cake"]},
	{"coins": 550},
	{"item": ["skins", "bp_dancefloor"]},
	{"coins": 600},
	{"coins": 600},
	{"item": ["skins", "bp_disco"]},
	{"coins": 700},
	{"coins": 750},
	{"item": ["hats", "bp_discoball"]},
	{"coins": 800},
	{"item": ["outfits", "bp_disco_star"]},
]
## Kind names of the reward categories, for cards and the detail panel.
const KIND_NAMES := {"skins": "WEAPON SKIN", "hats": "HAT", "charms": "WEAPON CHARM", "sprays": "SPRAY",
	"outfits": "OUTFIT", "coins": "COINS"}


## "SEASON 1: BLOCK PARTY".
static func title() -> String:
	return "SEASON %d: %s" % [NUMBER, NAME.to_upper()]


## Tiers reached with `xp` season XP (0..TIERS).
static func tier_for(xp: int) -> int:
	return clampi(xp / XP_PER_TIER, 0, TIERS)


## Season XP gathered towards the next tier (0..XP_PER_TIER-1; 0 once every tier is reached).
static func tier_progress(xp: int) -> int:
	return 0 if xp >= MAX_XP else posmod(xp, XP_PER_TIER)


## The reward of `tier` (1..TIERS), {} for any other number.
static func reward(tier: int) -> Dictionary:
	return REWARDS[tier - 1] if tier >= 1 and tier <= TIERS else {}


## The tier that unlocks a season cosmetic, 0 when `id` isn't one.
static func item_tier(category: String, id: String) -> int:
	for i in REWARDS.size():
		var item: Array = REWARDS[i].get("item", [])
		if not item.is_empty() and item[0] == category and item[1] == id:
			return i + 1
	return 0


## Reward category ("coins" or a Data catalog) of `tier`.
static func reward_category(tier: int) -> String:
	var r := reward(tier)
	return str(r.item[0]) if r.has("item") else "coins"


## Short name of a tier's reward: "Disco Fever" or "500 coins".
static func reward_name(tier: int) -> String:
	var r := reward(tier)
	if r.has("item"):
		return str(Data.catalog(r.item[0])[r.item[1]].name)
	return "%d coins" % int(r.get("coins", 0))


## "Disco Fever (weapon skin)" or "500 coins": the toast and claim line.
static func reward_text(tier: int) -> String:
	var cat := reward_category(tier)
	if cat == "coins":
		return reward_name(tier)
	return "%s (%s)" % [reward_name(tier), str(KIND_NAMES[cat]).to_lower()]


## Day number (Challenges.day_number) of the season's last day.
static func end_day() -> int:
	return Challenges.day_number(int(END_DATE.year), int(END_DATE.month), int(END_DATE.day))


## Days left including today (0 once the season ended); `day` overrides today.
static func days_left(day := -1) -> int:
	if day < 0:
		day = Challenges.today()
	return maxi(0, end_day() - day + 1)


## True after the last day. The pass keeps counting XP and stays claimable.
static func ended(day := -1) -> bool:
	return days_left(day) == 0


## "57 DAYS LEFT", "LAST DAY" or "SEASON OVER · STILL CLAIMABLE".
static func time_left_text(day := -1) -> String:
	var n := days_left(day)
	if n == 0:
		return "SEASON OVER · STILL CLAIMABLE"
	if n == 1:
		return "LAST DAY"
	return "%d DAYS LEFT" % n


## "ENDS 31 DEC 2026".
static func end_text() -> String:
	const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	return "ENDS %d %s %d" % [int(END_DATE.day), MONTHS[int(END_DATE.month) - 1], int(END_DATE.year)]
