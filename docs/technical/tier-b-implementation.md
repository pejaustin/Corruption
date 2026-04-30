# Tier B — Targeting Pass: Implementation Notes

Code-side roadmap for the [avatar-combat.md Tier B](../systems/avatar-combat.md#tier-b--targeting-pass)
targeting pass. Every system in the table below is plumbed; the only assets
required are optional strafe/roll directional clips. The reticle ships with
Godot's built-in `PlaceholderTexture2D` so it's visible immediately.

**Architectural note:** Targeting is the only system on the entire avatar-
combat roadmap with **zero rollback footprint**. There are no `state_properties`
on `Targeting`, no `input_properties`, no RPCs, and no `_rollback_tick` paths.
Per `docs/systems/avatar-combat.md` §6 and `docs/technical/netfox-reference.md`,
target selection is purely camera/local — the controlling peer's view of the
world. If overlords ever need to see who an avatar has locked, that becomes a
low-rate cosmetic broadcast layered on top, not netfox state.

---

## Status

| System | Code | Asset hookup | File(s) |
|---|---|---|---|
| `Targeting` component (local-only) | Done | n/a | `scripts/combat/targeting.gd` |
| Soft-target picker | Done | n/a | `scripts/combat/targeting.gd:find_best_target` |
| Hard-target lock + cycle | Done | n/a | `scripts/combat/targeting.gd:acquire,release,toggle_lock,cycle_target` |
| Target-loss rules | Done | n/a | `scripts/combat/targeting.gd:_process` |
| `toggle_lock` / `cycle_target_left` / `cycle_target_right` actions | Done | n/a | `project.godot:[input]` |
| Avatar input wiring | Done | n/a | `scenes/actors/player/avatar/avatar_actor.gd:_unhandled_input` |
| Camera follow-target mode | Done | n/a | `scripts/avatar_camera.gd:_tick_lock_follow,look_at_target` |
| Soft-lock camera assist scaffold | Plumbed (off) | Set `soft_lock_strength > 0` in inspector to enable | `scripts/avatar_camera.gd:soft_lock_strength` |
| Reticle scene + script | Done | Stub PlaceholderTexture2D; swap art per "Asset plug-in" | `scenes/ui/lock_on_reticle.tscn`, `scripts/ui/lock_on_reticle.gd` |
| Strafe locomotion (target-relative basis) | Done | Author `walk_*` / `run_*` clips per direction | `scenes/actors/player/states/move_state.gd` |
| Directional roll | Done | Author `roll_back` / `roll_left` / `roll_right` | `scenes/actors/player/states/roll_state.gd` |
| Lock-aware lock cleanup on controller change | Done | n/a | `scenes/actors/player/avatar/avatar_actor.gd:deactivate` |
| Hit-from-behind hard-lock break | Plumbed (gated on source) | Lights up automatically when `Actor.took_damage` carries source actor (Tier C/D) | `scripts/combat/targeting.gd:_on_owner_took_damage` |

`avatar-combat.md` has the system-level "Status by System" table; this file
is the file-level cross-reference.

## What works without art

You can plug Tier B into the existing avatar today and see all of:

- Press middle-mouse → reticle (placeholder yellow square) appears over the
  best hostile actor in front of you. Camera yaws toward them with a damped
  chase.
- Mouse wheel up/down (or LB/RB on a gamepad) cycles to the next/prev hostile
  in the camera's front cone, ranked by signed angle.
- Walk away → at >25 m XZ distance the lock breaks.
- Step behind a wall (any layer-1 collider) → lock survives ~0.5 s grace,
  then breaks.
- Target dies → lock releases immediately.
- Press middle-mouse again or get the avatar killed → lock releases.
- Roll while locked with no input → roll-back animation fires (or falls back
  to the existing `large-male/Crouch` clip if `<library>/roll_back` isn't
  authored yet).
- Walk while locked → movement basis is target-relative (W = toward target,
  S = away, A/D = strafe), and the avatar faces the target rather than the
  camera. Animation falls back to the existing `large-male/Walk` clip until
  strafe variants are authored.

What does NOT work yet (art-gated):

- Strafe walk/run animations — needs `walk_forward/back/left/right` and
  `run_forward/back/left/right` clips in the model's animation library.
  Without them, locked locomotion uses the legacy single `Walk` clip and
  visually looks identical to free walk. The basis math still applies.
- Directional roll animations — needs `roll_forward/back/left/right`.
  Without them, every roll plays the legacy `Crouch` clip.
- Real reticle art — currently a `PlaceholderTexture2D` (32×32 grey square)
  modulated yellow.
- Soft-lock camera assist — code path is wired, but `soft_lock_strength`
  defaults to 0. Designers opt in by raising it in the inspector.

---

## Asset plug-in instructions

### Reticle texture

Edit `scenes/ui/lock_on_reticle.tscn`:

1. Open the scene in the editor.
2. On `LockOnReticle/Sprite3D`, swap the `texture` from
   `PlaceholderTexture2D` to a real `Texture2D` (e.g. `assets/ui/reticle.png`).
3. Tune `pixel_size` (default `0.005`) and `modulate` (default warm yellow).
4. The `fixed_size = true` flag keeps the reticle a constant on-screen size
   regardless of distance — leave it on for the targeting use case.
5. `no_depth_test = true` is intentional. Without it, the reticle gets
   occluded by the target's mesh whenever the camera angle dips below the
   chest plane — leave it on.

### Strafe locomotion clips

`MoveState._play_strafe_clip` resolves the library prefix from the state's
configured `animation_name` (e.g. `large-male/Walk` → `large-male`), then
looks up:

| Direction | Walk clip | Run clip |
|---|---|---|
| Toward target (W) | `<library>/walk_forward` | `<library>/run_forward` |
| Away (S) | `<library>/walk_back` | `<library>/run_back` |
| Strafe left (A) | `<library>/walk_left` | `<library>/run_left` |
| Strafe right (D) | `<library>/walk_right` | `<library>/run_right` |

Author the eight clips in the model's animation library (e.g.
`assets/characters/avatar/avatar.glb` → import → animations). Missing clips
fall back silently to the configured `animation_name` clip — the state never
crashes. Author them in any order; each lights up the moment it appears in
the library.

