class_name Targeting extends Node

## Local-only target tracker for the Avatar.
##
## Soft-target = the actor `find_best_target` would pick right now (camera/aim
## assist only). Hard-target = a sticky lock the player toggled on. Both live
## entirely on the controlling peer — there are NO state_properties, NO RPCs,
## NO `_rollback_tick` paths in this file. Per docs/systems/avatar-combat.md
## §6, target selection is purely camera/local. If overlords ever need to see
## who an avatar has locked, that's a low-rate cosmetic broadcast, not netfox
## state. Resist syncing.

signal target_changed(new_target: Actor, old_target: Actor)
signal lock_state_changed(is_locked: bool)

## Hard cutoff for target eligibility (XZ distance from owner).
const MAX_RANGE: float = 25.0
## Front cone half-angle for the soft picker; ±this in degrees from camera forward.
const SOFT_MAX_ANGLE_DEG: float = 60.0
## Hits arriving from outside this front cone (relative to camera forward) drop
## a hard-lock. ±90° = a hit from anywhere except your front hemisphere.
const HARD_LOCK_BREAK_BEHIND_DEG: float = 90.0
## Tolerance window before LOS-blocked target drops the lock.
const OCCLUSION_GRACE_SEC: float = 0.5
## Physics layer mask for the LOS raycast (world geometry only, layer 1).
const OCCLUSION_RAY_MASK: int = 1
## Per-axis weights for soft-target scoring. Angle dominates — the closer
## actor is preferred only as a tiebreaker among similarly-aimed candidates.
const ANGLE_SCORE_WEIGHT: float = 0.7
const DISTANCE_SCORE_WEIGHT: float = 0.3
## Vertical offset on the target's origin where LOS rays terminate. Roughly
## chest height for the existing avatar/minion rigs.
const TARGET_CHEST_OFFSET: Vector3 = Vector3(0.0, 1.4, 0.0)

@export var owner_actor: Actor
@export var camera: AvatarCamera
@export var reticle_scene: PackedScene

var current_target: Actor = null
var is_locked: bool = false

var _occlusion_timer: float = 0.0
var _reticle: Node3D = null

func _ready() -> void:
	if owner_actor == null:
		owner_actor = get_parent() as Actor
	if owner_actor and owner_actor.has_signal(&"took_damage"):
		# Hit-from-behind drops the hard-lock. The source param is null in
		# Tier A's took_damage emission; the conditional handles it gracefully
		# until later tiers plumb the attacker through.
		owner_actor.took_damage.connect(_on_owner_took_damage)

func _process(delta: float) -> void:
	# Targeting input/state belongs to whoever controls the avatar locally;
	# remote peers see nothing here.
	if not _is_local_controller():
		_release_internal(false)
		return
	if current_target == null:
		return
	if not is_instance_valid(current_target):
		_release_internal(true)
		return
	if not _is_target_alive(current_target):
		_release_internal(true)
		return
	if _xz_distance_to(current_target) > MAX_RANGE:
		_release_internal(true)
		return
	if _is_target_occluded(current_target):
		_occlusion_timer += delta
		if _occlusion_timer >= OCCLUSION_GRACE_SEC:
			_release_internal(true)
			return
	else:
		_occlusion_timer = 0.0

# --- Public API ---

## Return the highest-scored hostile actor in front of the camera within
## SOFT_MAX_ANGLE_DEG and MAX_RANGE, or null. Used both for soft-target hint
## and as the seed for `toggle_lock`.
func find_best_target() -> Actor:
	var candidates := _candidates()
	if candidates.is_empty():
		return null
	var cam_forward := _camera_forward()
	var cam_origin := _camera_origin()
	var best: Actor = null
	var best_score: float = -INF
	for actor in candidates:
		var to_target: Vector3 = actor.global_position - cam_origin
		to_target.y = 0.0
		var dist: float = to_target.length()
		if dist <= 0.0001 or dist > MAX_RANGE:
			continue
		var dir: Vector3 = to_target / dist
		var angle_deg: float = rad_to_deg(acos(clampf(dir.dot(cam_forward), -1.0, 1.0)))
		if angle_deg > SOFT_MAX_ANGLE_DEG:
			continue
		var angle_score: float = 1.0 - (angle_deg / SOFT_MAX_ANGLE_DEG)
		var distance_score: float = 1.0 - (dist / MAX_RANGE)
		var score: float = angle_score * ANGLE_SCORE_WEIGHT + distance_score * DISTANCE_SCORE_WEIGHT
		if score > best_score:
			best_score = score
			best = actor
	return best

