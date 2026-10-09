extends Interactable

## The Mirror: live calls and recorded messages to rival Overlords (GDD §10).
##
## Calling a rival rings their mirror. If they walk over and answer (E) before
## RING_TIMEOUT, both mirrors show the other player's "clone" (a ghost copy of
## the player model on a stage scene) driven live by streamed skeleton poses,
## with voice both ways; either side ends it with E. If nobody answers, the
## caller is told and the call falls back to recording a message (RECORDING ->
## PREVIEW -> sent), which the recipient watches from their inbox.
##
## Everything is skeleton based (MirrorCodec): bone rotations plus the model's
## root transform relative to the mirror. All traffic is peer-routed through
## GameState RPCs (any peer can call any other peer's mirror).

const STAGE_SCENE: PackedScene = preload("res://scenes/interactibles/mirror_stage.tscn")

# Pose recording cadence
const POSE_SAMPLE_RATE: float = 30.0
const POSE_SAMPLE_INTERVAL: float = 1.0 / POSE_SAMPLE_RATE
const MAX_RECORD_SECONDS: float = 10.0

## PLACEHOLDER: tuning. Seconds the caller waits for the rival to answer before
## the call falls back to recording a message.
const RING_TIMEOUT: float = 20.0
## PLACEHOLDER: tuning. Pose frames per second streamed during a live call.
const LIVE_POSE_RATE: float = 20.0
## PLACEHOLDER: tuning. Voice is downsampled to about this many Hz for live calls.
const LIVE_AUDIO_RATE: int = 11025
## PLACEHOLDER: tuning. Seconds of voice per live audio packet.
const LIVE_AUDIO_CHUNK_SECONDS: float = 0.1
## PLACEHOLDER: tuning. Seconds a status line ("no answer" etc.) stays in the prompt.
const NOTICE_SECONDS: float = 5.0
## PLACEHOLDER: tuning. Seconds between chimes while the mirror rings.
const RING_CHIME_INTERVAL: float = 2.0
## PLACEHOLDER: tuning. Glow pulses per second while the mirror rings.
const RING_PULSE_HZ: float = 1.0
## PLACEHOLDER: art direction. Stand-in ring look: a coloured halo quad and light.
const RING_GLOW_COLOR: Color = Color(0.7, 0.5, 1.0)
const RING_GLOW_MARGIN: float = 0.3
const RING_GLOW_MAX_ALPHA: float = 0.45
const RING_LIGHT_ENERGY: float = 2.5
const RING_LIGHT_RANGE: float = 5.0
## PLACEHOLDER: art direction. Stand-in chime: two synthesized sine tones.
const CHIME_RATE: int = 22050
const CHIME_SECONDS: float = 0.7
const CHIME_HZ_LOW: float = 880.0
const CHIME_HZ_HIGH: float = 1320.0
const CHIME_DECAY: float = 5.0
const CHIME_VOLUME: float = 0.5

enum State { IDLE, SELECTING, CALLING, LIVE, RECORDING, PREVIEW, PLAYING }

var _mirror3d: Node3D
var _mirror_viewport: SubViewport:
	get: return _mirror3d.mirror_viewport if _mirror3d else null
var _mirror_quad: MeshInstance3D:
	get: return _mirror3d.mirror_quad if _mirror3d else null

var _state: State = State.IDLE

# Status line shown in the prompt for a few seconds ("no answer", "ended")
var _notice: String = ""
var _notice_timer: float = 0.0

# Recording
var _record_origin: Transform3D
var _record_pose: PackedByteArray = PackedByteArray()
var _record_frame_size: int = 0
var _record_audio: PackedFloat32Array = PackedFloat32Array()
var _record_sample_timer: float = 0.0
var _record_duration: float = 0.0

# Audio capture
var _mic_player: AudioStreamPlayer
var _audio_capture: AudioEffectCapture
var _mic_bus_idx: int = -1

# Stage / playback (shared by recorded playback and live calls)
var _play_message: MirrorMessage = null
var _play_stage: Node3D = null
var _play_ghost: Node3D = null
var _play_skeleton: Skeleton3D = null
var _play_audio_player: AudioStreamPlayer
var _play_audio_samples: PackedFloat32Array
var _play_audio_pos: int = 0
var _play_timer: float = 0.0

