# Boss Mechanics

**Build status:** Tier 3 (Guardian) done; Tier 4 (BossManager + Seraph) scripts ready, needs editor setup.

## Implementation

- **Phase 1 — Capitol Guardian:** `scenes/actors/enemy/guardian/guardian_boss.tscn` (script `scripts/guardian_boss.gd`, stats from `data/minions/guardian_boss.tres`). Pre-placed in the world.
- **Phase 2 — Corrupted Seraph:** `scenes/actors/enemy/seraph/corrupted_seraph.tscn` is an **inherited scene** of `guardian_boss.tscn` with `minion_type = corrupted_seraph.tres` and `boss_name = "Corrupted Seraph"`. No runtime script override — just scene inheritance.
- **Sequencer:** `scripts/boss_manager.gd` (BossManager Node in `tower_scene.tscn`). Exports `initial_boss`, `seraph_scene`, `seraph_spawn_point`. Listens for `boss_defeated`, runs 3s intermission, instantiates the Seraph scene, then announces win on phase-2 defeat.

---

## Overview

The win condition. The Avatar must defeat two bosses back-to-back in the Capitol to corrupt the main gem.

```
┌──────────────── BOSS ENCOUNTER ────────────────┐
│                                                  │
│  Avatar enters Capitol                           │
│       │                                          │
│       ▼                                          │
│  ┌──────────┐    defeat    ┌──────────┐          │
│  │  BOSS 1  │ ──────────► │  BOSS 2  │          │
│  │          │              │          │          │
│  │ Debuffed │   no heal    │ Debuffed │          │
│  │ by total │   between    │ by total │          │
│  │ + personal│             │ + personal│         │
│  │ corruption│             │ corruption│         │
│  └──────────┘              └─────┬────┘          │
│       │                          │               │
│    Avatar                     Victory            │
│    defeated                  GEM CORRUPTED       │
│       │                      YOU WIN             │
│       ▼                                          │
│  Control passes to next                          │
│  highest influence player                        │
│  Bosses reset to current                         │
│  debuffed state                                  │
│                                                  │
│  ┌────────────────────────────────────┐          │
│  │ ASTRAL PROJECTION                  │          │
│  │                                    │          │
│  │ All other players are pulled into  │          │
│  │ the boss room as spectators.       │          │
│  │ Can watch and heckle.              │          │
│  │ Cannot interfere.                  │          │
│  │ Minions/territory on autopilot.    │          │
│  └────────────────────────────────────┘          │
└──────────────────────────────────────────────────┘
```

## Boss Debuff System

The bosses are designed to be near-impossible at full strength. The match is a long prep phase to weaken them.

**Debuff sources:**
- **Total corruption** (all players combined) — reduces boss HP, damage, speed
- **Personal corruption** (attempting player's influence) — additional debuffs
- **Map interactions** — corrupting holy sites near the Capitol weakens its defenses

This means:
- All 4 players indirectly cooperate on total corruption
- But compete for who gets to cash in on the weakened bosses
- A Nature/Fey player with massive territory could face paper bosses despite weak Avatar combat

## Attempt Failure

- Avatar dies → control transfers to next highest influence player
- Bosses reset to their **current debuffed state** (not full health — debuffs are permanent for the match)
- New Avatar gets a fresh attempt at the same difficulty
- Influence can shift during the attempt (Overlord minions still active in background)

## Open Design Questions

- What are the two bosses? Thematic design? One physical, one magical?
- Specific debuff numbers — how much does each corruption point reduce boss stats?
- Can the Avatar retreat from the boss fight, or is it a commitment?
- Is there a minimum corruption threshold to even enter the Capitol?
- Do the bosses have phases or is it a straight fight?