## Hard-lock onto target. Becomes a no-op if target is invalid or hostile-test
## fails (defensive — input layer should already have filtered).
func acquire(target: Actor) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not _is_eligible(target):
		return
	var prev: Actor = current_target
	current_target = target
	is_locked = true
	_occlusion_timer = 0.0
	_spawn_reticle()
	if camera:
		camera.look_at_target = true
	target_changed.emit(current_target, prev)
	lock_state_changed.emit(true)

## Drop the hard-lock and clear the target. Soft-target may re-acquire
## next frame if the camera-aim picker still finds someone.
func release() -> void:
	_release_internal(true)

## Soft-toggle: if locked, release. If not locked, lock onto best candidate.
func toggle_lock() -> void:
	if is_locked:
		release()
		return
	var t := find_best_target()
	if t != null:
		acquire(t)

## Pick the next candidate in the requested direction. -1 = left, +1 = right.
## "Left/right" is measured by signed angle around camera forward in the XZ
## plane: candidates with the smallest signed angle in `direction` win.
func cycle_target(direction: int) -> void:
	if direction == 0:
		return
	var candidates := _candidates()
	if candidates.is_empty():
		return
	var cam_forward := _camera_forward()
	var cam_origin := _camera_origin()
	# Build a ranked list of (signed_angle_deg, actor) for everyone in range.
	# Signed angle: positive = to the camera's right, negative = to its left.
	var ranked: Array = []
	for actor in candidates:
		var to_target: Vector3 = actor.global_position - cam_origin
		to_target.y = 0.0
		if to_target.length_squared() < 0.0001:
			continue
		var signed_angle: float = _signed_angle_deg(cam_forward, to_target)
		ranked.append([signed_angle, actor])
	if ranked.is_empty():
		return
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var current_angle: float = INF
	if current_target != null and is_instance_valid(current_target):
		var to_curr: Vector3 = current_target.global_position - cam_origin
		to_curr.y = 0.0
		if to_curr.length_squared() > 0.0001:
			current_angle = _signed_angle_deg(cam_forward, to_curr)
	var pick: Actor = null
	if direction > 0:
		# Smallest angle strictly greater than current; wrap to leftmost on miss.
		for entry in ranked:
			if entry[0] > current_angle + 0.01:
				pick = entry[1]
				break
		if pick == null:
			pick = ranked.front()[1]
	else:
		# Largest angle strictly less than current; wrap to rightmost on miss.
		for i in range(ranked.size() - 1, -1, -1):
			if ranked[i][0] < current_angle - 0.01:
				pick = ranked[i][1]
				break
		if pick == null:
			pick = ranked.back()[1]
	if pick != null and pick != current_target:
		acquire(pick)

# --- Private helpers ---

func _candidates() -> Array[Actor]:
	var out: Array[Actor] = []
	if owner_actor == null:
		return out
	var actors := get_tree().get_nodes_in_group(&"actors")
	for n in actors:
		var a := n as Actor
		if _is_eligible(a):
			out.append(a)
	return out

func _is_eligible(a: Actor) -> bool:
	if a == null or a == owner_actor:
		return false
	if not is_instance_valid(a):
		return false
	if not a.can_take_damage():
		return false
	if not owner_actor.is_hostile_to(a):
		return false
	return true

func _is_target_alive(a: Actor) -> bool:
	if a.has_method("can_take_damage"):
		return a.can_take_damage()
	return a.hp > 0

