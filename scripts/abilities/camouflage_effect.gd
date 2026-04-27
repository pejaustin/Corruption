class_name CamouflageEffect extends AbilityEffect

## Nature/Fey: Avatar turns invisible for 10 seconds.
## Breaks on attack (AvatarAbilities.cancel is called by AttackState).

const DURATION: float = 10.0

func _on_activate() -> void:
	duration = DURATION
	_set_model_visible(false)

func _on_expire() -> void:
	_set_model_visible(true)

func makes_invisible() -> bool:
	return true

func _set_model_visible(visible: bool) -> void:
	var actor := caster as AvatarActor
	if actor and actor._model:
		actor._model.visible = visible
