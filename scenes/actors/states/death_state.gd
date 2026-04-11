extends ActorState

## Death state. Actor is immobile.
## Subtypes handle death transfer/cleanup via Actor._die().

func enter(previous_state: RewindableState, tick: int):
	actor.velocity = Vector3.ZERO

func tick(delta: float, tick: int, is_fresh: bool):
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
