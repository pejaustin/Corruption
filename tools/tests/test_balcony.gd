extends "res://tools/tests/test_base.gd"

## The balcony (GDD §2) and the day/night cycle: E at your own balcony takes the
## camera to a lookout and E/Q returns; the clock advances and turns the sun.

func run_tests() -> void:
	var world := await load_world()
	var balcony: Balcony = null
	var other_balconies: int = 0
	for t in Tower.in_slot_order(get_tree()):
		if t is Tower:
			var b := t.get_node_or_null("Balcony") as Balcony
			check(b != null, "%s has a balcony" % t.name)
			if (t as Tower).owner_peer_id == 1:
				balcony = b
			else:
				other_balconies += 1
	check(balcony != null, "peer 1's tower has a balcony")
	var player := world.find_child("1", true, false) as OverlordActor
	check(player != null, "peer 1's overlord exists")
	if balcony == null or player == null:
		return
	check(balcony.is_active_for_local_peer(), "peer 1 may use its own balcony")
	check(balcony.get_camera().far >= 1000.0, "lookout sees far enough for beacons")

	balcony.open_lookout(player)
	await frames(3)
	check(balcony.is_open() and Interactable.has_modal(), "lookout opens and takes the modal lock")
	check(balcony.get_camera().current, "lookout camera is current")
	var yaw_before: float = balcony.get_camera().global_rotation.y
	balcony.rotate_lookout(Vector2(100.0, 0.0) * Balcony.MOUSE_ROTATION_SPEED)
	check(not is_equal_approx(yaw_before, balcony.get_camera().global_rotation.y), "mouse look turns the camera")
	balcony.rotate_lookout(Vector2(0.0, -100000.0))
	check(balcony.get_camera().rotation.x <= Balcony.PITCH_MAX + 0.001, "pitch is clamped")
	balcony.close_lookout()
	await frames(2)
	check(not balcony.is_open() and not Interactable.has_modal(), "closing releases the modal lock")
	check(not balcony.get_camera().current, "lookout camera released")

	# Another tower's balcony is not ours.
	for t in Tower.in_slot_order(get_tree()):
		if t is Tower and (t as Tower).owner_peer_id != 1:
			var b := t.get_node("Balcony") as Balcony
			b.open_lookout(player)
			check(not b.is_open(), "a rival's balcony will not open")
			break

	# Day/night.
	var clock := world.get_node_or_null("DayNight") as DayNight
	check(clock != null, "world has a day/night clock")
	if clock == null:
		return
	var light := world.get_node("World/Atmosphere/DirectionalLight3D") as DirectionalLight3D
	clock.set_time(0.5)
	var noon_energy: float = light.light_energy
	var noon_rot: float = light.rotation.x
	check(not clock.is_night(), "noon is day")
	clock.set_time(0.0)
	check(clock.is_night(), "midnight is night")
	check(light.light_energy < noon_energy, "night light is dimmer")
	check(light.light_energy > 0.0, "night stays playable (not black)")
	var t0: float = clock.time_of_day
	await frames(30)
	check(not is_equal_approx(t0, clock.time_of_day), "the clock advances")
	clock.set_time(0.3)
	var rot_a: float = light.rotation.x
	clock.set_time(0.4)
	check(not is_equal_approx(rot_a, light.rotation.x) and not is_equal_approx(noon_rot, rot_a), "the sun rotates with the hour")
