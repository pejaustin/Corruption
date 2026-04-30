extends ActorState

## Stagger state. Actor is stunned briefly after taking a hit.
## Returns to IdleState when duration elapses.
##
## Duration is measured against NetworkTime.tick so the exit transition
## happens at the same tick on authority and remote peers (no wall-clock
## accumulator that can desync under rollback replay). NetworkTime.tick is
## used instead of the tick argument because MinionActor calls
## `_rollback_tick(delta, 0, true)` outside the rollback loop, so the tick
## arg is always 0 for minions — reading the global tick works for both
## rollback-driven actors and host-authoritative minions.
##
## Hit-react variety: when the model's animation library carries
## `<library>/hit_react_light` and `<library>/hit_react_heavy`, this state
## picks one based on the most recent damage amount. Library is inferred
## from the configured `animation_name` (split on the first slash). Falls
## back to `animation_name` itself when neither variant exists — works
## with or without art added.

## Animation clip names for the variety variants. Library prefix is taken
## from `animation_name` so the same state can serve any avatar archetype.
const HIT_REACT_LIGHT_CLIP: StringName = &"hit_react_light"
const HIT_REACT_HEAVY_CLIP: StringName = &"hit_react_heavy"

var _enter_tick: int = -1

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_enter_tick = NetworkTime.tick
	actor.velocity.x = 0
	actor.velocity.z = 0

## display_enter runs AFTER Actor._on_display_state_changed has played the
## default animation_name (post-rollback, display side). Picking the variant
## here lets us override the base play without racing the rollback loop.
func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_hit_react_variant()

func exit(_next_state: RewindableState, _tick: int) -> void:
	_enter_tick = -1

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	# Non-authority peers enter this state via state_property sync, which
	# bypasses enter(). Latch the first tick we see so elapsed is measured
	# from the same point on every peer.
	if _enter_tick < 0:
		_enter_tick = NetworkTime.tick
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	var elapsed := (NetworkTime.tick - _enter_tick) * NetworkTime.ticktime
	if elapsed >= actor.get_stagger_duration():
		state_machine.transition(&"IdleState")

## Override the default Actor._on_display_state_changed clip with a light/heavy
## variant when the animation library has one. The base method already played
## animation_name; we may swap it here to a more specific clip without breaking
## actors whose library hasn't been authored with the variants.
func _play_hit_react_variant() -> void:
	var anim_player: AnimationPlayer = actor._animation_player
	if anim_player == null:
		return
	var library_prefix := _resolve_library_prefix()
	if library_prefix == "":
		return
	var heavy: bool = actor._last_damage_amount >= Actor.HEAVY_REACT_THRESHOLD
	var clip_name := HIT_REACT_HEAVY_CLIP if heavy else HIT_REACT_LIGHT_CLIP
	var full := "%s/%s" % [library_prefix, clip_name]
	if anim_player.has_animation(full):
		anim_player.play(full)

func _resolve_library_prefix() -> String:
	# `animation_name` is "<library>/<clip>" by project convention. Pull the
	# prefix off so the variant lookup uses the same library as the
	# configured stagger clip.
	var configured: String = animation_name
	var slash: int = configured.find("/")
	if slash <= 0:
		return ""
	return configured.substr(0, slash)
