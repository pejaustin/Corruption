# Corruption & Gem Sites

**Build status:** Implemented (gem sites need editor placement) — see build-phases.md

> **History:** This page replaces `territory-control.md` (2026-06-05). The original design had two parallel resources — a per-player "influence" score and a grid-based territory/corruption system driven by minion presence. That split was confusing and unintentional: influence was renamed **Corruption**, and the territory grid was removed. Corruption is now tied to gem-site control ONLY.

---

## Overview

**Corruption** is the single per-player score. It is earned exclusively by holding Minor Gem Sites, and it drives three things:

1. **Avatar succession** — when the Avatar dies to a neutral (no hostile takeover), the highest-corruption peer takes over (`GameState.get_highest_corruption_peer()`).
2. **Boss debuff** — the Guardian Boss's HP/damage are reduced by *total* corruption (sum across all players, `GameState.get_total_corruption()`). Everyone's sites weaken the boss; whoever holds the Avatar reaps it.
3. **Divine intervention** — if zero gem sites are held for too long, the gods purge the land and all players lose.

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
│   ○ = Minor Gem Site (the ONLY corruption source)      │
│   Towers on periphery, Capitol at center               │
└────────────────────────────────────────────────────────┘
```

## Minor Gem Capture Flow

```
  OVERLORD prepares          AVATAR confirms
  ─────────────────          ────────────────
  1. Send minions to site    3. Take Avatar control
  2. Clear neutral defenders 4. Travel to prepared site
     (minion presence in     5. Hold E to channel capture
      clear radius)          6. Site trickles Corruption
         │                              │
         └── VULNERABLE ────────────────┘
             Site can be taken by rival
             minions before confirmation
```

**Key tension:** You can prepare a site as Overlord, but you can't lock it down without Avatar time. Other players can swoop in.

## Implementation

- `scripts/interactibles/gem_site.gd` (`GemSite`, in group `gem_sites`) — NEUTRAL → CLEARED (minion presence) → CAPTURED (Avatar channel). While CAPTURED, trickles `corruption_per_second` (default 0.5) to the controlling peer via `GameState.add_corruption`.
- `GameState.corruption` — `Dictionary[int, float]`, host-authoritative, broadcast on change (`corruption_changed` signal).
- `scripts/guardian_boss.gd` — debuff = `clampf(total / 60.0, 0, 0.6)`. At current tuning, one site held for ~2 minutes maxes the debuff; revisit once sites are placed.
- `scripts/divine_intervention.gd` — arms on the first capture; zero held sites for 60s (checked every 2s, recovers at 2× while held) → all players lose.

## Divine Intervention (Lose Condition)

- No arbitrary timer — pressure comes from site control.
- If **no gem site is held by anyone** for 60 seconds, the gods seal the gems permanently. All players lose.
- Arms only after the first capture, so the early game is exempt.
- Creates natural pressure — somebody must always be corrupting, even while players knife each other for the Avatar.

## The Neutral Faction ("The Good")

- AI-driven, hostile to all players.
- Defends gem sites; future: actively re-clears captured sites.
- **Asymmetric detection by faction:**
  - Demonic: highly detectable
  - Undeath: detectable
  - Eldritch: detectable
  - Nature/Fey: **undetectable** by priests

## Open Design Questions

- Can captured gem sites be lost / stolen by rival players? (Currently capture is permanent, which means corruption only goes up and divine intervention only threatens the early game. Contested recapture would keep both live all match.)
- How are held sites visually represented? (Faction-colored gem glow? Environmental change radiating from the site?)
- Should sites differ — corruption rate, clear difficulty, distance-to-Capitol risk curve?
- Does the war-table belief model apply to site state, or is site control public information?
