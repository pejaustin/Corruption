class_name DivineIntervention extends Node

## Lose condition: if no gem site is held (CAPTURED) for too long, the gods
## purge the land and all players lose.
## Host-authoritative. Adds tension — somebody must always hold a site.
## Arms after the first capture, so the early game is exempt.

signal intervention_warning(time_remaining: float)
signal intervention_triggered

const GRACE_PERIOD: float = 60.0  # Seconds with zero held sites before divine intervention
const WARNING_START: float = 30.0  # Start warning at this many seconds remaining
const CHECK_INTERVAL: float = 2.0  # How often to check site control

var _timer: float = 0.0  # Time spent with zero held sites
var _check_timer: float = 0.0
var _triggered: bool = false
var _active: bool = false  # Only starts after the first gem site is captured

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _triggered:
		return

	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	var held := _count_held_sites()

	# Don't start counting until somebody has captured a site at least once
	if not _active:
		if held > 0:
			_active = true
		return

	if held == 0:
		_timer += CHECK_INTERVAL
		var remaining = GRACE_PERIOD - _timer
		if remaining <= WARNING_START:
			_sync_warning.rpc(remaining)
		if _timer >= GRACE_PERIOD:
			_trigger_intervention()
	else:
		if _timer > 0:
			_timer = max(0, _timer - CHECK_INTERVAL * 2.0)  # Recover twice as fast
			if _timer <= GRACE_PERIOD - WARNING_START:
				_sync_warning.rpc(-1)  # Clear warning

func _count_held_sites() -> int:
	## Number of gem sites currently CAPTURED by any player.
	var held := 0
	for site in get_tree().get_nodes_in_group(&"gem_sites"):
		if site is GemSite and site.state == GemSite.SiteState.CAPTURED:
			held += 1
	return held

func _trigger_intervention() -> void:
	_triggered = true
	_do_intervention.rpc()

@rpc("authority", "call_local", "reliable")
func _do_intervention() -> void:
	_triggered = true
	intervention_triggered.emit()
	# All players lose
	GameState._announce_loss.rpc()
	print("[DivineIntervention] The gods have purged the corruption. All players lose.")

@rpc("authority", "call_local", "reliable")
func _sync_warning(time_remaining: float) -> void:
	intervention_warning.emit(time_remaining)

func get_timer() -> float:
	return _timer

func get_time_remaining() -> float:
	return max(0, GRACE_PERIOD - _timer)

func is_warning() -> bool:
	return _active and _timer > GRACE_PERIOD - WARNING_START
