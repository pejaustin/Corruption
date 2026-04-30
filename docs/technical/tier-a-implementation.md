# Tier A — Feel Pass: Implementation Notes

Code-side roadmap for the [avatar-combat.md Tier A](../systems/avatar-combat.md#tier-a--feel-pass)
feel pass. Every system in the table below is plumbed; none requires art to
function. Where art is expected (particles, shaders, hit-react clips), the
system runs as a stub with a documented swap-in point.

---

## Status

| System | Code | Asset hookup | File(s) |
|---|---|---|---|
| Hitstop (state-synced) | Done | n/a (data-only) | `scenes/actors/actor.gd:18,38,101–119,207–240`, `scenes/actors/player/player_actor.tscn:26`, `scenes/actors/minion/minion_actor.gd:184–210,251–268`, `scripts/minion_manager.gd:459–476`, `scripts/guardian_boss.gd:77–96` |
| `Actor.took_damage` signal | Done | n/a | `scenes/actors/actor.gd:12,117–119` |
| Hit-FX spawner helper | Done | Stub scenes; swap particles in-editor | `scripts/combat/hit_fx.gd`, `scenes/vfx/hit_spark_*.tscn`, `scripts/vfx/hit_spark.gd` |
| Hit-flash uniform writer | Done | Needs `ShaderMaterial` per actor | `scenes/actors/actor.gd:25,48,243–296`, `docs/technical/hit-flash-shader.md` |
| Camera shake API | Done | n/a | `scripts/avatar_camera.gd:14–24,32–68` |
| Hit-shake hookup (dealt) | Done | n/a | `scenes/actors/player/states/attack_state.gd:23–26,89–116` |
| Hit-shake hookup (received) | Done | n/a | `scenes/actors/player/avatar/avatar_actor.gd:14–18,33–48` |
| Damage numbers autoload | Done | Tweak font/colour in scene | `scripts/ui/damage_numbers.gd`, `scenes/ui/damage_number.tscn`, `scenes/ui/damage_number.gd`, `project.godot:43` |
| Hurtbox `material_kind` export | Done | Set per actor in inspector | `scripts/combat/hurtbox.gd:25–28` |
| `dust_scenes` dict + `_spawn_dust` hook | Done | Author dust scenes; assign per-actor; add anim method tracks | `scenes/actors/actor.gd:50–53,303–323` |
| StaggerState light/heavy variant | Done | Author `hit_react_light` / `hit_react_heavy` clips | `scenes/actors/states/stagger_state.gd:29–86` |

`avatar-combat.md` has the system-level "Status by System" table; this file
is the file-level cross-reference.

## What works without art

You can plug Tier A into the existing avatar today and see all of:

- Animations freezing for 2 ticks on every successful hit (hitstop), driven by
  `AnimationPlayer.speed_scale = 0.0` while `NetworkTime.tick < hitstop_until_tick`.
- Tiny coloured particle bursts at the hurtbox location (CPU-particle stubs,
  one scene per material kind).
- Floating yellow damage numbers above each victim, fading upward.
- Camera punch on every dealt and received hit (no shader required).
- Damage numbers + camera shake on victim minions and bosses.
- Resimulation safety: rollback resims do NOT stack particles, double-shake the
  camera, or double-emit damage numbers (see "Resimulation gates" below).

What does NOT work yet (art-gated):

- Visible hit-flash on actor models — needs a `ShaderMaterial` per surface.
- Light vs heavy hit reaction — needs `hit_react_light` / `hit_react_heavy`
  clips in the model's animation library.
- Roll dust, footstep dust, land dust — needs `dust_scenes` dict populated and
  animation method tracks calling `_spawn_dust(&"...")` at the right frames.
- Audio — there is no `_spawn_sfx` hook yet; audio is deferred (see
  "Known limitations").

---

## Asset plug-in instructions

### Hit spark scenes

Three stub scenes ship with this tier:

- `scenes/vfx/hit_spark_flesh.tscn` — red sphere puff, 16 particles, 0.4s
- `scenes/vfx/hit_spark_armor.tscn` — gold sparks, 20 particles, 0.35s
- `scenes/vfx/hit_spark_shield.tscn` — blue puff, 14 particles, 0.35s

All use `CPUParticles3D` with a `SphereMesh` for placeholder visibility. To
swap in real particle systems:

1. Open the `.tscn` in the editor.
2. Replace the `CPUParticles3D` child with a `GPUParticles3D` (or keep
   `CPUParticles3D` and tune it). Either type is supported by the
   `HitSpark._ready` script — it walks descendants and toggles `emitting`.
3. Tune `lifetime` on the root `HitSparkXxx` node so it exceeds the longest
   particle lifetime, then the node free-frees after that.
4. Don't rename the scene file — `HitFx.SCENES` references it by path:

   ```gdscript
   const SCENES: Dictionary[StringName, String] = {
       &"flesh": "res://scenes/vfx/hit_spark_flesh.tscn",
       &"armor": "res://scenes/vfx/hit_spark_armor.tscn",
       &"shield": "res://scenes/vfx/hit_spark_shield.tscn",
   }
   ```

   To add a new kind (e.g. `&"void"`), add a key here AND a matching scene
   at the resolved path.

The kind is selected per-victim via `Hurtbox.material_kind`. Default = flesh.
Set it on each actor's hurtbox in the inspector. Examples to wire in-editor:

- Avatar (paladin armour) → `armor`
- Skeleton minion → `flesh`
- Holy Knight (later) → `armor`
- Guardian Boss → `armor`

The scene root **must** be a `Node3D` and **must** have the `HitSpark` script
attached. The `HitFx.spawn()` call sets `global_position` directly on the
root before adding it to the tree.

### Hit-flash shader

Full contract: [`hit-flash-shader.md`](hit-flash-shader.md).

Short version: any `ShaderMaterial` exposing
`uniform float hit_flash_intensity` participates. `Actor._set_hit_flash_intensity`
walks the `_model` subtree, finds matching materials (both surface-override
and mesh-internal), and writes the value. Plain `StandardMaterial3D` meshes
are silently skipped — no behaviour change.

To wire the flash on an existing avatar:

1. Open `assets/characters/avatar/avatar.tscn`.
2. For each `MeshInstance3D`, replace its surface materials with a
   `ShaderMaterial` using the example shader in `hit-flash-shader.md`.
3. Save. The flash automatically engages on the next hit (no code changes).

### Hit-react animations

`StaggerState._play_hit_react_variant` reads the configured `animation_name`
on the StaggerState node, splits off the `<library>/` prefix, and looks up:

- `<library>/hit_react_light` if `_last_damage_amount < HEAVY_REACT_THRESHOLD` (30)
- `<library>/hit_react_heavy` otherwise

If neither exists in the player, the base `Actor._on_display_state_changed`
already played the configured `animation_name` (e.g.
`large-male/Stagger`), so the legacy behaviour is preserved.

To add the variants: open the model's animation library `.res` (e.g.
`assets/characters/avatar/avatar.glb` → import → animations) and author two
new clips named `hit_react_light` and `hit_react_heavy`. Tune
`HEAVY_REACT_THRESHOLD` in `scenes/actors/actor.gd` if 30 doesn't feel right
once the animations are in.

