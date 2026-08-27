# Scavock on Luanti

A vertical slice of **SCAVOCK** (see `../scavock/SCAVOCK_Master_Design_Doc_v8.md`)
built as a **Luanti game** — a total conversion running on the Luanti engine
(formerly Minetest). No minetest_game content; every node, item, and rule is
Scavock's.

This is the "fork a Minecraft-clone" experiment. On Luanti you don't fork the
engine to make a game — you write a *game package* (this repo) and the engine
runs it. Forking the engine itself is only needed later, for branding or
engine-level features.

## Run it

1. Install Luanti: `brew install --cask luanti` (already done on this machine).
2. This repo is symlinked into `~/Library/Application Support/minetest/games/scavock`,
   so it appears as **Scavock** in Luanti's game list.
3. Open Luanti → select the Scavock game → create a world (mapgen v7, any seed —
   seeds are arbitrary strings, matching D16) → play.

Controls that matter: **double-tap W or hold Shift** to sprint (unlimited —
no stamina, §7), **C/Ctrl** to crouch, **I** for the grid backpack,
right-click an **Evac Beacon** to start a 10-second extraction channel,
`/vault` and `/stash` (or the buttons on the inventory screen) for storage.

## The loop as built

Spawn with nothing (§10) → scavenge **abandoned outposts** on the plains for
crates → chop/mine your way up the **material ladder**
(Scrap → Iron → Steel → Titanium → Graphene, §6/§11) at the **workbench** and
**furnace** → carry everything you've gathered to an **Evac Beacon** and channel
10 seconds to bank it into your **Extraction Stash** → die first and *everything
drops where you fell* (§12), while your small **Vault** survives (§5).

## Design doc mapping

| Doc decision | Status here |
|---|---|
| Fully diggable voxel world (§4) | ✅ engine-native |
| Structures are voxel data, stamped at worldgen (§4) | ✅ outposts + evac stations are schematics, fully breachable |
| Tool-gated progression, weak bare-hands fallback (§6) | ✅ hand digs dirt slowly, chops wood painfully, can't touch stone |
| No firearms; bows with travel time, recoverable arrows (§6) | ✅ bow + arrow entity; missed arrows drop as items, body hits recover 50% |
| Material ladder ×  form ladder (§6) | ✅ 5 materials × (pick, axe, dagger, sword, war axe, double axe, spear) |
| Weapon roster as roles, not ranks (§7) | ✅ per-form speed/damage/reach; TTK tuned on *time* (~5s window each) |
| Long TTK, gradual gear slope (§7) | ✅ +0..+2 damage across five tiers; no one-shots |
| Blocking windows per weapon (§7) | ✅ right-click opens the window (dagger 0.55s … war axe 0.22s); sprint halves it; 75% absorb |
| Stagger: chance, weight-scaled, ICD (§7) | ✅ 8% dagger … 32% war axe (max 40%); 2s internal cooldown; brief hard slow |
| Two-stage death (§12) | ✅ lethal damage downs (1 HP, crawl 0.12x, no jump/interact/attack); one more hit finishes → full drop; downed can't be looted (nothing drops until finished) |
| Revives (§12 table) | ✅ right-click a downed player: bare 10%/6s, med kit 20%/4s, stabiliser 30%/2s; kits craftable + in crate loot |
| STEP_HEIGHT = 1.0 (§7) | ✅ `stepheight = 1.1` |
| Unlimited sprint, no stamina meter (§7) | ✅ double-tap W or Shift, 1.65× (D6, engine fork) |
| Weight governs speed, floor at 0.6× (§7) | ✅ occupied grid cells → speed multiplier |
| Death drops full inventory (§12) | ✅ |
| Vault survives everything, deliberately small (§5) | ✅ 8 slots, persisted in player meta |
| Evac points across large biomes, cooldown model (D1, §4) | ✅ beacons w/ 120s cooldown; block-damage/repair states not yet |
| Biome roster (§4) | ✅ grasslands, plains, forest ×3, snowy ×2, desert, savanna, rainforest, mountains, beach, ocean |
| Graphene from coal (§11) | ✅ placeholder recipe (dedicated workbench not yet specified in doc either) |
| Fuel as the economy's sink (§6) | ✅ furnace burns coal/wood; power tools not yet |

### Known adaptations (engine reality vs. doc)

- ~~Slot inventory, not Tarkov grid~~ **Implemented (scavock_grid):** the
  backpack is a true 8x6 spatial grid — items occupy multi-cell footprints,
  rotate (R while held), and the vault (4x2) is grid-restricted with a
  transfer view. Interaction is click-to-move (pick up / place / rotate);
  engine-native drag-and-drop is the remaining polish. The top row doubles
  as the hotbar, so wieldables must anchor there. Engine-driven moves
  (shift-click from crates, craft output) are policed into first-fit
  placements by an allow-callback.
- ~~Sprint input is Aux1~~ **Resolved by the engine fork:** D6 is implemented
  as designed — double-tap forward OR hold Shift, both feeding the aux1 bit;
  crouch/sneak moved to C/Ctrl. (`doubletap_forward_sprint` engine setting.)
- **Mountains are altitude-approximated**, not an independent noise field (D17
  needs a custom mapgen pass).
- **Weight = occupied grid cells**, since items have no per-item mass stat yet.
- **Logging out while downed counts as knocked out** (inventory drops) — an
  anti-exploit rule the doc doesn't specify; without it a relog stands you
  back up at 1 HP.

### Deferred (big rocks, in doc order)


reinforcement crafting + damage pool (§11), noise & stealth (§8), creatures
(§24), Icelands/Cavock/Muvock and the compass system (§4b/4c), proximity voice,
wipe cycles as a server feature, evac block-structure damage/repair (D1).

## Dev notes

- `tools/gen_textures.py` — regenerates all 84 placeholder textures
  (pure-stdlib PNG writer, deterministic). Replace with real art at will.
- Smoke tests: the build was verified with an in-engine test mod (recipes,
  loot fill, worldgen stamping, biome census) run against a headless server:
  `/Applications/Luanti.app/Contents/MacOS/luanti --server --gameid scavock --world <dir>`.
- Mods: `scavock_core` (nodes/materials/workbench/furnace), `scavock_player`
  (movement/death/UI), `scavock_tools`, `scavock_weapons`, `scavock_biomes`,
  `scavock_loot` (outposts/crates), `scavock_evac` (beacons/vault/stash).
