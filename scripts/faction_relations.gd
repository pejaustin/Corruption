class_name FactionRelations

## Static registry for faction-vs-faction relations.
## Default: different non-neutral factions are hostile; NEUTRAL is hostile to all non-neutral
## factions (so aggro works against neutral mobs) but not to itself.
## Call set_relation() at runtime to override for domination, alliances, etc.

enum Relation { HOSTILE, NEUTRAL, ALLIED }

static var _overrides: Dictionary = {}

static func is_hostile(a: int, b: int) -> bool:
	return get_relation(a, b) == Relation.HOSTILE

static func get_relation(a: int, b: int) -> Relation:
	var key := _key(a, b)
	if _overrides.has(key):
		return _overrides[key]
	return _default_relation(a, b)

static func set_relation(a: int, b: int, r: Relation) -> void:
	_overrides[_key(a, b)] = r

static func clear_overrides() -> void:
	_overrides.clear()

static func _default_relation(a: int, b: int) -> Relation:
	if a == b:
		return Relation.ALLIED
	return Relation.HOSTILE

static func _key(a: int, b: int) -> Vector2i:
	return Vector2i(min(a, b), max(a, b))
