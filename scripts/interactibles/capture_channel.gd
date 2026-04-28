class_name CaptureChannel extends Node

## Reusable "hold E to capture" component for interactables (Gem, GemSite).
##
## Host-authoritative:
## - Server starts the timer, watches for damage / dormancy interruption,
##   and broadcasts lifecycle RPCs.
## - Controlling peer transitions the Avatar into ChannelState so the player
##   stands still and can't act until the channel ends.
## - Any peer can request a cancel (E-press) via request_cancel().
##
## Subscribe to channel_completed / channel_interrupted to apply game effects
## (flip a gem_site to CAPTURED, trigger win, etc.) — only act on the host.

signal channel_started(peer_id: int, faction: int)
signal channel_progressed(t: float)  # 0..1, emitted every physics tick while active
signal channel_completed(peer_id: int, faction: int)
signal channel_interrupted(peer_id: int, reason: StringName)

@export var channel_duration: float = 3.0
## When true, emits GameState.capture_broadcast on start so any global
## listener (clouds, audio sting, HUD banner) can react.
@export var broadcast: bool = false

var _active: bool = false
var _peer_id: int = -1
var _faction: int = -1
var _avatar: AvatarActor = null
var _start_time_msec: int = 0
var _start_hp: int = 0

func is_active() -> bool:
	return _active

func get_peer_id() -> int:
	return _peer_id

func get_progress() -> float:
	if not _active:
		return 0.0
	var elapsed := (Time.get_ticks_msec() - _start_time_msec) / 1000.0
	return clamp(elapsed / channel_duration, 0.0, 1.0)

## Called by the peer who just pressed E. Routes the request to the host.
func try_start(avatar: AvatarActor, peer_id: int, faction: int) -> void:
	if _active:
		return
	if avatar == null or avatar.is_dormant:
		return
	_request_start.rpc_id(1, peer_id, faction)

## Called by the peer who pressed E a second time to cancel.
func request_cancel() -> void:
	if not _active:
		return
	_request_cancel.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func _request_start(peer_id: int, faction: int) -> void:
	if not multiplayer.is_server():
		return
	if _active:
		return
	var avatar := _find_avatar(peer_id)
	if avatar == null or avatar.is_dormant:
		return
	_start_channel.rpc(peer_id, faction)

@rpc("any_peer", "call_local", "reliable")
func _request_cancel() -> void:
	if not multiplayer.is_server():
		return
	if not _active:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != _peer_id:
		return
	_interrupt_channel.rpc(&"cancelled")

@rpc("authority", "call_local", "reliable")
func _start_channel(peer_id: int, faction: int) -> void:
	_active = true
	_peer_id = peer_id
	_faction = faction
	_avatar = _find_avatar(peer_id)
	_start_time_msec = Time.get_ticks_msec()
	_start_hp = _avatar.hp if _avatar else 0
	# Every peer sets active_channel so ChannelState.tick stays truthy through
	# rollback replay on both authority and display peers. The actual state
	# transition is driven by PlayerState.try_enter_channel() inside tick(),
	# because netfox rollback clobbers state changes made outside the tick loop.
	if _avatar:
		_avatar.active_channel = self
	channel_started.emit(peer_id, faction)
	if broadcast:
		GameState.capture_broadcast.emit(peer_id, faction, channel_duration)

@rpc("authority", "call_local", "reliable")
func _complete_channel() -> void:
	if not _active:
		return
	var pid := _peer_id
	var fac := _faction
	_reset()
	channel_completed.emit(pid, fac)

@rpc("authority", "call_local", "reliable")
func _interrupt_channel(reason: StringName) -> void:
	if not _active:
		return
	var pid := _peer_id
	_reset()
	channel_interrupted.emit(pid, reason)

func _reset() -> void:
	if _avatar and _avatar.active_channel == self:
		_avatar.active_channel = null
	_active = false
	_peer_id = -1
	_faction = -1
	_avatar = null
	_start_time_msec = 0
	_start_hp = 0

func _physics_process(_delta: float) -> void:
	if not _active:
		return
	channel_progressed.emit(get_progress())
	if not multiplayer.is_server():
		return
	if _avatar == null or not is_instance_valid(_avatar) or _avatar.is_dormant:
		_interrupt_channel.rpc(&"avatar_lost")
		return
	if _avatar.hp < _start_hp:
		_interrupt_channel.rpc(&"damage")
		return
	if get_progress() >= 1.0:
		_complete_channel.rpc()

func _find_avatar(peer_id: int) -> AvatarActor:
	for node in get_tree().get_nodes_in_group(&"actors"):
		if node is AvatarActor and node.controlling_peer_id == peer_id:
			return node
	return null
