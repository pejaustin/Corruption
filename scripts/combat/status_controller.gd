class_name StatusController extends Node

## Tier G — per-actor live state for active StatusEffects.
##
## Hangs off an Actor as a `StatusController` child node. Owns an
## `Array[ActiveStatus]` of currently-running effects; ticks each on the
## host's `_rollback_tick`; encodes the active list into the
## `active_status_ids: PackedStringArray` state_property so clients
## reconstruct from the same data.
##
## Authority model: **host-only mutation**. Clients receive `active_status_ids`
## via the RollbackSynchronizer, decode in `_rollback_tick`, and rebuild the
## local `_active` array. The catalog (StatusEffect.lookup) is shared, so
## clients only need ids + start ticks + stacks to mirror state.
##
## Damage-tick application:
## - `tick_active(delta)` runs every host rollback tick. Each ActiveStatus
##   that's hit its tick_interval gate calls `_apply_tick`, which fires the
##   data-driven `damage_per_tick` through `Actor.take_damage` (so block /
##   parry / posture / lifesteal interact correctly).
## - The `subclass.on_tick` hook fires AFTER the data-driven damage, so
##   subclass behavior layers on top.
##
## Aggregate queries:
## - `get_movement_mult` / `get_attack_speed_mult` multiply across all
##   active statuses. Move states / attack states already call these
##   on `Actor` — Tier G threads them through here so the StatusController
##   becomes the single source of truth for combat modifiers.
##
## Visuals:
## - `visual_scene` instances are added as children of the affected actor
##   on apply, freed on expire. Resimulation-safe: spawn / free are gated
##   by `_is_resimulating` to avoid stacking on rewinds.

## Inner class: per-actor live state for one StatusEffect. Mirrored on every
## peer via the encoded `active_status_ids` state_property.
class ActiveStatus:
	var status: StatusEffect
	var enter_tick: int = 0
	var last_tick_fired: int = -1
	var stacks: int = 1
	var visual_instance: Node = null

	func _init(p_status: StatusEffect, p_enter_tick: int, p_stacks: int = 1) -> void:
		status = p_status
		enter_tick = p_enter_tick
		stacks = p_stacks
		last_tick_fired = -1

## Name of the rollback state_property exposed by this controller. Register
## as `"StatusController:active_status_ids"` on the parent actor's
## RollbackSynchronizer state_properties array.
const ACTIVE_STATUS_IDS_PROPERTY: StringName = &"active_status_ids"

## Host-authored, rollback-synced encoded list of `<id>:<enter_tick>:<stacks>`
## strings — one per active status. Clients decode in `_rollback_tick` and
## rebuild `_active` from it, looking up the StatusEffect resource via
## `StatusEffect.lookup`. Empty array = no active statuses.
##
## Wire it on the actor's RollbackSynchronizer with:
##   "StatusController:active_status_ids"
var active_status_ids: PackedStringArray = PackedStringArray()

## Local mirror — host writes, clients rebuild from `active_status_ids`.
var _active: Array[ActiveStatus] = []

## The Actor that owns this controller. Resolved in _ready by walking up
## one level (the controller is always a direct child of an Actor).
var _owner_actor: Actor = null

## Cached signature of the most recently encoded active list. When the
## host's mutate path stamps a new signature, the encoder writes
## `active_status_ids` for sync. Skipping unchanged ticks keeps the
## state-prop traffic minimal at high tick rates.
var _last_encoded_signature: String = ""

func _ready() -> void:
	_owner_actor = get_parent() as Actor
	if _owner_actor == null:
		push_warning("[StatusController] parent is not an Actor: %s" % get_parent())

# --- Public API (host-authoritative writes) ---

