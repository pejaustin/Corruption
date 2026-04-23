class_name UpgradeData extends Resource

## A single upgrade sold at the Upgrade Altar. Authored as .tres files under
## res://data/upgrades/. The altar reads an Array[UpgradeData] and looks up
## levels via GameState.get_upgrade_level(peer, kind).

enum Kind {
	MINION_HP,
	MINION_DAMAGE,
	RESOURCE_RATE,
	AVATAR_HP,
	AVATAR_DAMAGE,
}

@export var id: StringName
@export var kind: Kind = Kind.MINION_HP
@export var display_name: String
@export_multiline var description: String
@export var cost: int = 15
@export var max_level: int = 3
## How much the multiplier grows per level (e.g. 0.2 = +20% per level).
@export var per_level_bonus: float = 0.2

func get_multiplier(level: int) -> float:
	return 1.0 + level * per_level_bonus
