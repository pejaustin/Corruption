extends Node3D

## Tier F — hostile-takeover edge case harness. Spawns the REAL AvatarActor
## (with full state machine + abilities + targeting) plus a couple of minions
## so the user can manually trigger takeover scenarios while the avatar is
## mid-attack / mid-roll / mid-charge / mid-riposte. Each scenario kills the
## avatar at a deterministic point in its current state, then logs whether
## the transition / takeover landed cleanly.
##
## Networking is faked with OfflineMultiplayerPeer (mirroring war_table_test).
## multiplayer.is_server() returns true; controlling_peer_id ends up the same
## peer that did the killing, which exercises the influence-fallback path
## rather than hostile-takeover-with-different-owner. That's fine for state-
## machine cleanliness — the question this harness answers is "does the body
## reset cleanly when transferred?", not "does the new owner inherit?".
##
## Hotkeys:
##   1 — Avatar in IdleState → lethal damage. Expected: clean DeathState →
##       respawn delay (~3s) → IdleState at the picked spawn position.
##   2 — Avatar mid-LightAttack → lethal damage. Expected: AttackHitbox is
##       disabled by exit() so no orphaned damage window persists.
##   3 — Avatar mid-Roll → lethal damage. Expected: roll i-frames don't
##       carry to the new owner (respawn invuln supersedes them).
##   4 — Avatar mid-ChargeWindup → lethal damage. Expected: charge_start_tick
##       resets to -1 on respawn (state_property is a member var, but new
##       owner's claim resets the avatar's stats; verify visually).
##   5 — Avatar mid-Riposte → lethal damage. Expected: both attacker and
##       victim states exit cleanly; the riposte-victim minion (if any) also
##       exits its locked state.
##   K — kill avatar manually (no scenario setup, just baseline).
##   R — reset: full HP, restore Idle, clear scenario flags.
##   Esc — release/recapture mouse. Shift+Esc to quit.

const LOCAL_PEER_ID: int = 1

@export var avatar: AvatarActor
@export var minion_manager: MinionManager
@export var status_label: Label

var _scenario_log: PackedStringArray = []

func _enter_tree() -> void:
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _ready() -> void:
	assert(avatar, "Assign avatar in the inspector")
	assert(minion_manager, "Assign minion_manager in the inspector")
	if NetworkTime.has_method("start"):
		NetworkTime.start()
	GameState.player_factions[LOCAL_PEER_ID] = GameConstants.Faction.UNDEATH
	# Wait one frame for MinionManager to set up its container.
	await get_tree().process_frame
	# Claim the avatar so it's an active participant in the harness.
	if avatar.is_dormant:
		GameState._set_avatar.rpc(LOCAL_PEER_ID)
		avatar.activate(LOCAL_PEER_ID)
	_log("harness ready — avatar claimed by peer %d" % LOCAL_PEER_ID)
	_refresh_status()

# --- Scenario triggers ---

func _scenario_idle_kill() -> void:
	_log("scenario 1: idle kill")
	avatar._state_machine.transition(&"IdleState")
	# One-frame yield so the state actually entered before we kill.
	await get_tree().process_frame
	_kill_avatar()

func _scenario_mid_light_attack() -> void:
	_log("scenario 2: mid-LightAttack kill")
	avatar._state_machine.transition(&"LightAttackState")
	await get_tree().process_frame
	# Mid-swing — hitbox should be active here in some attacks.
	_kill_avatar()
	# Verify hitbox is disabled after death by inspecting it next frame.
	await get_tree().process_frame
	var hitbox := avatar.get_node_or_null(^"%AttackHitbox") as AttackHitbox
	if hitbox and hitbox.is_active():
		_log("  WARN: AttackHitbox still active after death (orphan window)")
	else:
		_log("  OK: AttackHitbox disabled cleanly")

