# Faction Design

**Build status:** Design done | Implementation not started

---

## Overview

Four asymmetric factions, each representing a different type of corruption. Every faction has a unique relationship with Avatar time, Overlord tools, and map presence.

## Faction Axes

```
        Avatar Desire ──────────────────────────►
   LOW                                        HIGH
    │                                           │
    │  ELDRITCH          UNDEATH    DEMONIC     │
    │  (needs it for     (confirm   (wants to   │
    │   rituals, then     gems)     fight)      │
    │   gives it back)                           │
    │                   NATURE/FEY              │
    │                   (infiltrate)             │


        Overlord Depth ─────────────────────────►
   LOW                                        HIGH
    │                                           │
    │  UNDEATH    DEMONIC    NATURE    ELDRITCH │
    │  (simple)   (medium)   (vision)  (puppet) │


        Map Spread ─────────────────────────────►
   FOCUSED                                    WIDE
    │                                           │
    │  ELDRITCH  DEMONIC    UNDEATH  NATURE/FEY│
    │  (worst)   (corridor)  (swarm)  (best)    │


        PvP Strength ──────────────────────────►
   WEAK                                      STRONG
    │                                           │
    │  NATURE    UNDEATH    DEMONIC   ELDRITCH │
    │  (avoids)  (mixed)    (mixed)   (best)   │
```

## Counter-Play Matrix

```
         Undeath ──swarms──► Demonic
            ▲                   │
            │               smashes
         outpaces               │
            │                   ▼
        Nature/Fey ◄──bullies── Eldritch
```

Each faction has a natural predator and natural prey.

## Faction Detail: Undeath

| Aspect | Detail |
|--------|--------|
| **Corruption type** | Necromancy |
| **Playstyle** | Swarm / attrition — flood the map with cheap bodies |
| **Minions** | Cheap, numerous, simple commands. Can raise fallen enemy minions |
| **Avatar** | Medium strength. Purpose: confirm gem captures, bolster swarm |
| **Overlord** | Weakest tools. Compensates with minion throughput |
| **Territory** | Good spread — corruption is wide but shallow |
| **Weakness** | Limited tower mechanics, individual minions are weak |

## Faction Detail: Demonic

| Aspect | Detail |
|--------|--------|
| **Corruption type** | Hellfire |
| **Playstyle** | Brute force — strong specialized units, beginner-friendly |
| **Minions** | Expensive, powerful, specialized roles |
| **Avatar** | Strongest in combat. The brawler. Wants Avatar time most |
| **Overlord** | Medium depth, straightforward tools |
| **Territory** | Focused — pushes corridors, struggles to hold wide territory |
| **Weakness** | Units expensive to replace, highly visible on the board |

## Faction Detail: Nature/Fey

| Aspect | Detail |
|--------|--------|
| **Corruption type** | Wild corruption |
| **Playstyle** | Map control, PvE dominance, infiltration |
| **Minions** | Specialized but weak in direct combat |
| **Avatar** | Weak fighter, but undetectable by human priests. Stealth infiltrator |
| **Overlord** | High depth. Best map visibility, excellent territory tools |
| **Territory** | Best in game — spreads wide, controls efficiently |
| **Weakness** | Crumbles in PvP. Can't fight, must avoid |

## Faction Detail: Eldritch / Deep One

| Aspect | Detail |
|--------|--------|
| **Corruption type** | Madness |
| **Playstyle** | Puppet master — manipulate from tower, strongest saboteur |
| **Minions** | Dominated from other factions + summoned via Avatar rituals |
| **Avatar** | Weakest fighter, but required for rituals that unlock best abilities |
| **Overlord** | Highest depth. Best sabotage, can dominate enemy minions and NPCs |
| **Territory** | Worst — can manipulate but can't hold ground |
| **Weakness** | Poor territory control, Avatar is vulnerable during rituals |

## Open Design Questions

- Detailed minion rosters per faction
- Faction-specific Avatar skill trees
- Faction-specific tower upgrade paths
- Visual identity for each faction's corruption on the map
