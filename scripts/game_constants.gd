class_name GameConstants

const MAX_PLAYERS: int = 4

## Allegiance of the good faction (the humans, the Paladin when no player holds
## him). Every other allegiance is a player's peer id. Hostility is by
## allegiance, not faction, because in the MVP every player is Undead (GDD §1).
const GOOD_SIDE: int = -1

enum Faction {
	UNDEATH,
	DEMONIC,
	NATURE_FEY,
	ELDRITCH,
	NEUTRAL,
}

## Factions a player can pick. MVP: everyone plays Undead (GDD §1, Q7); more
## factions come later, so the enum keeps the old entries.
const PLAYABLE_FACTIONS: Array[int] = [
	Faction.UNDEATH,
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

## PLACEHOLDER: seat colours (one per tower slot), not designed. They tell
## players apart now that everyone is the same faction.
const SEAT_COLORS: Array[Color] = [
	Color(0.35, 0.8, 0.45),
	Color(0.85, 0.3, 0.25),
	Color(0.35, 0.55, 0.95),
	Color(0.9, 0.75, 0.25),
]

## PLACEHOLDER: colour for the good faction (humans, an unheld Paladin), not designed.
const GOOD_COLOR: Color = Color(0.95, 0.92, 0.8)
