class_name Actor extends CharacterBody3D

## Base class for all combat entities (players and enemies).
## Provides HP, damage, stagger, death, gravity, and animation hookup.
## Subtypes: PlayerActor (→ AvatarActor, OverlordActor), MinionActor.

signal hp_changed(new_hp: int)
signal died
## Fired AFTER take_damage applies the hit and any hitstop has been latched.
## Local-only consumers (damage numbers, hit-flash, FX) listen here. Gated by
## _is_resimulating() inside take_damage so resims don't double-fire.
signal took_damage(amount: int, source: Node)

## Hitstop hold-the-frame duration in physics ticks. ~67ms at netfox 30Hz.
## Authoritative source sets `hitstop_until_tick = NetworkTime.tick + this`
## inside take_damage; subclasses with a RollbackSynchronizer carry it as
## a state_property so resimulation reproduces the freeze deterministically.
const HITSTOP_TICKS: int = 2

## Damage threshold for picking the heavy hit-react clip in StaggerState.
## Below this, light reaction. Tuneable per-feel.
const HEAVY_REACT_THRESHOLD: int = 30

## Hit-flash decay rate (seconds). The flash intensity goes from 1.0 to 0.0
## over this duration via local _process; never enters rollback state.
const HIT_FLASH_DURATION: float = 0.15

var hp: int
var incoming_damage: int = 0
var faction: int = GameConstants.Faction.NEUTRAL
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## NetworkTime.tick at which hitstop ends. -1 = no hitstop active. Carried as
## a state_property on PlayerActor (rollback-synced); on MinionActor it's
## host-authoritative + piggybacked on the existing sync RPC. The state machine
## reads this in _rollback_tick / _physics_process to pause animation playback
## while NetworkTime.tick < hitstop_until_tick.
var hitstop_until_tick: int = -1

## Source actor of the most recent damage. Used by StaggerState to pick a hit-
## react clip variant (light/heavy) and by attackers for lifesteal-style
## consequences. Local; not synced.
var _last_damage_amount: int = 0

## Hit-flash uniform intensity. Walks the model meshes each frame while > 0,
## decays linearly. Local-only feedback — never gates damage. Shader contract
## documented in docs/technical/hit-flash-shader.md.
var _hit_flash_intensity: float = 0.0

## Per-actor map of dust kinds → scenes. Empty by default → _spawn_dust no-ops.
## Animation method tracks call _spawn_dust(&"footstep") / _spawn_dust(&"roll_dust")
## etc. Wire scenes per faction in the actor scene's inspector.
@export var dust_scenes: Dictionary[StringName, PackedScene] = {}

var _state_machine: RewindableStateMachine
var _model: Node3D
var _animation_player: AnimationPlayer

func _ready() -> void:
	add_to_group(&"actors")
	_state_machine = $RewindableStateMachine
	_model = _find_model_node()
	if _model:
		_animation_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	hp = get_max_hp()
	_state_machine.on_display_state_changed.connect(_on_display_state_changed)
	_state_machine.state = &"IdleState"
	_check_combat_components()

# --- Virtual methods (override in subtypes) ---

func get_max_hp() -> int:
	return 100

func get_attack_damage() -> int:
	return 25

func get_stagger_duration() -> float:
	return 0.5

func can_take_damage() -> bool:
	return hp > 0

# --- Faction / Perception ---

func is_hostile_to(other: Actor) -> bool:
	if other == null or other == self:
		return false
	return FactionRelations.is_hostile(faction, other.faction)

func can_see(other: Actor) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	return not other.is_stealthed_from(self)

func is_stealthed_from(_observer: Actor) -> bool:
	return false

# --- Combat ---

func take_damage(amount: int) -> void:
	if not can_take_damage():
		return
	hp = max(0, hp - amount)
	hp_changed.emit(hp)
	_last_damage_amount = amount
	# Hitstop is authority-set; on PlayerActor this is a state_property so
	# rollback resim reproduces it. MinionActor carries it via its own sync
	# RPC (see scripts/minion_manager.gd).
	hitstop_until_tick = NetworkTime.tick + HITSTOP_TICKS
	if hp <= 0:
		_die()
	else:
		try_stagger()
	# Local-only feedback. Skipped during resim so spark/flash/numbers don't
	# double-fire. See docs/technical/netfox-reference.md §5.
	if not _is_resimulating():
		_hit_flash_intensity = 1.0
		took_damage.emit(amount, null)

