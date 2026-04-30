class_name AttackHitbox extends Area3D

## Modular attack hitbox. Hosts one or more named CollisionShape3D children —
## each is an "attack profile" (e.g. Windup, Impact, Recovery). Call enable()
## with a profile name to swap between them during a swing; animation call
## tracks can drive it directly. Per-activation hit reporting prevents the same
## body being damaged twice in one window.
##
## Placement is the scene's concern: drop this under a BoneAttachment3D for
## bone-following hitboxes, or keep it at actor root for a fixed-relative box.
## The component is agnostic to where it sits.
##
## Usage in an attack state:
##   hitbox.enable(&"Impact")              # swap shape, start tracking
##   for hurt in hitbox.get_new_hits():    # Hurtbox areas newly overlapping
##       hurt.get_actor().take_damage(
##           dmg * hitbox.get_damage_multiplier() * hurt.get_damage_multiplier(),
##           attacker)                     # source carries Tier C block/parry causality
##   hitbox.disable()                      # end window, clear log
##
## Hit targets are Hurtbox areas, not CharacterBody3Ds — damage detection
## is decoupled from the actor's physics collider. Each targetable actor
## must host a Hurtbox child somewhere in its tree.
##
## Single-shape scenes: leave the child named "CollisionShape3D" and call
## enable() with no args — the first shape child is used.

signal profile_changed(profile: StringName)

## Per-profile damage multiplier. Keys are child CollisionShape3D names; values
## multiply the caller's base damage. Missing keys default to 1.0.
@export var profile_damage: Dictionary[StringName, float] = {}

const DEBUG_COLOR: Color = Color(1.0, 0.15, 0.15, 0.35)

var _active_profile: StringName = &""
var _reported: Array[Hurtbox] = []
var _debug_visuals: Array[MeshInstance3D] = []

func _ready() -> void:
	_disable_all_shapes()
	_debug_visuals = CombatBoxDebug.build_visuals(self, DEBUG_COLOR)
	DebugManager.combat_boxes_toggled.connect(_on_combat_boxes_toggled)
	CombatBoxDebug.set_visibility(_debug_visuals, DebugManager.show_combat_boxes)

func _on_combat_boxes_toggled(new_visible: bool) -> void:
	CombatBoxDebug.set_visibility(_debug_visuals, new_visible)

## Activate a profile by name (must match a CollisionShape3D child). Empty
## name picks the first CollisionShape3D child — useful for single-shape setups.
## Switching profiles within the same swing preserves the hit log; call disable()
## between swings to reset it.
func enable(profile: StringName = &"") -> void:
	var target := _resolve_profile(profile)
	if target == &"":
		return
	_active_profile = target
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = c.name != String(target)
	CombatBoxDebug.refresh_active_state(_debug_visuals)
	profile_changed.emit(_active_profile)

## Disable all shapes and clear the per-activation hit log.
func disable() -> void:
	_disable_all_shapes()
	_active_profile = &""
	_reported.clear()
	CombatBoxDebug.refresh_active_state(_debug_visuals)

func is_active() -> bool:
	return _active_profile != &""

func get_active_profile() -> StringName:
	return _active_profile

## Damage multiplier for the current profile (1.0 if unset or inactive).
func get_damage_multiplier() -> float:
	if _active_profile == &"":
		return 1.0
	return profile_damage.get(_active_profile, 1.0)

## Hurtbox areas currently overlapping that haven't been reported yet this
## window. Reported hurtboxes are remembered until disable() is called, so
## the same target isn't damaged twice across a Windup → Impact profile
## switch on the same swing.
func get_new_hits() -> Array[Hurtbox]:
	var hits: Array[Hurtbox] = []
	if _active_profile == &"":
		return hits
	for area in get_overlapping_areas():
		var hurt := area as Hurtbox
		if hurt == null:
			continue
		if hurt in _reported:
			continue
		_reported.append(hurt)
		hits.append(hurt)
	return hits

## Manually forget a hurtbox so it can be hit again (e.g. multi-hit profiles).
func forget(hurt: Hurtbox) -> void:
	_reported.erase(hurt)

func _disable_all_shapes() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true

func _resolve_profile(profile: StringName) -> StringName:
	if profile != &"":
		var node := get_node_or_null(String(profile))
		if node is CollisionShape3D:
			return profile
		push_warning("[AttackHitbox] No CollisionShape3D child named '%s'" % profile)
		return &""
	for c in get_children():
		if c is CollisionShape3D:
			return StringName(c.name)
	return &""
