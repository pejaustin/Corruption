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
##   hitbox.enable(&"Impact")           # swap shape, start tracking
##   for body in hitbox.get_new_hits(): # bodies newly overlapping this window
##       body.take_damage(dmg * hitbox.get_damage_multiplier())
##   hitbox.disable()                   # end window, clear log
##
## Single-shape scenes: leave the child named "CollisionShape3D" and call
## enable() with no args — the first shape child is used.

signal profile_changed(profile: StringName)

## Per-profile damage multiplier. Keys are child CollisionShape3D names; values
## multiply the caller's base damage. Missing keys default to 1.0.
@export var profile_damage: Dictionary[StringName, float] = {}

var _active_profile: StringName = &""
var _reported: Array[Node3D] = []

func _ready() -> void:
	_disable_all_shapes()

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
	profile_changed.emit(_active_profile)

## Disable all shapes and clear the per-activation hit log.
func disable() -> void:
	_disable_all_shapes()
	_active_profile = &""
	_reported.clear()

func is_active() -> bool:
	return _active_profile != &""

func get_active_profile() -> StringName:
	return _active_profile

## Damage multiplier for the current profile (1.0 if unset or inactive).
func get_damage_multiplier() -> float:
	if _active_profile == &"":
		return 1.0
	return profile_damage.get(_active_profile, 1.0)

## Bodies currently overlapping that haven't been reported yet this window.
## Reported bodies are remembered until disable() is called.
func get_new_hits() -> Array[Node3D]:
	var hits: Array[Node3D] = []
	if _active_profile == &"":
		return hits
	for body in get_overlapping_bodies():
		if body in _reported:
			continue
		_reported.append(body)
		hits.append(body)
	return hits

## Manually forget a body so it can be hit again (e.g. multi-hit profiles).
func forget(body: Node3D) -> void:
	_reported.erase(body)

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
