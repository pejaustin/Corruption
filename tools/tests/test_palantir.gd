extends "res://tools/tests/test_base.gd"

const Driver := preload("res://tools/playtest/input_driver.gd")

## The Palantir (GDD §8) reached the way a player reaches it: the overlord's
## interaction ray finds it, the prompt shows, E starts scrying, and once the
## Paladin is his, E again takes control.

func run_tests() -> void:
	var world := await load_world()
	var player := world.find_child("1", true, false) as OverlordActor
	check(player != null, "peer 1's overlord exists")
	if player == null:
		return
	var pal: Interactable = null
	for p in world.find_children("Palantir", "Interactable", true, false):
		if player.global_position.distance_to(p.global_position) < 40.0 and (pal == null or player.global_position.distance_to(p.global_position) < player.global_position.distance_to(pal.global_position)):
			pal = p
	check(pal != null, "a Palantir is in peer 1's tower")
	if pal == null:
		return
	check(pal.get("scry_rig_scene") != null and pal.get("scry_rig_scene").can_instantiate(), "the scry rig scene loads")
	check(pal.collision_layer & Interactable.INTERACTABLE_LAYER != 0, "the Palantir sits on the interactable layer")
	var dist: float = player.global_position.distance_to(pal.global_position)
	print("  overlord at ", player.global_position, " palantir at ", pal.global_position, " (%.1f m)" % dist)

	var cam: Camera3D = (player.find_children("*", "CameraInput", true, false)[0] as CameraInput).camera_3d
	var ray := cam.get_node("InteractionRayCast") as RayCast3D
	# Stand where the player would: as close to the Palantir as the ray is long.
	await _aim_at(player, cam, pal)
	print("  cam ", cam.global_position, " fwd ", -cam.global_basis.z, " ray enabled ", ray.enabled, " mask ", ray.collision_mask, " target ", ray.global_transform * ray.target_position)
	var hit: Object = ray.get_collider() if ray.is_colliding() else null
	print("  ray hit: ", hit, " at ", hit.get_path() if hit is Node else "-")
	check(hit != null and (hit == pal or pal.is_ancestor_of(hit as Node)), "the interaction ray hits the Palantir")
	check(pal._is_focused and pal.is_overlord_in_range(), "the Palantir takes focus")
	check(pal.get_prompt_text() == "Press E to scry", "the prompt invites scrying")

	await _press_e()
	check(pal.get("_is_scrying"), "E starts scrying")
	check(Interactable.has_modal(), "scrying claims the modal lock")
	check(pal.get("_scry_camera") != null and pal.get("_scry_camera").current, "the scry camera is current")
	check(pal.get_prompt_text().contains("Q to return"), "scrying shows the return prompt")

	# Not his owner yet: E does nothing; Q goes back.
	await _press_e()
	check(pal.get("_is_scrying") and not GameState.has_avatar(), "E does not possess him while he is not yours")
	await _press("cancel")
	check(not pal.get("_is_scrying") and not Interactable.has_modal(), "Q stops scrying")

	# His owner: E again takes control.
	GameState.set_avatar_owner(1)
	await frames(5)
	await _aim_at(player, cam, pal)
	await _press_e()
	check(pal.get("_is_scrying"), "scrying again as his owner")
	check(pal.get_prompt_text().contains("E to take control"), "the owner is offered control")
	await _press_e()
	await frames(10)
	check(GameState.has_avatar(), "E as owner possesses the Paladin")
	check(not pal.get("_is_scrying"), "possessing ends the scrying")

func _aim_at(player: OverlordActor, cam: Camera3D, pal: Node3D) -> void:
	## Walk up to the Palantir and look at it with real input events.
	var drv := get_node_or_null("Driver")
	if drv == null:
		drv = Driver.new()
		drv.name = "Driver"
		add_child(drv)
	drv.bind(player, cam)
	var here := Vector2(player.global_position.x, player.global_position.z)
	var there := Vector2(pal.global_position.x, pal.global_position.z)
	var stand := there - (there - here).normalized() * 1.5
	var arrived: bool = await drv.walk_to(stand, 0.3, 20.0)
	check(arrived, "walked up to the Palantir")
	await drv.aim_at(pal.global_position)
	await frames(5)

func _press_e() -> void:
	await _press("interaction")

func _press(action: String) -> void:
	var drv := get_node("Driver")
	await drv.press_action(action, 0.1)
