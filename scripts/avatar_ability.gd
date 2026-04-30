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

# --- Tier E: Resource economy (DORMANT BY DEFAULT) ---
# `cost = 0` and `cost_resource = &""` means the ability is free — current
# behavior. Designers can wire faction-specific resource gates by setting
# `cost > 0` on a per-ability `.tres`. The check fires inside
# `AvatarAbilities.activate_ability` (host-side) and consults `GameState`
# for the controlling peer's pool. See docs/technical/tier-e-implementation.md
# for how to enable.

## Resource cost to activate. 0 = free (default). When > 0, the controlling
## peer's pool of `cost_resource` is checked + drained host-side on activation.
@export var cost: int = 0

## Resource pool key. Reserved for future expansion (corruption / mana / etc.).
## When empty AND cost > 0, the active pool is `corruption_power` (currently
## the only pool defined on GameState).
@export var cost_resource: StringName = &""

# --- Tier E: Slot 4 / Ultimate ---

## When true, this ability is gated by `actor.ultimate_charge` instead of by
## cooldown. Activation requires `actor.ultimate_charge >= ULTIMATE_CHARGE_MAX`
## and drains charge to 0 on cast. Cooldown still ticks afterwards as a
## fallback rhythm; designers can set cooldown low (e.g. 0.5s) so charge is
## the only practical gate.
@export var is_ultimate: bool = false

func duplicate_for_match() -> AvatarAbility:
	## Return a match-local copy safe to mutate (cooldown reductions, etc).
	return duplicate(true) as AvatarAbility
