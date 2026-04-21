extends MinionState

## Traverses a NavigationLink3D by applying a ballistic arc toward
## minion.jump_target. Entered when the agent reports link_reached on a
## NavigationLink3D in the "jumpable" group (see MinionActor._on_link_reached).
## Gravity is applied by MinionActor._physics_process before this tick, so
## we just set the launch velocity on enter and hold horizontal on each tick,
## returning to chase/idle the first tick we land back on the floor.

## Peak jump height above the launch point, in meters.
const JUMP_PEAK_HEIGHT: float = 2.5
## Minimum airborne time before we allow landing detection (prevents the very
## first tick — still touching the floor — from transitioning out immediately).
const MIN_AIR_TIME: float = 0.08

var _air_time: float = 0.0

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_air_time = 0.0
	if minion == null or minion.jump_target == Vector3.INF:
		return
	var g: float = minion.gravity
	# Time to apex = sqrt(2h/g). Total air time is 2 * t_apex when landing at
	# the same height; link endpoints usually differ by < jump height so this
	# is close enough for gameplay.
	var t_apex := sqrt(2.0 * JUMP_PEAK_HEIGHT / g)
	var t_total := 2.0 * t_apex
	var from := actor.global_position
	var to := minion.jump_target
	var horizontal := Vector3(to.x - from.x, 0, to.z - from.z)
	actor.velocity.y = g * t_apex
	actor.velocity.x = horizontal.x / t_total
	actor.velocity.z = horizontal.z / t_total
	face_direction(horizontal.normalized())

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	_air_time += delta
	physics_move()
	if _air_time >= MIN_AIR_TIME and actor.is_on_floor():
		minion.jump_target = Vector3.INF
		state_machine.transition(&"ChaseState")
