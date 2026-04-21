class_name AbilityEffect extends Node3D

## Base class for Avatar ability effect scenes.
## When an AvatarAbility fires, its effect_scene is instanced as a child
## of the caster and activate(caster) is called. The effect owns its own
## visuals, timing, and gameplay, and frees itself when done.

var caster: Node3D

func activate(caster_node: Node3D) -> void:
	caster = caster_node
	_on_activate()

## Override in subclasses. Default is a stub that self-frees after a tick.
func _on_activate() -> void:
	print("[AbilityEffect stub] %s activated by %s" % [name, caster])
	queue_free()
