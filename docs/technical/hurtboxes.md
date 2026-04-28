# Hurtboxes

**Component:** `scripts/combat/hurtbox.gd` — `class_name Hurtbox extends Area3D`

---

## Overview

A modular damage-target component that any actor can wear. Mirrors `AttackHitbox` on the receiving side: attacks query `hitbox.get_new_hits()` for overlapping `Hurtbox` areas, not for overlapping bodies. This decouples hit detection from the `CharacterBody3D` used for navigation and physics — a minion's collision capsule can be sized for pathfinding without changing the target it presents to attackers.

Hurtboxes host one or more named `CollisionShape3D` children. Single-shape setups (the common case) leave one child enabled and ignore the profile API. Multi-profile setups (e.g. `Head` / `Torso` / `Legs`) enable one at a time and multiply incoming damage per profile via `profile_damage`.

Placement is per-scene: drop it under a `BoneAttachment3D` for bone-following regions, or at the actor root for a fixed box. The component is agnostic to where it sits.

## API

| Method | Purpose |
|---|---|
| `enable(profile: StringName = &"")` | Activate a profile by name (must match a `CollisionShape3D` child). Empty = first shape child. |
| `disable()` | Disable all shapes. |
| `is_active() -> bool` | Whether any profile is currently active. |
| `get_active_profile() -> StringName` | Currently active profile name, or `&""` if none. |
| `get_damage_multiplier() -> float` | Per-profile incoming-damage multiplier (from `profile_damage` export, defaults 1.0). |
| `get_actor() -> Actor` | Owning `Actor`, resolved by walking up the tree and cached. |

Export: `profile_damage: Dictionary[StringName, float]` — per-profile incoming-damage multipliers.

## Setup per actor scene

Every actor scene needs a `Hurtbox` child. The pattern:

1. Add an `Area3D` child of the actor root. Name it `Hurtbox`. Mark **Unique Name in Owner** on.
2. Attach `scripts/combat/hurtbox.gd`.
3. Set `collision_layer` to the owner's hit layer (4 = Avatar, 8 = Minion/Enemy). `collision_mask = 0`, `monitoring = off`, `monitorable = on` — the script enforces these in `_ready()` too, but the editor defaults are wrong so set them explicitly.
4. Add a `CollisionShape3D` child with whatever shape matches the model. For a single-region hurtbox, the shape name doesn't matter — the script picks the first enabled shape on `_ready()`.
5. Position via the `Hurtbox`'s own `transform` (usually raise it to the model's center: `y ≈ 1.0`–`1.5`).

For a multi-profile setup (named regions), add one `CollisionShape3D` per region with meaningful names (`Head`, `Torso`, ...) and set `profile_damage` on the Hurtbox (e.g. `{ &"Head": 2.0 }`). Call `hurtbox.enable(&"Torso")` from wherever drives the switch (animation track, state script, etc.).

## Attack-state integration

Both attack states iterate hurtboxes returned by the hitbox and pass damage through both multipliers:

```gdscript
for hurt in hitbox.get_new_hits():
    var target := hurt.get_actor()
    if target == null:
        continue
    var dmg := base * hitbox.get_damage_multiplier() * hurt.get_damage_multiplier()
    target.take_damage(dmg)
```

The hitbox's mask is set to the hurtbox layers it should hit (mask `8` for Avatar attackers hitting minions, mask `12` for minion attackers hitting both Avatar and other minions).

## Debug visualization

Both `AttackHitbox` and `Hurtbox` build matching `MeshInstance3D` debug visuals on `_ready()` via `CombatBoxDebug.build_visuals()`. They subscribe to `DebugManager.combat_boxes_toggled` and show/hide together.

- Hitboxes render in red (`Color(1.0, 0.15, 0.15, 0.35)`).
- Hurtboxes render in yellow (`Color(1.0, 0.85, 0.1, 0.35)`).

Toggle at runtime from the pause menu's Debug panel ("Toggle Combat Boxes") or programmatically via `DebugManager.toggle_combat_boxes()`.

Debug meshes are unshaded, alpha-blended, depth-test disabled, cull disabled — they show through geometry so you can see what's actually overlapping.

## Missing-component warning

`Actor._check_combat_components()` runs on `_ready()` and puts a yellow ⚠ `Label3D` above any actor missing expected combat components:

- `Hurtbox` is always required.
- `AttackHitbox` is required only if the actor's state machine has an `AttackState` child (so passive actors like the overlord don't false-positive).

The label is billboarded, depth-test off, so it stays visible in-editor-style regardless of camera angle. `push_warning` also fires so the missing components show in the editor's debugger log.

## Gotchas

- `collision_layer` on the hurtbox must match what the attacker's hitbox masks. Layer 4 = Avatar, layer 8 = Minion/Enemy — check both sides when wiring a new actor.
- `monitoring` must be **off** on the hurtbox — the hitbox is the one that monitors. Both boxes monitoring each other is redundant and doubles overlap events.
- `get_actor()` walks up the tree until it finds an `Actor`. If you place a hurtbox under non-Actor scaffolding (e.g. a destructible prop), either make the root extend `Actor` or extend `Hurtbox` and override `get_actor()` to return the right object.
- The body's own `CollisionShape3D` (`$Body` on the actor) stays on its movement layer for navigation/physics — don't put the hit layer on it too, or attacks will hit the navigation capsule instead of the hurtbox.
