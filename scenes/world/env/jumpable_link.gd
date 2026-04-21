class_name JumpableLink extends NavigationLink3D

## NavigationLink3D that minions traverse with a jump arc instead of walking.
## Placed anywhere the navmesh needs a jumpable gap (over walls, across drops).
## MinionActor._on_link_reached checks for membership in JumpableLink.GROUP.

const GROUP: StringName = &"jumpable"

func _ready() -> void:
	add_to_group(GROUP)
