extends Node

## Tracks global match state: seats, the Avatar's owner and controller,
## Palantir watchers, match pace, and the win / draw announcements.
## Autoload singleton.
##
## GDD v2 (docs/GDD.md): corruption is not a resource, so there is no per-player
## score here. What a player has is the set of corruption sites they hold
## (CorruptionSite, group &"corruption_sites"); see get_held_sites().

signal avatar_changed(old_peer_id: int, new_peer_id: int)
signal avatar_owner_changed(old_peer_id: int, new_peer_id: int)
signal game_won(peer_id: int)
signal game_drawn
signal watcher_count_changed(count: int)
signal watcher_positions_changed()
## Fired on every peer when a site changes hands (GDD §7: "a beacon in the sky
## ... marks a site taken for the first time, changing hands, or returning to
## neutral"). old/new are peer ids; -1 is neutral.
signal site_changed(site: Node, old_holder: int, new_holder: int, first_taken: bool)
signal mirror_message_received(message: MirrorMessage)
## Mirror calls (GDD §10). Each fires only on the peer the call is addressed to.
signal mirror_ring_received(caller_id: int)
signal mirror_ring_cancelled(caller_id: int)
signal mirror_ring_answered(answerer_id: int, accepted: bool)
signal mirror_call_ended(peer_id: int)
signal mirror_live_pose_received(sender_id: int, frame: PackedByteArray)
signal mirror_live_audio_received(sender_id: int, pcm: PackedByteArray, sample_rate: int)

# The Avatar (the Paladin) can be owned by a player and, separately, driven
# directly by them (docs/systems/avatar-possession.md).
# CONTROLLER: -1 = no one is driving it (AI drives).
var avatar_peer_id: int = -1
# OWNER: which peer holds the Paladin. -1 = the good faction has him.
var avatar_owner_peer_id: int = -1
# How many Overlords are scrying the Avatar right now
var watcher_count: int = 0
## Peers looking through a Palantir right now (GDD §8 "Seen by all"). Kept by
## the host and mirrored to every peer.
var watchers: Array[int] = []
# peer_id -> global camera position of each active scryer (remote ones only)
var watcher_positions: Dictionary[int, Vector3] = {}
# peer_id -> faction id (GameConstants.Faction). Populated by lobby at match start.
# MVP: everyone is Undead (GDD §1).
var player_factions: Dictionary[int, int] = {}
# peer_id -> display name. Populated by lobby at match start.
var player_names: Dictionary[int, String] = {}
# peer_id -> tower slot (0..MAX_PLAYERS-1). Set on every peer when the host
# binds towers (MinionManager._bind_rally_rpc). Drives seat colours.
var player_slots: Dictionary[int, int] = {}
## peer_id -> extra route points an order may carry (order granularity, Q2).
var route_point_bonus: Dictionary[int, int] = {}
## Match pace (MatchConfig.Pace), chosen by the host in the lobby.
var match_pace: int = MatchConfig.Pace.NORMAL

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
	var old := avatar_peer_id
	avatar_peer_id = peer_id
	avatar_changed.emit(old, peer_id)

@rpc("authority", "call_local", "reliable")
func _set_avatar_owner(peer_id: int) -> void:
	var old := avatar_owner_peer_id
	avatar_owner_peer_id = peer_id
	avatar_owner_changed.emit(old, peer_id)

func set_avatar_owner(peer_id: int) -> void:
	## Host-only: hand the Paladin to a new owner (or -1, the good faction).
	## Any change of owner also drops whoever was driving him.
	if not multiplayer.is_server():
		return
	if avatar_owner_peer_id == peer_id:
		return
	if avatar_peer_id != -1:
		_set_avatar.rpc(-1)
	_set_avatar_owner.rpc(peer_id)

@rpc("any_peer", "call_local", "reliable")
func request_possess_avatar() -> void:
	## The owner takes direct control at the Palantir (GDD §8: "you can leave the
	## Palantir for the tower and come back freely"). Only the owner may drive.
	if not multiplayer.is_server():
		request_possess_avatar.rpc_id(1)
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if avatar_owner_peer_id == sender and avatar_peer_id == -1:
		_set_avatar.rpc(sender)