### Footstep / dust hook

`Actor.dust_scenes: Dictionary[StringName, PackedScene]` is the per-actor
table of dust kinds → scenes. Default is empty → all `_spawn_dust()` calls
no-op silently.

To wire dust on an actor:

1. Author `scenes/vfx/dust_footstep.tscn` (or wherever) — a `Node3D` with a
   self-freeing particle child, same pattern as `hit_spark_flesh.tscn`.
2. Open the actor's `.tscn` (e.g. `avatar_actor.tscn`).
3. In the inspector → Dust Scenes, add entries:
   - `footstep` → `dust_footstep.tscn`
   - `roll_dust` → `dust_roll.tscn`
   - `land_dust` → `dust_land.tscn`
4. Open the relevant animation in the model's library and add a Call Method
   Track on the `Actor` root node calling `_spawn_dust` with one
   `StringName` argument:
   - `walk` / `run` clips: `_spawn_dust(&"footstep")` near foot-down keys.
   - `roll_forward` clip: `_spawn_dust(&"roll_dust")` near the start.
   - `jump_land` clip: `_spawn_dust(&"land_dust")` on impact.

`_spawn_dust` is gated by `_is_resimulating()`, so resims don't pile up dust.

### Hit / footstep sounds

**Audio is deferred to a follow-up tier.** When it lands, the canonical hook
will be a sibling `_spawn_sfx(kind: StringName)` forwarder mirroring
`_spawn_dust`'s shape, plus an `AudioStream` dictionary export. Wire one
animation method-track call per impact frame.

For now, no SFX are spawned. Damage application is silent (the camera
shake + spark + damage number is the entire feedback loop).

---

## How to test

### Hitstop (host + client)

1. Open `scenes/test/war_table_test.tscn` (the existing minion harness).
2. Run, spawn a minion (`1`), select it as a target, walk into it with the
   Avatar, attack (LMB).
3. Watch the minion's animation **freeze** for ~70 ms on hit.

For the rollback path: open the project in two instances, host one, join the
second, attack the avatar from the host. Both peers should see identical
hitstop windows (the host's animations sync via state_property; the client's
`AnimationPlayer.speed_scale` is driven locally from
`hitstop_until_tick`, which IS synced).

### Damage numbers

Same scene. Every hit on Avatar or minion floats a yellow `25` (or similar)
upward from the victim, fading out over ~0.9s. Numbers spawn on every peer
that runs `take_damage` or sees a sync hp drop (minion clients).

### Hit sparks

