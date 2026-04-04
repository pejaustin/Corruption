# Progression & Loot

**Build status:** Not started

---

## Overview

How players grow stronger over the course of a match. Progression feeds into Avatar combat effectiveness and Overlord capabilities.

```
┌────────── PROGRESSION SOURCES ──────────┐
│                                          │
│  As Avatar:           As Overlord:       │
│  - Kill enemies       - Upgrade altar    │
│  - Loot drops         - Territory income │
│  - Clear dungeons     - Gem tap income   │
│  - Complete objectives                   │
│                                          │
│              │                │           │
│              ▼                ▼           │
│     ┌──────────────────────────────┐     │
│     │     PLAYER POWER LEVEL       │     │
│     │                              │     │
│     │  Avatar: gear + skills       │     │
│     │  Overlord: tower + minions   │     │
│     │  Corruption: influence       │     │
│     └──────────────────────────────┘     │
└──────────────────────────────────────────┘
```

## Open Design Questions

This is the least defined system. Key questions:

- Does Avatar progress persist when you lose control? (Levels, gear, skills)
- Is there a shared resource currency or separate Avatar/Overlord economies?
- How does loot work — random drops, fixed locations, crafting?
- What does the Avatar skill tree look like? Faction-specific?
- What tower upgrades are available and what do they cost?
- How does Overlord preparation translate to Avatar strength when you regain control?
