# Advisor & Command System

**Build status:** First-pass MVP shipped (handoff intake + courier dispatch only). Stats at `data/minions/advisor.tres`. Actor scene `scenes/actors/minion/types/advisor_actor.tscn` runs two custom states — `advisor_idle_state.gd` and `advisor_follow_state.gd` (mounted as overrides on the inherited IdleState / ChaseState nodes; both find the owner overlord via the `actors` group and the `owner_peer_id`-named OverlordActor). The Advisor follows its owner with a 2.0m / 3.5m hysteresis. A `HandoffArea` Area3D child (1.2×3×1.2 box centered at body height, on the interactable layer so the gaze raycast detects it) runs `scripts/interactibles/advisor_handoff.gd`: when the owning overlord aims at the Advisor and presses E, `KnowledgeManager.dispatch_drafts(peer_id)` runs on the host. For each entry currently in `&"draft"` stage on the peer's `WorldModel.pending_commands`, a Courier is spawned at the tower spawn marker with `waypoint = source_pos` and a delivery payload (`delivery_minion_ids`, `delivery_target_pos`, `return_pos`) attached to the courier actor — the entry flips to `&"dispatched"` and `courier_id` is filled in. What's still TODO: paper-item handoff (`held-items.md`), spoken/balcony intake mode, multi-command-type parsing (currently movement only), faction courier caps, Stay-vs-Leave delivery modes, dominate/impersonate hooks, and combat-survivability tuning (currently hp 40, no aggro, no defenses).

---

## Overview

The **Advisor** is a minion NPC who lives in the overlord's tower and is the single point of contact between the overlord's *intent* and the world's *execution*. The overlord does not directly push buttons that move minions, capture gems, or dispatch couriers. The overlord formulates a plan (usually by producing a held item at a station like the War Table), **hands the plan to the Advisor**, and the Advisor decides how to execute it.

This system is **broader than the War Table.** The War Table produces one kind of plan (movement orders). Other stations will eventually produce others (defensive postures, construction orders, ritual preparations, diplomatic dispatches). All of them route through the Advisor.

```
┌─── OVERLORD ────┐      ┌──── ADVISOR ────┐      ┌──── WORLD ────┐
│                 │      │                 │      │                │
│  Compose plan   │ ───▶ │  Parse payload  │ ───▶ │  Couriers      │
│  (War Table,    │      │  Decide how to  │      │  Minions       │
│   etc.)         │      │  execute        │      │  Summons       │
│                 │      │  Queue Commands │      │  ...           │
│  Hand paper to  │      │                 │      │                │
│  Advisor        │      │  Can be killed  │      │                │
│                 │      │  Can be lied to │      │                │
└─────────────────┘      └─────────────────┘      └────────────────┘
```

---

## Design goals

- **A bottleneck, not a menu.** The Advisor is a physical minion who **follows the overlord around the tower**, always within earshot. Commands must be handed over or spoken aloud in their presence — they are never "just received" from a UI. The friction of needing the Advisor in the same room is the point, and it's what makes assassinating the Advisor meaningful.
- **Single handoff surface.** Any new command type ships as a new held-item payload + an Advisor parser, not as a new UI popup on the overlord's HUD.
- **Fallible and attackable.** The Advisor can be killed, silenced, dominated, or impersonated. Falsification attacks (see `war-table.md`) route through the Advisor because it is the canonical writer of the overlord's WorldModel and the canonical dispatcher of their commands.
- **Diegetic command queue.** The Advisor has a visible workload — overlord can see stacked papers on the Advisor's desk, couriers waiting for orders, etc. No hidden queue.

---

## Command lifecycle

The Advisor accepts commands through **two intake modes**, both of which require the Advisor to be physically present:

- **Handoff intake** — the overlord hands the Advisor a held item (e.g. plan-paper from the War Table). The payload is parsed from the item.
- **Spoken intake** — the overlord issues orders aloud while the Advisor is within earshot. The primary case is balcony-shouting (see `war-table.md`): the overlord reads the plan-paper aloud from the balcony, the Advisor is right beside them listening in, and the Advisor treats the shouted orders the same way it would treat a handed-over paper — except execution is immediate-voice-to-visible-minions instead of couriers. Since the Advisor follows the overlord everywhere in the tower, "within earshot" is the normal state.

Once a payload is received:

