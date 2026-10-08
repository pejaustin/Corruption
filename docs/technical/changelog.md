# Changelog

Dated record of shipped work, verification passes, and design calls — newest first. Forward-looking state lives in `build-phases.md`; war-table build history detail in `docs/systems/war-table.md` (numbered steps + map-representation phase plan).

---

## 2026-06-10 — All six MVP design calls resolved (+ combat-stream worktree surfaced)

Austin answered the roadmap's open calls (third session today); recorded in `mvp-roadmap.md` and the system docs:

1. **One currency** — corruption pays for everything (summons, upgrades, avatar upkeep), replacing `resources` (W3 rework). Boss debuff reads CURRENT total, deliberately — spending on the army trades off boss debuff, and other debuff/buff paths will exist.
2. **Two bosses** for the MVP win, as BossManager is wired (Guardian → Corrupted Seraph).
3. **All-Undeath MVP** — faction asymmetry deferred to next phase. Gotcha recorded: keep distinct per-player faction ids (`FactionRelations.is_hostile` is faction-based) and source roster/kit from the Undeath profile.
4. **Phase D re-speced** — no separate gauge: owning the Avatar drains corruption at an escalating rate, faster while released-to-AI than while directly possessed; bankrupt → neutral, escalation clock resets for the next owner. `avatar-possession.md` rewritten accordingly.
5. **Neutral camps** — station-aware AI: static guards + patrollers, both leash back to station when aggro drops; camps respawn ONLY while the holder's garrison at the protected gem site is below threshold (not enough player minions stationed). New workstream W7; `minion-ai.md` tagged as the likely `MinionBehavior` migration trigger. Open sub-question: respawned neutrals contest vs. re-flip a held site.
6. **Avatar combat already exists** — `combat-stream` branch (worktree `../corruption-combat`): tiers A–G, 8 commits / ~9.3k lines (lock-on, posture/riposte/forced-recovery, `AttackData` combos, status effects, faction passives + ultimates, telegraphs, damage numbers/VFX, per-tier implementation docs + `asset-checklist.md` for animations). **Untested**; branched at `5c7f4dc` — pre-unification, pre-possession — and overlaps 13 files with the uncommitted possession work, so **commit master before merging** (M0 → W4). Also noted: the `overlord-stream` worktree is fully merged into master — cleanup candidate.

## 2026-06-10 — Design calls: ritual stations CUT, astral deferred, MVP roadmap created

Austin, reviewing design after the doc audit (same day, second session):

- **Eldritch ritual stations removed entirely** — never part of the original game plan (an over-eager Tier 4 implementation). Deleted: `ritual_site.gd`, `ritual_data.gd`, `data/rituals/` (both .tres), the station-coupled `eldritch_ritual` avatar ability (effect script + scene + .tres; dropped from `eldritch.tres` — the Eldritch kit is `mind_blast`-only until a replacement), `GameState`'s eldritch-vision plumbing (write-only — nothing ever read `has_eldritch_vision`), `MinionManager.domination_discounts` (also write-only — never applied to a cost), `AvatarAbilities.is_channeling_ritual()` (no callers), and the balance-CSV rituals sheet. Doc references scrubbed from build-phases, CLAUDE.md, project-structure, advisor, held-items, art-asset-plan, balance-csv. Faction *flavor* language ("ritual summoning" as Eldritch identity in one-pager/faction-design) deliberately kept — the cut is the station mechanic, not the theme.
- **BossManager + DivineIntervention placed in `world.tscn`** (Austin, in-editor). BossManager's `initial_boss` was unset (clean push_warning, but phase 1 inert) — wired to `World/Enemies/GuardianBoss` via tscn edit; verify in-editor.
- **AstralProjection deferred from MVP** — boss-room activation isn't ready. MVP plan: HUD notification on Guardian engagement ("scry to watch") + Palantir spectating. The pre-built `scenes/astral_projection.tscn` stays on disk.
- **`docs/technical/mvp-roadmap.md` created** — supersedes build-phases as the start-here forward plan (build-phases keeps tier history + test checklists). Headlines: Cania terrain becomes the real map (foliage, structures, neutral camps around gem sites, Capital v1); each player starts holding one home gem site + starting resources; **ambient corruption directly feeds minion spawning** (exact model = open design call); a Terrain3D-compatible world-editing toolset (macro mountain/valley/river brushes, PoI stamps + editor navigation, war-table map generated from real geography); avatar-combat feel + art de-placeholdering as the polish tracks. Also fixed while scrubbing: `project-structure.md` claimed `tower_scene.tscn` was the main game scene (it's `scenes/world/world.tscn`).

## 2026-06-10 — Doc reconciliation pass (no code changes)

Full docs-vs-code audit after the 2026-06-05/09 reworks. The new systems' own pages were current, but four docs still carried the OLD avatar succession model; all fixed to the possession model (killer's owner takes ownership, neutral kill → unowned; no round-robin, no corruption fallback):

