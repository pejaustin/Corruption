extends Control

@export var active_host_label: RichTextLabel

# Debug buttons — wired through scene connections in the editor.
@onready var _btn_spawn_dummy: Button = %BtnSpawnDummy
@onready var _btn_god_mode: Button = %BtnGodMode
@onready var _btn_kill_avatar: Button = %BtnKillAvatar
@onready var _btn_spawn_enemy: Button = %BtnSpawnEnemy
@onready var _btn_spawn_minion: Button = %BtnSpawnMinion
@onready var _btn_add_influence: Button = %BtnAddInfluence
@onready var _btn_cycle_faction: Button = %BtnCycleFaction
@onready var _btn_boost_corruption: Button = %BtnBoostCorruption
@onready var _btn_aggro_rings: Button = %BtnAggroRings
@onready var _btn_combat_boxes: Button = %BtnCombatBoxes

func _ready() -> void:
	visible = false

func open() -> void:
	active_host_label.text = NetworkManager.active_host_ip
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_set_gameplay_input(false)
	_refresh_button_states()

func close() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_set_gameplay_input(true)

func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("in-game-menu"):
		if visible:
			close()
		else:
			open()

func _set_gameplay_input(enabled: bool) -> void:
	# Two gameplay-input paths bypass the menu's focus/mouse state:
	#   1. PlayerInput / AvatarInput poll Input.is_action_pressed each tick.
	#   2. Interactables (war table, palantir, altar, summoning circle,
	#      mirror, base interact E) run their own _unhandled_input hooks.
	# Disabling process_mode on each Interactable halts its input callbacks
	# without touching the subclass scripts; the input flags cover poll-path.
	var scene := get_tree().current_scene
	if scene == null:
		return
	_toggle_inputs_under(scene, enabled)

func _toggle_inputs_under(node: Node, enabled: bool) -> void:
	if node is PlayerInput or node is AvatarInput:
		node.input_enabled = enabled
	elif node is Interactable:
		node.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_toggle_inputs_under(child, enabled)

func _refresh_button_states() -> void:
	# Host-only actions are disabled for clients so clicking them doesn't silently no-op.
	var is_host := multiplayer.is_server()
	if _btn_spawn_dummy:
		_btn_spawn_dummy.disabled = not is_host
	if _btn_kill_avatar:
		_btn_kill_avatar.disabled = not is_host
	if _btn_spawn_enemy:
		_btn_spawn_enemy.disabled = not is_host
	if _btn_spawn_minion:
		_btn_spawn_minion.disabled = not is_host
	if _btn_add_influence:
		_btn_add_influence.disabled = not is_host
	if _btn_cycle_faction:
		_btn_cycle_faction.disabled = not is_host
	if _btn_boost_corruption:
		_btn_boost_corruption.disabled = not is_host

func _on_resume_pressed() -> void:
	close()

func _on_main_menu_pressed() -> void:
	NetworkManager.disconnect_from_game()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_copy_ip_pressed() -> void:
	DisplayServer.clipboard_set(NetworkManager.active_host_ip)

# --- Debug button handlers ---
# One-shots auto-close the menu so the action happens in gameplay context
# (e.g. spawn-at-camera uses the current crosshair). Toggles stay open so
# you can flip multiple settings in one pause.

func _on_spawn_dummy_pressed() -> void:
	DebugManager.add_dummy_player()
	close()

func _on_god_mode_pressed() -> void:
	DebugManager.toggle_god_mode()

func _on_kill_avatar_pressed() -> void:
	DebugManager.kill_avatar()
	close()

func _on_spawn_enemy_pressed() -> void:
	DebugManager.spawn_enemy_at_camera()
	close()

func _on_spawn_minion_pressed() -> void:
	DebugManager.spawn_minion_at_camera()
	close()

func _on_add_influence_pressed() -> void:
	DebugManager.add_influence_to_self()
	close()

func _on_cycle_faction_pressed() -> void:
	DebugManager.cycle_faction()
	close()

func _on_boost_corruption_pressed() -> void:
	DebugManager.boost_corruption()
	close()

func _on_aggro_rings_pressed() -> void:
	DebugManager.toggle_aggro_rings()

func _on_combat_boxes_pressed() -> void:
	DebugManager.toggle_combat_boxes()
