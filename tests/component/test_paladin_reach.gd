extends "res://tests/support/stage_test.gd"

## The AI-driven Paladin drops targets he cannot walk to (a unit on a roof with no ramp)
## and still picks reachable ones. Targeting is decided by calling _update_target directly.

const ROOF_HEIGHT: float = 3.6

var avatar: AvatarActor
var ai: AvatarAI

func before_each() -> void:
	await super()
	await add_ground()
	avatar = add_avatar()
	ai = avatar.get_node(^"AvatarAI") as AvatarAI

func _add_roof(pos: Vector3) -> void:
	## A box ROOF_HEIGHT tall with no ramp. Its top is baked as a separate navmesh island.
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = 0.75
	mesh.agent_height = 3.0
	region.navigation_mesh = mesh
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, ROOF_HEIGHT, 8)
	shape.shape = box
	shape.position.y = ROOF_HEIGHT * 0.5
	body.add_child(shape)
	region.add_child(body)
	region.position = pos
	stage.add_child(region)
	region.bake_navigation_mesh(false)
	var map := stage.get_world_3d().navigation_map
	for i in 20:
		if NavigationServer3D.map_get_closest_point(map, pos + Vector3(0, ROOF_HEIGHT, 0)).y > 1.0:
			break
		await get_tree().physics_frame

func test_a_target_on_a_roof_with_no_ramp_is_dropped() -> void:
	await _add_roof(Vector3(6, 0, 0))
	var roofed := spawn(&"skeleton", 1, Vector3(6, ROOF_HEIGHT, 0))
	ai._update_target()
	assert_null(ai._target, "not chosen")
	assert_true(ai._is_blacklisted(roofed), "left alone for a while")

func test_a_target_on_the_ground_is_fought() -> void:
	await _add_roof(Vector3(-20, 0, 0))
	var grounded := spawn(&"skeleton", 1, Vector3(5, 0, 0))
	ai._update_target()
	assert_eq(ai._target, grounded)

func test_the_roofed_one_is_skipped_for_the_reachable_one() -> void:
	await _add_roof(Vector3(3, 0, 0))
	spawn(&"skeleton", 1, Vector3(3, ROOF_HEIGHT, 0))
	var grounded := spawn(&"skeleton", 1, Vector3(0, 0, 8))
	ai._update_target()
	assert_eq(ai._target, grounded)
