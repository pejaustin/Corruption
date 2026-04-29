extends MinionState

## Mounted as the IdleState script override on info_courier_actor.tscn.
## Lifecycle:
##
##   1. Info-courier spawns at owner's tower spawn point with waypoint = target.
##      Initial state is IdleState (= this script).
##   2. tick() sees we're far from target, transitions to ChaseState. Inherited
##      ChaseState handles travel.
##   3. ChaseState transitions back to IdleState (= this) on arrival.
##   4. tick() sees we're at the target — start the observe timer and stand
##      still. While observing, MinionActor._observe() (which runs every tick
##      regardless of state) keeps populating _field_log.
##   5. Once OBSERVE_DURATION elapses, transition to RetreatState. Standard
##      retreat path takes the courier home and flushes the log to the owner's
##      WorldModel via KnowledgeManager.flush_observations.

const ARRIVAL_DISTANCE: float = 2.0
## Seconds the info-courier stands at the target observing before turning back
## for home. Tunable. 4s is enough to soak ~16 _observe() sweeps at the default
## OBSERVE_INTERVAL of 0.25s.
const OBSERVE_DURATION: float = 4.0

var _observe_elapsed: float = 0.0
var _observing: bool = false

func enter(_previous: RewindableState, _tick: int) -> void:
	_observe_elapsed = 0.0
	_observing = false

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	if not multiplayer.is_server():
		return
	if minion.waypoint == Vector3.ZERO:
		return

	var to_target := actor.global_position.distance_to(minion.waypoint)
	if to_target > ARRIVAL_DISTANCE:
		# Still en route — let the inherited ChaseState handle travel.
		state_machine.transition(&"ChaseState")
		return

	# Arrived. Start (or continue) observing.
	_observing = true
	_observe_elapsed += delta
	if _observe_elapsed >= OBSERVE_DURATION:
		# Mission complete — head home. RetreatState flushes _field_log.
		state_machine.transition(&"RetreatState")
