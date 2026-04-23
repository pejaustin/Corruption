# War Table — Information & Command System

**Build status:** Steps 1–4 in. `KnowledgeManager` autoload + per-peer `WorldModel`, diorama rendering via `WarTableMap`, table↔world click mapping, and the isolated `war_table_test.tscn` harness are all live. `INFINITE_BROADCAST_RANGE` and `INSTANT_COMMANDS` still default to `true` so the rest of the game plays unchanged. Steps 5–9 (range truthing, retreat reporting, courier commands/info, falsification) are pending.

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
# In GameConstants or a dedicated KnowledgeConfig
const INFINITE_BROADCAST_RANGE: bool = true
const INSTANT_COMMANDS: bool = true
```

When these are true:
- Every friendly and enemy minion continuously updates every overlord's WorldModel (effectively a 1:1 mirror of truth).
- Commands apply instantly — clicks move real minions, no couriers.
- The WarTable behaves as a transparent god-view.

This is the configuration for playtesting combat, territory, boss fights, etc. Switch off per-flag once individual subsystems are ready.

### War Table test scene

A dedicated scene `scenes/test/war_table_test.tscn` whose only purpose is rapid iteration on the diorama, piece rendering, and click mapping. Contents:

- One War Table instance.
- An overlord player model positioned at the table's stand point (no network, no lobby, no menus).
- A handful of **scripted fake minions** — `Node3D`s with a simple path-follow script that walk around a dummy playspace. They're not `MinionActor` instances; they just publish their position to a mock `KnowledgeManager`.
- A mock `KnowledgeManager` that exposes the same API as the real one but with configurable staleness (inject delays and stale entries to test the visual treatment).
- Hotkeys for fast iteration:
  - `1` — teleport a fake minion, check that the table piece lags realistically.
  - `2` — kill a fake minion, check piece removal and any death indicator.
  - `3` — toggle broadcast range (test what stale entries look like).
  - `4` — issue a command click programmatically, check courier animation.

This scene lets you develop the whole War Table in isolation, including artwork on the table surface, piece meshes, staleness fade, courier animations, and click projection — none of which need the full game running.

---

## Build order

1. ✅ **`WorldModel` + `KnowledgeManager` stub** — autoload at `scripts/knowledge/`, per-peer dicts, `INFINITE_BROADCAST_RANGE` and `INSTANT_COMMANDS` flags defaulting to `true`. `MinionManager.notify_minion_died` forwards to `KnowledgeManager.notify_minion_removed`.
2. ✅ **War Table reads from WorldModel** — `WarTableMap` spawns a colored cylinder piece per believed minion. Table `_process` calls `map.render_from_model(KnowledgeManager.get_model(peer_id))` each frame.
3. ✅ **Table-space ↔ world-space mapping + click handling** — `WarTableMap` exports `map_world_center`, `map_world_size`, `table_surface_size`. `camera_ray_to_world()` projects table clicks onto the map plane and converts to battlefield coords. `WarTableRange` (tool script) draws a semi-transparent BoxMesh covering the effective region so designers can see it in-editor and in-game.
4. ✅ **Test scene** — `scenes/test/war_table_test.tscn` with wandering `FakeMinion` actors, a `WarTableTestController` that feeds sightings into `KnowledgeManager.get_model(9999)`, and hotkeys `1`–`4` / click for rapid iteration without the full game.
5. **Broadcast-range truthing** — flip `INFINITE_BROADCAST_RANGE` off, tune range, validate staleness visuals.
6. **Forced retreat + return-to-tower update** — a retreating minion's arrival flushes its sightings log.
7. **Courier for commands** — ghost flags, courier animation, courier success/failure. `KnowledgeManager.issue_move_command` already routes through a flag-gated path.
8. **Courier for information** — scheduled reports back from the field.
9. **Falsification hooks** — Eldritch dominate-courier, interception detection. Out of scope for first build.
