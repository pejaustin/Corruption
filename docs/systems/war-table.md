# War Table — Information & Command System

**Build status:** Steps 1–8 in. Phase 3 of the map-representation refactor (in-world inspect popup) is in: pieces and ghosts are now standard `Interactable`s, the modal "press E to use the war table" mode is gone, and every affordance on the table is a single-shot E interaction. The order lifecycle gained a third stage: `draft → readied → dispatched`. Drafts are recorded by the new **MapTarget** interactable; the **Paper** on the table promotes drafts → readied; the **Advisor** still does readied → dispatched. The **Reset** prop wipes drafts + selection. Multi-member stacks open a ghost popup on E (latched, with grace-timer auto-close); each ghost is its own Interactable for per-member selection. Couriers are now batched per `MinionType.max_orders`: N orders for one source cluster ride a single courier; advanced couriers can carry orders across multiple source clusters in a single outing.

`KnowledgeManager` autoload + per-peer `WorldModel`, diorama rendering via `WarTableMap`, and the isolated `war_table_test.tscn` harness are all live. The harness uses real `OverlordActor` + `MinionActor` + `MinionManager` (single-peer via `OfflineMultiplayerPeer`) — full command-loop is testable without booting the lobby. `INFINITE_BROADCAST_RANGE` and `INSTANT_COMMANDS` default to `false` (instant flips back on for direct-command iteration in the test harness) so the courier path is canonical. Steps 9–14 (composition UI / undo, paper held item, Stay-vs-Leave modes, balcony shouting, falsification) remain pending.

`MinionType` data for the three info-warfare roles exists at `data/minions/advisor.tres`, `data/minions/courier.tres`, and `data/minions/scout.tres` (NEUTRAL faction, role-not-faction; per-faction visual flavor is layered on at the actor scene). Actor `.tscn` scenes and behavioral state machines are not yet authored — the `.tres` files are stats-only prerequisites for steps 7 and 11.

---

## Design goal

The game is RTS-shaped — four overlords commanding armies for territory and bosses — but the overlord does **not** have omniscient control. They can only act on what they believe is happening, and their beliefs are updated through fallible in-world channels (couriers, sight range). This is the defining asymmetry against conventional RTS games and the thing every other system has to respect.

The War Table is the diorama where the overlord sees their current belief and issues new intent. It is not a satellite view. It is a map that an advisor keeps updated with whatever scraps of information have reached the tower.

```
┌──────────── TRUTH ────────────┐       ┌────── BELIEF ──────┐
│                               │       │                     │
│  Real minion positions        │       │  Overlord's         │
│  Real enemy positions         │  ───▶ │  WorldModel         │  ───▶  War Table
│  Real territory state         │       │  (lossy, delayed,   │
│                               │       │   possibly false)   │
└───────────────────────────────┘       └─────────────────────┘
         Simulation                          Knowledge                    UI
   (one source of truth)              (per overlord, independent)    (renders belief)
```

The table **never reads the truth directly.** It reads the overlord's `WorldModel`.

---

## WorldModel

Each overlord has a `WorldModel` — a per-peer structure owned by a `KnowledgeManager` autoload. Rough shape:

```
WorldModel:
    believed_friendly_minions:  { minion_id → { pos, last_updated_tick, source } }
    believed_enemy_minions:     { minion_id → { pos, faction, last_updated_tick, source } }
    believed_avatar_pos + timestamp
    believed_gem_states:        { gem_id → { capture_progress, owner, last_updated_tick } }
    pending_commands:           { command_id → {
        stage,         # &"draft" before handoff, &"dispatched" after
        spawn_pos,     # tower spawn, where the courier originates
        source_pos,    # believed location of the selected minions
        target_pos,    # where those minions are ordered to go
        minion_ids,    # the specific minions the courier carries orders for
        courier_id,    # -1 while a draft, real minion id once dispatched
        issued_tick,
    } }
```

Every piece of data is timestamped. The table renders staleness visually — fresh information is opaque, old information fades or shows an "hourglass" icon. This makes information asymmetry legible to the player.

`WorldModel` entries can be **wrong**. They are the overlord's best guess, not ground truth.

---

## Knowledge update paths

### Path 1 — Broadcast range (passive)

Any friendly minion within **broadcast range** of the owning tower pushes its position into its overlord's WorldModel continuously. Enemy minions within sight of those friendlies also leak into the WorldModel (your scouts see enemies, and you see what your scouts see). Broadcast range is a tunable constant — small enough that the battlefield is mostly dark, large enough that activity near home is transparent.

### Path 2 — Courier returns (active)

A minion too far from home can only update the WorldModel by physically returning to the tower. Two ways a minion leaves the field:

- **Forced retreat** (health threshold, aggro loss, etc.) — the minion breaks off and heads home. On arrival, its observation log flushes into the WorldModel.
- **Recall order carried by a courier** — a courier minion dispatched from the tower travels to where the overlord *believes* the army is. If the army has moved, **the courier returns empty-handed** — orders undelivered, no observation update about that army. The overlord just sees "my courier came back with nothing," which is itself a signal something changed.

There is **no magic recall.** A minion in the field stays in the field until it's ordered back (by a courier who found it) or forced back (by combat state).

### Path 3 — Advisor NPC in the tower (diegetic anchor)

An "Advisor" NPC stands near the table. It is the in-world entity that:
- Receives returning couriers and updates the WorldModel on their arrival.
- Dispatches outgoing couriers when the overlord issues a command.
- Can be **killed** — silencing all updates and commands until a replacement arrives. A high-value assassination target.
- Can be **impersonated / compromised** by falsification attacks (later phase).

---

## Commands

Clicking does **not** move minions. The war table is a cluster of single-shot E-interactables — there is no modal "press E to use the table" mode, no camera takeover, no rig pin. The overlord stays in first-person, walks around the table, and aims with the crosshair. Each affordance has its own `Interactable`:

| Interactable | Lives at | E behavior |
|---|---|---|
| **Piece** (`WarTablePiece`) | one per `WorldModel` cluster on the diorama | single-member: toggle that id; multi-member: toggle every available member ("select all") |
| **Ghost** (`WarTableGhost`) | spawned by the inspector above multi-member stacks | toggle that single member id |
| **MapTarget** (`WarTableMapTarget`) | flat Area3D over the diorama | with non-empty selection, project crosshair onto map plane and record a draft via `issue_move_command`; clear selection |
| **Paper** (`WarTablePaper`) | scroll on the table top, beside the diorama | promote every draft → readied (`KnowledgeManager.ready_drafts`) |
| **Reset** (`WarTableReset`) | reset prop on the table top | discard drafts + clear selection (readied / dispatched untouched) |
| **Advisor** (`AdvisorHandoff`) | on the advisor minion (separate from the table) | promote every readied → dispatched (`KnowledgeManager.dispatch_readied`); spawn couriers |

`issue_move_command` snapshots each selected minion's believed position into a `legs: Array[{source_pos, minion_ids}]` (one leg per minion at draft time) and stamps a `pending_commands` entry as `stage = &"draft"` with `spawn_pos` (tower courier-spawn), `source_pos` (centroid, for the dispatched courier's first leg), `target_pos`, and the `minion_ids` payload.

When the overlord interacts with the **Paper**, every draft entry's `stage` flips to `&"readied"` in place — same `command_id`, same arrows, color flips from red to amber. No couriers are dispatched; nothing leaves the tower. The orders are committed in the sense that Reset can no longer cancel them, but they're not yet in the world.

When the overlord interacts with the **Advisor**, `KnowledgeManager.dispatch_readied(peer_id)` runs on the host. For each readied entry it spawns a real Courier minion at the owner's tower spawn marker, with `waypoint = source_pos` and the delivery payload (`delivery_minion_ids`, `delivery_target_pos`, `return_pos`) attached to the courier actor. The entry's `stage` flips in place to `&"dispatched"` and `courier_id` is set.

The Courier travels via the inherited ChaseState. On arrival at `source_pos`, `courier_arrival_state.gd`:
- Iterates `delivery_minion_ids`, sets each living, still-owned target's waypoint to `delivery_target_pos`.
- Sets the courier's own `waypoint = return_pos` and clears the payload.
- Lets ChaseState walk it back to the tower spawn.
- On arrival home, despawns (Leave mode — Stay mode TBD per step 12).

If the courier dies en route, `MinionManager.notify_minion_died` → `KnowledgeManager.notify_minion_removed` drops the entry; the visuals evaporate.

If the believed source has gone stale (minions actually moved), the courier checks **visual range** on arrival: only minions within `MinionType.courier_visual_range` of the courier (default 6m, configurable per type) get the order. Anything that's not in range — including dead/removed/dominated minions — stays "missing." The courier loiters at the source for `MinionType.courier_wait_seconds` (default 4s, also per-type), re-checking every tick so a minion that wanders into range during the wait still gets its order. Whatever's still missing when the timer expires is appended to the courier's `delivery_failures` list and reported via `KnowledgeManager.notify_delivery_failures` when the courier crosses back into the home zone — feeds `WorldModel.failure_messages` so the overlord knows their belief was wrong.

The visual range can be toggled on as a translucent debug sphere via `DebugManager.show_courier_visual_range` (test harness hotkey `V`) — useful for seeing exactly what the courier "sees" at each leg.

---

## Command composition & Advisor handoff (future design)

The current clicks-move-minions flow is a stub. The intended end-to-end loop looks like this:

### 1. Compose orders at the table (planning UI)

