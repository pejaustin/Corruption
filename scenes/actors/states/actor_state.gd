class_name ActorState extends RewindableState

## Base state for all actors.
## Provides animation_name export and actor accessor via state machine parent.

@export var animation_name: String

var actor: Actor:
	get: return state_machine.get_parent() as Actor

func physics_move() -> void:
	## Apply physics_factor, move_and_slide, restore velocity.
	## Gravity is already applied by the Actor before the state ticks.
	actor.velocity *= NetworkTime.physics_factor
	actor.move_and_slide()
	actor.velocity /= NetworkTime.physics_factor
