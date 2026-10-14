class_name ArenaPanel extends PanelContainer

## The combat test arena's setup panel (Esc shows and hides it). Edits an
## ArenaConfig; the arena (arena.gd) does the networking and runs the round.

signal offline_pressed
signal host_pressed
signal join_pressed(address: String)
signal fight_pressed(config: ArenaConfig)
signal spawn_pressed(config: ArenaConfig)

var _attacks: Array[BossAttack] = []
var _minion_ids: Array[StringName] = []

@onready var _offline_button: Button = %OfflineButton
@onready var _host_button: Button = %HostButton
@onready var _join_address: LineEdit = %JoinAddress
@onready var _join_button: Button = %JoinButton
@onready var _role_option: OptionButton = %RoleOption
@onready var _level_spin: SpinBox = %LevelSpin
@onready var _attack_list: ItemList = %AttackList
@onready var _boss_hp_spin: SpinBox = %BossHpSpin
@onready var _boss_damage_spin: SpinBox = %BossDamageSpin
@onready var _opponent_option: OptionButton = %OpponentOption
@onready var _minion_option: OptionButton = %MinionOption
@onready var _count_spin: SpinBox = %CountSpin
@onready var _fight_button: Button = %FightButton
@onready var _spawn_button: Button = %SpawnButton
@onready var _status_label: Label = %StatusLabel

func _ready() -> void:
	_offline_button.pressed.connect(offline_pressed.emit)
	_host_button.pressed.connect(host_pressed.emit)
	_join_button.pressed.connect(func() -> void: join_pressed.emit(_join_address.text.strip_edges()))
	_fight_button.pressed.connect(func() -> void: fight_pressed.emit(read_config()))
	_spawn_button.pressed.connect(func() -> void: spawn_pressed.emit(read_config()))
	# Data, not nodes: one list row per attack and one menu entry per minion type.
	_attacks = ArenaConfig.all_boss_attacks()
	for attack in _attacks:
		_attack_list.add_item("%s (%s)" % [attack.display_name.trim_prefix("PLACEHOLDER: "), attack.input_action])
	var catalog := FactionData.get_catalog()
	for packed in catalog.scenes:
		var mtype := catalog.minion_type_for_scene(packed)
		if mtype:
			_minion_ids.push_back(mtype.id)
	_minion_ids.sort()
	for id in _minion_ids:
		_minion_option.add_item(String(id))
	set_network_chosen(false, false)

func show_config(config: ArenaConfig) -> void:
	_role_option.select(config.role)
	_level_spin.value = config.control_level
	_attack_list.deselect_all()
	for i in _attacks.size():
		if _attacks[i] in config.boss_attacks:
			_attack_list.select(i, false)
	_boss_hp_spin.value = config.boss_hp
	_boss_damage_spin.value = config.boss_damage
	_opponent_option.select(config.opponent)
	var minion_index := _minion_ids.find(config.minion_type)
	if minion_index >= 0:
		_minion_option.select(minion_index)
	_count_spin.value = config.minion_count

func read_config() -> ArenaConfig:
	var config := ArenaConfig.new()
	config.role = _role_option.selected as ArenaConfig.Role
	config.control_level = int(_level_spin.value)
	for i in _attack_list.get_selected_items():
		config.boss_attacks.push_back(_attacks[i])
	config.boss_hp = int(_boss_hp_spin.value)
	config.boss_damage = int(_boss_damage_spin.value)
	config.opponent = _opponent_option.selected as ArenaConfig.Opponent
	if _minion_option.selected >= 0:
		config.minion_type = _minion_ids[_minion_option.selected]
	config.minion_count = int(_count_spin.value)
	return config

func set_network_chosen(chosen: bool, is_host: bool) -> void:
	## Pick offline, host or join once; then only the host sets up fights.
	for button: Button in [_offline_button, _host_button, _join_button]:
		button.disabled = chosen
	_join_address.editable = not chosen
	_fight_button.disabled = not (chosen and is_host)
	_spawn_button.disabled = not (chosen and is_host)

func set_status(text: String) -> void:
	_status_label.text = text
