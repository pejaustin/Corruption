class_name Body extends Node3D

## A human's body on the ground (GDD §5: "Undead troops are raised from killed
## humans; bodies must be brought to the tower"). Units with the "carry the
## dead home" goal pick these up. Spawned and removed by MinionManager.
## PLACEHOLDER: art — a pale slab.

var body_id: int = -1

func _ready() -> void:
	add_to_group(&"bodies")
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.2, 1.6)
	mi.mesh = box
	mi.position = Vector3(0, 0.1, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.45)
	mi.material_override = mat
	add_child(mi)
