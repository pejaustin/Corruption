class_name AvatarAbility extends Resource

## Data describing an Avatar ability (Hellfire Strike, Camouflage, etc).
## Authored as .tres files under res://data/abilities/.
## The effect_scene is instanced at runtime when the ability fires —
## that scene owns the visuals, timing, and gameplay for the effect.

@export var id: StringName
@export var display_name: String
@export var cooldown: float = 8.0
@export_multiline var description: String

## Scene instanced when the ability activates. The scene's root should
## extend AbilityEffect and implement activate(caster).
@export var effect_scene: PackedScene

@export var icon: Texture2D

func duplicate_for_match() -> AvatarAbility:
	## Return a match-local copy safe to mutate (cooldown reductions, etc).
	return duplicate(true) as AvatarAbility
