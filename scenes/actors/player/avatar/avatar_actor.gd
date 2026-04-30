class_name AvatarActor extends PlayerActor

## The shared Paladin vessel. Dormant when unclaimed.
## When a player claims it, their input drives this entity
## while their Overlord body stays idle in the tower.

const WATCHER_ORB_DISTANCE: float = 2.5
const WATCHER_ORB_HEIGHT: float = 2.0
const DEATH_TRANSFER_DELAY: float = 2.0
## Legacy single-point respawn. Kept for backwards compatibility with code paths
## that may still read it; new code consults `RESPAWN_POSITIONS` via
## `_pick_respawn_position`. Designers should override the array in subclassed
## scenes once the map has multiple safe spawn anchors.
const RESPAWN_POSITION: Vector3 = Vector3(0.1, 0.04, -0.06)
## Tier F — anti-camp spawn-point variation. The picker scores each candidate
## by min-distance to any alive opponent and picks the highest. Currently
## seeded with the legacy origin in slot 0 plus three offset candidates so the
## picker has something to choose between even before the map adds dedicated
## anchors. Designers should replace this with map-authored spawn markers
## (TODO: per-tower spawn points exported from the world scene).
const RESPAWN_POSITIONS: Array[Vector3] = [
	Vector3(0.1, 0.04, -0.06),
	Vector3(8.0, 0.04, 8.0),
	Vector3(-8.0, 0.04, 8.0),
	Vector3(0.0, 0.04, -10.0),
]
## Ticks between death and respawn. ~3s at netfox 30Hz — long enough for a
## death animation to read, short enough that 4-way PvP doesn't stall.
const RESPAWN_DELAY_TICKS: int = 90
## Camera-shake feel on hit received. Larger than the hit-dealt punch in
## attack_state.gd because the victim experience needs more weight; both are
## clamped at AvatarCamera.SHAKE_AMPLITUDE_CAP.
const HIT_TAKEN_SHAKE_AMPLITUDE: float = 0.12
const HIT_TAKEN_SHAKE_DURATION: float = 0.25
const WATCHER_ORB_SIZE: Vector3 = Vector3(0.3, 0.3, 0.3)
const WATCHER_ORB_COLOR: Color = Color(0.4, 0.6, 1.0, 0.7)
const WATCHER_ORB_EMISSION: Color = Color(0.4, 0.6, 1.0)
const WATCHER_ORB_EMISSION_ENERGY: float = 2.0

@onready var avatar_input: AvatarInput = $AvatarInput
@onready var avatar_camera: AvatarCamera = $AvatarCamera
@onready var watcher_label: Label3D = $WatcherLabel
@onready var targeting: Targeting = $Targeting

var controlling_peer_id: int = -1
var is_dormant: bool = true
var god_mode: bool = false
var _watcher_orbs: Dictionary[int, MeshInstance3D] = {}
# Tracks who dealt the killing blow for hostile takeover
var last_damage_source_peer: int = -1
# Faction abilities
var abilities: AvatarAbilities
# --- Tier E: Faction-driven combat stat overrides ---
# Resolved on `activate(peer_id)` from `FactionData.get_profile(faction)`.
# Persist for the lifetime of the claim. State scripts read these to
# customize per-faction feel.
var _max_hp_override: int = -1
var _base_damage_override: int = -1
var _attack_speed_mult: float = 1.0
var _roll_distance_override: float = -1.0
var _roll_iframe_ticks_override: int = -1
var _animation_library_override: String = ""
# The CaptureChannel currently locking this avatar (null when not channeling).
# Read by ChannelState; written by CaptureChannel when the channel starts/ends.
var active_channel: CaptureChannel = null

func _ready() -> void:
	super()
	_set_dormant_visual(true)
	GameState.watcher_count_changed.connect(_on_watcher_count_changed)
	_update_watcher_label(0)
	# Create abilities node
	abilities = AvatarAbilities.new()
	abilities.name = "AvatarAbilities"
	add_child(abilities)
	# Hit-received camera shake — local feedback for the controlling peer.
	# Actor.took_damage is already gated against rollback resimulation.
	took_damage.connect(_on_took_damage)

