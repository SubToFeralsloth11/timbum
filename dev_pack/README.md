# THE DEV PACK

**Status: assets only. NOT in the game.** This folder has a `.gdignore`, so Godot doesn't parse,
import or export anything here. Nothing outside `dev_pack/` references it. Only add it to the game
when the owner asks; when you do, follow this file exactly.

## What it is

A four-piece cosmetic set that can't be bought. The only way to get it is the redeem code
**`LastMinutePlaysonyt`**. Matte black as the main colour, neon green (`#39ff14`) for every line,
and it all glows. It's the most exclusive item set in Timbum and should look and read that way
everywhere it appears.

| Piece | Category / id | Look |
|---|---|---|
| **Dev Suit** | `outfits` / `dev_suit` | Matte black bodysuit. Neon jagged grin on the face (ring eye with a beating pupil, X eye, zigzag teeth) in **half-size pixels**. Neon collar, belt, cuffs, knee pads and soles, circuit traces down the outer arms and legs, a circuit on the back and a "spine" up the back of the head. **The only animated outfit in the game**: bands crawl slowly along every line, light pulses run head to toe down the traces, the eye and chest core beat like a heart, and a faint scan line rises through the body. |
| **Dev Circuit** | `skins` / `dev_circuit` | Carbon-weave black gun with neon circuit traces and pads. The whole circuit **slides slowly** along the gun while bright pulses race towards the muzzle. |
| **Dev Halo** | `hats` / `dev_halo` | Black circlet with a neon inlay and a front node, a floating neon diamond halo and a floating pixel `</>` glyph above it. Shimmer climbs the neon. |
| **Dev Core** | `charms` / `dev_core` | Black cube in a neon wireframe cage, with a lit pip, on a gunmetal chain. |

**Kill flash:** when the wearer gets a kill, every pack piece they wear flashes. The neon lines go
white-hot and the whole set floods green, then it fades over 0.7 s (`DevPack.FLASH_TIME`). Other
players see it on the killer's body and gun; the killer sees it on their first-person arms, gun and charm.

Previews are in `preview/`: `turntable.mp4` / `turntable.gif` (a kill flash every 2 s),
`suit_motion.mp4` and `gun_motion.mp4` (the slowly moving lines), `hero.png`, `face.png`,
`front_unarmed.png`, `back_unarmed.png`, `hat.png`, `gun.png`, `flash_peak.png`.

## Files

- `dev_pack.gd`: `class_name DevPack`. Everything: catalog entries (`DevPack.ENTRIES`), the code
  check, three shaders (each with a first-person `VIEWMODEL` variant), materials, hat and charm
  meshes, and `DevPack.flash()`. It depends only on `MeshKit` and `Models.AVATAR_PARTS` / `Models.ATLAS_SIZE`.
- `preview/`: render stills and turntable. Reference only; don't ship them.

## How it's built (read before changing anything)

- Every pack material is a `ShaderMaterial` on one of `DevPack.shader("outfit" | "skin" | "solid")`.
  Each shader has `instance uniform float kill_flash`. The flash sets it **per GeometryInstance3D**,
  so the materials stay shared and cached and only the killer lights up. Don't duplicate the materials.
- Instance uniforms need Forward+ or Mobile; the project uses Forward+. The Compatibility renderer would break the flash.
- The suit atlas is **128x128** (`SUIT_SCALE` 2 × `Models.ATLAS_SIZE`), not 64. UVs are normalised,
  so the existing avatar meshes map it unchanged. Body texels are drawn as 2x2 blocks; the head's
  front face uses the 16x16 `_FACE` map (the half-size pixels).
- Mask channels (suit): r static neon, g circuit trace, b pulse phase (0 top of head .. 1 soles),
  a beating core (chest and pupil). Gun: r trace, g pad.
