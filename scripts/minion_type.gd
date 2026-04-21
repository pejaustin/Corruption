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

func duplicate_for_match() -> MinionType:
	## Return a match-local copy safe to mutate (upgrades, buffs, domination).
	return duplicate(true) as MinionType