func _scenario_mid_roll() -> void:
	_log("scenario 3: mid-Roll kill")
	avatar._state_machine.transition(&"RollState")
	await get_tree().process_frame
	_kill_avatar()
	# After respawn settles, verify state is IdleState (not Roll).
	# This requires waiting through RESPAWN_DELAY_TICKS — done as a separate
	# verify hotkey, since it takes ~3s.
	_log("  (verify after respawn: state == IdleState)")

func _scenario_mid_charge() -> void:
	_log("scenario 4: mid-ChargeWindup kill")
	avatar._state_machine.transition(&"ChargeWindupState")
	await get_tree().process_frame
	# ChargeWindupState should set charge_start_tick on enter.
	var pre_charge: int = avatar.charge_start_tick
	_log("  charge_start_tick before kill: %d" % pre_charge)
	_kill_avatar()
	_log("  (verify after respawn: charge_start_tick == -1)")

func _scenario_mid_riposte() -> void:
	_log("scenario 5: mid-Riposte kill")
	# Spawn a victim minion in front of the avatar so the riposte has a
	# target. This is best-effort — without a posture-broken target the
	# riposte may not trigger; we just transition the state directly to
	# exercise the cleanup path.
	avatar._state_machine.transition(&"RiposteAttackerState")
	await get_tree().process_frame
	_kill_avatar()
	_log("  (verify after respawn: state == IdleState, no orphaned animations)")

func _kill_avatar() -> void:
	if avatar == null or avatar.is_dormant:
		_log("  skip: avatar dormant")
		return
	avatar.god_mode = false
	avatar.incoming_damage += avatar.hp + 100
	_log("  killed avatar (hp was %d)" % avatar.hp)

func _reset() -> void:
	avatar.god_mode = false
	avatar.hp = avatar.get_max_hp()
	avatar.respawn_invuln_until_tick = -1
	avatar.combo_step = 0
	avatar.charge_start_tick = -1
	avatar.posture = 0
	avatar._state_machine.transition(&"IdleState")
	_log("reset: hp=%d, state=Idle" % avatar.hp)
	_refresh_status()

# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_scenario_idle_kill()
			KEY_2:
				_scenario_mid_light_attack()
			KEY_3:
				_scenario_mid_roll()
			KEY_4:
				_scenario_mid_charge()
			KEY_5:
				_scenario_mid_riposte()
			KEY_K:
				_kill_avatar()
			KEY_R:
				_reset()
			_:
				return
		_refresh_status()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if event.shift_pressed:
			get_tree().quit()
		else:
			var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()

# --- HUD ---

func _log(msg: String) -> void:
	# Recent-N log so the screen doesn't fill up.
	_scenario_log.append("[%d] %s" % [Time.get_ticks_msec() / 1000, msg])
	if _scenario_log.size() > 12:
		_scenario_log.remove_at(0)
	print("[TakeoverEdgeTest] %s" % msg)

func _refresh_status() -> void:
	if status_label == null:
		return
	var state_name: String = "?"
	if avatar and avatar._state_machine:
		state_name = String(avatar._state_machine.state)
	var hp_str: String = "?"
	if avatar:
		hp_str = "%d / %d" % [avatar.hp, avatar.get_max_hp()]
	var invuln_str: String = "no"
	if avatar and avatar.respawn_invuln_until_tick > 0 and NetworkTime.tick < avatar.respawn_invuln_until_tick:
		invuln_str = "yes (%d ticks left)" % (avatar.respawn_invuln_until_tick - NetworkTime.tick)
	var log_text: String = "\n".join(_scenario_log)
	status_label.text = "Takeover Edge Test — Tier F harness\nState: %s   HP: %s   Invuln: %s\n\n[1] idle kill           [2] mid-LightAttack kill\n[3] mid-Roll kill       [4] mid-ChargeWindup kill\n[5] mid-Riposte kill    [K] plain kill\n[R] reset               [Esc] mouse  [Shift+Esc] quit\n\nLog:\n%s\n" % [state_name, hp_str, invuln_str, log_text]

func _process(_delta: float) -> void:
	# Cheap refresh so the invuln countdown ticks visibly.
	_refresh_status()
