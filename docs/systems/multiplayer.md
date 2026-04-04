# Multiplayer Architecture

**Build status:** Foundation built (lobby, ENet/Noray networking, player sync)

---

## Overview

4-player competitive multiplayer. Peer-to-peer with host authority.

```
┌──────────────────── NETWORK TOPOLOGY ────────────────────┐
│                                                           │
│              ┌───────────────┐                            │
│              │   HOST (P1)   │ ◄── Authoritative server  │
│              │   Validates   │     Also plays as P1       │
│              │   all state   │                            │
│              └───┬───┬───┬──┘                            │
│                  │   │   │                                │
│          ┌───────┘   │   └───────┐                       │
│          │           │           │                        │
│     ┌────▼──┐   ┌───▼───┐  ┌───▼────┐                  │
│     │  P2   │   │  P3   │  │  P4    │                   │
│     └───────┘   └───────┘  └────────┘                   │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

## Authority Model

**Full host authority.** The host validates all game state.

- Cheat resistance is critical for competitive PvP.
- Latency trade-off acceptable at 4-player scale.
- Host runs game simulation; clients send inputs, receive state.

## Sync Frequency

| Data | Frequency | Method |
|------|-----------|--------|
| Avatar position & combat | Every physics frame | High-frequency, rollback |
| Minion positions & commands | Medium | State sync |
| Resources, upgrades, timer | Low (every few seconds) | Reliable RPC |
| Diplomacy messages (Mirror) | Event-driven | Reliable RPC |
| Palantir video feed | Continuous when active | Viewport streaming |

## Match Flow

```
Main Menu → Host/Join → Lobby (faction select) → Game Scene → Win/Lose → Results
```

## Current Implementation

- **Godot 4.6** with netfox addon (rollback networking)
- **ENet** for LAN, **Noray** for NAT punchthrough with relay fallback
- **Lobby** with faction selection, player count, host start
- **Max 4 players** enforced at server creation
- **MultiplayerManager** handles player spawn/despawn on connect/disconnect
- **MultiplayerSpawner** for player scene replication

## Open Design Questions

- Host migration if host disconnects?
- Lobby-based only or random matchmaking later?
- How does Palantir video streaming work technically? (SubViewport → texture → RPC?)
- Mirror recordings — how are they transmitted? (Audio + viewport capture?)
- Anti-cheat beyond host authority?
