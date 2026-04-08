extends Area3D

## The Mirror — record and send video messages to rival Overlords.
## Uses the tower's existing SubViewport/Sprite3D for the mirror surface.
## Diegetic UI: buttons are Area3D children positioned on the mirror.

@export var interact_prompt: Label3D

var _mirror3d: Node3D  # The Mirror3D addon node (typed loosely to avoid class load issues)
# Convenience accessors into the addon (which has its own per-instance material)
var _mirror_viewport: SubViewport:
	get: return _mirror3d.mirror_viewport if _mirror3d else null
var _mirror_quad: MeshInstance3D:
	get: return _mirror3d.mirror_quad if _mirror3d else null
var _mirror_camera: Camera3D  # The reflection camera (Mirror3D's main one)
var _recording_camera: Camera3D  # Sibling camera used while recording

enum State { IDLE, SELECTING, RECORDING, PREVIEW, PLAYING }

var _player_in_range: Player = null
var _state: State = State.IDLE

# Recording
var _record_frames: Array[PackedByteArray] = []
var _record_audio: PackedFloat32Array = PackedFloat32Array()
var _record_timer: float = 0.0
var _record_duration: float = 0.0
const FRAME_INTERVAL := 1.0 / 15.0  # 15 fps
const MAX_RECORD_SECONDS := 10.0
const FRAME_MAX_DIMENSION := 480
const FRAME_JPEG_QUALITY := 0.85

# Audio capture
var _mic_player: AudioStreamPlayer
var _audio_capture: AudioEffectCapture
var _mic_bus_idx: int = -1

# Playback
var _play_message: MirrorMessage = null
var _play_frame_idx: int = 0
var _play_timer: float = 0.0
var _play_audio_player: AudioStreamPlayer
var _play_audio_samples: PackedFloat32Array
var _play_audio_pos: int = 0

# Pending messages (received from other players)
var _inbox: Array[MirrorMessage] = []
var _original_mirror_texture: Texture2D = null

# Selected recipient for sending
var _selected_recipient: int = -1
var _recorded_message: MirrorMessage = null

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
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
	# Cache references to the two cameras inside the Mirror3D's SubViewport
	_mirror_camera = _mirror3d.get_node_or_null("Viewport/Camera")
	_recording_camera = _mirror3d.get_node_or_null("Viewport/RecordingCamera")
	print("Mirror: Mirror3D resolved at %s (mirror_cam=%s rec_cam=%s)" % [
		_mirror3d.get_path(), _mirror_camera, _recording_camera
	])

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

func _on_body_exited(body: Node3D):
	if body == _player_in_range:
		_player_in_range = null
		if _state == State.RECORDING:
			_stop_recording()
		if _state != State.IDLE:
			_state = State.IDLE
		_update_prompt()

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
			# Selected recipient is set by _process raycast
			if _selected_recipient > 0:
				_start_recording()
		State.RECORDING:
			_stop_recording()
		State.PREVIEW:
			# E confirms send
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

func _start_recording():
	_state = State.RECORDING
	_record_frames.clear()
	_record_audio = PackedFloat32Array()
	_record_timer = 0.0
	_record_duration = 0.0

	# Switch the SubViewport to render from RecordingCamera instead of the
	# reflection camera. This both gives us the right POV for the recording
	# AND turns the mirror surface into a live preview while recording.
	if _recording_camera and _mirror3d:
		# Static "selfie" framing: sit at the mirror, facing out the player side.
		# Default Camera3D forward is local -Z, which matches this scene's setup
		# (player approaches from the -Z side of the Mirror3D node). If the
		# mirror is reoriented in the editor and the camera ends up facing the
		# wrong way, rotate the Mirror3D node 180° around its Y axis.
		_recording_camera.global_transform = _mirror3d.global_transform
		_recording_camera.current = true

	# Start mic capture
	_audio_capture.clear_buffer()
	_mic_player.play()

func _stop_recording():
	_mic_player.stop()

	# Restore the reflection camera as the SubViewport's active camera
	if _mirror_camera:
		_mirror_camera.current = true

	# Tell the addon to reapply its config so the reflection feed resumes cleanly.
	if _mirror3d:
		_mirror3d.config_dirty = true

	# Grab remaining audio
	_grab_audio()

	# Build message
	_recorded_message = MirrorMessage.new()
	_recorded_message.sender_peer_id = multiplayer.get_unique_id()
	_recorded_message.recipient_peer_id = _selected_recipient
	_recorded_message.frames = _record_frames.duplicate()
	_recorded_message.audio_data = _float32_to_bytes(_record_audio)
	_recorded_message.sample_rate = int(AudioServer.get_mix_rate())
	_recorded_message.duration = _record_duration
	_recorded_message.frame_rate = 1.0 / FRAME_INTERVAL
	print("Mirror: recorded %d frames, %d audio samples, %.1fs" % [_record_frames.size(), _record_audio.size(), _record_duration])

	_state = State.PREVIEW

func _grab_audio():
	if _audio_capture:
		var avail = _audio_capture.get_frames_available()
		if avail > 0:
			var buf = _audio_capture.get_buffer(avail)
			var nonzero := 0
			for frame in buf:
				if frame.x != 0.0:
					nonzero += 1
				_record_audio.append(frame.x)  # Mono: take left channel
			if nonzero == 0 and buf.size() > 0:
				print("Mirror: grabbed %d frames, ALL ZERO" % buf.size())

