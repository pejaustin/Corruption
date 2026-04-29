class_name MinionType extends Resource

## Data describing a single minion variant (skeleton, imp, wisp, etc).
## Authored as .tres files under res://data/minions/.
## Shared across all instances by default. Call duplicate_for_match()
## when spawning a minion so per-instance buffs (upgrades, domination)
## cannot bleed back to the on-disk resource.

@export var id: StringName
@export var display_name: String
@export var faction: GameConstants.Faction = GameConstants.Faction.NEUTRAL

@export_group("Stats")
@export var hp: int = 40
@export var damage: int = 10
@export var speed: float = 3.5
@export var cost: int = 8

@export_group("Combat Tuning")
@export var aggro_radius: float = 8.0
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.5

@export_group("Presentation")
@export var color: Color = Color.WHITE
@export var icon: Texture2D

@export_group("Behavior")
## Trait-tag consumed by minion AI and MinionManager (raise_dead, stealth, dominate, ...).
@export var trait_tag: StringName

@export_group("Retreat")
## When true, this minion's combat states yield to RetreatState once HP drops
## below retreat_hp_threshold. Opt-in — most fighters fight to the death; only
## minions whose role includes "carry intel home" (some scouts, info-couriers,
## retreat-trained warband units) flip this on. Couriers / advisors / bosses
## leave it false because their state machines own their own retreat semantics
## or aren't retreat-shaped at all.
@export var can_retreat: bool = false
## Fraction of max HP at or below which a retreat-capable minion breaks off
## and heads home. 0.3 = retreat at 30% HP. Ignored when can_retreat is false.
@export var retreat_hp_threshold: float = 0.3

func duplicate_for_match() -> MinionType:
	## Return a match-local copy safe to mutate (upgrades, buffs, domination).
	return duplicate(true) as MinionType
