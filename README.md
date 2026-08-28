# Scavock Lua Edition

**Survival Sandbox Extraction.** The full 1.0 feature set of the SCAVOCK
Master Design Doc (v8), implemented as a total-conversion game on the
[Scavock engine](https://github.com/gremstard/scavock-engine) (a rebranded
Luanti fork). Every node, item, creature, and rule is Scavock's.

**Status: feature-complete against the design doc's 1.0 scope (as adapted
below). What remains is bug-testing, tuning, and fixing.**

## Run it

Download from [Releases](https://github.com/gremstard/scavock-lua/releases)
(macOS .app / Windows .exe, game bundled), or clone next to the engine repo
and symlink into its `games/`.

Controls: double-tap **W** or hold **Shift** to sprint · **C/Ctrl** crouch ·
**I** gear + grid backpack · right-click weapons to open the block window ·
right-click a downed player to revive · `/spawns`, `/stash` commands.

## The loop

Spawn with shorts (§10) → forage berries, scavenge outposts, fight or slip
past the roster → climb Leather→Graphene at workbench and furnace → build,
light, and power a base that is never safe → reach an evac console, watch
the beacon run red-green-blue, drop through the trapdoors — and hope
whoever pulls the lever waits for you. Die anywhere in that and everything
drops where you fell; the vault survives.

## Design doc → build (1.0 systems)

| System | Doc | Status |
|---|---|---|
| Diggable persistent voxel world, structures as voxels | §4 | ✅ |
| Biome roster + mutation spectrum (green→chartreuse→orange) | §4/§25 | ✅ seed-noise mutation zones, creeping mutated grass/flora, per-item 50/50 loot roll |
| Underground: ancient ruins / mutated caves / Cavock | §4b | ✅ stamped into natural caves; Cavock holds exactly one compass |
| Compasses: bind by touch, continuity, Cavock preset | §4c | ✅ full continuity table; trades can carry trackers |
| Icelands + futuristic city + The Source + Yetis | §4b/§24 | ✅ seed-derived location ~4–6 km out, compass-only, lethal cold, no food |
| Wipes/vault | §5/§18 | ✅ vault survives death (wipe = new world; cross-world vault is a server feature, noted) |
| Tool gating, material ladder, no firearms, recoverable arrows | §6 | ✅ |
| Weapon roster, blocking windows, stagger, long TTK | §7 | ✅ |
| Noise & stealth, group multiplication, creatures hear | §8 | ✅ |
| Grid inventory (spatial, rotatable) + hotbar | §9 | ✅ 8×N grid, footprints, rotation; top row = hotbar |
| Clothing equip layers, spawn-with-shorts, backpack sizing | §10 | ✅ 8 slots + reinforcement slot; cosmetics N/A (no model layers) |
| Reinforcement: pool split, break moment, repair, 4 perks | §11 | ✅ 7 tiers, element→perk crafting, Safe Slot survives death |
| Two-stage death, revives, bleedout, self-revive, corpses, beds, safe zones, spawn invuln | §12 | ✅ complete |
| Hunger/thirst (mild), salt ocean, bleeding + capped spiral, broken legs | §13 | ✅ |
| Bases never safe, lighting mob-proofing, containers, locks, 3-outcome forcing | §14 | ✅ |
| Wires & power: torch floor, engine/battery/solar, parts list | §15 | ✅ loud engines (open #1 resolved to the tradeoff) |
| TNT, grenades, trigger bombs (linked pair), disarm+tamper, chains | §16 | ✅ range-limited detonation (open #13 → limited) |
| Bow upgrades + poison/fire/explosive arrows, consumed on impact | §17 | ✅ no enchanting anywhere |
| Credits + merchants | §19 | ✅ trading posts in safe zones |
| Evac as required-block structure: lever→red→green→blue→trapdoors→betrayal lever; binary broken +X | §21 | ✅ the strongest story mechanic, preserved exactly |
| Day/night rhythm | §22 | ✅ night ≈2× outdoor spawns + dusk spike; sunlight-damage unbuilt per open item 22 (no roster owner) |
| Creature roster: 10 animals, 7 megafauna, 2 Man Eaters, Yeti; commitment=vulnerability; pets; livestock; foraging | §24 | ✅ box-rig cubes; Titanoboa's three stages intact; swallowed loot destroyed |
| Water traversal, boats, fishing (no underwater zone) | §24.10 | ✅ |
| Vehicles: fuel %, HP curve, 0% = voxel-destroying explosion | §27 | ✅ car/boat/plane (planes fly by look; "jets" = same system, faster — not separately built) |

### Adaptations (engine reality vs. doc — all flagged in code comments)

- Sprint = double-tap W / Shift via the engine fork (D6). Crouch on C/Ctrl;
  Caps-Lock crouch (D9) and the crouch auto-step/ledge rules are engine work
  not yet done.
- Grid inventory is click-to-move; drag-and-drop needs an engine formspec
  element (the fork's next big engine feature).
- Weak points are temporal (hits during commitment) rather than positional
  hitboxes — cube entities have one hitbox. Glyptodon's facing check is the
  positional exception.
- Mountains/Icelands placement approximate D17's independent-noise ideal.
- Logging out while downed counts as knocked out (anti-exploit, not in doc).
- Open questions answered with smallest-reversible choices are marked
  "(open #N)" in code comments; genuinely open ones remain unbuilt.

### Out of scope for the Lua edition (platform/service work, not game rules)

Proximity voice (LiveKit), accounts/unified official vault/playtime
gate/anti-cheat/replay (§18/§28 server infrastructure — Luanti provides
plain multiplayer + auth), cosmetics + Tokens/packs/quests/seasons/streamer
rewards (§19/§20/§31 live-ops on a cosmetic layer that needs the player
model), Muvock + mutated equipment (§26/§17, post-1.0 by the doc itself),
water-as-a-zone + water Man Eater/cryptid (post-1.0), underground tracker
(post-1.0), Blockwire content tools (§29, belongs to the Babylon edition).

## Dev notes

- `tools/gen_textures.py` regenerates all 231 placeholder textures.
- Headless suites (run against a dedicated server): grid logic (16 checks),
  full creature roster spawn/tick (20/20), recipes/loot/worldgen. See git
  history for the exact worldmods.
- Mods: core, player, grid, gear, combat, death, survival, creatures
  (+megafauna/maneaters), noise, world, power, locks, boom, weapons, tools,
  compass, under, vehicles, trade, loot, evac, biomes.
