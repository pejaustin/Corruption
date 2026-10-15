class_name BossHUD
extends CanvasLayer

## Shown to the peer playing a boss form (BossActor): its health and the keys of
## its attacks. A passive view; it never writes gameplay state.

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _attack_list: Label = %AttackList

var _boss: BossActor = null

func _ready() -> void:
	_boss = get_parent() as BossActor
	if _boss == null:
		queue_free()
		return
	_attack_list.text = _describe_attacks()

func _process(_delta: float) -> void:
	visible = _boss.controlling_peer_id == multiplayer.get_unique_id()
	# Read every frame: this HUD is ready before its boss sets his HP.
	_health_bar.max_value = _boss.get_max_hp()
	_health_bar.value = _boss.hp

func _describe_attacks() -> String:
	var lines: Array[String] = []
	for attack in _boss.attacks:
		var events := InputMap.action_get_events(attack.input_action)
		var key := events[0].as_text() if not events.is_empty() else "?"
		lines.push_back("%s: %s" % [key, attack.display_name])
	return "\n".join(lines)
