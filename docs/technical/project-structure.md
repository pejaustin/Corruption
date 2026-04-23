# Project Structure

**Build status:** Done

---

## Directory Layout

```
corruption/
├── addons/
│   ├── netfox/              # Rollback networking
│   ├── netfox.extras/       # Window tiler, etc.
│   ├── netfox.internals/
│   └── netfox.noray/        # NAT punchthrough
├── assets/
│   ├── characters/          # Player models, skins
│   ├── ui/                  # Fonts, icons, menu assets
│   └── world/env/           # Environment models, textures
├── data/
│   ├── abilities/           # AbilityData .tres (per Avatar ability)
│   ├── minions/             # MinionType .tres (skeleton, imp, guardian, corrupted_seraph, ...)
│   ├── rituals/             # RitualData .tres (domination_mastery, corruption_surge, eldritch_vision)
│   └── upgrades/            # UpgradeData .tres (minion_vitality, minion_ferocity, dark_tithe, avatar_fortitude, avatar_might)
├── docs/
│   ├── one-pager.md         # Game overview
│   ├── systems/             # System design pages
│   └── technical/           # Implementation notes
├── scenes/
│   ├── actors/
│   │   ├── minion/
│   │   │   ├── minion_actor.gd / .tscn     # MinionActor base scene
│   │   │   ├── minion_spawn_point.gd       # Tower-owned Marker3D where summons appear
│   │   │   ├── minion_rally_point.gd       # Owner-only rally flag (Marker3D)
│   │   │   ├── states/                     # idle / chase / attack / jump
│   │   │   └── types/                      # skeleton_actor.tscn, imp_actor.tscn, ...
│   │   └── enemy/                          # Neutral enemy actors
│   │       ├── guardian/                   # guardian_boss.tscn (Phase 1 boss)
│   │       └── seraph/                     # corrupted_seraph.tscn (inherits guardian_boss.tscn)
│   ├── abilities/                          # Ability effect scenes (one per ability)
│   ├── interactibles/                         # war_table.tscn (with Map child)
│   ├── menus/               # Main menu, lobby, enet menu, player panel
│   ├── network/             # Multiplayer manager, enet/noray network
│   ├── player/              # Player, camera, perspective manager
│   ├── test/                                  # Isolated test harnesses (war_table_test, fake_minion)
│   └── world/env/
│       ├── tower.gd / .tscn                # Tower — pairs its spawn point w/ a rally at runtime
│       ├── jumpable_link.gd                # NavigationLink3D subclass minions traverse by jumping
│       └── ...                             # Other env scenes (rocks, foliage)
├── scripts/
│   ├── abilities/           # AbilityEffect base + per-ability effect scripts
│   ├── interactibles/       # WarTable + WarTableMap + WarTableRange, GemSite, UpgradeAltar, RitualSite
│   ├── knowledge/           # KnowledgeManager autoload + WorldModel (per-peer battlefield belief)
│   ├── menus/               # Menu logic
│   ├── network/             # Network manager, connection configs
│   ├── states/movement/     # Player movement state machine
│   ├── test/                # FakeMinion + WarTableTestController (harness-only scripts)
│   ├── ability_data.gd      # AbilityData Resource class
│   ├── upgrade_data.gd      # UpgradeData Resource class
│   ├── ritual_data.gd       # RitualData Resource class
│   ├── minion_type.gd       # MinionType Resource class
│   ├── boss_manager.gd      # Two-phase boss sequencer
│   ├── game_constants.gd    # Factions, max players
│   ├── debug_overlay.gd     # F3 debug panel
│   ├── player.gd            # Player controller
│   ├── player_input.gd      # Input handling
│   └── camera_input.gd      # Camera control
├── shaders/
│   └── ps1+postprocess.gdshader
├── lobby.gd                 # Lobby with faction selection
└── project.godot            # "Corruption" — Godot 4.6
```

## Autoloads

| Name | Path | Purpose |
|------|------|---------|
| NetworkManager | `scripts/network/network_manager.gd` | Network selection, host/join, scene loading |
| WindowTiler | netfox.extras | Multi-window testing |
| Noray | netfox.noray | NAT punchthrough relay |
| PacketHandshake | netfox.noray | Connection handshake |
| NetworkTime | netfox | Synchronized time |
| NetworkTimeSynchronizer | netfox | Time sync |
| NetworkRollback | netfox | Rollback networking |
| NetworkEvents | netfox | Network event bus |
| NetworkPerformance | netfox | Performance monitoring |
| GameState | `scripts/game_state.gd` | Per-peer faction, upgrades, ritual buffs |
| DebugManager | `scripts/debug_manager.gd` | F2–F8 debug keys |
| InteractionUI | `scripts/interaction_ui.gd` | HUD prompt routing for Interactables |
| KnowledgeManager | `scripts/knowledge/knowledge_manager.gd` | Per-peer WorldModel; War Table reads belief from here. `INFINITE_BROADCAST_RANGE` / `INSTANT_COMMANDS` flags |

## Key Scenes

| Scene | Purpose |
|-------|---------|
| `tower_scene.tscn` | Main game scene (loaded as GAME_SCENE) |
| `player.tscn` | Multiplayer-spawned player character |
| `main_menu.tscn` | Entry point, host/join selection |
| `enet_menu.tscn` | ENet connection + lobby |
| `lobby.tscn` | Faction selection, player list |
| `debug_overlay.tscn` | F3 debug panel |
