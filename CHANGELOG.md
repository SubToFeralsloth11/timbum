# Changelog

## 2.4.3

### Scopes
- **Built-in scopes look through like custom ones:** the Sniper, DMR and Crossbow no longer black out the screen when you aim. You look through the scope on the gun, with its dark housing as a border round the lens and the rest of the gun in view. The Sniper keeps its black crosshair, the DMR and Crossbow their red chevron, and the zoom is unchanged.

## 2.4.2

### Custom scopes
- **Look through the scope itself:** aiming brings the eyepiece up to your eye and the lens sits where the scope really is on the gun, with the scope's housing drawn round it as a border in its body colour. The rest of the gun, the mount, turrets and gear stay in view round it, and the lens follows the gun's sway and recoil.
- **The lens takes the scope's shape:** a Prism Scope looks through a triangle, square bodies (Square Block, Box Reflex, Pixel Cube, CRT, Thermal) a square, Octagon and Hex Tubes their shapes. Other bodies use the VIEW SHAPE you pick, which now includes Triangle.

## 2.4.1

### Scopes and sights
- **Custom scopes are see-through:** no more black circle round the lens. Aiming keeps your gun on screen, so you look through the scope on top of it, with only the lens tint inside the view shape. Guns' own built-in scopes are unchanged.
- **Free SIGHT ZOOM:** every gun you own has a SIGHT ZOOM slider in its shop panel. Iron sights and red dots (like the AR's) zoom in up to 2x; guns with a built-in scope zoom out down to 0.5x. Saved per gun; hidden while a custom scope is on (its POWER sets the zoom).

## 2.4.0

### Bedwars
- **New mode: Bedwars** on Bed Islands (two team islands, two diamond islands, an emerald island, all over the void). Forges pile up iron and gold, the outer islands diamonds and emeralds; stand on a pile to collect it. Press interact at your island's shop for wool, planks, end stone, swords, armour, a bow, arrows and golden apples, and at the upgrades stand for team Sharpness, Protection and Forge. Right click places blocks, left click breaks blocks players placed; crouch to sneak so you can't walk off an edge and bridge like Minecraft Java. Break the enemy bed and their next death is a FINAL KILL; the last team standing wins.
- **Bedwars swords only:** Wooden, Stone, Iron and Diamond swords (no guns), with a Minecraft-style attack cooldown shown under the crosshair (spam clicking does little), crits on falling hits and knockback. Bows draw and drop arrows; armour and Protection cut damage.
- **Bedwars bots** gear up at the forge and shop, cover their bed in blocks, bridge round the flank, dig through and break your bed, time their sword hits, jump for crits and shoot the bow at range.

### Updates
- An **UPDATE AVAILABLE** screen opens on the home screen when a new version is out: DOWNLOAD & RESTART installs it and restarts straight into it.

### Custom mutators
- **Make your own rules** for bot matches and hosted games: CUSTOM MUTATORS in match setup sets one weapon for everyone (any gun or melee weapon), max health (25 to 400 %), gravity, player size, move speed, damage and jump height, and switches Headshots Only, Infinite Ammo and No Grenades. They stack on the random mutator, bots follow them, presets keep them, and the lobby and scoreboard list them. Modes without guns skip the gun options; the panel says which picks a mode ignores.

### Match setup
- **No more scrolling at 720p:** all 13 mode cards, every built-in map card and every rule of the chosen mode (and the host's connection, addresses and port) fit on the screen. The presets moved to the top bar and the mode's rules text sits under the mode cards. Only your own custom maps scroll when there are many.
- **Bedwars** has its own card, emblem and rules: players, bot difficulty, time, weather and custom mutators.

### Map editor
- **Bulk tools:** BOX (B, solid or hollow with H), WALL (V, 1 to 12 high with [ and ]) and FLOOR (F) fill or carve a whole shape between two clicks, with a ghost of the shape first. SELECT (G) marks an area to fill (Ctrl+F), clear (Delete), replace the aimed block type with yours (T), copy, cut and paste (Ctrl+C / X / V) and mirror the copy (M, Shift+M). Each is one undo step; the side panel has buttons for all of it. Map files are unchanged.

### Results screen
- **Scrolls:** everything above the buttons (table, highlights, rewards, next match, loadout) scrolls with the mouse wheel, the scrollbar or the right stick, so it fits a 720p screen; the timer, Start Next Match and Leave stay pinned at the bottom. It still brings your own row into view.
- **Match time and MATCH SCORE:** the results show how long the match lasted and a SCORE column for every player, worked out once by the host so everyone sees the same numbers. Under the highlights, your score is itemised: kills, headshots, deaths, objective (flag captures and returns, points, race progress, or beds broken in Bedwars), placement or team result, and time played. No cap; it works in every mode.

### Season pass
- **Takes the whole season now:** before, the 30 tiers were done in about two days. Season XP is now its own currency (30 a match, 3 a kill up to 15, 25 a win; 60 per daily challenge, 250 per weekly) and a tier costs 1,200. An hour a day finishes it around 31 December.
- **Season quests:** four new quests every Monday (16 Nov to 21 Dec), worth 600 season XP each, counting matches online and offline. Tiers 6, 11, 16, 21, 26 and 30 also need that week's quests. The SEASON screen lists every week with your progress, when it opens and the tier it unlocks.
- **Everybody's pass was reset once:** season XP, claimed tiers and the 12 season cosmetics (unequipped back to the defaults; coins you claimed stay). A notice on the home screen explains it.

### Levels
- **No level cap and no prestige:** the PRESTIGE button, the ★ badges and the rank are gone. Levels take longer: 750 + 400 per level + 15 per level² XP each (about 5,600 at level 10, 56,000 at level 50).
- **Level flame:** your level burns in a live, flickering flame that gets brighter, healthier and a little bigger as you climb (ember, orange, gold, white-hot, blue, violet, rainbow from 100). It shows on the home screen card, the results, Stats, the scoreboard and the lobby.
- **Every 5 levels** a LEVEL UP banner with a flame burst plays at the top of the results screen, out of the way.

## 2.3.2: Smarter bots, block-sized hiders, one-click updates (2026-11-20)

### Bots
- **Seekers chase and tag** in Tag, Hide and Seek and Block Hunt instead of fighting like it's Deathmatch: no more strafing, keeping range, peeking or lying down. They sprint straight at you, cut you off where you're heading and swing as soon as you're in reach.
- **Seekers search properly:** at each spot they check, they stop and look around before moving on.
- **Parkour bots finish the course:** they no longer walk off the platform after a jump pad landing, and they don't get stuck standing on the Hurdles. Before, they stalled at checkpoint 2.

### Block Hunt
- Your disguise is now exactly one block tall, not slightly shorter.
- Hiders fit through one-block gaps, see from the middle of their block and can't peek.

### Updates
- When a new version is out, the main menu shows **DOWNLOAD & RESTART**. Press it once and the game downloads the update and restarts into the new version.

## 2.3.0: Parkour (2026-11-20)

A new mode with no guns: race up an obstacle course. The game shows these notes once when you first open 2.3.

### New mode
- **Parkour:** everyone races up the **Parkour Run**, a floating course over a lava sea. It has 14 stages and gets harder as it climbs, starting with stepping stones and stairs, then balance beams, hurdles, jump pads, a pad tower, 1x1 pillars, zigzag ladders, long sprint jumps and pad chains. Each stage's blocks change colour from white to red as it gets harder.
- **Checkpoints:** a gold pad ends every stage. Fall off and you're put straight back on your last checkpoint (it counts as a fall, not a death). The HUD shows your stage, its name and your falls.
- **Winning:** the first to the finish wins and the match ends 20 seconds later. At the time limit, whoever reached the furthest checkpoint first wins. The scoreboard shows each player's checkpoint, finish time and falls.
- No guns, no grapple and no hits. Bots run the course too and miss a jump now and then (easy bots more often).
- New medals: **Speedrunner** (the fastest run to the finish) and **Sure Feet** (the fewest falls).

## 2.2.0: Hide & Seek (2026-11-19)

Three new modes with no guns, custom scopes you build part by part, two new guns and a batch of fixes. The game shows these notes once when you first open 2.2.

### New modes
- **Tag:** nobody gets hurt. One player is IT; swing your melee weapon at someone or run into them to make them IT. The new IT waits 3 seconds and can't tag you straight back. You score a point every second you're not IT and 3 for a tag. Most points wins.
- **Hide and Seek:** there is always one seeker. They count blindfolded for 20 seconds while everyone hides. When the seeker catches a hider, they swap: the hider becomes the seeker and counts for 6 seconds. There are no nametags, and hiders can see the seeker through walls (in red). Hiders score a point a second while the seeker searches; a catch scores 10.
- **Block Hunt:** pick one of 4 blocks taken from the map and become it. Hold still and your block snaps onto the grid so it lines up with the real ones. After 30 seconds, one player in five becomes a seeker and hunts with their melee weapon; found hiders seek too. No nametags. Hiders win if any are left when time runs out.
- **Balloons (Block Hunt):** press fire to release a balloon for points: small +1, medium +3, big +7. A balloon rises from you in a burst of confetti and your block glows its colour (3, 6 or 10 seconds), and the bigger it is the longer you wait for the next one (6, 15 or 30 seconds). Pick the size with 1-3 or the scroll wheel.
- **Smarter bots for hiding:** hider bots look for covered spots away from the seeker and, in Block Hunt, the spot and block that match their surroundings best. They hold still and run when they're spotted. Seeker bots search places they haven't checked, follow balloons and running footsteps, and only spot a hider they could really make out: one that moves, stands out in colour against what's behind it, shows past cover or (in Block Hunt) hasn't settled onto the grid.

### Weapons
- **New: Pulse Cube** (650 coins), an automatic rifle: 800 rounds a minute, 35-round magazine and little recoil, but its damage drops off sooner. Up close it kills as fast as the AR-Cube and is easier to keep on target; the AR-Cube wins at range.
- **New: Rapid Block** (1000 coins), a fast semi-automatic marksman rifle: 50 damage to the body and 84 to the head, 10 rounds, open reflex sight.
- **AR-Cube:** damage 25 → 23.
- **Stacker LMG and Cuber .44:** your hand and parts of the gun no longer cover the middle of the screen when you shoot or aim.

### Custom scopes
- **Shop > a gun you own > BUY CUSTOM SCOPE** (5,000 coins per gun) gives that gun a custom scope with 3 starter parts, then opens the **SCOPE BUILDER**: a live 3D preview you can turn, and 97 parts in 7 groups (bodies, mounts, front ends, eyepieces, turrets, gear, decorations), each with its own colour (24 swatches or any colour), one of 12 finishes (matte, gloss, metal, glow, camo, carbon, holo, your gun skin...), length, width, position and roll. Up to 24 parts.
- **Every part you add costs 150 coins.** Removing parts gives nothing back; changing colours, finishes, sizes, positions and the optics is free and saves by itself.
- **Optics:** 16 reticles, including one you paint pixel by pixel, its colour, glow and size, lens tint, 6 view shapes (including an open reflex view), view size, zoom, height and position. Zoom stays fair: guns without a scope can go up to 2x their own sights, and the sniper, DMR and crossbow can only zoom out.
- **Turn it off** any time with SCOPE ON / OFF in the builder or under CUSTOM SCOPES in the locker. It's free both ways and keeps the purchase and your design.
- Other players see your scope on your gun, and aiming through it shows your view shape, tint and reticle (also in the kill cam).

### Fixes
- Nametags follow the player's head when they crouch or lie down.
- Lying down under a 1-block gap and getting up no longer puts you inside the blocks: you stay down (or crouched) until there is room.
- No more thin gaps between blocks: at chunk edges, around swaying leaves and at the edges of water and lava.

## 2.1.1 (2026-11-04)

### Fixes
- Clip studio: after you fly the drone and let go of the right mouse button, it stays where you flew it, even when you then move the playhead. Before, it jumped back to the first key, so every key after the first was saved in the same place. The drone goes back onto the key path when you press ADD KEY, CLEAR or play.

## 2.1.0: Clips & Gallery (2026-11-04)

Save your best kills and turn them, and your photos, into videos and pictures. The game shows these notes once when you first open 2.1.

### Kill clips
- **New setting: Settings > Gameplay > Clips** (off until you switch it on). With it on, the game keeps the last 22 seconds of the match.
- After a kill, **double-tap K** (up to 10 seconds later) to save that kill with the 10 seconds before it. A card says CLIP SAVED; a clip saved straight after the kill waits a moment to catch the victim falling.
- K still skips the kill cam while you are dead. The clip key is **Clip your last kill** in Settings > Controls, on any key, mouse button or controller button.
- A clip records everyone's moves, shots, grenades, rockets, explosions, hits and deaths rather than a video, so it is small and can be filmed again from anywhere. It works in every mode with respawns, offline and online (not in Tactical).

### Gallery
- **New GALLERY button** on the home screen, beside LOCKER and SHOP: every clip and photo you saved, newest first, with ALL / CLIPS / PHOTOS, OPEN, SHOW and DELETE.
- Photo mode now saves the scene with each photo, so a photo can be opened and re-shot: another angle, time of day, weather or look. Photos from before 2.1 open with the look tools only.
- VIDEO EXPORTS and PICTURE EXPORTS open Movies/Timbum and Pictures/Timbum.

### Clip studio
- **Cameras:** POV (through the eyes of you or any player in the clip, gun in hand), CHASE, ORBIT (radius, angle and speed) and DRONE, which you fly with the right mouse button held, like photo mode. Drone keys make the drone fly a smooth path through the views you set.
- **Scene:** day, sunset or night, and clear, rain, thunderstorm, snow, sandstorm or ash. Field of view, depth of field and a YOU tag.
- **Look:** 16 filters (Cinematic, Black & white, Sepia, Noir, Vintage, Vibrant, Cool, Warm, Neon, Retro 8-bit, VHS, CRT, Thermal, Dream, Comic), exposure, contrast, saturation, warmth, vignette, film grain, colour fringe, sharpen, pixelate, cinema bars and a TIMBUM watermark.
- **Timeline:** scrub, trim with IN / OUT handles (or I / O), step frames with the arrow keys, play at 0.25x to 2x (slow motion slows the effects and deepens the sound).
- **Export video:** 720p, 1080p, 1440p or 4K at 30 or 60 fps with the game's sound, as an MP4 in Movies/Timbum (on Windows an AVI unless ffmpeg is installed). A second copy of the game draws every frame at full quality in a small window, however long each frame takes, so the video is smooth whatever your frame rate; the studio shows its progress and can cancel it.
- **Save frame / export photo:** a PNG of the picture with its look, in Pictures/Timbum.

### Also
- The kill cam now shows the burst and sound of anyone who dies during the replay.

## 2.0.1 (2026-11-04)

- **Automatic updates.** From this version on, Timbum updates itself. A few seconds after it starts it checks the latest GitHub release, downloads the new game data in the background and shows **UPDATE READY · RESTART** at the bottom left of the home screen. RESTART, or just closing the game, installs it; the next start runs the new version. Updates are signed and checked before they are used. When an update needs the whole app (a new Godot version), the button reads **DOWNLOAD** and opens the release page instead. On Windows the game data now sits beside the game as `Timbum.pck`; keep it next to `Timbum.exe`.
- **Developer tag.** The admin panel (cheats) and the Dev Pack are now for the developer's profile only. A profile is the developer's when it carries a signed developer tag; only the public key ships, so the tag can't be made by editing a save. Every other profile has no ADMIN PANEL button, F1 does nothing, and the Dev Pack can't be owned (the credits code says "Invalid code"). The tag is saved with the profile and travels in progress exports.
- **App icon.** The icon no longer has a dark rim and drop shadow around it, and its grid lines are solid, so it looks clean on dark backgrounds, the Dock and the Windows taskbar.

## 2.0.0: The Big Block Update (2026-11-04)

The biggest Timbum update yet: three new weapons, two new modes (Capture the Flag and One in the Chamber), two new maps (Moon Base and Volcano Forge), weather, a free season pass and an in-game update log. The game shows these notes once when you first open 2.0 (WHAT'S NEW), and the version button at the bottom left of the home screen opens them again.

### Three new weapons
- **Rail Cube** (900 coins): hold fire to charge a railgun, then let go to fire a bright cyan beam that goes through up to three players in a line. A full charge does 90 to the body and kills with a headshot.
- While you charge, the coils glow, a whine rises and a ring fills around your crosshair. Other players see the glow and hear the whine too.
- **Cube Lobber** (800 coins): a grenade launcher with a 6-round drum. Its cube grenades bounce off walls and floors and blow after 1.6 seconds, or straight away when they hit a player. In Demolition they break blocks.
- **Pixel Scythe** (700 coins): a long, slow melee sweep that reaches 2.9 m and catches players a little off your aim. Two hits kill.
- All three come with their own models, sounds, kill-feed icons, skins, charms, mastery camos and per-weapon stats. You can try them at the Firing Range console.
- The Rail Cube and Cube Lobber join the Gun Game ladder (now 21 guns). Bots use all three: they charge the Rail Cube before they fire and never use the Lobber at point blank.

### Capture the Flag
- **New mode: Capture the Flag.** Two teams, a flag on a glowing stand at each base on every deathmatch map. Grab the enemy flag and run it onto your own stand while your flag is home to score. First to 1, 3 or 5 captures wins.
- The carrier wears the flag on their back for everyone to see, runs a little slower and can't use the grapple hook. Kill them and the flag drops; touch your own dropped flag to send it home, or it goes home by itself after 20 seconds.
- Markers through walls tell you what to do with each flag (TAKE, DEFEND, ESCORT, KILL CARRIER, RETURN with a countdown), the compass points to both, and the score card shows where each flag is.
- Callouts for every take, drop, return and capture, a scoreboard with captures and returns, and two new medals: Flag Runner and Flag Defender.
- Bots play it properly: attackers steal and run flags home, defenders guard the stand and return dropped flags, and everyone hunts the player carrying their flag.
- New challenges (capture flags, return your flag) and achievements: Flag Bearer, Flag Master, Homeward and Flag Day. Works offline and online, including for players who join mid-match.

### One in the Chamber
- **New mode: One in the Chamber.** Everyone gets the Cuber .44 with a single round plus their own melee weapon. Any hit with the Cuber .44 kills, head or body.
- Every kill, with the gun or your melee weapon, gives you a round. Rounds stack, so a good streak builds up a reserve. Each new life starts with one round.
- You have 3 lives (pick 1, 3 or 5 in match setup). Run out and you watch the players still in for the rest of the match. The last player standing wins; at time up, the most lives left wins.
- A new card shows your lives as hearts, your rounds as cartridges and how many players are still in. Callouts for every player knocked out, your last life, each round you earn and the last two standing.
- No grenades, ammo crates, killstreaks or mutators, so it is all about the shot. Health packs stay.
- Bots only take their shot when it will land and otherwise rush you with their melee weapon.
- New medals (Last One Standing, Dead Eye, Flawless), a new challenge and two achievements: One Shot Wonder and Untouchable.
- Match setup now fits all eight mode cards on one screen.

### New maps: Moon Base and Volcano Forge
- Two new deathmatch maps in the rotation, the map vote and match setup (with their own map card pictures): Moon Base and Volcano Forge.
- Moon Base: a moon-dust base floating in space under a starry black sky with the Earth overhead, with a command dome, habitats, hangars, launch towers around a rocket, a comms tower and craters. Step off the edge and you fall into space.
- Volcano Forge: basalt forge halls and foundries around a glowing lava lake and lava channels, with drifting embers and a smoky red sky. Falling into the lava kills you, and the kill feed says Lava.
- Both maps have their own sunset and night looks: long moon shadows and earthlight at night on Moon Base, a deep red glow on Volcano Forge.
- Both play every mode, with jump pads, King of the Block zones and Capture the Flag stands, and bots know their way around them (and no longer wander into lava or water while strafing).
- The World Tour achievement now needs a win on all 10 deathmatch maps. If you already have it, you keep it.
- The map editor has eight new blocks: regolith, moon rock, hull panel, solar panel, basalt, basalt brick, magma and lava.

### Weather
- **Weather.** Every match now rolls its weather for the map: rain and thunderstorms on most maps, snowfall on Snow Fort, sandstorms on Desert Ruins and falling ash on Volcano Forge. Moon Base stays clear (no air), and most matches are still clear.
- Rain streaks, snowflakes, blowing sand and ash fall around you, and stay outside: nothing falls under roofs or through floors. Fog, sky and sunlight change with the weather, and night rain and snow still look like night.
- Thunderstorms darken the sky and flash with lightning, with thunder rolling in a moment later. Rain, wind and thunder have their own sounds, a little quieter when you are under a roof, and they pause with the match.
- Match setup has a new WEATHER row: Auto, Clear or any weather the picked map allows (on Rotation: Auto, Clear, Rain or Storm). It is saved in your presets.
- The match intro card and the results screen's "next match" line name the weather. Online, everyone gets the same weather.
- Settings > Video has a new "Weather effects" option: Off, Low or High. The Low preset picks Low. Off removes the falling particles but keeps the weather's fog, lighting and sound.

### Season 1: Block Party
- **New: a free season pass, Season 1: Block Party.** 30 tiers; every 1,000 season XP unlocks one. Matches and challenges earn season XP, and it keeps counting even at the level cap or after prestige.
- Rewards on every tier: coins, plus 12 exclusive cosmetics you can't buy: four skins (Confetti Pop, Gift Wrap, Dance Floor and the animated Disco Fever at tier 25), three hats (Balloon Pup, Party Cake, Disco Ball), two charms, two sprays and the Disco Star outfit at tier 30.
- Open SEASON on the home screen (a gold badge shows how many tiers are waiting): scroll the tier track, preview any reward in 3D, CLAIM tiers one by one or CLAIM ALL, and equip what you unlocked straight away. Works with mouse, keyboard and controller.
- The shop shows the season cosmetics on SEASON cards with the tier that unlocks them, and other players see them on you online.
- The results screen shows the season XP each match earned and your tier, and a toast pops mid-match when you reach a new tier.
- The season ends on 31 December 2026, but nothing is lost: the pass stays open and every tier stays claimable afterwards. Two new achievements: Party Starter (tier 10) and Life of the Party (tier 30).

### Fixes
- The Map Editor has a new FLAGS tool for placing the two Capture the Flag stands. Custom maps without stands use the two spawns farthest apart. If those spawns are too close together, the map is greyed out for Capture the Flag in match setup, with a hint explaining why. Matches no longer end the moment they start because both flags sat on the same spot.
- In Capture the Flag, the kill cam now shows the flags where they were: on the carrier's back or lying where they were dropped.
- One in the Chamber no longer announces "YOU TAKE THE LEAD" at the start of every match.
- The Firing Range now shows the Rail Cube's real distance to the dummy, not the distance to the wall behind it.
- With a keyboard or controller, you can now reach the WHAT'S NEW button: move down from the daily reward button.
- The match's weather now appears in the Tab scoreboard title and under the results title.
- Once the season pass is finished, the results screen no longer shows season XP you didn't get, and near the end of the pass it shows only the XP that was actually added.
- Fixed an error bots could hit when the player they were chasing left or switched to spectating.
- The Map Editor now flags a Capture the Flag stand that bots can't walk to (for example one on a ledge without a jump pad), and such maps are no longer offered for Capture the Flag, so bot matches on them can score.
- Match setup now says why a custom map can't host Capture the Flag (for example stands too close together) instead of always saying it has no flag stands, and that note only shows in Capture the Flag.
- With a controller or keyboard, focus now stays inside the WHAT'S NEW panel and the tutorial offer instead of slipping to the home screen behind them; right from a page goes to NEXT (or GOT IT on the last page).
- On the season screen with a controller, press down on a claimed cosmetic to reach EQUIP, and up from the tier cards reaches CLAIM ALL.

### Update log
- **WHAT'S NEW.** The first time you open the game after an update, a panel lists everything new, one page per part of the update. Close it with GOT IT (or Esc / B); the version button at the bottom left of the home screen opens it again.

### Under the hood
- Network protocol version 29: 2.0 players can't join 1.x hosts and the other way round.
- Version 2.0.0.