- `one-pager.md` — core-loop diagram (AVATAR TRANSFER box → ownership rules), key-mechanics rows (added Avatar possession; corruption/gems rows updated to ceiling+regen), system-page index (added war-table + avatar-possession rows, refreshed all build statuses).
- `corruption-and-gems.md` — "drives Avatar succession" → feeds the planned Phase D upkeep gauge; the capture diagram still said sites deplete (they don't — ceiling+regen); build status now notes the 3 placed sites.
- `boss-mechanics.md` — attempt-failure succession rewritten; BossManager was claimed to live "in tower_scene.tscn" — it is NOT yet placed anywhere (see Editor TODO).
- `avatar-combat.md` §15 — death/respawn transfer rules.
- `test-plan-corruption-avatar.md` — top half still described the deleted `AVATAR_AS_MINION` flag and its menu toggle; added the Phase C file list; commit-scope warning refreshed (terrain churn landed in `8bec331`).
- `build-phases.md` — resume banner now covers Phases A–C + the 06-09 smoke pass; EnemyManager references corrected.

Also corrected in CLAUDE.md/build-phases: **EnemyManager no longer exists** — neutral enemies are NEUTRAL-faction minions via `MinionManager.spawn_neutral_minion` (holy_knight etc. live under `scenes/actors/minion/types/`). `GameState.get_highest_corruption_peer()` is now orphaned (zero callers since the succession removal); kept as a harmless query — candidate for the balance dashboard, delete if it bothers anyone.

Known doc gap, flagged not filled: the Azgaar→Terrain3D map pipeline (`scripts/build/build_azgaar_terrain.gd`, `paint_terrain_textures.gd`, the importer/painter scenes, `cania_walk_test.tscn`) has no docs page — the build scripts' inline headers are the only documentation.

## 2026-06-09 — Avatar-as-minion is now THE avatar model (flag + legacy path removed)

Austin's call after first hands-on testing: the possession loop functions, so it stops being an experiment. The Avatar is a minion that can be optionally controlled directly by the player with power over it — no flag.

- Removed: `GameState.AVATAR_AS_MINION`, the pause-menu toggle + its RPC (`DebugManager.toggle_avatar_as_minion` / `_set_avatar_as_minion`), the legacy hot-seat path (`claim_avatar`, `release_avatar`, `_get_next_peer` round-robin), the corruption-fallback succession in `_on_death_transfer`, and every flag conditional (claim prompts, MultiplayerManager mode swap, AvatarAI.is_driving, KnowledgeManager tracking, courier delivery).
- `AvatarActor.activate()/deactivate()` survive as harness/bootstrap utilities (capture-channel + cania walk tests drive the avatar without the GameState claim flow).
- F3 always shows `Avatar Owner | Controller` now.

Also fixed, same session:
- **Stuck "Your Avatar awaits" prompt.** `avatar_claim.gd`'s avatar_changed/avatar_owner_changed lambdas called `_update_ui_prompt()` directly, which pushes onto the shared InteractionUI even when the station is unfocused — so Q'ing out across the map stamped the station's prompt on screen with nothing to ever clear it (clear only runs on set_focused(false)). Now they call `_refresh_prompt()` (focus-gated, the pattern InteractionFocus expects).
- **Courier dispatch diagnostics.** Reported: ordering the avatar produced no courier; the dispatch chain reads correct by inspection, so the host now prints `[KnowledgeManager] Courier N dispatched for peer P (L legs)` on success and warns loudly when `spawn_named_minion_for_peer` fails. Next repro will say exactly which stage dropped the order (draft warnings already existed: no-courier-spawn / no-belief).

## 2026-06-09 — Avatar possession Phase C: war-table pawn + command routing (impl, untested)

Reported during first manual testing: the avatar had no presence on the war table. That's Phase C, now built:

- `KnowledgeManager.AVATAR_ID` (-100, reserved — minion ids are positive). `_ingest_sightings` publishes the owned, alive, rework-flagged avatar into WorldModels: owner always sees it (broadcasting units self-report), rivals under normal broadcast-range rules; untracked → forgotten everywhere (parity with minion death), ownership flip → loser's entry just goes stale. `_observable_by` refactored to take a position instead of a MinionActor.
- `WarTableMap._cluster_minions` never merges the avatar into a stack; its piece renders 1.6× with an "AVATAR" badge. `WarTablePiece` prompts "[E] select Avatar". Selection, pending-lock, draft legs all reuse the generic id machinery untouched.
- Orders: instant path → new `KnowledgeManager.request_avatar_move` RPC (host validates sender owns the avatar) → `AvatarAI.command_move`. Courier path → `courier_arrival_state` special-cases the AVATAR_ID leg: visual-range + live-ownership checks, then delivers to `AvatarAI` directly (host-side already). Ownership flipped between draft and delivery = failed delivery, same as a dominated minion.

Also fixed (same session): **debug spawn/order buttons dropped things under the terrain.** `spawn_enemy_at_camera` / `spawn_minion_at_camera` / `order_avatar_to_camera` flattened their target to `y = 0`, which worked on the flat greybox but buries the point under the heightmapped Terrain3D — "Spawn Enemy at Camera" looked like it did nothing. New `DebugManager._aim_world_point()` raycasts the crosshair against world geometry (excluding the aiming actor's own body), navmesh-snap fallback for sky aims; spawns offset +0.5 up so bodies settle.

## 2026-06-09 — Avatar AI bug pass (pre-test audit, by inspection)

Two `avatar_ai.gd` fixes ahead of the Phase A/B test run, both in the "spinning / never-arrives" class the test plan flags:

- **Horizontal distances.** Aggro/leash/attack-range/waypoint-arrival used full 3D `distance_to`, but every minion system measures horizontally (`MinionState.distance_to` zeroes Y) and waypoints arrive with y = 0 (debug order, later the war table). On heightmapped terrain the avatar could never close within `ARRIVE_RADIUS` of a y=0 waypoint (push-forward forever), and slopes skewed melee-range checks. New `_flat_distance()` helper used everywhere.
- **One-tick-stale steering basis.** `AvatarCamera` precedes `AvatarInput` in the tree, so its `before_tick_loop` gather snapshots `camera_basis` *before* `AvatarAI._face()` rotates the mount — the AI's forward-push paired with last tick's heading on every peer (orbiting around targets/corners). `_face()` now writes `camera_basis` directly after rotating the mount so input and heading land in the same tick.

Rest of the audit came back clean: Phase A RPC ordering (owner → controller, reliable), minion→avatar damage already dual-writes on the host (direct + RPC only when `controlling_peer_id > 0`, so the host-owned released avatar takes damage and records `last_damage_source_peer` correctly), death-transfer branches, prompts, and debug wiring all check out by inspection. Still untested in-engine — test plan unchanged.

## 2026-06-05 — Avatar possession Phase B: host-driven AI brain (impl, untested)

`AvatarAI` + `NavAgent` (NavigationAgent3D) added to `avatar_actor.tscn`. `AvatarInput._gather` delegates to `ai_driver.drive()` when the avatar is owned-but-uncontrolled (host = input authority, so AI input rides the existing rollback sync — no new state properties). Steering trick: the AI rotates the camera mount at the nav path and "holds W" (`input_dir = (0,-1)`); `camera_basis` is already a synced input property, so movement and model facing replay identically everywhere. Aggro 10m / leash 15m / melee 2m, sticky targets via `FactionRelations.is_hostile`; waypoints via `AvatarAI.command_move(pos)` (cleared on possess + ownership change — new masters and live drivers void standing orders). Debug: "Order Avatar to Camera" pause-menu button (host) exercises the same entry point Phase C's war-table routing will use.

## 2026-06-05 — Avatar possession Phase A: ownership/control split (impl, untested)

Behind `GameState.AVATAR_AS_MINION` (static, default false; host debug-toggle RPCs it to all peers — it gates host validation AND per-peer prompt/mode-swap logic, so unlike the war-table flags it can't diverge between peers).

- `GameState`: `avatar_owner_peer_id` + `_set_avatar_owner` RPC + `avatar_owner_changed`. Claim = own+possess (unowned) / re-possess (own, uncontrolled). Q = release control, keep ownership.
- `AvatarActor.possess()/release_control()` are control-scoped (no heal on re-possess); `_on_avatar_owner_changed` is ownership-scoped (faction, fresh HP, dormant neutral husk when unowned). Death under flag: killer's owner gains ownership (no auto-possess, own-minion kills don't transfer), neutral kill → unowned. Round-robin/corruption-fallback bypassed.
- `MultiplayerManager`: released-but-owned avatar stays in the field (`release_control`), only unowned goes dormant.
- `avatar_claim.gd` prompts: claim / possess / "Avatar sworn to <faction>". F3: Owner | Controller line.
- Testing checklist in build-phases (Phase A section). Legacy path untouched with flag off.

## 2026-06-05 — Design call: Avatar possession rework (planned)

The always-controlled Avatar model is out. Decided with Austin: ownership/control split, neutral start with first-claim ownership, Q releases control but keeps ownership (round-robin deleted), full minion AI + war-table commandability when released, and a corruption-fed upkeep gauge whose depletion (or combat defeat) is the ONLY way ownership moves. Design + 4-phase implementation plan: `docs/systems/avatar-possession.md`. Will ship behind `AVATAR_AS_MINION` (default false).

## 2026-06-05 — Gem-site capture rework: contest gate + capacity

Follow-up to the corruption unification, after first playtest feedback.

- **Capture gating inverted.** Old: NEUTRAL → CLEARED required *friendly* minion presence before the Avatar could channel (felt wrong — you couldn't capture without minions nearby). New: the Avatar captures any site freely UNLESS **hostile** minions (another faction or NEUTRAL) are within `contest_radius` (renamed from `minion_clear_radius`, default 8m). Contest is re-checked host-side mid-channel (breaks the channel, reason `&"contested"`) and at completion. `SiteState.CLEARED` and `_set_cleared` removed; new public `CaptureChannel.interrupt(reason)` for host-side gameplay interrupts.
- **Ceiling + regen model** (corrected same-day from a first-cut "finite well that depletes" design — Austin: sites are not a resource to drain). A held site adds `max_corruption_contribution` (default 7) to its holder's **max** corruption and regens them toward that ceiling at `corruption_per_second`; `GameState.get_max_corruption(peer)` sums held-site contributions. Sites never deplete; future corruption-draining abilities refill from held sites. F3 shows `current / max` per peer. Tuning flag: 3×7 = 21 global ceiling → boss debuff tops out at 35%, not the 60% cap.
- Harness `capture_channel_test.tscn` updated: no auto-clear ([2] now spawns a hostile AT the site to test the contest gate); HUD shows site yield/capacity and your corruption.

## 2026-06-05 — Corruption unification (influence + territory → one stat)

The per-player "influence" score and the grid-based territory/corruption system were two parallel resources for one design concept — confusing and unintentional. Merged into a single stat: **Corruption**, tied to gem-site control ONLY.

### Changed

- `GameState`: `influence` → `corruption` (dict, signal `corruption_changed`, `get_/add_corruption`, `get_highest_corruption_peer`); new `get_total_corruption()` (sum over peers).
- `GemSite`: `influence_per_second` → `corruption_per_second` (0.5/s trickle while CAPTURED, still the only earn path); sites now join group `gem_sites`.
- `GuardianBoss` debuff reads `GameState.get_total_corruption()` (was TerritoryManager); same `total/60` scaling, cap 0.6 — retune once sites are placed (one site ≈ 2 min to max debuff).
- `DivineIntervention` rewritten: arms on first capture; **zero held sites** for 60s (2s checks, 2× recovery while held) → all lose. Was: total grid-corruption below threshold.
- Avatar succession fallback: highest corruption (mechanically unchanged, renamed).
- Debug: pause-menu button is now "+10 Corruption"; "Boost Corruption near origin" removed. F3: one Corruption section (per-peer + total) + Gem Sites held count; Territory section removed.

### Removed

- `scripts/territory_manager.gd` + its `world.tscn` node — the whole minion-presence grid (cells, spread, decay, faction tags). Corruption no longer accrues from minions standing on land.
- **Corruption Surge ritual** (orphaned by the grid removal): `data/rituals/corruption_surge.tres`, `RitualData.Effect.CORRUPTION_SURGE` (enum now DOMINATION_MASTERY=0, ELDRITCH_VISION=1; `eldritch_vision.tres` re-pointed 2→1).
- The never-implemented "kills award influence" test item — kills intentionally award nothing; sites are the only source.

### Design calls

- **Corruption is competitive AND cooperative**: per-player it decides Avatar succession; summed it debuffs the boss and holds off divine intervention.
- **Gem capture is still permanent** — so corruption is monotonic and divine intervention only threatens pre-first-capture. Site loss/recapture is the open follow-up that would keep both live all match (see `docs/systems/corruption-and-gems.md` open questions).
- Docs: `docs/systems/territory-control.md` replaced by `docs/systems/corruption-and-gems.md`.

## 2026-06-05 — War-table phase 3/4 test pass + multiplayer client fixes

Full verification pass over the phase 3/4 refactor: every harness system (`war_table_test.tscn`) and every main-game system in a 2-peer session. Everything below is **verified working** unless marked otherwise.

### Verified — War Table command flow (harness + 2-peer main game)

- Single-shot-E flow end to end: piece E selects (multi-member stacks open the ghost popup; ghost E selects single members), MapTarget E records a draft at the crosshair point, Paper E promotes drafts → readied, Reset E wipes drafts + selection (readied/dispatched untouched). No camera takeover, no rig pin.
- Stage visuals: red order arrow per leg (draft) → amber in place (readied) → black + light-blue route arrow (dispatched). Same arrow node throughout; both arrows evaporate together on courier despawn or mid-flight death.
- Couriers: batched per `MinionType.max_orders` (N sub-orders ride one courier, multi-leg with TSP-greedy ordering), spawn at the tower's ground-level `CourierSpawn`, per-leg visual-range + loiter delivery check (`courier_visual_range` / `courier_wait_seconds`), walk home, despawn on zone overlap. Failed deliveries report home into `WorldModel.failure_messages`.
- Ghost popup: latch open/close on E, per-ghost selection, 1.5s grace-timer auto-close that survives glancing at the MapTarget, clean handling of member death mid-popup, pending members filtered from re-selection.
- Advisor: idles ≤3.5m / follows / settles at 2.0m, never fights, Hurtbox live (`Shift+K`). Handoff prompt: "confer" (0 readied) / "hand orders (N)" / "Another overlord's Advisor" (non-owner, E no-op).
- Reality overlay (M): yellow spheres track both courier kinds' actual positions; belief layer untouched when off.
- Suppression: no support-staff minion (`courier` / `info_courier` / `advisor` trait) ever renders as a table pawn, own or rival (`KnowledgeManager.UNTRACKED_TRAITS` gate).
- Broadcast-range gating (`INFINITE_BROADCAST_RANGE = false` default): only enemies within 30m of a friendly minion enter the WorldModel; sightings persist at last-known position; stale clusters (>3s, `WarTableMap.STALE_THRESHOLD_SECONDS`) show a red "?" badge that clears on refresh.
- Info-courier (`I`): travel → loiter-observe (12m, 4s) → return → flush; sightings appear on the table even with broadcast gating on. (Premature-retreat-on-damage deferred with the `can_retreat` work.)
- Belief privacy: each table renders only for its owning peer on their own client; rival tables are inert props.
- **Client-peer parity**: the full draft → ready → dispatch → deliver loop works for a non-host overlord (see Fixed below).

### Verified — other systems

- Summoning Circle slot flow: per-roster `SummoningSlot` prompts, cost/cap gating, live faction-cycle rebind, avatar-mode gate.
- Upgrade Altar slot flow: per-upgrade `UpgradeSlot` prompts, host purchase, **client purchase via `_request_upgrade.rpc_id(1)` round trip**, insufficient-funds rejection, `[MAX]`, per-peer resource deduction, cross-tower gating. (Effect multipliers not yet spot-checked — still open in build-phases.)
- Advisor faction binding: own minions no longer read their advisor as NEUTRAL-hostile.
- Camera-rotation leak fix: a peer's overlord body no longer rotates for remote viewers while that peer controls the Avatar / scries.
- Focus fix: tower rig fires no phantom prompts while its peer is Avatar.
- Pause-menu debug toggles (courier visual range / instant commands / broadcast range).

### Fixed — multiplayer client command loop (three stacked bugs)

1. **Client slot resolution** — `MultiplayerManager._player_slot_order` is host-only, so `get_player_slot()` returned -1 for everything on clients, nulling courier-spawn lookups and silently dropping drafts. Clients now learn peer→slot from `_bind_rally_rpc` into `MinionManager._peer_slots` (`_slot_for_peer` consulted by all per-peer lookups).
2. **Host binding heal** — the host's initial bind loop can race slot assignment, and `_request_rally_bindings` only replied to the requester, leaving host-side tower/advisor owner bindings permanently unset. Requests now trigger a full **broadcast** rebind (idempotent), healing host and all clients.
3. **Owner-authoritative dispatch** — `pending_commands` live only in the owner's local WorldModel (models are never replicated), but dispatch ran host-side reading the host's empty copy. Now: Advisor E → `KnowledgeManager.request_dispatch` gathers local readied entries (in-flight latch against double-E) → `_request_dispatch_rpc` to host (owner = sender) → host `_dispatch_entries` batches + spawns → per-entry `_dispatch_confirmed_rpc` back to the owner (confirm with courier_id + route, or reject −1 leaving the entry readied). Delivery-failure reports take the same hop (`_delivery_failures_rpc`).

Plus: pre-placed tower Advisors are now **adopted into `MinionManager._minions_node`** at scene setup — previously each peer had a frozen local copy and only the host saw the advisor follow (no `_sync_all_minions` coverage).

### Design calls

- **Couriers and Advisors never render as table pawns**, own or rival (`UNTRACKED_TRAITS`). Spotting rival runners becomes future interception gameplay (step 14 falsification), not a free broadcast sighting. Reality overlay still shows couriers (`COURIER_TRAITS`).
- **Belief is private to the owner's table on their own client** — rival tables render nothing (was: any player could glance at any table).
- **`INFINITE_BROADCAST_RANGE` and `INSTANT_COMMANDS` both default `false`** — the information-warfare model and courier loop are canonical play; god-view/instant are debug toggles.

### Harness rework — real-scale field

`war_table_test.tscn` playspace expanded 30×30 → **300×300 (production `map_world_size`)**: real broadcast ranges, courier travel times, and visual ranges. Overlord + table + Advisor on a 40m observation platform at the east edge (own nav island); couriers stage at a ground-level `CourierSpawn` below. New hotkeys: `H` time-scale cycle (1/2/4/8×), `K` kill-nearest skips the Advisor, `Shift+K` includes it. PlayspaceBorder removed (`WarTableRange` is the single region marker). HUD/doc text updated to the single-shot-E flow.

### Earlier history

War-table map-representation phases: phase 1 — piece colliders, no camera takeover (2026-04-30); phase 2 — auto-merging stacks (2026-05-02); phases 3/4 — in-world inspect popup + multi-leg batched couriers (2026-05-06, refined through 2026-06-05). Detail in `docs/systems/war-table.md`. Tier 0–2 build history: see git log.
