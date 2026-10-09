class_name Maneuver extends Resource

## A maneuver a group's leader can learn (GDD §5, Q35/Q36): leaders gain
## experience, learn maneuvers at thresholds, teach them to other groups, and a
## successor remembers only some. Authored as .tres under res://data/maneuvers/.
## PLACEHOLDER: which maneuvers exist and what each does is Austin's (ticket
## #581). The shipped entries are stand-ins that only record that they were
## learned; none changes how a group fights yet.

const DIR: String = "res://data/maneuvers/"

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## Leader experience at which a leader learns this on his own.
@export var experience_required: float = 5.0

static var _all: Array[Maneuver] = []
static var _loaded: bool = false

static func all() -> Array[Maneuver]:
	## Every maneuver, easiest first.
	if not _loaded:
		_loaded = true
		for file in DirAccess.get_files_at(DIR):
			var clean := file.trim_suffix(".remap")
			if clean.ends_with(".tres"):
				var m := load(DIR + clean) as Maneuver
				if m:
					_all.append(m)
		_all.sort_custom(func(a: Maneuver, b: Maneuver) -> bool:
			return a.experience_required < b.experience_required if a.experience_required != b.experience_required else String(a.id) < String(b.id))
	return _all

static func find(maneuver_id: StringName) -> Maneuver:
	for m in all():
		if m.id == maneuver_id:
			return m
	return null
