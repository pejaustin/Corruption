extends "res://tests/support/stage_test.gd"

## The balcony (GDD §2): E at your own balcony takes the camera to a lookout and E/Q returns.

const BALCONY := preload("res://scenes/interactibles/balcony.tscn")

var balcony: Balcony
var player: OverlordActor

func before_each() -> void:
	await super()
	player = add_overlord()
	balcony = BALCONY.instantiate() as Balcony
	add_tower(1).add_child(balcony)

func after_each() -> void:
	if balcony.is_open():
		balcony.close_lookout()
	await super()

func test_the_lookout_sees_far_enough_for_beacons() -> void:
	assert_gte(balcony.get_camera().far, 1000.0)

func test_the_lookout_opens_with_the_modal_lock_and_its_camera() -> void:
	balcony.open_lookout(player)
	assert_true(balcony.is_open() and Interactable.has_modal())
	assert_true(balcony.get_camera().current)

func test_mouse_look_turns_the_camera_and_pitch_is_clamped() -> void:
	balcony.open_lookout(player)
	var yaw := balcony.get_camera().global_rotation.y
	balcony.rotate_lookout(Vector2(100.0, 0.0) * Balcony.MOUSE_ROTATION_SPEED)
	assert_ne(balcony.get_camera().global_rotation.y, yaw)
	balcony.rotate_lookout(Vector2(0.0, -100000.0))
	assert_lte(balcony.get_camera().rotation.x, Balcony.PITCH_MAX + 0.001)

func test_closing_releases_the_lock_and_camera() -> void:
	balcony.open_lookout(player)
	balcony.close_lookout()
	assert_false(balcony.is_open() or Interactable.has_modal())
	assert_false(balcony.get_camera().current)

func test_a_rivals_balcony_will_not_open() -> void:
	var rival := BALCONY.instantiate() as Balcony
	add_tower(2).add_child(rival)
	rival.open_lookout(player)
	assert_false(rival.is_open())