The overlord enters the War Table camera and uses a **cursor** to author a batch of movement orders, not single clicks that fire immediately:

- Click a minion or drag-select a **group** of minions to select them.
- Click a destination on the map to assign their target.
- The table paints the planned movement: the current position of the selected unit(s), and a **winding arrow** along the intended path to the destination (approximating how the courier + minions will actually travel, not a straight line).
- Up to **5 pending commands** can be stacked in a single session, each targeting a different minion or group.
- **Undo** pops the most recent command off the stack.
- **Confirm** closes the table camera and emits a held item (see below).

This replaces the current "click = instant move" behavior once the courier system lands. `INSTANT_COMMANDS=true` should continue to bypass composition and move minions directly for playtesting.

### 2. Paper item in the held-items slot

Confirmation does *not* dispatch couriers. Instead the overlord **exits the table holding an item** — a coiled piece of paper inscribed with the plan. Per-faction flavor is on the table (a bone scroll for Undeath, a brand-seared hide for Demonic, a leaf-bound weave for Fey, a stone tablet etched with sigils for Eldritch).

> **Depends on:** the Overlord held-items interface (see `held-items.md`), which is its own system and not confined to the War Table.

### 3. Hand the paper to the Advisor

The overlord walks to the **Advisor minion** in the tower and hands over the paper. The Advisor is the diegetic "AI that executes plans" — it reads the paper and decides how to carry out each plan.

> **Depends on:** the Advisor command-interpretation system (see `advisor.md`), which is also broader than the War Table — the Advisor will eventually accept non-movement commands (build orders, defensive postures, etc.) through the same handoff.

For War Table movement commands specifically, the Advisor's response is to dispatch couriers.

### 4. Couriers (constrained, faction-tuned)

- **Courier cap in the field** is configurable per faction (e.g. Fey get more, Undeath fewer but raise-able). When the cap is hit, new plans wait in the Advisor's queue until a courier returns.
- Each courier carries a subset of the plan — one target group, one order.
- **Delivery mode** is chosen per order at composition time:
  - **Stay** — the courier remains with the minions after delivering, observes execution, and returns with a **status report** (succeeded / failed / partial / minions wiped).
  - **Leave** — the courier hands off the order and heads straight home. No execution check, no status report. Faster return, blind to outcome.
- The overlord's `WorldModel` only updates when a courier **returns**. A Stay courier updates with execution-accurate data; a Leave courier updates with "orders delivered" but nothing about whether they were carried out.

### 5. Visual-range exceptions

Two shortcuts bypass the courier loop for minions close to home:

- **Automatic table updates** — minions within visual range of the tower update the War Table in real time (this is the current `INFINITE_BROADCAST_RANGE` behavior, narrowed to a specific radius).
- **Balcony shouting** — while holding the paper, the overlord can walk to the tower balcony and read the orders aloud. Any minion in visual range of the balcony receives the orders immediately, no courier required. The Advisor still mediates: because the Advisor follows the overlord everywhere in the tower, it's standing beside them on the balcony, "listening in," and updating the War Table when the orders land. The shortcut is that couriers are skipped — not that the Advisor is bypassed. This is the "I can see them from here, I don't need a messenger" case and should feel like a faster, riskier (you're exposed on the balcony) alternative to the desk-side Advisor handoff. See `advisor.md` for the intake model.

---

## Falsification (later phase)

Once the above is in, the door is open for:

- **Eldritch:** dominate an enemy courier, rewrite its payload, release it. The target WorldModel receives lies.
- **Courier interception:** kill a courier silently to prevent an update without alerting the enemy that it was killed.
- **Fake advisor:** a high-risk sabotage where a player plants a doppelganger advisor in an enemy tower, poisoning their WorldModel.

These are design hooks — not in scope for the first build.

---

## Visual design of the table

- Table surface is a **diorama** rendered in world space. Each overlord's belief is *private to their own table on their own client* — the local peer only sees pieces and arrows on their own tower's table; walking past a rival tower shows an inert prop with no rendering. (`KnowledgeManager._models` is per-peer and not replicated, so even if we wanted to display rivals' beliefs we don't have the data; the per-owner gate codifies that fact in the UI.)
- Minion pieces are chess-piece-style miniatures (cylinder), parented to the table, colored by faction.
- Gems, towers, and the Capitol are drawn/labeled icons, placed statically at the start of the match.
- A stylized map texture (hand-drawn feel) covers the table surface to provide regional context independent of world sculpting state.
- Staleness is shown visually — recent data is crisp, old data is faded, very old data is replaced with a "?" token.

### Order lifecycle on the table

A move command goes through **three stages**, all stored in `WorldModel.pending_commands` per `command_id`. Each stage renders **up to two arrows** — an order arrow that always exists, and a courier route arrow that only appears once dispatched:

