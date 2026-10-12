class_name EncounterSpawn extends Marker3D

## Where one of an encounter's enemies stands when the Paladin enters. Authored
## in the dungeon and arena scenes; the SiteEncounter spawns the minions at run
## time. PLACEHOLDER: every enemy type, count and position is not designed.

## The MinionType id to spawn here (must be in data/minion_catalog.tres).
@export var minion_type: StringName = &"holy_knight"
## 1-based room this enemy belongs to (the arena has one).
@export var room: int = 1
## PLACEHOLDER: tuning — 0 keeps the type's own health / damage.
@export var hp_override: int = 0
@export var damage_override: int = 0
