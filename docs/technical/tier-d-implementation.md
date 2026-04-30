# Tier D — Attack Depth Pass: Implementation Notes

Code-side roadmap for the [avatar-combat.md Tier D](../systems/avatar-combat.md#tier-d--attack-depth-pass)
attack-depth pass. Every system in the table below is plumbed; none requires
art to function. Where art is expected (8 attack clips, 2 paired riposte
clips, charge VFX/SFX), the system runs as a stub with a documented swap-in
point — the legacy single `Attack` clip carries every state until the named
variants are authored.

**Architectural notes:**

- This is the first tier to **lift balance data out of state-script
  `@export`s and into `Resource` files**. Every attack — light_1/2/3,
  heavy_1, charge release, sprint, jump, riposte — is a `data/attacks/*.tres`
  authored as `AttackData`. The state scripts read all damage / posture /
  hitbox-window numbers from that resource. Pre–Tier D, those values lived
  on each state node directly. Per
  [avatar-combat.md §1 risk callout](../systems/avatar-combat.md#tier-d--attack-depth-pass)
  the threshold for promotion is "≥ 3 attacks per faction" — Tier D ships
  ≥ 7 attacks for the avatar, so the extraction is overdue.
- Two new netfox `state_property` slots: `combo_step: int` and
  `charge_start_tick: int` on `PlayerActor`. Both rolled into
  `player_actor.tscn` alongside the Tier C posture trio.
- The riposte pair (`RiposteAttackerState` + `RiposteVictimState`) uses the
  same host-authoritative forced-transition pattern Tier C established with
  `ForcedRecovery`/`ParryRecoilState`.
- The legacy `attack_state.gd` is **deprecated, not deleted** — its node
  still lives in `avatar_actor.tscn` so any older references compile, but
  new wiring goes through `LightAttackState` / `HeavyAttackState` etc.

---

## Status

| System | Code | Asset hookup | File(s) |
|---|---|---|---|
| `AttackData` resource | Done | Author per-faction `.tres` files | `scripts/combat/attack_data.gd`, `data/attacks/{light_1,light_2,light_3,heavy_1,charge_release,sprint_attack,jump_attack,riposte}.tres` |
| AttackData catalog lookup | Done | n/a | `scripts/combat/attack_data.gd:lookup,_load_catalog` |
| `LightAttackState` (combo-aware) | Done | Author `light_1`/`light_2`/`light_3` clips with `_combo_window_open/close` method tracks | `scenes/actors/player/states/light_attack_state.gd` |
| `HeavyAttackState` (with charge promote) | Done | Author `heavy_1` clip | `scenes/actors/player/states/heavy_attack_state.gd` |
| `ChargeWindupState` | Done | Author `heavy_charge_loop` clip | `scenes/actors/player/states/charge_windup_state.gd` |
| `ChargeReleaseState` (level-picked) | Done | Author `heavy_charge_release` clip | `scenes/actors/player/states/charge_release_state.gd` |
| `SprintAttackState` | Done | Author `sprint_attack` clip | `scenes/actors/player/states/sprint_attack_state.gd` |
| `JumpAttackState` | Done | Author `jump_attack` clip | `scenes/actors/player/states/jump_attack_state.gd` |
| `RiposteAttackerState` (snap-in) | Done | Author `riposte_attacker` clip | `scenes/actors/player/states/riposte_attacker_state.gd` |
| `RiposteVictimState` (paired) | Done | Author `riposte_victim` clip | `scenes/actors/states/riposte_victim_state.gd` |
| `combo_step: int` state_property | Done | n/a | `scenes/actors/actor.gd:125`, `scenes/actors/player/player_actor.tscn:30` |
| `charge_start_tick: int` state_property | Done | n/a | `scenes/actors/actor.gd:129`, `scenes/actors/player/player_actor.tscn:30` |
| `combo_window_open: bool` (local) | Done | n/a | `scenes/actors/actor.gd:138` |
| `_combo_window_open()` / `_combo_window_close()` forwarders | Done | Add Call Method Tracks at recovery-mid / recovery-end frames | `scenes/actors/actor.gd:_combo_window_open,_combo_window_close` |
| Combo reset on take_damage / staleness | Done | n/a | `scenes/actors/actor.gd:take_damage,_decay_combo` |
| `light_attack` / `heavy_attack` input actions | Done | n/a | `project.godot:[input]` |
| Avatar input gather (light + heavy held + edge press) | Done | n/a | `scripts/avatar_input.gd` |
| `try_light_attack` / `try_heavy_attack` / `try_riposte` | Done | n/a | `scenes/actors/player/states/player_state.gd` |
| Sprint-attack entry from MoveState | Done — run + attack press while grounded → SprintAttackState | n/a | `scenes/actors/player/states/move_state.gd` |
| Jump-attack entry from JumpState/FallState | Done — attack press while airborne → JumpAttackState | n/a | `scenes/actors/player/states/jump_state.gd`, `fall_state.gd` |
| Riposte trigger (heavy near posture-broken target) | Done — `try_heavy_attack` defers to `try_riposte` | n/a | `scenes/actors/player/states/player_state.gd` |
| AttackData posture-mult plumbing through `take_damage` | Done — meta-passed `_pending_posture_mult` | n/a | `scenes/actors/actor.gd:take_damage`, all attack states `_handle_hits` |
| AttackHitbox profile passthrough | Done — each state forwards `attack_data.hitbox_profile` | n/a | all attack states' `_handle_hits` |
| Hyper-armor active window (AttackData-driven) | Done — `attack_data.hyper_armor` flips `stagger_immune` over hit window | n/a | `light_attack_state.gd`, `heavy_attack_state.gd`, `charge_release_state.gd`, `sprint_attack_state.gd`, `jump_attack_state.gd`, `riposte_attacker_state.gd` |
| Forward lunge per-AttackData | Done — `attack_data.lunge_distance` ramped over active window | n/a | same files as above |
| Legacy `AttackState` script deprecated (kept) | Done | n/a | `scenes/actors/player/states/attack_state.gd` (header comment) |
| AbilityCross HUD label rebind | Done — points at `light_attack` action | Tweak in editor if rebound | `scenes/ui/widgets/ability_cross.gd:13` |

`avatar-combat.md` has the system-level "Status by System" table; this file
is the file-level cross-reference.

---

## What works without art

You can plug Tier D into the existing avatar today and see all of:

- Tap **LMB** (or gamepad RT) → LightAttackState fires `light_1`'s damage
  profile (1.0× damage, 1.0× posture). The animation falls back to the
  legacy `large-male/Attack` clip.
- Re-tap LMB during the swing → press is buffered into the combo window;
  when the window opens (animation progress crosses
  `combo_window_start_ratio = 0.55` by default), the state chains to
  LightAttackState2 (`light_2`, 1.1× damage). A third tap chains again to
  LightAttackState3 (`light_3`, 1.5× damage). Without method tracks, the
  ratio-based fallback drives `combo_window_open` automatically.
- Wait > 2 seconds between attacks → combo memory decays via
  `_decay_combo`, the next tap restarts at light_1.
- Tap **V** (keyboard) or gamepad RB → HeavyAttackState fires `heavy_1`'s
  profile (1.8× damage, 2.0× posture, hyper-armor on the active window).
- Hold V past `CHARGE_HOLD_THRESHOLD_TICKS` (~6 ticks ≈ 200 ms) →
  HeavyAttackState defers to ChargeWindupState. The windup loop holds
  until you release V.
- Release V from charge → ChargeReleaseState picks an AttackData by
  hold time:
  - <6 ticks held: light release (`heavy_1.tres` fallback)
  - 6–14 ticks: mid release (`heavy_1.tres`)
  - ≥15 ticks: full release (`charge_release.tres`, 2.5× damage, 3.0×
    posture)
- Roll-cancel a charge windup → animation cancels, no damage dealt.
- Sprint (run held) + attack press → SprintAttackState fires
  `sprint_attack.tres`'s lunge profile. The state pulls the avatar
  forward over the active window via `lunge_distance`.
- Jump + attack press → JumpAttackState fires `jump_attack.tres`. The
  state drives a downward velocity until the avatar lands; hyper-armor
  protects the landing frame.
- Build a target's posture to break (Tier C) → press V near the broken
  target → `try_riposte` snaps the avatar to a melee-range slot in front
  of the victim, forces the victim into RiposteVictimState, and plays
  the riposte animation. 4.0× damage, 0.0× posture (the victim is
  already broken).

What does NOT work yet (art-gated):

- The 10 named animation clips below all currently fall back to
  `large-male/Attack` (or the configured fallback). The state machinery
  is correct; the animations are simply the same one swing playing
  every time.
- Charge buildup VFX (intensifying glow over the windup) — hook
  documented; deferred to whichever pass adds it.
- Riposte impact VFX — hook documented; piggybacks on the existing Tier A
  `HitFx.spawn(material_kind, ...)` system but probably wants its own
  scene (`hit_spark_riposte.tscn` or similar) for visual weight.
- Charge whir / riposte stab / weapon whoosh per attack — audio is still
  deferred (Tier A's `_spawn_sfx` follow-up).

---

## Asset plug-in instructions

### Animation clips (per Avatar model)

The 10 new clips live in the model's animation library
(`assets/characters/avatar/avatar.glb` → import → animations) under the
existing `large-male/` prefix. State scripts pull the prefix from the
state node's configured `animation_name` (typically `large-male/Attack` or
`large-male/Stagger`).

| Clip | Used by | Fallback |
|---|---|---|
| `large-male/light_1` | `LightAttackState` (combo step 1) — set on `light_1.tres` | `large-male/Attack` |
| `large-male/light_2` | `LightAttackState2` (combo step 2) — set on `light_2.tres` | `large-male/Attack` |
| `large-male/light_3` | `LightAttackState3` (combo step 3 / finisher) — set on `light_3.tres` | `large-male/Attack` |
| `large-male/heavy_1` | `HeavyAttackState` — set on `heavy_1.tres` | `large-male/Attack` |
| `large-male/heavy_charge_loop` | `ChargeWindupState` (looping pose) | `large-male/Stagger` |
| `large-male/heavy_charge_release` | `ChargeReleaseState` full release — set on `charge_release.tres` | `large-male/Attack` |
| `large-male/sprint_attack` | `SprintAttackState` — set on `sprint_attack.tres` | `large-male/Attack` |
| `large-male/jump_attack` | `JumpAttackState` — set on `jump_attack.tres` | `large-male/Attack` |
| `large-male/riposte_attacker` | `RiposteAttackerState` (paired with riposte_victim) | `large-male/Attack` |
| `large-male/riposte_victim` | `RiposteVictimState` (paired with riposte_attacker) | `large-male/Stagger` |

Each combat clip should also carry the standard method tracks per the
[3D pipeline](3d-asset-pipeline.md) and
[avatar-combat.md "Per-animation method-track checklist"](../systems/avatar-combat.md#per-animation-method-track-checklist):

| Frame | Method | Why |
|---|---|---|
| active-start | `lock_action` | Commit the swing |
| active-start | `enable_stagger_immunity` | Hyper-armor (if AttackData doesn't already drive it) |
| active-start | `%AttackHitbox.enable(<profile>)` | Open damage window — set `use_animation_keys = true` on the state if you want the keys to drive instead of ratios |
| active-end | `%AttackHitbox.disable` | Close damage window |
| active-end | `disable_stagger_immunity` | Drop hyper-armor |
| active-end | `unlock_action` | Recovery is cancellable |
| recovery-mid | `_combo_window_open` | (LightAttackState only) buffered light press chains |
| recovery-end | `_combo_window_close` | (LightAttackState only) buffer expires |

The `_combo_window_open` / `_combo_window_close` calls target the Actor
root (forwarded onto `combo_window_open` flag), same as
`lock_action`/`unlock_action`. Without method tracks, `LightAttackState`
falls back to `combo_window_start_ratio` / `combo_window_end_ratio` on the
AttackData — set `use_animation_keys = false` on the state to use the
ratio fallback (the default).

### AttackData `.tres` files

Open any of `data/attacks/*.tres` in the editor. The exported fields are:

| Field | Default | Meaning |
|---|---|---|
| `id` | matches filename | StringName key for catalog lookup; also used by `next_attack_id` chain |
| `display_name` | "Light Combo 1" | balance CSV label |
| `animation_name` | `large-male/Attack` | clip path (state falls back if missing) |
| `damage_mult` | 1.0 | × `actor.get_attack_damage()` |
| `posture_damage_mult` | 1.0 | × `Actor.HIT_POSTURE_PER_HIT` (Tier C constant) |
| `hyper_armor` | false | flips `stagger_immune = true` over the active window |
| `damage_type` | `&"physical"` | Tier G consumer (resistance / status) |
| `hitbox_start_ratio` / `hitbox_end_ratio` | 0.25 / 0.6 | active-window ratios |
| `hitbox_profile` | `&""` | `AttackHitbox.enable(profile)` argument; `&""` = first child shape |
| `combo_window_start_ratio` / `combo_window_end_ratio` | 0.55 / 0.85 | buffered chain window |
| `next_attack_id` | `&""` | next combo step (`&""` = combo end) |
| `lunge_distance` | 0.0 | meters of forward velocity over the active window |

The starter values were tuned for the existing `large-male/Attack` clip
length. When real `light_1/2/3` etc. animations land with different
durations, re-author the ratios per clip — they're authoring conveniences,
not gameplay constants.

### Adding a new combo step

1. Author a new clip (e.g. `large-male/light_4`).
2. Create `data/attacks/light_4.tres` (duplicate `light_3.tres`, set
   `id = &"light_4"`, `animation_name = "large-male/light_4"`).
3. Update `data/attacks/light_3.tres`: `next_attack_id = &"light_4"`.
4. Add a fourth `LightAttackState4` node in `avatar_actor.tscn` mirroring
   the existing pattern (script = `light_attack_state.gd`,
   `attack_data = ExtResource("light_4_data")`, `combo_step = 4`).
5. The chain auto-resolves via `_state_name_for_attack` — no script edit.

### VFX hooks

| FX | Where | When |
|---|---|---|
| Charge buildup glow | `ChargeWindupState.display_enter` (extend) | Spawn an effect scene parented under `actor._model`; intensify over time |
| Charge release burst | `ChargeReleaseState.display_enter` (extend) | One-shot spawn at hitbox position |
| Riposte impact | `RiposteAttackerState._spawn_local_hit_feedback` (extend) | Replace `HitFx.spawn(hurtbox.material_kind, ...)` with a riposte-specific scene; or add a new `&"riposte"` material kind to `HitFx.SCENES` |

All FX must be gated by `if NetworkRollback.is_rollback(): return` to avoid
stacking during resimulation — same pattern as Tier A.

### SFX hooks

Audio is still deferred (Tier A's `_spawn_sfx` follow-up). When it lands:

- `ChargeWindupState.display_enter` → `_spawn_sfx(&"charge_whir")`
- `ChargeReleaseState.display_enter` → `_spawn_sfx(&"charge_release")`
- `RiposteAttackerState._handle_hits` (on connect) → `_spawn_sfx(&"riposte_stab")`
- Per-attack `_handle_hits` connect → `_spawn_sfx(&"weapon_whoosh")` already
  conceptually wanted; can be hooked at the same time

### Balance CSV pipeline (deferred extension)

`scripts/build/balance_csv.gd` doesn't currently know about AttackData. To
enable spreadsheet round-tripping, add one entry to its `TARGETS` array:

```gdscript
{"name": "attacks", "dir": "res://data/attacks/", "script": "res://scripts/combat/attack_data.gd"},
```

The serializer auto-derives columns from the script's `@export` properties
via `get_property_list()`, so AttackData "just works" with the existing
import/export flow. See [balance-csv.md](balance-csv.md) for the workflow.

---

## How to test

The `scenes/test/war_table_test.tscn` harness is the iteration target —
spawns a real `OverlordActor` plus minions in an offline lobby. For Avatar
combat tests you'll want either:

- A live lobby (host + ≥1 client) with a peer claiming the Avatar via the
  tower scene, or
- Add a starter Avatar to the harness (one-line: instance
  `avatar_actor.tscn` next to the Overlord in `war_table_test.tscn` and
  call `activate(get_unique_id())` from the controller's `_ready`).

In the live-lobby setup with the avatar claimed:

### 3-hit combo

1. Walk into a hostile minion (press `2`/`3`/`4` to spawn enemies in the
   harness).
2. Press **LMB** three times in succession with each press inside the
   combo window of the previous swing (~150–800 ms apart).
3. Confirm the combo chain: the avatar's `combo_step` (visible via the
   debug overlay if exposed, or via console) goes 0 → 1 → 2 → 3.
4. Damage should escalate: ~25 → ~28 → ~38 (1.0× → 1.1× → 1.5× of base
   25 damage).

### Combo timeout

1. Press **LMB** once. Wait 2.5 seconds (longer than
   `COMBO_RESET_GRACE_TICKS = 60`). Press LMB again.
2. The second press should restart at `combo_step = 1`, not chain to
   `combo_step = 2`. Verify in console: `actor.combo_step` reads 1 each
   time.

### Charge attack

1. Hold **V** for at least ~600 ms (15+ ticks).
2. The avatar enters ChargeWindupState (looping charge pose, falls back
   to Stagger animation until art lands).
3. Release **V** → ChargeReleaseState fires `charge_release.tres`'s
   2.5× damage profile.
4. Tap **V** quickly (release before ~200 ms) → no charge promotion;
   plain HeavyAttackState fires. To verify: a tap should deal ~45 damage
   (1.8× × 25), a full release ~62 (2.5× × 25).

### Charge cancel via roll

1. Hold **V** to enter ChargeWindupState.
2. Press **C** (roll) before releasing.
3. The state cancels into RollState; no damage dealt; charge is lost
   (`actor.charge_start_tick` resets to -1).

### Sprint attack

1. Hold **Shift** (run) and a movement key, then press **LMB** while
   moving.
2. SprintAttackState fires; the avatar lunges forward 1.5 m over the
   active window per `sprint_attack.tres:lunge_distance`.

### Jump attack

1. Press **Space** (jump). While airborne, press **LMB** or **V**.
2. JumpAttackState fires; the avatar accelerates downward
   (`PLUNGE_DESCENT_VELOCITY = -10.0`).
3. Hyper-armor on the landing frame protects against incoming hits.

### Riposte

1. Engage a minion (or a second avatar) and pressure with blocks/parries
   until the target enters PostureBrokenState (Tier C).
2. While they're broken (`is_ripostable = true`), press **V** within
   2.5 m and facing them.
3. The avatar snaps to the riposte slot in front of the victim, the
   victim is forced into RiposteVictimState, and the riposte animation
   plays. Damage = ~100 (4.0× × 25) — typically lethal.

### Inputs / actions sanity

- LMB → `light_attack` action
- V (keyboard) / RB (gamepad button 5) → `heavy_attack` action
- F → `block` (Tier C) — should NOT conflict with V
- C → `roll`
- Middle mouse → `toggle_lock` (Tier B)

If V is bound elsewhere on your system, rebind in
**Project Settings → Input Map** without code changes.

### Resimulation gates (correctness check)

Same protocol as Tier A: with two peers and simulated 200 ms latency,
trade hits and confirm:

- Damage numbers / sparks / camera shake fire **exactly once per hit**.
- Combo step transitions are deterministic — both peers see the same
  `combo_step` after each press.
- Charge release damage is the same on both peers (`charge_start_tick`
  is rollback-synced; the held-tick computation is deterministic).
- Riposte snap-in: both peers see the attacker at the same position
  after the snap (transform is in `state_properties`).

---

## Known limitations / followups

- **Art-gated:** all 10 clips fall back to the legacy single attack
  animation. The state machinery is correct, but the visual identity of
  the moveset is missing until art lands.
- **Combo branching not supported.** Single canonical 3-hit string per
  faction (light → light → light). Per the design doc, branching
  (light → heavy → light vs. light → light → heavy) is deferred —
  re-evaluate after Tier E faction stats land.
- **Sprint / Jump attacks share one set of `*_attack.tres` configs.**
  Tier E may diverge per faction (Demonic = greatweapon plunge, Fey =
  dagger pirouette). Adding faction-specific AttackData is one new
  `.tres` plus a per-archetype state node; the AttackData lookup table
  finds them by `id` alone.
- **Charge VFX deferred.** The charge windup is mechanically correct —
  the looping animation plays, charge_start_tick latches — but there's
  no visible glow buildup. Hook is documented above.
- **Charge SFX deferred.** No audio for charge whir or riposte stab. Wait
  for the `_spawn_sfx` framework.
- **AttackData CSV export deferred.** The resource shape works fine with
  the existing pipeline; just add the dict entry to `TARGETS` when
  designers want spreadsheet tuning.
- **The legacy `attack_state.gd` is still wired in `avatar_actor.tscn`.**
  Removing it is a follow-up — its node is harmless (no transitions
  target it now that `try_attack` aliases through to LightAttackState).
  Removal requires re-saving the scene in-editor to clean up the orphan
  node; left as user-driven cleanup.
- **Riposte snap-in ignores the victim's hurtbox shape.** It snaps the
  attacker `RIPOSTE_OFFSET_DISTANCE = 1.4 m` from the victim's origin
  along the victim's forward axis. For most minion sizes this is fine;
  giant-class targets (Guardian Boss, future bosses) may want a
  per-minion-type override. Add a `riposte_offset_override` field on
  MinionType when needed.
- **Riposte facing assumes the victim is upright and facing in the
  expected direction.** Posture-broken minions face the player who
  broke them by default, but a posture-break-while-running edge case
  may leave them facing oddly. Acceptable for the stub pass.
- **`_pending_posture_mult` meta is used to pass the posture multiplier
  through `take_damage`.** Lightweight but a little gross — long-term
  the cleaner refactor is `take_damage(amount, source, posture_mult)`.
  Not done here to avoid touching every `take_damage` callsite (there
  are several outside the new attack states).
- **Heavy-press tap-vs-hold detection runs inside HeavyAttackState's
  pre-active window** — if the player holds V for less than
  `CHARGE_HOLD_THRESHOLD_TICKS` ticks but more than 0, they get a
  partial heavy that doesn't promote. This is intentional (a quick tap
  fires the heavy, a deliberate hold fires the charge windup), but
  worth playtesting — the threshold may need tuning.
- **Charge-release damage scaling is binary**: <6 ticks = light release
  (uses `light_attack_data` if set, else `mid_attack_data`); 6–14 ticks
  = mid; ≥15 = full. A continuous scaling curve would be smoother but
  AttackData-per-level keeps the data flat and CSV-friendly. Re-evaluate
  if playtesters want progressive feel.
- **Combo reset on `take_damage` ignores blocked/parried hits.** A
  blocked hit doesn't break the chain (you survived clean); a successful
  parry doesn't break the chain (the attacker got bounced, not you).
  Only an unblocked, non-parried hit with `final_damage > 0` resets
  `combo_step` and `charge_start_tick`. Documented inline in
  `actor.gd:take_damage`.
- **Sprint attack and jump attack states are uninterruptible** (empty
  cancel_whitelist). Hard commitment beat. Roll-cancel is allowed for
  sprint via the `cancel_whitelist`; jump attack is fully uncancellable
  (you committed in the air). If playtesters complain, swap to
  `cancel_whitelist = [&"RollState"]`.
- **Combo state_property `combo_step` is on the avatar but not yet
  surfaced in the HUD.** Tier E or polish pass can add a "1/2/3" visual
  pip to the AbilityCross center cell so the player can read where they
  are in the chain. The data is already synced; just needs UI work.
- **No "guard counter" yet.** Per `avatar-combat.md` §2 TBD, a heavy
  press against a blocking opponent should crack their guard. That's
  technically a follow-up — Tier D ships the heavy attack itself, but
  the "guard counter" interaction (heavy bypasses block damage
  reduction) is not wired. Add a `bypass_block: bool` to AttackData
  if/when designers want it.
- **`AbilityCross` HUD label updates** to read the new `light_attack`
  binding. If the player rebinds the action in the input map, the HUD
  picks up the new key automatically — no code change needed.
- **The `try_riposte` / `_pending_riposte_target` meta path** uses a
  non-rollback meta to pass the victim into RiposteAttackerState's
  enter() — same-tick so the meta is read before any rollback resim.
  If the riposte trigger races a rollback boundary, the worst case is
  a fall-through to plain HeavyAttackState (the meta isn't set on the
  resim), which is a graceful degradation rather than a crash.
- **Forced RiposteVictimState transition is host-authoritative.** Same
  pattern as ForcedRecovery → ParryRecoilState. Clients see the victim
  state via `state_properties` sync; their `is_ripostable = false`
  flips on the next tick after the host's transition propagates. There
  is a brief window (~1 tick at 30Hz) where a second peer's heavy press
  could trigger a redundant riposte; both would resolve into the
  victim's RiposteVictimState because that state is locked, but the
  damage would double-apply on the host. If that proves problematic,
  add an `is_ripostable` reset *inside* `try_riposte` host-side via
  RPC. Not a Tier D scope concern; flag for Tier F PvP polish.