# Pending messages
var _inbox: Array[MirrorMessage] = []

# Selected recipient for sending
var _rival_index: int = 0
var _selected_recipient: int = -1
var _recorded_message: MirrorMessage = null

# Calls. _call_peer is the other end while CALLING or LIVE.
var _call_peer: int = -1
var _ring_elapsed: float = 0.0
## Peer whose call is ringing this mirror; -1 when quiet.
var _incoming_caller: int = -1
var _incoming_elapsed: float = 0.0
var _live_pose_timer: float = 0.0
var _live_frame: PackedByteArray = PackedByteArray()
var _live_audio_out: PackedFloat32Array = PackedFloat32Array()
var _live_audio_rate: int = 0
var _local_skeleton: Skeleton3D = null

# Ring effects (built in code)
var _ring_glow: MeshInstance3D
var _ring_glow_material: StandardMaterial3D
var _ring_light: OmniLight3D
var _chime_player: AudioStreamPlayer3D
var _chime_timer: float = 0.0
var _ring_phase: float = 0.0

func _interactable_ready() -> void:
	GameState.mirror_message_received.connect(_on_message_received)
	GameState.mirror_ring_received.connect(_on_ring_received)
	GameState.mirror_ring_cancelled.connect(_on_ring_cancelled)
	GameState.mirror_ring_answered.connect(_on_ring_answered)
	GameState.mirror_call_ended.connect(_on_call_ended)
	GameState.mirror_live_pose_received.connect(_on_live_pose_received)
	GameState.mirror_live_audio_received.connect(_on_live_audio_received)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_setup_mic_bus()
	_setup_ring_effects()
	call_deferred("_setup_mirror3d")

func _setup_mirror3d() -> void:
	var model := get_model()
	if model:
		_mirror3d = model.get_node_or_null("Mirror3D")
	if not _mirror3d:
		push_warning("Mirror: Mirror3D child not found under Model on %s" % get_path())
		_attach_ring_effects()
		return
	_attach_ring_effects()
	var quad_size: Vector2 = _mirror3d.size
	(_ring_glow.mesh as QuadMesh).size = quad_size + Vector2.ONE * RING_GLOW_MARGIN
	print("Mirror: Mirror3D resolved at %s" % _mirror3d.get_path())

func _setup_mic_bus() -> void:
	var existing_idx = AudioServer.get_bus_index("MirrorMic")
	if existing_idx != -1:
		_mic_bus_idx = existing_idx
		var effect_count = AudioServer.get_bus_effect_count(existing_idx)
		for i in effect_count:
			var fx = AudioServer.get_bus_effect(existing_idx, i)
			if fx is AudioEffectCapture:
				_audio_capture = fx
				break
	else:
		var bus_count = AudioServer.bus_count
		AudioServer.add_bus(bus_count)
		AudioServer.set_bus_name(bus_count, "MirrorMic")
		AudioServer.set_bus_send(bus_count, "Master")
		AudioServer.set_bus_mute(bus_count, true)
		_mic_bus_idx = bus_count

		var reverb = AudioEffectReverb.new()
		reverb.room_size = 0.8
		reverb.damping = 0.5
		reverb.wet = 0.12
		AudioServer.add_bus_effect(_mic_bus_idx, reverb)

		var capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_mic_bus_idx, capture)
		_audio_capture = capture

	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "MirrorMic"
	add_child(_mic_player)

	_play_audio_player = AudioStreamPlayer.new()
	add_child(_play_audio_player)

func _setup_ring_effects() -> void:
	## PLACEHOLDER: art direction. A pulsing halo, a light and a synthesized chime
	## stand in for "their mirror chimes or glows" (Q34) until there is real art/audio.
	_ring_glow_material = StandardMaterial3D.new()
	_ring_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_glow_material.albedo_color = Color(RING_GLOW_COLOR, 0.0)
	var quad := QuadMesh.new()
	quad.material = _ring_glow_material
	_ring_glow = MeshInstance3D.new()
	_ring_glow.mesh = quad
	_ring_glow.visible = false
	_ring_glow.position = Vector3(0.0, 0.0, -0.02)
	_ring_light = OmniLight3D.new()
	_ring_light.light_color = RING_GLOW_COLOR
	_ring_light.omni_range = RING_LIGHT_RANGE
	_ring_light.light_energy = 0.0
	_ring_light.visible = false
	_chime_player = AudioStreamPlayer3D.new()
	_chime_player.stream = _make_chime()
	_chime_player.volume_db = linear_to_db(CHIME_VOLUME)

