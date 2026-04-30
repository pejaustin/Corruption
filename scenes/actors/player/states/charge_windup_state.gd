extends PlayerState

## Tier D — heavy-charge windup. Entered from HeavyAttackState when the
## player keeps the heavy button held past `CHARGE_HOLD_THRESHOLD_TICKS`.
## Plays the charge_loop animation while the button is held; on release
## transitions to ChargeReleaseState which picks an attack profile based on
## charge_level.
##
## Cancel grammar: Roll cancels (loses the charge — gameplay-as-design,
## charge is a commitment beat). No other interrupts.
##
## Networking: stamps `actor.charge_start_tick` on enter (state_property);
## ChargeReleaseState reads the synced value to recompute charge_level
## deterministically across rollback resim.
##
## Animation: prefer `<library>/heavy_charge_loop` (per asset checklist).
## Falls back silently to `animation_name` (configured to a stagger or idle
## clip in the scene) when the loop isn't authored.

const CHARGE_LOOP_CLIP: StringName = &"heavy_charge_loop"

func enter(_previous_state: RewindableState, _tick: int) -> void:
	# Stamp the charge tick — this is the load-bearing state_property for
	# ChargeReleaseState's level computation.
	actor.charge_start_tick = NetworkTime.tick
	action_locked = true
	cancel_whitelist = [&"RollState", &"BackstepState"]
	# Charge breaks any in-progress combo — heavy/charge is its own beat.
	actor.combo_step = 0
	actor.velocity.x = 0
	actor.velocity.z = 0

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_charge_loop()

func exit(_next_state: RewindableState, _tick: int) -> void:
	# Only clear charge_start_tick when the next state isn't ChargeReleaseState
	# — the release reads the tick on enter, which fires AFTER our exit. Clean
	# up after a roll-cancel (lose the charge) or any other non-release exit.
	if _next_state == null or _next_state.name != &"ChargeReleaseState":
		actor.charge_start_tick = -1

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	if try_roll():
		return
	# Hold horizontal velocity at 0; charging drains commitment, no scoot.
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	# Released? Fire the release. The release state reads
	# `actor.charge_start_tick` to compute the charge level — a tap-and-release
	# fires a weak release, a long hold fires a strong one. The decision is
	# inside ChargeReleaseState.enter so this state stays simple.
	if not get_heavy_attack():
		state_machine.transition(&"ChargeReleaseState")
		return

func _play_charge_loop() -> void:
	var anim: AnimationPlayer = actor._animation_player
	if anim == null:
		return
	var library := _resolve_library_prefix()
	if library == "":
		return
	var full: String = "%s/%s" % [library, CHARGE_LOOP_CLIP]
	if anim.has_animation(full):
		anim.play(full)

func _resolve_library_prefix() -> String:
	var configured: String = animation_name
	var slash: int = configured.find("/")
	if slash <= 0:
		return ""
	return configured.substr(0, slash)
