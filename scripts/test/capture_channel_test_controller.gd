extends Node3D

## Real-systems harness for the Gem / GemSite capture channel.
## Activates the shared AvatarActor for peer 1 immediately, places a Gem and a
## GemSite nearby, and lets you summon a hostile minion to interrupt channels.
##
## Networking is faked with OfflineMultiplayerPeer: multiplayer.get_unique_id()
## returns 1 and multiplayer.is_server() returns true, so host-authoritative
## paths (CaptureChannel, MinionManager, GemSite clear-check) run locally.
##
## Hotkeys (mirrored on the HUD):
##   1 — spawn a hostile Sprite (Nature/Fey) 4m in front of the Avatar
##   2 — force-clear the GemSite for UNDEATH (skips the minion-clear step)
##   3 — damage the Avatar 10 HP (tests damage interruption without AI)
##   K — despawn all enemies
##   R — reset: heal Avatar, clear enemies, reset GemSite to NEUTRAL
##
## Esc — release/recapture mouse.  Shift+Esc — quit.

const LOCAL_PEER_ID: int = 1
const SPAWN_ID_BASE: int = 10000

@export var avatar: AvatarActor
@export var gem: Node3D
@export var gem_site: GemSite
@export var minion_manager: MinionManager
@export var status_label: Label

var _next_spawn_id: int = SPAWN_ID_BASE

func _enter_tree() -> void:
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _ready() -> void:
	assert(avatar, "Assign avatar in the inspector")
	assert(gem, "Assign gem in the inspector")
	assert(gem_site, "Assign gem_site in the inspector")
	assert(minion_manager, "Assign minion_manager in the inspector")
	if NetworkTime.has_method("start"):
		NetworkTime.start()
	GameState.player_factions[LOCAL_PEER_ID] = GameConstants.Faction.UNDEATH
	# Global capture broadcast signal — surfaces on the HUD for now.
	GameState.capture_broadcast.connect(_on_capture_broadcast)
	# Wait a frame so MinionManager's deferred setup finishes before we possibly
	# spawn enemies, and so the Avatar's _ready has run before we activate it.
	await get_tree().process_frame
	avatar.activate(LOCAL_PEER_ID)
	# Auto-clear the GemSite so it's immediately channelable. Otherwise its
	# _on_interact bails on state != CLEARED and E appears to do nothing.
	# Press [2] after a reset to put it back into CLEARED.
	_force_clear_gem_site()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_refresh_status()

func _physics_process(_delta: float) -> void:
	_refresh_status()

# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var handled := true
		match event.keycode:
			KEY_1:
				_spawn_hostile_sprite()
			KEY_2:
				_force_clear_gem_site()
			KEY_3:
				_damage_avatar(10)
			KEY_K:
				_kill_all_enemies()
			KEY_R:
				_reset()
			_:
				handled = false
		if handled:
			_refresh_status()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if event.shift_pressed:
			get_tree().quit()
		else:
			var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()

# --- Handlers ---

func _spawn_hostile_sprite() -> void:
	# Spawn 4m in front of the avatar so it walks right over and attacks.
	var forward := -avatar.global_basis.z
	var pos := avatar.global_position + forward * 4.0
	pos.y = 0.0
	var id := _next_spawn_id
	_next_spawn_id += 1
	minion_manager._spawn_minion_rpc.rpc(id, -1, GameConstants.Faction.NATURE_FEY, pos, "sprite", pos)

func _force_clear_gem_site() -> void:
	if gem_site == null:
		return
	gem_site._set_cleared.rpc(GameConstants.Faction.UNDEATH, LOCAL_PEER_ID)

func _damage_avatar(amount: int) -> void:
	if avatar == null:
		return
	avatar.take_damage(amount)

func _kill_all_enemies() -> void:
	if minion_manager == null:
		return
	for m in minion_manager.get_all_minions():
		minion_manager.notify_minion_died(m)

func _reset() -> void:
	_kill_all_enemies()
	if avatar:
		avatar.hp = avatar.get_max_hp()
		avatar.hp_changed.emit(avatar.hp)
	if gem_site:
		gem_site.reset_site.rpc()
		_force_clear_gem_site()

func _on_capture_broadcast(peer_id: int, faction: int, duration: float) -> void:
	print("[Test] capture broadcast: peer %d faction %d duration %.1fs" % [peer_id, faction, duration])

# --- HUD ---

func _refresh_status() -> void:
	if status_label == null:
		return
	var hp_text := "%d / %d" % [avatar.hp, avatar.get_max_hp()] if avatar else "?"
	var channeling := ""
	if avatar and avatar.active_channel and avatar.active_channel.is_active():
		channeling = "  [CHANNELING %.0f%%]" % (avatar.active_channel.get_progress() * 100.0)
	var state_name := str(avatar._state_machine.state) if avatar else "?"
	var site_state := ""
	if gem_site:
		site_state = ["NEUTRAL", "CLEARED", "CAPTURED"][int(gem_site.state)]
	var enemy_count := 0
	if minion_manager:
		enemy_count = minion_manager.get_all_minions().size()
	status_label.text = "Capture Channel Test — real systems\n" \
		+ "You are peer %d (UNDEATH). HP: %s  State: %s%s\n" % [LOCAL_PEER_ID, hp_text, state_name, channeling] \
		+ "GemSite: %s   Enemies: %d\n" % [site_state, enemy_count] \
		+ "\n" \
		+ "Walk to the Gem or GemSite and press E to channel. Press E again to cancel.\n" \
		+ "\n" \
		+ "[1] spawn hostile Sprite in front of you\n" \
		+ "[2] force-clear the GemSite (skip minion-clear step)\n" \
		+ "[3] take 10 damage (tests channel interruption)\n" \
		+ "[K] despawn all enemies\n" \
		+ "[R] reset: heal, clear enemies, reset GemSite\n" \
		+ "[Esc] release/recapture mouse   [Shift+Esc] quit\n"
