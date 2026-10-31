# THE DEV PACK

**Status: in the game.** The script now lives at `scripts/models/dev_pack.gd`; this folder keeps
the notes and previews and has a `.gdignore`, so Godot doesn't parse, import or export it.

## What it is

A four-piece cosmetic set that can't be bought. The only way to get it is a secret dev code typed
on the keypad behind **Stats > CREDITS > DEV**. It is not redeemable in the shop: the shop only
shows the pieces as CODE ONLY and never says what the code is or where to enter it.

**The code changed** from the one this pack was first made with. The old code no longer works;
the game only holds the SHA-256 of the new one (`DevPack.UNLOCK_CODE_SHA256`). Don't write the
plain code in the repo (code, docs or commits); ask the owner for it.

Matte black as the main colour, neon green (`#39ff14`) for every line,
and it all glows. It's the most exclusive item set in Timbum and should look and read that way
everywhere it appears.

| Piece | Category / id | Look |
|---|---|---|
| **Dev Suit** | `outfits` / `dev_suit` | Matte black bodysuit. A subtle face drawn with smooth, thin, dimmer neon lines: two small X eyes and a wide, closed, always-on creepy smile curling up at the corners, with stitches across it. Neon collar, belt, cuffs, knee pads and soles, circuit traces down the outer arms and legs, a circuit on the back and a "spine" up the back of the head. **The only animated outfit in the game**: bands crawl slowly along every line, light pulses run head to toe down the traces, the chest core beats like a heart, and a faint scan line rises through the body. |
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

- `../scripts/models/dev_pack.gd`: `class_name DevPack`. Everything: catalog entries (`DevPack.ENTRIES`), the code
  check, three shaders (each with a first-person `VIEWMODEL` variant), materials, hat and charm
  meshes, and `DevPack.flash()`. It depends only on `MeshKit` and `Models.AVATAR_PARTS` / `Models.ATLAS_SIZE`.
- `preview/`: render stills and turntable. Reference only; don't ship them.

## How it's built (read before changing anything)

- Every pack material is a `ShaderMaterial` on one of `DevPack.shader("outfit" | "skin" | "solid")`.
  Each shader has `instance uniform float kill_flash`. The flash sets it **per GeometryInstance3D**,
  so the materials stay shared and cached and only the killer lights up. Don't duplicate the materials.
- Instance uniforms need Forward+ or Mobile; the project uses Forward+. The Compatibility renderer would break the flash.
- The face isn't in the atlas: `OUTFIT_SHADER` draws it as smooth anti-aliased lines (signed
  distances, `face_sdf`) inside the head's front-face UV rect (`face_rect`), so it never looks pixelly.
- Mask channels (suit): r static neon, g circuit trace, b pulse phase (0 top of head .. 1 soles),
  a beating core (chest). Gun: r trace, g pad.
- First person: `DevPack.viewmodel_material(m)` returns the depth-squashing copy of a pack material
  (`m` unchanged if it isn't from the pack).

## Integration checklist (done; kept as the map of where it's wired in)

Steps 7 and 12 differ from the original brief, at the owner's request: no shop redeem button, and
the code changed.

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
7. **Redeem code:** `Profile.redeem_code(code: String) -> String` in `scripts/autoload/profile.gd`.
   If `DevPack.code_matches(code)` and the pack isn't owned yet, it appends every `DevPack.IDS` id to
   `owned[category]`, `save()`, `changed.emit()` and returns `Profile.REDEEM_UNLOCKED`
   ("THE DEV PACK UNLOCKED"); already owned returns `REDEEM_ALREADY` ("Already unlocked"), anything
   else `REDEEM_INVALID` ("Invalid code"). The plain code must never appear in game code; only the
   SHA-256 in `DevPack.UNLOCK_CODE_SHA256` ships.
   The only caller is the credits keypad (`ui/credits_panel.gd`, `CreditsPanel`): Stats > CREDITS
   lists the credits, and the DEV row opens a rounded on-screen keypad (A-Z, 0-9, CLEAR, BACKSPACE,
   ENTER; keyboard typing and controller navigation work too). A wrong code shakes the display and
   says "Invalid code"; the right one unlocks all four with a celebration. There is no shop button.
8. **Shop / locker display** (`ui/shop_screen.gd`, `ui/ui_kit.gd`, locker): any item with `dev: true`
   shows a **CODE ONLY** tag instead of a price (never the raw `-1`) and no Buy button. Owned, it
   equips like any other item. Give owned pack cards a neon green (`DevPack.NEON`) border and title
   so the set stands out as exclusive.
9. **Bots** (`scripts/game/world.gd` around the bot loadout, `Data.OUTFITS.keys().pick_random()` etc.):
   leave `dev: true` items out of bot picks for outfits, hats, skins and charms.
10. **Network:** `Net` already accepts any catalog id for cosmetics (`net.gd` sanitise). Nothing to add.
11. **Docs:** document `DevPack` in `docs/ARCHITECTURE.md` (Models section: the pack, its
    shaders, the instance-uniform flash, and the shader-drawn face) and add a README changelog line.
12. **Verify:** load the game (through `~/.agents/bin/heavy`) with a fresh profile. Check: the pack
    shows CODE ONLY and can't be bought; a wrong code fails on the keypad; the dev code (any case)
    unlocks all four; equip them and check the shop preview, the third-person avatar and the
    first-person view (lines move, pulses run); get a kill against a bot and watch the flash on the
    viewmodel; check that a bot wearing a normal outfit doesn't flash.
