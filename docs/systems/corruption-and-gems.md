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

The gate is **the absence of hostiles**, not the presence of friendlies. The Avatar captures any uncontested site freely; hostile minions (another faction or the neutral faction) within the contest radius block capture and break an active channel. Friendly minions are never *required* — they're how you clear and hold the area.

```
  Site CONTESTED?            AVATAR captures
  ─────────────────          ────────────────
  Hostile minions within     No hostiles in radius:
  contest_radius block       walk up, hold E, channel
  capture. Clear them        completes → site trickles
  (minions or Avatar's       Corruption to you until
  own sword) to open it.     its capacity is drained.
         │                              │
         └── VULNERABLE ────────────────┘
             A rival minion walking into
             radius re-contests the site
             and breaks a channel mid-cast
```

**Key tension:** Holding a site open for capture takes board presence, but only Avatar time converts it. Other players can swoop in.

## Implementation

- `scripts/interactibles/gem_site.gd` (`GemSite`, in group `gem_sites`) — NEUTRAL → CAPTURED (Avatar channel, blocked while `_hostiles_near()` within `contest_radius`, default 8m; host re-checks mid-channel and at completion).
- **Ceiling + regen model (corrected 2026-06-05):** a held site adds `max_corruption_contribution` (default 7) to its holder's **maximum** corruption (`GameState.get_max_corruption(peer)` = Σ held-site contributions) and regenerates the holder's corruption toward that ceiling at `corruption_per_second` (default 0.5). Sites **never deplete** — anything that drains corruption (future abilities) just gets refilled by held sites. Holding more sites = higher max AND faster combined regen.
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

- Can captured gem sites be lost / stolen by rival players? (Currently capture is permanent. Contested recapture would keep divine intervention live all match — the contest check already exists for the capture gate. Note: on site loss, the holder's max drops; does corruption above the new max clamp instantly, decay, or persist?)
- How are held sites visually represented? (Faction-colored gem glow? Environmental change radiating from the site?)
- Should sites differ — regen rate, **max contribution**, clear difficulty, distance-to-Capitol risk curve?
- Boss-debuff tuning: with 3 sites × 7 contribution, the global ceiling is 21 total corruption → max debuff 21/60 = **35%**, well short of the 60% cap. Raise contributions, lower the divisor, or accept — decide at the boss playtest.
- Does the war-table belief model apply to site state, or is site control public information?