func _die() -> void:
	died.emit()
	_state_machine.transition(&"DeathState")

# --- Action gating (see docs/systems/action-gating.md) ---

## Current state as ActorState, or null if the state machine has no matching
## child. Helper for the try_* gate functions.
func _current_state() -> ActorState:
	return _state_machine.get_node_or_null(String(_state_machine.state)) as ActorState

## Request a transition to `new_state`. Blocked if the current state is
## action_locked and the target isn't in its cancel_whitelist. Returns true
## iff the transition went through.
func try_transition(new_state: StringName) -> bool:
	var current := _current_state()
	if current and current.action_locked and new_state not in current.cancel_whitelist:
		return false
	_state_machine.transition(new_state)
	return true

## Request a stagger transition. Blocked if the current state is stagger_immune.
## Called by take_damage and any external stagger source (ability effects, boss
## rage, etc.). Returns true iff the stagger went through.
func try_stagger() -> bool:
	var current := _current_state()
	if current and current.stagger_immune:
		return false
	_state_machine.transition(&"StaggerState")
	return true

# --- Animation-method-track forwarders ---
# Bound to the Actor root so AnimationPlayer Call Method Tracks can target a
# stable path. Each forwards to the currently-active state; if the state
# transitioned mid-animation the forwarded call no-ops rather than touching
# the wrong state.
func lock_action() -> void:
	var s := _current_state()
	if s:
		s.lock_action()

func unlock_action() -> void:
	var s := _current_state()
	if s:
		s.unlock_action()

func enable_stagger_immunity() -> void:
	var s := _current_state()
	if s:
		s.enable_stagger_immunity()

func disable_stagger_immunity() -> void:
	var s := _current_state()
	if s:
		s.disable_stagger_immunity()

# --- Physics helpers ---

func apply_gravity(delta: float) -> void:
	velocity.y -= gravity * delta

func force_update_is_on_floor() -> void:
	var old_velocity = velocity
	velocity *= 0
	move_and_slide()
	velocity = old_velocity

# --- Animation ---

func _on_display_state_changed(_old_state: RewindableState, new_state: RewindableState) -> void:
	# Reset the action-gating flags on entry. A missed "turn off" method key
	# at the end of the previous animation self-recovers here rather than
	# permanently locking the actor. See docs/systems/action-gating.md.
	var actor_state = new_state as ActorState
	if actor_state:
		actor_state.action_locked = false
		actor_state.stagger_immune = false
	if not _animation_player:
		return
	if actor_state and actor_state.animation_name != "":
		_animation_player.play(actor_state.animation_name)

# --- Rollback ---
# Called by RollbackSynchronizer for PlayerActor.
# MinionActor applies gravity in _physics_process instead.

func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	if incoming_damage > 0:
		take_damage(incoming_damage)
		incoming_damage = 0
	force_update_is_on_floor()
	if not is_on_floor():
		apply_gravity(delta)
	_apply_hitstop_animation_pause()

# --- Rollback helpers ---

## True iff netfox is currently resimulating a rolled-back tick. Use this to
## gate local-only side effects (spark spawning, camera shake, damage numbers)
## so resimulation doesn't stack them. The netfox API is is_rollback() — this
## helper makes the call sites read as intent rather than implementation.
func _is_resimulating() -> bool:
	return NetworkRollback.is_rollback()

## Pause animation playback while NetworkTime.tick < hitstop_until_tick by
## setting the AnimationPlayer's speed_scale. Reset to 1.0 once the freeze
## window ends. The check runs every rollback tick (PlayerActor) and every
## physics frame (MinionActor) so resim reproduces the same speed_scale state
## the host authored. No side effects when the actor has no animation player.
func _apply_hitstop_animation_pause() -> void:
	if not _animation_player:
		return
	if hitstop_until_tick > 0 and NetworkTime.tick < hitstop_until_tick:
		_animation_player.speed_scale = 0.0
	elif _animation_player.speed_scale == 0.0:
		# Only restore if we're the ones who paused it. Other systems that want
		# to control speed_scale (slow-mo, charge buildup) should set it to a
		# non-zero value; this branch deliberately re-asserts 1.0 when leaving
		# hitstop so a forgotten-to-restore window self-recovers.
		_animation_player.speed_scale = 1.0

