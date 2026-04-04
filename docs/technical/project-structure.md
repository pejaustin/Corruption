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
├── docs/
│   ├── one-pager.md         # Game overview
│   ├── systems/             # System design pages
│   └── technical/           # Implementation notes
├── scenes/
│   ├── menus/               # Main menu, lobby, enet menu, player panel
│   ├── network/             # Multiplayer manager, enet/noray network
│   ├── player/              # Player, camera, perspective manager
│   └── world/env/           # Environment scenes (rocks, towers, etc.)
├── scripts/
│   ├── menus/               # Menu logic
│   ├── network/             # Network manager, connection configs
│   ├── states/movement/     # Player movement state machine
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

## Key Scenes

| Scene | Purpose |
|-------|---------|
| `tower_scene.tscn` | Main game scene (loaded as GAME_SCENE) |
| `player.tscn` | Multiplayer-spawned player character |
| `main_menu.tscn` | Entry point, host/join selection |
| `enet_menu.tscn` | ENet connection + lobby |
| `lobby.tscn` | Faction selection, player list |
| `debug_overlay.tscn` | F3 debug panel |
