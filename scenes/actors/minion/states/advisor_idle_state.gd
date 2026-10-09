extends MinionState

const Placement := preload("res://scenes/actors/minion/advisor_placement.gd")

## Advisor idle: stand still facing the owner overlord. When the overlord is in
## range of a tower station, pick a spot beside it (off the map floor) and hand
## off to AdvisorFollowState (mounted under the node name "ChaseState") to walk
## there. With no station in range he stays put, or returns home if he is on
## the map floor. Retargets only when the nearest in-range station changes,
## after RETARGET_DWELL.

var _station_id: int = 0
var _retarget_at: float = 0.0
var _home: Vector3 = Vector3.INF

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	var overlord := _find_owner_overlord()
	var tower := Placement.tower_of(actor)
	if overlord == null or tower == null:
		return
	var floor_map := Placement.map_floor(tower)
	if _home == Vector3.INF:
		_home = Placement.push_off_floor(actor, floor_map, actor.global_position)

	var now := Time.get_ticks_msec() / 1000.0
	var st := Placement.nearest_in_range(tower, actor, overlord)
	if st != null and now >= _retarget_at:
		# Every station on the map floor counts as one: he waits at the floor's edge.
		var at_floor := Placement.on_floor(floor_map, st.global_position)
		var key: int = floor_map.get_instance_id() if at_floor else st.get_instance_id()
		var drifted: bool = at_floor and Placement.flat_dist(actor.global_position, overlord.global_position) > Placement.FLOOR_RETARGET
		if key != _station_id or drifted:
			_station_id = key
			_retarget_at = now + Placement.RETARGET_DWELL
			var s := Placement.push_off_floor(actor, floor_map, overlord.global_position) if at_floor else st.global_position
			minion.waypoint = Placement.spot_for(actor, s, overlord, floor_map, _home)
			state_machine.transition(&"ChaseState")
			return
	if st == null and Placement.on_floor(floor_map, actor.global_position):
		_station_id = 0
		minion.waypoint = _home
		state_machine.transition(&"ChaseState")
		return

	var to_ov := overlord.global_position - actor.global_position
	to_ov.y = 0
	face_direction(to_ov.normalized())

func _find_owner_overlord() -> OverlordActor:
	for node in actor.get_tree().get_nodes_in_group(&"actors"):
		var ov := node as OverlordActor
		if ov != null and ov.name.to_int() == minion.owner_peer_id:
			return ov
	return null
