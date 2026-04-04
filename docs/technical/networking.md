# Networking Implementation

**Build status:** Foundation built

---

## Current State

### What's built
- [x] ENet peer-to-peer server/client
- [x] Noray NAT punchthrough with relay fallback
- [x] Lobby with faction selection and player sync
- [x] Max 4 player enforcement at server creation
- [x] MultiplayerManager: spawn/despawn players on connect/disconnect
- [x] MultiplayerSpawner for player scene replication
- [x] Loading screen for client connection
- [x] Disconnect handling and return to main menu
- [x] netfox rollback networking addon integrated

### What's needed next
- [ ] Avatar state sync (position, animation, combat) — high frequency
- [ ] Mode switch sync (which player is Avatar, who is Overlord)
- [ ] Minion state sync — medium frequency
- [ ] Territory/influence state sync — low frequency
- [ ] Palantir viewport streaming
- [ ] Mirror message delivery
- [ ] Host authority validation for game state changes

## Architecture Notes

### Network Manager (`network_manager.gd`)
Autoload singleton. Manages network selection (ENet vs Noray), host/join flow, scene transitions. Stores `is_hosting_game`, `active_host_ip`, `active_game_id`.

### Multiplayer Manager (`multiplayer_manager.gd`)
Lives in the game scene. Authority (host) only. Handles `peer_connected` / `peer_disconnected` signals, spawns/removes player scenes, positions players at spawn point.

### Game Constants (`game_constants.gd`)
`MAX_PLAYERS = 4`. Faction enum. Faction names and colors. Referenced by server creation and lobby.

### Connection Flow
```
Host: Main Menu → Host Game → ENet/Noray create_server → Lobby → Start → Game Scene
Join: Main Menu → Join Game → Enter IP/Port → ENet/Noray create_client → Game Scene
```
