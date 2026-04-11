extends Area3D

## The Mirror — record and send "video" messages to rival Overlords.
##
## Instead of capturing pixel frames (which forces a per-frame GPU readback
## and tanks fps), we record the sender's player-model pose at a fixed rate.
## On playback the recipient's mirror loads its own isolated stage scene
## into the Mirror3D SubViewport and drives a ghost copy of player_model.tscn
## from the recorded pose track.

@export var interact_prompt: Label3D

const STAGE_SCENE := preload("res://scenes/interactibles/mirror_stage.tscn")

# Pose recording cadence
const POSE_SAMPLE_RATE := 30.0
const POSE_SAMPLE_INTERVAL := 1.0 / POSE_SAMPLE_RATE
const MAX_RECORD_SECONDS := 10.0

var _mirror3d: Node3D  # The Mirror3D addon node (typed loosely to avoid class load issues)
# Convenience accessors into the addon (which has its own per-instance material)
var _mirror_viewport: SubViewport:
	get: return _mirror3d.mirror_viewport if _mirror3d else null
var _mirror_quad: MeshInstance3D:
	get: return _mirror3d.mirror_quad if _mirror3d else null

enum State { IDLE, SELECTING, RECORDING, PREVIEW, PLAYING }

var _player_in_range: Player = null
var _state: State = State.IDLE

# Recording — pose track (stage-local) + audio
var _record_origin: Transform3D
var _record_xforms: Array[Transform3D] = []
var _record_anims: PackedStringArray = PackedStringArray()
var _record_audio: PackedFloat32Array = PackedFloat32Array()
var _record_sample_timer: float = 0.0
var _record_duration: float = 0.0

# Audio capture
var _mic_player: AudioStreamPlayer
var _audio_capture: AudioEffectCapture
var _mic_bus_idx: int = -1

# Playback
var _play_message: MirrorMessage = null
var _play_stage: Node3D = null
var _play_ghost: Node3D = null
var _play_ghost_anim: AnimationPlayer = null
var _play_last_anim: String = ""
var _play_audio_player: AudioStreamPlayer
var _play_audio_samples: PackedFloat32Array
var _play_audio_pos: int = 0
var _play_timer: float = 0.0

# Pending messages (received from other players)
var _inbox: Array[MirrorMessage] = []

# Selected recipient for sending
var _selected_recipient: int = -1
var _recorded_message: MirrorMessage = null

func _ready():
	body_entered.connect(_on_body_entered)
	#body_exited.connect(_on_body_exited)
	GameState.mirror_message_received.connect(_on_message_received)
	_setup_mic_bus()
	_update_prompt()
	# Defer Mirror3D lookup until the whole tree is ready (sibling nodes
	# may not be in the tree yet during our _ready)
	call_deferred("_setup_mirror3d")

func _setup_mirror3d():
	# Find the Mirror3D addon node as a sibling under our parent (the tower).
	var parent := get_parent()
	if parent:
		_mirror3d = parent.get_node_or_null("Mirror3D")
	if not _mirror3d:
		push_warning("Mirror: Mirror3D sibling not found under parent %s" % parent)
		return
	print("Mirror: Mirror3D resolved at %s" % _mirror3d.get_path())

func _setup_mic_bus():
	# All mirrors share a single "MirrorMic" bus. If another mirror already
	# created it, reuse the existing capture effect rather than making a
	# duplicate-named bus (the mic player would resolve to the first one,
	# leaving other mirrors' captures silent).
	var existing_idx = AudioServer.get_bus_index("MirrorMic")
	if existing_idx != -1:
		_mic_bus_idx = existing_idx
		# Find the AudioEffectCapture on the existing bus
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
		# Mute the bus so the recorder doesn't hear themselves while recording.
		AudioServer.set_bus_mute(bus_count, true)
		_mic_bus_idx = bus_count

		# Reverb first so capture grabs the wet (reverbed) signal
		var reverb = AudioEffectReverb.new()
		reverb.room_size = 0.8
		reverb.damping = 0.5
		reverb.wet = 0.12
		AudioServer.add_bus_effect(_mic_bus_idx, reverb)

		# Capture after reverb — records the processed signal
		var capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_mic_bus_idx, capture)
		_audio_capture = capture

	# Mic player
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "MirrorMic"
	add_child(_mic_player)

	# Playback player
	_play_audio_player = AudioStreamPlayer.new()
	add_child(_play_audio_player)

