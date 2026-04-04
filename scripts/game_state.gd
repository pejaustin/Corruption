extends Node

## Tracks global game state: who is the Avatar, influence, win condition.
## Autoload singleton.

signal avatar_changed(old_peer_id: int, new_peer_id: int)
signal game_won(peer_id: int)

# -1 means no Avatar is active
var avatar_peer_id: int = -1

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
	if not multiplayer.is_server():
		return
	_set_avatar.rpc(-1)

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

func reset():
	## Called when returning to menu to clear game state.
	avatar_peer_id = -1
