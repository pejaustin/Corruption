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
             │(0-1 players)│                  │ (3-4 players) │
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
             │             │                  │ - Hold gem    │
             └──────┬──────┘                  │   sites       │
                    │                         │ - Sabotage    │
                    │                         │ - Diplomacy   │
                    │                         └───────┬───────┘
                    │                                  │
                    └────────────┬─────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │   AVATAR OWNERSHIP      │
                    │                         │
                    │ Claim: first E owns it  │
                    │ Q: release → AI drives  │
                    │ Killed by minions →     │
                    │   killer's owner takes  │
                    │ Killed by neutrals →    │
                    │   unowned, re-claimable │
                    │ Upkeep gauge empty →    │
                    │   neutral (planned)     │
                    └────────────┬────────────┘
                                 │
              ┌──────────────────▼──────────────────┐
              │           ENDGAME                    │
              │                                      │
              │  Avatar reaches Capitol → 2 bosses   │
              │  Bosses debuffed by total corruption  │
              │  Other players: astral spectators     │
              │  If Avatar dies → re-claim & retry    │
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
| **Avatar possession** | The Avatar is a claimable pawn — own it, possess it, or release it to AI; lose it to combat defeat or unpaid upkeep (upkeep escalates, faster on autopilot) |
| **Corruption** | THE currency: held gem sites bank it toward your ceiling; spend it on minions, upgrades, and Avatar upkeep; summed (current), it debuffs the bosses |
| **Minor Gems** | At settlements, temples, holy sites. Avatar captures freely unless hostiles contest the radius; sites never deplete |
| **Palantir** | Overlord watches Avatar in real-time. Avatar knows when being watched |
| **Mirror** | Send video messages to rival Overlords. Diegetic diplomacy |
| **Divine Intervention** | No gem site held for too long → gods seal gems → everyone loses |
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
| Avatar Combat | [avatar-combat.md](systems/avatar-combat.md) | Implemented (Tier 2) |
| Avatar Possession | [avatar-possession.md](systems/avatar-possession.md) | Phases A–C in; D (upkeep) planned |
| Overlord Mode | [overlord-mode.md](systems/overlord-mode.md) | Implemented (Tiers 1–3) |
| War Table & Knowledge | [war-table.md](systems/war-table.md) | Implemented, verified 2026-06-05 |
| Faction Design | [faction-design.md](systems/faction-design.md) | Scripts ready, untested |
| Corruption & Gems | [corruption-and-gems.md](systems/corruption-and-gems.md) | Implemented, untested |
| Boss Mechanics | [boss-mechanics.md](systems/boss-mechanics.md) | Guardian in; sequel needs editor setup |
| Multiplayer | [multiplayer.md](systems/multiplayer.md) | Implemented |
| Progression & Loot | [progression-loot.md](systems/progression-loot.md) | Not started |

## Technical Pages

| Topic | Page | Build Status |
|-------|------|--------------|
| Project Structure | [project-structure.md](technical/project-structure.md) | Done |
| Networking Implementation | [networking.md](technical/networking.md) | Foundation built |
| Path to MVP Roadmap | [mvp-roadmap.md](technical/mvp-roadmap.md) | **Active — start here** |
| Build Phases (tier history + test checklists) | [build-phases.md](technical/build-phases.md) | Reference |