| Stage | Trigger | Order arrow (source → target) | Courier route arrow (spawn → source) |
|---|---|---|---|
| `draft` | MapTarget E with selection (`KnowledgeManager.issue_move_command`) | **Red** — the planned move from believed minion location to destination. | Not drawn — no courier exists yet. |
| `readied` | Paper E (`KnowledgeManager.ready_drafts`) | Same arrow flips to **amber** in place. | Still not drawn. |
| `dispatched` | Advisor E (`KnowledgeManager.dispatch_readied`) | Same arrow flips to **black** in place. | **Blue** courier-color arrow appears — the runner's path from the tower to the believed source. |

The order arrow does NOT disappear-and-reappear between stages — the same `command_id` entry stays put and only the `stage` field flips, so the visual reads as "color change, same arrow." When the courier despawns (delivered, killed, anything in `KnowledgeManager.notify_minion_removed`), the entry is removed and both arrows evaporate together.

The two-arrow rendering is symbolic: the order arrow is the **command** (where minions are ordered to go), the route arrow is the **logistics** (where the courier currently is, abstractly). Neither tracks the courier's actual real-time position — they're belief-layer drawings on the Advisor's table. To see ground truth, flip `WarTableMap.SHOW_REALITY` for a yellow sphere at every live courier's actual world position.

Your own couriers are *suppressed* from the regular minion-sighting buckets so they don't double-render. **Rival couriers** are not — to a rival you don't see *intent*, just a minion you happen to spot, so a rival's courier shows up the same way any other rival minion does (regular pawn at its sighted position).

> Why intent-only by default? The war table is *the Advisor's drawing*, not a satellite feed. The Advisor knows what was ordered and where; how far the courier has actually got is a question the Advisor can't answer until the courier comes back. The midpoint pawn is the "I sent a runner, they're somewhere on the road" abstraction. The red→black flip is the moment the order leaves the player's hands.

### Held-item flavor (deferred)

