class_name UltimateFeyEffect extends AbilityEffect

## Tier E — Fey ultimate placeholder. 3s invisibility + speed boost echo.
## Like CamouflageEffect but with shorter duration and harder-to-break
## (we don't auto-cancel on attack like Camouflage does — see
## LightAttackState's cancel(&"camouflage") path; ultimate's id is
## different so it stays through swings). Wraps the same makes_invisible
## query so the rest of the targeting/take_damage pipeline transparently
## treats us as stealthed.

const DURATION: float = 3.0

func _on_activate() -> void:
	duration = DURATION
	_set_model_visible(false)

func _on_expire() -> void:
	_set_model_visible(true)

func makes_invisible() -> bool:
	return true

func _set_model_visible(visible: bool) -> void:
	var actor := caster as Actor
	if actor and actor._model:
		actor._model.visible = visible
