# Timbum

A blocky shooter made with Godot 4.7: free-for-all deathmatch, Team Deathmatch, Gun Game, King of the Block, Infected, or 25 v 25 Tactical in an office block. Play against bots offline, or host a match and have friends join from the same Wi-Fi, with a room code, through Steam, or by IP.

## Features

- **Free-for-all deathmatch.** The first player to reach the kill limit wins, or whoever has the most kills when time runs out. When the match ends, every player's camera turns to the winner, who performs their win emote. Then a results screen shows the final table, match highlights (best streak, sharpshooter, survivor), your accuracy and most-used weapon, an itemised list of the coins and XP you earned, and the next map, mutator and time of day. You can switch your primary and secondary for the next match right there, and start it early once most of the players in the lobby press Start Next Match (everyone sees how many are ready). Hold Tab to see the scoreboard over the results screen too.
- **Team Deathmatch.** Pick TEAM DM in match setup. Two teams, ALPHA (blue) and BRAVO (orange), on the deathmatch maps with respawns. Every kill of an enemy scores a point for your team; the first team to the kill limit (25 to 100, default 50) wins, or the higher score when time runs out (equal scores are a draw). Friendly fire is off. Humans are split evenly and bots fill both teams evenly; you spawn on your team's half of the map near teammates and away from enemies. Team colours show on armbands, nametags (teammates' tags show through walls), the kill feed and the scoreboard (grouped by team, with each team's score), and the top of the HUD shows the score race. A team win counts as a win for everyone on the winning team. Mutators work as in Deathmatch.
- **Gun Game.** Pick GUN GAME in match setup. Everyone climbs the same ladder of guns: SMG, AR-Cube, Tri-Cube, LMG, Brick Buster, Block Marksman, Voxel Longshot, Boom Block, Bitstorm MP, Pocket Boomer, Tri-Tap, Cuber .44, Whisper .22 and Block 9, then the Pixel Blade. Every kill hands you the next gun, which you draw on the spot. A knife kill (quick melee counts) also knocks your victim down a step. The first knife kill on the last step wins; when time runs out, the highest level wins. Match setup offers a ladder of 5, 9 or all 14 guns (shorter ladders skip evenly through the list). Your loadout is ignored, there are no grenades, and Rocket Party and Snipers Only are never rolled. A card in the top left shows your level, the gun you hold and the next one; the scoreboard is sorted by level. Bots fight with whatever gun they are on, and on the knife they hunt the nearest player.
- **King of the Block.** Pick KING in match setup. A glowing zone sits on one of each map's 5 to 9 spots. Stand in it alone and you score a point every second; with two or more players inside it is contested and nobody scores. The zone moves to another spot every minute, with a 10-second warning that also shows where it is going. The first to the score limit (60 to 200, default 120) wins, or whoever has the most points when time runs out. The zone glows gold when free, green when it's yours, red when someone else holds it and pulses magenta when contested. A marker shows it and how far away it is through walls, the compass points to it, and a card shows who holds it, your capture progress, your points and when it moves. Bots head for the zone and fight in it.
- **Infected.** Pick INFECTED in match setup. Everyone starts as a Survivor with their own loadout. Ten seconds in, one random player turns Infected: knife only, no grenades, 150 health, 15% faster and tinted green. A Survivor who dies turns Infected and respawns as one. The Infected win as soon as nobody survives; the Survivors win if any are left when the clock runs out. Players joining after the infection started join the Infected. The HUD shows your role and the survivors left, the scoreboard shows everyone's role, and the results list who survived and who infected the most. Infected bots hunt the nearest Survivor with the knife; Survivor bots shoot and back away. Rocket Party and Snipers Only are never rolled in Infected.
- **Tactical mode (25 v 25).** Pick Tactical in match setup (Play vs Bots or Host Game). 50 players, two teams of 25 (ALPHA starts at the west end of Block HQ, BRAVO at the east), bots in every slot no human takes; online, humans are split evenly between the teams. Everyone spawns with only the knife, frags and their tactical grenade: guns lie in the rooms of the three-storey building (every primary and secondary, rocket launchers and snipers rare), and walking over one picks it up into its empty slot; with that slot full, press B to swap. Ammo, health and grenade crates are spread around too, and the dead drop their gun. A match opens with a 30-second planning phase behind glowing barriers: the floor plan (M) shows each storey with your teammates and the weapons, and clicks put ATTACK and HOLD markers your whole team sees in the world and on the compass. Bots move in squads of five along different routes (both stairwells, the central hallway, the atrium balconies, the alleys outside), stop and hold at each stage, and follow your markers. One life: when you die you spectate your living teammates (left/right mouse to switch) and can leave from the menu at any time. The last team standing wins (at the time limit, the team with more players alive; equal is a draw); coins and XP count a team win as victory. At the end the winning side's top survivor performs their win emote, then the results screen has a NEW GAME button instead of a countdown. Tactical plays slower: no grapple hook and no sliding.
- **Bots.** Easy, Normal and Hard bots navigate with a navmesh. They strafe, aim-track, throw frags and tacticals and fall back to their knife. With a sniper or rocket launcher they switch to their other gun when you get close. They also pick up health when hurt and ammo when low, and use the same moves you do: they slide, peek around corners, go prone to snipe at long range and grapple up ledges and across gaps. Smoke blocks their sight and a flash blinds them. They aim a little sharper at whoever is running away with the match and ease off on players who are behind. Bots fill the empty slots, and one drops out each time a human joins.
- **Online play without typing an IP.** Up to 12 players; the host's machine runs the match. Friends on the same Wi-Fi see the game listed, anyone else pastes a room code (no port forwarding), and Steam lobbies, WebRTC codes, virtual LANs and plain IP addresses work too. See [Playing online](#playing-online).
- **15 weapons.** Secondaries: Block 9 pistol, Cuber .44 revolver, Bitstorm MP machine pistol, Tri-Tap burst pistol, Pocket Boomer sawn-off and the suppressed Whisper .22 (no tracer, flash or flyby for anyone else). Primaries: Bit-SMG, AR-Cube rifle, Tri-Cube burst rifle, Brick Buster shotgun, Stacker LMG, Block Marksman DMR with a low-power marksman scope, Voxel Longshot sniper with a high-power scope and Boom Block rocket launcher. Plus the Pixel Blade knife.
- **Grenades.** Every player carries two frag grenades, which explode the moment they touch a wall, the floor or a player, and one tactical grenade picked in the locker: a Smoke Block (a 10-second cloud) or a Flash Cube (blinds whoever is looking at it).
- **Movement.** Crouch while sprinting to slide (slopes keep it going, jump out of it to keep the speed). Peek left and right around corners; the eye, the view and your head hitbox lean out, stopping at walls. Go prone to lie flat: you crawl slowly but aim steadier (less spread and recoil) and present a much smaller target; crouch, jump or prone again gets you back up (a sprinting slide can dive straight into prone). A grapple hook reels you to whatever you aim at within 42 m.
- **Every match plays differently.** The map rotation is shuffled, the time of day changes (day, sunset or night), and half the matches roll a mutator: Low Gravity, Turbo, Big Heads, Vampire, Rocket Party, Snipers Only or Glass Cannon. Rocket Party and Snipers Only hand everyone the Boom Block or the Voxel Longshot and keep your own primary as the backup in your secondary slot. You can switch mutators off in match setup.
- **Gunplay.** Aiming down sights, recoil, spread bloom, damage falloff, headshots, auto, semi and three-round burst fire, hitmarkers, damage numbers (rapid hits on one target add up into a single total), kill feed, kill streaks and multi-kills. Damage numbers and the kill feed can each be turned off in Settings. When you die, the camera turns to watch your killer (zooming in if they are far away, and dropping to where you fell or back to your body when a wall hides them) and the death screen tells you how far away they were, how many hits and how much damage they dealt you (shield included), and how much health (and Overshield) they had left.
- **Killstreak rewards.** Kills without dying earn rewards: 3 in a row a **Radar Sweep** (every enemy shows on your compass and on screen for 8 seconds; in team modes for your whole team), 5 an **Overshield** (+50 shield shown in cyan on your health bar, used up before your health) and 7 a **Block Bomber**: press 4 to aim it (the line of blasts shows on the ground), then fire or 4 again to call it in on that spot. Everyone sees a red ground warning for 2 seconds and hears the siren, then five explosions walk along the line; its kills are yours (with a bomb icon in the kill feed) but don't extend your streak. A card above your health shows your streak, the next reward, radar time and when an enemy radar has spotted you. Dying loses your shield, radar and an unused bomber. Bots earn and use rewards too, and run from a bomber's warning (not always in time). Match setup's KILLSTREAKS row turns them on or off; they are on by default in Deathmatch, Team Deathmatch and King of the Block, off in Gun Game, Infected and Tactical.
- **Quick ping.** In the team modes (Team Deathmatch, Infected and Tactical) press the middle mouse button to mark what you are aiming at for your team: aim at an enemy for a red ENEMY marker, or anywhere else to mark that spot with your name. Teammates (and only teammates) hear it and see the marker with its distance through walls and a pip on the compass for 6 seconds; your next ping replaces your last. Pings are limited to one every 0.6 seconds and three in five seconds. Bots call out enemies they spot the same way, and a teammate bot with nothing to shoot goes to check an enemy pinged nearby. In free-for-all modes the key does nothing.
- **HUD.** A compass (with pips for Tactical's team markers, King of the Block's zone, pings, radar contacts and airstrikes), a race against the leader (kills, Gun Game level or King of the Block points; in team modes, a bar per team: the team score race in Team Deathmatch, survivors and Infected in Infected, players left in Tactical), segmented health with a movement status line (sliding, peeking, grappling, blinded), and a weapon card with fire mode, magazine bar, your three slots and the frag, tactical and grapple readouts, all labelled with the keys you have bound.
- **8 deathmatch maps.** Village, Desert Ruins, Factory, Sky Islands, Snow Fort, Harbor Docks, Jungle Temple and City Rooftops, plus Block HQ for Tactical. Each has its own sky, fog and lighting. Health, ammo and grenade pickups are spread around every map. A taken pickup shows a faint ghost and a countdown until it comes back. On Sky Islands, Harbor Docks, Jungle Temple and City Rooftops, falling off (into the void, the water, the river gorge or the street) kills you.
- **Shop and locker.** Coins buy guns, 11 weapon skins (including camo, lava, neon, gold, diamond and galaxy), 10 hats, 9 outfits, 11 gun charms (little trinkets that dangle from every gun and swing as you move), 9 win emotes and 6 draw animations (twirl, barrel roll, drop in, sidewinder, toss and catch). Draw animations are only for looks: every one finishes in the normal switch time. The locker is where you equip your loadout (including your tactical grenade) and look.
- **Attachment upgrades.** The shop's ATTACHMENTS tab sells 10 upgrades that apply to every gun: Laser Sight (tighter hip fire and a visible laser), Recoil Grip, Bloom Stabilizer, Extended Mag, Speed Loader, Quick Optic (faster aiming), Long Barrel (damage holds up further), Light Stock (faster movement while aiming), Quick Holster (faster switching) and Grapple Motor (faster hook recharge). Each has 5 levels bought one at a time, and each level costs 1.75 times the last, so the first levels are cheap and noticeable and maxing one out takes a while.
- **Progression.** XP, levels, a daily reward and lifetime stats. **Stats > Export Progress** saves everything (coins, items, upgrades, stats, settings and key bindings) to a file, and **Import Progress** restores it, on the same computer or another one.
- **Per-weapon stats.** Stats has a table with your kills, accuracy, headshot share of kills and damage for every weapon you have used, plus frag grenades and the Block Bomber (whose kills count for them, never for the gun you were holding). A shot is one round: one trigger pull, each round of a burst (a three-round burst is three shots), one shotgun shell however many pellets hit, one rocket, one knife swing. A hit is a shot that struck at least one enemy, so accuracy never goes over 100%. Stats are kept in every mode, offline and online.
- **Weapon mastery.** 25, 75 and 150 kills with a weapon earn its Bronze (250 coins), Silver (500) and Gold (1000) mastery, each paid once and listed on the results screen. Gold unlocks that gun's mastery camo: black scales with glowing gold veins and an accent colour of the gun's own. Switch it on per gun with the CAMO switch in the locker's MASTERY section; everyone in the match sees it on that gun, in first and third person, and on the gun when you drop it in Tactical. The locker and the shop's weapon details show each gun's mastery progress.
- **Everything is generated by code.** Textures, models, sound effects and the chiptune music are all procedural; the only image files are the app icon, which is a render of the game itself. The block shader adds pixel-art relief, glossy metal, ice and water, swaying leaves, and a colour grade with sharpening (Settings > Video can turn the grade off).
- **Graphics settings.** Settings > Video has anti-aliasing (off, FXAA, MSAA 2x/4x or TAA), render scale, and separate toggles for shadows, ambient occlusion, bloom, reflections, the block shader effects (relief, swaying leaves, rippling water) and the colour grade. They all apply instantly. Picking a graphics quality preset switches these to that preset's values.

## Controls

Every action except Esc can be rebound in **Settings > Controls** (two keys or mouse buttons per action). The defaults:

| Action | Key |
|---|---|
| Move | WASD / arrow keys |
| Jump / Sprint / Crouch | Space / Shift / Ctrl or C |
| Prone (lie down / get up) | Z |
| Slide | Crouch while sprinting |
| Peek left / right | Q / E |
| Fire / Aim down sights | Left mouse / Right mouse |
| Reload | R |
| Primary / Secondary / Knife | 1 / 2 / 3 or mouse wheel, X swaps to the last weapon |
| Frag grenade / Tactical grenade | G / H |
| Grapple hook | F (again, or jump, to let go) |
| Call in Block Bomber (killstreak) | 4 (aim, then fire or 4 again; right mouse cancels) |
| Ping (team modes) | Middle mouse |
| Swap weapon / floor plan (Tactical) | B / M |
| Quick melee | V |
| Scoreboard | Tab (hold) |
| Chat | T or Enter |
| Pause / settings | Esc (pauses the match when playing against bots) |

## Playing online

**Host:** choose **Host Game**, pick your map and settings and a **Connection**, then press Start Hosting. Once the match starts, press Esc: the pause menu shows how friends can join (room code with a COPY button, your addresses, or a Steam invite button).

**Join:** choose **Join Game**, then whichever works:

| Way to join | Works across | What the joiner does | Needs |
|---|---|---|---|
| **Nearby games** | Same Wi-Fi / LAN | Click the game in the list | Nothing; hosts answer UDP discovery on port 47777 |
| **Room code** (Connection: Code + Wi-Fi) | The internet | Paste the code, press Join | Internet access. The code server ([noray](https://github.com/foxssake/noray) at `tomfol.io`) tells both sides each other's address so they connect directly; if the routers block that, it relays the game traffic. Codes are case-sensitive, so use COPY and PASTE. |
| **Steam** (Connection: Steam) | The internet | Accept the Steam invite, use **Find Steam Games**, or paste the lobby number | Steam open and signed in on both computers. Uses Valve's free test app (Spacewar, app id 480), so Steam shows you as playing Spacewar. |
| **WebRTC code** (Connection: WebRTC) | The internet | Paste the `W-XXXXXX` code | Internet access; peers meet through the free [PeerJS](https://peerjs.com) server. A fallback when room codes fail; no relay, so some strict networks can't connect. |
| **Address** | LAN, virtual LAN, or the internet | Type an IP or hostname and the port (default 7777) | For a virtual LAN, both players join the same [Tailscale](https://tailscale.com) or [ZeroTier](https://www.zerotier.com) network and use the address the host screen labels TAILSCALE or ZEROTIER. For a [playit.gg](https://playit.gg) tunnel, use the address it gives you. A public IP needs UDP 7777 forwarded on the host's router. |

The host's firewall must allow Timbum. Steam and WebRTC support are native add-ons for macOS, Windows (64-bit) and Linux (x86_64); see `addons/`.

## Running from source

1. Install [Godot 4.7](https://godotengine.org/download).
2. Open `project.godot`, or run `godot --path .`

## Building release versions

You need the Godot 4.7 export templates installed. Run:

```sh
godot --headless --path . --export-release "macOS"   build/macos/Timbum.zip
godot --headless --path . --export-release "Windows" build/windows/Timbum.exe
godot --headless --path . --export-release "Linux"   build/linux/Timbum.x86_64
```

The macOS build is signed ad hoc and not notarized. The first time, open it with right-click → Open.

## Project layout

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for module contracts, the networking model and collision layers.

Your save file (coins, items, upgrades, settings) is stored at `user://profile.json`. Its location depends on your OS (use Stats > Export Progress to back it up):

| OS | Save folder |
|---|---|
| macOS | `~/Library/Application Support/Godot/app_userdata/Timbum/` |
| Windows | `%APPDATA%\Godot\app_userdata\Timbum\` |
| Linux | `~/.local/share/godot/app_userdata/Timbum/` |

## License

MIT, see [`LICENSE`](LICENSE).