### Directional roll clips

`RollState._play_roll_variant` resolves the library prefix the same way
(from `large-male/Crouch` → `large-male`), then looks up:

| Direction | Clip |
|---|---|
| Toward target (W) | `<library>/roll_forward` |
| Away from target (S, or no input) | `<library>/roll_back` |
| Strafe left (A) | `<library>/roll_left` |
| Strafe right (D) | `<library>/roll_right` |

Same fallback rule as strafe — missing clips silently fall back to the
configured `animation_name` (currently `large-male/Crouch`). The
displacement math is identical regardless of clip; only the playing animation
differs.

### Optional: distinct soft-lock vs hard-lock reticle variants

`Targeting` currently only spawns a reticle on hard-lock. If you want a
subtler reticle for soft-target hover later:

1. Add a second `@export var soft_reticle_scene: PackedScene` to
   `Targeting`.
2. In `_process` (or a new tick path), call `find_best_target()` each
   frame even when `is_locked == false`, instance the soft reticle when a
   non-null target appears and isn't the same as the hovered one, despawn
   on miss.
3. Same parent + offset rules as the hard-lock reticle.

Deferred — the doc lists soft-lock as nice-to-have polish; hard-lock pulls
the larger weight.

---

## How to test

Use the existing `scenes/test/war_table_test.tscn` harness — it spawns a
real Avatar, real MinionActors, and runs offline so you can iterate
single-peer.

### Hard-lock and reticle

