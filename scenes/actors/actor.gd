class_name Actor extends CharacterBody3D

## Base class for all combat entities (players and enemies).
## Provides HP, damage, stagger, death, gravity, and animation hookup.
## Subtypes: PlayerActor, EnemyActor.

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
	_model = get_node_or_null("Model")
	if _model:
		_animation_player = _model.get_node_or_null("AnimationPlayer")
	hp = get_max_hp()
	_state_machine.on_display_state_changed.connect(_on_display_state_changed)
	_state_machine.state = &"IdleState"

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
		_state_machine.transition(&"StaggerState")

func _die() -> void:
	died.emit()
	_state_machine.transition(&"DeathState")

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
	if not _animation_player:
		return
	var actor_state = new_state as ActorState
	if actor_state and actor_state.animation_name != "":
		_animation_player.play(actor_state.animation_name)

# --- Rollback ---
# Called by RollbackSynchronizer for PlayerActor.
# EnemyActor applies gravity in _physics_process instead.

func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	if incoming_damage > 0:
		take_damage(incoming_damage)
		incoming_damage = 0
	force_update_is_on_floor()
	if not is_on_floor():
		apply_gravity(delta)