func _on_body_entered(body: Node3D):
	if body is Player:
		_player_in_range = body
		_update_prompt()

#func _on_body_exited(body: Node3D):
	#if body == _player_in_range:
		#_player_in_range = null
		#if _state == State.RECORDING:
			#_stop_recording()
		#if _state != State.IDLE:
			#_state = State.IDLE
		#_update_prompt()

func _unhandled_input(event: InputEvent):
	if not _player_in_range:
		return
	var peer_id = _player_in_range.name.to_int()
	if multiplayer.get_unique_id() != peer_id:
		return
	if not event.is_action_pressed("player_action_1"):
		return

	match _state:
		State.IDLE:
			if _inbox.size() > 0:
				_start_playback(_inbox[0])
			else:
				_enter_selecting()
		State.SELECTING:
			if _selected_recipient > 0:
				_start_recording()
		State.RECORDING:
			_stop_recording()
		State.PREVIEW:
			_send_message()
		State.PLAYING:
			_stop_playback()

	_update_prompt()

func _input(event: InputEvent):
	if not _player_in_range:
		return
	var peer_id = _player_in_range.name.to_int()
	if multiplayer.get_unique_id() != peer_id:
		return

	# Q cancels in preview/selecting
	if event.is_action_pressed("avatar_recall"):
		if _state == State.PREVIEW:
			_recorded_message = null
			_state = State.IDLE
			_update_prompt()
			get_viewport().set_input_as_handled()
		elif _state == State.SELECTING:
			_state = State.IDLE
			_update_prompt()
			get_viewport().set_input_as_handled()

func _enter_selecting():
	_state = State.SELECTING
	_selected_recipient = -1

# ---------------------------------------------------------------------------
# RECORDING
# ---------------------------------------------------------------------------

func _start_recording():
	if not _player_in_range:
		return
	_state = State.RECORDING
	_record_xforms.clear()
	_record_anims = PackedStringArray()
	_record_audio = PackedFloat32Array()
	_record_sample_timer = 0.0
	_record_duration = 0.0

	# Anchor pose samples in the recorder's mirror local space. On playback
	# the recipient anchors their stage to their own mirror, so the ghost
	# ends up at the same offset from the recipient's mirror as the recorder
	# was from theirs — Mirror3D's reflection camera then renders it as if
	# it were a real reflection, parallax and all.
	if _mirror3d:
		_record_origin = _mirror3d.global_transform
	else:
		_record_origin = global_transform

	# Take an initial sample so the very first frame of playback is correct
	_capture_pose_sample()

	# Start mic capture
	_audio_capture.clear_buffer()
	_mic_player.play()

func _stop_recording():
	_mic_player.stop()
	_grab_audio()

	# Build message
	_recorded_message = MirrorMessage.new()
	_recorded_message.sender_peer_id = multiplayer.get_unique_id()
	_recorded_message.recipient_peer_id = _selected_recipient
	_recorded_message.ghost_xforms = _record_xforms.duplicate()
	_recorded_message.anim_states = _record_anims.duplicate()
	_recorded_message.pose_sample_rate = POSE_SAMPLE_RATE
	_recorded_message.audio_data = _record_audio.to_byte_array()
	_recorded_message.audio_sample_rate = int(AudioServer.get_mix_rate())
	_recorded_message.duration = _record_duration
	print("Mirror: recorded %d pose samples, %d audio samples, %.1fs" % [
		_record_xforms.size(), _record_audio.size(), _record_duration
	])

	_state = State.PREVIEW

func _process_recording(delta: float):
	_record_duration += delta
	_record_sample_timer += delta

	# Capture pose at fixed cadence
	while _record_sample_timer >= POSE_SAMPLE_INTERVAL:
		_record_sample_timer -= POSE_SAMPLE_INTERVAL
		_capture_pose_sample()

	# Drain mic buffer continuously
	_grab_audio()

	_update_prompt()

	if _record_duration >= MAX_RECORD_SECONDS:
		_stop_recording()
		_update_prompt()

