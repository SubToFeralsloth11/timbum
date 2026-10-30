class_name Palette
extends RefCounted
## The one source of the colours that tell sides and states apart, remapped by Settings >
## Accessibility > Colour mode (`color_mode`: Off, Deuteranopia, Protanopia, Tritanopia). Team
## colours (Teams.color), nametags, the kill feed, hitmarkers and damage numbers, the health and
## shield bar, compass pips, King of the Block's zone, pings, radar contacts and airstrike warnings
## all ask `Palette.color(role)`. Red-green modes (deuteranopia, protanopia) build on blue against
## orange / yellow, with magenta for kills and contests; protanopia keeps its warm colours bright
## because reds look dark to it. Tritanopia builds on teal against red / pink. Colour is never the
## only cue: teams also carry shapes (Teams.shape), zone states and pings have their own labels.

const MODE_NAMES: Array[String] = ["Off", "Deuteranopia", "Protanopia", "Tritanopia"]

## Per colour mode, role -> colour. Every set has every role.
const SETS: Array[Dictionary] = [
	{ # Off: the game's own colours.
		"team_a": Color(0.3, 0.62, 1.0), "team_b": Color(1.0, 0.45, 0.22),
		"survivors": Color(0.45, 0.78, 1.0), "infected": Color(0.45, 0.95, 0.3),
		"feed_killer": Color(1.0, 0.55, 0.5), "feed_victim": Color(0.6, 0.8, 1.0),
		"hit": Color(1.0, 1.0, 1.0), "hit_head": Color(1.0, 0.8, 0.2), "hit_kill": Color(1.0, 0.25, 0.2),
		"health_high": Color(0.35, 0.95, 0.45), "health_low": Color(0.95, 0.3, 0.25), "shield": Color(0.45, 0.85, 1.0),
		"zone_free": Color(1.0, 0.85, 0.3), "zone_mine": Color(0.35, 1.0, 0.45), "zone_other": Color(1.0, 0.4, 0.3),
		"zone_contested": Color(1.0, 0.3, 0.9), "zone_next": Color(0.85, 0.92, 1.0),
		"ping_spot": Color(1.0, 0.85, 0.3), "ping_enemy": Color(1.0, 0.3, 0.2),
		"radar": Color(1.0, 0.25, 0.2), "warning": Color(1.0, 0.18, 0.1),
	},
	{ # Deuteranopia (green-blind).
		"team_a": Color(0.25, 0.55, 1.0), "team_b": Color(1.0, 0.62, 0.1),
		"survivors": Color(0.35, 0.7, 1.0), "infected": Color(1.0, 0.8, 0.15),
		"feed_killer": Color(1.0, 0.7, 0.3), "feed_victim": Color(0.55, 0.75, 1.0),
		"hit": Color(1.0, 1.0, 1.0), "hit_head": Color(1.0, 0.9, 0.2), "hit_kill": Color(0.95, 0.35, 1.0),
		"health_high": Color(0.3, 0.65, 1.0), "health_low": Color(1.0, 0.6, 0.05), "shield": Color(0.92, 0.94, 1.0),
		"zone_free": Color(1.0, 0.95, 0.6), "zone_mine": Color(0.3, 0.65, 1.0), "zone_other": Color(1.0, 0.55, 0.0),
		"zone_contested": Color(0.95, 0.35, 1.0), "zone_next": Color(0.85, 0.92, 1.0),
		"ping_spot": Color(1.0, 0.9, 0.35), "ping_enemy": Color(1.0, 0.5, 0.0),
		"radar": Color(1.0, 0.5, 0.0), "warning": Color(1.0, 0.5, 0.0),
	},
	{ # Protanopia (red-blind): reds look dark, so the warm side is bright orange-yellow.
		"team_a": Color(0.25, 0.55, 1.0), "team_b": Color(1.0, 0.8, 0.2),
		"survivors": Color(0.35, 0.7, 1.0), "infected": Color(1.0, 0.88, 0.3),
		"feed_killer": Color(1.0, 0.82, 0.35), "feed_victim": Color(0.55, 0.75, 1.0),
		"hit": Color(1.0, 1.0, 1.0), "hit_head": Color(1.0, 0.92, 0.3), "hit_kill": Color(0.85, 0.45, 1.0),
		"health_high": Color(0.3, 0.65, 1.0), "health_low": Color(1.0, 0.8, 0.1), "shield": Color(0.92, 0.94, 1.0),
		"zone_free": Color(0.95, 0.95, 0.95), "zone_mine": Color(0.3, 0.65, 1.0), "zone_other": Color(1.0, 0.78, 0.1),
		"zone_contested": Color(0.85, 0.45, 1.0), "zone_next": Color(0.8, 0.88, 1.0),
		"ping_spot": Color(0.95, 0.95, 0.95), "ping_enemy": Color(1.0, 0.78, 0.1),
		"radar": Color(1.0, 0.78, 0.1), "warning": Color(1.0, 0.75, 0.1),
	},
	{ # Tritanopia (blue-yellow): teal against red and pink.
		"team_a": Color(0.2, 0.85, 0.85), "team_b": Color(1.0, 0.35, 0.4),
		"survivors": Color(0.3, 0.9, 0.9), "infected": Color(1.0, 0.45, 0.65),
		"feed_killer": Color(1.0, 0.45, 0.5), "feed_victim": Color(0.4, 0.9, 0.9),
		"hit": Color(1.0, 1.0, 1.0), "hit_head": Color(1.0, 0.6, 0.8), "hit_kill": Color(1.0, 0.15, 0.15),
		"health_high": Color(0.3, 0.9, 0.9), "health_low": Color(1.0, 0.25, 0.3), "shield": Color(0.95, 0.95, 1.0),
		"zone_free": Color(0.95, 0.95, 0.95), "zone_mine": Color(0.3, 0.9, 0.9), "zone_other": Color(1.0, 0.3, 0.35),
		"zone_contested": Color(1.0, 0.55, 0.85), "zone_next": Color(0.8, 0.95, 0.95),
		"ping_spot": Color(0.85, 1.0, 1.0), "ping_enemy": Color(1.0, 0.25, 0.3),
		"radar": Color(1.0, 0.25, 0.3), "warning": Color(1.0, 0.2, 0.2),
	},
]


## The player's colour mode (index into MODE_NAMES).
static func mode() -> int:
	return clampi(int(Profile.get_setting("color_mode")), 0, SETS.size() - 1)


## The colour of `role` in the player's colour mode.
static func color(role: String) -> Color:
	return SETS[mode()][role]


## The health bar's colour at `frac` (0 empty .. 1 full).
static func health(frac: float) -> Color:
	return color("health_low").lerp(color("health_high"), clampf(frac, 0.0, 1.0))
