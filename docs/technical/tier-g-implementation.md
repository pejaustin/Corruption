# Tier G — PvE Depth: Implementation Notes

Code-side roadmap for the [avatar-combat.md Tier G](../systems/avatar-combat.md#tier-g--pve-depth)
PvE depth pass. The systems plumbed here are mostly *consumed* by later art /
boss design — they ship as a generic `StatusEffect` framework, a per-attack
parryable flag, a placeholder telegraph cosmetic, and a per-region hurtbox
template that designers retrofit into existing actor scenes.

---

## Status

| System | Code | Asset hookup | File(s) |
|---|---|---|---|
| `StatusEffect` resource | Done | n/a (data-only) | `scripts/combat/status_effect.gd` |
| `StatusController` component | Done | n/a | `scripts/combat/status_controller.gd` |
| Status `.tres` catalog (5) | Done | designers add more | `data/status/{bleed,burn,corruption,slow,silenced}.tres` |
| StatusController node on base actor | Done | n/a | `scenes/actors/actor.tscn:7,32–33` |
| `active_status_ids` state_property | Done | n/a | `scenes/actors/player/player_actor.tscn:30` |
| StatusController tick in rollback | Done | n/a | `scenes/actors/actor.gd:_rollback_tick` |
| Damage-type resistance dict | Done | per-actor inspector | `scenes/actors/actor.gd:damage_type_resistances` |
| `AttackData.parryable` flag | Done | per-attack `.tres` toggle | `scripts/combat/attack_data.gd:parryable` |
| `parryable` consumed in take_damage | Done | n/a | `scenes/actors/actor.gd:take_damage` |
| Fey passive → StatusController | Done | n/a (migrated) | `scripts/faction_passive_fey.gd` |
| `TelegraphArc` cosmetic | Done | swap mesh / material | `scripts/vfx/telegraph_arc.gd`, `scenes/vfx/telegraph_arc.tscn` |
| Per-region hurtbox template | Done | retrofit per-actor | `scenes/test/hurtbox_regions_template.tscn` |
| Boss `parryable` integration | Hookup | designer authors AttackData per boss attack | (deferred — see "Asset plug-in") |
| Status visual scenes | Hookup | author per-status `visual_scene` | (deferred) |
| Status icon HUD | Deferred | future tier | n/a |

`avatar-combat.md` has the system-level Status by System table; this file is
the file-level cross-reference.

---

## What works without art

You can plug Tier G into the existing avatar today and see all of:

- **StatusEffect catalog**: `StatusEffect.lookup(&"bleed")` returns the bleed
  resource. Same for `burn`, `corruption`, `slow`, `silenced`.
- **StatusController on every actor**: every PlayerActor and MinionActor
  carries a `StatusController` child node (inherited from `actor.tscn`).
  `actor.get_status_controller()` returns it.
- **Apply / clear**: `controller.apply(StatusEffect.lookup(&"bleed"))` adds
  the effect on the host; clients see it after the next state-prop sync.
- **Damage-tick application**: `bleed` ticks 5 damage every 30 ticks for 6 s,
  routed through `Actor.take_damage` so block / parry / posture / lifesteal
  all interact correctly. Stacks up to 3.
- **Aggregate queries**: `controller.get_movement_mult()` and
  `get_attack_speed_mult()` multiply across all active statuses; consumed
  by `Actor.get_movement_speed_mult` and `Actor.get_status_attack_speed_mult`.
- **Damage-type resistance**: set `damage_type_resistances` on any actor's
  `.tscn`; incoming damage of that type scales by the multiplier.
- **Fey passive bleed** now flows through `StatusController.apply` rather
  than the temp Tier-E delayed-damage queue.
- **Per-attack parryable flag**: any AttackData `.tres` with
  `parryable = false` skips the parry-window check inside the victim's
  `take_damage`. Defaults to true so existing player attacks remain
  parryable.
- **Telegraph cosmetic**: `TelegraphArc` instance with a flat plane mesh,
  fades from yellow to red over its windup, flashes on cancel/active,
  self-frees. Placeholder visual; swap the mesh / material with authored
  VFX scenes.
- **Per-region hurtbox template**: `scenes/test/hurtbox_regions_template.tscn`
  shows the three-shape pattern (Head 1.5×, Torso 1.0×, Legs 0.75×) with
  the `material_kind = &"flesh"` and `profile_damage` Dict already wired.

What does NOT work yet (asset-gated):

- **Boss telegraph spawning** — `TelegraphArc.setup()` exists; bosses must
  call it from their attack states' enter / exit code. Not auto-wired.
- **Per-region hurtbox switching at hit time** — the hurtbox supports
  multiple profiles (Head / Torso / Legs) but the attacker side has to
  call `hurtbox.enable(profile)` to pick which one is live for a swing.
  See "Known limitations" — designers wire per-attack profile selection.
- **Status visuals** — `StatusEffect.visual_scene` is null on every
  shipped `.tres`; populate to make a status visible above the affected
  actor.
- **Damage-type tag propagation from direct hits** — the resistance
  multiplier reads `_pending_damage_type` meta on the victim, set by
  StatusController for status DOTs. Direct attacks don't yet plumb the
  type through. See "Known limitations" for the one-line fix.
- **Boss audit** — the existing `GuardianBoss` and `CorruptedSeraph` don't
  yet author AttackData per attack. Once they do, designers flip
  `parryable = false` per attack to mark unparryable specials.

---

## Asset plug-in instructions

### Status visual scenes

Each `data/status/*.tres` has a `visual_scene: PackedScene` slot. Default
is null → no visual. To add an above-actor icon for bleed:

1. Author `scenes/vfx/status_visual_bleed.tscn` — a `Node3D` with a
   billboarded `Sprite3D` (or particle), positioned `+1.8` Y above the
   actor (chest-level). The script can be empty; the controller frees it
   on expire.
2. Open `data/status/bleed.tres` in the inspector. Drag the visual scene
   into `visual_scene`. Save.
3. The next applied bleed spawns the visual as a child of the affected
   actor. On expire, it queue_frees automatically.

The `StatusController._spawn_visual` is gated by `_is_resimulating` so
rollback doesn't stack visuals.

### Per-region hurtbox retrofit

The current `avatar_actor.tscn` and `minion_actor.tscn` ship a single
hurtbox shape (the simple capsule on the Hurtbox node). To get crit
damage on head shots, copy the pattern from
`scenes/test/hurtbox_regions_template.tscn`:

1. Open the actor's `.tscn` in the editor.
2. Delete the existing single CollisionShape3D under the Hurtbox.
3. Copy the three children (`Head`, `Torso`, `Legs`) from the template.
4. Adjust their transforms to match the actor's mesh (scale, height
   offset). The template values target a humanoid standing ~2 m tall.
