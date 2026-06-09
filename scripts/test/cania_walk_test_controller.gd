extends Node3D

## Walkabout harness for the Cania world map. Instances the real
## cania_terrain.tscn and the real AvatarActor, and hands peer 1 control of
## the avatar standing at the map center — so movement, camera, animations,
## and terrain collision all run exactly as in the game.
##
## Networking is faked with OfflineMultiplayerPeer (single peer, id 1), same
## as war_table_test: NetworkTime is started so netfox input gathering and
## the rollback state machine tick locally without a lobby.
##
## Terrain collision comes from Terrain3D's default Dynamic/Game mode: shapes
## are built around the active camera at runtime, so the avatar lands on the
## heightmap instead of falling through. The avatar is dropped 2 m above the
## sampled ground height at spawn_xz.
##
## Hotkeys:
##   Esc — release/recapture the mouse
##   Shift+Esc — quit
##   (Q would normally recall the avatar; it no-ops here because GameState
##   has no registered avatar, so control can't be lost.)

const LOCAL_PEER_ID: int = 1
const SPAWN_HEIGHT_OFFSET: float = 2.0

@export var avatar: AvatarActor
## Root of the instanced terrain scene; the Terrain3D node is found beneath it.
@export var terrain_root: Node3D
## XZ drop point. The map's world rect is x -24576..25424, z -16384..10704,
## so the default is its exact center. Tweak to start somewhere else.
@export var spawn_xz: Vector2 = Vector2(424.0, -2840.0)

var _terrain: Terrain3D


func _enter_tree() -> void:
	# Must be set BEFORE any child _ready fires: AvatarInput/AvatarCamera
	# authority checks compare against multiplayer.get_unique_id(), which is 0
	# until a peer exists.
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _ready() -> void:
	assert(avatar, "Assign avatar in the inspector")
	assert(terrain_root, "Assign terrain_root in the inspector")
	var terrains: Array[Node] = terrain_root.find_children("*", "Terrain3D", true, false)
	assert(not terrains.is_empty(), "No Terrain3D node found under terrain_root")
	_terrain = terrains[0] as Terrain3D
	# Without the netfox tick loop, AvatarInput._gather never fires and WASD
	# does nothing. As the offline host (peer 1) start() returns synchronously.
	if NetworkTime.has_method("start"):
		NetworkTime.start()
	GameState.player_factions[LOCAL_PEER_ID] = GameConstants.Faction.UNDEATH
	# Let the terrain finish _ready (region load + collision setup) first.
	await get_tree().process_frame
	var ground: float = _terrain.data.get_height(Vector3(spawn_xz.x, 0.0, spawn_xz.y))
	if is_nan(ground):
		ground = 0.0
	avatar.global_position = Vector3(spawn_xz.x, ground + SPAWN_HEIGHT_OFFSET, spawn_xz.y)
	avatar.activate(LOCAL_PEER_ID)
	# Default camera far (4000) clips the horizon hard on a 50k-unit map.
	avatar.avatar_camera.camera_3d.far = 20000.0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("[CaniaWalkTest] spawned at %v (ground %.1f)" % [avatar.global_position, ground])


func _input(event: InputEvent) -> void:
	# This scene has no pause menu; without this the captured mouse traps the
	# user. Esc toggles capture, Shift+Esc quits.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if event.shift_pressed:
			get_tree().quit()
		else:
			var captured: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