1. **Advisor parses** it into command objects. Different inputs map to different command subclasses:
   - Plan-paper (handed) → `MovementCommand` — group targets, destinations, Stay/Leave modes, dispatched via couriers.
   - Plan-paper (shouted from balcony) → `MovementCommand` — same payload, but execution is direct voice to any minion in visual range of the balcony; no couriers dispatched.
   - *(future)* Sealed order → `ConstructionCommand`, `RitualCommand`, etc.
2. **Advisor decides execution strategy.** For courier-routed movement commands: dispatch one courier per group, subject to the faction's courier cap. If the cap is hit, queue until a courier returns. For shouted movement commands: resolve immediately against minions in balcony sight range.
3. **Advisor emits sub-tasks** (courier dispatches, minion orders, whatever the command resolves to).
4. **Sub-tasks report back** to the Advisor on completion or failure.
5. **Advisor writes to the overlord's WorldModel** with outcome data (where applicable).

The key property: *the overlord's WorldModel is only ever written by the Advisor.* Balcony-shouting does not bypass this — the Advisor is standing beside the overlord on the balcony and is the one who updates the table after the shout lands. If the Advisor is dead, no updates arrive — and no shouted or handed-over commands are processed either. If the Advisor is compromised, updates are lies.

---

## Advisor as a target

- **Killable.** The Advisor has HP and can be attacked by an infiltrating Avatar or a minion sent by another overlord. While dead, the overlord cannot issue commands or receive WorldModel updates. A new Advisor spawns after a delay (TBD — probably long enough to hurt).
- **Dominatable (Eldritch).** Eldritch players can temporarily control an enemy Advisor, corrupting the commands it issues or the WorldModel it writes.
- **Impersonatable (later).** A doppelganger Advisor, planted in sabotage, poisons the overlord's WorldModel with crafted lies. Out of scope for first build — design hook only.

These are the reasons the Advisor exists as a physical entity. A UI-only command system would have no analogous attack surface.

---

## Command types (initial + planned)

| Command | Produced by | Sub-tasks | WorldModel update on completion |
|---|---|---|---|
| `MovementCommand` | War Table plan-paper | Dispatch couriers per group, Stay/Leave modes | Stay: execution status + sightings. Leave: "delivered" only. |
| *(planned)* `ConstructionCommand` | TBD station | Dispatch worker minion(s) | Structure state |
| *(planned)* `RitualCommand` | Ritual Site reagent | Dispatch ritualist minion or spend locally | Buff applied |
| *(planned)* `RecallCommand` | Tower recall action | Dispatch courier with recall order (same as War Table Path 2) | Returning minion sightings |

---

## Courier cap (War Table–specific for now)

For movement commands, the Advisor manages a **per-faction cap on in-field couriers.** When the overlord hands over a plan with more groups than free courier slots, the remainder queue on the Advisor's desk until slots open. This cap is a lever for faction asymmetry:

| Faction | Courier cap (tentative) | Notes |
|---|---|---|
| Fey | Highest | Information-advantage faction; more couriers = fresher WorldModel |
| Demonic | Medium | |
| Undeath | Low but raise-able | Can reanimate fallen couriers as new ones |
| Eldritch | Low | Compensates by dominating enemy couriers instead |

Numbers TBD. Tuned in a later balance pass.

---

## Open questions

- Is the Advisor a **fixed tower NPC** (one per tower, respawns on death) or a **summoned minion** the overlord can choose from their roster?
- Does each station have its own dedicated NPC (War Advisor, Ritual Advisor, ...) or one generalist Advisor that accepts everything?
- Does the Advisor have an inventory visible to walking-past observers — i.e. can a rival glimpse your pending plans through a Palantir / Mirror?
- What happens to in-flight couriers when the Advisor dies? Do they still complete and just have no one to report back to? Do they go feral?
- Does the Advisor have combat ability, or is it a defenseless specialist that relies on the tower's other minions for protection?
- If the overlord dies/transfers to Avatar mode mid-plan, does the Advisor continue executing queued commands?

---

## Dependencies

- **Held items system** (`held-items.md`) — the handoff surface. No Advisor work is possible without at least the plan-paper item wired up.
- **Minion AI** — the Advisor is a minion with specialized behavior. Reuses the standard `MinionActor` / state machine.
- **Networking** — the Advisor's state (HP, queue contents, dispatched couriers) is host-authoritative and replicated to the owning peer's client.

---

## Consumers currently blocked on this system

- **War Table → courier dispatch** (see `war-table.md` Build order step 11).
- **Falsification hooks** (War Table step 14) — dominate-advisor and impersonate-advisor routes both require the Advisor to exist first.
- Any future command-producing station.
