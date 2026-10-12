class_name GoodFaction extends Node

## The good faction's slow growth toward a draw (GDD §9 "Draw", Q29/Q30).
## Replaces DivineIntervention's loss timer.
##
## Every growth step (MatchConfig.good_growth_interval(), set by match pace):
## - corruption thresholds rise for every site (threshold_scale),
## - every STEPS_PER_LOST_SITE steps one site becomes permanently unusable,
## - a flavour moment plays (placeholder: a message to every player),
## - late in the round (from MARCH_FROM_STEP), it marches on a tower, adding
##   pressure toward an ending (Austin, 2026-10-12, #575).
## When the holy site's threshold passes what any army could bring, the city
## centre can no longer be corrupted and the match ends in a draw.
## Host-authoritative; the step count is mirrored to clients.

signal grew(step: int)
signal flavour_moment(text: String)

## PLACEHOLDER: tuning, not designed — how much each growth step raises every
## site's strength threshold (multiplicative).
const THRESHOLD_GROWTH_PER_STEP: float = 0.15
## PLACEHOLDER: tuning — every this many growth steps one site goes dark.
const STEPS_PER_LOST_SITE: int = 2
## PLACEHOLDER: tuning — the growth step at which the city centre can no
## longer be corrupted and the match is drawn (with the NORMAL pace interval,
## 15 steps × 360 s = 90 minutes).
const DRAW_AT_STEP: int = 15
## PLACEHOLDER: tuning — the growth step from which it marches on towers.
const MARCH_FROM_STEP: int = 10
## PLACEHOLDER: tuning — soldiers in each march (plus one per step past the first march).
const MARCH_SIZE: int = 6
## PLACEHOLDER: unit type that marches.
const MARCH_UNIT: StringName = &"holy_knight"
## PLACEHOLDER: not written by Austin — flavour lines for growth moments.
const FLAVOUR_LINES: Array[String] = [
	"PLACEHOLDER: bells ring out across the land.",
	"PLACEHOLDER: a light kindles over the city.",
	"PLACEHOLDER: pilgrims crowd the roads to the holy site.",
]

## Growth steps taken so far. Static so sites can read it without a lookup.
static var step: int = 0

var _timer: float = 0.0
var _drawn: bool = false

static func threshold_scale() -> float:
	return 1.0 + THRESHOLD_GROWTH_PER_STEP * float(step)

func _ready() -> void:
	step = 0

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _drawn:
		return
	_timer += delta
	if _timer < MatchConfig.good_growth_interval():
		return
	_timer = 0.0
	_grow()

func get_time_to_next_step() -> float:
	return maxf(0.0, MatchConfig.good_growth_interval() - _timer)

func _grow() -> void:
	var next := step + 1
	var lost_site: NodePath = NodePath()
	if next % STEPS_PER_LOST_SITE == 0:
		var site := _pick_site_to_lose()
		if site:
			site.make_unusable()
			lost_site = site.get_path()
	var line: String = FLAVOUR_LINES[(next - 1) % FLAVOUR_LINES.size()]
	_sync_step.rpc(next, line)
	if next >= MARCH_FROM_STEP:
		march_on_tower(next - MARCH_FROM_STEP)
	if next >= DRAW_AT_STEP:
		_drawn = true
		# The city centre can no longer be corrupted: no gauntlet starts or goes on.
		HolySite.lock_all(get_tree())
		GameState.announce_draw()

func march_on_tower(extra: int = 0) -> Tower:
	## Host: send an army from the city centre at one tower. Returns the target.
	var target := pick_tower_to_march_on()
	var mm := get_tree().current_scene.get_node_or_null(^"MinionManager") as MinionManager
	if target == null or mm == null:
		return null
	var at: Node3D = target.courier_spawn if target.courier_spawn else target
	var from := HolySite.city_centre(get_tree())
	for i in MARCH_SIZE + extra:
		var offset := Vector3(float(i % 3) * 1.5, 0.5, float(i / 3) * 1.5)
		mm.spawn_neutral_minion(from + offset, MARCH_UNIT, at.global_position)
	return target

func pick_tower_to_march_on() -> Tower:
	## PLACEHOLDER: rule — it marches on the tower of whoever holds the most
	## sites (ties: the lowest slot).
	var best: Tower = null
	var best_held := -1
	for t in Tower.in_slot_order(get_tree()):
		if t.owner_peer_id <= 0:
			continue
		var held := GameState.count_held_sites(t.owner_peer_id)
		if held > best_held:
			best_held = held
			best = t
	return best

func _pick_site_to_lose() -> CorruptionSite:
	## The neutral site nobody holds goes first; failing that, any held one.
	## Never a tower or the holy site.
	var candidates: Array[CorruptionSite] = []
	for node in GameState.get_all_sites():
		var site := node as CorruptionSite
		if site == null or site.permanent or site.unusable:
			continue
		if site.grants(SiteCapability.HOLY_SITE):
			continue
		candidates.append(site)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: CorruptionSite, b: CorruptionSite) -> bool:
		return int(a.is_held()) < int(b.is_held()))
	return candidates[0]

@rpc("authority", "call_local", "reliable")
func _sync_step(new_step: int, line: String) -> void:
	step = new_step
	grew.emit(new_step)
	flavour_moment.emit(line)
