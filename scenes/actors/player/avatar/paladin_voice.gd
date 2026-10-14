class_name PaladinVoice extends Node

## Live voice around the Paladin (GDD §8 "Seen by all", Q19; ticket #558):
## everyone looking through a Palantir and whoever drives him hear each other,
## with no distance falloff. A child of AvatarActor (in avatar_actor.tscn, with its Mic player).
##
## Same approach as the mirror's live calls (scripts/interactibles/mirror.gd):
## the microphone plays into a muted bus with an AudioEffectCapture; captured
## frames are averaged down to about VOICE_RATE Hz, packed as int16 with
## MirrorCodec and sent with rpc_id to every other member; each sender gets an
## AudioStreamGenerator player on the receiving side.
## UNTESTED: real multi-peer voice (the headless tests have one peer and no mic).

const MIC_BUS: String = "PaladinMic"
## PLACEHOLDER: tuning — voice is downsampled to about this many Hz.
const VOICE_RATE: int = 11025
## PLACEHOLDER: tuning — seconds of voice per packet.
const CHUNK_SECONDS: float = 0.1
const PLAYBACK_BUFFER_SECONDS: float = 0.5

## Instanced per remote speaker.
@export var voice_player_scene: PackedScene

var _capture: AudioEffectCapture
var _speaking: bool = false
var _out: PackedFloat32Array = PackedFloat32Array()
var _players: Dictionary[int, AudioStreamPlayer] = {}
var _player_rates: Dictionary[int, int] = {}
var _queues: Dictionary[int, PackedFloat32Array] = {}

@onready var _mic_player: AudioStreamPlayer = $Mic

func _ready() -> void:
	_setup_mic_bus()

func _process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var me := multiplayer.get_unique_id()
	var members := GameState.get_paladin_voice_peers()
	var in_group := me in members
	if in_group != _speaking:
		_set_speaking(in_group)
	if _speaking:
		_send_voice(me, members)
	_drop_departed(members)
	_feed_players()

func is_speaking() -> bool:
	return _speaking

func _setup_mic_bus() -> void:
	# Data-only: the shared PaladinMic audio bus lives in the AudioServer, not the
	# scene tree; the Mic player that records into it is authored in avatar_actor.tscn.
	var idx := AudioServer.get_bus_index(MIC_BUS)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, MIC_BUS)
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_mute(idx, true)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectCapture:
			_capture = fx

func _set_speaking(on: bool) -> void:
	_speaking = on
	_out.clear()
	if on:
		if _capture:
			_capture.clear_buffer()
		# No microphone in headless runs (tests, dedicated server).
		if DisplayServer.get_name() != "headless":
			_mic_player.play()
	else:
		_mic_player.stop()

func _send_voice(me: int, members: Array[int]) -> void:
	if _capture == null:
		return
	var avail := _capture.get_frames_available()
	if avail > 0:
		for frame in _capture.get_buffer(avail):
			_out.append(frame.x)
	var mix_rate := int(AudioServer.get_mix_rate())
	if _out.size() < int(mix_rate * CHUNK_SECONDS):
		return
	var decimate: int = maxi(1, roundi(float(mix_rate) / VOICE_RATE))
	var pcm := MirrorCodec.encode_audio(_out, decimate)
	var rate: int = roundi(float(mix_rate) / decimate)
	_out.clear()
	for peer in members:
		if peer != me and peer in multiplayer.get_peers():
			_receive_voice.rpc_id(peer, pcm, rate)

@rpc("any_peer", "unreliable")
func _receive_voice(pcm: PackedByteArray, sample_rate: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var members := GameState.get_paladin_voice_peers()
	if sample_rate <= 0 or sender not in members or multiplayer.get_unique_id() not in members:
		return
	if _player_rates.get(sender, 0) != sample_rate:
		_start_player(sender, sample_rate)
	var queue: PackedFloat32Array = _queues.get(sender, PackedFloat32Array())
	queue.append_array(MirrorCodec.decode_audio(pcm))
	_queues[sender] = queue

func _start_player(sender: int, sample_rate: int) -> void:
	var player: AudioStreamPlayer = _players.get(sender, null)
	if player == null:
		player = voice_player_scene.instantiate() as AudioStreamPlayer
		player.name = "Voice%d" % sender
		add_child(player)
		_players[sender] = player
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = PLAYBACK_BUFFER_SECONDS
	player.stream = generator
	player.play()
	_player_rates[sender] = sample_rate

func _feed_players() -> void:
	for sender in _players:
		var queue: PackedFloat32Array = _queues.get(sender, PackedFloat32Array())
		if queue.is_empty():
			continue
		var playback := _players[sender].get_stream_playback() as AudioStreamGeneratorPlayback
		if playback == null:
			continue
		var n: int = mini(playback.get_frames_available(), queue.size())
		for i in n:
			playback.push_frame(Vector2(queue[i], queue[i]))
		_queues[sender] = queue.slice(n)

func _drop_departed(members: Array[int]) -> void:
	## A viewer who left the Palantir (or a controller who let go) falls silent.
	for sender in _players.keys():
		if sender not in members:
			_players[sender].queue_free()
			_players.erase(sender)
			_player_rates.erase(sender)
			_queues.erase(sender)