func _attach_ring_effects() -> void:
	## Hang the effects under the Model's Mirror3D (or under us if it is missing).
	var host: Node3D = _mirror3d if _mirror3d else self
	for n in [_ring_glow, _ring_light, _chime_player]:
		host.add_child(n)

func _make_chime() -> AudioStreamWAV:
	var count: int = int(CHIME_RATE * CHIME_SECONDS)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / CHIME_RATE
		var env: float = exp(-CHIME_DECAY * t)
		var v: float = (sin(TAU * CHIME_HZ_LOW * t) + sin(TAU * CHIME_HZ_HIGH * t)) * 0.5 * env
		data.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = CHIME_RATE
	wav.stereo = false
	wav.data = data
	return wav

# --- Ownership ---

func get_owner_peer_id() -> int:
	## The peer whose tower this mirror stands in; the local peer when it is not
	## in a tower (test harness / the scene alone).
	var n: Node = get_parent()
	while n:
		if n is Tower:
			return (n as Tower).owner_peer_id
		n = n.get_parent()
	return multiplayer.get_unique_id()

func is_mine() -> bool:
	return get_owner_peer_id() == multiplayer.get_unique_id()

# --- Prompt ---

func get_prompt_text() -> String:
	if not is_mine():
		return "Mirror"
	if _notice != "":
		return _notice
	match _state:
		State.IDLE:
			if _incoming_caller > 0:
				return "%s is calling. Press E to answer" % GameState.get_player_name(_incoming_caller) # PLACEHOLDER: prompt text
			if _inbox.size() > 0:
				return "Press E to watch message (%d)" % _inbox.size()
			elif is_overlord_in_range():
				return "Press E to call"
			return "Mirror"
		State.SELECTING:
			if _selected_recipient > 0:
				return "Call %s. Press E (A/D to change)" % GameState.get_player_name(_selected_recipient) # PLACEHOLDER: prompt text
			return "No rivals connected" # PLACEHOLDER: prompt text
		State.CALLING:
			return "Calling %s... %ds. E to hang up" % [GameState.get_player_name(_call_peer), ceili(RING_TIMEOUT - _ring_elapsed)] # PLACEHOLDER: prompt text
		State.LIVE:
			return "On a call with %s. Press E to end" % GameState.get_player_name(_call_peer) # PLACEHOLDER: prompt text
		State.RECORDING:
			return "Recording... (%.1fs) Press E to stop" % _record_duration
		State.PREVIEW:
			return "E to send / Q to cancel"
		State.PLAYING:
			return "Playing... Press E to stop"
	return "Mirror"

func get_prompt_color() -> Color:
	if _notice != "":
		return Color(1, 0.8, 0.2)
	match _state:
		State.RECORDING:
			return Color(1, 0.2, 0.2)
		State.PREVIEW:
			return Color(0.2, 1, 0.2)
		State.PLAYING, State.CALLING, State.LIVE:
			return Color(1, 0.8, 0.2)
		State.IDLE:
			if _incoming_caller > 0 or _inbox.size() > 0:
				return Color(1, 0.8, 0.2)
	return Color(0.8, 0.5, 1)

# --- Input ---

func _on_interact() -> void:
	if not is_overlord_in_range() or not is_mine():
		return
	match _state:
		State.IDLE:
			if _incoming_caller > 0:
				_answer_call()
			elif _inbox.size() > 0:
				_start_playback(_inbox[0])
			else:
				_enter_selecting()
		State.SELECTING:
			if _selected_recipient > 0:
				_start_call(_selected_recipient)
		State.CALLING:
			_hang_up()
		State.LIVE:
			_end_live(true)
		State.RECORDING:
			_stop_recording()
		State.PREVIEW:
			_send_message()
		State.PLAYING:
			_stop_playback()

func _input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	if not _is_local_player(_player_in_range):
		return
	# Q cancels in preview/selecting/calling
	if event.is_action_pressed("cancel"):
		match _state:
			State.PREVIEW:
				_recorded_message = null
				_set_state(State.IDLE)
				get_viewport().set_input_as_handled()
			State.SELECTING:
				_set_state(State.IDLE)
				get_viewport().set_input_as_handled()
			State.CALLING:
				_hang_up()
				get_viewport().set_input_as_handled()

