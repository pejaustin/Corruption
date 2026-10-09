class_name MatchConfig

## Match pace (GDD §1, Q31): 4 players, ~90 minutes by default; a slower setting
## that changes unit move speed and the good faction's growth timer stretches a
## match to 4–5 hours. The host picks it in the lobby; GameState.match_pace
## holds it for the match.

enum Pace { NORMAL, SLOW }

const PACE_NAMES: Dictionary[int, String] = {
	Pace.NORMAL: "Normal (~90 min)",
	Pace.SLOW: "Slow (4–5 h)",
}

## PLACEHOLDER: tuning, not designed — unit move-speed multiplier per pace.
const UNIT_SPEED: Dictionary[int, float] = {
	Pace.NORMAL: 1.0,
	Pace.SLOW: 0.4,
}

## PLACEHOLDER: tuning, not designed — seconds between good-faction growth steps
## per pace (GoodFaction, GDD §9 "Draw").
const GOOD_GROWTH_INTERVAL: Dictionary[int, float] = {
	Pace.NORMAL: 360.0,
	Pace.SLOW: 1200.0,
}

static func unit_speed_multiplier() -> float:
	return UNIT_SPEED.get(GameState.match_pace, 1.0)

static func good_growth_interval() -> float:
	return GOOD_GROWTH_INTERVAL.get(GameState.match_pace, 360.0)

## Each player starts with a ruined tower, the advisor, a few couriers and one
## small group of troops, and no sites (GDD §2, Q38).
## PLACEHOLDER: tuning, not designed — the size of that first group.
const STARTING_GROUP_SIZE: int = 4
## PLACEHOLDER: tuning, not designed — how many couriers wait at the tower.
const STARTING_COURIERS: int = 2
## Order granularity (GDD Q2, ticket #539): how many points an order's route
## may pass through before its destination. Training and relics widen it.
## PLACEHOLDER: tuning, not designed.
const STARTING_ROUTE_POINTS: int = 3