func _xz_distance_to(a: Actor) -> float:
	var d: Vector3 = a.global_position - owner_actor.global_position
	d.y = 0.0
	return d.length()

func _camera_forward() -> Vector3:
	# AvatarCamera.camera_basis points +Z away from the look direction (Godot
	# camera convention), so the "forward" the player sees is -Z.
	if camera != null:
		return -camera.camera_basis.z.slide(Vector3.UP).normalized()
	# Fallback to model facing if camera is somehow missing during teardown.
	if owner_actor and owner_actor._model:
		return -owner_actor._model.global_transform.basis.z.slide(Vector3.UP).normalized()
	return Vector3.FORWARD

func _camera_origin() -> Vector3:
	if camera != null and camera.camera_3d != null:
		return camera.camera_3d.global_position
	return owner_actor.global_position + TARGET_CHEST_OFFSET

func _signed_angle_deg(forward: Vector3, to_target: Vector3) -> float:
	var f := Vector3(forward.x, 0.0, forward.z).normalized()
	var t := Vector3(to_target.x, 0.0, to_target.z).normalized()
	var dot: float = clampf(f.dot(t), -1.0, 1.0)
	var ang: float = rad_to_deg(acos(dot))
	# Sign by the cross-product Y component: positive = target is to the right.
	var cross_y: float = f.x * t.z - f.z * t.x
	return ang if cross_y >= 0.0 else -ang

func _is_target_occluded(target: Actor) -> bool:
	if owner_actor == null:
		return false
	var space := owner_actor.get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		_camera_origin(),
		target.global_position + TARGET_CHEST_OFFSET,
		OCCLUSION_RAY_MASK,
	)
	# Don't let the avatar's own body block its sightline.
	query.exclude = [owner_actor.get_rid()]
	var hit := space.intersect_ray(query)
	return not hit.is_empty()

func _is_local_controller() -> bool:
	# AvatarActor exposes controlling_peer_id; minions/overlords don't carry
	# Targeting, so the duck-typed check is enough.
	if owner_actor == null:
		return false
	if "controlling_peer_id" in owner_actor:
		return owner_actor.controlling_peer_id == multiplayer.get_unique_id()
	return owner_actor.is_multiplayer_authority()

func _on_owner_took_damage(_amount: int, source: Node) -> void:
	# Tier A leaves source = null until later tiers plumb the attacker actor
	# through take_damage. The behind-attack drop activates automatically when
	# Tier C/D fills it in.
	if not is_locked or source == null:
		return
	var src_actor := source as Actor
	if src_actor == null or not is_instance_valid(src_actor):
		return
	var to_attacker: Vector3 = src_actor.global_position - _camera_origin()
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.0001:
		return
	var ang_deg: float = rad_to_deg(acos(clampf(_camera_forward().dot(to_attacker.normalized()), -1.0, 1.0)))
	if ang_deg > HARD_LOCK_BREAK_BEHIND_DEG:
		release()

func _release_internal(emit: bool) -> void:
	var prev: Actor = current_target
	var was_locked: bool = is_locked
	current_target = null
	is_locked = false
	_occlusion_timer = 0.0
	_despawn_reticle()
	if camera:
		camera.look_at_target = false
	if emit and prev != null:
		target_changed.emit(null, prev)
	if emit and was_locked:
		lock_state_changed.emit(false)

func _spawn_reticle() -> void:
	_despawn_reticle()
	if reticle_scene == null or current_target == null:
		return
	var inst := reticle_scene.instantiate() as Node3D
	if inst == null:
		return
	# Park reticle under the current scene root, NOT the avatar — it follows
	# the locked enemy each frame; nesting under the avatar would drag it.
	var parent := get_tree().current_scene
	if parent == null:
		inst.queue_free()
		return
	parent.add_child(inst)
	if "target" in inst:
		inst.target = current_target
	_reticle = inst

func _despawn_reticle() -> void:
	if _reticle != null and is_instance_valid(_reticle):
		_reticle.queue_free()
	_reticle = null