func _set_state(new_state: State) -> void:
	## Calling, live, recording and preview hold the modal lock so E still reaches
	## the mirror while the player looks away (a call must be endable anywhere).
	_state = new_state
	match new_state:
		State.CALLING, State.LIVE, State.RECORDING, State.PREVIEW:
			_claim_modal()
		_:
			_release_modal()

func _show_notice(text: String) -> void:
	_notice = text
	_notice_timer = NOTICE_SECONDS
	print("Mirror: ", text)

func _enter_selecting() -> void:
	_set_state(State.SELECTING)
	_rival_index = 0
	_select_rival(0)

func _rivals() -> Array[int]:
	var out: Array[int] = []
	for pid in multiplayer.get_peers():
		out.append(pid)
	out.sort()
	return out

func _select_rival(step: int) -> void:
	var rivals := _rivals()
	if rivals.is_empty():
		_selected_recipient = -1
		return
	_rival_index = posmod(_rival_index + step, rivals.size())
	_selected_recipient = rivals[_rival_index]

# --- Calling ---

func _can_reach(peer_id: int) -> bool:
	return peer_id > 0 and peer_id != multiplayer.get_unique_id() and peer_id in multiplayer.get_peers()

func start_call(peer_id: int) -> void:
	## Rings peer_id's mirror (public so tests and other UI can place a call).
	_start_call(peer_id)

func _start_call(peer_id: int) -> void:
	_selected_recipient = peer_id
	_call_peer = peer_id
	_ring_elapsed = 0.0
	_set_state(State.CALLING)
	if _can_reach(peer_id):
		GameState.mirror_ring.rpc_id(peer_id, peer_id)

func _hang_up() -> void:
	if _can_reach(_call_peer):
		GameState.mirror_ring_cancel.rpc_id(_call_peer, _call_peer)
	_call_peer = -1
	_set_state(State.IDLE)

func _ring_unanswered(reason: String) -> void:
	## Nobody picked up: tell the caller and fall back to recording a message.
	if _can_reach(_call_peer):
		GameState.mirror_ring_cancel.rpc_id(_call_peer, _call_peer)
	_call_peer = -1
	_show_notice(reason + " Recording a message.") # PLACEHOLDER: prompt text
	_start_recording()

func _process_calling(delta: float) -> void:
	_ring_elapsed += delta
	if _ring_elapsed >= RING_TIMEOUT:
		_ring_unanswered("No answer.") # PLACEHOLDER: prompt text

func _on_ring_received(caller_id: int) -> void:
	if not is_mine():
		return
	if _state != State.IDLE or _incoming_caller > 0:
		if _can_reach(caller_id):
			GameState.mirror_ring_reply.rpc_id(caller_id, caller_id, false)
		return
	_incoming_caller = caller_id
	_incoming_elapsed = 0.0
	_chime_timer = 0.0
	_ring_phase = 0.0
	_show_notice("")
	_refresh_prompt()

func _on_ring_cancelled(caller_id: int) -> void:
	if is_mine() and caller_id == _incoming_caller:
		_stop_ringing()

func _stop_ringing() -> void:
	_incoming_caller = -1
	_ring_glow.visible = false
	_ring_light.visible = false
	_chime_player.stop()
	_refresh_prompt()

func _answer_call() -> void:
	var caller := _incoming_caller
	_stop_ringing()
	_call_peer = caller
	if _can_reach(caller):
		GameState.mirror_ring_reply.rpc_id(caller, caller, true)
	_start_live()

func _on_ring_answered(answerer_id: int, accepted: bool) -> void:
	if not is_mine() or _state != State.CALLING or answerer_id != _call_peer:
		return
	if accepted:
		_start_live()
	else:
		_ring_unanswered("Line busy.") # PLACEHOLDER: prompt text

func _on_call_ended(peer_id: int) -> void:
	if is_mine() and _state == State.LIVE and peer_id == _call_peer:
		_end_live(false)

func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id == _incoming_caller:
		_stop_ringing()
	if peer_id == _call_peer and _state == State.LIVE:
		_end_live(false)
	elif peer_id == _call_peer and _state == State.CALLING:
		_ring_unanswered("Line dropped.") # PLACEHOLDER: prompt text