5. On the Hurtbox node itself, set `profile_damage` to:
   ```
   { &"head": 1.5, &"torso": 1.0, &"legs": 0.75 }
   ```
6. Per CLAUDE.md §6, this is editor-restructuring (deleting a child of
   an existing node). Hand-edit only if the actor scene is small. Better:
   open in editor and visually drop in the regions.

The attacker side then needs to call `hurtbox.enable(&"head")` /
`enable(&"torso")` / `enable(&"legs")` based on which body part the swing
hit. The simplest approach: the AttackHitbox detects overlap with each
shape and picks whichever has the closest contact point. For Tier G the
hookup is left as a designer task; the framework supports it.

### Telegraph arc — swapping the placeholder

`scenes/vfx/telegraph_arc.tscn` ships a flat `PlaneMesh` with a
yellow/red `StandardMaterial3D`. The script mutates `albedo_color`
during the windup. To replace with a real VFX:

1. Open the scene in the editor.
2. Replace the `Mesh` child with whatever VFX you want — particle
   system, decal, animated mesh. Keep the unique-name `%Mesh` so the
   script's `_apply_color` continues to work, OR remove it and override
   `_apply_color` with a no-op (the fade is purely cosmetic; you can
   drive your own animation independently).
3. Boss attack states call:
   ```gdscript
   var arc := TELEGRAPH_SCENE.instantiate() as TelegraphArc
   get_tree().current_scene.add_child(arc)
   arc.setup(active_world_pos, facing_dir, windup_seconds)
   # ...active frame:
   arc.cancel()
   ```

