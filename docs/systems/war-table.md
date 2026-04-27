# War Table — Information & Command System

**Build status:** Steps 1–4 in. `KnowledgeManager` autoload + per-peer `WorldModel`, diorama rendering via `WarTableMap`, table↔world click mapping, and the isolated `war_table_test.tscn` harness are all live. The harness now uses real `OverlordActor` + `MinionActor` + `MinionManager` (single-peer via `OfflineMultiplayerPeer`) instead of stand-in fakes — full command-loop is testable without booting the lobby. `INFINITE_BROADCAST_RANGE` and `INSTANT_COMMANDS` still default to `true` so the rest of the game plays unchanged, but they're now runtime-mutable (`static var`) so tests can toggle them without restarting. Steps 5–9 (range truthing, retreat reporting, courier commands/info, falsification) are pending.

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
    pending_commands:           { command_id → { target_pos, issued_tick, courier_id? } }
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

Clicking a target on the War Table does **not** move minions. It records an **intent** in the overlord's pending_commands. The Advisor then dispatches a courier carrying that order toward the target region. Minions receive the order only when the courier physically reaches them. If the courier dies en route, the order dissolves. If the army has moved, same result as Path 2: courier returns empty-handed, order undelivered.

Visually:
- A **ghost flag** appears on the table at the intended target the moment the player clicks.
- A **courier icon** animates across the table from tower toward target.
- When the courier arrives at the target region, the ghost flag becomes a **solid flag** (order active) or disappears (no minions found).
- If the courier dies, the ghost flag turns red then fades.

This makes the "command latency" the player's *own* latency — they can see their orders in flight.

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

- Table surface is a **diorama**, always rendered in world space. Any player walking past any tower can glance at any table and see that overlord's current belief.
- Minion pieces are chess-piece-style miniatures, parented to the table, colored by faction.
- Gems, towers, and the Capitol are drawn/labeled icons, placed statically at the start of the match.
- A stylized map texture (hand-drawn feel) covers the table surface to provide regional context independent of world sculpting state.
- Staleness is shown visually — recent data is crisp, old data is faded, very old data is replaced with a "?" token.

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
- One **real `OverlordActor`** named `"1"` (peer-id authority requirement) — walk around with WASD, approach the table, press E to use it.
- A `World/StartingMinions` node holding **`StartingMinionSpec` markers** — drop Marker3D children, set `type_id`/`faction`/`owner_peer_id` in the inspector, and the controller spawns one real `MinionActor` per spec on `_ready` (call path: `MinionManager._spawn_minion_rpc.rpc(...)` runs locally under the offline peer).
- Hotkeys for fast iteration:
  - `1`/`2`/`3`/`4` — spawn Skeleton (yours) / Imp (Demonic) / Sprite (Fey) / Cultist (Eldritch) at random points
  - `F` — cycle your overlord's faction (tests piece-color rendering and faction-gated table features)
  - `K` — kill nearest minion (tests `notify_minion_died` → `KnowledgeManager.notify_minion_removed` → piece removal)
  - `R` — wipe + respawn the authored starting state
  - `T` / `B` — toggle `INSTANT_COMMANDS` / `INFINITE_BROADCAST_RANGE` at runtime
  - `Esc` — release/recapture mouse  ·  `Shift+Esc` — quit
  - At the table: left-click commands, right-click / shift-click use faction features, `Ctrl+Click` drops a yellow debug marker at the projected world point (pure click→world projection check, no command)

Because the harness runs the real `MinionManager`, the autoload's ingest loop populates peer 1's `WorldModel` automatically — the controller doesn't write sightings itself. Use this scene to exercise courier animations, staleness fade, and falsification once those land.

---

## Build order

1. ✅ **`WorldModel` + `KnowledgeManager` stub** — autoload at `scripts/knowledge/`, per-peer dicts, `INFINITE_BROADCAST_RANGE` and `INSTANT_COMMANDS` flags defaulting to `true`. `MinionManager.notify_minion_died` forwards to `KnowledgeManager.notify_minion_removed`.
2. ✅ **War Table reads from WorldModel** — `WarTableMap` spawns a colored cylinder piece per believed minion. Table `_process` calls `map.render_from_model(KnowledgeManager.get_model(peer_id))` each frame.
3. ✅ **Table-space ↔ world-space mapping + click handling** — `WarTableMap` exports `map_world_center`, `map_world_size`, `table_surface_size`. `camera_ray_to_world()` projects table clicks onto the map plane and converts to battlefield coords. `WarTableRange` (tool script) draws a semi-transparent BoxMesh covering the effective region so designers can see it in-editor and in-game.
4. ✅ **Test scene** — `scenes/test/war_table_test.tscn` runs the real `WarTable` + `OverlordActor` + `MinionManager` via `OfflineMultiplayerPeer`. Starter minions are authored as `StartingMinionSpec` Marker3D children. Full command loop is exercised end-to-end.
5. **Broadcast-range truthing** — flip `INFINITE_BROADCAST_RANGE` off, tune range, validate staleness visuals.
6. **Forced retreat + return-to-tower update** — a retreating minion's arrival flushes its sightings log.
7. **Courier for commands** — ghost flags, courier animation, courier success/failure. `KnowledgeManager.issue_move_command` already routes through a flag-gated path.
8. **Courier for information** — scheduled reports back from the field.
9. **Command composition UI** — cursor-based minion/group select, destination click, painted path arrow, up-to-5-command stack with undo/confirm. Replaces the current click-to-move on confirm; `INSTANT_COMMANDS=true` still bypasses to the direct path for playtesting.
10. **Paper held item** — confirming at the table exits camera and places a plan-paper in the overlord's held-item slot (faction-flavored). *Blocked on the held-items system — see `held-items.md`.*
11. **Advisor handoff** — hand the paper to the Advisor minion in the tower; Advisor parses and queues plans. *Blocked on the Advisor command system — see `advisor.md`.*
12. **Courier cap + delivery modes** — per-faction cap on in-field couriers; Stay vs Leave per-order mode chosen at composition. WorldModel updates only on courier return, with Stay couriers carrying status reports and Leave couriers carrying only "delivered."
13. **Balcony shouting** — while holding the paper, standing on the tower balcony, issue orders by voice to any minion in visual range of the balcony (bypasses Advisor + courier, at the cost of exposure).
14. **Falsification hooks** — Eldritch dominate-courier, interception detection. Out of scope for first build.
