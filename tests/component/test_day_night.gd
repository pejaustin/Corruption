extends "res://tests/support/stage_test.gd"

## The day/night clock: it advances, decides night, and turns and dims the sun.

var clock: DayNight
var light: DirectionalLight3D

func before_each() -> void:
	await super()
	var world := Node3D.new()
	world.name = "World"
	var atmosphere := Node3D.new()
	atmosphere.name = "Atmosphere"
	light = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	atmosphere.add_child(light)
	world.add_child(atmosphere)
	stage.add_child(world)
	clock = DayNight.new()
	stage.add_child(clock)
	clock.set_process(false)

func test_noon_is_day_and_midnight_is_night() -> void:
	clock.set_time(0.5)
	assert_false(clock.is_night())
	clock.set_time(0.0)
	assert_true(clock.is_night())

func test_night_is_dimmer_but_not_black() -> void:
	clock.set_time(0.5)
	var noon := light.light_energy
	clock.set_time(0.0)
	assert_lt(light.light_energy, noon)
	assert_gt(light.light_energy, 0.0)

func test_the_clock_advances() -> void:
	clock.set_time(0.2)
	clock._process(DayNight.DAY_SECONDS * 0.1)
	assert_almost_eq(clock.time_of_day, 0.3, 0.0001)

func test_the_sun_turns_with_the_hour() -> void:
	clock.set_time(0.3)
	var a := light.rotation.x
	clock.set_time(0.4)
	assert_ne(light.rotation.x, a)

func test_night_darkens_the_cloud_sky() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.sky = Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sky_clouds.gdshader")
	mat.set_shader_parameter(&"sky_top_color", Color(0.4, 0.7, 0.9))
	env.sky.sky_material = mat
	env_node.environment = env
	stage.get_node("World/Atmosphere").add_child(env_node)
	var sky_clock := DayNight.new()
	sky_clock.set_process(false)
	stage.add_child(sky_clock)
	var sky := env_node.environment.sky.sky_material as ShaderMaterial
	sky_clock.set_time(0.5)
	var noon: Color = sky.get_shader_parameter(&"sky_top_color")
	sky_clock.set_time(0.0)
	var midnight: Color = sky.get_shader_parameter(&"sky_top_color")
	assert_lt(midnight.v, noon.v)