func _capture_pose_sample():
	if not _player_in_range:
		return
	var model := _get_player_model(_player_in_range)
	if not model:
		return
	var stage_local := _record_origin.affine_inverse() * model.global_transform
	_record_xforms.append(stage_local)
	_record_anims.append(_get_current_anim_name(_player_in_range))

func _get_player_model(player: Player) -> Node3D:
	# Player.tscn exposes the model under "Model" — see player.tscn:25
	return player.get_node_or_null("Model") as Node3D

func _get_current_anim_name(player: Player) -> String:
	# Read the animation name straight off the current state node. This
	# avoids depending on the (currently broken) AnimationPlayer reference
	# on the live player; the state machine is the source of truth.
	if not player or not player._state_machine:
		return ""
	var state_name: StringName = player._state_machine.state
	if state_name == &"":
		return ""
	var state_node := player._state_machine.get_node_or_null(NodePath(state_name))
	if state_node and "animation_name" in state_node:
		return state_node.animation_name
	return ""

func _grab_audio():
	if _audio_capture:
		var avail = _audio_capture.get_frames_available()
		if avail > 0:
			var buf = _audio_capture.get_buffer(avail)
			for frame in buf:
				_record_audio.append(frame.x)  # Mono: take left channel

# ---------------------------------------------------------------------------
# SENDING
# ---------------------------------------------------------------------------

func _send_message():
	if not _recorded_message:
		return
	var msg = _recorded_message
	_recorded_message = null
	_state = State.IDLE

	GameState.deliver_mirror_message.rpc_id(
		msg.recipient_peer_id,
		msg.sender_peer_id,
		msg.recipient_peer_id,
		msg.ghost_xforms,
		msg.anim_states,
		msg.pose_sample_rate,
		msg.audio_data,
		msg.audio_sample_rate,
		msg.duration
	)

func _on_message_received(msg: MirrorMessage):
	_inbox.append(msg)
	_update_prompt()

# ---------------------------------------------------------------------------
# PLAYBACK
# ---------------------------------------------------------------------------

func _start_playback(msg: MirrorMessage):
	_state = State.PLAYING
	_play_message = msg
	_play_timer = 0.0
	_play_audio_pos = 0
	_play_last_anim = ""

	if not _mirror_viewport:
		push_warning("Mirror: cannot play, no SubViewport")
		return

	# Give the SubViewport its own World3D so the stage scene is isolated
	# from the live game world.
	_mirror_viewport.own_world_3d = true

	# Instance the stage and parent it under the SubViewport, then anchor
	# it to the mirror's world transform. With pose samples stored in
	# mirror-local space, this places the ghost at the same relative
	# position to *this* mirror as the recorder was to theirs.
	_play_stage = STAGE_SCENE.instantiate()
	_mirror_viewport.add_child(_play_stage)
	_play_stage.global_transform = _mirror3d.global_transform

	# Make sure Mirror3D's reflection camera is the one rendering — it lives
	# in the SubViewport's isolated World3D and Godot's auto-current pick is
	# unreliable when stage scenes also bring cameras along.
	if _mirror3d.mirror_camera:
		_mirror3d.mirror_camera.current = true
	_mirror3d.config_dirty = true

	# Locate the ghost and its AnimationPlayer. Ghost lives under StageOrigin
	# so the StageOrigin transform can be edited in mirror_stage.tscn to
	# adjust where the ghost appears relative to the mirror.
	_play_ghost = _play_stage.get_node_or_null("StageOrigin/Ghost") as Node3D
	if _play_ghost:
		_play_ghost_anim = _find_animation_player(_play_ghost)
		# Apply the first sample immediately so the very first frame is right
		if msg.ghost_xforms.size() > 0:
			_play_ghost.transform = msg.ghost_xforms[0]
		if msg.anim_states.size() > 0:
			_apply_anim_state(msg.anim_states[0])
		#print("Mirror: Ghost local=%s anim_player=%s mesh_count=%d" % [
			#_play_ghost.transform, _play_ghost_anim, _count_meshes(_play_ghost)
		#])
	else:
		push_warning("Mirror: stage scene has no Ghost node")

	# Build audio stream for playback
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
	print("Mirror: playing %d pose samples, %.1fs, %d audio samples" % [
		msg.ghost_xforms.size(), msg.duration, _play_audio_samples.size() if msg.audio_data.size() > 0 else 0
	])