@rpc("any_peer", "call_local", "reliable")
func request_recall_avatar() -> void:
	## Q from the Avatar: releases control only — the sender keeps ownership
	## and the Paladin stays in the field following orders (AvatarAI).
	if not multiplayer.is_server():
		request_recall_avatar.rpc_id(1)
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if not is_avatar(sender):
		return
	_set_avatar.rpc(-1)

func announce_win(peer_id: int) -> void:
	## Host-only.
	if multiplayer.is_server():
		_announce_win.rpc(peer_id)

func announce_draw() -> void:
	## Host-only.
	if multiplayer.is_server():
		_announce_draw.rpc()

@rpc("authority", "call_local", "reliable")
func _announce_win(peer_id: int) -> void:
	game_won.emit(peer_id)

@rpc("authority", "call_local", "reliable")
func _announce_draw() -> void:
	game_drawn.emit()

func is_watching(peer_id: int) -> bool:
	return peer_id in watchers

@rpc("any_peer", "call_local", "reliable")
func request_set_watching(watching: bool) -> void:
	## A peer starts or stops looking through a Palantir. Routed to the host,
	## which keeps the list and mirrors it to everyone.
	if not multiplayer.is_server():
		request_set_watching.rpc_id(1, watching)
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var list: Array[int] = watchers.duplicate()
	if watching and sender not in list:
		list.append(sender)
	elif not watching:
		list.erase(sender)
	_sync_watchers.rpc(list)

@rpc("authority", "call_local", "reliable")
func _sync_watchers(list: Array) -> void:
	# Untyped over the wire; copied (call_local hands us the sender's array).
	watchers.clear()
	for pid in list:
		watchers.append(int(pid))
	for pid in watcher_positions.keys():
		if pid not in watchers:
			watcher_positions.erase(pid)
	watcher_count = watchers.size()
	watcher_count_changed.emit(watcher_count)
	watcher_positions_changed.emit()

@rpc("any_peer", "unreliable")
func update_watcher_position(pos: Vector3) -> void:
	## Called by scrying peers every frame to broadcast their camera position.
	## Late packets from someone who stopped watching are dropped.
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender not in watchers:
		return
	watcher_positions[sender] = pos
	watcher_positions_changed.emit()

func get_paladin_voice_peers() -> Array[int]:
	## Everyone who hears the Paladin's channel (GDD §8: "every player sees and
	## hears him live, and the viewers hear each other"): the Palantir viewers
	## plus whoever drives him.
	var out: Array[int] = watchers.duplicate()
	if avatar_peer_id > 0 and avatar_peer_id not in out:
		out.append(avatar_peer_id)
	return out

@rpc("any_peer", "reliable")
func deliver_mirror_message(
	sender_id: int,
	recipient_id: int,
	pose_data: PackedByteArray,
	pose_frame_size: int,
	pose_sample_rate: float,
	audio_data: PackedByteArray,
	audio_sample_rate: int,
	duration: float
) -> void:
	## Route mirror messages through this autoload so the RPC path is consistent.
	## Called by sender, arrives on recipient.
	if multiplayer.get_unique_id() != recipient_id:
		return
	var msg := MirrorMessage.new()
	msg.sender_peer_id = sender_id
	msg.recipient_peer_id = recipient_id
	msg.pose_data = pose_data
	msg.pose_frame_size = pose_frame_size
	msg.pose_sample_rate = pose_sample_rate
	msg.audio_data = audio_data
	msg.audio_sample_rate = audio_sample_rate
	msg.duration = duration
	mirror_message_received.emit(msg)

# Mirror calls. Every call is sent with rpc_id straight to the peer it is for;
# the sender id is taken from the RPC itself (never trusted from an argument).

