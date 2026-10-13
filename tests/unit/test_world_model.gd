extends GutTest

## A player's map of their own groups (Austin, 2026-10-09): after an order a piece is
## expected along its route; a courier failure makes it missing; reports confirm it or
## replace the expectation. Pure WorldModel, no scene tree.

const ROUTE_END := Vector3(100, 0, 0)

var model: WorldModel
var t0: int

func before_each() -> void:
	model = WorldModel.new()
	t0 = NetworkTime.tick
	model.believed_groups[7] = {"id": 7, "pos": Vector3.ZERO, "count": 3, "goal": -1}
	model.expect(7, 1, Vector3.ZERO, [ROUTE_END], OrderGoal.Goal.GO_HERE, &"X", t0)

func _report(pos: Vector3, goal := OrderGoal.Goal.GO_HERE, source := &"courier") -> void:
	model.update_group({"id": 7, "pos": pos, "count": 3, "goal": goal, "obs_tick": t0}, t0, source)

func test_a_sent_order_makes_the_piece_expected() -> void:
	assert_eq(model.piece_state(7), &"expected")

func test_an_expected_piece_walks_its_route_at_the_expected_speed() -> void:
	var ticks := int(WorldModel._rate() * 2.0)
	assert_almost_eq(model.group_position(7, t0 + ticks), Vector3(WorldModel.EXPECTED_SPEED * 2.0, 0, 0), Vector3.ONE * 0.01)

func test_an_expected_piece_stops_at_the_destination() -> void:
	assert_eq(model.group_position(7, t0 + 1000000), ROUTE_END)

func test_a_courier_failure_marks_it_missing_where_it_was_expected() -> void:
	var ticks := int(WorldModel._rate() * 2.0)
	var at := model.group_position(7, t0 + ticks)
	model.mark_missing(7, t0 + ticks)
	assert_eq(model.piece_state(7), &"missing")
	assert_eq(model.group_position(7, t0 + ticks * 10), at, "a missing piece stays put")

func test_a_report_on_the_route_confirms_it() -> void:
	model.mark_missing(7, t0)
	_report(Vector3(40, 0, 0))
	assert_eq(model.piece_state(7), &"confirmed")

func test_a_report_far_off_the_route_replaces_the_expectation() -> void:
	_report(Vector3(40, 0, WorldModel.CONTRADICTION_RADIUS + 10.0), -1)
	assert_false(model.expectations.has(7))

func test_a_report_with_another_goal_replaces_the_expectation() -> void:
	_report(Vector3(40, 0, 0), OrderGoal.Goal.CORRUPT)
	assert_false(model.expectations.has(7))

func test_the_old_goal_seen_as_the_order_is_handed_over_is_no_contradiction() -> void:
	model.update_group({"id": 7, "pos": Vector3(1, 0, 0), "count": 3, "goal": OrderGoal.Goal.CORRUPT, "before_cmd": 1, "obs_tick": t0}, t0, &"courier")
	assert_true(model.expectations.has(7))

func test_arriving_ends_the_expectation() -> void:
	_report(ROUTE_END)
	assert_false(model.expectations.has(7))

func test_coming_home_ends_the_expectation() -> void:
	_report(Vector3(40, 0, 0), OrderGoal.Goal.GO_HERE, &"returned")
	assert_false(model.expectations.has(7))

func test_a_stuck_report_stops_the_piece_where_they_gave_up() -> void:
	model.update_group({"id": 7, "pos": Vector3(30, 0, 0), "count": 3, "goal": OrderGoal.Goal.GO_HERE,
		"status": &"stuck", "obs_tick": t0}, t0, &"courier")
	assert_eq(model.piece_state(7), &"stuck")
	assert_eq(model.group_position(7, t0 + 1000000), Vector3(30, 0, 0), "it does not walk on")

func test_a_courier_searches_ahead_then_back_along_the_route() -> void:
	model.expect(8, 2, Vector3.ZERO, [Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3(30, 0, 0)], OrderGoal.Goal.GO_HERE, &"X", t0)
	var ticks := int(WorldModel._rate() * 15.0 / WorldModel.EXPECTED_SPEED)  # 15 m along
	assert_eq(model.search_points(8, t0 + ticks, 10), [Vector3(20, 0, 0), Vector3(30, 0, 0), Vector3(10, 0, 0), Vector3.ZERO] as Array[Vector3])

func test_a_dead_group_leaves_the_map() -> void:
	model.update_group({"id": 7, "count": 0}, t0, &"courier")
	assert_false(model.believed_groups.has(7))
	assert_false(model.expectations.has(7))

func test_path_helpers() -> void:
	var path := [Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, 10)]
	assert_eq(WorldModel.path_length(path), 20.0)
	assert_eq(WorldModel.point_along(path, 15.0), Vector3(10, 0, 5))
	assert_almost_eq(WorldModel.project_on_path(path, Vector3(12, 0, 4)), 14.0, 0.001)
	assert_almost_eq(WorldModel.distance_to_path(path, Vector3(12, 0, 4)), 2.0, 0.001)

func test_a_road_route_is_searched_at_its_map_points_not_every_waypoint() -> void:
	var route: Array[Vector3] = []
	for x in range(5, 105, 5):
		route.append(Vector3(x, 0, 0))
	model.expect(9, 3, Vector3.ZERO, route, OrderGoal.Goal.GO_HERE, &"X", t0, [Vector3(50, 0, 0), Vector3(100, 0, 0)])
	var ticks := int(WorldModel._rate() * 20.0 / WorldModel.EXPECTED_SPEED)  # 20 m along
	assert_eq(model.search_points(9, t0 + ticks, 10), [Vector3(50, 0, 0), Vector3(100, 0, 0), Vector3.ZERO] as Array[Vector3])