## Apply or refresh `status` on the owning actor. Host-side; clients see
## the change after the next state-prop sync. If the status is already
## active and `refresh_on_apply` is true, the duration window resets. If
## `max_stacks > 1`, the stack count is incremented up to the cap.
##
## Returns the resulting ActiveStatus, or null if the status had no effect
## (e.g. duplicate apply on a non-refreshing, single-stack status).
func apply(status: StatusEffect) -> ActiveStatus:
	if status == null:
		return null
	if _owner_actor == null:
		return null
	if not _is_host():
		# Defensive — apply should only be called host-side. Bail rather
		# than silently writing local-only state that will desync on next
		# sync.
		return null
	var existing := _find(status.id)
	if existing != null:
		# Existing status — refresh / stack.
		if status.max_stacks > 1 and existing.stacks < status.max_stacks:
			existing.stacks += 1
		if status.refresh_on_apply:
			existing.enter_tick = NetworkTime.tick
			# Reset last_tick_fired so the freshly-extended duration starts
			# its tick clock over — bleed re-applied at tick 100 fires its
			# next tick at 100 + interval, not at the old schedule.
			existing.last_tick_fired = NetworkTime.tick
		# Subclass hook gets the new stack count.
		status.on_apply(_owner_actor, existing.stacks)
		_encode()
		return existing
	# Fresh apply.
	var fresh := ActiveStatus.new(status, NetworkTime.tick, 1)
	fresh.last_tick_fired = NetworkTime.tick
	_active.append(fresh)
	_spawn_visual(fresh)
	status.on_apply(_owner_actor, 1)
	_encode()
	return fresh

## Remove an active status by id. Host-side. Idempotent — no-op when not
## active. Fires the StatusEffect.on_expire hook.
func clear(id: StringName) -> void:
	if not _is_host():
		return
	var idx := _index_of(id)
	if idx < 0:
		return
	var entry := _active[idx]
	_active.remove_at(idx)
	_free_visual(entry)
	if entry.status != null:
		entry.status.on_expire(_owner_actor)
	_encode()

## Returns the ActiveStatus for `id`, or null if not active. Read-only.
func get_status(id: StringName) -> ActiveStatus:
	return _find(id)

## True iff a status with `id` is currently active.
func has_status(id: StringName) -> bool:
	return _find(id) != null

# --- Aggregate queries (consumed by Actor / states) ---

## Multiplicative movement-speed modifier across all active statuses. 1.0
## when nothing's active. Move states multiply this against their nominal
## walk/run speed in addition to `Actor.get_movement_speed_mult`.
func get_movement_mult() -> float:
	var m: float = 1.0
	for entry in _active:
		if entry.status != null:
			m *= entry.status.move_speed_mult
	return m

## Multiplicative attack-speed modifier across all active statuses. 1.0
## when nothing's active. Light/heavy attack states read this on entry to
## drive `AnimationPlayer.speed_scale`.
func get_attack_speed_mult() -> float:
	var m: float = 1.0
	for entry in _active:
		if entry.status != null:
			m *= entry.status.attack_speed_mult
	return m

# --- Tick (called from Actor._rollback_tick) ---

## Run one rollback tick of all active statuses.
##
## Host: fire periodic `damage_per_tick` (and the subclass hook) for any
## status whose interval has elapsed; expire statuses whose duration ran
## out. Clients: decode the synced `active_status_ids` and rebuild the
## local `_active` mirror.
func tick_active(delta: float) -> void:
	if _owner_actor == null:
		return
	if _is_host():
		_tick_host(delta)
	else:
		_decode_if_changed()

# --- Host-side internals ---

func _tick_host(_delta: float) -> void:
	if _active.is_empty():
		return
	var i: int = 0
	var current_tick: int = NetworkTime.tick
	var changed: bool = false
	while i < _active.size():
		var entry := _active[i]
		var st := entry.status
		if st == null:
			_active.remove_at(i)
			changed = true
			continue
		# Periodic tick fire.
		if st.tick_interval_ticks > 0:
			var due_tick: int = entry.last_tick_fired + st.tick_interval_ticks
			if current_tick >= due_tick:
				_apply_tick(entry)
				entry.last_tick_fired = due_tick
				# If `take_damage` killed the actor, stop iterating — the
				# status loop is moot once the owner's gone.
				if not is_instance_valid(_owner_actor) or _owner_actor.hp <= 0:
					return
		# Expire when duration runs out (skip when permanent).
		if st.duration_ticks >= 0:
			var expire_tick: int = entry.enter_tick + st.duration_ticks
			if current_tick >= expire_tick:
				_active.remove_at(i)
				_free_visual(entry)
				st.on_expire(_owner_actor)
				changed = true
				continue
		i += 1
	# Always re-encode at end-of-tick so client sync stays current. Cheap
	# when nothing changed (the signature compare in `_encode` short-
	# circuits without writing).
	if changed:
		_encode()

