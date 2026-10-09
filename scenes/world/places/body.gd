class_name Body extends Node3D

## A human's body on the ground (GDD §5: "Undead troops are raised from killed
## humans; bodies must be brought to the tower"). Units with the "carry the
## dead home" goal pick these up. Spawned (as an instance of body.tscn) and removed by MinionManager.
## PLACEHOLDER: art — a pale slab (authored in body.tscn).

var body_id: int = -1

func _ready() -> void:
	add_to_group(&"bodies")
