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

func _ready() -> void:
	super()
	rollback_synchronizer.process_settings()