func _on_took_damage(_amount: int, _source: Node) -> void:
	if controlling_peer_id != multiplayer.get_unique_id():
		return
	if avatar_camera:
		avatar_camera.shake(HIT_TAKEN_SHAKE_AMPLITUDE, HIT_TAKEN_SHAKE_DURATION)

# --- Combat overrides ---

## Tier E — overrides the Actor base 100. Resolved from FactionProfile.avatar_hp
## at claim time; falls back to base when no profile is configured.
func get_max_hp() -> int:
	if _max_hp_override > 0:
		return _max_hp_override
	return super()

## Tier E — overrides the Actor base 25. Resolved from
## FactionProfile.avatar_base_damage at claim time.
func get_attack_damage() -> int:
	if _base_damage_override > 0:
		return _base_damage_override
	return super()

## Tier E — exposed for attack states' speed_scale tweak. 1.0 = no change.
func get_attack_speed_mult() -> float:
	return _attack_speed_mult

## Tier E — exposed for RollState. Returns -1.0 when unset (use defaults).
func get_roll_distance_override() -> float:
	return _roll_distance_override

## Tier E — exposed for RollState. Returns -1 when unset (use defaults).
func get_roll_iframe_ticks_override() -> int:
	return _roll_iframe_ticks_override

func can_take_damage() -> bool:
	if god_mode or is_dormant:
		return false
	return hp > 0

## No take_damage override needed — Actor.take_damage handles it.
## Damage from outside rollback (enemies) goes through incoming_damage instead.

## Called by host (enemy/minion attacks) to apply damage through the rollback owner,
## since incoming_damage is a state-synced property owned by the controlling peer.
@rpc("any_peer", "call_local", "reliable")
func apply_incoming_damage(amount: int, source_peer: int) -> void:
	incoming_damage += amount
	last_damage_source_peer = source_peer

func _die() -> void:
	super()
	if multiplayer.is_server():
		get_tree().create_timer(DEATH_TRANSFER_DELAY).timeout.connect(_on_death_transfer)

func _on_death_transfer() -> void:
	if not multiplayer.is_server():
		return
	# Hostile takeover: if a minion killed the Avatar, its owner becomes Avatar
	if last_damage_source_peer > 0 and last_damage_source_peer != controlling_peer_id:
		var old = GameState.avatar_peer_id
		GameState._set_avatar.rpc(-1)
		GameState._set_avatar.rpc(last_damage_source_peer)
		_respawn.rpc()
		last_damage_source_peer = -1
		return
	# Influence fallback: highest influence peer takes over
	var best = GameState.get_highest_influence_peer()
	if best > 0 and best != controlling_peer_id:
		var old = GameState.avatar_peer_id
		GameState._set_avatar.rpc(-1)
		GameState._set_avatar.rpc(best)
		_respawn.rpc()
		last_damage_source_peer = -1
		return
	# Default: round-robin
	GameState.release_avatar()
	_respawn.rpc()
	last_damage_source_peer = -1

@rpc("authority", "call_local", "reliable")
func _respawn() -> void:
	# Tier F — schedule the actual respawn after RESPAWN_DELAY_TICKS so the
	# new owner has a beat to orient. The avatar stays in DeathState (already
	# entered host-side via _die → state_machine.transition(DeathState)) until
	# `_do_respawn` fires. Host-only timer; clients will see the eventual
	# state_property + transform sync once the host respawns.
	if multiplayer.is_server():
		# Convert ticks → seconds via netfox ticktime so the timer matches the
		# rollback clock. Using a tree timer is fine here — the respawn itself
		# is fully host-authoritative; clients receive the final position +
		# state via the standard rollback channel.
		var delay: float = float(RESPAWN_DELAY_TICKS) * NetworkTime.ticktime
		get_tree().create_timer(delay).timeout.connect(_do_respawn)
	# else: clients no-op; the host's _do_respawn will broadcast.

func _do_respawn() -> void:
	## Host-side respawn body. Picks a spawn point furthest from any alive
	## opponent, restores HP, grants brief invuln, and transitions to Idle.
	## RPCs to clients with the resolved position + state changes.
	if not multiplayer.is_server():
		return
	var spawn_pos: Vector3 = _pick_respawn_position(controlling_peer_id)
	_apply_respawn.rpc(spawn_pos, NetworkTime.tick + RESPAWN_INVULN_TICKS)

