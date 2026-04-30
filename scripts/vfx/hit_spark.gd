class_name HitSpark extends Node3D

## Self-freeing hit-spark stub. Attached to scenes/vfx/hit_spark_*.tscn.
##
## On _ready: kicks off any GPUParticles3D / CPUParticles3D children (sets
## emitting = true) and queues itself free after `lifetime` seconds.
##
## Artists swap in real particle systems by editing the .tscn files —
## the only contract is that this script's lifetime exceeds the longest
## particle lifetime so trails finish before the node despawns.

@export var lifetime: float = 0.4

func _ready() -> void:
	for child in _walk_descendants():
		if child is GPUParticles3D:
			(child as GPUParticles3D).restart()
			(child as GPUParticles3D).emitting = true
		elif child is CPUParticles3D:
			(child as CPUParticles3D).restart()
			(child as CPUParticles3D).emitting = true
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _walk_descendants() -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			out.append(c)
			stack.append(c)
	return out
