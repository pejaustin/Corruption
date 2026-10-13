class_name RiverCrossing
extends Marker3D
## A place where units cross Pale River (Austin, 2026-10-12: every town on the river is a crossing; Hopes Gate is three, its
## city gates spanning three river openings). Hung under a town's marker in art/world/export/world_landscape_2km.tscn. The world
## build (scripts/build/world_areas.gd) leaves the river open within radius_m of it: no blocker, no bank wall. After moving one,
## run tools/sync_world_sizes.sh --no-export (the areas and the navmesh are rebuilt).

## PLACEHOLDER: how far around this point the river can be crossed, in metres at 2 km (scales with the map's width).
@export var radius_m: float = 20.0
