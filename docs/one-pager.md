# Corruption — One-Page Overview

**A PvP Dark Lord simulator where four players compete to corrupt the land of the good.**

---

## Core Loop

```
                         ┌─────────────────────────────────┐
                         │         MATCH START              │
                         │   4 players, 4 factions, 1 map   │
                         └───────────┬─────────────────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │                                  │
             ┌──────▼──────┐                  ┌───────▼───────┐
             │   AVATAR    │                  │   OVERLORD    │
             │  (1 player) │                  │  (3 players)  │
             │             │                  │               │
             │ 3rd person  │    Palantir:     │ 1st person    │
             │ Souls-like  │◄── watch but ───►│ Tower view    │
             │ combat      │    they know     │               │
             │             │                  │ Mirror:       │
             │ - Fight     │                  │ video msgs    │
             │ - Explore   │                  │ to rivals     │
             │ - Capture   │                  │               │
             │   gems      │                  │ - Spawn       │
             │ - Infiltrate│                  │   minions     │
             │             │                  │ - Control     │
             └──────┬──────┘                  │   territory   │
                    │                         │ - Sabotage    │
                    │                         │ - Diplomacy   │
                    │                         └───────┬───────┘
                    │                                  │
                    └────────────┬─────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │    AVATAR TRANSFER      │
                    │                         │
                    │ Hostile: minions kill    │
                    │ Fallback: most influence │
                    └────────────┬────────────┘
                                 │
              ┌──────────────────▼──────────────────┐
              │           ENDGAME                    │
              │                                      │
              │  Avatar reaches Capitol → 2 bosses   │
              │  Bosses debuffed by total corruption  │
              │  Other players: astral spectators     │
              │  If Avatar dies → next in line        │
              │                                      │
              │  WIN: Corrupt the gem                 │
              │  LOSE: Divine intervention (all lose) │
              └──────────────────────────────────────┘
```

---

## The Four Factions

```
    UNDEATH              DEMONIC             NATURE/FEY           ELDRITCH
    ░░▓▓░░              ██████              ░▒▓▒░▒               ▓░▒▓░▒
    Swarm               Brute Force         Map Control           Puppet Master
    
    Cheap hordes        Strong few          Stealth infiltration  Dominate enemies
    Raise the dead      Beginner-friendly   Best vs neutrals      Ritual summoning
    Weak tower tools    Loud & visible      Weak in PvP           Worst territory
    
    Avatar: Medium      Avatar: STRONGEST   Avatar: Weak          Avatar: WEAKEST
    Overlord: LOW       Overlord: Medium    Overlord: High        Overlord: HIGHEST
```

**Counter-play:** Undeath swarms Demonic -> Nature outpaces Undeath -> Eldritch bullies Nature -> Demonic smashes Eldritch

---

## Key Mechanics

| Mechanic | Summary |
|----------|---------|
| **Ambient Influence** | Territory + captured minor gems = your claim to Avatar control |
| **Minor Gems** | At settlements, temples, holy sites. Overlord clears, Avatar confirms capture |
| **Palantir** | Overlord watches Avatar in real-time. Avatar knows when being watched |
| **Mirror** | Send video messages to rival Overlords. Diegetic diplomacy |
| **Divine Intervention** | Total corruption stagnates → gods seal gems → everyone loses |
| **Astral Projection** | During boss fight, all rivals spectate and heckle |

---

## Match Shape

**~90 min average | ~2 hr max | 4 players | Hand-crafted map | Host authority P2P**

```
EARLY GAME              MID GAME                LATE GAME
Land grab.              Avatar fights.          Boss attempt.
Spread corruption.      Gems contested.         Corruption vs divine
Factions dig in.        Alliances form/break.   intervention race.
                        Hostile takeovers.
```

---

## System Pages

| System | Page | Build Status |
|--------|------|--------------|
| Avatar Combat | [avatar-combat.md](systems/avatar-combat.md) | Not started |
| Overlord Mode | [overlord-mode.md](systems/overlord-mode.md) | Not started |
| Faction Design | [faction-design.md](systems/faction-design.md) | Design done |
| Territory & Gems | [territory-control.md](systems/territory-control.md) | Not started |
| Boss Mechanics | [boss-mechanics.md](systems/boss-mechanics.md) | Not started |
| Multiplayer | [multiplayer.md](systems/multiplayer.md) | Foundation built |
| Progression & Loot | [progression-loot.md](systems/progression-loot.md) | Not started |

## Technical Pages

| Topic | Page | Build Status |
|-------|------|--------------|
| Project Structure | [project-structure.md](technical/project-structure.md) | Done |
| Networking Implementation | [networking.md](technical/networking.md) | Foundation built |
| Build Phases (MVP) | [build-phases.md](technical/build-phases.md) | Active |