### Boss `AttackData` authoring

`AttackData.parryable: bool` defaults to `true`. To mark a boss attack
unparryable (e.g. a windmill spin or grab):

1. Create / open the AttackData `.tres` for that attack
   (`data/attacks/boss_*.tres` once authored).
2. Set `parryable = false`.
3. Boss state passes the AttackData through the existing damage path;
   `take_damage` reads the `_pending_parryable` meta and skips the
   parry check.

The existing player-attack `.tres` files (light_1/2/3, heavy_1, etc.)
keep `parryable = true` by default — no change needed.

### Damage-type tagging on direct hits

To make a swing apply fire damage that benefits from `damage_type_resistances`:

1. Set `damage_type = &"fire"` on the AttackData `.tres`.
2. Currently the attack states don't propagate this tag into the victim's
   `take_damage` resistance lookup — see "Known limitations" for the
   one-line fix. Once that lands, the resistance multiplier auto-applies.

### Per-actor damage-type resistances

To make a fire-immune undead minion:

1. Open the minion's `.tscn`.
2. On the Actor root, set `damage_type_resistances` to:
   ```
   { &"fire": 0.0, &"corruption": 0.5 }
   ```
3. Save. Incoming `fire`-typed damage goes to 0. Missing types default
   to 1.0 (no resistance).

---

## How to test

### Status apply / tick / expire

In the existing harness `scenes/test/war_table_test.tscn`:

1. Run; spawn a minion (`1`).
2. With the Avatar, set faction to Fey via Cycle Faction (`F`).
3. Hit the minion with a light_attack. Observe: `Actor.took_damage`
   fires for the swing damage.
4. Watch the minion's HP — it should drop by 5 every ~1 s for 6 s
   (3 stacks of bleed × 5 dmg per tick × 30-tick interval = 5 dmg
   every second, 18 ticks total per stack).
5. Re-hit the minion before the bleed expires → stacks bump up to
   `max_stacks = 3`; duration refreshes to 180 ticks from the new
   apply (because `refresh_on_apply = true`).

### Damage-type resistance

1. Open `scenes/actors/minion/minion_actor.tscn` in the editor.
2. On the Actor root, set `damage_type_resistances` to
   `{ &"physical": 0.5 }`. Save.
3. Run the harness; hit the minion with the avatar's light attack.
4. Observe the damage number floats are halved compared to baseline.
5. Reset the property to `{}` afterward.

(Note: until the direct-hit damage-type tag is plumbed — see Known
limitations — the resistance only triggers for status DOTs, which
always tag their type via `_pending_damage_type`.)

### Telegraph cosmetic

1. Author a quick test in `scripts/test/war_table_test_controller.gd`
   that spawns a TelegraphArc on Q-press at the camera's hit point:
   ```gdscript
   if event.is_action_pressed("ui_cancel"):
       var arc := preload("res://scenes/vfx/telegraph_arc.tscn").instantiate() as TelegraphArc
       get_tree().current_scene.add_child(arc)
       arc.setup(camera.global_position + camera.basis.z * -3.0,
                 camera.basis.z * -1.0, 1.5)
   ```
2. Run; press the test hotkey. Observe a yellow/orange ground plane
   that fades to red over 0.9 s, then flashes yellow on cancel and
   self-frees.
3. Remove the temp hotkey before merging.

### Parryable flag

1. Open `data/attacks/heavy_1.tres` in the inspector. Set
   `parryable = false`. Save.
2. Run with two avatars (or one avatar + a spawned dummy). Time a tap-
   block as a heavy_1 connects → no parry triggers; the hit lands as a
   normal blocked hit.
