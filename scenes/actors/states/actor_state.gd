class_name ActorState extends RewindableState

## Base state for all actors.
## Provides animation_name export and actor accessor via state machine parent.
##
## Action gating — see docs/systems/action-gating.md
## `action_locked` and `stagger_immune` are runtime flags flipped by animation
## method tracks to carve a state's animation into cancellable/uncancellable and
## stagger-vulnerable/immune windows. Both are zeroed every time a state is
## entered (Actor._on_display_state_changed), so a missed "turn off" key self-
## recovers on the next transition instead of permanently locking the actor.
## Drive them via the lock_action/unlock_action/enable_stagger_immunity/
## disable_stagger_immunity helpers on Actor so animation tracks can target the
## Actor root (a known path from the AnimationPlayer) instead of reaching into
## the state machine.

@export var animation_name: String
## States listed here can interrupt this state even while action_locked is true.
## Example: AttackState's cancel_whitelist = [&"RollState"] — Roll breaks the
## swing during lockout, other inputs do not.
@export var cancel_whitelist: Array[StringName] = []

var action_locked: bool = false
var stagger_immune: bool = false

var actor: Actor:
	get: return state_machine.get_parent() as Actor

func physics_move() -> void:
	## Apply physics_factor, move_and_slide, restore velocity.
	## Gravity is already applied by the Actor before the state ticks.
	actor.velocity *= NetworkTime.physics_factor
	actor.move_and_slide()
	actor.velocity /= NetworkTime.physics_factor

# --- Animation-method-track setters ---
# Keep these as methods (not raw property access) so AnimationPlayer Call
# Method tracks can invoke them; Godot doesn't allow property assignment from
# a method track.
func lock_action() -> void:
	action_locked = true

func unlock_action() -> void:
	action_locked = false

func enable_stagger_immunity() -> void:
	stagger_immune = true

func disable_stagger_immunity() -> void:
	stagger_immune = false
