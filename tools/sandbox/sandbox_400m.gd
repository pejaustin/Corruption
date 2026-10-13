extends Node

## A sandbox on the 400 m world that opens on its own: open
## tools/sandbox/sandbox_400m.tscn in the editor and press F6 (Run Current
## Scene), or run `godot --path . res://tools/sandbox/sandbox_400m.tscn`.
## You are an offline host (peer 1) in your tower, with no lobby; the pause menu's
## Debug panel (Esc) spawns units and enemies, gives you sites and the Paladin.
## The scene inherits world_400m.tscn, so the whole world is editable here; this
## node only sets up the offline host.

func _enter_tree() -> void:
	# Runs before any node in the world is ready: they read these as they start.
	NetworkManager.is_hosting_game = true
	GameState.world_size = MatchConfig.WorldSize.SMALL

func _ready() -> void:
	# The real game starts netfox's clock when a match begins.
	NetworkTime.start()

func _exit_tree() -> void:
	NetworkManager.is_hosting_game = false
	GameState.world_size = MatchConfig.WorldSize.NORMAL