3. Reset `parryable = true` afterward.

### Fey passive migration

Same as the status apply test — the Fey passive's bleed now flows
through `StatusController.apply` instead of the old delayed-damage
queue. The behavior is identical from the player's perspective. Verify
by checking that `target.get_status_controller().has_status(&"bleed")`
is true after a Fey hit.

---

## Known limitations / followups

- **Direct-hit damage-type propagation.** The `damage_type` field on
  `AttackData` exists but isn't currently piped into the victim's
  `_pending_damage_type` meta. Status DOTs propagate the tag via
  `StatusController._apply_tick`; direct attacks don't. One-line fix:
  in each attack state's `_on_hit_landed` (or wherever it calls
  `victim.take_damage(...)`), wrap with:
  ```gdscript
  victim.set_meta(&"_pending_damage_type", attack_data.damage_type)
  victim.take_damage(damage, self_actor)
  victim.remove_meta(&"_pending_damage_type")
  ```
  Deferred until per-faction attack damage types are designed.

- **Per-region hurtbox attack-side selection.** The framework supports
  multiple shapes per Hurtbox; the attacker has to choose which is
  active. The simplest pattern: each `AttackHitbox.tick()` checks the
  closest CollisionShape3D contact point and calls
  `hurtbox.enable(profile)` accordingly. Deferred — designers retrofit
  per-actor first.

- **Status visuals.** Every `data/status/*.tres` has `visual_scene = null`.
  No visual cue appears on affected actors today. Authoring is per-status
  art work; the hookup is mechanical.

- **Status HUD icons.** No row of buff/debuff icons above the avatar's
  HP bar. A `StatusController.status_added` / `status_removed` signal
  pair would let a HUD subscribe; not shipped in Tier G to keep the
  scope tight.

- **Boss telegraph wiring.** `TelegraphArc.setup()` is ready; bosses
  must call it. Defer until the boss attack rework decides which moves
  are telegraphed.

- **Boss `AttackData`.** `GuardianBoss` and `CorruptedSeraph` don't
  currently author `AttackData` per attack — they use hardcoded values
  in their state scripts. Designers convert each boss attack to an
  AttackData `.tres` to consume `parryable` (and the rest of the
  per-attack stat block).

- **`StatusEffect.on_apply` / `on_tick` / `on_expire` subclass hooks**
  are present but the data-driven path covers Tier G — no shipped
  status subclasses these. Reserved for special-case effects (e.g. a
  status that drains ultimate charge per tick) when designers want
  behavior beyond `damage_per_tick + speed_mult`.

- **Status sync at high tick rates.** Per-tick re-encoding of
  `active_status_ids: PackedStringArray` is gated by a signature
  compare in `_encode` — empty / unchanged ticks short-circuit. If
  status churn becomes a perf issue, switch to a per-status delta
  state property.

- **Catalog warmup.** `StatusEffect.lookup` lazy-loads on first call
  by walking `res://data/status/`. The catalog isn't refreshed at
  runtime; calling `clear_catalog()` forces a re-scan if statuses are
  added during a play session.

- **MinionActor status sync.** MinionActor's `_physics_process` skips
  the rollback-driven `Actor._rollback_tick`, so the StatusController's
  `tick_active` runs only when the minion's owning RPC sync triggers a
  tick. For Tier G the host applies statuses host-side and the visible
  effects (movement slow, periodic damage) work because damage is
  host-driven anyway. Promote to a tighter sync if minion DOTs need
  visible per-frame fidelity on clients.

- **Old `Actor.queue_delayed_damage` is still present.** It's the
  one-shot delayed-damage utility used by Demonic's "+1 hit" passive.
  Not deprecated; just orthogonal to the new StatusController. Audit
  later if it becomes redundant.

- **Damage-type meta cleanup.** Status DOTs set `_pending_damage_type`
  before calling take_damage and clear it after. If `take_damage`
  early-returns somewhere, the meta could leak. Worth a final
  `remove_meta` in a defer block if this becomes a real bug source.