@rpc("authority", "call_local", "reliable")
func _apply_respawn(spawn_pos: Vector3, invuln_until_tick: int) -> void:
	# Body of the respawn — runs on every peer so transform / hp / invuln
	# match. The state_property `respawn_invuln_until_tick` already syncs via
	# rollback, but we set it directly here so the assignment lands at the
	# same wall-clock moment as the position teleport (avoids a one-tick
	# window where the new avatar exists at the new spot without invuln).
	global_position = spawn_pos
	velocity = Vector3.ZERO
	hp = get_max_hp()
	hp_changed.emit(hp)
	respawn_invuln_until_tick = invuln_until_tick
	_state_machine.transition(&"IdleState")

## Tier F — anti-camp spawn picker. Scores each candidate in `RESPAWN_POSITIONS`
## by the minimum distance to any alive opponent (avatars in the actors group
## with hp > 0, excluding self and the new owner). Returns the highest-scoring
## candidate. With no opponents alive, returns slot 0 deterministically.
func _pick_respawn_position(_new_owner_peer_id: int) -> Vector3:
	if RESPAWN_POSITIONS.is_empty():
		return RESPAWN_POSITION
	# Gather alive opponent positions. Avatar is shared, but additional
	# AvatarActors / hostile minions could exist in future; we treat any
	# living non-self actor as a threat. Iterating the actors group avoids
	# coupling to MinionManager / scene-specific paths.
	var threat_positions: Array[Vector3] = []
	for n in get_tree().get_nodes_in_group(&"actors"):
		var a := n as Actor
		if a == null or a == self:
			continue
		if not is_instance_valid(a):
			continue
		if a.hp <= 0:
			continue
		threat_positions.append(a.global_position)
	if threat_positions.is_empty():
		return RESPAWN_POSITIONS[0]
	var best: Vector3 = RESPAWN_POSITIONS[0]
	var best_score: float = -1.0
	for candidate in RESPAWN_POSITIONS:
		var min_d: float = INF
		for tp in threat_positions:
			var d: float = candidate.distance_to(tp)
			if d < min_d:
				min_d = d
		if min_d > best_score:
			best_score = min_d
			best = candidate
	return best

# --- Activation ---

func activate(peer_id: int) -> void:
	controlling_peer_id = peer_id
	is_dormant = false
	avatar_input.set_controller(peer_id)
	avatar_camera.activate(peer_id)
	rollback_synchronizer.process_settings()
	_set_dormant_visual(false)
	# Inherit the controlling peer's faction so hostility checks work
	# (e.g. MinionState.find_hostile_target treats NEUTRAL-vs-NEUTRAL as ALLIED).
	faction = GameState.get_faction(peer_id)
	# Tier E — apply faction combat stat overrides BEFORE seeding hp from
	# get_max_hp(), so the new owner's HP cap reflects their faction.
	_apply_faction_combat_stats(FactionData.get_profile(faction))
	hp = get_max_hp()
	hp_changed.emit(hp)
	# Reset Tier E meters so the new owner doesn't inherit the previous
	# claim's ultimate progress.
	ultimate_charge = 0
	if abilities:
		abilities.setup(self, faction)

## Tier E — applies a FactionProfile's combat stats to this avatar. Idempotent;
## safe to call multiple times. Pass null to clear overrides (deactivate path).
func _apply_faction_combat_stats(profile: FactionProfile) -> void:
	if profile == null:
		_max_hp_override = -1
		_base_damage_override = -1
		_attack_speed_mult = 1.0
		_roll_distance_override = -1.0
		_roll_iframe_ticks_override = -1
		_animation_library_override = ""
		_faction_passive = null
		max_posture = 100
		return
	_max_hp_override = profile.avatar_hp
	_base_damage_override = profile.avatar_base_damage
	_attack_speed_mult = profile.attack_speed_mult
	_roll_distance_override = profile.roll_distance
	_roll_iframe_ticks_override = profile.roll_iframe_ticks
	_animation_library_override = profile.animation_library_name
	# Faction passive — cached on the actor so passive hooks resolve without
	# round-tripping through FactionData every hit.
	set_faction_passive(profile.passive)
	# Tier C posture cap is exported on Actor; faction profile overrides at claim.
	max_posture = profile.max_posture