## Fire a single tick on `entry` — applies the data-driven damage_per_tick
## and runs the subclass hook. Damage is host-authoritative via the
## standard `take_damage` path; the source is null because the original
## attacker may have left the world. Status passives that need attribution
## (lifesteal etc.) should subclass and pass a tracked source.
func _apply_tick(entry: ActiveStatus) -> void:
	var st := entry.status
	if st == null:
		return
	if st.damage_per_tick != 0 and is_instance_valid(_owner_actor):
		# Per-stack scaling: data-driven. Each stack contributes its own
		# damage chunk.
		var dmg: int = st.damage_per_tick * entry.stacks
		# Mark the damage type for resistance lookup. Same `_pending_*` meta
		# pattern used by Tier C posture (status damage doesn't enter the
		# block / parry path because there's no source actor — but the type
		# tag still flows to the resistance multiplier in take_damage).
		_owner_actor.set_meta(&"_pending_damage_type", st.damage_type)
		_owner_actor.take_damage(dmg, null)
		_owner_actor.remove_meta(&"_pending_damage_type")
	st.on_tick(_owner_actor, entry.stacks)

## Encode the active list into `active_status_ids` for state-prop sync.
## Format per entry: `"<id>:<enter_tick>:<stacks>"`. Idempotent — when the
## encoded signature is unchanged, the PackedStringArray isn't rewritten,
## avoiding spurious property-changed fires.
func _encode() -> void:
	var arr: PackedStringArray = PackedStringArray()
	arr.resize(_active.size())
	for i in _active.size():
		var entry := _active[i]
		var sid: String = String(entry.status.id) if entry.status != null else ""
		arr[i] = "%s:%d:%d" % [sid, entry.enter_tick, entry.stacks]
	var sig: String = ",".join(arr)
	if sig == _last_encoded_signature:
		return
	active_status_ids = arr
	_last_encoded_signature = sig

# --- Client-side reconstruction ---

func _decode_if_changed() -> void:
	var sig: String = ",".join(active_status_ids)
	if sig == _last_encoded_signature:
		return
	_last_encoded_signature = sig
	# Rebuild from scratch — the active set is small, no need for diffing.
	# Free any prior visuals before clearing so the new set's visuals come
	# in clean.
	for entry in _active:
		_free_visual(entry)
	_active.clear()
	for raw in active_status_ids:
		var entry := _decode_entry(String(raw))
		if entry != null:
			_active.append(entry)
			_spawn_visual(entry)

func _decode_entry(raw: String) -> ActiveStatus:
	var parts := raw.split(":")
	if parts.size() != 3:
		return null
	var id := StringName(parts[0])
	var enter_tick := int(parts[1])
	var stacks := int(parts[2])
	var status := StatusEffect.lookup(id)
	if status == null:
		return null
	var entry := ActiveStatus.new(status, enter_tick, stacks)
	entry.last_tick_fired = enter_tick
	return entry

# --- Visual lifecycle ---

func _spawn_visual(entry: ActiveStatus) -> void:
	if entry == null or entry.status == null or entry.status.visual_scene == null:
		return
	if _is_resimulating():
		return
	if not is_instance_valid(_owner_actor):
		return
	var inst := entry.status.visual_scene.instantiate()
	if inst == null:
		return
	_owner_actor.add_child(inst)
	entry.visual_instance = inst

func _free_visual(entry: ActiveStatus) -> void:
	if entry == null:
		return
	if entry.visual_instance and is_instance_valid(entry.visual_instance):
		entry.visual_instance.queue_free()
	entry.visual_instance = null

# --- Helpers ---

func _find(id: StringName) -> ActiveStatus:
	for entry in _active:
		if entry.status != null and entry.status.id == id:
			return entry
	return null

func _index_of(id: StringName) -> int:
	for i in _active.size():
		var entry := _active[i]
		if entry.status != null and entry.status.id == id:
			return i
	return -1

func _is_host() -> bool:
	if multiplayer == null:
		return true
	return multiplayer.is_server()

func _is_resimulating() -> bool:
	return NetworkRollback.is_rollback()