1. Open `scenes/test/war_table_test.tscn`. Run.
2. Press `1` a few times to spawn skeletons (your faction, allies — you
   can't lock onto these).
3. Press `2`–`4` to spawn enemy minions (Demonic, Fey, Eldritch — these
   are hostile to your default UNDEATH faction).
4. Walk close enough that an enemy is in your front cone (±60° from
   camera forward).
5. Press **Middle-Mouse Button** (or right-stick click on a gamepad) →
   reticle appears over the nearest hostile, camera yaws toward them with
   a damped chase.
6. Press Middle-Mouse again → reticle disappears.

### Cycle target

While locked, press **Mouse Wheel Up** → lock jumps to the next enemy to
your right (positive signed angle). **Mouse Wheel Down** → next to the
left. Wraps around the front-cone.

Gamepad: LB / RB (button indices 9/10) cycle left/right.

### Range break

While locked, press `R` to reset and respawn. Walk away from the target
in a straight line until the XZ distance exceeds 25 m. Lock releases the
moment you cross the boundary.

### Occlusion break

Spawn an enemy near a wall or terrain edge. Lock onto it, then walk so
that world geometry (any layer-1 collider) sits between the camera and
the target. After ~0.5 s, the lock drops. Step out from behind cover
within the grace window and the lock survives.

### Strafe basis

Lock onto an enemy. Walk forward (W) — the avatar moves *toward* the
target, not toward the camera. Strafe with A/D — the avatar circles
the target, not the camera. Walk back (S) — avatar retreats away from
the target, not toward the camera.

If strafe clips aren't authored yet, the animation will keep playing
the legacy `Walk` clip — that's expected. The basis math is what you're
verifying; check by toggling between locked and unlocked walk, the
movement vector should rotate to match the target rather than the
camera.

### Directional roll

Lock onto an enemy. With no input held, press `C` (roll) — the avatar
rolls back, away from the target. With S held, also rolls back. With
A or D held, lateral roll. With W held, roll-forward toward the target.

Same fallback rule applies — the displacement is correct even before
directional roll clips are authored.

### Soft-lock (optional, off by default)

Open the `AvatarCamera` node in the inspector and set
`soft_lock_strength` to `0.5` or so. With no hard-lock active, the
camera now *gently* yaws toward whatever `Targeting.current_target`
the picker has selected — except `Targeting.current_target` is only
populated by hard-lock. To make soft-lock fully work, you'd need to
extend `Targeting._process` to keep `current_target` updated to the
picker's best candidate while `is_locked == false`. Deferred — see
"Known limitations" below.

---

## Known limitations / followups

- **Hit-from-behind hard-lock break is dormant**. The handler is wired,
  but `Actor.take_damage` emits `took_damage(amount, null)` (Tier A
  didn't plumb the source actor through). The `_on_owner_took_damage`
  conditional `if source == null: return` handles this gracefully —
  when Tier C (defense pass) or Tier D (attack depth) hands over the
  attacker actor, the behind-attack drop activates automatically. No
  changes needed in `targeting.gd`.
- **Soft-lock camera assist is plumbed but disabled**. `AvatarCamera.soft_lock_strength`
  defaults to `0.0`. The math is intentionally inert until designers
  validate the feel; flipping it on is one inspector change. Soft-lock
  *also* requires `Targeting` to keep `current_target` populated to the
  picker's best candidate while `is_locked == false`, which is a small
  follow-up — see commented TODO in `_process`. Lean: ship soft-lock
  on Tier C alongside the block facing-cone work, since both want to
  read "the most credible enemy in front of the avatar."
- **No info-warfare reveal of the lock to overlords yet**. Per
  `docs/systems/avatar-combat.md` §6 open question, this is a
  deliberate non-decision — overlords currently see no hint of who
  the avatar is locked onto. If we decide to surface it via the War
  Table, the broadcast lives outside `Targeting` (probably a
  `KnowledgeManager` per-tick status push), since `Targeting` is
  forbidden from holding netfox state.
- **Free-look during hard-lock = manual orbit only**. The camera
  follow chase is *additive* on top of player input — mouse / right
  stick still orbit around the target. There's no "snap-back when
  released" behavior; the camera just resumes free orbit at whatever
  yaw the player left it at. Probably fine; if it reads wrong in
  playtest, add a snap interpolation to last-target-yaw on release.
- **Pitch is not driven by lock-on**. Only yaw chases the target.
  If the target's at a wildly different elevation, the player has to
  pitch the camera manually. Easy follow-up if needed: extend
  `_tick_lock_follow` to also damp `camera_rot.rotation.x` toward the
  pitch implied by the target's chest position.
- **Reticle uses `PlaceholderTexture2D`**. It's a 32×32 grey square
  modulated yellow — visible enough for testing, definitely not ship.
- **Reticle is parented under `get_tree().current_scene`**, not the
  avatar. This is correct — the reticle follows the *target*, not the
  avatar — but means the reticle persists for one frame if a scene
  transitions while a lock is active. Acceptable for current scope.
- **Single avatar assumption.** Each avatar instance owns its own
  `Targeting` child, so 4-player support already works. Targeting is
  gated by `_is_local_controller()` which checks `controlling_peer_id`
  vs `multiplayer.get_unique_id()`, so remote peers' avatars run no
  targeting logic locally — only the controlling peer drives input
  and reticle spawn.
- **Cycle target wraps the full candidate list, not just visible ones.**
  Candidates are filtered by `MAX_RANGE` and hostility but not by
  occlusion or front-cone. This is deliberate — cycling should let
  the player *find* hidden enemies, not just rotate among visible
  ones. If it reads unintuitively, restrict cycle candidates to the
  same ±60° cone the soft picker uses.
- **Strafe / roll directional clips are matched only by name lookup**.
  No fallback "use the closest matching clip" logic. If the model
  carries `walk_left` but not `walk_right`, only left-strafe shows
  the new clip. The forward/back fallbacks (to the configured
  `animation_name`) are the only safety net. Author all 4 clips per
  set (or none) for consistent feel.
- **No camera shake / FOV punch on lock acquire**. Polish nice-to-have.
  Easy follow-up: hook `Targeting.lock_state_changed` to a one-shot
  `avatar_camera.shake(...)`.
