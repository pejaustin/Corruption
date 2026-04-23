class_name EldritchRitualEffect extends AbilityEffect

## Eldritch: channel for 5 seconds to mark the Avatar as ritualising.
## The ritual site's bonuses are applied separately (see RitualSite).

const DURATION: float = 5.0

func _on_activate() -> void:
	duration = DURATION

func is_channeling() -> bool:
	return true