@rpc("any_peer", "reliable")
func mirror_ring(recipient_id: int) -> void:
	## Caller rings the recipient's mirror.
	if multiplayer.get_unique_id() != recipient_id:
		return
	mirror_ring_received.emit(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func mirror_ring_cancel(recipient_id: int) -> void:
	## Caller gave up (hung up or timed out); the recipient's mirror stops ringing.
	if multiplayer.get_unique_id() != recipient_id:
		return
	mirror_ring_cancelled.emit(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func mirror_ring_reply(caller_id: int, accepted: bool) -> void:
	## Recipient answers (true) or is busy (false); arrives on the caller.
	if multiplayer.get_unique_id() != caller_id:
		return
	mirror_ring_answered.emit(multiplayer.get_remote_sender_id(), accepted)

@rpc("any_peer", "reliable")
func mirror_call_end(peer_id: int) -> void:
	## Either side ends a live call.
	if multiplayer.get_unique_id() != peer_id:
		return
	mirror_call_ended.emit(multiplayer.get_remote_sender_id())

@rpc("any_peer", "unreliable")
func mirror_live_pose(peer_id: int, frame: PackedByteArray) -> void:
	## One MirrorCodec pose frame of a live call; lost packets are simply skipped.
	if multiplayer.get_unique_id() != peer_id:
		return
	mirror_live_pose_received.emit(multiplayer.get_remote_sender_id(), frame)

@rpc("any_peer", "unreliable")
func mirror_live_audio(peer_id: int, pcm: PackedByteArray, sample_rate: int) -> void:
	## One chunk of live voice (int16 mono at `sample_rate`).
	if multiplayer.get_unique_id() != peer_id:
		return
	mirror_live_audio_received.emit(multiplayer.get_remote_sender_id(), pcm, sample_rate)

# --- Corruption sites ---

func get_all_sites() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"corruption_sites")

func get_held_sites(peer_id: int) -> Array[Node]:
	## Every corruption site this peer holds, including their own tower.
	var out: Array[Node] = []
	for site in get_all_sites():
		if site.get(&"holder_peer_id") == peer_id:
			out.append(site)
	return out

func count_held_sites(peer_id: int, include_towers: bool = false) -> int:
	var n := 0
	for site in get_held_sites(peer_id):
		if not include_towers and bool(site.get(&"permanent")):
			continue
		n += 1
	return n

func has_capability(peer_id: int, capability: StringName) -> bool:
	## True if any site this peer holds grants `capability` (GDD §7: "each type
	## of corruption site grants one discrete capability").
	for site in get_held_sites(peer_id):
		if site.has_method(&"grants") and site.grants(capability):
			return true
	return false

func count_capability(peer_id: int, capability: StringName) -> int:
	## How many held sites grant `capability` — for capabilities that stack
	## (Avatar control, boss strength).
	var n := 0
	for site in get_held_sites(peer_id):
		if site.has_method(&"grants") and site.grants(capability):
			n += 1
	return n

# --- Seats ---

func get_player_peers() -> Array[int]:
	## Every seated player (real or CPU), sorted.
	var out: Array[int] = []
	for pid in player_names:
		out.append(pid)
	for pid in player_slots:
		if pid not in out:
			out.append(pid)
	out.sort()
	return out

func get_faction(peer_id: int) -> int:
	return player_factions.get(peer_id, GameConstants.PLAYABLE_FACTIONS[0])

func get_peer_faction(peer_id: int) -> int:
	return get_faction(peer_id)

func set_player_slot(peer_id: int, slot: int) -> void:
	player_slots[peer_id] = slot

func get_player_color(peer_id: int) -> Color:
	## Seat colour. The good faction (-1) has its own colour.
	if peer_id < 0:
		return GameConstants.GOOD_COLOR
	var slot: int = player_slots.get(peer_id, -1)
	if slot < 0:
		var peers := get_player_peers()
		slot = peers.find(peer_id)
	if slot < 0:
		return Color.WHITE
	return GameConstants.SEAT_COLORS[slot % GameConstants.SEAT_COLORS.size()]

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

@rpc("authority", "call_local", "reliable")
func sync_match_pace(pace: int) -> void:
	match_pace = pace

func get_route_point_bonus(peer_id: int) -> int:
	return route_point_bonus.get(peer_id, 0)

@rpc("authority", "call_local", "reliable")
func add_route_point_bonus(peer_id: int, amount: int) -> void:
	route_point_bonus[peer_id] = get_route_point_bonus(peer_id) + amount

func get_player_name(peer_id: int) -> String:
	if peer_id < 0:
		return "the good faction"
	return player_names.get(peer_id, "Player %d" % peer_id)

func reset() -> void:
	## Called when returning to menu to clear game state.
	avatar_peer_id = -1
	avatar_owner_peer_id = -1
	watcher_count = 0
	watchers.clear()
	watcher_positions.clear()
	player_factions.clear()
	player_names.clear()
	player_slots.clear()
	route_point_bonus.clear()
	match_pace = MatchConfig.Pace.NORMAL