func _stop_playback():
	_play_audio_player.stop()

	if _play_stage and is_instance_valid(_play_stage):
		_play_stage.queue_free()
	_play_stage = null
	_play_ghost = null
	_play_ghost_anim = null
	_play_last_anim = ""

	if _mirror_viewport:
		_mirror_viewport.own_world_3d = false
	if _mirror3d:
		# Re-assert the reflection camera and force a config rebuild so the
		# live reflection feed comes back cleanly after the world switch.
		_mirror3d.mirror_camera.current = true
		_mirror3d.config_dirty = true

	if _play_message in _inbox:
		_inbox.erase(_play_message)
	_play_message = null
	_state = State.IDLE

func _process_playback(delta: float):
	if not _play_message:
		return
	_play_timer += delta

	# Push audio samples to the generator buffer
	_push_audio_to_buffer()

	# Drive the ghost from pose samples, indexed by playback time so that
	# pose stays locked to audio even if the local frame rate hitches.
	if _play_ghost and _play_message.ghost_xforms.size() > 0:
		var idx := int(_play_timer * _play_message.pose_sample_rate)
		if idx >= _play_message.ghost_xforms.size():
			idx = _play_message.ghost_xforms.size() - 1
		_play_ghost.transform = _play_message.ghost_xforms[idx]
		if idx < _play_message.anim_states.size():
			_apply_anim_state(_play_message.anim_states[idx])

	if _play_timer >= _play_message.duration:
		_stop_playback()
		_update_prompt()

func _apply_anim_state(anim_name: String):
	if anim_name == _play_last_anim:
		return
	_play_last_anim = anim_name
	if _play_ghost_anim and anim_name != "" and _play_ghost_anim.has_animation(anim_name):
		_play_ghost_anim.play(anim_name)

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null

func _push_audio_to_buffer():
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

# ---------------------------------------------------------------------------
# MAIN LOOP / UI
# ---------------------------------------------------------------------------

func _process(delta: float):
	match _state:
		State.RECORDING:
			_process_recording(delta)
		State.PLAYING:
			_process_playback(delta)
		State.SELECTING:
			_process_selecting()

func _process_selecting():
	# TODO: raycast-based selection from diegetic mirror buttons
	var peers = multiplayer.get_peers()
	if peers.size() > 0 and _selected_recipient <= 0:
		_selected_recipient = peers[0]

func _get_peer_list() -> Array:
	var peers = []
	for p in multiplayer.get_peers():
		if p != multiplayer.get_unique_id():
			peers.append(p)
	return peers

func _update_prompt():
	if not interact_prompt:
		return
	match _state:
		State.IDLE:
			if _inbox.size() > 0:
				interact_prompt.text = "Press E to watch message (%d)" % _inbox.size()
				interact_prompt.modulate = Color(1, 0.8, 0.2)
			elif _player_in_range:
				interact_prompt.text = "Press E to record message"
				interact_prompt.modulate = Color(0.8, 0.5, 1)
			else:
				interact_prompt.text = "Mirror"
				interact_prompt.modulate = Color(0.8, 0.5, 1)
		State.SELECTING:
			if _selected_recipient > 0:
				interact_prompt.text = "Send to %d — Press E" % _selected_recipient
			else:
				interact_prompt.text = "Select recipient..."
			interact_prompt.modulate = Color(0.8, 0.5, 1)
		State.RECORDING:
			interact_prompt.text = "Recording... (%.1fs) Press E to stop" % _record_duration
			interact_prompt.modulate = Color(1, 0.2, 0.2)
		State.PREVIEW:
			interact_prompt.text = "E to send / Q to cancel"
			interact_prompt.modulate = Color(0.2, 1, 0.2)
		State.PLAYING:
			interact_prompt.text = "Playing... Press E to stop"
			interact_prompt.modulate = Color(1, 0.8, 0.2)
