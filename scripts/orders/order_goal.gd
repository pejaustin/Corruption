class_name OrderGoal

## What a group (or a lone courier) is ordered to do at the end of its route
## (GDD §3: "An order is a route and a goal", Q1, Q9).
##
## Settled by Austin (2026-10-08): the starting goals are "go here" and "assess
## location state and return"; a destination's kind adds goals (a corruption
## site adds "corrupt site"). "Take it" means fight and stay whatever happens;
## "assess" includes coming back. The goals for hauling, capturing and offers
## follow from §5–§6 (hauls by order, live captives for thralls, offers to
## nobles). The advisor's wording for each is a placeholder (ticket #585).

enum Goal {
	GO_HERE,
	ASSESS,
	CORRUPT,
	HAUL,
	CAPTURE,
	GATHER_DEAD,
	OFFER,
	SCOUT,
	RETRIEVE,
	CHECK,
}

## PLACEHOLDER: wording, not written by Austin — what the advisor calls each goal.
const NAMES: Dictionary[int, String] = {
	Goal.GO_HERE: "Go there and hold",
	Goal.ASSESS: "Go, look, and come back",
	Goal.CORRUPT: "Corrupt the site",
	Goal.HAUL: "Haul the goods home",
	Goal.CAPTURE: "Bring back a living human",
	Goal.GATHER_DEAD: "Carry the dead home",
	Goal.OFFER: "Take an offer to the noble",
	Goal.SCOUT: "Send a courier to look and come back",
	Goal.RETRIEVE: "Bring back what lies here",
	Goal.CHECK: "Check that my orders were followed",
}

## Goals a unit group can be given at a destination of `kind` (MapPoint.Kind).
static func goals_for(kind: int, has_groups: bool) -> Array[int]:
	var out: Array[int] = []
	if not has_groups:
		out.append(Goal.SCOUT)
		return out
	out.append(Goal.GO_HERE)
	out.append(Goal.ASSESS)
	match kind:
		MapPoint.Kind.SITE:
			out.append(Goal.CORRUPT)
			out.append(Goal.RETRIEVE)  # PLACEHOLDER: relics lie at sites (#580)
		MapPoint.Kind.RESOURCE:
			out.append(Goal.HAUL)
		MapPoint.Kind.SETTLEMENT, MapPoint.Kind.CITY:
			out.append(Goal.CAPTURE)
			out.append(Goal.OFFER)
	out.append(Goal.GATHER_DEAD)
	# Austin, 2026-10-09: always possible, for any group, so none is ever beyond reach.
	out.append(Goal.CHECK)
	return out

static func name_of(goal: int) -> String:
	return NAMES.get(goal, "?")

## Goals whose group stays at the destination whatever happens.
static func holds_ground(goal: int) -> bool:
	return goal == Goal.GO_HERE or goal == Goal.CORRUPT

## Goals that end with the group walking home.
static func returns_home(goal: int) -> bool:
	return goal in [Goal.ASSESS, Goal.HAUL, Goal.CAPTURE, Goal.GATHER_DEAD, Goal.OFFER, Goal.SCOUT, Goal.RETRIEVE]
