class_name BossInput extends AvatarInput

## Input for a player-driven boss form (BossActor). Like AvatarInput, authority
## moves to the controlling peer (set_controller) so netfox syncs it from them.
## A boss walks and throws attacks: no run, jump or roll. `attack_pick` is the
## index of the attack asked for this tick (-1 = none), one synced value for all
## the attack keys.

var attack_pick: int = -1

## The input action of each of the boss's attacks, in attack order (set by BossActor).
var attack_actions: Array[StringName] = []

## Host-side driver (BossAI) for a CPU seat or a boss whose peer left.
var boss_ai: BossAI = null

func _gather() -> void:
	if input_enabled and controlling_peer_id == multiplayer.get_unique_id():
		input_dir = Input.get_vector("left", "right", "forward", "backward")
		attack_pick = -1
		for i in attack_actions.size():
			if Input.is_action_pressed(attack_actions[i]):
				attack_pick = i
				break
	elif boss_ai != null and boss_ai.is_driving():
		boss_ai.drive(self)
	else:
		input_dir = Vector2.ZERO
		attack_pick = -1
