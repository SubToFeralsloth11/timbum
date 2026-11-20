class_name Season
extends RefCounted
## The season pass: Season 1 "Block Party", free, TIERS tiers of XP_PER_TIER season XP each.
## Every tier has one reward (REWARDS): coins, or one of the season's exclusive cosmetics (Data
## catalog entries with `season: true` and price -1: never sold, owned once their tier is claimed).
## Progress lives in Profile (season_id, season_xp, season_claimed, season_quests). After END_DATE
## the pass stays open: XP and quests still count and every tier stays claimable.
##
## Season XP (SXP) is its own currency, not the match XP: a match pays match_sxp (MATCH_SXP, plus
## KILL_SXP a kill for up to KILL_SXP_MAX kills, plus WIN_SXP for a win), a claimed challenge
## CHALLENGE_SXP, a finished season quest QUEST_SXP (Profile.record_match, claim_challenge,
## refresh_challenges).
##
## Season quests (QUESTS) come in WEEKS weekly batches of four; week w unlocks on the Monday
## START_DATE + 7 (w - 1) days (16 Nov, 23 Nov, 30 Nov, 7 Dec, 14 Dec, 21 Dec 2026) and stays open.
## A quest only counts matches played once its week is open, at match end (Profile.record_match),
## online and offline. GATES lock bands of tiers behind quests: whatever the XP, tier 6+ needs 2
## week-1 quests, 11+ 2 of week 2, 16+ 2 of week 3, 21+ 2 of week 4, 26+ 2 of week 5 and tier 30
## three of week 6 (tier_cap). Extra XP banks while a gate holds and the tiers open the moment it
## is passed.
##
## The math (MAX_XP 36,000), counted from the 2.4.0 reset on 21 Nov 2026 to END_DATE (41 days):
## - Regular player, about an hour a day: 5 matches at ~55 SXP (275), the 3 dailies (180), both
##   weeklies (500 a week: ~71 a day) and the quests as they open (24 x 600 = 14,400 over the
##   season: ~351 a day) = ~877 SXP a day -> 36,000 / 877 = ~41 days: the last tier around 31 Dec.
## - Light player: 2 matches a day (110), the dailies (180), one weekly (~36) and half the quests
##   (~175) = ~500 a day -> about tier 17 by the end (the pass stays claimable afterwards).
## - Grinder: 20 matches a day (~1,200) plus everything else = ~1,800 a day: the XP is there in
##   ~20 days, but tier 26 waits for week 5's quests (14 Dec) and tier 30 for week 6's (21 Dec).
## (Before 2.4.0 the pass paid every match's full XP, ~1,000 a match: 30 tiers in about two days.)

const ID := "s1"
const NUMBER := 1
const NAME := "Block Party"
## Last day of the season (local calendar, inclusive).
const END_DATE := {"year": 2026, "month": 12, "day": 31}
## Monday the first quest week opens.
const START_DATE := {"year": 2026, "month": 11, "day": 16}
## Season pass resets so far. A profile whose Profile.season_reset is lower is wiped once on load
## or import (Profile._reset_season): season XP, claims, quests and every season cosmetic.
## 1: the 2.4.0 slow-down (the old pass was finished in days).
const RESET := 1
const TIERS := 30
const XP_PER_TIER := 1200
const MAX_XP := TIERS * XP_PER_TIER
const MATCH_SXP := 30
const KILL_SXP := 3
const KILL_SXP_MAX := 15
const WIN_SXP := 25
const CHALLENGE_SXP := {"daily": 60, "weekly": 250}
const QUEST_SXP := 600
const WEEKS := 6
## Season quests: {id, week, text, key (a MatchFacts.tally counter), target, best (true: the best
## single match counts, not the sum), unit ("min": `seconds` shown in minutes)}. Four a week.
const QUESTS: Array[Dictionary] = [
	{"id": "w1_play", "week": 1, "text": "Play 8 matches", "key": "matches", "target": 8},
	{"id": "w1_kills", "week": 1, "text": "Get 50 kills", "key": "kills", "target": 50},
	{"id": "w1_wins", "week": 1, "text": "Win 3 matches", "key": "wins", "target": 3},
	{"id": "w1_time", "week": 1, "text": "Play for 45 minutes", "key": "seconds", "target": 2700, "unit": "min"},
	{"id": "w2_heads", "week": 2, "text": "Get 25 headshot kills", "key": "headshots", "target": 25},
	{"id": "w2_ctf", "week": 2, "text": "Play 3 matches of Capture the Flag", "key": "mode_matches:ctf", "target": 3},
	{"id": "w2_score", "week": 2, "text": "Score 1,500 in one match", "key": "match_score", "target": 1500, "best": true},
	{"id": "w2_medals", "week": 2, "text": "Earn 6 match highlights", "key": "medals", "target": 6},
	{"id": "w3_caps", "week": 3, "text": "Capture 4 flags", "key": "captures", "target": 4},
	{"id": "w3_koth", "week": 3, "text": "Win 2 matches of King of the Block", "key": "wins_mode:koth", "target": 2},
	{"id": "w3_tdm", "week": 3, "text": "Get 40 kills in Team Deathmatch", "key": "mode_kills:tdm", "target": 40},
	{"id": "w3_time", "week": 3, "text": "Play for 90 minutes", "key": "seconds", "target": 5400, "unit": "min"},
	{"id": "w4_hide", "week": 4, "text": "Play 3 matches of Hide and Seek", "key": "mode_matches:hideseek", "target": 3},
	{"id": "w4_hunt", "week": 4, "text": "Play 3 matches of Block Hunt", "key": "mode_matches:blockhunt", "target": 3},
	{"id": "w4_streak", "week": 4, "text": "Get a 7-kill streak in one match", "key": "best_streak", "target": 7, "best": true},
	{"id": "w4_wins", "week": 4, "text": "Win 6 matches", "key": "wins", "target": 6},
	{"id": "w5_kills", "week": 5, "text": "Get 120 kills", "key": "kills", "target": 120},
	{"id": "w5_gungame", "week": 5, "text": "Win a match of Gun Game", "key": "wins_mode:gungame", "target": 1},
	{"id": "w5_parkour", "week": 5, "text": "Play 3 matches of Parkour", "key": "mode_matches:parkour", "target": 3},
	{"id": "w5_score", "week": 5, "text": "Score 2,500 in one match", "key": "match_score", "target": 2500, "best": true},
	{"id": "w6_wins", "week": 6, "text": "Win 8 matches", "key": "wins", "target": 8},
	{"id": "w6_heads", "week": 6, "text": "Get 40 headshot kills", "key": "headshots", "target": 40},
	{"id": "w6_infected", "week": 6, "text": "Play 3 matches of Infected", "key": "mode_matches:infected", "target": 3},
	{"id": "w6_time", "week": 6, "text": "Play for 2 hours", "key": "seconds", "target": 7200, "unit": "min"},
]
## Tier gates: [first tier, quest week, quests of that week needed]. A gate covers its first tier up
## to the tier before the next gate; every earlier gate must be passed too.
const GATES: Array = [[6, 1, 2], [11, 2, 2], [16, 3, 2], [21, 4, 2], [26, 5, 2], [30, 6, 3]]
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


