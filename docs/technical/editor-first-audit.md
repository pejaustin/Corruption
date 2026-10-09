# Editor-first audit

Austin's rule (2026-10-09): "Nodes should never need to be created from code unless they are explicitly a dynamic
asset, i.e. new troops being made from corpses." Rule and conventions: `CLAUDE.md` section 5.7.

Method: `rg -n '\.new\(' -g '*.gd' scripts scenes tools` (addons excluded) on the tree before the refactor
(commit `10d12cb`), 158 construction sites. Line numbers below are from that tree. Each site is classified and the
action taken. Sites that added `add_child` without `.new()` (reparenting, `instantiate()` of authored scenes,
`MultiplayerManager` adding players) were reviewed too; they only place existing or instanced nodes.

## Counts

| Class | Sites |
|---|---|
| (a) static, moved into a scene | 91 |
| (b) dynamic, now instances an authored scene | 24 |
| (c) data-only, stays in code | 21 |
| (d) tool or dev diagnostic, left alone | 22 |

## Sites

| file:line | what | class | action |
|---|---|---|---|
| `scenes/actors/actor.gd:192` | `Label3D.new()` | d | Kept: dev diagnostic label made only when a combat component is missing (commented in code); nothing to author |
| `scenes/actors/minion/minion_actor.gd:175` | `MeshInstance3D.new()` | a | AggroRing node now in minion_actor.tscn (%AggroRing) |
| `scenes/actors/minion/minion_actor.gd:198` | `ArrayMesh.new()` | c | Kept: ring line geometry from aggro_radius (ArrayMesh), commented |
| `scenes/actors/minion/minion_actor.gd:200` | `StandardMaterial3D.new()` | a | Ring material now local-to-scene sub_resource in minion_actor.tscn |
| `scenes/actors/minion/minion_actor.gd:250` | `MeshInstance3D.new()` | b | Overlay instanced from visual_range_overlay.tscn (couriers only) |
| `scenes/actors/minion/minion_actor.gd:255` | `SphereMesh.new()` | a | Sphere mesh and material authored in visual_range_overlay.tscn; script sets radius |
| `scenes/actors/minion/minion_actor.gd:260` | `StandardMaterial3D.new()` | a | Sphere mesh and material authored in visual_range_overlay.tscn; script sets radius |
| `scenes/actors/minion/minion_actor.gd:320` | `MeshInstance3D.new()` | a | CarryVisual box, mesh and material now in minion_actor.tscn (%CarryVisual), toggled |
| `scenes/actors/minion/minion_actor.gd:321` | `BoxMesh.new()` | a | CarryVisual box, mesh and material now in minion_actor.tscn (%CarryVisual), toggled |
| `scenes/actors/minion/minion_actor.gd:325` | `StandardMaterial3D.new()` | a | CarryVisual box, mesh and material now in minion_actor.tscn (%CarryVisual), toggled |
| `scenes/actors/player/avatar/avatar_actor.gd:89` | `AvatarAbilities.new()` | a | AvatarAbilities, PaladinHold, PaladinVoice are nodes in avatar_actor.tscn |
| `scenes/actors/player/avatar/avatar_actor.gd:93` | `PaladinHold.new()` | a | AvatarAbilities, PaladinHold, PaladinVoice are nodes in avatar_actor.tscn |
| `scenes/actors/player/avatar/avatar_actor.gd:96` | `PaladinVoice.new()` | a | AvatarAbilities, PaladinHold, PaladinVoice are nodes in avatar_actor.tscn |
| `scenes/actors/player/avatar/avatar_actor.gd:300` | `MeshInstance3D.new()` | b | Watcher orb instanced from watcher_orb.tscn, script tints it |
| `scenes/actors/player/avatar/avatar_actor.gd:303` | `SphereMesh.new()` | b | Watcher orb instanced from watcher_orb.tscn, script tints it |
| `scenes/actors/player/avatar/avatar_actor.gd:308` | `StandardMaterial3D.new()` | b | Watcher orb instanced from watcher_orb.tscn, script tints it |
| `scenes/actors/player/avatar/avatar_actor.gd:323` | `Label3D.new()` | a | ResistLabel now in avatar_actor.tscn (%ResistLabel) |
| `scenes/actors/player/avatar/paladin_voice.gd:56` | `AudioEffectCapture.new()` | c | Kept: AudioServer bus effect (not a node), commented |
| `scenes/actors/player/avatar/paladin_voice.gd:61` | `AudioStreamPlayer.new()` | a | Mic AudioStreamPlayer and microphone stream now child of PaladinVoice in avatar_actor.tscn |
| `scenes/actors/player/avatar/paladin_voice.gd:63` | `AudioStreamMicrophone.new()` | a | Mic AudioStreamPlayer and microphone stream now child of PaladinVoice in avatar_actor.tscn |
| `scenes/actors/player/avatar/paladin_voice.gd:112` | `AudioStreamPlayer.new()` | b | Per-speaker player instanced from paladin_voice_player.tscn |
| `scenes/actors/player/avatar/paladin_voice.gd:117` | `AudioStreamGenerator.new()` | c | Kept: AudioStreamGenerator resource at the sender rate (audio data) |
| `scenes/actors/player/overlord/overlord_actor.gd:95` | `MeshInstance3D.new()` | a | HeldScroll node, mesh and material now under the camera in overlord_actor.tscn, toggled |
| `scenes/actors/player/overlord/overlord_actor.gd:97` | `CylinderMesh.new()` | a | HeldScroll node, mesh and material now under the camera in overlord_actor.tscn, toggled |
| `scenes/actors/player/overlord/overlord_actor.gd:102` | `StandardMaterial3D.new()` | a | HeldScroll node, mesh and material now under the camera in overlord_actor.tscn, toggled |
| `scenes/map/map_floor.gd:62` | `Node3D.new()` | a | Routes/Markers/Pieces/Ink roots now in map_floor.tscn |
| `scenes/map/map_floor.gd:494` | `MeshInstance3D.new()` | b | Draft line is a map_line_pencil.tscn instance in map_floor.tscn; route/ink ribbons instance map_line_route.tscn / map_line.tscn; ImmediateMesh is local-to-scene, refilled each frame (c) |
| `scenes/map/map_floor.gd:495` | `ImmediateMesh.new()` | b | Draft line is a map_line_pencil.tscn instance in map_floor.tscn; route/ink ribbons instance map_line_route.tscn / map_line.tscn; ImmediateMesh is local-to-scene, refilled each frame (c) |
| `scenes/map/map_floor.gd:496` | `StandardMaterial3D.new()` | b | Draft line is a map_line_pencil.tscn instance in map_floor.tscn; route/ink ribbons instance map_line_route.tscn / map_line.tscn; ImmediateMesh is local-to-scene, refilled each frame (c) |
| `scenes/map/map_floor.gd:534` | `MeshInstance3D.new()` | a | Illustration plane, mesh and material now in map_floor.tscn; script paints the generated texture |
| `scenes/map/map_floor.gd:536` | `PlaneMesh.new()` | a | Illustration plane, mesh and material now in map_floor.tscn; script paints the generated texture |
| `scenes/map/map_floor.gd:540` | `StandardMaterial3D.new()` | a | Illustration plane, mesh and material now in map_floor.tscn; script paints the generated texture |
| `scenes/map/map_piece.gd:29` | `MapPiece.new()` | b | create() instantiates map_piece.tscn (map_piece_avatar.tscn for the Paladin) |
| `scenes/map/map_piece.gd:39` | `CollisionShape3D.new()` | a | Collision, meshes, material and label authored in map_piece.tscn |
| `scenes/map/map_piece.gd:40` | `CylinderShape3D.new()` | a | Collision, meshes, material and label authored in map_piece.tscn |
| `scenes/map/map_piece.gd:46` | `StandardMaterial3D.new()` | a | Collision, meshes, material and label authored in map_piece.tscn |
| `scenes/map/map_piece.gd:47` | `MeshInstance3D.new()` | a | Collision, meshes, material and label authored in map_piece.tscn |
| `scenes/map/map_piece.gd:48` | `CylinderMesh.new()` | a | Collision, meshes, material and label authored in map_piece.tscn |
| `scenes/map/map_piece.gd:56` | `MeshInstance3D.new()` | a | Collision, meshes, material and label authored in map_piece.tscn |
| `scenes/map/map_piece.gd:57` | `SphereMesh.new()` | a | Collision, meshes, material and label authored in map_piece.tscn |
| `scenes/map/map_piece.gd:64` | `Label3D.new()` | a | Collision, meshes, material and label authored in map_piece.tscn |
| `scenes/map/map_point_marker.gd:12` | `MapPointMarker.new()` | b | create() instantiates map_point_marker.tscn |
| `scenes/map/map_point_marker.gd:19` | `CollisionShape3D.new()` | a | Collision, disc, material and label authored in map_point_marker.tscn |
| `scenes/map/map_point_marker.gd:20` | `CylinderShape3D.new()` | a | Collision, disc, material and label authored in map_point_marker.tscn |
| `scenes/map/map_point_marker.gd:25` | `MeshInstance3D.new()` | a | Collision, disc, material and label authored in map_point_marker.tscn |
| `scenes/map/map_point_marker.gd:26` | `CylinderMesh.new()` | a | Collision, disc, material and label authored in map_point_marker.tscn |
| `scenes/map/map_point_marker.gd:31` | `StandardMaterial3D.new()` | a | Collision, disc, material and label authored in map_point_marker.tscn |
| `scenes/map/map_point_marker.gd:35` | `Label3D.new()` | a | Collision, disc, material and label authored in map_point_marker.tscn |
| `scenes/menus/player_panel.gd:75` | `StyleBoxFlat.new()` | a | Panel StyleBoxFlat is the scene sub_resource (local-to-scene); script only sets the seat tint |
| `scenes/sites/corruption_site.gd:249` | `MeshInstance3D.new()` | a | Base, Pillar, Beacon, meshes and materials now in corruption_site.tscn |
| `scenes/sites/corruption_site.gd:251` | `CylinderMesh.new()` | a | Base, Pillar, Beacon, meshes and materials now in corruption_site.tscn |
| `scenes/sites/corruption_site.gd:258` | `MeshInstance3D.new()` | a | Base, Pillar, Beacon, meshes and materials now in corruption_site.tscn |
| `scenes/sites/corruption_site.gd:260` | `PrismMesh.new()` | a | Base, Pillar, Beacon, meshes and materials now in corruption_site.tscn |
| `scenes/sites/corruption_site.gd:264` | `StandardMaterial3D.new()` | a | Base, Pillar, Beacon, meshes and materials now in corruption_site.tscn |
| `scenes/sites/corruption_site.gd:269` | `MeshInstance3D.new()` | a | Base, Pillar, Beacon, meshes and materials now in corruption_site.tscn |
| `scenes/sites/corruption_site.gd:271` | `CylinderMesh.new()` | a | Base, Pillar, Beacon, meshes and materials now in corruption_site.tscn |
| `scenes/sites/corruption_site.gd:277` | `StandardMaterial3D.new()` | a | Base, Pillar, Beacon, meshes and materials now in corruption_site.tscn |
| `scenes/ui/advisor_dialogue.gd:27` | `AdvisorDialogue.new()` | b | get_instance() instantiates advisor_dialogue.tscn |
| `scenes/ui/advisor_dialogue.gd:34` | `Label.new()` | a | Subtitle, panel, question, options box authored in advisor_dialogue.tscn |
| `scenes/ui/advisor_dialogue.gd:46` | `PanelContainer.new()` | a | Subtitle, panel, question, options box authored in advisor_dialogue.tscn |
| `scenes/ui/advisor_dialogue.gd:53` | `VBoxContainer.new()` | a | Subtitle, panel, question, options box authored in advisor_dialogue.tscn |
| `scenes/ui/advisor_dialogue.gd:55` | `Label.new()` | a | Subtitle, panel, question, options box authored in advisor_dialogue.tscn |
| `scenes/ui/advisor_dialogue.gd:58` | `VBoxContainer.new()` | a | Subtitle, panel, question, options box authored in advisor_dialogue.tscn |
| `scenes/ui/advisor_dialogue.gd:93` | `Button.new()` | b | One answer button instanced from advisor_option_button.tscn |
| `scenes/ui/avatar_hud.gd:72` | `ProgressBar.new()` | a | HoldBar and HoldLabel now in avatar_hud.tscn |
| `scenes/ui/avatar_hud.gd:86` | `Label.new()` | a | HoldBar and HoldLabel now in avatar_hud.tscn |
| `scenes/world/places/body.gd:12` | `MeshInstance3D.new()` | a | Slab authored in body.tscn; MinionManager instances it (b) |
| `scenes/world/places/body.gd:13` | `BoxMesh.new()` | a | Slab authored in body.tscn; MinionManager instances it (b) |
| `scenes/world/places/body.gd:17` | `StandardMaterial3D.new()` | a | Slab authored in body.tscn; MinionManager instances it (b) |
| `scenes/world/places/holy_site.gd:230` | `MeshInstance3D.new()` | a | Disc authored in holy_site.tscn (script fits it to radius); world.tscn instances the scene |
| `scenes/world/places/holy_site.gd:231` | `CylinderMesh.new()` | a | Disc authored in holy_site.tscn (script fits it to radius); world.tscn instances the scene |
| `scenes/world/places/holy_site.gd:236` | `StandardMaterial3D.new()` | a | Disc authored in holy_site.tscn (script fits it to radius); world.tscn instances the scene |
| `scenes/world/places/relic_place.gd:53` | `MeshInstance3D.new()` | a | Gem authored in relic_place.tscn; world.tscn instances the scene |
| `scenes/world/places/relic_place.gd:54` | `SphereMesh.new()` | a | Gem authored in relic_place.tscn; world.tscn instances the scene |
| `scenes/world/places/relic_place.gd:58` | `StandardMaterial3D.new()` | a | Gem authored in relic_place.tscn; world.tscn instances the scene |
| `scenes/world/places/resource_site.gd:80` | `MeshInstance3D.new()` | a | Crate stack authored in resource_site.tscn; world.tscn instances the scene |
| `scenes/world/places/resource_site.gd:81` | `BoxMesh.new()` | a | Crate stack authored in resource_site.tscn; world.tscn instances the scene |
| `scenes/world/places/resource_site.gd:84` | `StandardMaterial3D.new()` | a | Crate stack authored in resource_site.tscn; world.tscn instances the scene |
| `scripts/build/balance_csv.gd:179` | `script.new()` | d | Tool: editor build script; allowed to build nodes |
| `scripts/build/build_azgaar_terrain.gd:181` | `Node3D.new()` | d | Tool: editor build script; allowed to build nodes |
| `scripts/build/build_azgaar_terrain.gd:183` | `Terrain3D.new()` | d | Tool: editor build script; allowed to build nodes |
| `scripts/build/build_azgaar_terrain.gd:192` | `PackedScene.new()` | d | Tool: editor build script; allowed to build nodes |
| `scripts/combat/combat_box_debug.gd:63` | `MeshInstance3D.new()` | d | Kept: debug overlay mirroring each authored hit/hurt shape at runtime (F-key toggle); flag for Austin |
| `scripts/combat/combat_box_debug.gd:67` | `StandardMaterial3D.new()` | d | Kept: debug overlay mirroring each authored hit/hurt shape at runtime (F-key toggle); flag for Austin |
| `scripts/combat/combat_box_debug.gd:81` | `SphereMesh.new()` | d | Kept: debug overlay mirroring each authored hit/hurt shape at runtime (F-key toggle); flag for Austin |
| `scripts/combat/combat_box_debug.gd:87` | `BoxMesh.new()` | d | Kept: debug overlay mirroring each authored hit/hurt shape at runtime (F-key toggle); flag for Austin |
| `scripts/combat/combat_box_debug.gd:92` | `CapsuleMesh.new()` | d | Kept: debug overlay mirroring each authored hit/hurt shape at runtime (F-key toggle); flag for Austin |
| `scripts/combat/combat_box_debug.gd:98` | `CylinderMesh.new()` | d | Kept: debug overlay mirroring each authored hit/hurt shape at runtime (F-key toggle); flag for Austin |
| `scripts/game_state.gd:205` | `MirrorMessage.new()` | c | Data-only: MirrorMessage is a Resource |
| `scripts/groups/group_manager.gd:118` | `UnitGroup.new()` | c | Data-only: UnitGroup is not a Node |
| `scripts/interactibles/balcony.gd:117` | `Node3D.new()` | a | LookoutPivot/Pitch/Camera now in balcony.tscn |
| `scripts/interactibles/balcony.gd:121` | `Node3D.new()` | a | LookoutPivot/Pitch/Camera now in balcony.tscn |
| `scripts/interactibles/balcony.gd:124` | `Camera3D.new()` | a | LookoutPivot/Pitch/Camera now in balcony.tscn |
| `scripts/interactibles/desk.gd:181` | `CanvasLayer.new()` | a | Book layer, panel, stylebox, tabs row, scroll, body authored in desk.tscn |
| `scripts/interactibles/desk.gd:184` | `PanelContainer.new()` | a | Book layer, panel, stylebox, tabs row, scroll, body authored in desk.tscn |
| `scripts/interactibles/desk.gd:185` | `StyleBoxFlat.new()` | a | Book layer, panel, stylebox, tabs row, scroll, body authored in desk.tscn |
| `scripts/interactibles/desk.gd:197` | `VBoxContainer.new()` | a | Book layer, panel, stylebox, tabs row, scroll, body authored in desk.tscn |
| `scripts/interactibles/desk.gd:200` | `HBoxContainer.new()` | a | Book layer, panel, stylebox, tabs row, scroll, body authored in desk.tscn |
| `scripts/interactibles/desk.gd:203` | `ScrollContainer.new()` | a | Book layer, panel, stylebox, tabs row, scroll, body authored in desk.tscn |
| `scripts/interactibles/desk.gd:207` | `VBoxContainer.new()` | a | Book layer, panel, stylebox, tabs row, scroll, body authored in desk.tscn |
| `scripts/interactibles/desk.gd:235` | `Button.new()` | b | Tab per page instanced from desk_tab_button.tscn |
| `scripts/interactibles/desk.gd:243` | `StyleBoxFlat.new()` | b | Tab per page instanced from desk_tab_button.tscn |
| `scripts/interactibles/desk.gd:262` | `VBoxContainer.new()` | b | Entry per record instanced from desk_entry.tscn |
| `scripts/interactibles/desk.gd:272` | `TextEdit.new()` | a | Notes TextEdit, its styles and labels authored in desk.tscn / desk_entry.tscn |
| `scripts/interactibles/desk.gd:280` | `StyleBoxFlat.new()` | a | Notes TextEdit, its styles and labels authored in desk.tscn / desk_entry.tscn |
| `scripts/interactibles/desk.gd:289` | `Label.new()` | a | Notes TextEdit, its styles and labels authored in desk.tscn / desk_entry.tscn |
| `scripts/interactibles/ledger.gd:165` | `CanvasLayer.new()` | a | Layer, panel, stylebox, body authored in ledger.tscn |
| `scripts/interactibles/ledger.gd:168` | `PanelContainer.new()` | a | Layer, panel, stylebox, body authored in ledger.tscn |
| `scripts/interactibles/ledger.gd:169` | `StyleBoxFlat.new()` | a | Layer, panel, stylebox, body authored in ledger.tscn |
| `scripts/interactibles/ledger.gd:181` | `VBoxContainer.new()` | a | Layer, panel, stylebox, body authored in ledger.tscn |
| `scripts/interactibles/ledger.gd:186` | `Label.new()` | b | Line per report instanced from ledger_line.tscn |
| `scripts/interactibles/mirror.gd:161` | `AudioEffectReverb.new()` | c | Kept: shared MirrorMic AudioServer bus effects (not nodes), commented |
| `scripts/interactibles/mirror.gd:167` | `AudioEffectCapture.new()` | c | Kept: shared MirrorMic AudioServer bus effects (not nodes), commented |
| `scripts/interactibles/mirror.gd:171` | `AudioStreamPlayer.new()` | a | MicPlayer and PlaybackPlayer now in mirror.tscn |
| `scripts/interactibles/mirror.gd:172` | `AudioStreamMicrophone.new()` | a | MicPlayer and PlaybackPlayer now in mirror.tscn |
| `scripts/interactibles/mirror.gd:176` | `AudioStreamPlayer.new()` | a | MicPlayer and PlaybackPlayer now in mirror.tscn |
| `scripts/interactibles/mirror.gd:182` | `StandardMaterial3D.new()` | a | RingGlow, RingLight, ChimePlayer, quad and material now under Mirror3D in mirror.tscn |
| `scripts/interactibles/mirror.gd:187` | `QuadMesh.new()` | a | RingGlow, RingLight, ChimePlayer, quad and material now under Mirror3D in mirror.tscn |
| `scripts/interactibles/mirror.gd:189` | `MeshInstance3D.new()` | a | RingGlow, RingLight, ChimePlayer, quad and material now under Mirror3D in mirror.tscn |
| `scripts/interactibles/mirror.gd:193` | `OmniLight3D.new()` | a | RingGlow, RingLight, ChimePlayer, quad and material now under Mirror3D in mirror.tscn |
| `scripts/interactibles/mirror.gd:198` | `AudioStreamPlayer3D.new()` | a | RingGlow, RingLight, ChimePlayer, quad and material now under Mirror3D in mirror.tscn |
| `scripts/interactibles/mirror.gd:217` | `AudioStreamWAV.new()` | c | Kept: synthesized chime waveform (AudioStreamWAV data) |
| `scripts/interactibles/mirror.gd:526` | `AudioStreamGenerator.new()` | c | Kept: AudioStreamGenerator / MirrorMessage data |
| `scripts/interactibles/mirror.gd:561` | `MirrorMessage.new()` | c | Kept: AudioStreamGenerator / MirrorMessage data |
| `scripts/interactibles/mirror.gd:718` | `AudioStreamGenerator.new()` | c | Kept: AudioStreamGenerator / MirrorMessage data |
| `scripts/interactibles/palantir.gd:131` | `Node3D.new()` | b | Scry rig instanced from scry_rig.tscn when someone looks in |
| `scripts/interactibles/palantir.gd:133` | `Node3D.new()` | b | Scry rig instanced from scry_rig.tscn when someone looks in |
| `scripts/interactibles/palantir.gd:136` | `Camera3D.new()` | b | Scry rig instanced from scry_rig.tscn when someone looks in |
| `scripts/interactibles/treasure_room.gd:72` | `MultiMesh.new()` | b | MultiMesh replaced by a crate.tscn instance per good (capped), under Crates in treasure_room.tscn |
| `scripts/interactibles/treasure_room.gd:74` | `BoxMesh.new()` | b | MultiMesh replaced by a crate.tscn instance per good (capped), under Crates in treasure_room.tscn |
| `scripts/interactibles/treasure_room.gd:87` | `MultiMeshInstance3D.new()` | b | MultiMesh replaced by a crate.tscn instance per good (capped), under Crates in treasure_room.tscn |
| `scripts/interactibles/treasure_room.gd:90` | `StandardMaterial3D.new()` | b | MultiMesh replaced by a crate.tscn instance per good (capped), under Crates in treasure_room.tscn |
| `scripts/interactibles/treasure_room.gd:94` | `Label3D.new()` | a | Plaque now in treasure_room.tscn |
| `scripts/knowledge/knowledge_manager.gd:54` | `WorldModel.new()` | c | Data-only: WorldModel is not a Node |
| `scripts/menus/lobby.gd:378` | `OptionButton.new()` | a | PaceSelector and PaceLabel now in lobby.tscn |
| `scripts/menus/lobby.gd:386` | `Label.new()` | a | PaceSelector and PaceLabel now in lobby.tscn |
| `scripts/menus/main_menu.gd:14` | `NetworkConnectionConfigs.new()` | c | Data-only: NetworkConnectionConfigs is a RefCounted |
| `scripts/menus/main_menu.gd:26` | `NetworkConnectionConfigs.new()` | c | Data-only: NetworkConnectionConfigs is a RefCounted |
| `scripts/menus/main_menu.gd:35` | `NetworkConnectionConfigs.new()` | c | Data-only: NetworkConnectionConfigs is a RefCounted |
| `scripts/minion_manager.gd:56` | `Node3D.new()` | a | World/Minions container now in world.tscn (minions_root export) |
| `scripts/minion_manager.gd:453` | `Body.new()` | b | Body instanced from body.tscn (body_scene export): dynamic, bodies left by dead humans |
| `scripts/network/enet_network.gd:22` | `ENetMultiplayerPeer.new()` | c | Data-only: ENet/UPNP/Thread network objects, not nodes |
| `scripts/network/enet_network.gd:33` | `Thread.new()` | c | Data-only: ENet/UPNP/Thread network objects, not nodes |
| `scripts/network/enet_network.gd:37` | `UPNP.new()` | c | Data-only: ENet/UPNP/Thread network objects, not nodes |
| `scripts/network/enet_network.gd:69` | `UPNP.new()` | c | Data-only: ENet/UPNP/Thread network objects, not nodes |
| `scripts/network/enet_network.gd:77` | `ENetMultiplayerPeer.new()` | c | Data-only: ENet/UPNP/Thread network objects, not nodes |
| `scripts/test/cania_walk_test_controller.gd:41` | `OfflineMultiplayerPeer.new()` | d | Tool: walk-test harness |
| `scripts/world_nav_baker.gd:41` | `NavigationMeshSourceGeometryData3D.new()` | c | Data-only: navmesh source geometry |
| `tools/playtest/input_driver.gd:50` | `InputEventAction.new()` | d | Tool: tests, playtest driver, shot rig |
| `tools/playtest/input_driver.gd:82` | `InputEventKey.new()` | d | Tool: tests, playtest driver, shot rig |
| `tools/playtest/input_driver.gd:93` | `InputEventMouseButton.new()` | d | Tool: tests, playtest driver, shot rig |
| `tools/playtest/input_driver.gd:101` | `InputEventMouseMotion.new()` | d | Tool: tests, playtest driver, shot rig |
| `tools/playtest/playtest_order.gd:41` | `Driver.new()` | d | Tool: tests, playtest driver, shot rig |
| `tools/shots/shot.gd:33` | `Camera3D.new()` | d | Tool: tests, playtest driver, shot rig |
| `tools/tests/test_endgame.gd:36` | `Marker3D.new()` | d | Tool: tests, playtest driver, shot rig |
| `tools/tests/test_mirror.gd:24` | `RandomNumberGenerator.new()` | d | Tool: tests, playtest driver, shot rig |
| `tools/tests/test_mirror.gd:50` | `MirrorMessage.new()` | d | Tool: tests, playtest driver, shot rig |
| `tools/tests/test_orders.gd:127` | `WorldModel.new()` | d | Tool: tests, playtest driver, shot rig |

