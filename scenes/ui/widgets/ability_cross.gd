class_name AbilityCross
extends Control

## Bottom-right diamond of 4 ability slots:
##   - Top:    secondary_ability → avatar abilities[0]
##   - Right:  primary_ability (fixed, represents attack)
##   - Bottom: item_1           → avatar abilities[1]
##   - Left:   item_2           → avatar abilities[2]
##
## Binding labels are read from the InputMap so rebinds update the HUD
## automatically. Ability icons and cooldowns come from AvatarAbilities.

const ACTION_PRIMARY: StringName = &"primary_ability"
const ACTION_SECONDARY: StringName = &"secondary_ability"
const ACTION_ITEM_1: StringName = &"item_1"
const ACTION_ITEM_2: StringName = &"item_2"

@onready var _slot_top: AbilitySlot = %SlotTop
@onready var _slot_right: AbilitySlot = %SlotRight
@onready var _slot_bottom: AbilitySlot = %SlotBottom
@onready var _slot_left: AbilitySlot = %SlotLeft

var _abilities: AvatarAbilities = null

func _ready() -> void:
	_slot_right.is_fixed_primary = true
	_slot_top.set_binding_label(_binding_label_for(ACTION_SECONDARY))
	_slot_right.set_binding_label(_binding_label_for(ACTION_PRIMARY))
	_slot_bottom.set_binding_label(_binding_label_for(ACTION_ITEM_1))
	_slot_left.set_binding_label(_binding_label_for(ACTION_ITEM_2))
	set_process(false)

func setup(abilities: AvatarAbilities) -> void:
	_abilities = abilities
	if abilities == null:
		return
	_refresh_icons()
	abilities.abilities_initialized.connect(_refresh_icons)
	abilities.ability_ready.connect(_on_ability_ready)
	set_process(true)

func _refresh_icons() -> void:
	var list := _abilities.get_abilities()
	_slot_top.set_ability(list[0] if list.size() > 0 else null)
	_slot_bottom.set_ability(list[1] if list.size() > 1 else null)
	_slot_left.set_ability(list[2] if list.size() > 2 else null)

func _process(_delta: float) -> void:
	if _abilities == null:
		return
	var list := _abilities.get_abilities()
	if list.size() > 0:
		_slot_top.set_cooldown(_abilities.get_cooldown(list[0].id), list[0].cooldown)
	if list.size() > 1:
		_slot_bottom.set_cooldown(_abilities.get_cooldown(list[1].id), list[1].cooldown)
	if list.size() > 2:
		_slot_left.set_cooldown(_abilities.get_cooldown(list[2].id), list[2].cooldown)

func _on_ability_ready(ability_id: StringName) -> void:
	var list := _abilities.get_abilities()
	if list.size() > 0 and list[0].id == ability_id:
		_slot_top.flash_ready()
	elif list.size() > 1 and list[1].id == ability_id:
		_slot_bottom.flash_ready()
	elif list.size() > 2 and list[2].id == ability_id:
		_slot_left.flash_ready()

func _binding_label_for(action: StringName) -> String:
	var events := InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			var keycode: int = (ev as InputEventKey).physical_keycode
			if keycode == 0:
				keycode = (ev as InputEventKey).keycode
			return OS.get_keycode_string(keycode)
		if ev is InputEventMouseButton:
			var idx := (ev as InputEventMouseButton).button_index
			match idx:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				_: return "M%d" % idx
	return "?"
