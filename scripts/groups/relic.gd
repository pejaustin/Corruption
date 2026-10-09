class_name Relic extends Resource

## A relic found somewhere on the map and carried home (GDD §5, Q35). It grants
## its effect through flags: a group that brings it home gains `auto_courier`,
## and its player gains route points. Authored as .tres under res://data/relics/.
## PLACEHOLDER: which relics exist and what each does is Austin's (ticket #580).
## The shipped entries are stand-ins.

const DIR: String = "res://data/relics/"

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## The group that brings it home sends a runner on the first hit (UnitGroup.auto_courier).
@export var grants_auto_courier: bool = false
## Extra route points its player may walk when planning (GameState.add_route_point_bonus).
@export var route_point_bonus: int = 0

static var _all: Array[Relic] = []
static var _loaded: bool = false

static func all() -> Array[Relic]:
	if not _loaded:
		_loaded = true
		for file in DirAccess.get_files_at(DIR):
			var clean := file.trim_suffix(".remap")
			if clean.ends_with(".tres"):
				var r := load(DIR + clean) as Relic
				if r:
					_all.append(r)
		_all.sort_custom(func(a: Relic, b: Relic) -> bool: return String(a.id) < String(b.id))
	return _all

static func index_of(relic: Relic) -> int:
	if relic == null:
		return -1
	for i in all().size():
		if all()[i].id == relic.id:
			return i
	return -1

static func at(index: int) -> Relic:
	var list := all()
	return list[index] if index >= 0 and index < list.size() else null

func apply(peer_id: int, group: UnitGroup) -> void:
	## Host-only: the effect, once the relic is home.
	if grants_auto_courier and group != null:
		group.auto_courier = true
	if route_point_bonus != 0:
		GameState.add_route_point_bonus(peer_id, route_point_bonus)
