extends Node

## Tracks global game state: who is the Avatar, corruption, win condition.
## Autoload singleton.

signal avatar_changed(old_peer_id: int, new_peer_id: int)
signal avatar_owner_changed(old_peer_id: int, new_peer_id: int)
signal game_won(peer_id: int)
signal game_lost
signal watcher_count_changed(count: int)
signal watcher_positions_changed()
signal corruption_changed(peer_id: int, new_value: float)
## Fired on every peer when a gem capture starts (CaptureChannel.broadcast=true).
## Listen here for global reactions (storm cue, HUD banner, audio sting).
signal capture_broadcast(peer_id: int, faction: int, duration: float)

# The Avatar is a minion that can be optionally controlled directly by the
# player with power over it (docs/systems/avatar-possession.md): ownership
# (whose pawn it is) and control (who is driving right now) are separate.
# It starts the match neutral and unowned; the first claim owns it, Q releases
# control but keeps ownership, and ownership moves only via defeat (or the
# Phase D upkeep gauge).
# CONTROLLER: -1 = no one is driving it (AI drives while owned).
var avatar_peer_id: int = -1
# OWNER: which peer owns the Avatar as their pawn. -1 = neutral/unowned.
var avatar_owner_peer_id: int = -1
# How many Overlords are scrying the Avatar right now
var watcher_count: int = 0
# peer_id -> global camera position of each active scryer
var watcher_positions: Dictionary[int, Vector3] = {}
# peer_id -> corruption score (float). Earned only from held gem sites; the
# per-player claim to the Avatar AND (summed) the global boss-debuff pool.
var corruption: Dictionary[int, float] = {}
# peer_id -> faction id (GameConstants.Faction). Populated by lobby at match start.
var player_factions: Dictionary[int, int] = {}
# peer_id -> display name. Populated by lobby at match start. Falls back to "Player <id>".
var player_names: Dictionary[int, String] = {}
# peer_id -> faction id. Overrides player_factions (debug faction swap, etc).
var faction_overrides: Dictionary[int, int] = {}
# peer_id -> { upgrade_kind_int -> level_int } (see UpgradeData.Kind)
var upgrade_levels: Dictionary[int, Dictionary] = {}

func is_avatar(peer_id: int) -> bool:
	return avatar_peer_id == peer_id

func has_avatar() -> bool:
	return avatar_peer_id != -1

func is_avatar_owner(peer_id: int) -> bool:
	return avatar_owner_peer_id == peer_id

func has_avatar_owner() -> bool:
	return avatar_owner_peer_id != -1

@rpc("authority", "call_local", "reliable")
func _set_avatar(peer_id: int) -> void:
	var old = avatar_peer_id
	avatar_peer_id = peer_id
	avatar_changed.emit(old, peer_id)

@rpc("authority", "call_local", "reliable")
func _set_avatar_owner(peer_id: int) -> void:
	var old = avatar_owner_peer_id
	avatar_owner_peer_id = peer_id
	avatar_owner_changed.emit(old, peer_id)

@rpc("any_peer", "call_local", "reliable")
func request_claim_avatar() -> void:
	## Any peer can request to claim. Host validates and grants.
	## Claiming an unowned avatar = own + possess in one step; the owner
	## re-requesting an uncontrolled avatar = possess only. A rival's avatar
	## can't be claimed here — take it in the field.
	if not multiplayer.is_server():
		request_claim_avatar.rpc_id(1)
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1 # Local call from host
	if avatar_owner_peer_id == -1:
		_set_avatar_owner.rpc(sender)
		_set_avatar.rpc(sender)
	elif avatar_owner_peer_id == sender and avatar_peer_id == -1:
		_set_avatar.rpc(sender)

@rpc("any_peer", "call_local", "reliable")
func request_recall_avatar() -> void:
	## Q from the Avatar: releases control only — the sender keeps ownership
	## and the avatar stays in the field as their pawn (AI-driven).
	if not multiplayer.is_server():
		request_recall_avatar.rpc_id(1)
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if not is_avatar(sender):
		return
	_set_avatar.rpc(-1)

@rpc("any_peer", "call_local", "reliable")
func request_win() -> void:
	## Any peer can request a win (touching the gem). Host validates.
	if not multiplayer.is_server():
		request_win.rpc_id(1)
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if is_avatar(sender):
		_announce_win.rpc(sender)

@rpc("authority", "call_local", "reliable")
func _announce_win(peer_id: int) -> void:
	game_won.emit(peer_id)

@rpc("authority", "call_local", "reliable")
func _announce_loss() -> void:
	game_lost.emit()

@rpc("any_peer", "reliable")
func request_add_watcher() -> void:
	if not multiplayer.is_server():
		request_add_watcher.rpc_id(1)
		return
	_set_watcher_count.rpc(watcher_count + 1)

@rpc("any_peer", "reliable")
func request_remove_watcher() -> void:
	if not multiplayer.is_server():
		request_remove_watcher.rpc_id(1)
		return
	_set_watcher_count.rpc(max(0, watcher_count - 1))

@rpc("authority", "call_local", "reliable")
func _set_watcher_count(count: int) -> void:
	watcher_count = count
	watcher_count_changed.emit(count)

@rpc("any_peer", "unreliable")
func update_watcher_position(pos: Vector3) -> void:
	## Called by scrying peers every frame to broadcast their camera position.
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	watcher_positions[sender] = pos
	watcher_positions_changed.emit()