func _process_ring_effects(delta: float) -> void:
	if _incoming_caller <= 0:
		return
	_incoming_elapsed += delta
	if _incoming_elapsed > RING_TIMEOUT + NOTICE_SECONDS:
		_stop_ringing()  # the caller's cancel never arrived
		return
	_ring_phase += delta * RING_PULSE_HZ
	var pulse: float = 0.5 - 0.5 * cos(TAU * _ring_phase)
	_ring_glow.visible = true
	_ring_light.visible = true
	_ring_glow_material.albedo_color = Color(RING_GLOW_COLOR, pulse * RING_GLOW_MAX_ALPHA)
	_ring_light.light_energy = pulse * RING_LIGHT_ENERGY
	_chime_timer -= delta
	if _chime_timer <= 0.0:
		_chime_timer = RING_CHIME_INTERVAL
		_chime_player.play()

# --- Live call ---

func _start_live() -> void:
	_set_state(State.LIVE)
	_live_pose_timer = 0.0
	_live_frame = PackedByteArray()
	_live_audio_out = PackedFloat32Array()
	_live_audio_rate = 0
	_play_audio_samples = PackedFloat32Array()
	_play_audio_pos = 0
	_local_skeleton = MirrorCodec.find_skeleton(_player_in_range.get_model() if _player_in_range else null)
	if not _open_stage():
		push_warning("Mirror: live call without a stage; voice only")
	if _audio_capture:
		_audio_capture.clear_buffer()
	_mic_player.play()

func _end_live(notify: bool) -> void:
	if notify and _can_reach(_call_peer):
		GameState.mirror_call_end.rpc_id(_call_peer, _call_peer)
	_mic_player.stop()
	_close_stage()
	_call_peer = -1
	_local_skeleton = null
	_set_state(State.IDLE)
	_show_notice("Call ended.") # PLACEHOLDER: prompt text

func _process_live(delta: float) -> void:
	if not _can_reach(_call_peer):
		return
	_live_pose_timer += delta
	if _live_pose_timer >= 1.0 / LIVE_POSE_RATE:
		_live_pose_timer = 0.0
		var frame := _capture_pose_frame(_mirror3d.global_transform if _mirror3d else global_transform, _local_skeleton)
		if frame.size() > 0:
			GameState.mirror_live_pose.rpc_id(_call_peer, _call_peer, frame)
	_live_audio_out.append_array(_drain_capture())
	var mix_rate: int = int(AudioServer.get_mix_rate())
	if _live_audio_out.size() >= int(mix_rate * LIVE_AUDIO_CHUNK_SECONDS):
		var decimate: int = maxi(1, roundi(float(mix_rate) / LIVE_AUDIO_RATE))
		GameState.mirror_live_audio.rpc_id(_call_peer, _call_peer, MirrorCodec.encode_audio(_live_audio_out, decimate), roundi(float(mix_rate) / decimate))
		_live_audio_out.clear()

func _on_live_pose_received(sender_id: int, frame: PackedByteArray) -> void:
	if is_mine() and _state == State.LIVE and sender_id == _call_peer:
		_live_frame = frame

func _on_live_audio_received(sender_id: int, pcm: PackedByteArray, sample_rate: int) -> void:
	if not is_mine() or _state != State.LIVE or sender_id != _call_peer or sample_rate <= 0:
		return
	if sample_rate != _live_audio_rate:
		_live_audio_rate = sample_rate
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = sample_rate
		generator.buffer_length = 0.5
		_play_audio_player.stream = generator
		_play_audio_player.bus = "Master"
		_play_audio_player.play()
	_play_audio_samples.append_array(MirrorCodec.decode_audio(pcm))

# --- Recording ---

func _start_recording() -> void:
	if not _player_in_range:
		_set_state(State.IDLE)
		return
	_set_state(State.RECORDING)
	_record_pose = PackedByteArray()
	_record_audio = PackedFloat32Array()
	_record_sample_timer = 0.0
	_record_duration = 0.0
	_local_skeleton = MirrorCodec.find_skeleton(_player_in_range.get_model())
	_record_frame_size = MirrorCodec.frame_size(_local_skeleton.get_bone_count() if _local_skeleton else 0)

	if _mirror3d:
		_record_origin = _mirror3d.global_transform
	else:
		_record_origin = global_transform

	_capture_pose_sample()
	_audio_capture.clear_buffer()
	_mic_player.play()

