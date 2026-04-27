extends ActorState

## Stagger state. Actor is stunned briefly after taking a hit.
## Returns to IdleState when duration elapses.
##
## Duration is measured against NetworkTime.tick so the exit transition
## happens at the same tick on authority and remote peers (no wall-clock
## accumulator that can desync under rollback replay). NetworkTime.tick is
## used instead of the tick argument because MinionActor calls
## `_rollback_tick(delta, 0, true)` outside the rollback loop, so the tick
## arg is always 0 for minions — reading the global tick works for both
## rollback-driven actors and host-authoritative minions.

var _enter_tick: int = -1

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_enter_tick = NetworkTime.tick
	actor.velocity.x = 0
	actor.velocity.z = 0

func exit(_next_state: RewindableState, _tick: int) -> void:
	_enter_tick = -1

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	# Non-authority peers enter this state via state_property sync, which
	# bypasses enter(). Latch the first tick we see so elapsed is measured
	# from the same point on every peer.
	if _enter_tick < 0:
		_enter_tick = NetworkTime.tick
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	var elapsed := (NetworkTime.tick - _enter_tick) * NetworkTime.ticktime
	if elapsed >= actor.get_stagger_duration():
		state_machine.transition(&"IdleState")