## Left in code, and why

- **Data-only (c):** `MirrorMessage`, `WorldModel`, `UnitGroup`, `NetworkConnectionConfigs` (not nodes);
  the `Image`/`ImageTexture` map illustration generated from terrain heights (`map_floor.gd`); the `ImmediateMesh`
  ribbons refilled from route points (the mesh and its MeshInstance3D are authored in `map_line*.tscn`);
  the aggro ring's `ArrayMesh` (circle from `aggro_radius`; the node and material are authored);
  `AudioStreamGenerator`, the synthesized chime and the `AudioServer` buses `MirrorMic` / `PaladinMic`
  (the players that use them are authored); ENet/UPNP network objects; navmesh source geometry.
- **Debug (d):** `CombatBoxDebug` builds a translucent mesh per authored collision shape on hit and hurt boxes
  when the debug toggle is on. It mirrors shapes that are already authored, so there is nothing to author by hand;
  say so if you would rather it use Godot's built-in "Visible Collision Shapes".
  The missing-component warning in `actor.gd` is a dev diagnostic that only exists when a scene is broken.
- **Tools:** `scripts/build/`, `scripts/test/`, `tools/` (tests, input driver, shot rig).

## Notes for editing the new scenes

- Per-instance tints (site pillar and beacon, markers, pieces, watcher orbs, aggro ring, carry box) use
  `resource_local_to_scene` materials, so one instance's colour never leaks into another.
- Scenes that set a Node-typed `@export` in a hand-written `.tscn` need `node_paths=PackedStringArray(...)` on the node
  line (`MinionManager.minions_root`), or the export loads null.
- All new art is placeholder and marked `PLACEHOLDER:` in the scene files; looks are unchanged from the code-built ones.
