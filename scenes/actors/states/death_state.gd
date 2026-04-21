extends ActorState

## Death state. Actor is immobile.
## Subtypes handle death transfer/cleanup via Actor._die().

func enter(previous_state: RewindableState, tick: int) -> void:
	actor.velocity = Vector3.ZERO

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
