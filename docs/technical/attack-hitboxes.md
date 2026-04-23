# Attack Hitboxes

**Component:** `scripts/combat/attack_hitbox.gd` — `class_name AttackHitbox extends Area3D`

---

## Overview

A modular hitbox component that any actor's attack can wear. It hosts one or more named `CollisionShape3D` children — each is an "attack profile" (e.g. `Windup`, `Impact`, `Recovery`). Attack states swap between profiles during a swing; animation call tracks can drive it directly. Per-activation hit reporting prevents the same body being damaged twice in one window.

Placement is the scene's concern: drop it under a `BoneAttachment3D` for a bone-following hitbox, or keep it at the actor root for a fixed-relative box. The component is agnostic to where it sits.

## API

| Method | Purpose |
|---|---|
| `enable(profile: StringName = &"")` | Activate a profile by name (must match a `CollisionShape3D` child). Empty = first shape child. |
| `disable()` | Disable all shapes and clear the per-activation hit log. |
| `is_active() -> bool` | Whether any profile is currently active. |
| `get_active_profile() -> StringName` | Currently active profile name, or `&""` if none. |
| `get_damage_multiplier() -> float` | Per-profile damage multiplier (from `profile_damage` export, defaults 1.0). |
| `get_new_hits() -> Array[Node3D]` | Bodies overlapping that haven't been reported yet this window. |
| `forget(body: Node3D)` | Manually forget a body so it can be hit again (multi-hit profiles). |

Export: `profile_damage: Dictionary[StringName, float]` — per-profile damage multipliers.

## Attack-state integration

Both `scenes/actors/player/states/attack_state.gd` and `scenes/actors/minion/states/attack_state.gd` already use the component. Each exposes a `hitbox_profile: StringName` export — set it per attack state to pick a profile, or leave empty for single-shape hitboxes.

The hit loop is:

```gdscript
if progress >= hitbox_start_ratio and not _hitbox_active:
    _hitbox_active = true
    hitbox.enable(hitbox_profile)
elif progress >= hitbox_end_ratio and _hitbox_active:
    _hitbox_active = false
    hitbox.disable()

if _hitbox_active:
    for body in hitbox.get_new_hits():
        body.take_damage(base * hitbox.get_damage_multiplier())
```

## Adding a bone-attached, multi-shape hitbox

1. Open the model scene (e.g. `assets/characters/enemies/Zombie.tscn`).
2. Add a `BoneAttachment3D` child of the `Skeleton3D` and pick the swinging bone (hand or weapon bone).
3. Move/reparent the `AttackHitbox` under that `BoneAttachment3D`, or instance a new `AttackHitbox` there. Either way the node's name must stay `AttackHitbox` so the attack state can find it via `actor.get_node_or_null("AttackHitbox")`.
4. Add named `CollisionShape3D` children under the hitbox — e.g. `Windup`, `Impact`, `Recovery`. Each is a profile.
5. Pick how to drive the profile switch:
   - **Static per attack:** set `hitbox_profile` on the AttackState (e.g. `&"Impact"`). The existing start/end ratio window enables it once.
   - **Per-frame via animation:** add method call tracks on the attack animation that call `AttackHitbox.enable(&"Windup")`, then `enable(&"Impact")`, then `disable()` at specific keyframes. Leave `hitbox_start_ratio` > 1.0 on the state so it doesn't also toggle the hitbox.
6. (Optional) Set `profile_damage` on the AttackHitbox — e.g. `{ &"Impact": 1.5 }` to make the impact frame hit harder than `Windup`.

## Backward compatibility

Scenes with a single unnamed `CollisionShape3D` child still work: `enable()` with no args picks the first shape child. Existing PlayerActor and MinionActor hitboxes are unchanged in layout — they now just have the `AttackHitbox` script attached.

## Gotchas

- The node must be named `AttackHitbox` — the attack state looks it up by name. If bone-attaching, the `BoneAttachment3D` goes inside the model, but the `AttackHitbox` node it holds must sit at a path the actor can resolve, or the lookup pattern needs updating.
- `get_new_hits()` tracks reported bodies until `disable()` — switching profiles mid-swing without calling `disable()` preserves the log (so the same enemy isn't hit twice across Windup → Impact). Call `forget(body)` if you want a profile to re-hit.
- Animation method call tracks run on every peer, including clients. Damage application is still gated by the attack state's `multiplayer.is_server()` check — the component itself does no damage, it just reports overlaps.
