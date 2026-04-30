class_name Actor extends CharacterBody3D

## Base class for all combat entities (players and enemies).
## Provides HP, damage, stagger, death, gravity, and animation hookup.
## Subtypes: PlayerActor (→ AvatarActor, OverlordActor), MinionActor.

signal hp_changed(new_hp: int)
signal died
## Fired AFTER take_damage applies the hit and any hitstop has been latched.
## Local-only consumers (damage numbers, hit-flash, FX) listen here. Gated by
## _is_resimulating() inside take_damage so resims don't double-fire.
##
## Tier C: `source` is now propagated through the damage pipeline (was always
## null in Tiers A/B). Listeners that branched on source != null now light up
## (e.g. Targeting._on_owner_took_damage's behind-attack lock-break).
signal took_damage(amount: int, source: Node)
## Fired locally on the parrier and the attacker when a parry is resolved
## host-side. `attacker` was the swinging actor, `victim` is the parrier.
## Local-only — same resim gate as took_damage. VFX/SFX hooks subscribe here.
signal parried(attacker: Node, victim: Node)
## Fired host-side when posture reaches max. Local — clients learn via
## the synced `state` flipping to PostureBrokenState. UI hooks may listen.
signal posture_broken

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

# --- Tier C: Defense / Posture constants ---

## Block protects this much front-cone, half-angle in degrees. ±60° = 120° arc.
const BLOCK_FRONT_CONE_DEG: float = 60.0
## Damage multiplier applied to incoming hits while blocking and facing the
## source within the front cone. 0.3 = 70% reduction.
const BLOCK_DAMAGE_REDUCTION: float = 0.3
## Tap-block window (ticks since BlockState entered) that registers as a parry
## instead of a held block. ~200ms at netfox 30Hz.
const PARRY_WINDOW_TICKS: int = 6
## How long PostureBrokenState lingers before the actor recovers. Riposte
## (Tier D) interrupts early.
const POSTURE_BROKEN_DURATION_TICKS: int = 30
## Posture gained on the victim per unblocked hit.
const HIT_POSTURE_PER_HIT: int = 4
## Posture gained on the victim per blocked hit (greater than unblocked —
## blocking trades hp for posture).
const BLOCK_POSTURE_PER_HIT: int = 12
## Posture gained on the attacker when their swing is parried.
const PARRY_POSTURE_GAIN: int = 30

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

# --- Tier C: posture meter exports + state ---

## Sekiro-style posture cap. Hits while blocking accelerate posture gain;
## reaching this triggers PostureBrokenState.
@export var max_posture: int = 100
## Per-rollback-tick posture decay applied while not in active combat.
## Float to allow sub-integer rates; accumulator is integer-clamped on apply.
@export var posture_decay_per_tick: float = 0.5

## Current posture (rollback-synced via PlayerActor's RollbackSynchronizer;
## host-authoritative on MinionActor — see scripts/minion_manager.gd sync RPC).
var posture: int = 0
## NetworkTime.tick at which the most recent posture-break event happened.
## Carried as a state_property so resim reproduces the entry deterministically.
## -1 = never broken.
var posture_break_tick: int = -1
## Marker for ripostable victims. Set true on entry to PostureBrokenState,
## cleared on exit. Local-only flag — Tier D's heavy-attack-vs-broken-target
## logic reads it on the host that's running the attacker.
var is_ripostable: bool = false
## NetworkTime.tick when BlockState was last entered. Used host-side to
## resolve parry causality: a hit that lands while
## `NetworkTime.tick - block_press_tick <= PARRY_WINDOW_TICKS` parries.
## State_property on PlayerActor so clients carry the same value during resim.
## -1 = no recent press.
var block_press_tick: int = -1
## Sub-integer accumulator for posture decay. Stays out of state_properties —
## resim deltas are deterministic from the synced posture/tick pair, and the
## fractional drift is invisible to gameplay.
var _posture_decay_accumulator: float = 0.0
## NetworkTime.tick at which the most recent damage was taken. Posture decay
## is gated on (now - this) > POSTURE_DECAY_GRACE_TICKS so combat doesn't
## drain a victim's poise while the next swing is still landing. -1 = never.
var _last_damage_tick: int = -1
## Grace window after taking damage where posture decay is suspended. Avoids
## the posture meter feeling "leaky" during sustained pressure.
const POSTURE_DECAY_GRACE_TICKS: int = 60

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