The current MVP does NOT yet show the player physically *carrying* the plan-paper between the table and the Advisor — the drafts persist in `WorldModel.pending_commands` invisibly until handoff. The diegetic paper item (rolled scroll in the overlord's hand, faction-flavored, see `held-items.md`) is still TODO. Once it lands, "leaving the table with confirmed orders" will pick up a held item; "handing it to the Advisor" will consume the held item; the lifecycle on the table doesn't change.

### Reality overlay (debug)

`WarTableMap.SHOW_REALITY` (default `false`) is a debug toggle. When `true`, the war table additionally draws a small **yellow sphere marker** at every live courier's actual world position, sourced directly from `MinionManager` (truth, not belief). Rendered on top of the belief layer — both visible simultaneously. Yellow is chosen specifically to stay distinct from red (drafts) and black (dispatched arrows).

Use it to verify dispatch correctness, courier pathing, and intent-vs-reality drift. In the war-table test harness, press **M** to flip the toggle.

---

## Testing

Two separate test paths, because iterating on the diorama shouldn't require booting the whole game, and iterating on gameplay shouldn't be blocked on the diorama.

### Full game with stubbed information

While the War Table is under construction, the rest of the game needs to remain playable. Gate the information/command system behind a flag:

```gdscript
# scripts/knowledge/knowledge_manager.gd — runtime-mutable so test harnesses
# can A/B the two modes without restarting.
static var INFINITE_BROADCAST_RANGE: bool = true
static var INSTANT_COMMANDS: bool = true
```

When these are true:
- Every friendly and enemy minion continuously updates every overlord's WorldModel (effectively a 1:1 mirror of truth).
- Commands apply instantly — clicks move real minions, no couriers.
- The WarTable behaves as a transparent god-view.

This is the configuration for playtesting combat, territory, boss fights, etc. Switch off per-flag once individual subsystems are ready.

### War Table test scene

A dedicated scene `scenes/test/war_table_test.tscn` whose only purpose is rapid iteration on the diorama, piece rendering, click mapping, *and* the full command loop — because everything past Step 5 needs end-to-end testing of belief → click → command → minion movement.

Setup pattern: the controller (`scripts/test/war_table_test_controller.gd`) installs an `OfflineMultiplayerPeer` in `_enter_tree` (so `multiplayer.get_unique_id() == 1` and `is_server() == true` before any child `_ready` fires), starts `NetworkTime` so the netfox tick loop runs, and seeds `GameState.player_factions[1] = UNDEATH`. The scene then runs the real `OverlordActor`, the real `WarTable.tscn`, the real `MinionManager`, and real `MinionActor`s — no fakes anywhere.

Contents:

- One **real `WarTable` instance** (so any edit to `war_table.tscn` propagates), `map_world_size = (30, 30)` overridden on the instance, sitting east of the playspace.
- A 30×30 bounded playspace with `NavigationRegion3D` (user bakes once in editor) and a `StaticBody3D` floor.
- One **real `OverlordActor`** named `"1"` (peer-id authority requirement) — walk around with WASD, approach the table, aim at pieces / map / paper / reset and press E to interact (no modal mode).
- A `World/StartingMinions` node holding **`StartingMinionSpec` markers** — drop Marker3D children, set `type_id`/`faction`/`owner_peer_id` in the inspector, and the controller spawns one real `MinionActor` per spec on `_ready` (call path: `MinionManager._spawn_minion_rpc.rpc(...)` runs locally under the offline peer).
- Hotkeys for fast iteration:
  - `1`/`2`/`3`/`4` — spawn Skeleton (yours) / Imp (Demonic) / Sprite (Fey) / Cultist (Eldritch) at random points
  - `F` — cycle your overlord's faction (tests piece-color rendering and faction-gated table features)
  - `K` — kill nearest minion (tests `notify_minion_died` → `KnowledgeManager.notify_minion_removed` → piece removal)
  - `R` — wipe + respawn the authored starting state
  - `T` / `B` — toggle `INSTANT_COMMANDS` / `INFINITE_BROADCAST_RANGE` at runtime
  - `Esc` — release/recapture mouse  ·  `Shift+Esc` — quit
  - At the table: aim and E — pieces select, MapTarget targets, Paper readies drafts, Reset wipes drafts/selection. Faction-gated right-click / shift-click features (Eldritch dominate, Demonic single-pick) were removed with the modal flow; they'll come back as their own discrete interactables when the systems land.

Because the harness runs the real `MinionManager`, the autoload's ingest loop populates peer 1's `WorldModel` automatically — the controller doesn't write sightings itself. Use this scene to exercise courier animations, staleness fade, and falsification once those land.

---

## Scout & Scry

Scouts (`data/minions/scout.tres`) are the cheap, fast, low-HP eyes of the army. They are a specialized minion type, not an upgrade tier — there is no "promoted" form. Two functions on the same body:

- **Passive WorldModel feed** — like any friendly minion, a Scout in broadcast range pushes sightings into its owner's `WorldModel`. Their job description is "be in the field at the broadcast-range edge," so they tend to be the WorldModel's primary out-there source.
- **Scry target (cross-player)** — Scouts are *publicly scryable*. Any player — owner, ally, or rival — can park a third-person scry camera on a Scout, just as the existing Palantir already does for the shared Paladin (the Avatar; see `scripts/interactibles/palantir.gd`). The Scout becomes a window that other towers can look through. The scout knows it is being watched the same way the Paladin does (the watcher position is broadcast and rendered as a visible ghost cube near the target — see `palantir.gd:_start_scrying`). Multiple watchers on the same Scout produce multiple ghost cubes — no aggregation.

The Paladin (the Avatar) remains a scryable target as today, just opened up so every peer's Palantir can hold a feed on it concurrently rather than only the tower whose Palantir is currently bound to the Avatar slot.

> Terminology: **Paladin** = the in-flavor name for the shared Avatar entity. **Holy Knight** = a separate neutral-faction minion type (`data/minions/holy_knight.tres`) used as gemsite guards / boss texture. They are not the same thing.

### Palantir target selection

Each tower has one Palantir. On interact, it presents a target picker over **all currently active scryable targets** in the match — the Paladin (when one exists) plus every living Scout owned by any peer. The overlord chooses one target, the orb begins streaming that feed (third-person orbit, mouse/joystick to rotate around the target), Q exits as today. Switching targets is the same flow: stop the current scry, re-open the picker, choose another. There is no per-Scout interactable elsewhere — the Palantir is the single entry point and always lists the full live roster.

> Implementation tracking lives in `docs/technical/ui-rework.md` § "Palantir — multi-target scry picker". The current `palantir.gd` is single-target on the Paladin and will be reworked when Scouts ship.

### Why public visibility

This is an intentional asymmetry against the WorldModel. The WorldModel is *private and lossy* (you only see what your own minions report). The Scout-scry network is *public and live* (anyone with a Palantir can look through any Scout in real-time). Consequences:

- An overlord who deploys a Scout is offering free intel to their rivals as well as themselves. Killing your own scouts is a legitimate counter-intel move.
- An ally can spot for you by deploying a Scout near a contested gem; you scry through their Scout from your tower.
- A rival who finds your Scout deep in their territory can scry through it back at *your* army. Protect or kill on sight.

### Bandwidth cap

Each scryable target has a max-concurrent-watchers cap, exposed as an export on the target's actor scene:

```gdscript
@export var max_concurrent_watchers: int = 4
```

Default is **4** for every target type (Scout, Paladin, anything added later). The export lets specific scenes or instances tune it without touching code — e.g. a story boss could be capped at 1, a free-for-all "town square" Scout could be raised to 8.

When a target is at cap, the Palantir picker shows it as **full** and prevents selection. If a watcher disconnects (Q exits, watcher's tower destroyed, target dies), a freed slot opens immediately for the next picker request — no queue.

### Open questions

- **Alliance gating** later: in a future version, scry access could be alliance-gated rather than fully public. First build keeps it fully public to make the asymmetry sharp.

---

## Build order

1. ✅ **`WorldModel` + `KnowledgeManager` stub** — autoload at `scripts/knowledge/`, per-peer dicts, `INFINITE_BROADCAST_RANGE` and `INSTANT_COMMANDS` flags defaulting to `true`. `MinionManager.notify_minion_died` forwards to `KnowledgeManager.notify_minion_removed`.
2. ✅ **War Table reads from WorldModel** — `WarTableMap` spawns a colored cylinder piece per believed minion. Table `_process` calls `map.render_from_model(KnowledgeManager.get_model(peer_id))` each frame.
3. ✅ **Table-space ↔ world-space mapping + click handling** — `WarTableMap` exports `map_world_center`, `map_world_size`, `table_surface_size`. `camera_ray_to_world()` projects table clicks onto the map plane and converts to battlefield coords. `WarTableRange` (tool script) draws a semi-transparent BoxMesh covering the effective region so designers can see it in-editor and in-game.
4. ✅ **Test scene** — `scenes/test/war_table_test.tscn` runs the real `WarTable` + `OverlordActor` + `MinionManager` via `OfflineMultiplayerPeer`. Starter minions are authored as `StartingMinionSpec` Marker3D children. Full command loop is exercised end-to-end.
5. ✅ **Broadcast-range truthing** — flip `INFINITE_BROADCAST_RANGE` off, tune range, validate staleness visuals. **Implemented**: `KnowledgeManager._observable_by` already gates sightings to within `BROADCAST_RANGE` (30m, tunable const) of any of the peer's friendly minions when the flag is `false`. Test harness `B` hotkey toggles the flag at runtime. Staleness now also surfaces visually: when a cluster's freshest belief is older than `WarTableMap.STALE_THRESHOLD_SECONDS` (default 3s), a red "?" Label3D appears above the piece signaling "your information about this group is stale." Cluster freshness = max of members' `last_updated_tick`.
6. ✅ **Forced retreat + return-to-tower update** — a retreating minion's arrival flushes its sightings log. **First-pass MVP shipped.** Opt-in per `MinionType` via `can_retreat` (default `false`) and `retreat_hp_threshold` (default 0.3). On the host, `MinionActor._observe()` runs every 0.25s while in the field and stamps nearby hostiles into `_field_log`. `MinionState.check_retreat()` fires from Idle/Chase/Attack at top of `tick()` and routes into `RetreatState`, which navigates to the owner's tower spawn marker and on arrival calls `KnowledgeManager.flush_observations(peer_id, log)` then transitions back to IdleState (with a partial heal so the trigger doesn't immediately re-fire). No retreat animation set yet (uses Run); no panic state; no faction tunables. See `docs/systems/minion-ai.md` for the architecture this'll migrate into.
7. ✅ **Courier for commands** — selection-based dispatch, courier delivery, return-home. **MVP shipped, refactored 2026-05-06 into the three-stage E-driven flow.** With `INSTANT_COMMANDS=false`: aim at a piece and E to add to selection (multi-member stacks open the ghost popup; aim at a ghost and E to add a single member); aim at the diorama (MapTarget) and E to record a draft for the current selection; aim at the on-table Paper and E to ready those drafts; walk to the Advisor and E to dispatch readied orders as couriers. The Advisor calls `KnowledgeManager.dispatch_readied(peer_id)`, which for each readied entry spawns a real Courier minion at the tower spawn with `waypoint = source_pos` and stamps `delivery_minion_ids` / `delivery_target_pos` / `return_pos` onto the actor. The Courier travels via inherited ChaseState; on arrival at the source, `courier_arrival_state.gd` sets each delivery target's waypoint to `delivery_target_pos`, then sets its own `waypoint = return_pos` and walks home, despawning on arrival (Leave mode). No Stay/Leave selection at composition time, no per-faction courier cap, and no LOS/staleness gate — those land with steps 12+.
8. ✅ **Courier for information** — scheduled reports back from the field. **First-pass MVP shipped.** New `info_courier` minion type (`data/minions/info_courier.tres`) and actor scene; `KnowledgeManager.dispatch_info_courier(peer_id, target_pos)` host-spawns one at the owner's tower spawn with `waypoint = target`. Lifecycle: travel via inherited ChaseState → `InfoCourierObserveState` (loiter `OBSERVE_DURATION = 4s`) → `RetreatState` → flush `_field_log` → IdleState/despawn. Bypasses the draft / Advisor handoff loop — info-missions are reactive, not order-batched. No dispatch UI yet (test harness `I` hotkey is the only entry point); composition surface lands with step 9.
9. **Command composition UI** — single-piece selection is shipped (step 7); the rest of this step is group-select (drag-select multiple at once, or marker-of-N representation), painted nav-mesh path arrow instead of straight line, an up-to-5-command stack with undo/confirm, and a separate "exit table holding plan-paper" step. Today the selection submits immediately on the second click; the composition UI will defer submission until explicit Confirm.
10. **Paper held item** — confirming at the table exits camera and places a plan-paper in the overlord's held-item slot (faction-flavored). *Blocked on the held-items system — see `held-items.md`.*
11. **Advisor handoff** — hand the paper to the Advisor minion in the tower; Advisor parses and queues plans. *Blocked on the Advisor command system — see `advisor.md`.*
12. **Courier cap + delivery modes** — per-faction cap on in-field couriers; Stay vs Leave per-order mode chosen at composition. WorldModel updates only on courier return, with Stay couriers carrying status reports and Leave couriers carrying only "delivered."
13. **Balcony shouting** — while holding the paper, standing on the tower balcony, issue orders by voice to any minion in visual range of the balcony (bypasses Advisor + courier, at the cost of exposure).
14. **Falsification hooks** — Eldritch dominate-courier, interception detection. Out of scope for first build.

---

## Map representation layer (phase plan)

A second build axis runs orthogonal to the numbered build order above: the **diorama as a representation** rather than a literal mini-world. Steps 1–8 shipped a render that was effectively a 1:1 minified physics world (one piece per minion, distance-on-the-table click hit-test). The phase plan below splits the diorama into a dedicated representation layer so future features (zoom, multiple maps, town/fortification icons, alliance overlays) are all variations on the same machinery.

The guiding principle: **the map is representation, the world is reality.** Two minions crossing paths in the world don't share orders, but on the diorama their pieces collapse into a single stack. Clicking a stack opens an in-world inspect popup, not a HUD overlay — the diorama is a physical thing the overlord walks around.

### Phase 1 — Real piece colliders, no camera takeover ✅ (2026-04-30)

- Each piece carries an `Area3D` ("ClickArea") on collision layer 32 (`WarTableMap.PIECE_COLLISION_LAYER_BIT`). Selection is a screen-space `PhysicsServer3D.intersect_ray` from the overlord camera through the crosshair — no plane-distance math, no `map_world_size` scaling concern.
- War table mode no longer takes over the camera or pins the rig. The overlord stays in first-person, mouse captured, walks around the table, and aims with the crosshair. Modal lock prevents other interactables (advisor, gem sites, …) from grabbing focus while the table is in use.
- Per-piece draft arrows: `KnowledgeManager.issue_move_command` records `legs: Array[{source_pos, minion_ids}]` (one leg per minion, snapshot at draft time). `WarTableMap._render_pending_commands` draws one red arrow per leg — pieces at different positions get individual arrows instead of a single centroid arrow. The legacy `source_pos` (centroid) field stays on draft entries until phase 4 swaps the courier path to multi-leg.
- Pieces with pending orders are filtered out of new selections via `KnowledgeManager.is_minion_pending(peer_id, minion_id)`. The lock lifts when the draft is cancelled (Q / Backspace) or the courier delivers and `notify_minion_removed` clears the entry.
- Q + Backspace controls: Q = clear all drafts and exit; Backspace = clear current selection or pop most recent draft.
- Couriers spawn at and return to a per-tower `CourierSpawn` `Area3D`, resolved via `MinionManager.get_courier_spawn_for(peer_id)`. The arrival test is **zone overlap** (`Area3D.overlaps_body`) not point-distance — point-distance fails on slopes and slight Y mismatches. Falls back to distance for setups (test harness) that bind a plain `Marker3D` instead of an Area3D.

### Phase 2 — Auto-merging stacks ✅ (2026-05-02)

- `WarTableMap` renders one node per **stack** (cluster of believed pieces), not one per minion. `_pieces` was replaced with `_stacks: Dictionary[StringName, Node3D]` keyed by sorted member ids joined by "," (e.g. `&"5,12,17"`) — stable across frames so the same membership reuses its visual node and doesn't flicker.
- Clustering: greedy proximity, `MERGE_DISTANCE = 0.15` table-local meters, scoped to `(owner_peer_id, faction)`. Mixed-ownership stacks would mislead the player; friendly/enemy lines never merge.
- Each stack's `ClickArea` is stamped with `member_ids: Array[int]` (instead of a single `minion_id`), `owner_peer_id`, and `faction` metadata. The `war_table_piece.tscn` `Label3D` "CountBadge" shows the count when `> 1` and is hidden for single-member stacks (so a stack of one looks identical to phase 1's piece).
- Click handler (`WarTable._command_move_to_click`) now resolves to a stack collider, filters members through `is_minion_pending`, and toggles selection in three modes: NONE selected → add all available; ALL available selected → remove them; PARTIAL → fill in the rest. A click on a stack with no available members is a deliberate no-op (doesn't fall through to dispatch).

### Phase 3 — In-world inspect popup ✅ (2026-05-06, refined later)

The whole table stopped being a modal — every affordance is now its own E-driven `Interactable` (see "Commands" table above). Q + Backspace hotkeys are gone; Reset replaces them.

- `WarTablePiece` (the cluster's chess piece) extends `Interactable`. Single-member: E toggles that id directly. Multi-member: E **latches the ghost popup** open (and a second E closes it) — `WarTable._popup_for_stack` holds the latch and the inspector mirrors it.
- `WarTableGhost` extends `Interactable` and lives as a child of its source stack while the popup is open. E toggles its single member id. Each ghost owns its own selection-tint material variant (default + highlight) and swaps between them in `_process` based on `WarTable.is_selected(member_id)` ∨ `_is_focused`. The map's stack-tint walker skips ghost subtrees so the stack-level "any selected" color doesn't bleed onto every ghost.
- Visual: a small yellow emissive sphere (`Visual/DefaultMesh`) is the authored fallback so ghosts are visible immediately. When the inspector successfully loads a per-type `MinionType.model_scene` it hides the fallback and parents the proper model under `Visual` instead.
- `WarTableStackInspector` (script-only Node child of `WarTable`) reads the latch each frame: spawns ghosts when it changes from null, despawns when it clears. A grace timer (`auto_close_seconds = 1.5`) auto-clears the latch when neither the source stack nor any of its ghosts have been focused for that long — so flicking your aim toward the MapTarget doesn't immediately yank the popup, but walking away does.
- Pieces / ghosts both stamp metadata (`member_ids`, `member_id`, `owner_peer_id`, `faction`) on their root Area3D so the prompt + select logic reads it without indirection. Foreign-owner stacks still render but show no prompt (uninteractable for the local peer).
- Already-pending members are filtered out of `_available_members` so a piece that's already locked into a draft can't be re-selected. The pending arrows already telegraph why.

**Acceptance** — verified live in `war_table_test.tscn`: spawn 4 minions in a tight cluster, walk up to the stack, E → 4 yellow spheres unfurl above. Aim at two of them, E each → only those two glow. Aim at MapTarget, E → those two go; the other two stay put. Aim away for >1.5s → ghosts despawn.

### Phase 4 — Multi-leg, multi-target couriers ✅ (2026-05-06, refined later)

Couriers now ride one per source cluster (matching the "board grouping" the player sees) up to a tunable per-type capacity, and an advanced courier can deliver multiple distinct orders — even to multiple targets — in a single outing.

- New `MinionType.max_orders: int = 1` field on the courier .tres controls how many sub-orders one courier can carry. Default `data/minions/courier.tres` is `5`, so five individual orders for five minions in the same stack ride a single courier.
- `MinionActor.delivery_legs` schema is now nested:
  ```
  delivery_legs: Array[{
      source_pos: Vector3,
      sub_orders: Array[{minion_ids: Array[int], target_pos: Vector3}],
  }]
  ```
  Each leg is "stop at this source cluster, deliver every sub-order here." `delivery_target_pos` is removed — the target is per-sub-order so a single leg can dispatch multiple distinct orders.
- `KnowledgeManager.dispatch_readied`:
  - Flattens every readied entry's `legs` into a list of sub-orders `{source_pos, minion_ids, target_pos, cmd_id}`.
  - Greedy first-fit chunks the list into batches of at most `max_orders`. Within a batch, sub-orders are clustered by source-pos proximity into legs (one stop per cluster). Legs are TSP-greedy ordered from the tower spawn.
  - Spawns one courier per batch with `courier.delivery_legs = ordered_legs`. Every entry whose sub-orders contributed to the batch is promoted to dispatched and stamped with the courier's id.
  - Writes the same `route_waypoints` polyline onto every entry sharing a courier; the renderer dedups by `courier_id`.
- `courier_arrival_state._deliver_head_leg` walks every sub-order at the leg, dispatching each via `MinionManager.command_selection_move(ids, target_pos)` (formation-slot distribution per sub-order). Pops the leg, advances to the next or heads home.
- `WarTableMap._render_pending_commands` adds a billboard `Label3D` count badge at the midpoint of every order arrow when its leg covers >1 minion, so the player can see at a glance how many minions an arrow applies to.
- `CountBadge` on the chess piece is now world-space (`fixed_size = false`) so the count grows and shrinks naturally with viewing distance instead of locking to viewport pixels.
- Legacy single-leg / one-courier-per-entry fallbacks remain in the renderer for any in-flight entry that predates the schema change.
