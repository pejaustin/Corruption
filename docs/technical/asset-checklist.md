# Avatar Combat — Asset Checklist

Single-page index of every asset hookup left open by the Tier A–G code pass.
The detailed swap-in instructions live in each tier's implementation doc;
this file is the navigation aid that aggregates them by asset type and
flags which feature each asset unlocks.

For the design-target inventory (full animation list per archetype, weapon
taxonomy, HUD asset list, per-animation method-track contract), see
[avatar-combat.md § Asset Checklist](../systems/avatar-combat.md#asset-checklist).
That doc is the *what* and *why*; this file is the *what's-blocking-what*
plus *where the swap-in lives in code today*.

---

## Authoring order (highest perceived uplift first)

Cribbed from `avatar-combat.md` and refined now that all tiers have
landed:

1. **Hit-flash shader + flesh hit-spark + impact SFX** — Tier A pays off
   immediately on every existing swing. (No new code required.)
2. **Reticle texture** — Tier B is functional today, but the placeholder
   `PlaceholderTexture2D` is ugly. One PNG swap.
3. **Two reaction clips (`hit_react_light`, `hit_react_heavy`)** — Tier A
   reaction-variety wiring is dormant until both clips exist.
4. **Block animation set + block clang SFX** — unlocks Tier C's defense
   feel (block today plays the legacy stagger clip as a fallback).
5. **Light combo string (`light_1` / `light_2` / `light_3`)** — biggest
   combat-depth unlock for the same animator-hour budget. Tier D's
   combo logic is ready and waiting on these clips.
6. **Charge clips + charge whir SFX** — Tier D's heavy-charge loop.
7. **Riposte paired clips + riposte stab SFX** — finishes Tier D's
   posture-broken execution moment.
8. **Per-status visual scenes (bleed/burn/corruption)** — Tier G icons.
9. **Per-region hurtbox retrofit on each Avatar / boss / minion** —
   Tier G crit-spot damage. Editor-restructuring work; not a render asset.
10. **Per-faction avatar meshes + animation libraries** — Tier E
    asymmetry. Largest scope; defer until at least one faction has a
    fully-built combat loop you've playtested.

Skip per-archetype movesets (paired daggers, polearm, staff) until at
least one weapon archetype's loop is fun in playtest.

---

## By asset type

### Animations (per Avatar model + per minion model)

Clip-name conventions: `<library>/<clip>` per
[3d-asset-pipeline.md](3d-asset-pipeline.md). The state machine is
library-agnostic; faction skins set their own `<library>` prefix via
`FactionProfile.animation_library_name`.

| Clip | Unlocks | Hookup ref |
|---|---|---|
| `hit_react_light` / `hit_react_heavy` | Tier A reaction variety; StaggerState picks by damage threshold | [tier-a § Hit-react animations](tier-a-implementation.md#hit-react-animations) |
| `walk_forward` / `walk_back` / `walk_left` / `walk_right` (× run set) | Tier B strafe locomotion when target-locked | [tier-b § Strafe locomotion clips](tier-b-implementation.md#strafe-locomotion-clips) |
| `roll_forward` / `roll_back` / `roll_left` / `roll_right` | Tier B directional roll when target-locked | [tier-b § Directional roll clips](tier-b-implementation.md#directional-roll-clips) |
| `block_enter` / `block_loop` / `block_hit_light` / `block_hit_heavy` / `block_break` | Tier C BlockState | [tier-c § Defense animation clips](tier-c-implementation.md#defense-animation-clips) |
| `parry_flash` (one-shot upper-body deflect) | Tier C parry visual cue | [tier-c § Parry flash VFX](tier-c-implementation.md#parry-flash-vfx) |
| `parry_recoil` (forced-recovery on parried attacker) | Tier C ParryRecoilState | [tier-c § Defense animation clips](tier-c-implementation.md#defense-animation-clips) |
| `posture_broken` (long unbalanced loop) | Tier C PostureBrokenState | [tier-c § Defense animation clips](tier-c-implementation.md#defense-animation-clips) |
| `backstep` (short i-frame retreat) | Tier C BackstepState | [tier-c § Defense animation clips](tier-c-implementation.md#defense-animation-clips) |
| `light_1` / `light_2` / `light_3` (combo string with combo-window method tracks) | Tier D 3-hit combo | [tier-d § Animation clips](tier-d-implementation.md#animation-clips-per-avatar-model) |
| `heavy_1` (single big swing) | Tier D HeavyAttackState | [tier-d § Animation clips](tier-d-implementation.md#animation-clips-per-avatar-model) |
| `heavy_charge_loop` / `heavy_charge_release` (held charge → release) | Tier D ChargeWindupState / ChargeReleaseState | [tier-d § Animation clips](tier-d-implementation.md#animation-clips-per-avatar-model) |
| `sprint_attack` / `jump_attack` | Tier D SprintAttackState / JumpAttackState | [tier-d § Animation clips](tier-d-implementation.md#animation-clips-per-avatar-model) |
| `riposte_attacker` + `riposte_victim` (paired, position-snapped) | Tier D Riposte execution | [tier-d § Animation clips](tier-d-implementation.md#animation-clips-per-avatar-model) |
| `ultimate_<faction>` (per-faction ultimate cast pose) | Tier E slot-4 ultimate | [tier-e § Ultimate ability animation slot](tier-e-implementation.md#ultimate-ability-animation-slot) |
| `respawn_rise` (optional getting-up clip) | Tier F respawn delay | [tier-f § Respawn animation hookup](tier-f-implementation.md#respawn-animation-hookup) |

**Method tracks each new offensive clip needs** (timing in
animation-frame ratios, not seconds):
- active-start: `lock_action`, `enable_stagger_immunity` (if hyper-armor),
  `%AttackHitbox.enable(<profile>)`
- active-end: `%AttackHitbox.disable`, `disable_stagger_immunity`,
  `unlock_action`
- recovery-mid: `_combo_window_open` (Tier D — combo strings only)
- recovery-end: `_combo_window_close`
- foot-down: `_spawn_dust(&"footstep")` (Tier A — locomotion)
- roll-start: `_spawn_dust(&"roll_dust")`
- jump_land impact: `_spawn_dust(&"land_dust")`

Full contract in [action-gating](../systems/avatar-combat.md#per-animation-method-track-checklist).

---

### Particles / VFX scenes

Each VFX entry is a `.tscn` under `scenes/vfx/`. The file paths below are
stubs the code already references — replacing the contents with authored
particles "just works." No code changes needed.

| Scene | Unlocks | Code consumer | Hookup ref |
|---|---|---|---|
| `scenes/vfx/hit_spark_flesh.tscn` | Tier A hit feedback (default) | `HitFx.spawn(&"flesh", …)` | [tier-a § Hit spark scenes](tier-a-implementation.md#hit-spark-scenes) |
| `scenes/vfx/hit_spark_armor.tscn` | Tier A hit feedback (armor-tagged hurtboxes) | `HitFx.spawn(&"armor", …)` | [tier-a § Hit spark scenes](tier-a-implementation.md#hit-spark-scenes) |
| `scenes/vfx/hit_spark_shield.tscn` | Tier C blocked-hit feedback | `HitFx.spawn(&"shield", …)` (call site documented) | [tier-c § shield variant](tier-c-implementation.md#hit-spark-shield-variant-on-blocked-hits) |
| Footstep / roll / land dust (designer-named under `scenes/vfx/`) | Tier A locomotion texture | `Actor.dust_scenes` dict + `_spawn_dust(kind)` | [tier-a § Footstep / dust hook](tier-a-implementation.md#footstep--dust-hook) |
| `parry_flash` particle (recommended at chest-bone) | Tier C parry connect feedback | wire to the `Actor.parried` signal in a HUD-FX scene | [tier-c § Parry flash VFX](tier-c-implementation.md#parry-flash-vfx) |
| Posture-break burst | Tier C posture-zero moment | wire to `Actor.posture_broken` signal | [tier-c § Posture-break VFX](tier-c-implementation.md#posture-break-vfx--sfx) |
| Charge buildup glow | Tier D charge_loop | spawn from `ChargeWindupState._enter`; free on exit | [tier-d § VFX hooks](tier-d-implementation.md#vfx-hooks) |
| Riposte impact | Tier D riposte connect | spawn from `RiposteAttackerState`'s connect frame | [tier-d § VFX hooks](tier-d-implementation.md#vfx-hooks) |
| Per-faction ultimate cast effect | Tier E ultimate flair | wire as a child of each ultimate AbilityEffect scene | [tier-e § Per-faction VFX/SFX hooks](tier-e-implementation.md#per-faction-vfxsfx-hooks) |
| Per-faction death dissolve | Tier E death flavor | spawn from DeathState by faction lookup | [tier-e § Per-faction VFX/SFX hooks](tier-e-implementation.md#per-faction-vfxsfx-hooks) |
| Per-status `visual_scene` (bleed / burn / corruption / slow / silenced) | Tier G HUD-side icon over affected actor | `StatusEffect.visual_scene` slot per `.tres` | [tier-g § Status visual scenes](tier-g-implementation.md#status-visual-scenes) |
| `scenes/vfx/telegraph_arc.tscn` | Tier G boss telegraph (placeholder ships; swap mesh) | `TelegraphArc.setup()` from boss state | [tier-g § Telegraph arc — swapping the placeholder](tier-g-implementation.md#telegraph-arc--swapping-the-placeholder) |

---

### Shaders

| Shader / material | Unlocks | Code consumer | Hookup ref |
|---|---|---|---|
| `hit_flash_intensity` uniform on actor model `ShaderMaterial`s | Tier A hit-flash on damage | `Actor._set_hit_flash_intensity` writes the uniform every frame while > 0 | [tier-a § Hit-flash shader](tier-a-implementation.md#hit-flash-shader) + [hit-flash-shader.md](hit-flash-shader.md) |

Plain `StandardMaterial3D` meshes are silently skipped — opt-in by author
per surface.

---

### Audio (SFX)

**Audio is currently deferred across the entire combat stack.** The
`_spawn_dust` shape is the canonical pattern for the eventual `_spawn_sfx`
forwarder; ship it the same way (per-actor `Dictionary[StringName,
AudioStream]` export + animation method-track call + `_is_resimulating`
gate). The list below records the call sites for when audio lands.

| Sound | When | Tier ref |
|---|---|---|
| Footstep × surface (4 surfaces × 2 paces) | Walk/run loops | [tier-a § Hit / footstep sounds](tier-a-implementation.md#hit--footstep-sounds) |
| Cloth roll / dodge whoosh | Roll, backstep | tier-a, tier-c |
| Weapon whoosh × archetype | Active window of swings | tier-a, tier-d |
| Impact × material × damage type | Damage applied | tier-a; per-type expansion in tier-g |
| Block clang | Damage absorbed by block | [tier-c § Defense animation clips](tier-c-implementation.md#defense-animation-clips) |
| Parry ding | Successful parry | [tier-c § Parry flash VFX](tier-c-implementation.md#parry-flash-vfx) |
| Stagger grunt | Enter StaggerState | tier-a |
| Posture-break growl | Posture meter break | [tier-c § Posture-break VFX / SFX](tier-c-implementation.md#posture-break-vfx--sfx) |
| Charge whir | Heavy charge_loop | [tier-d § SFX hooks](tier-d-implementation.md#sfx-hooks) |
| Riposte stab | Riposte connection | [tier-d § SFX hooks](tier-d-implementation.md#sfx-hooks) |
| Ultimate cast (per faction) | Slot-4 activation | [tier-e § Per-faction VFX/SFX hooks](tier-e-implementation.md#per-faction-vfxsfx-hooks) |
| Death sound (per faction) | DeathState enter | tier-e |
| Ability casts | Per-ability AbilityEffect scenes | (audit existing) |

---

### HUD / UI assets

| Asset | Unlocks | Code consumer | Hookup ref |
|---|---|---|---|
| Health bar styling | already exists; verify per-Avatar feel | `scenes/ui/hud/avatar_hud.tscn` | n/a |
| Damage number font / colour | Tier A | `scenes/ui/damage_number.tscn` | [tier-a § Damage numbers](tier-a-implementation.md#damage-numbers) (autoload + scene) |
| Reticle texture (replaces `PlaceholderTexture2D`) | Tier B | `scenes/ui/lock_on_reticle.tscn`, Sprite3D.texture | [tier-b § Reticle texture](tier-b-implementation.md#reticle-texture) |
| Posture bar (red/orange tone, near-break pulse styling) | Tier C | `scenes/ui/posture_bar.tscn` | [tier-c § Posture HUD styling](tier-c-implementation.md#posture-hud-styling) |
| Cooldown ring × 3 (or 4 if ultimate ships) | Tier E ultimate slot | existing `avatar_hud` (verify slot 4 added) | [tier-e § Ultimate ability animation slot](tier-e-implementation.md#ultimate-ability-animation-slot) |
| Ultimate charge meter | Tier E slot-4 charge gauge | existing HUD; reads `PlayerActor.ultimate_charge` | tier-e |
| Hit-direction indicator (red arc when hit from off-screen) | Tier F anti-camera-loss | not yet built — design open | tier-f future |
| Status-icon row (one icon per active StatusEffect, above HP bar) | Tier G | not yet built — `StatusController` would emit a signal pair | [tier-g § Known limitations](tier-g-implementation.md#known-limitations--followups) |

---

### Scene retrofits (editor work)

These are scene-structure changes that must be done in-editor (per
CLAUDE.md §6 — editor restructuring is a hand-off, not text-edited).

| Retrofit | Unlocks | Template / source | Hookup ref |
|---|---|---|---|
| Reticle texture swap (one-line) | Tier B | `scenes/ui/lock_on_reticle.tscn` | [tier-b § Reticle texture](tier-b-implementation.md#reticle-texture) |
| Per-actor `dust_scenes` dict population | Tier A locomotion dust | actor `.tscn` inspector | [tier-a § Footstep / dust hook](tier-a-implementation.md#footstep--dust-hook) |
| Per-actor `material_kind` on Hurtbox | Tier A spark variety | actor `.tscn` inspector | [tier-a § Hit spark scenes](tier-a-implementation.md#hit-spark-scenes) |
| Spawn-point Marker3D anchors (replace placeholder `RESPAWN_POSITIONS`) | Tier F anti-camp respawn | level scene | [tier-f § Spawn-point markers](tier-f-implementation.md#spawn-point-markers) |
| Per-actor 3-region Hurtbox retrofit (`Head` / `Torso` / `Legs`) | Tier G crit damage | `scenes/test/hurtbox_regions_template.tscn` | [tier-g § Per-region hurtbox retrofit](tier-g-implementation.md#per-region-hurtbox-retrofit) |
| Per-actor `damage_type_resistances` dict population | Tier G fire-immune undead etc. | actor `.tscn` inspector | [tier-g § Per-actor damage-type resistances](tier-g-implementation.md#per-actor-damage-type-resistances) |
| `TelegraphArc` mesh swap (placeholder → real VFX) | Tier G boss telegraph | `scenes/vfx/telegraph_arc.tscn` | [tier-g § Telegraph arc swap](tier-g-implementation.md#telegraph-arc--swapping-the-placeholder) |
| Per-faction inherited avatar scenes | Tier E faction visual asymmetry | `scenes/actors/player/avatar/avatar_actor.tscn` (parent) | [tier-e § Per-faction avatar mesh inherited scenes](tier-e-implementation.md#per-faction-avatar-mesh-inherited-scenes) |
| Friendly-fire indicator (HUD overlay when FF off and same faction) | Tier F clarity | HUD scene | [tier-f § Friendly-fire visual indicator](tier-f-implementation.md#friendly-fire-visual-indicator) |

---

### Models / meshes

| Mesh | Unlocks | Notes | Hookup ref |
|---|---|---|---|
| Per-faction avatar mesh (4 total) | Tier E asymmetry | Same rig; bone names must match across faction skins | [tier-e § Per-faction avatar mesh inherited scenes](tier-e-implementation.md#per-faction-avatar-mesh-inherited-scenes) |
| Weapon mesh × archetype | Tier E (or earlier per-archetype iteration) | `weapon_grip` socket on hand bone | [avatar-combat.md § Weapon archetypes](../systems/avatar-combat.md#weapon-archetypes) |
| Per-region hurtbox shapes (Head sphere, Torso capsule, Legs capsule) | Tier G crit damage | Use template; tune transforms per actor scale | [tier-g § Per-region hurtbox retrofit](tier-g-implementation.md#per-region-hurtbox-retrofit) |
| LOD / low-tri weapon variants | Tier E (perf) | For overlords watching from war table | [avatar-combat.md § Weapon archetypes](../systems/avatar-combat.md#weapon-archetypes) |

---

### Data resources (`.tres` authoring, no art skill needed)

| Resource | Unlocks | Path | Hookup ref |
|---|---|---|---|
| `AttackData` per swing (designer balancing) | Tier D — eight starter `.tres` ship; tune per faction | `data/attacks/*.tres` | [tier-d § AttackData `.tres` files](tier-d-implementation.md#attackdata-tres-files) |
| Boss `AttackData` per attack (parryable / unparryable, damage type) | Tier G | `data/attacks/boss_*.tres` (TBD) | [tier-g § Boss AttackData authoring](tier-g-implementation.md#boss-attackdata-authoring) |
| `FactionProfile` combat stats per faction | Tier E (4 ship; tune values) | `data/factions/*.tres` | [tier-e § Per-faction animation library naming](tier-e-implementation.md#per-faction-animation-library-naming) |
| `FactionPassive` `.tres` per faction | Tier E (4 ship; designers extend) | `data/factions/passives/*.tres` | tier-e |
| Ultimate `AvatarAbility` per faction | Tier E (placeholders ship) | `data/abilities/ultimate_*.tres` | [tier-e § Ultimate ability animation slot](tier-e-implementation.md#ultimate-ability-animation-slot) |
| `StatusEffect` `.tres` extras (poison, frozen, marked, …) | Tier G open expansion | `data/status/*.tres` | [tier-g § Status visual scenes](tier-g-implementation.md#status-visual-scenes) |

---

## What's working today without art

For grounding: with zero asset work, the following systems are functional
right now (they fall back to the legacy clip when a new clip is missing,
and to placeholders when a new VFX scene is missing):

- Hitstop, damage numbers, camera shake, hit sparks (placeholder spheres)
- Hard-lock targeting + cycling + reticle (placeholder texture)
- Block + parry + posture meter + posture-broken state (legacy stagger
  clip used as fallback for `block_*`)
- Light/heavy split, 3-hit combo, charge release, sprint/jump attack,
  riposte (legacy `Attack` clip used everywhere as fallback)
- Faction stats, passives, slot-4 ultimate (placeholder effects), corruption_power
- Respawn invuln + delay, FF toggle, takeover edge harness
- Bleed / burn / corruption / slow / silenced statuses (numerical effects
  only; no above-actor icons until `visual_scene` is set per-status)
- Boss `parryable` flag plumbed; telegraph arc ships as a fading
  yellow→red plane

Everything else lives behind one of the rows above. Pick the row, follow
the linked tier doc's section, ship.
