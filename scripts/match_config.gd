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

## World size (Austin, 2026-10-10): the same map at three sizes, picked by the host in the lobby like the pace;
## GameState.world_size holds it for the match. 2 km is Austin's map as authored; 400 m is a miniature for quick tests
## and 6 km a larger one for getting a sense of distance (art/world/README.md, "Sizes").
enum WorldSize { SMALL, NORMAL, LARGE }

const WORLD_SIZE_NAMES: Dictionary[int, String] = {
	WorldSize.SMALL: "400 m (quick test)",
	WorldSize.NORMAL: "2 km",
	WorldSize.LARGE: "6 km",
}

## The game world scene per size (the 400 m and 6 km ones are generated: scripts/build/build_world_sizes.gd).
const WORLD_SCENES: Dictionary[int, String] = {
	WorldSize.SMALL: "res://scenes/world/world_400m.tscn",
	WorldSize.NORMAL: "res://scenes/world/world.tscn",
	WorldSize.LARGE: "res://scenes/world/world_6km.tscn",
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

## The size names the tools use (WORLD_SIZE=400m|2km|6km): the same three sizes.
const WORLD_SIZE_BY_NAME: Dictionary[String, int] = {
	"400m": WorldSize.SMALL,
	"2km": WorldSize.NORMAL,
	"6km": WorldSize.LARGE,
}

static func world_scene_named(size_name: String) -> String:
	## The world scene for a tool's size name; an empty or unknown name is the 2 km world.
	return WORLD_SCENES[WORLD_SIZE_BY_NAME.get(size_name, WorldSize.NORMAL)]

static func world_scene() -> String:
	return WORLD_SCENES.get(GameState.world_size, WORLD_SCENES[WorldSize.NORMAL])

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
