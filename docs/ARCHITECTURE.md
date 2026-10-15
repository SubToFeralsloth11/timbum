# Timbum: architecture

Timbum is a blocky free-for-all FPS built with Godot 4.7 (GDScript, Forward+, Jolt).
Matches mix bots and humans. Humans join a host by IP over ENet.

## Design decisions

These were settled up front, choosing the standard option each time:

| Topic | Decision |
|---|---|
| Mode | Free-for-all deathmatch. First to the kill limit (default 20) or the most kills when time runs out (default 8 min). After a match: results screen, coins/XP, then the next map in rotation 12 s later. |
| Players | 2-12 per match. Bots fill up to the target player count (default 8). When a human joins, one bot leaves; when a human leaves, a bot comes back. |
| Networking | ENet, default port **7777**. The host is the server and also plays. Clients run their own movement and hit detection. The server owns health, kills, score, pickups, bots, projectiles, and the match clock. It sanity-checks every hit request: shooter alive, target alive, fire-rate budget, range. Offline play uses `OfflineMultiplayerPeer`, so the same code runs everywhere. |
| Art | All art is procedural; there are no external assets. Voxel maps use 1 m blocks, a 16x16 pixel-art texture atlas, vertex ambient occlusion, and ramps for elevation changes. Characters, guns, and hats are built from boxes. |
| Audio | All sound effects and the chiptune music are synthesised at startup into `AudioStreamWAV`. |
| Variety | Map rotation is shuffled each cycle. Each match the server rolls a time of day (day/sunset/night) and, when mutators are on, a mutator half the time (`Data.MUTATORS`: low gravity, turbo, big heads, vampire, rocket party, snipers only, glass cannon). Both travel to clients inside `Net.config`. |
| Economy | Coins come from kills, headshots, placement, level-ups, and a 24-hour daily reward. The shop sells guns, weapon skins (one equipped skin applies to every gun), hats, and outfits. Nothing is random; there are no loot boxes. Everything persists in `user://profile.json`. |
| Maps | Village, Desert Ruins, Factory, Sky Islands, Snow Fort. Each is generated deterministically from code, so every peer builds identical geometry from the map id. |
| Bots | Run on the server and use the Godot navigation mesh, baked at runtime from the map. Easy/Normal/Hard set reaction time, aim error (a floor of error never goes away), turn speed, view range and trigger discipline; getting shot makes a bot flinch. Bots loot pickups when hurt, strafe, and use every gun and the knife. |

## Layout

```
project.godot
scenes/main_menu.tscn        root Control, script ui/main_menu.gd
scenes/world.tscn            root Node3D, script scripts/game/world.gd
scripts/autoload/data.gd     Data    (catalogs, constants)
scripts/autoload/profile.gd  Profile (save data, settings, input map)
scripts/autoload/sfx.gd      Sfx     (procedural audio)
scripts/autoload/net.gd      Net     (ENet session, peer registry, scene flow)
scripts/world/               voxel maps: atlas, mesher, map generators, MapBuilder
scripts/models/              Models: guns, avatar, hats, pickups, skins
scripts/game/                world/match, player, weapons, projectiles, pickups, bots
ui/                          menus, shop, locker, settings panel, HUD
```

## Collision layers (bit numbers as in the editor; value = 1 << (n-1))

| Layer | Use |
|---|---|
| 1 | World (static map) |
| 2 | Player/bot movement bodies |
| 3 | Hitboxes (`Area3D`, metadata `part` = `"head"`/`"body"`, metadata `player` = the player node) |
| 4 | Pickups (`Area3D`) |
| 5 | Projectiles |

## Visual layers

| Layer | Use |
|---|---|
| 1 | Everything normal |
| 2 | First-person viewmodel only; drawn by an overlay camera. The main camera's cull mask excludes it. |

The local player's own avatar stays on layer 1 with `cast_shadow = SHADOW_CASTING_SETTING_SHADOWS_ONLY`.

## Contracts between modules

### Data (autoload, `scripts/autoload/data.gd`)
Constant dictionaries `WEAPONS`, `SKINS`, `HATS`, `OUTFITS`, `MAPS`. Item ids are snake_case strings.
Helpers: `Data.catalog(category) -> Dictionary` for category in `"weapons"|"skins"|"hats"|"outfits"`.

