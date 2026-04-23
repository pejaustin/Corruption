extends SceneTree

func _init() -> void:
	var paths := [
		"res://scenes/interactibles/war_table.tscn",
		"res://scenes/interactibles/gem_site.tscn",
		"res://scenes/actors/enemy/guardian/guardian_boss.tscn",
		"res://scenes/astral_projection.tscn",
	]
	var any_fail := false
	for p in paths:
		var ps := load(p) as PackedScene
		if ps == null:
			push_error("FAILED to load: " + p)
			any_fail = true
			continue
		var inst := ps.instantiate()
		if inst == null:
			push_error("FAILED to instantiate: " + p)
			any_fail = true
			continue
		print("OK: ", p, " root=", inst.name, " class=", inst.get_class())
		inst.queue_free()
	if any_fail:
		quit(1)
	else:
		quit(0)