func _stop_recording() -> void:
	_mic_player.stop()
	_record_audio.append_array(_drain_capture())

	_recorded_message = MirrorMessage.new()
	_recorded_message.sender_peer_id = multiplayer.get_unique_id()
	_recorded_message.recipient_peer_id = _selected_recipient
	_recorded_message.pose_data = _record_pose.duplicate()
	_recorded_message.pose_frame_size = _record_frame_size
	_recorded_message.pose_sample_rate = POSE_SAMPLE_RATE
	_recorded_message.audio_data = _record_audio.to_byte_array()
	_recorded_message.audio_sample_rate = int(AudioServer.get_mix_rate())
	_recorded_message.duration = _record_duration
	print("Mirror: recorded %d pose frames, %d audio samples, %.1fs" % [
		_recorded_message.frame_count(), _record_audio.size(), _record_duration
	])

	_local_skeleton = null
	_set_state(State.PREVIEW)

func _process_recording(delta: float) -> void:
	_record_duration += delta
	_record_sample_timer += delta

	while _record_sample_timer >= POSE_SAMPLE_INTERVAL:
		_record_sample_timer -= POSE_SAMPLE_INTERVAL
		_capture_pose_sample()

	_record_audio.append_array(_drain_capture())

	if _record_duration >= MAX_RECORD_SECONDS:
		_stop_recording()

func _capture_pose_sample() -> void:
	var frame := _capture_pose_frame(_record_origin, _local_skeleton)
	if frame.size() == _record_frame_size:
		_record_pose.append_array(frame)

func _capture_pose_frame(origin: Transform3D, skeleton: Skeleton3D) -> PackedByteArray:
	## One MirrorCodec frame of the local player's model, relative to `origin`
	## (the mirror). Empty when there is no player model in range.
	if not _player_in_range:
		return PackedByteArray()
	var model := _player_in_range.get_model()
	if not model:
		return PackedByteArray()
	return MirrorCodec.encode_pose(skeleton, origin.affine_inverse() * model.global_transform)

func _drain_capture() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if _audio_capture:
		var avail: int = _audio_capture.get_frames_available()
		if avail > 0:
			for frame in _audio_capture.get_buffer(avail):
				out.append(frame.x)
	return out

# --- Sending ---

func _send_message() -> void:
	if not _recorded_message:
		return
	var msg = _recorded_message
	_recorded_message = null
	_call_peer = -1
	_set_state(State.IDLE)

	if not _can_reach(msg.recipient_peer_id):
		return
	GameState.deliver_mirror_message.rpc_id(
		msg.recipient_peer_id,
		msg.sender_peer_id,
		msg.recipient_peer_id,
		msg.pose_data,
		msg.pose_frame_size,
		msg.pose_sample_rate,
		msg.audio_data,
		msg.audio_sample_rate,
		msg.duration
	)

func _on_message_received(msg: MirrorMessage) -> void:
	if msg.recipient_peer_id != multiplayer.get_unique_id() or not is_mine():
		return
	_inbox.append(msg)

# --- Stage (ghost on the mirror) ---

func _open_stage() -> bool:
	## Puts the stage scene (with its ghost copy of the player model) into the
	## mirror's viewport. The ghost's own animation is stopped: only the
	## streamed/recorded skeleton pose moves it.
	if not _mirror_viewport:
		push_warning("Mirror: cannot show stage, no SubViewport")
		return false

	_mirror_viewport.own_world_3d = true

	_play_stage = STAGE_SCENE.instantiate()
	_mirror_viewport.add_child(_play_stage)
	_play_stage.global_transform = _mirror3d.global_transform

	if _mirror3d.mirror_camera:
		_mirror3d.mirror_camera.current = true
	_mirror3d.config_dirty = true

	_play_ghost = _play_stage.get_node_or_null("StageOrigin/Ghost") as Node3D
	if not _play_ghost:
		push_warning("Mirror: stage scene has no Ghost node")
		return false
	_freeze_animation(_play_ghost)
	_play_skeleton = MirrorCodec.find_skeleton(_play_ghost)
	return true

