# Avatar Combat

**Build status:** Not started

---

## Overview

The Avatar is the player's direct presence in the world. Third-person, Souls-like action combat. Only one Avatar is active at any time.

```
┌─────────────────────────────────────────────┐
│                 AVATAR                       │
│                                              │
│  3rd Person Camera                           │
│  ┌─────────┐                                 │
│  │ Player  │──── Movement (WASD + dodge)     │
│  │ Model   │──── Light attack                │
│  │         │──── Heavy attack                │
│  └─────────┘──── Block / parry               │
│       │     ──── Faction ability (1-3)        │
│       │                                      │
│       ▼                                      │
│  ┌──────────┐                                │
│  │ State    │  Idle ↔ Move ↔ Attack          │
│  │ Machine  │  Jump ↔ Fall ↔ Dodge           │
│  │          │  Block ↔ Stagger ↔ Death       │
│  └──────────┘                                │
│                                              │
│  Stats: HP | Stamina | Corruption Power      │
└─────────────────────────────────────────────┘
```

## Combat Model

- **Stamina-based:** Attacks, dodges, and blocks consume stamina. Stamina regens when not acting.
- **Commitment:** Attacks have wind-up and recovery — you commit to swings. Cancel windows are deliberate.
- **Stagger:** Enough hits break poise, opening a stagger window for bonus damage.

## Faction Avatar Differences

| Faction | Avatar Style | Unique Trait |
|---------|-------------|--------------|
| Undeath | Medium combat, attrition | Sustain — drains life on hit |
| Demonic | Strongest combat, aggressive | Raw power — highest damage output |
| Nature/Fey | Weak combat, evasive | Stealth — undetectable by priests, infiltration |
| Eldritch | Weakest combat, utility | Ritual — can summon/activate faction abilities in the field |

## Open Design Questions

- What does the skill tree look like? Is it faction-specific?
- How does loot work — random drops, fixed locations, crafting?
- Does Avatar progress persist across control transfers?
- Dodge: i-frames or position-based?
- Lock-on targeting or free aim?
