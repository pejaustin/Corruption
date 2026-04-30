# Tier E — Faction Asymmetry: Implementation Notes

Code-side roadmap for the [avatar-combat.md Tier E](../systems/avatar-combat.md#tier-e--faction-asymmetry)
faction-asymmetry pass. Every system in the table below is plumbed; none
requires art to function. Where art is expected (per-faction skins,
animation libraries, ultimate VFX/SFX), the system runs as a stub with a
documented swap-in point — base-avatar mesh and the existing `large-male/*`
animations carry every faction until per-faction libraries are authored.

**Architectural notes:**

- **Faction stats land on `FactionProfile`.** Authoring is `.tres` only —
  designers tune `avatar_hp`, `avatar_base_damage`, `attack_speed_mult`,
  `roll_distance`, `roll_iframe_ticks`, `max_posture` per faction in the
  inspector. AvatarActor reads them once on `activate(peer_id)` and caches
  override fields locally for the life of the claim.
- **`FactionPassive` is a Resource subclass, not a Node.** Subclasses live
  in `scripts/faction_passive_*.gd`; instances live in
  `data/factions/passives/*.tres`. Hooks (`on_attack_connect`,
  `on_take_damage`, `on_kill`, `on_tick`) fire from `Actor.take_damage` and
  `Actor._rollback_tick`. The passive resource is shared across actors of
  the same faction — per-actor mutable state lives on the actor (meta or
  field), not on the passive.
- **One new netfox `state_property`:** `ultimate_charge: int` on
  `PlayerActor`, registered in `player_actor.tscn`. Increments on damage
  taken / dealt / kill via `Actor.add_ultimate_charge`; drains on cast.
- **Slot 4 / ultimate** uses `is_ultimate: bool` on `AvatarAbility` plus
  `AvatarAbilities.SLOT_ULTIMATE = 3`. Charge-gated, not cooldown-gated. The
  fourth ability lives at `avatar_abilities[3]`; `avatar_abilities[2]` (the
  unused `item_2` slot) is null in every shipped faction profile.
- **Resource economy plumbing is dormant.** `AvatarAbility.cost = 0` and
  `AvatarAbility.cost_resource = &""` on every shipped ability — the cost
  gate in `AvatarAbilities._request_activate` is a passthrough until a
  designer sets `cost > 0` on a `.tres`. `GameState.corruption_power[peer_id]`
  is replenished by kills (`+25`) and gemsite captures (`+50`); no shipped
  ability spends it.
- **DOT in Fey passive is temporary.** `Actor._passive_queued_hits` /
  `queue_delayed_damage()` is a Tier-E-only hack. Tier G's `StatusEffect`
  system replaces it with typed status pipelines.

---

## Status

| System | Code | Asset hookup | File(s) |
|---|---|---|---|
| `FactionProfile` combat-stat exports | Done | Tune values per faction in `.tres` | `scripts/faction_profile.gd:30-87` |
| `FactionProfile.passive` reference | Done | Wire `.tres` per faction | `scripts/faction_profile.gd:79`, `data/factions/{undeath,demonic,nature_fey,eldritch}.tres` |
| `FactionProfile.animation_library_name` | Done | Set per faction once art lands | `scripts/faction_profile.gd:90` |
| `FactionPassive` base resource | Done | n/a | `scripts/faction_passive.gd` |
| `FactionPassiveUndeath` (lifesteal + kill heal) | Done | n/a | `scripts/faction_passive_undeath.gd` |
| `FactionPassiveDemonic` (25% extra-hit) | Done | n/a | `scripts/faction_passive_demonic.gd` |
| `FactionPassiveFey` (3-stack bleed DOT) | Done | n/a | `scripts/faction_passive_fey.gd` |
| `FactionPassiveEldritch` (every-3rd slow) | Done | n/a | `scripts/faction_passive_eldritch.gd` |
| Per-faction passive `.tres` instances | Done | n/a | `data/factions/passives/*.tres` |
| Avatar applies faction stats on claim | Done | n/a | `scenes/actors/player/avatar/avatar_actor.gd:_apply_faction_combat_stats` |
| `Actor.get_faction_passive` cache | Done | n/a | `scenes/actors/actor.gd:get_faction_passive,set_faction_passive` |
| Passive hooks called from `take_damage` | Done — `on_attack_connect` (attacker), `on_take_damage` (victim), `on_kill` (attacker) | n/a | `scenes/actors/actor.gd:take_damage` |
| Passive `on_tick` from `_rollback_tick` | Done | n/a | `scenes/actors/actor.gd:_rollback_tick` |
| `ultimate_charge: int` state_property | Done | n/a | `scenes/actors/actor.gd:75`, `scenes/actors/player/player_actor.tscn:30` |
| Charge attribution (damage taken/dealt/kill) | Done | n/a | `scenes/actors/actor.gd:take_damage` |
| `Actor.add_ultimate_charge` / `is_ultimate_ready` / `drain_ultimate_charge` | Done | n/a | `scenes/actors/actor.gd:add_ultimate_charge` etc. |
| `AvatarAbility.is_ultimate` flag | Done | Set on ultimate `.tres` | `scripts/avatar_ability.gd:50` |
| `AvatarAbilities` 4-slot extension | Done — `SLOT_ULTIMATE = 3`, charge-gated activation | n/a | `scripts/avatar_abilities.gd:30-90` |
| `ultimate` input action | Done — Q (keyboard), gamepad button 7 | Rebind in editor if conflicts | `project.godot:[input] ultimate` |
| `AvatarInput.ultimate_input` held flag | Done | n/a | `scripts/avatar_input.gd:31-58` |
| AvatarActor ultimate input → activate_ability(3) | Done | n/a | `scenes/actors/player/avatar/avatar_actor.gd:_unhandled_input` |
| Per-faction ultimate `.tres` + scenes | Done — placeholder effects (heal, dmg buff, invis, AoE slow) | Replace `effect_scene` per faction once richer effects authored | `data/abilities/ultimate_*.tres`, `scenes/abilities/ultimate_*.tscn`, `scripts/abilities/ultimate_*_effect.gd` |
| `AvatarAbility.cost` / `cost_resource` (DORMANT) | Done | All shipped abilities have `cost = 0` | `scripts/avatar_ability.gd:35-44` |
| `GameState.corruption_power` per-peer | Done | n/a | `scripts/game_state.gd:36-46` |
| `corruption_power_changed` signal | Done | HUD listeners can subscribe | `scripts/game_state.gd:15` |
| `add_corruption_power` on kill | Done — host-side, +25 per kill | n/a | `scenes/actors/actor.gd:take_damage` (kill branch) |
| `add_corruption_power` on gemsite capture | Done — +50 to capturing peer | n/a | `scripts/interactibles/gem_site.gd:_set_captured` |
| Cost gate in `AvatarAbilities._request_activate` | Done — checks pool, deducts, falls through if cost=0 | n/a | `scripts/avatar_abilities.gd:_request_activate,_has_cost,_pay_cost` |
| `Actor._passive_queued_hits` queue | Done — drained in `_rollback_tick` host-only | n/a | `scenes/actors/actor.gd:_drain_passive_queued_hits` |
| `Actor.queue_delayed_damage` API | Done — used by Demonic + Fey passives | n/a | `scenes/actors/actor.gd:queue_delayed_damage` |
| `_passive_inhibit` recursion guard | Done — prevents passive hooks re-firing on delayed-damage re-entry | n/a | `scenes/actors/actor.gd:_drain_passive_queued_hits`, all four passives |
| `Actor.apply_movement_slow` / `get_movement_speed_mult` | Done — Eldritch passive applies; MoveState honors | n/a | `scenes/actors/actor.gd:apply_movement_slow`, `scenes/actors/player/states/{player_state,move_state}.gd` |
| Roll distance / i-frame override path | Done — `RollState` reads `actor.get_roll_*_override()` and scales duration | n/a | `scenes/actors/player/states/roll_state.gd:enter` |
| Attack speed multiplier path | Done — `LightAttackState._play_attack_clip` writes `speed_scale` from `actor.get_attack_speed_mult()` | Heavy/sprint/jump/charge states fall through at 1.0 — extend if needed | `scenes/actors/player/states/light_attack_state.gd:_play_attack_clip` |
| Per-faction max_posture override | Done — `_apply_faction_combat_stats` writes `max_posture` directly | Designers tune in `.tres` | `scenes/actors/player/avatar/avatar_actor.gd:_apply_faction_combat_stats` |
| Reset corruption_power in `GameState.reset` | Done | n/a | `scripts/game_state.gd:reset` |

`avatar-combat.md` has the system-level "Status by System" table; this file
is the file-level cross-reference.

---

## What works without art

You can plug Tier E into the existing avatar today and see all of:

- Cycle faction in the lobby (or use the Cycle Faction debug button), claim
  the avatar, and inspect the stats in the debug overlay or via console:
  - **Demonic:** 120 HP, 32 base damage, 0.95× attack speed, 130 max posture.
  - **Undeath:** 100 HP, 25 base damage, baseline.
  - **Fey:** 80 HP, 22 base damage, 1.20× attack speed, 8 m roll, 16-tick
    i-frames (vs. baseline 6 m / 12-tick), 90 max posture.
  - **Eldritch:** 80 HP, 18 base damage, baseline roll, 90 max posture.
- Roll as Fey → noticeably longer dodge distance and i-frame window.
- Light-attack as Fey → faster swings (`AnimationPlayer.speed_scale = 1.20`
  on swing entry; restored to 1.0 between swings via the existing hitstop
  recovery path).
- **Faction passive — Undeath:** Land any hit while controlling Undeath →
  attacker's HP ticks up by `5%` of `final_damage`. Land a killing blow →
  `+30 HP` bonus.
- **Faction passive — Demonic:** Land hits while Demonic. Roughly 1 in 4
  hits triggers a delayed half-damage follow-up `4` ticks later. The
  follow-up applies through standard `take_damage`, so block / parry /
  posture all interact correctly.
- **Faction passive — Fey:** Land any hit while Fey → target accumulates
  three 5-damage bleed ticks at 30, 60, 90 ticks (1 / 2 / 3 seconds at
  netfox 30 Hz). The bleed applies through the standard damage path.
- **Faction passive — Eldritch:** Land three hits in a row → on the third
  the target's movement multiplier drops to `0.75×` for 60 ticks (~2 s).
  Visible by watching a chasing minion slow down. Counter resets on a kill.
- **Ultimate charge:** Land hits, take hits, score kills → press `Q` (or
  gamepad button 7) when `ultimate_charge >= 100` to fire the faction's
  ultimate. Charge drains to 0 on cast.
  - Undeath ultimate: `+100 HP` self-heal + 5 s lifesteal.
  - Demonic ultimate: 5 s `2.5×` damage buff.
  - Fey ultimate: 3 s invisibility (model hidden).
  - Eldritch ultimate: AoE 75°-cone movement slow on every hostile in
    18 m for 3 s (0.5× multiplier).
- **Resource economy plumbing:** Watch `GameState.corruption_power[peer_id]`
  in the debug overlay (when wired). Killing minions / capturing gemsites
  bumps the pool. No shipped ability spends from it — set `cost > 0` on any
  `data/abilities/*.tres` to enable cost gating.

What does NOT work yet (art-gated):

- Per-faction avatar skins. Every faction shares the base `avatar.tscn`
  Paladin model. Set `FactionProfile.animation_library_name` and create
  inherited `.tscn` per faction once art lands.
- Per-faction ultimate VFX/SFX. The four shipped ultimates trigger gameplay
  effects but visually look like their non-ultimate cousins (Demonic's
  ultimate uses the same DemonRage-shaped buff with no VFX, etc.). Replace
  the `effect_scene` PackedScene on `data/abilities/ultimate_*.tres` with a
  richer scene to add visuals.
- Death-dissolve faction flavour. The death animation is generic. Listen
  on `Actor.died` and gate on `actor.faction` to spawn a per-faction
  dissolve VFX.

---

## Asset plug-in instructions

### Per-faction animation library naming

The 3D pipeline ([3d-asset-pipeline.md](3d-asset-pipeline.md)) calls clips
as `<library>/<clip>`. Each faction's avatar is an inherited scene of the
base avatar with a different `AnimationPlayer` library. To wire:

1. Author the clips in your DCC tool with the faction prefix (e.g.
   `demonic-male/Attack`, `undeath-male/Walk`).
2. Import the GLB into `assets/characters/avatar/<faction>/`.
3. Create an inherited `avatar_<faction>.tscn` from the base
   `avatar.tscn`.
4. Set `FactionProfile.animation_library_name = "demonic-male"` (etc.) on
   the faction's `.tres`.
5. Per-state `animation_name` exports already use the same convention
   (`large-male/Attack` etc.); the base scene's library prefix governs
   default playback. When per-faction libraries land, the avatar inherited
   scene reassigns the `AnimationPlayer` lookup path; no code changes
   needed.

### Per-faction avatar mesh inherited scenes

Each faction gets a `scenes/actors/player/avatar/avatar_<faction>.tscn`
that:

- Inherits from `avatar_actor.tscn`.
- Replaces the `Avatar` model node with the faction-specific GLB
  instance.
- Sets `default_avatar_scene` on the matching `data/factions/*.tres` to
  point at the new scene (the field already exists; it's the existing
  faction-skin override).

Per `docs/technical/3d-asset-pipeline.md`, the actor scene retains all
combat wiring (hurtbox, AttackHitbox, state machine); only the model
swaps.

### Ultimate ability animation slot

When per-faction ultimate animations land, add an `ultimate_<faction>`
clip to each animation library. The shipped ultimate effects don't yet
play a dedicated state-machine state — they instance an AbilityEffect
scene as a child of the actor, the same way the existing 3-slot abilities
do. To add a dedicated `UltimateState` (similar to the existing
`ChannelState`):

1. Create `scenes/actors/player/states/ultimate_state.gd` extending
   `PlayerState`. Mirror `ChannelState`.
2. Add an `UltimateState` node to `avatar_actor.tscn` under
   `RewindableStateMachine` with `animation_name = "<library>/ultimate"`.
3. In each `ultimate_*_effect.gd`, in `_on_activate`, call
   `(caster as Actor)._state_machine.transition(&"UltimateState")` if
   you want the body to enter the dedicated pose.

The state-driven path is OPTIONAL — the current ability-effect path is
sufficient for testing. Skipping this until art lands is fine.

### Per-faction VFX/SFX hooks

| FX | Where to hook |
|---|---|
| Death dissolve (per-faction flavour) | Listen on `Actor.died`; branch on `actor.faction`; spawn the appropriate dissolve scene. Faction colors live in `GameConstants.faction_colors` for tinting. |
| Ultimate cast effect | Inside each `ultimate_<faction>_effect.gd`'s `_on_activate`, after the gameplay logic, instance a one-shot VFX scene. Gate by `if NetworkRollback.is_rollback(): return` to avoid stacking during resimulation. |
| Eldritch slow indicator | `Actor.apply_movement_slow` is the place to spawn a debuff icon / status overlay. The slow timer ticks from `NetworkTime.tick`; the visual can poll `actor._slow_until_tick > NetworkTime.tick` per frame. |
| Fey bleed drip | When Fey passive queues a delayed hit, the visual is currently silent. Add a particle spawn inside `FactionPassiveFey.on_attack_connect` at the target's position before queuing the damage. |
| Demonic echo flash | Same pattern — spawn a brief red flash on the attacker inside `FactionPassiveDemonic.on_attack_connect` when the proc rolls true. |
| Ultimate-charge HUD meter | Listen on `Actor.took_damage` to refresh; or poll `actor.ultimate_charge` from the HUD's `_process`. The state_property carries it across rollback so any peer sees the same number. |

---

## How to test

The `scenes/test/war_table_test.tscn` harness is the iteration target.
Spawning a minion plus an Avatar and switching factions covers most paths.

### Faction stat application

1. Open lobby (or use Cycle Faction debug button) and pick **Demonic**.
2. Claim the avatar, then check via console / debug:
   - `actor.get_max_hp()` returns `120`.
   - `actor.get_attack_damage()` returns `32`.
   - `actor.max_posture` is `130`.
3. Switch to **Fey** and reclaim → `actor.get_max_hp() = 80`,
   `actor.get_attack_damage() = 22`, roll covers more ground.
4. Switch to **Eldritch** and reclaim → `actor.get_max_hp() = 80`,
   `actor.get_attack_damage() = 18`.

### Faction passives

1. **Undeath:** spawn a hostile minion. Take damage to drop the avatar to
   ~50 HP. Land hits — HP ticks up by 5% of each hit's final damage. Land
   a killing blow — HP jumps by 30.
2. **Demonic:** land 8–10 hits on a long-HP minion (set HP high in the
   minion type). Roughly 25% of hits should produce a delayed second
   damage tick about 4 frames later (visible in the damage numbers HUD if
   wired, or in the minion's HP).
3. **Fey:** hit a minion once. Watch its HP drop by `5` three times over
   the next ~3 seconds while the avatar does nothing.
4. **Eldritch:** hit a minion three times. On the third hit, the minion's
   movement noticeably slows for ~2 seconds.

### Ultimate charge & cast

1. Watch `actor.ultimate_charge` via console as you take and deal damage.
   It increments by:
   - +5 per damage taken
   - +10 per damage dealt that connects
   - +25 per kill
   Clamped to 100.
2. Once `ultimate_charge >= 100`, press **Q** (or gamepad button 7) →
   ultimate fires; charge drains to 0; cooldown ticks 1.0 s.
3. Faction-specific results:
   - **Undeath:** HP jumps by 100 (capped at max_hp); next 5 s of hits
     lifesteal.
   - **Demonic:** next 5 s of hits do 2.5× damage.
   - **Fey:** model disappears for 3 s.
   - **Eldritch:** every hostile in a 75° cone within 18 m gets a
     `0.5× movement slow` for 3 s.

### Resource economy plumbing (DORMANT default)

1. Kill a minion → `GameState.corruption_power[peer_id]` increments by
   25 (visible via console).
2. Capture a gemsite → `+50` to the capturing peer.
3. To enable a cost gate: edit any `data/abilities/*.tres`, set
   `cost = 50`, save. Activating that ability now requires
   `GameState.get_corruption_power(peer_id) >= 50`. The activation flow
   emits `ability_cost_insufficient(ability_id)` when blocked; HUD/SFX
   listeners can subscribe.

---

## Known limitations / followups

- **Resource economy is dormant.** All shipped abilities ship with
  `cost = 0`. Designers can A/B-test cost gating without code changes by
  editing per-ability `.tres`. Document any cost values in the matching
  faction's `.tres` so they appear in the balance CSV pipeline once
  AbilityData is added to its TARGETS table (see
  [tier-d-implementation.md](tier-d-implementation.md) "Balance CSV
  pipeline").
- **Per-archetype movesets require asset work, not code.** The state
  machine is asset-agnostic — light_1/2/3, heavy_1, sprint, jump, riposte
  all read their clip name from AttackData. Swapping animation libraries
  per faction (via `FactionProfile.animation_library_name` + inherited
  avatar `.tscn`) gives different visual identity without touching code.
  Diverging frame data per faction is a balance-CSV / per-faction
  AttackData duplicates exercise; not in Tier E scope.
- **DOT in Fey passive is a temporary hack.** `Actor._passive_queued_hits`
  is a Tier E-only mechanism. Tier G's `StatusEffect` system replaces it
  with typed status pipelines (bleed becomes a `StatusEffect.tres` with
  its own visual hook + resistance read). Migration when Tier G lands:
  drop `target.queue_delayed_damage(...)` calls in favor of
  `StatusController.apply(target, BLEED_STATUS)`.
- **Ultimate AbilityEffect scenes are placeholders.** All four ultimate
  effects ship with the simplest possible implementation re-using existing
  AbilityEffect query overrides (`grants_lifesteal`, `get_damage_multiplier`,
  `makes_invisible`). Replace `effect_scene` on the matching `.tres` with
  a richer scene (custom VFX, sub-state transitions, AoE damage rings)
  when art and design land.
- **Ultimate has no dedicated AnimationState.** It currently spawns the
  effect scene as a child of the avatar without changing the avatar's
  body pose. Add an `UltimateState` (mirror `ChannelState`) and wire each
  effect's `_on_activate` to transition into it when the per-faction
  `ultimate_<faction>` clips land.
- **Attack-speed multiplier only applies to LightAttackState.** Heavy /
  sprint / jump / charge_release retain `speed_scale = 1.0`. Extend each
  state's `_play_attack_clip` with the same `actor.get_attack_speed_mult()`
  poke if/when designers want full-moveset acceleration. Skipped here
  to keep the change surface minimal — light combos are the bulk of swings
  and the most "feel" sensitive.
- **Ultimate-charge HUD meter is unwired.** The state_property is synced
  and the public API (`Actor.is_ultimate_ready`,
  `actor.ultimate_charge`) is in place. A HUD widget (likely an addition
  to `AbilityCross` or a dedicated bar) is a polish-pass task.
- **`AbilityCross` HUD shows three slots.** Adding a fourth slot for the
  ultimate is a HUD polish task — the underlying data plumbing supports
  it (`AvatarAbilities.get_ability_at_slot(SLOT_ULTIMATE)`).
  `_slot_left` is currently the item_2 slot; either repurpose or add a
  separate `SlotUltimate` node above the cross.
- **Eldritch's strike counter can drift across faction switches.** The
  counter is stored on the actor as meta; switching factions mid-claim is
  unsupported (the avatar is recalled), but a quick re-claim on the same
  peer could carry the meta. Cleared on each `activate(peer_id)` is a
  one-line follow-up if it matters in playtest.
- **Demonic extra-hit RNG is non-deterministic across rollback resim.**
  `randf()` re-rolls per resim pass; the consequence is at most a
  cosmetic spark divergence on a roll-back tick. Authoritative damage
  application is host-driven via `take_damage`, so the canonical state
  always matches the host. If this becomes visible in playtests, switch
  to a deterministic xorshift seeded by `(NetworkTime.tick, attacker_id)`.
- **`item_2` slot is null in every shipped faction.** This was a pre-Tier-E
  state — Tier E retains it. Filling slot 2 with a third per-faction
  ability is a content-design decision; the slot is wired and an ability
  set there will activate on the existing `item_2` input.
- **`set_faction_passive` doesn't gate on minion vs avatar.** Minions
  resolve their passive lazily via `get_faction_passive`. If a minion's
  faction changes mid-match (currently impossible) the cache won't
  refresh — call `set_faction_passive(null)` to invalidate.
