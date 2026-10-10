extends Node

## Minimal headless test runner for systems that need the real world scene.
## Each test is a tiny scene whose root runs a subclass of this script, so the
## autoloads exist before any game script compiles. Run one with:
##   godot --headless --path . res://tools/tests/test_<name>.tscn
## Exit code is the number of failed checks.

const WORLD: String = "res://scenes/world/world.tscn"
## WORLD_SIZE=400m|6km runs the test on that size's world (world_<size>.tscn); the default is the 2 km world.
const WORLD_SIZE_SCENE: String = "res://scenes/world/world_%s.tscn"

var failures: int = 0
var checks: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await run_tests()
	print("[tests] %d checks, %d failed" % [checks, failures])
	get_tree().quit(failures)

func run_tests() -> void:
	pass

func load_world() -> Node:
	## Loads the match scene as an offline host (peer 1) and lets it settle.
	## The world is added beside this runner (not swapped in for it) so the
	## runner survives; game code finds it through current_scene as usual.
	NetworkManager.is_hosting_game = true
	var size := OS.get_environment("WORLD_SIZE")
	var world: Node = (load(WORLD if size == "" or size == "2km" else WORLD_SIZE_SCENE % size) as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	# The real game starts netfox's clock when a match begins; actors' display
	# states (and so their animations, attacks included) only advance with it.
	NetworkTime.start()  # Warns and no-ops if already running.
	await frames(30)
	return world

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)