## Season XP one match pays (match_sxp in the header): `kills` this match, `won` a contested win.
static func match_sxp(kills: int, won: bool) -> int:
	return MATCH_SXP + mini(maxi(0, kills), KILL_SXP_MAX) * KILL_SXP + (WIN_SXP if won else 0)


# ---------------------------------------------------------------- quests and gates

## Day number (Challenges.day_number) quest week `week` (1..WEEKS) opens.
static func week_start(week: int) -> int:
	return Challenges.day_number(int(START_DATE.year), int(START_DATE.month), int(START_DATE.day)) + 7 * (week - 1)


## True once quest week `week` has opened (it then stays open); `day` overrides today.
static func week_open(week: int, day := -1) -> bool:
	if day < 0:
		day = Challenges.today()
	return day >= week_start(week)


## "23 NOV": the day quest week `week` opens.
static func week_date_text(week: int) -> String:
	const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	var d := Time.get_date_dict_from_unix_time(week_start(week) * 86400)
	return "%d %s" % [int(d.day), MONTHS[int(d.month) - 1]]


## The quests of week `week`, in QUESTS order.
static func week_quests(week: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q: Dictionary in QUESTS:
		if int(q.week) == week:
			out.append(q)
	return out


## How far quest `q` is with `progress` (Profile.season_quests: quest id -> value), capped at its target.
static func quest_value(q: Dictionary, progress: Dictionary) -> int:
	return mini(int(progress.get(q.id, 0)), int(q.target))


static func quest_done(q: Dictionary, progress: Dictionary) -> bool:
	return quest_value(q, progress) >= int(q.target)


## Quest `q`'s value after one match's `tally` (MatchFacts.tally): the sum, or the best single match
## for a `best` quest, capped at its target.
static func quest_after(q: Dictionary, progress: Dictionary, tally: Dictionary) -> int:
	var now := int(progress.get(q.id, 0))
	var got := int(tally.get(str(q.key), 0))
	return mini(int(q.target), maxi(now, got) if bool(q.get("best", false)) else now + got)


## "23 / 45 min" or "3 / 8".
static func quest_progress_text(q: Dictionary, progress: Dictionary) -> String:
	var v := quest_value(q, progress)
	if str(q.get("unit", "")) == "min":
		return "%d / %d min" % [v / 60, int(q.target) / 60]
	return "%s / %s" % [UIKit.format_int(v), UIKit.format_int(int(q.target))]


## Finished quests of week `week`.
static func done_in_week(week: int, progress: Dictionary) -> int:
	var n := 0
	for q in week_quests(week):
		if quest_done(q, progress):
			n += 1
	return n


## The highest tier the quests in `progress` allow (TIERS once every gate is passed): the tier
## before the first gate whose week hasn't enough finished quests.
static func tier_cap(progress: Dictionary) -> int:
	for g: Array in GATES:
		if done_in_week(int(g[1]), progress) < int(g[2]):
			return int(g[0]) - 1
	return TIERS


## The first gate [first tier, week, quests needed] still holding `tier` back with `progress`
## (Profile.season_quests), [] when none does.
static func blocking_gate(tier: int, progress: Dictionary) -> Array:
	for g: Array in GATES:
		if tier >= int(g[0]) and done_in_week(int(g[1]), progress) < int(g[2]):
			return g
	return []
