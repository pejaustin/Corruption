class_name PlayerActor extends Actor

## Base class for player-controlled actors.
##
## Concrete subtypes:
## - AvatarActor: the shared Paladin vessel (claim/recall, dormant state, 3rd-person)
## - OverlordActor: the per-player tower body (first-person, always active)
##
## Holds only the plumbing both modes need. Mode-specific input, camera, and
## behavior live in the subclasses. Scenes inherit `player_actor.tscn`, which
## in turn inherits `actor.tscn` for the shared Actor base (hp, state machine,
## damage, gravity).

@onready var rollback_synchronizer: RollbackSynchronizer = $RollbackSynchronizer

## When set, the rig is pinned to `_pin_xform` at the end of every rollback
## tick. We can't just snap `global_transform` from outside the tick loop —
## netfox restores the recorded state each on_prepare_tick, so a one-shot set
## gets reverted on the next tick. Re-applying inside _rollback_tick makes
## on_record_tick capture the pinned value, so subsequent restores keep it.
## Used by the War Table to plant the overlord at the stand point.
var _is_pinned: bool = false
var _pin_xform: Transform3D = Transform3D.IDENTITY

func _ready() -> void:
	super()
	rollback_synchronizer.process_settings()

## Pin the rig at `xform` for the duration of an external interaction (War
## Table). Applies the snap immediately AND keeps applying it inside the
## rollback tick so netfox doesn't undo it.
func pin_transform(xform: Transform3D) -> void:
	_is_pinned = true
	_pin_xform = xform
	global_transform = xform
	velocity = Vector3.ZERO

## Stop pinning. The next rollback tick proceeds normally.
func unpin_transform() -> void:
	_is_pinned = false

func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	super._rollback_tick(delta, tick, is_fresh)
	if _is_pinned:
		# Re-apply at the very end so whatever the active state did earlier in
		# the tick (physics_move, gravity) is overwritten. on_record_tick will
		# now capture _pin_xform.
		global_transform = _pin_xform
		velocity = Vector3.ZERO
