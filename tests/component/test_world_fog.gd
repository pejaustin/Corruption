extends "res://tests/support/stage_test.gd"

## The world fog: night thickens it, and the fog volumes drift with the shared fog shader.

const FOG_SCENE := preload("res://scenes/world/fog/world_fog.tscn")

var clock: DayNight
var env_node: WorldEnvironment
var fog: WorldFog

func before_each() -> void:
	await super()
	var world := Node3D.new()
	world.name = "World"
	var atmosphere := Node3D.new()
	atmosphere.name = "Atmosphere"
	env_node = WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	env_node.environment = Environment.new()
	env_node.environment.volumetric_fog_density = 0.01
	atmosphere.add_child(env_node)
	world.add_child(atmosphere)
	fog = FOG_SCENE.instantiate()
	fog.world_environment = env_node
	clock = DayNight.new()
	clock.set_process(false)
	fog.day_night = clock
	atmosphere.add_child(fog)
	stage.add_child(world)
	stage.add_child(clock)

func test_night_thickens_the_haze() -> void:
	clock.set_time(0.5)
	var noon := env_node.environment.volumetric_fog_density
	assert_almost_eq(fog.night, 0.0, 0.01)
	clock.set_time(0.0)
	assert_almost_eq(fog.night, 1.0, 0.01)
	assert_gt(env_node.environment.volumetric_fog_density, noon)

func test_back_to_day_restores_the_haze() -> void:
	clock.set_time(0.0)
	clock.set_time(0.5)
	assert_almost_eq(env_node.environment.volumetric_fog_density, 0.01, 0.0001)

func test_every_volume_drifts_and_thickens_at_night() -> void:
	var volumes := fog.find_children("*", "FogVolume", true, false)
	assert_gt(volumes.size(), 0)
	for v: FogVolume in volumes:
		var mat := v.material as ShaderMaterial
		assert_not_null(mat, v.name)
		assert_eq(mat.shader.resource_path, "res://shaders/drifting_fog.gdshader", v.name)
		assert_not_null(mat.get_shader_parameter("noise"), v.name)
