class_name FactionPassiveFey extends FactionPassive

## Fey passive — bleeding vine DOT.
##
## On a successful hit, applies the `bleed` StatusEffect to the target via the
## actor's `StatusController`. Bleed ticks 5 damage every 30 ticks for 6s with
## up to 3 stacks; data lives in `res://data/status/bleed.tres`.
##
## Tier G migration note: the Tier E iteration of this passive used the
## ad-hoc `Actor.queue_delayed_damage` mechanism. That codepath still exists
## as a generic delayed-damage utility, but new DOT/status work should go
## through `StatusController.apply` so resistance, decay, stack caps, and
## visual hookup all reconcile in one place.

const BLEED_STATUS_ID: StringName = &"bleed"

func on_attack_connect(attacker: Actor, target: Actor, final_damage: int) -> void:
	if attacker == null or target == null or final_damage <= 0:
		return
	if not attacker.multiplayer.is_server():
		return
	# Skip when the trigger is itself a delayed-damage application or a status
	# tick — avoids bleed re-stacking infinitely from its own ticks.
	if attacker.has_meta(&"_passive_inhibit"):
		return
	var controller: StatusController = target.get_status_controller()
	if controller == null:
		return
	var bleed: StatusEffect = StatusEffect.lookup(BLEED_STATUS_ID)
	if bleed == null:
		return
	controller.apply(bleed)
