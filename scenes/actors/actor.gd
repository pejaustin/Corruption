class_name Actor extends CharacterBody3D

## Base class for all combat entities (players and enemies).
## Provides HP, damage, stagger, death, gravity, and animation hookup.
## Subtypes: PlayerActor (→ AvatarActor, OverlordActor), MinionActor.

signal hp_changed(new_hp: int)
signal died

var hp: int
var incoming_damage: int = 0
var faction: int = GameConstants.Faction.NEUTRAL
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

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
	if hp <= 0:
		_die()
	else:
		try_stagger()

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