func _float32_to_bytes(samples: PackedFloat32Array) -> PackedByteArray:
	return samples.to_byte_array()

func _bytes_to_float32(data: PackedByteArray) -> PackedFloat32Array:
	return data.to_float32_array()

func _send_message():
	if not _recorded_message:
		return
	var msg = _recorded_message
	_recorded_message = null
	_state = State.IDLE

	# Route through GameState autoload so the RPC path is consistent
	GameState.deliver_mirror_message.rpc_id(msg.recipient_peer_id,
		msg.sender_peer_id,
		msg.recipient_peer_id,
		msg.frames,
		msg.audio_data,
		msg.duration,
		msg.sample_rate,
		msg.frame_rate
	)

func _on_message_received(msg: MirrorMessage):
	_inbox.append(msg)
	_update_prompt()

func _start_playback(msg: MirrorMessage):
	_state = State.PLAYING
	_play_message = msg
	_play_frame_idx = 0
	_play_timer = 0.0
	_play_audio_pos = 0

	print("Mirror: _start_playback frames=%d duration=%.2f mirror3d=%s quad=%s" % [
		msg.frames.size(), msg.duration, _mirror3d, _mirror_quad
	])

	# Save original mirror texture so we can restore it
	if _mirror_quad and not _original_mirror_texture:
		var mat = _mirror_quad.get_active_material(0)
		if mat:
			_original_mirror_texture = mat.get_shader_parameter("mirror_texture_linear")
			print("Mirror: saved original texture: %s" % _original_mirror_texture)

	# Build audio stream for playback
	if msg.audio_data.size() > 0:
		_play_audio_samples = _bytes_to_float32(msg.audio_data)
		var generator = AudioStreamGenerator.new()
		generator.mix_rate = msg.sample_rate
		generator.buffer_length = 0.5
		_play_audio_player.stream = generator
		_play_audio_player.volume_db = 0.0
		_play_audio_player.bus = "Master"
		_play_audio_player.play()
		# Diagnostic: peak amplitude of samples
		var peak := 0.0
		for s in _play_audio_samples:
			var a = abs(s)
			if a > peak:
				peak = a
		print("Mirror: playing %d audio samples at %dhz, duration=%.2fs, peak=%f, player.playing=%s" % [_play_audio_samples.size(), msg.sample_rate, msg.duration, peak, _play_audio_player.playing])
		# Pre-fill the buffer immediately so the generator doesn't underrun
		_push_audio_to_buffer()
	else:
		print("Mirror: no audio data in message")

func _stop_playback():
	_play_audio_player.stop()
	if _play_message in _inbox:
		_inbox.erase(_play_message)
	_play_message = null
	_state = State.IDLE

	# Restore mirror to live viewport feed
	if _mirror_quad and _original_mirror_texture:
		var mat = _mirror_quad.get_active_material(0)
		if mat:
			mat.set_shader_parameter("mirror_texture_linear", _original_mirror_texture)
		_original_mirror_texture = null

func _process(delta: float):
	match _state:
		State.RECORDING:
			_process_recording(delta)
		State.PLAYING:
			_process_playback(delta)
		State.SELECTING:
			_process_selecting()

func _process_recording(delta: float):
	_record_duration += delta
	_record_timer += delta

	# Capture frame at interval
	if _record_timer >= FRAME_INTERVAL:
		_record_timer -= FRAME_INTERVAL
		if _mirror_viewport:
			var image = _mirror_viewport.get_texture().get_image()
			# Scale down proportionally if either dimension exceeds the cap,
			# preserving the mirror's aspect ratio.
			var w := image.get_width()
			var h := image.get_height()
			if w > FRAME_MAX_DIMENSION or h > FRAME_MAX_DIMENSION:
				var scale: float = float(FRAME_MAX_DIMENSION) / float(maxi(w, h))
				image.resize(int(w * scale), int(h * scale))
			var jpg = image.save_jpg_to_buffer(FRAME_JPEG_QUALITY)
			_record_frames.append(jpg)

	# Capture audio
	_grab_audio()

	_update_prompt()

	# Auto-stop at max duration
	if _record_duration >= MAX_RECORD_SECONDS:
		_stop_recording()
		_update_prompt()

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

func _process_playback(delta: float):
	if not _play_message:
		return
	_play_timer += delta

	# Push audio samples to the generator buffer
	_push_audio_to_buffer()

	# Show current frame on mirror viewport
	var frame_idx = int(_play_timer * _play_message.frame_rate)
	if frame_idx < _play_message.frames.size():
		if frame_idx != _play_frame_idx:
			_play_frame_idx = frame_idx
			var image = Image.new()
			image.load_jpg_from_buffer(_play_message.frames[frame_idx])
			if _mirror_quad and image:
				var tex = ImageTexture.create_from_image(image)
				var mat = _mirror_quad.get_active_material(0)
				if mat:
					mat.set_shader_parameter("mirror_texture_linear", tex)
					print("Mirror: showing frame %d on %s" % [frame_idx, _mirror_quad.get_path()])
	elif _play_timer >= _play_message.duration:
		_stop_playback()
		_update_prompt()

func _process_selecting():
	# Determine which player the reticle is pointing at
	# For now, cycle through available peers
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
