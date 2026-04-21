class_name FactionData

## Thin static façade over FactionProfile + MinionCatalog. Profiles live in
## res://data/factions/*.tres and carry identity/colors/abilities; the catalog
## at res://data/minion_catalog.tres lists all minion scenes. Minion rosters
## per faction are derived from the catalog (MinionType.faction drives grouping).

const _PROFILES := {
	GameConstants.Faction.UNDEATH:    preload("res://data/factions/undeath.tres"),
	GameConstants.Faction.DEMONIC:    preload("res://data/factions/demonic.tres"),
	GameConstants.Faction.NATURE_FEY: preload("res://data/factions/nature_fey.tres"),
	GameConstants.Faction.ELDRITCH:   preload("res://data/factions/eldritch.tres"),
}

const _CATALOG: MinionCatalog = preload("res://data/minion_catalog.tres")

static func get_profile(faction: int) -> FactionProfile:
	return _PROFILES.get(faction, _PROFILES[GameConstants.Faction.UNDEATH])

static func get_catalog() -> MinionCatalog:
	return _CATALOG

static func get_minion_roster(faction: int) -> Array[MinionType]:
	return _CATALOG.minion_types_for_faction(faction)

static func get_default_minion(faction: int) -> MinionType:
	var roster: Array[MinionType] = get_minion_roster(faction)
	return roster[0] if roster.size() > 0 else null

static func get_minion_scene_for_id(type_id: StringName) -> PackedScene:
	return _CATALOG.scene_for_id(type_id)

static func get_avatar_abilities(faction: int) -> Array[AvatarAbility]:
	return get_profile(faction).avatar_abilities