- First person: `DevPack.viewmodel_material(m)` returns the depth-squashing copy of a pack material
  (`m` unchanged if it isn't from the pack).

## Integration checklist (when asked to add it)

Do every step. Each one is needed.

1. **Move the script:** `git mv dev_pack/dev_pack.gd scripts/models/dev_pack.gd`. Leave `dev_pack/`
   (README, previews, `.gdignore`) where it is.
2. **Catalog** (`scripts/autoload/data.gd`): add each entry of `DevPack.ENTRIES` under its id
   (`DevPack.IDS`) to `OUTFITS`, `SKINS`, `HATS`, `CHARMS`, copied as literals; `data.gd` is
   const-only. Keep `price: -1`: `Profile.buy` refuses negative prices and `Profile.is_owned` only
   counts price 0 as free, so the code is the only way to own them. Keep `dev: true`.
3. **Models** (`scripts/models/models.gd`):
   - `skin_material()`: `if skin_id == "dev_circuit": return DevPack.skin_material()` before the
     cache and pattern checks.
   - `outfit_material()`: `if outfit_id == "dev_suit": return DevPack.outfit_material()` first.
     Change its return type from `StandardMaterial3D` to `Material`. Callers only assign `material_override`.
   - `build_hat()`: `if hat_id == "dev_halo": return DevPack.build_hat()`.
   - Check `build_outfit_extra("dev_suit", …)` returns null (no extras).
4. **Charm** (`scripts/models/gun_charm.gd` `mesh_for`): `if id == "dev_core": return DevPack.charm_mesh(LENGTH)`.
5. **First person** (`scripts/game/viewmodel.gd` `_converted_material`): at the top, after the
   cache check, add `if DevPack.is_dev_material(m): return DevPack.viewmodel_material(m)`. Without
   this the gun, charm and arms lose their animation in first person.
6. **Kill flash** (`scripts/game/world.gd` `_s_killed`, which runs on every peer): when
   `killer_id != victim_id` and `entities.get(killer_id)` is a Player, call `DevPack.flash(killer)`.
   That covers the third-person avatar, gun, hat and charm. If the killer is `local_player`, also
   call `DevPack.flash(local_player.viewmodel)` (null-check it). `flash()` ignores anything that isn't from the pack, so it's safe on every killer.
7. **Redeem code:** add `Profile.redeem_code(code: String) -> String` to `scripts/autoload/profile.gd`.
   If `DevPack.code_matches(code)` and the pack isn't owned yet, append every `DevPack.IDS` id to
   `owned[category]`, `save()`, `changed.emit()` and return "THE DEV PACK UNLOCKED". If it's already
   owned, return "Already redeemed". Otherwise return "Invalid code". The plain code must never
   appear in game code; only the SHA-256 in `DevPack.UNLOCK_CODE_SHA256` ships.
   Add a **REDEEM CODE** button and a LineEdit to the shop screen (`ui/shop_screen.gd`), built with
   `UIKit` like the rest of the screen, that calls it and shows the result.
8. **Shop / locker display** (`ui/shop_screen.gd`, `ui/ui_kit.gd`, locker): any item with `dev: true`
   shows a **CODE ONLY** tag instead of a price (never the raw `-1`) and no Buy button. Owned, it
   equips like any other item. Give owned pack cards a neon green (`DevPack.NEON`) border and title
   so the set stands out as exclusive.
9. **Bots** (`scripts/game/world.gd` around the bot loadout, `Data.OUTFITS.keys().pick_random()` etc.):
   leave `dev: true` items out of bot picks for outfits, hats, skins and charms.
10. **Network:** `Net` already accepts any catalog id for cosmetics (`net.gd` sanitise). Nothing to add.
11. **Docs:** document `DevPack` in `docs/ARCHITECTURE.md` (Models section: the pack, its
    shaders, the instance-uniform flash, and the 128 px suit atlas) and add a README changelog line.
12. **Verify:** load the game (through `~/.agents/bin/heavy`) with a fresh profile. Check: the pack
    shows CODE ONLY and can't be bought; a wrong code fails; `lastminuteplaysonyt` (any case)
    unlocks all four; equip them and check the shop preview, the third-person avatar and the
    first-person view (lines move, pulses run); get a kill against a bot and watch the flash on the
    viewmodel; check that a bot wearing a normal outfit doesn't flash.
