extends "res://tests/support/stage_test.gd"

## The Palantir (GDD §8): scrying, its prompts, and possessing the Paladin as his owner.
## E is the interact call; reaching it with the interaction ray is the milestone input test
## (tests/integration/test_palantir.tscn).

const PALANTIR := preload("res://scenes/interactibles/palantir.tscn")

var pal: Interactable
var player: OverlordActor

func before_each() -> void:
	await super()
	add_avatar()
	player = add_overlord()
	pal = PALANTIR.instantiate() as Interactable
	stage.add_child(pal)
	pal.set_process(false)
	pal._player_in_range = player

func after_each() -> void:
	pal._stop_scrying(false)
	await super()

func test_the_palantir_sits_on_the_interactable_layer() -> void:
	assert_ne(pal.collision_layer & Interactable.INTERACTABLE_LAYER, 0)

func test_in_range_it_invites_scrying() -> void:
	assert_eq(pal.get_prompt_text(), "Press E to scry")

func test_e_starts_scrying() -> void:
	pal._on_interact()
	assert_true(pal._is_scrying)
	assert_true(Interactable.has_modal())
	assert_true(pal._scry_camera.current)
	assert_true(GameState.is_watching(1), "a viewer is watching")
	assert_string_contains(pal.get_prompt_text(), "Q to return")

func test_e_does_not_possess_him_while_he_is_not_yours() -> void:
	pal._on_interact()
	pal._on_scry_interact()
	assert_true(pal._is_scrying)
	assert_false(GameState.has_avatar())

func test_q_stops_scrying() -> void:
	pal._on_interact()
	pal._stop_scrying(true)
	assert_false(pal._is_scrying or Interactable.has_modal())
	assert_false(GameState.is_watching(1))

func test_his_owner_is_offered_control_and_e_possesses_him() -> void:
	GameState.set_avatar_owner(1)
	pal._on_interact()
	assert_string_contains(pal.get_prompt_text(), "E to take control")
	pal._on_scry_interact()
	assert_true(GameState.is_avatar(1))
	assert_false(pal._is_scrying)
