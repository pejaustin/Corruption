# Corruption — Claude Code Project Guide

## What is this?

A 4-player PvP Dark Lord simulator built in Godot 4.6 with GDScript. One player controls a Souls-like Avatar (3rd person) while three others scheme as Overlords from towers (1st person). See `docs/one-pager.md` for the full game overview.

## Documentation Structure

- `docs/one-pager.md` — Visual summary of the entire game
- `docs/systems/` — One page per major system (combat, overlord mode, factions, territory, bosses, multiplayer, progression)
- `docs/technical/` — Implementation notes and build phases
- `docs/technical/build-phases.md` — **MVP tier tracker with current progress** (start here for what to build next)
- `docs/Corruption_GDD_v0.1.md` — Original GDD (reference, superseded by modular docs)

## Key Architecture

- **Networking:** Godot ENet P2P with host authority, using netfox addon for rollback
- **Player scene:** `scenes/player/player.tscn` — CharacterBody3D with movement state machine, rollback sync, PerspectiveManager
- **Game scene:** `scenes/tower_scene.tscn` — The main game scene (loaded as GAME_SCENE despite the name)
- **Autoloads:** NetworkManager, DebugManager, plus netfox autoloads (NetworkTime, NetworkRollback, etc.)
- **Game constants:** `scripts/game_constants.gd` — Factions enum, MAX_PLAYERS, faction names/colors

## Build & Run

Open `project.godot` in Godot Editor, press F5. Use Godot's multi-instance debug for multiplayer testing.

### Debug Tools
- **F2** — Spawn dummy player (fills next empty tower slot, up to 4 total)
- **F3** — Toggle debug overlay (network info, players, factions, FPS)

## Current State (Tier 0: The Board is Set)

Players connect via lobby with faction selection. All spawn as 1st-person Overlords distributed across 4 towers. Dummy players can fill empty slots for solo testing.

### What's built
- P2P lobby with faction selection (4 factions: Undeath, Demonic, Nature/Fey, Eldritch)
- Max 4 player enforcement (ENet + Noray)
- Players spawn in separate towers
- 1st-person movement with rollback networking
- Dummy player system for solo testing
- Debug overlay

### What's next (Tier 0 remaining)
See `docs/technical/build-phases.md` for full details. Summary:
- Avatar 3rd-person mode (camera behind character)
- Avatar claim interactible in tower (first to interact becomes Avatar)
- Mode switch (1st-person tower → 3rd-person world)
- Avatar movement visible to all clients
- The gem (interactible at map center, touch to win)
- Match flow (win screen → back to lobby)

## Conventions

- GDScript with tabs for indentation
- Scenes in `scenes/`, scripts in `scripts/`, mirroring directory structure
- Player authority set via node name matching peer ID
- Netfox rollback: state properties synced via RollbackSynchronizer, input gathered in `before_tick_loop`
