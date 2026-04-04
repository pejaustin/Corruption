# Territory & Gems

**Build status:** Not started

---

## Overview

Territory control and gem capture are the two sources of **ambient influence** — the resource that determines Avatar succession and debuffs the final bosses.

```
┌─────────────────────── THE MAP ───────────────────────┐
│                                                        │
│   [Tower 1]              [Capitol]           [Tower 2] │
│       │                 ┌────────┐               │     │
│       │    ○ temple     │ MAIN   │    ○ village  │     │
│       │                 │  GEM   │               │     │
│       │  ○ village      └────────┘  ○ holy site  │     │
│       │                                          │     │
│   [Tower 3]     ○ settlement          [Tower 4]  │     │
│                  ○ holy site                      │     │
│                                                        │
│   ○ = Minor Gem Site                                   │
│   Towers on periphery, Capitol at center               │
└────────────────────────────────────────────────────────┘
```

## Ambient Influence

Two sources, additive:

1. **Territory** — Corrupted land area. More = more influence.
2. **Minor Gems** — Captured and tapped at settlements, temples, holy sites.

## Minor Gem Capture Flow

```
  OVERLORD prepares          AVATAR confirms
  ─────────────────          ────────────────
  1. Send minions to site    3. Take Avatar control
  2. Clear neutral defenders 4. Travel to prepared site
     and hold territory      5. Interact to confirm capture
                             6. Gem begins generating influence
         │                              │
         └── VULNERABLE ────────────────┘
             Site can be taken by rival
             minions before confirmation
```

**Key tension:** You can prepare a site as Overlord, but you can't lock it down without Avatar time. Other players can swoop in.

## The Neutral Faction ("The Good")

- AI-driven, hostile to all players.
- **Actively reclaims territory** — corruption decays if undefended.
- **Asymmetric detection by faction:**
  - Demonic: highly detectable
  - Undeath: detectable
  - Eldritch: detectable
  - Nature/Fey: **undetectable** by priests

## Divine Intervention (Lose Condition)

- No arbitrary timer.
- The good faction purifies corruption over time.
- If total corruption across all players drops too low, the gods **seal the gems permanently**.
- All players lose.
- Creates natural late-game pressure — you must keep pushing or collectively fail.

## Open Design Questions

- How fast does corruption decay without minion presence?
- Can captured minor gems be stolen by rival players?
- How is territory visually represented? (Color overlay? Environmental change?)
- Are there neutral structures that provide benefits when corrupted?
- How close to a gem site does a player need to be to "confirm" capture?
