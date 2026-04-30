class_name HitFx extends Object

## Static helper for spawning hit-impact FX (sparks, dust, etc.).
## Single entrypoint: HitFx.spawn(kind, world_pos, victim).
##
## Cosmetic-only. Skipped during rollback resimulation so resims don't stack
## particles. Damage application is the authoritative event — this fires off
## the back of it on the local presentation only. See netfox-reference.md §5.
##
## Asset wiring: artists author particle systems inside the existing stub
## scenes (scenes/vfx/hit_spark_<kind>.tscn). The lookup table here is the
## stable contract — adding a new kind means adding both a key here and a
## scene at the matching path.

const SCENES: Dictionary[StringName, String] = {
	&"flesh": "res://scenes/vfx/hit_spark_flesh.tscn",
	&"armor": "res://scenes/vfx/hit_spark_armor.tscn",
	&"shield": "res://scenes/vfx/hit_spark_shield.tscn",
}

## Spawn a hit-spark of `kind` at `world_pos`, parented to the current scene
## so it doesn't move with the victim (impact FX should detach on the contact
## frame). The scene self-frees via its own lifetime export.
##
## `victim` is used only as a tree handle — its `get_tree()` finds the scene
## root. Pass the hit Actor or any node still in the tree.
static func spawn(kind: StringName, world_pos: Vector3, victim: Node) -> void:
	if NetworkRollback.is_rollback():
		return
	if victim == null or not is_instance_valid(victim):
		return
	var path: String = SCENES.get(kind, SCENES[&"flesh"])
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("[HitFx] Missing scene for kind '%s' at %s" % [kind, path])
		return
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return
	var parent := victim.get_tree().current_scene
	if parent == null:
		instance.queue_free()
		return
	parent.add_child(instance)
	instance.global_position = world_pos