# --- Local presentation feedback (hit flash + dust) ---

func _process(delta: float) -> void:
	if _hit_flash_intensity <= 0.0:
		return
	# Linear decay; the visible flash hits a uniform of the same value on
	# any ShaderMaterial that opts into the contract. Plain materials no-op.
	_hit_flash_intensity = max(0.0, _hit_flash_intensity - delta / HIT_FLASH_DURATION)
	_set_hit_flash_intensity(_hit_flash_intensity)

## Walks the meshes under _model and pokes the `hit_flash_intensity` uniform
## on any mesh whose material is a ShaderMaterial that exposes the uniform.
## Plain StandardMaterial3D meshes are skipped silently — opt-in by author.
##
## Shader contract:
##   shader_type spatial;
##   uniform float hit_flash_intensity = 0.0;
##   void fragment() { ALBEDO += vec3(hit_flash_intensity); }
##
## Full example: docs/technical/hit-flash-shader.md.
func _set_hit_flash_intensity(value: float) -> void:
	if _model == null:
		return
	for mi in _walk_mesh_instances(_model):
		_apply_flash_to_mesh_instance(mi, value)

func _apply_flash_to_mesh_instance(mi: MeshInstance3D, value: float) -> void:
	# Surface-override materials beat the mesh's own material; check both so
	# the flash works whether the artist drove it from the model or the scene.
	for i in mi.get_surface_override_material_count():
		var override_mat := mi.get_surface_override_material(i) as ShaderMaterial
		if override_mat:
			override_mat.set_shader_parameter(&"hit_flash_intensity", value)
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var surface_mat := mi.mesh.surface_get_material(i) as ShaderMaterial
		if surface_mat:
			surface_mat.set_shader_parameter(&"hit_flash_intensity", value)

func _walk_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n as MeshInstance3D)
		for c in n.get_children():
			stack.append(c)
	return out

## Animation method-track entrypoint. Animations call _spawn_dust(&"footstep")
## etc. to spawn the matching scene from `dust_scenes`. Empty dict → silent
## no-op; fully resimulation-safe (gated by _is_resimulating before spawn).
func _spawn_dust(kind: StringName) -> void:
	if _is_resimulating():
		return
	if not dust_scenes.has(kind):
		return
	var scene: PackedScene = dust_scenes[kind]
	if scene == null:
		return
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return
	var parent := get_tree().current_scene
	if parent == null:
		instance.queue_free()
		return
	parent.add_child(instance)
	instance.global_position = global_position

# --- Model slot resolution ---

## Returns the "Model" container from actor.tscn. Subclass scenes must drop
## their visual (e.g. an imported GLB instance) as a child of this node.
func _find_model_node() -> Node3D:
	return get_node_or_null(^"Model") as Node3D

# --- Missing-component warning ---
# Development aid: a yellow ⚠ floats above any actor subtype that lacks an
# expected combat component. AttackHitbox is expected iff the state machine
# has an AttackState; Hurtbox is always expected. The warning disappears
# the moment the missing component is added to the scene.

func _check_combat_components() -> void:
	var missing: Array[String] = []
	if _state_machine.has_node(^"AttackState") and get_node_or_null(^"%AttackHitbox") == null:
		missing.append("AttackHitbox")
	if get_node_or_null(^"%Hurtbox") == null:
		missing.append("Hurtbox")
	if missing.is_empty():
		return
	var warning := Label3D.new()
	warning.name = "_MissingComponentWarning"
	warning.text = "⚠ Missing: %s" % ", ".join(missing)
	warning.modulate = Color(1.0, 0.85, 0.1)
	warning.outline_modulate = Color(0.15, 0.1, 0.0)
	warning.outline_size = 8
	warning.font_size = 48
	warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	warning.no_depth_test = true
	warning.fixed_size = true
	warning.position = Vector3(0, 3.0, 0)
	add_child(warning)
	push_warning("[%s] missing combat component(s): %s" % [name, ", ".join(missing)])
