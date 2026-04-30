class_name AbilitySlot
extends Control

## Single ability icon in the AbilityCross. Shows the icon, the binding key
## label, and a radial cooldown sweep. Ready-flash pulses briefly when the
## cooldown finishes.
##
## For the fixed light-attack slot (the attack; was `primary_ability` pre–
## Tier D), set is_fixed_primary = true; it displays a placeholder icon,
## never shows a cooldown, and ignores set_ability() / set_cooldown() updates.

@onready var _binding_label: Label = %BindingLabel
@onready var _icon_rect: TextureRect = %AbilityIcon
@onready var _placeholder: ColorRect = %Placeholder
@onready var _cooldown_pie: CooldownPie = %CooldownPie
@onready var _ready_flash: ColorRect = %ReadyFlash

var is_fixed_primary: bool = false
var _ability: AvatarAbility = null

func _ready() -> void:
	_ready_flash.modulate.a = 0.0
	_cooldown_pie.set_progress(0.0)

func set_binding_label(text: String) -> void:
	_binding_label.text = text

func set_ability(ability: AvatarAbility) -> void:
	if is_fixed_primary:
		return
	_ability = ability
	if ability and ability.icon:
		_icon_rect.texture = ability.icon
		_icon_rect.visible = true
		_placeholder.visible = false
	else:
		_icon_rect.visible = false
		_placeholder.visible = true

## cooldown_remaining: seconds left. total: the ability's full cooldown. Pass
## zeros to clear.
func set_cooldown(cooldown_remaining: float, total: float) -> void:
	if is_fixed_primary:
		return
	if cooldown_remaining <= 0.0 or total <= 0.0:
		_cooldown_pie.set_progress(0.0)
		return
	_cooldown_pie.set_progress(cooldown_remaining / total)

func flash_ready() -> void:
	if is_fixed_primary:
		return
	var tween := create_tween()
	_ready_flash.modulate.a = 0.8
	tween.tween_property(_ready_flash, "modulate:a", 0.0, 0.35)