### Profile (autoload, `scripts/autoload/profile.gd`)
- `signal changed`: emitted on any change to coins, inventory, equipment, or settings.
- Fields: `player_name`, `coins`, `xp`, `level`, `owned: Dictionary` (category -> Array[String]), `loadout: Dictionary` (`primary`, `secondary`), `equipped: Dictionary` (`skin`, `hat`, `outfit`), `settings: Dictionary`, `stats: Dictionary`.
- `is_owned(category, id) -> bool`, `buy(category, id) -> bool`, `equip(category, id) -> bool`. Equipping a weapon sets the loadout slot from `Data.WEAPONS[id].slot`.
- `can_claim_daily() -> bool`, `claim_daily() -> int`, `xp_for_level(level) -> int`.
- `record_match(result: Dictionary) -> Dictionary`. Takes `{kills, deaths, headshots, placement, players, won, best_streak}` and returns `{coins, xp, levels_gained}`.
- `get_setting(key)`, `set_setting(key, value)` (applies the setting and saves), `apply_settings()`, `save()`.
- `peer_info() -> Dictionary`: what this player sends to the server, `{name, outfit, hat, skin, primary, secondary}`.

### Sfx (autoload, `scripts/autoload/sfx.gd`)
- `Sfx.play(name: StringName, pos: Variant = null, volume_db := 0.0, pitch := 1.0)`. Pass a `Vector3` for positional 3D sound or `null` for a flat UI sound. Unknown names are ignored with a warning.
- `Sfx.play_music(track: StringName)` with `&"menu"`, `&"match"`, or `&"results"`. `Sfx.stop_music()`.
- Buses `Master`, `Music`, `SFX` (`default_bus_layout.tres`).
- Required sound names: `shot_pistol shot_revolver shot_smg shot_rifle shot_shotgun shot_sniper shot_lmg shot_rocket explosion reload dry_fire knife_swing knife_hit hit_marker headshot kill_confirm hurt death footstep jump land pickup_health pickup_ammo grenade_throw grenade_bounce weapon_switch ui_click ui_hover ui_buy ui_error level_up coins countdown match_start match_end bullet_impact whizz spawn`.

### Net (autoload, `scripts/autoload/net.gd`)
- `const DEFAULT_PORT := 7777`
- `play_offline(config: Dictionary)`, `host(port: int, config: Dictionary) -> Error`, `join(ip: String, port: int) -> Error`, `leave()` (closes the session and returns to the main menu).
- `config` keys: `map` (map id or `"rotation"`), `bots_fill` (target total players, int), `difficulty` (0 easy, 1 normal, 2 hard), `kill_limit`, `time_limit` (seconds).
- `signal status(text: String)` reports connection progress or errors to the menu.
- `players: Dictionary` maps peer id to `peer_info`, kept on every peer.

### MapBuilder (`scripts/world/map_builder.gd`, `class_name MapBuilder`)
- `static func build(map_id: String, root: Node3D, quality: int) -> MapInfo` adds the chunk meshes, trimesh collision (layer 1), `WorldEnvironment`, `DirectionalLight3D`, and a `NavigationRegion3D` with a baked mesh to `root`.
- `MapInfo` (`class_name MapInfo`, a `RefCounted`) has `id`, `display_name`, `spawns: Array[Vector3]` (feet positions), `pickups: Array[Dictionary]` (`{kind: "health"|"ammo"|"grenade", pos: Vector3}`), `kill_y: float`, `bounds: AABB`, and `nav_map: RID`.
- `static func preview(map_id: String) -> ImageTexture` returns a cached top-down image of the map for menus. `root` must be in the scene tree when calling `build()`.

### Models (`scripts/models/models.gd`, `class_name Models`, static)
- `build_gun(weapon_id, skin_id) -> Node3D`: the origin is the grip and forward is -Z. Real-world scale. Child `Marker3D`s: `Muzzle`, `Sight` (rear sight, for ADS), and `Support` (off-hand point; absent on the knife).
- `Avatar.play_reload(duration)` / `stop_reload()`: third-person reload pose. Remote players' reloads are driven by the `FLAG_RELOAD` bit in their state flags. The first-person viewmodel (`scripts/game/viewmodel.gd`) animates the off hand fetching a magazine prop (`Viewmodel.MAGS`) via `ViewmodelArms.set_left_hand()`.
- `build_avatar(outfit_id, hat_id) -> Avatar`. `Avatar` (`class_name Avatar`, `extends Node3D`) has its feet at its origin, faces -Z, and is 1.8 m tall with eyes at 1.6 m. API: `set_look_pitch(rad)`, `animate(delta, speed: float, on_floor: bool, crouching: bool)`, `hold_weapon(weapon_id, skin_id)`, `play_shoot()`, `play_death()`, `reset_pose()`, `set_first_person(enabled)` (shadows only), `flash_hit()`.
- `build_hat(hat_id) -> Node3D`, `build_pickup(kind) -> Node3D`, `build_grenade() -> Node3D`, `build_rocket() -> Node3D`, `skin_material(skin_id) -> Material`.
