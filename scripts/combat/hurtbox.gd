class_name Hurtbox extends Area3D

## Damage-target component. Mirrors AttackHitbox on the receiving side: an
## attack's hitbox reports overlaps against Hurtbox areas, not against the
## owning CharacterBody3D. This decouples hit detection from physics
## collision — a minion's body can be sized for navigation without changing
## how big a target they present.
##
## Hosts one or more named CollisionShape3D children. Single-shape setups
## leave the one child enabled and ignore the API. Multi-profile setups
## (e.g. Head / Torso / Legs) enable one at a time and multiply incoming
## damage per profile via profile_damage.
##
## Placement is per-scene: drop it under a BoneAttachment3D for bone-
## following hit regions, or at the actor root for a fixed box. The
## component is agnostic to where it sits.
##
## The owning Actor is resolved by walking up the tree on first request
## and cached thereafter.

## Per-profile incoming-damage multiplier. Missing keys default to 1.0.
@export var profile_damage: Dictionary[StringName, float] = {}

const DEBUG_COLOR: Color = Color(1.0, 0.85, 0.1, 0.35)

var _actor: Actor
var _active_profile: StringName = &""
var _debug_visuals: Array[MeshInstance3D] = []

func _ready() -> void:
	# Only hitboxes monitor us — a hurtbox never needs to detect anything.
	monitoring = false
	monitorable = true
	add_to_group(&"hurtboxes")
	# Adopt whichever shape the scene left enabled as the starting profile.
	# Single-shape hurtboxes "just work" without the scene calling enable().
	for c in get_children():
		if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
			_active_profile = StringName(c.name)
			break
	_debug_visuals = CombatBoxDebug.build_visuals(self, DEBUG_COLOR)
	DebugManager.combat_boxes_toggled.connect(_on_combat_boxes_toggled)
	CombatBoxDebug.set_visibility(_debug_visuals, DebugManager.show_combat_boxes)

func _on_combat_boxes_toggled(new_visible: bool) -> void:
	CombatBoxDebug.set_visibility(_debug_visuals, new_visible)

## Walk up the scene tree to find the owning Actor. Cached after first hit.
func get_actor() -> Actor:
	if _actor and is_instance_valid(_actor):
		return _actor
	var n: Node = get_parent()
	while n:
		if n is Actor:
			_actor = n as Actor
			return _actor
		n = n.get_parent()
	return null

## Incoming-damage multiplier for the active profile (1.0 if inactive or unset).
func get_damage_multiplier() -> float:
	if _active_profile == &"":
		return 1.0
	return profile_damage.get(_active_profile, 1.0)

func get_active_profile() -> StringName:
	return _active_profile

func is_active() -> bool:
	return _active_profile != &""

## Switch active profile by CollisionShape3D child name. Empty picks the
## first shape child — useful for single-shape setups.
func enable(profile: StringName = &"") -> void:
	var target := _resolve_profile(profile)
	if target == &"":
		return
	_active_profile = target
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = c.name != String(target)
	CombatBoxDebug.refresh_active_state(_debug_visuals)

func disable() -> void:
	_active_profile = &""
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
	CombatBoxDebug.refresh_active_state(_debug_visuals)

func _resolve_profile(profile: StringName) -> StringName:
	if profile != &"":
		var node := get_node_or_null(String(profile))
		if node is CollisionShape3D:
			return profile
		push_warning("[Hurtbox] No CollisionShape3D child named '%s'" % profile)
		return &""
	for c in get_children():
		if c is CollisionShape3D:
			return StringName(c.name)
	return &""