## Apply `amount` damage to this actor, attributed to `source` (the attacking
## actor, when known). Tier C: defends against the hit through
## `is_blocking_against(source.global_position)` (full block reduction or a
## parry flip), and gains posture proportional to the outcome. Source = null
## is allowed for legacy / non-actor damage paths (debug, ability AoE on
## itself, environmental damage). All callers SHOULD pass source where it's
## available so the lock-from-behind drop and parry causality both fire.
func take_damage(amount: int, source: Node = null) -> void:
	if not can_take_damage():
		return
	var source_actor := source as Actor
	var final_damage: int = amount
	var was_parried: bool = false
	# Block / parry resolution — only meaningful when we know where the hit
	# came from. Without a source we can't run the front-cone check, so we
	# fall back to plain damage.
	if source_actor and is_instance_valid(source_actor):
		if is_blocking_against(source_actor.global_position):
			# Active BlockState + facing the attacker. Now check parry window.
			var since_press: int = NetworkTime.tick - block_press_tick
			if block_press_tick >= 0 and since_press >= 0 and since_press <= PARRY_WINDOW_TICKS:
				# Parry: zero damage to victim, posture to attacker, force
				# attacker into recovery. Local FX hook fires on both sides.
				was_parried = true
				final_damage = 0
				if source_actor.has_method(&"gain_posture"):
					source_actor.gain_posture(PARRY_POSTURE_GAIN)
				ForcedRecovery.apply(source_actor)
				# Local-only feedback. Both attacker and parrier emit on their
				# own peers — resim gate on each side handles double-fire.
				if not _is_resimulating():
					parried.emit(source_actor, self)
					if source_actor.has_signal(&"parried"):
						source_actor.parried.emit(source_actor, self)
			else:
				# Held block — reduce damage, accumulate posture faster than
				# unblocked (blocking trades hp for poise pressure).
				final_damage = int(round(amount * BLOCK_DAMAGE_REDUCTION))
				gain_posture(BLOCK_POSTURE_PER_HIT)
		else:
			# Unblocked hit — small posture bump (heavy hits feel like they
			# erode poise more than chip).
			gain_posture(HIT_POSTURE_PER_HIT)
	else:
		# Source unknown — treat as unblocked, accumulate posture as normal.
		gain_posture(HIT_POSTURE_PER_HIT)

	hp = max(0, hp - final_damage)
	hp_changed.emit(hp)
	_last_damage_amount = final_damage
	_last_damage_tick = NetworkTime.tick
	# Hitstop is authority-set; on PlayerActor this is a state_property so
	# rollback resim reproduces it. MinionActor carries it via its own sync
	# RPC (see scripts/minion_manager.gd). Parries skip hitstop on the victim
	# (their parry pose is its own beat) but the attacker still gets it via
	# their own ForcedRecovery / state.
	if not was_parried:
		hitstop_until_tick = NetworkTime.tick + HITSTOP_TICKS
	if hp <= 0:
		_die()
	elif not was_parried:
		try_stagger()
	# Local-only feedback. Skipped during resim so spark/flash/numbers don't
	# double-fire. See docs/technical/netfox-reference.md §5.
	if not _is_resimulating():
		if final_damage > 0:
			_hit_flash_intensity = 1.0
		took_damage.emit(final_damage, source)

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

# --- Tier C: Defense / Posture API ---

## True iff this actor is currently in BlockState AND `source_pos` lies inside
## the front cone (±BLOCK_FRONT_CONE_DEG of the model's forward, projected onto
## XZ). Used by take_damage to decide whether to apply block reduction or take
## the hit full. Cone-test ignores the Y axis so jumps don't disengage block.
func is_blocking_against(source_pos: Vector3) -> bool:
	if _state_machine == null or _state_machine.state != &"BlockState":
		return false
	var to_source: Vector3 = source_pos - global_position
	to_source.y = 0.0
	if to_source.length_squared() < 0.0001:
		# Source is on top of us — treat as in-cone (no meaningful direction).
		return true
	to_source = to_source.normalized()
	var forward: Vector3 = _resolve_forward()
	if forward.length_squared() < 0.0001:
		return false
	var dot: float = forward.dot(to_source)
	var cos_cone: float = cos(deg_to_rad(BLOCK_FRONT_CONE_DEG))
	return dot >= cos_cone

