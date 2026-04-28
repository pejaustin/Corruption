# Action Gating

Per-animation-phase control over whether a state can be interrupted, and whether the actor can be staggered, without putting state-specific logic in every call site.

## Why

Combat animations have phases — windup, active, recovery — with different interrupt policies:

- During a swing's **windup**, a Roll should be able to cancel the attack.
- During the **active** (damage-dealing) phase, nothing cancels — the actor is committed.
- During **recovery**, most inputs are allowed again.

Similarly, some animations (bosses, super-armored attacks) should make the actor **stagger-immune** for specific frames without making them invulnerable to damage.

The gating needs to be:
1. Decoupled from the state machine (any state can opt in).
2. Authorable by animators — no scripting per attack variation.
3. Two independent axes (interrupt-policy ≠ stagger-policy).

## The system

Two runtime flags on `ActorState`:

```gdscript
var action_locked: bool = false    # blocks try_transition except for cancel_whitelist
var stagger_immune: bool = false   # blocks try_stagger

@export var cancel_whitelist: Array[StringName] = []  # hard-coded exceptions
```

Both flags are **zeroed on state entry** by `Actor._on_display_state_changed`, so a forgotten "turn off" key at the end of an animation recovers on the next transition instead of permanently locking the actor.

Two gated entry points on `Actor`:

```gdscript
func try_transition(new_state: StringName) -> bool
func try_stagger() -> bool
```

Anything trying to cancel a state routes through `try_transition`. Anything inflicting stagger routes through `try_stagger`. Both return `true` if the change went through, `false` if gated.

`Actor.take_damage` already calls `try_stagger` internally — external damage sources (animation hitboxes) automatically respect `stagger_immune`. Callers that force-stagger without going through damage (boss HP thresholds, Entangle, Mind Blast) also use `try_stagger`.

## Authoring an animation

Method tracks on the animation call forwarder methods on the Actor root. The Actor routes each call to whatever state is currently active — you don't need `unique_name_in_owner` on every state node.

Four forwarders on `Actor`:

| Method | Effect on current state |
|---|---|
| `lock_action()` | `action_locked = true` |
| `unlock_action()` | `action_locked = false` |
| `enable_stagger_immunity()` | `stagger_immune = true` |
| `disable_stagger_immunity()` | `stagger_immune = false` |

### Example: a sword swing

On `large-male/Attack`:

| Frame | Method | Why |
|---|---|---|
| active-start | `lock_action` | commit — only cancel_whitelist entries (Roll) can break it |
| active-start | `enable_stagger_immunity` | super-armor through the active window |
| active-end | `unlock_action` | recovery is cancellable again |
| active-end | `disable_stagger_immunity` | back to normal |
| active-start | `%AttackHitbox.enable` | existing hitbox key — same track list |
| active-end | `%AttackHitbox.disable` | existing hitbox key |

Set `AttackState.cancel_whitelist = [&"RollState"]` (or whatever is authored) so that Roll specifically can break the lockout while other inputs cannot.

Since the four forwarders target the Actor root, the method track's target `NodePath` is whatever reaches the Actor from the `AnimationPlayer`. Under the `large-male` model the path is `../../../..` — same as the hitbox track already uses for `%AttackHitbox` via unique-name resolution. If you prefer, mark the Actor root with `unique_name_in_owner = true` in each actor scene and target `%AvatarActor` / `%HolyKnight` etc. directly.

## Call-site contract

For internal state-machine flow (`IdleState` → `MoveState` based on input direction, `AttackState` → `IdleState` when animation ends) continue to call `state_machine.transition(...)` directly — these are the state's own lifecycle and shouldn't be gated.

For **external cancel requests** — player input that tries to break out of the current state, abilities that interrupt, anything user-triggered — call `actor.try_transition(&"TargetState")`. The helper consults the current state's `action_locked` / `cancel_whitelist` and either forwards to the state machine or returns `false`.

Rule of thumb: if the transition represents a choice the player or an external system is making, gate it. If it's the state's own natural progression, don't.

## What gets synced across peers

Neither flag is rollback-synced. They're set by animation method keys during real-time playback, and the animation plays deterministically from state+tick entry on every peer, so the flags naturally end up consistent under normal play.

`try_stagger` and `try_transition` are only called on the authoritative peer for a given actor (host for minions, controlling peer for avatar-via-rollback). Gating decisions happen authority-side; remote peers just see the resulting state transition (or lack of one) via the state_property sync. No extra network machinery required.

**Rollback-replay caveat**: if a rollback rewinds past a window where `action_locked` was `true`, the replayed ticks won't see the flag set (the animation keys fire in real-time, not during replay). This is fine for the current use cases because the flags gate *triggers* (input, damage), not per-tick logic, and triggers are fresh on the replay head. If a future use case needs per-tick querying of these flags during rollback, promote them to RollbackSynchronizer state_properties.

## Input buffering (Souls-style queueing)

Locked actions cooperate with an input-buffer on `AvatarInput`:

- `AvatarInput._gather` stamps `Input.is_action_just_pressed` for `roll` and `primary_ability` into `_press_tick[action] = NetworkTime.tick`.
- `consume_if_buffered(action)` returns true if the press is within `BUFFER_WINDOW` (12 ticks ≈ 200ms) and clears the slot.
- `PlayerState.try_roll()` / `try_attack()` accept either a held input *or* a buffered press, so a press during a locked window fires the moment the actor is free.

Effect:
- Press Roll mid-attack while `action_locked` (and `RollState` not in `cancel_whitelist`): `try_transition` blocks the roll *now*, but the press sits in the buffer; AttackState's per-tick `try_roll()` consumes it the moment `unlock_action` fires.
- Press attack near the end of an attack: lands in the buffer; on transition to Idle/Move, `try_attack()` consumes it and chains the next swing.

The buffer lives client-side on the controlling peer. It's not state_property-synced — every consumption is deterministic on the authority peer, and remote peers see the resulting state transition through the existing rollback sync. Rare rollback-replay edge cases (consuming a buffer the original sim already consumed) are absorbed by state_property reconciliation on the next tick.

## Related systems

- `AttackHitbox` (`scripts/combat/attack_hitbox.gd`) — same animation-key-driven pattern, already in use on the attack swing.
- `MinionActor.stagger_invulnerable` — an older, static boolean that makes StaggerState skip the damage window. Narrower scope than this system; it exists for boss-style mid-attack invulnerability and is orthogonal.
