# Path to MVP — Playable First Iteration

**Created 2026-06-10; design calls resolved same day.** This is the forward plan — start here for what to build next. `build-phases.md` keeps the tier history (0–4) and the standing test checklists that gate M0. Per-system design detail stays in `docs/systems/`; this doc is scope and sequence.

---

## The MVP engine (design statement, Austin 2026-06-10)

> Players start with some corruption and one gem site already under their control. They fight for control of the Avatar, then fight for territory (gem sites) to grow their corruption economy — ambient corruption directly feeds their ability to spawn minions — so they can fight and defeat the Guardian. **First to finish the Capitol boss fight wins (two phases: Guardian → Corrupted Seraph); if divine intervention triggers, everyone loses.**

**MVP focus:** a real playable world and the feel of playing in it — terrain, models, animations, avatar combat — over breadth of systems. Current placeholders (models, upgrade values, minion stats) get their first real pass.

**Cut / deferred at this gate (2026-06-10):**
- **Eldritch ritual stations — CUT** (never in the original plan; all code + data deleted).
- **AstralProjection — DEFERRED.** Boss-room activation isn't ready; MVP ships a HUD notification when the Guardian is engaged ("scry to watch") and players spectate via the Palantir. The pre-built scene stays on disk.
- **Faction asymmetry — DEFERRED to the next phase.** Everyone plays the Undeath kit for MVP (call #3 below).

## Design calls — RESOLVED 2026-06-10

1. **Economy: one currency.** Corruption IS the money — summoning, upgrades, and Avatar upkeep all spend it. The boss debuff reads **current** total corruption, deliberately: spending on your army trades off boss debuff, and this won't be the only boss-debuff / avatar-buff path in the game.
2. **Two bosses** for the MVP win — Guardian → Corrupted Seraph, exactly as BossManager is wired.
3. **Everyone plays Undeath** for MVP; asymmetry returns next phase. *Implementation gotcha:* players must keep **distinct faction ids** — `FactionRelations.is_hostile` is faction-based, so literally sharing UNDEATH would make all players mutually friendly. Source the roster/abilities/passive from the Undeath profile for everyone instead.
4. **Avatar upkeep (Phase D): yes.** Possession costs corruption upkeep; the rate **escalates** the longer ownership is held, and escalates **faster while released-to-AI** than while directly possessed. Can't pay → ownership reverts to neutral; the clock resets for the next owner. Spec: `docs/systems/avatar-possession.md`.
5. **Neutral camps get real AI** — station-aware guards + patrollers with leash-return, respawn gated on the site's garrison falling below threshold → workstream W7.
6. **Avatar combat = land the `combat-stream` worktree** (tiers A–G; untested; needs animations) → workstream W4.

## Design deltas vs. today's build

| # | MVP statement | Today's build | Work |
|---|---|---|---|
| 1 | Start holding 1 gem site each | All sites start NEUTRAL, capture required | Match-start "home site" assignment per player; their corruption ceiling/regen starts live |
| 2 | Corruption feeds minion spawning | Separate `resources` currency (start 20, +2/s) pays for summons; corruption only debuffs the boss | One-currency rework (W3) |
| 3 | Real map (Cania terrain) | world.tscn greybox plane with its own Terrain3D; Cania exists only in the walk-test harness | Workstream W1 |
| 4 | Capitol boss fight = the win | BossManager chains Guardian → Corrupted Seraph | None — resolved: two bosses stay |
| 5 | Divine intervention loses for all | Implemented + placed (zero held sites for 60s, arms on first capture) | With pre-held home sites it effectively arms at match start — decide grace rules |

---

## Workstreams

### W1 — The real map (Cania)
Goal: the match plays on the Cania Terrain3D map.

- [ ] world.tscn terrain → `cania_terrain.tscn` (+ `cania_water`), navmesh rebaked over it
- [ ] 4 tower placements on the periphery
- [ ] Gem sites: one **home site** near each tower (pre-held at start) + contested sites in the midfield
- [ ] **Neutral minion camps** surrounding the contested gem sites (StartingMinionSpec-style markers). M1 ships them on today's static combat AI; W7 upgrades them
- [ ] **The Capital v1**: arena at/near map center, Guardian placed, readable approach routes
- [ ] Foliage + structures pass (seed from `scenes/world/env/` — ~30 kit pieces already imported)
- [ ] War-table regions: `map_world_size` / `map_world_center` per tower tuned to the real map

Can start by hand; W2 exists to make iterating on this fast.

### W2 — World-editing tooling (Terrain3D-compatible)
Goal: large-scale and modular world edits without granular sculpting; the war-table map derives from real geography.

- [ ] **Macro terrain brushes** — mountain / valley stamps and river carving as coarse parameterized operations (not per-vertex sculpting). Likely `@tool` scenes operating on Terrain3D region heightmaps — same pattern as the existing `build_azgaar_terrain.gd`
- [ ] **PoI placement + navigation** — encampments, gem sites, towers, the Capital as modular "stamps" (scene + marker); an editor dock/list that jumps the editor camera to any PoI
- [ ] **War-table map generation** — top-down render of the terrain (height/biome-tinted) → table surface texture that matches the world's geography, with PoI markers
- [ ] Document + fold in the existing Azgaar→Terrain3D importer and texture painter (currently undocumented)

### W3 — Economy & match setup (one currency: CORRUPTION)
- [ ] **Corruption replaces `resources`** as the only currency: summoning, upgrades, and avatar upkeep spend it; held sites bank it toward the ceiling and refill it after spends
- [ ] Boss debuff reads **current** total corruption (resolved — see call #1)
- [ ] **Retune the numbers**: per-site ceiling contribution (7 was a score, not a wallet), regen rate, minion/upgrade costs, starting corruption — via the balance-CSV round-trip
- [ ] `dark_tithe` upgrade (resource rate) reworked into corruption-regen or cut
- [ ] Match-start state: 1 held home site + starting corruption per player
- [ ] Divine-intervention pacing with pre-held sites (grace period / arm rules — delta #5)
- [ ] **All-Undeath MVP** (call #3): distinct per-player faction ids retained; roster/kit/passive sourced from the Undeath profile for everyone
- [ ] **Avatar upkeep** (call #4): escalating corruption drain, faster while AI-driven; bankrupt → neutral. Spec in `avatar-possession.md` Phase D
- [ ] MVP roster trim: the Undeath set + neutrals (the other factions' minions wait for the asymmetry phase)

### W4 — Avatar combat (land the `combat-stream` worktree)
The system already exists: branch `combat-stream` (worktree `../corruption-combat`), 8 commits / ~9.3k lines — **tiers A–G**: feel pass (hitstop/knockback/hit-flash), lock-on targeting, defense (posture bar, riposte, forced recovery), attack depth (light combo / heavy / charge / sprint / jump attacks as `AttackData` .tres), faction passives + ultimates, PvP damage filtering, PvE/boss telegraphs, status effects (bleed/burn/slow/silence/corruption), damage numbers + hit VFX, per-tier implementation docs, and `docs/technical/asset-checklist.md` (the animation shopping list). **Completely untested**, and branched at `5c7f4dc` — before the corruption unification, the war-table completion, and the possession rework.

- [ ] **Commit master's possession + gem work first** (M0) — 13 files overlap with the branch (`game_state.gd`, `avatar_input.gd`, `avatar_actor.*`, `minion_manager.gd`, menus, …)
- [ ] Merge `combat-stream` onto current master; resolve the overlap set (watch `avatar_input.gd`: AI-driver hook vs combat inputs); re-run the possession smoke test after
- [ ] Test pass over tiers A–G (each tier doc carries its own checklist)
- [ ] Animations per `asset-checklist.md`, for the existing or a new avatar model (joint with W5)
- [ ] Guardian fight tuned against the corruption-debuff curve
- Note: tier E's faction passives/ultimates merge in but stay dormant for MVP (all-Undeath)

### W5 — Models & animations
- [ ] Replace placeholder models (avatar, minions, Guardian, tower interior) — pipeline `3d-asset-pipeline.md`, priorities `art-asset-plan.md`
- [ ] Avatar animation set per the combat-stream `asset-checklist.md` (joint with W4)
- [ ] Corruption world-visuals first pass — the title mechanic currently has zero world presence; held sites should read at a glance

### W6 — Systems glue
- [ ] **Boss-fight HUD notification** — host detects Guardian engagement → banner on every peer ("The Guardian is under attack — scry to watch"); Palantir is the spectate path
- [ ] Run the standing test plan (`test-plan-corruption-avatar.md`) — possession A–C, gem capture, 2-peer sync; gates everything minion/avatar-adjacent
- [ ] Verify in-editor: BossManager `initial_boss` wiring + DivineIntervention (placed 2026-06-10)
- [ ] Housekeeping: `overlord-stream` worktree is fully merged into master — remove worktree + branch when convenient

### W7 — Neutral camps & site garrisons
Neutral minions become station-aware; held gem sites need garrisons (call #5).

- [ ] **Station memory** — every camp minion knows its station (camp anchor near a gem site)
- [ ] **Two duty types** — static guards and patrollers (waypoint loops); both leash back to their station when aggro drops
- [ ] **Garrison-gated respawn** — a camp respawns members ONLY while the holder's "corruption allocation" at the protected site is below threshold, i.e. not enough player minions stationed there. First cut: count the owner's minions within a garrison radius of the site
- [ ] Build on the `MinionBehavior` proposal in `minion-ai.md` (StationedGuard + Patrol behaviors) — this workstream is likely the migration trigger
- Open sub-question: respawned neutrals at a HELD site — contest only (block regen?), or actively re-flip the site to NEUTRAL?

---

## Suggested sequence

- **M0 — Stabilize** (≤1 session): run the standing test plan, fix fallout, **commit the possession + gem rework cleanly** (hard prerequisite for the W4 merge).
- **M1 — World first cut**: W1 by hand (static camps OK) + the W6 HUD notification → playable end-to-end on the real map.
- **M2 — Tooling**: W2, then re-iterate the M1 layout with it (incl. the generated war-table map).
- **M3 — Economy & life**: W3 (one currency, upkeep, all-Undeath setup) + W7 camps → the full engine loop is live: start → avatar → territory → corruption → army → Capitol.
- **M4 — Combat & art**: W4 merge/test + W5 in alternation, playtesting between passes.

**MVP exit:** a 2–4 player match on Cania, start to win/lose, no debug menu required, placeholder-free in the categories above.
