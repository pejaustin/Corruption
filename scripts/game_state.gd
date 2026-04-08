extends Node

## Tracks global game state: who is the Avatar, influence, win condition.
## Autoload singleton.

signal avatar_changed(old_peer_id: int, new_peer_id: int)
signal game_won(peer_id: int)
signal watcher_count_changed(count: int)
signal watcher_positions_changed()

# -1 means no Avatar is active
var avatar_peer_id: int = -1
# How many Overlords are scrying the Avatar right now
var watcher_count: int = 0
# peer_id -> global camera position of each active scryer
var watcher_positions: Dictionary = {}

func is_avatar(peer_id: int) -> bool:
	return avatar_peer_id == peer_id

func has_avatar() -> bool:
	return avatar_peer_id != -1

func claim_avatar(peer_id: int):
	## Called by the host when a player claims the Avatar.
	if not multiplayer.is_server():
		return
	if has_avatar():
		return
	_set_avatar.rpc(peer_id)

func release_avatar():
	## Called by the host when the Avatar is released (death, recall, etc.)
	## Passes control to the next player in round-robin order.
	if not multiplayer.is_server():
		return
	var old = avatar_peer_id
	_set_avatar.rpc(-1)
	# Round-robin: find the next connected peer
	var next = _get_next_peer(old)
	if next > 0:
		_set_avatar.rpc(next)

func _get_next_peer(current_peer: int) -> int:
	## Returns the next peer in round-robin order, skipping the current one.
	var peers = multiplayer.get_peers().duplicate()
	if multiplayer.get_unique_id() not in peers:
		peers.append(multiplayer.get_unique_id())
	peers.sort()
	if peers.size() <= 1:
		return -1  # No one else to transfer to
	var idx = peers.find(current_peer)
	if idx == -1:
		return peers[0]
	var next_idx = (idx + 1) % peers.size()
	if peers[next_idx] == current_peer:
		return -1
	return peers[next_idx]

@rpc("authority", "call_local", "reliable")
func _set_avatar(peer_id: int):
	var old = avatar_peer_id
	avatar_peer_id = peer_id
	avatar_changed.emit(old, peer_id)

@rpc("any_peer", "call_local", "reliable")
func request_claim_avatar():
	## Any peer can request to claim. Host validates and grants.
	if not multiplayer.is_server():
		request_claim_avatar.rpc_id(1)
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1 # Local call from host
	claim_avatar(sender)

@rpc("any_peer", "call_local", "reliable")
func request_recall_avatar():
	## Avatar controller requests to return to their tower.
	if not multiplayer.is_server():
		request_recall_avatar.rpc_id(1)
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if is_avatar(sender):
		release_avatar()

@rpc("any_peer", "call_local", "reliable")
func request_win():
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
func _announce_win(peer_id: int):
	game_won.emit(peer_id)

@rpc("any_peer", "reliable")
func request_add_watcher():
	if not multiplayer.is_server():
		request_add_watcher.rpc_id(1)
		return
	_set_watcher_count.rpc(watcher_count + 1)

@rpc("any_peer", "reliable")
func request_remove_watcher():
	if not multiplayer.is_server():
		request_remove_watcher.rpc_id(1)
		return
	_set_watcher_count.rpc(max(0, watcher_count - 1))

@rpc("authority", "call_local", "reliable")
func _set_watcher_count(count: int):
	watcher_count = count
	watcher_count_changed.emit(count)

@rpc("any_peer", "unreliable")
func update_watcher_position(pos: Vector3):
	## Called by scrying peers every frame to broadcast their camera position.
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	watcher_positions[sender] = pos
	watcher_positions_changed.emit()

func remove_watcher_position(peer_id: int):
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

func reset():
	## Called when returning to menu to clear game state.
	avatar_peer_id = -1
	watcher_count = 0
	watcher_positions.clear()
