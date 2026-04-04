# Overlord Mode

**Build status:** Not started

---

## Overview

When you're not the Avatar, you're in your tower — a first-person 3D space where you command your forces, spy on rivals, and scheme. Three players are always in Overlord mode simultaneously.

```
┌─────────────────────────── TOWER INTERIOR ──────────────────────────┐
│                                                                      │
│                          ┌──────────┐                                │
│                          │ PALANTIR │ ◄── Scrying orb               │
│                          │          │     Watch Avatar in real-time  │
│                          │  (they   │     But they KNOW you watch   │
│                          │   know)  │                                │
│                          └──────────┘                                │
│                                                                      │
│   ┌──────────┐                              ┌──────────┐            │
│   │  MIRROR  │                              │ BALCONY  │            │
│   │          │ ◄── Record & send            │          │ ◄── Walk  │
│   │ Diplomacy│     video messages           │ Overlook │    out &  │
│   │          │     to rival Overlords       │          │    see the │
│   └──────────┘                              │          │    world   │
│                                             └──────────┘            │
│                                                                      │
│   ┌──────────┐                              ┌──────────┐            │
│   │ SUMMONING│                              │ UPGRADE  │            │
│   │ CIRCLE   │ ◄── Spawn minions            │ ALTAR    │ ◄── Tower │
│   │          │     Deploy to map             │          │    and    │
│   └──────────┘                              │          │    Avatar  │
│                                             │          │    upgrades│
│                                             └──────────┘            │
└──────────────────────────────────────────────────────────────────────┘
```

## Core Interactibles

### Palantir (Scrying Orb)
- Walk up and interact to activate a live view of the current Avatar.
- The Avatar player receives a visual/audio cue that they are being watched (and by how many).
- You can see what the Avatar sees, where they are, what they're fighting.
- Information is power — but surveillance has a cost (the Avatar knows to be careful).

### Mirror (Diplomacy)
- Stand in front of the Mirror to record a video message to one or more rival Overlords.
- Recipients get a notification and can choose to watch.
- Enables alliance proposals, threats, deals, betrayals — all diegetic.
- Messages are one-way recordings, not real-time calls.

### Balcony (World Overlook)
- Walk out to the tower balcony and physically look down at the world below.
- Direct observation — no UI overlay, you see a scaled-down version of the map from your tower's vantage point.
- From here you can observe Avatar movement, minion positions, and territory changes in real-time.
- Later tiers add minion command from the balcony (point and direct).
- Visibility is faction-dependent (Nature/Fey sees most, others see less).

### Summoning Circle (Minion Spawn)
- Spend resources to spawn minions.
- Minions deploy to the map from your tower's location.
- Faction-specific minion roster.

### Upgrade Altar
- Spend resources on tower upgrades and Avatar ability preparation.
- Invest in your next Avatar turn so you're stronger when control comes.

## Faction Overlord Differences

| Faction | Overlord Strength | Unique Tools |
|---------|------------------|--------------|
| Undeath | Low complexity | Cheap mass spawning, raise-dead aura around territory |
| Demonic | Medium, straightforward | Strong individual minion commands, visible on war table |
| Nature/Fey | High, information advantage | Best war table visibility, territory spread tools |
| Eldritch | Highest, puppet master | Dominate enemy minions/NPCs remotely, best sabotage |

## Open Design Questions

- Is the tower a fully modeled 3D room you walk around in, or more stylized/abstract?
- How does the War Table render the map — miniature 3D? 2D top-down? Fog of war?
- What resources are spent on minions and upgrades? One currency or multiple?
- Can Overlords directly attack each other's towers, or only via minions?
- What are the Palantir's limitations? Cooldown? Duration? Can you watch other Overlords or only the Avatar?