## Multiplicative damage reduction this actor would apply to a hit from
## `source` right now. 1.0 = full damage; 0.0 = invulnerable. Tier C only
## consults this from take_damage when source is known. Subtypes can override
## for ability-driven defense (e.g. Eldritch ward).
func damage_reduction_against(source: Node) -> float:
	if source is Node3D:
		var src3 := source as Node3D
		if is_blocking_against(src3.global_position):
			return BLOCK_DAMAGE_REDUCTION
	return 1.0

## Add `amount` to posture, clamped to max_posture. If the cap is reached AND
## the actor's state machine has a PostureBrokenState node, the actor
## transitions into it (host-driven; rollback re-runs the same transition
## because state is in state_properties). Subtypes without the state (the
## base actor.tscn — minions etc. unless they add it) accumulate posture
## harmlessly: it caps at max_posture and the meter just shows full. Tier D
## can wire a riposte on `is_ripostable`, which only flips inside the broken
## state, so non-broken actors are simply never ripostable.
##
## Calling on a non-host peer is safe — they'll receive the broken state via
## sync. Do NOT call from inside the broken state (would re-enter recursively).
func gain_posture(amount: int) -> void:
	if amount <= 0:
		return
	if posture >= max_posture:
		return
	posture = min(max_posture, posture + amount)
	if posture < max_posture:
		return
	if _state_machine == null:
		return
	if _state_machine.state == &"PostureBrokenState":
		return
	# Only break if the state machine actually has a PostureBrokenState child.
	# Minion scenes that don't carry the state cap their meter silently.
	if _state_machine.get_node_or_null(^"PostureBrokenState") == null:
		return
	# Drain so subsequent damage doesn't immediately re-trigger; the broken
	# state itself takes over.
	posture = 0
	posture_break_tick = NetworkTime.tick
	if not _is_resimulating():
		posture_broken.emit()
	_state_machine.transition(&"PostureBrokenState")

## Forward vector for the block cone test. Avatar's _model is rotated by the
## locomotion code; minions rotate the body itself. Uses model basis when
## available, else the actor's own basis. Either way, Godot convention has
## -Z as forward.
func _resolve_forward() -> Vector3:
	var basis_node: Node3D = _model if _model else self
	var fwd: Vector3 = -basis_node.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return Vector3.FORWARD
	return fwd.normalized()

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
		# Damage from outside the rollback loop (minion swings, debug pokes)
		# arrives through incoming_damage. Tier C: source attribution is best-
		# effort here — the dual-write path stores the attacker's peer id, not
		# the actor reference. Pass null so block/parry/posture-on-attacker
		# don't fire from this leg. Direct attacker-source damage (player swings)
		# routes through take_damage(amount, source) and DOES carry the source.
		take_damage(incoming_damage, null)
		incoming_damage = 0
	force_update_is_on_floor()
	if not is_on_floor():
		apply_gravity(delta)
	_apply_hitstop_animation_pause()
	_decay_posture()

## Decays posture by `posture_decay_per_tick` per rollback tick when the actor
## is "out of combat" (no damage taken in POSTURE_DECAY_GRACE_TICKS) and not
## in a state that should hold posture (BlockState, PostureBrokenState). The
## fractional accumulator is local-only — resim stays deterministic from the
## synced posture int.
func _decay_posture() -> void:
	if posture <= 0:
		_posture_decay_accumulator = 0.0
		return
	# Hold posture during block (the meter is filling and you're under
	# pressure — no decay) and during posture-broken (the state itself
	# manages the drain on exit).
	var holding_state: bool = false
	if _state_machine and (_state_machine.state == &"BlockState" or _state_machine.state == &"PostureBrokenState"):
		holding_state = true
	if holding_state:
		_posture_decay_accumulator = 0.0
		return
	if _last_damage_tick >= 0 and NetworkTime.tick - _last_damage_tick < POSTURE_DECAY_GRACE_TICKS:
		return
	_posture_decay_accumulator += posture_decay_per_tick
	if _posture_decay_accumulator >= 1.0:
		var whole: int = int(_posture_decay_accumulator)
		_posture_decay_accumulator -= float(whole)
		posture = max(0, posture - whole)

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