func deactivate() -> void:
	controlling_peer_id = -1
	is_dormant = true
	faction = GameConstants.Faction.NEUTRAL
	# Tier E — clear faction stat overrides so the dormant avatar doesn't
	# carry the last claimer's tuning into the next claim's pre-activate
	# window.
	_apply_faction_combat_stats(null)
	ultimate_charge = 0
	avatar_input.set_controller(-1)
	avatar_camera.deactivate()
	rollback_synchronizer.process_settings()
	_set_dormant_visual(true)
	velocity = Vector3.ZERO
	# Drop any active lock when the avatar is unclaimed — the reticle and
	# camera-follow are tied to the previous controlling peer.
	if targeting:
		targeting.release()
	_state_machine.transition(&"IdleState")

func _set_dormant_visual(dormant: bool) -> void:
	if _model:
		_model.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if controlling_peer_id != multiplayer.get_unique_id():
		return
	if not avatar_input.input_enabled:
		return
	# During a capture channel, ignore every avatar input. Pause menu still
	# works (handled elsewhere) and the interact key is consumed by the
	# focused Interactable, which routes it to capture_channel.request_cancel().
	if active_channel != null and active_channel.is_active():
		return
	if event.is_action_pressed("cancel"):
		GameState.request_recall_avatar()
	if abilities:
		if event.is_action_pressed("secondary_ability"):
			abilities.activate_ability(0)
		elif event.is_action_pressed("item_1"):
			abilities.activate_ability(1)
		elif event.is_action_pressed("item_2"):
			abilities.activate_ability(2)
		elif InputMap.has_action("ultimate") and event.is_action_pressed("ultimate"):
			# Tier E — slot 4 / ultimate. Charge-gated rather than cooldown-
			# gated; AvatarAbilities.activate_ability does the
			# `is_ultimate_ready()` check before firing.
			abilities.activate_ability(AvatarAbilities.SLOT_ULTIMATE)
	# Local-only targeting input. These never enter netfox state — see
	# scripts/combat/targeting.gd for the rationale.
	if targeting:
		if event.is_action_pressed("toggle_lock"):
			targeting.toggle_lock()
		elif event.is_action_pressed("cycle_target_left"):
			if targeting.is_locked:
				targeting.cycle_target(-1)
		elif event.is_action_pressed("cycle_target_right"):
			if targeting.is_locked:
				targeting.cycle_target(1)

# --- Watchers ---

func _on_watcher_count_changed(count: int) -> void:
	_update_watcher_label(count)

func _update_watcher_label(count: int) -> void:
	if not watcher_label:
		return
	if count > 0:
		watcher_label.visible = true
		watcher_label.text = "(%d watching)" % count
	else:
		watcher_label.visible = false

func _create_watcher_orb() -> MeshInstance3D:
	var orb = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = WATCHER_ORB_SIZE
	orb.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = WATCHER_ORB_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = WATCHER_ORB_EMISSION
	mat.emission_energy_multiplier = WATCHER_ORB_EMISSION_ENERGY
	orb.set_surface_override_material(0, mat)
	add_child(orb)
	return orb

func _process(delta: float) -> void:
	# Run the base actor frame (hit-flash decay etc.) before our watcher logic.
	super(delta)
	var positions = GameState.watcher_positions
	for peer_id in _watcher_orbs.keys():
		if peer_id not in positions:
			_watcher_orbs[peer_id].queue_free()
			_watcher_orbs.erase(peer_id)
	for peer_id in positions:
		if peer_id not in _watcher_orbs:
			_watcher_orbs[peer_id] = _create_watcher_orb()
		var cam_pos: Vector3 = positions[peer_id]
		var dir = (cam_pos - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			dir = dir.normalized()
		else:
			dir = Vector3.FORWARD
		_watcher_orbs[peer_id].position = dir * WATCHER_ORB_DISTANCE + Vector3(0, WATCHER_ORB_HEIGHT, 0)