func _close_stage() -> void:
	_play_audio_player.stop()
	_play_audio_samples = PackedFloat32Array()
	_play_audio_pos = 0

	if _play_stage and is_instance_valid(_play_stage):
		_play_stage.queue_free()
	_play_stage = null
	_play_ghost = null
	_play_skeleton = null

	if _mirror_viewport:
		_mirror_viewport.own_world_3d = false
	if _mirror3d:
		_mirror3d.mirror_camera.current = true
		_mirror3d.config_dirty = true

func _freeze_animation(root: Node) -> void:
	if root is AnimationPlayer:
		(root as AnimationPlayer).stop()
		(root as AnimationPlayer).active = false
	elif root is AnimationTree:
		(root as AnimationTree).active = false
	for child in root.get_children():
		_freeze_animation(child)

func apply_pose_frame(frame: PackedByteArray) -> void:
	## Poses the ghost from one MirrorCodec frame.
	if _play_ghost == null or frame.is_empty():
		return
	_play_ghost.transform = MirrorCodec.decode_root(frame)
	MirrorCodec.apply_pose(_play_skeleton, frame)

# --- Playback of a recorded message ---

func _start_playback(msg: MirrorMessage) -> void:
	_set_state(State.PLAYING)
	_play_message = msg
	_play_timer = 0.0
	_play_audio_pos = 0

	if not _open_stage():
		return
	apply_pose_frame(msg.get_frame(0))

	if msg.audio_data.size() > 0:
		_play_audio_samples = msg.audio_data.to_float32_array()
		var generator = AudioStreamGenerator.new()
		generator.mix_rate = msg.audio_sample_rate
		generator.buffer_length = 0.5
		_play_audio_player.stream = generator
		_play_audio_player.volume_db = 0.0
		_play_audio_player.bus = "Master"
		_play_audio_player.play()
		_push_audio_to_buffer()
	print("Mirror: playing %d pose frames, %.1fs, %d audio samples" % [
		msg.frame_count(), msg.duration, _play_audio_samples.size() if msg.audio_data.size() > 0 else 0
	])

func _stop_playback() -> void:
	_close_stage()
	if _play_message in _inbox:
		_inbox.erase(_play_message)
	_play_message = null
	_set_state(State.IDLE)

func _process_playback(delta: float) -> void:
	if not _play_message:
		return
	_play_timer += delta

	_push_audio_to_buffer()

	if _play_message.frame_count() > 0:
		apply_pose_frame(_play_message.get_frame(int(_play_timer * _play_message.pose_sample_rate)))

	if _play_timer >= _play_message.duration:
		_stop_playback()

func _push_audio_to_buffer() -> void:
	if not _play_audio_player.playing or _play_audio_samples.size() == 0:
		return
	if _play_audio_pos >= _play_audio_samples.size():
		return
	var playback = _play_audio_player.get_stream_playback()
	if not playback:
		return
	var available = playback.get_frames_available()
	var remaining = _play_audio_samples.size() - _play_audio_pos
	var to_push = mini(available, remaining)
	for i in to_push:
		var s = _play_audio_samples[_play_audio_pos]
		playback.push_frame(Vector2(s, s))
		_play_audio_pos += 1

# --- Main loop ---

func _process(delta: float) -> void:
	super(delta)
	if _notice_timer > 0.0:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			_notice = ""
	_process_ring_effects(delta)
	match _state:
		State.CALLING:
			_process_calling(delta)
		State.LIVE:
			_process_live(delta)
			_process_live_playback()
		State.RECORDING:
			_process_recording(delta)
		State.PLAYING:
			_process_playback(delta)
		State.SELECTING:
			_process_selecting()

func _process_live_playback() -> void:
	apply_pose_frame(_live_frame)
	_push_audio_to_buffer()
	if _play_audio_pos > 0:
		# Drop what has been played so the live queue doesn't grow for the whole call.
		_play_audio_samples = _play_audio_samples.slice(_play_audio_pos)
		_play_audio_pos = 0

func _process_selecting() -> void:
	if Input.is_action_just_pressed("right"):
		_select_rival(1)
	elif Input.is_action_just_pressed("left"):
		_select_rival(-1)
	elif _selected_recipient <= 0 or not _can_reach(_selected_recipient):
		_select_rival(0)
