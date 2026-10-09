class_name UnitGroup extends RefCounted

## A group of troops that moves and fights together under one leader (GDD §5:
## "Group leaders gain experience and learn more complex maneuvers", Q35/Q36).
## Pieces on the map floor stand for groups. Host-side; owners learn about a
## group only through reports (KnowledgeManager).

var id: int = -1
var owner_peer_id: int = -1
var member_ids: Array[int] = []
var leader_id: int = -1
## Leader experience; maneuvers learned (MANEUVERS are Austin's, ticket #581).
var experience: float = 0.0
var maneuvers: Array[StringName] = []

## Current order: { route: Array[Vector3], route_points: Array[StringName],
## dest_point: StringName, goal: int (OrderGoal.Goal), issued_tick: int }.
## Empty = no order (holding where it is).
var order: Dictionary = {}
var route_index: int = 0
## &"holding", &"moving", &"stuck", &"fighting", &"assessing", &"returning",
## &"teaching", &"training".
var status: StringName = &"holding"
## Seconds spent at the destination for goals that wait there (assess).
var goal_timer: float = 0.0
## Progress tracking for "stuck" (GDD Q2: the army stands at the river,
## confused, until new orders arrive).
var best_distance: float = INF
var stall_timer: float = 0.0

## Sightings since the last report: observed id -> { id, pos, owner_peer_id,
## faction, observed_tick }.
var field_log: Dictionary[int, Dictionary] = {}
## Map points passed close enough to put on the map.
var discovered_points: Array[StringName] = []
## Set when the group has a courier-on-attack capability (ticket #544; how it
## is unlocked is Austin's call). The first hit sends a runner home.
var auto_courier: bool = false
var _auto_courier_sent: bool = false

func has_order() -> bool:
	return not order.is_empty()

func get_goal() -> int:
	return int(order.get("goal", OrderGoal.Goal.GO_HERE))

func current_waypoint() -> Vector3:
	var route: Array = order.get("route", [])
	if route_index < route.size():
		return route[route_index]
	return Vector3.INF

func clear_order() -> void:
	order = {}
	route_index = 0
	goal_timer = 0.0
	best_distance = INF
	stall_timer = 0.0

func take_log() -> Array:
	## The group's sightings since the last report, emptied.
	var out: Array = field_log.values()
	field_log.clear()
	return out

func take_points() -> Array[StringName]:
	var out := discovered_points.duplicate()
	discovered_points.clear()
	return out
