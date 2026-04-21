class_name FactionProfile extends Resource

## Identity + avatar data for one faction. Minion rosters are NOT listed here —
## they are derived at runtime from the MinionCatalog by reading each scene's
## MinionType.faction export. Authored as .tres files under res://data/factions/.

@export var id: GameConstants.Faction = GameConstants.Faction.NEUTRAL
@export var display_name: String
@export var color: Color = Color.WHITE
@export var avatar_abilities: Array[AvatarAbility] = []

## Optional: swap in faction-specific Avatar art/abilities on activation.
## Empty means "use the default Paladin scene".
@export var default_avatar_scene: PackedScene