Same scene. Every hit pops a small puff at the hurtbox location. Colour =
`Hurtbox.material_kind` (set on each actor's hurtbox; default flesh).

### Camera shake

Engage the avatar, attack. The camera punches outward briefly on hit
connect. Take damage from a minion — bigger shake, longer duration.

### Light/heavy hit react

This requires `hit_react_light` and `hit_react_heavy` clips in the
animation library. Once authored, attack the avatar with a low-damage hit
(< 30) to see the light react, then a heavy ability hit for the heavy
react. Without the clips, the legacy `Stagger` animation plays — verify
that fallback by leaving the library untouched and confirming nothing
broke.

### Resimulation gates (correctness check)

Open `addons/netfox/network-rollback.gd` and add a temporary `print` in
`is_rollback()`. Boot host + client, simulate ~200 ms latency
(`NetworkSimulator`), trade hits. The print should fire often (rollback
loops are normal); damage numbers / sparks / camera shake should each
fire **exactly once per hit** regardless. If you see doubles, the
resim gate is broken — the most likely culprits are
`HitFx.spawn` (gated at top), `_spawn_dust` (gated at top),
`Actor.take_damage` (gated around `_hit_flash_intensity = 1.0` and
`took_damage.emit`), and `AvatarActor._on_took_damage` (gated upstream
in `take_damage`).

### Optional debug toggles

There are no new debug toggles in this tier. The existing pause-menu
"Toggle Combat Boxes" still works; if you want a quick fake-damage trigger
to feel hitstop without combat, add a TEMP keypress in
`scripts/test/war_table_test_controller.gd`:

```gdscript
# TEMP: H = damage avatar by 20, for tier-A feel iteration
if event.is_action_pressed("ui_select") and not event.is_echo():
    if avatar:
        avatar.take_damage(20)
```

Remove before merging.

---

## Known limitations / followups

- **Minion hitstop on clients lags ~100ms.** `MinionManager._sync_all_minions`
  runs at 10Hz, so the `hitstop_until_tick` value arrives at clients up to
  100ms after the host applied damage. Hitstop is only ~67ms long, so the
  client may briefly miss the window altogether. Acceptable for the stub
  pass; if it reads as desync once SFX/sparks land, fan out a one-shot
  reliable `notify_damage(id, dmg, hitstop_tick)` RPC on the host's
  damage path and let clients latch directly.
- **Minion-attack hit sparks are host-only.** Minion `_check_hits` runs only
  on host (clients early-return from `_physics_process`), so the spark scenes
  spawn on host's screen only. Damage numbers and hit-flash still play on
  every peer because they're driven by the victim's `took_damage` signal.
  When SFX/sparks need to appear on every peer that watches a minion attack,
  pipe a one-shot RPC alongside the existing `_sync_minion_actor` (probably
  on the next pass when audio lands).
- **Avatar-attack hit sparks fire only on the attacker's screen** (gated by
  `controlling_peer_id == get_unique_id()` in `_spawn_local_hit_feedback`).
  Other peers see the swing animation and damage numbers but not the spark.
  This is correct for the "feel" framing — the attacker is the one whose
  swing connected. If watcher peers should also see the spark, drop the
  controlling-peer gate but keep the resim gate.
- **Audio not wired.** No `_spawn_sfx` hook exists yet — see the asset
  section above. When it's time to add it, mirror `_spawn_dust` exactly:
  `dict[StringName, AudioStream]` export + animation method-track entry +
  `_is_resimulating` gate.
- **Channeled abilities + hitstop.** A channel that takes damage will
  freeze its animation for 2 ticks. Probably fine, but channels with
  long visual timelines (e.g. a 3-second cast) may want to opt out via a
  `stagger_immune`-style check — defer until a designer hits the friction.
- **Hit-flash on multi-mesh actors** walks every `MeshInstance3D` in the
  `_model` subtree on every flash frame. For a 20-bone humanoid with
  ~6 mesh instances, this is fine. For a complex monster with 30+
  instances, cache `_walk_mesh_instances()` once on `_ready()` and reuse
  the array. See note in `hit-flash-shader.md`.
- **Damage number numerics** show raw post-multiplier integer damage. For
  PvP shipping, consider colour-coding crits / weak-points (Tier G's
  hurtbox profile work), and clamping the float distance against a cap
  for very high damage.
- **Hit-flash + damage numbers + sparks fire on the local presentation**.
  If a peer rewinds across a damage event under heavy lag, the FX play
  exactly once on the leading edge and don't replay during resim.
  Visually correct under all conditions tested in design; real lag
  testing pending the Tier F polish pass.
- **Camera shake doesn't apply to overlords** — only `AvatarCamera` has
  the API. If the overlord first-person body needs feedback later, port
  the same `_tick_shake` block into `scripts/camera_input.gd` or its
  camera owner.
- **GuardianBoss** now also flashes / emits `took_damage` like a regular
  actor. This is consistent and probably what you want; if the boss
  fight should feel weightier than minion combat, raise
  `HEAVY_REACT_THRESHOLD` for bosses or special-case in the boss
  animation library.
