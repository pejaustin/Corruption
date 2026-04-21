class_name GameConstants

const MAX_PLAYERS: int = 4

enum Faction {
	UNDEATH,
	DEMONIC,
	NATURE_FEY,
	ELDRITCH,
	NEUTRAL,
}

## Factions a player can pick. NEUTRAL is not selectable.
const PLAYABLE_FACTIONS: Array[int] = [
	Faction.UNDEATH,
	Faction.DEMONIC,
	Faction.NATURE_FEY,
	Faction.ELDRITCH,
]

static var faction_names := {
	Faction.NEUTRAL: "Neutral",
	Faction.UNDEATH: "Undeath",
	Faction.DEMONIC: "Demonic",
	Faction.NATURE_FEY: "Nature/Fey",
	Faction.ELDRITCH: "Eldritch",
}

enum PlayerMode {
	OVERLORD,
	AVATAR,
}

static var faction_colors := {
	Faction.NEUTRAL: Color(0.6, 0.6, 0.6),
	Faction.UNDEATH: Color(0.4, 0.8, 0.4),
	Faction.DEMONIC: Color(0.9, 0.2, 0.1),
	Faction.NATURE_FEY: Color(0.2, 0.7, 0.3),
	Faction.ELDRITCH: Color(0.5, 0.2, 0.8),
}