func remove_watcher_position(peer_id: int) -> void:
	watcher_positions.erase(peer_id)
	watcher_positions_changed.emit()

signal mirror_message_received(message: MirrorMessage)

@rpc("any_peer", "reliable")
func deliver_mirror_message(
	sender_id: int,
	recipient_id: int,
	ghost_xforms: Array,
	anim_states: PackedStringArray,
	pose_sample_rate: float,
	audio_data: PackedByteArray,
	audio_sample_rate: int,
	duration: float
):
	## Route mirror messages through this autoload so the RPC path is consistent.
	## Called by sender, arrives on recipient.
	if multiplayer.get_unique_id() != recipient_id:
		return
	var msg = MirrorMessage.new()
	msg.sender_peer_id = sender_id
	msg.recipient_peer_id = recipient_id
	for x in ghost_xforms:
		msg.ghost_xforms.append(x)
	msg.anim_states = anim_states
	msg.pose_sample_rate = pose_sample_rate
	msg.audio_data = audio_data
	msg.audio_sample_rate = audio_sample_rate
	msg.duration = duration
	print("Mirror: received message - %d pose samples @ %.1fhz, %d audio bytes, %.1fs" % [
		msg.ghost_xforms.size(), msg.pose_sample_rate, msg.audio_data.size(), msg.duration
	])
	mirror_message_received.emit(msg)

func get_corruption(peer_id: int) -> float:
	return corruption.get(peer_id, 0.0)

func add_corruption(peer_id: int, amount: float) -> void:
	## Host-only: add corruption and broadcast to all clients.
	if not multiplayer.is_server():
		return
	var current = corruption.get(peer_id, 0.0)
	_set_corruption.rpc(peer_id, current + amount)

@rpc("authority", "call_local", "reliable")
func _set_corruption(peer_id: int, value: float) -> void:
	corruption[peer_id] = value
	corruption_changed.emit(peer_id, value)

func get_highest_corruption_peer() -> int:
	## Returns the peer with the highest corruption, or -1 if none.
	var best_peer := -1
	var best_score := -1.0
	for pid in corruption:
		if corruption[pid] > best_score:
			best_score = corruption[pid]
			best_peer = pid
	return best_peer

func get_total_corruption() -> float:
	## Sum of every player's corruption — the global "how corrupted is the
	## land" value that debuffs the Guardian Boss.
	var total := 0.0
	for pid in corruption:
		total += corruption[pid]
	return total

func get_max_corruption(peer_id: int) -> float:
	## Σ max_corruption_contribution over the gem sites this peer holds.
	## Corruption regenerates toward this ceiling (driven by each GemSite's
	## tick); drains (abilities etc.) pull below it and held sites refill.
	var total := 0.0
	for site in get_tree().get_nodes_in_group(&"gem_sites"):
		if site is GemSite and site.state == GemSite.SiteState.CAPTURED and site.controlling_peer_id == peer_id:
			total += site.max_corruption_contribution
	return total

func get_peer_faction(peer_id: int) -> int:
	return get_faction(peer_id)

func get_faction(peer_id: int) -> int:
	## Authoritative faction lookup. Respects debug overrides, falls back to
	## lobby-assigned factions, then to a round-robin if the lobby never synced
	## (e.g. scene booted directly without a lobby).
	if peer_id in faction_overrides:
		return faction_overrides[peer_id]
	if peer_id in player_factions:
		return player_factions[peer_id]
	var peers := multiplayer.get_peers().duplicate()
	if multiplayer.get_unique_id() not in peers:
		peers.append(multiplayer.get_unique_id())
	peers.sort()
	var idx := peers.find(peer_id)
	if idx >= 0:
		return GameConstants.PLAYABLE_FACTIONS[idx % GameConstants.PLAYABLE_FACTIONS.size()]
	return GameConstants.PLAYABLE_FACTIONS[0]

func set_faction_override(peer_id: int, faction: int) -> void:
	faction_overrides[peer_id] = faction

func clear_faction_override(peer_id: int) -> void:
	faction_overrides.erase(peer_id)

# --- Upgrades ---

func get_upgrade_level(peer_id: int, kind: int) -> int:
	if peer_id not in upgrade_levels:
		return 0
	return upgrade_levels[peer_id].get(kind, 0)

func add_upgrade(peer_id: int, kind: int) -> void:
	if peer_id not in upgrade_levels:
		upgrade_levels[peer_id] = {}
	upgrade_levels[peer_id][kind] = upgrade_levels[peer_id].get(kind, 0) + 1

@rpc("authority", "call_local", "reliable")
func sync_player_factions(factions: Dictionary) -> void:
	player_factions.clear()
	for pid in factions:
		player_factions[int(pid)] = int(factions[pid])

@rpc("authority", "call_local", "reliable")
func sync_player_names(names: Dictionary) -> void:
	player_names.clear()
	for pid in names:
		player_names[int(pid)] = String(names[pid])

func get_player_name(peer_id: int) -> String:
	return player_names.get(peer_id, "Player %d" % peer_id)

func reset() -> void:
	## Called when returning to menu to clear game state.
	avatar_peer_id = -1
	avatar_owner_peer_id = -1
	watcher_count = 0
	watcher_positions.clear()
	corruption.clear()
	player_factions.clear()
	player_names.clear()
	faction_overrides.clear()
	upgrade_levels.clear()
