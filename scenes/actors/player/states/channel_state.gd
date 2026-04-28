extends PlayerState

## Avatar is capturing a gem / gem site. Locks the player in place for the
## duration of the paired CaptureChannel. All normal inputs are ignored —
## only the pause menu and the interact key (handled by the interactable,
## which calls capture_channel.request_cancel()) affect the avatar.
##
## The channel itself is host-authoritative; this state just holds the avatar
## still and pops back to Idle the moment the channel ends (completed,
## interrupted, or cancelled).

func enter(_previous_state: RewindableState, _tick: int) -> void:
	actor.velocity = Vector3.ZERO

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	var channel: CaptureChannel = player.active_channel
	if channel == null or not channel.is_active():
		state_machine.transition(&"IdleState")
