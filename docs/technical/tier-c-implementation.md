# Tier C — Defense Pass: Implementation Notes

Code-side roadmap for the [avatar-combat.md Tier C](../systems/avatar-combat.md#tier-c--defense-pass)
defense pass. Every system in the table below is plumbed; none requires art
to function. Where art is expected (block clips, parry flash, posture-break
animation, hit-spark variants), the system runs as a stub with a documented
swap-in point.

**Architectural note:** Posture and the parry-causality reconciliation are
the only two new netfox-touching surfaces in this tier. Everything else
(reticle? no — that was Tier B; backstep, posture decay, posture HUD) is
purely state-machine or local UI work. The `block_press_tick` state_property
is the single mechanism that lets the host on tick T+N reconcile a parrier's
press from tick T deterministically — see § Parry causality below.

---

## Status

| System | Code | Asset hookup | File(s) |
|---|---|---|---|
| `BlockState` (held guard, front-cone) | Done | Author `block_enter` / `block_loop` clips | `scenes/actors/player/states/block_state.gd` |
| `BackstepState` (block-and-roll variant) | Done | Author `backstep` clip | `scenes/actors/player/states/backstep_state.gd` |
| `PostureBrokenState` (long stagger, ripostable) | Done | Author `posture_broken` clip | `scenes/actors/states/posture_broken_state.gd` |
| `ParryRecoilState` (forced attacker recovery) | Done | Author `parry_recoil` clip | `scenes/actors/states/parry_recoil_state.gd` |
| `posture: int` state_property | Done | n/a | `scenes/actors/actor.gd:90`, `scenes/actors/player/player_actor.tscn:30` |
| `posture_break_tick: int` state_property | Done | n/a | `scenes/actors/actor.gd:102`, `scenes/actors/player/player_actor.tscn:30` |
| `block_press_tick: int` state_property | Done | n/a | `scenes/actors/actor.gd:112`, `scenes/actors/player/player_actor.tscn:30` |
| `max_posture` / `posture_decay_per_tick` exports | Done | Tune per actor in inspector | `scenes/actors/actor.gd:80,84` |
| Posture accumulation in `take_damage` | Done — block ×3, hit ×1, parry attacker ×30 | n/a | `scenes/actors/actor.gd:178-216` |
| Posture decay (idle drain) | Done | n/a | `scenes/actors/actor.gd:_decay_posture` |
| `Actor.is_blocking_against(source_pos)` | Done | n/a | `scenes/actors/actor.gd:is_blocking_against` |
| `Actor.damage_reduction_against(source)` | Done — multiplier hook for Tier E faction wards | n/a | `scenes/actors/actor.gd:damage_reduction_against` |
| `Actor.gain_posture(amount)` | Done — host-authoritative break trigger | n/a | `scenes/actors/actor.gd:gain_posture` |
| `is_ripostable` flag (local) | Done — set by PostureBrokenState entry/exit | n/a | `scenes/actors/states/posture_broken_state.gd:enter,exit` |
| Parry window (`PARRY_WINDOW_TICKS = 6`) | Done — host checks at hit-application | n/a | `scenes/actors/actor.gd:take_damage` |
| `ForcedRecovery.apply(attacker)` | Done — transitions attacker into ParryRecoilState | n/a | `scripts/combat/forced_recovery.gd` |
| `block` input action | Done — F (keyboard), LB (gamepad button 4) | n/a | `project.godot:[input]` |
| Avatar input wiring | Done — `block_input` held flag + buffered press | n/a | `scripts/avatar_input.gd` |
| `Actor.took_damage` source propagation | Done — Tier B's `_on_owner_took_damage` now sees real attackers | n/a | `scenes/actors/actor.gd:took_damage emit` |
| `take_damage(amount, source)` callsite update | Done across player/minion AttackState, ability AoE, boss, harness | n/a | grep `take_damage(` |
| Block damage reduction × 0.3 | Done | n/a | `scenes/actors/actor.gd:BLOCK_DAMAGE_REDUCTION` |
| Posture HUD bar | Done — bound under `AvatarHUD` | Style colour / placement tweakable | `scenes/ui/posture_bar.tscn`, `scripts/ui/posture_bar.gd` |
| Posture sync on minions | Done — piggybacks on existing `_sync_minion_actor` RPC | n/a | `scripts/minion_manager.gd:_sync_all_minions`, `scenes/actors/minion/minion_actor.gd:sync_from_server` |
| `parried` / `posture_broken` signals | Done — local FX hooks | Wire VFX + SFX on listeners | `scenes/actors/actor.gd:12,15` |

`avatar-combat.md` has the system-level "Status by System" table; this file
is the file-level cross-reference.

---

## What works without art

You can plug Tier C into the existing avatar today and see all of:

- Press F (or LB on a gamepad) to enter `BlockState`. The avatar slows to a
  guarded stand. Animation falls back to the stagger clip until the
  `block_*` clips land.
- Take a swing from a minion / second avatar that's in front of you while
  blocking → damage scaled by 0.3 (70% reduction), posture meter on the
  HUD ticks up by 12 per blocked hit.
- Take a swing from behind while blocking → full damage; posture ticks up
  by 4 (the "you weren't actually facing" path).
- Tap-block (release within ~200 ms / 6 ticks) just as a hit is about to
  land → parry: zero damage to victim, attacker is shoved into
  `ParryRecoilState` for ~0.6 s, attacker takes a +30 posture spike. The
  `parried` signal fires on both actors for VFX/SFX hooks.
- Hold block under sustained damage → posture climbs to max → avatar
  enters `PostureBrokenState`, stays uninterruptible for ~1 s
  (`POSTURE_BROKEN_DURATION_TICKS = 30`), then auto-recovers to
  `IdleState`. While in PostureBrokenState, `is_ripostable = true` is set
  on the actor — Tier D's heavy-attack-vs-broken-target logic will read
  this.
- Hold F + press C (roll) → BackstepState fires instead of normal roll —
  shorter retreat distance, briefer i-frames (6 ticks vs roll's full 12),
  longer total recovery (14 ticks).
- Posture decays at `posture_decay_per_tick` (default 0.5/tick) when no
  damage has landed in the last `POSTURE_DECAY_GRACE_TICKS = 60` ticks
  (~2 s). While in BlockState or PostureBrokenState, decay is paused so
  the meter stays visible during sustained pressure.

What does NOT work yet (art-gated):

- `block_enter`, `block_loop`, `block_hit_light`, `block_hit_heavy`,
  `block_break` clips — without them, BlockState plays the configured
  stagger fallback and visually looks identical to a stunned actor.
- `backstep` clip — without it, BackstepState plays the existing crouch
  fallback (the same clip RollState uses).
- `posture_broken` clip — without it, PostureBrokenState falls back to
  the stagger animation. Same fallback for ParryRecoilState if
  `parry_recoil` isn't authored.
- `parry_flash` VFX scene — there is no `&"shield"` hit_spark wired into
  the parry path yet. Tier A already ships a `hit_spark_shield.tscn`
  stub; calling `HitFx.spawn(&"shield", ...)` from a `parried` signal
  listener is the canonical hook.
- Block clang / parry ding SFX — audio is still deferred (Tier A's
  follow-up). When `_spawn_sfx` lands, BlockState and the parry path are
  the right hook sites.

---

## Asset plug-in instructions

### Defense animation clips

`BlockState`, `BackstepState`, `PostureBrokenState`, and `ParryRecoilState`
each look up a clip name relative to the library prefix in their configured
`animation_name`. They fall back silently to the configured clip if the
named variant is missing.

| State | Looked-up clip | Fallback if missing |
|---|---|---|
| `BlockState` (initial) | `<library>/block_enter` | configured `animation_name` (currently `large-male/Stagger`) |
| `BlockState` (sustained) | `<library>/block_loop` | configured `animation_name` |
| `BackstepState` | `<library>/backstep` | configured `animation_name` (currently `large-male/Crouch`) |
| `PostureBrokenState` | `<library>/posture_broken` | configured `animation_name` (currently `large-male/Stagger`) |
| `ParryRecoilState` | `<library>/parry_recoil` | configured `animation_name` (currently `large-male/Stagger`) |

To author the variants: open the model's animation library
(`assets/characters/avatar/avatar.glb` → import → animations) and add new
clips with the matching names. The state machine picks them up the moment
they appear — no script changes needed.

To swap the fallback (e.g. give BackstepState a different placeholder),
edit the `animation_name` export on the state node in `player_actor.tscn`.

### Hit-spark `&"shield"` variant on blocked hits

Tier A ships `scenes/vfx/hit_spark_shield.tscn` and registers it in
`HitFx.SCENES[&"shield"]`. Tier C does NOT auto-spawn it on blocked hits;
the hookup is a follow-up.

To wire: in a script that listens to `Actor.took_damage` (or
`Actor.parried`), check whether the hit was blocked / parried (today, the
victim's `_state_machine.state == &"BlockState"` is a fine proxy) and
call `HitFx.spawn(&"shield", contact_point, victim)`. Owner is per
project taste — VFX is local-only, gate the same way Tier A does:

```gdscript
if NetworkRollback.is_rollback():
    return
if controlling_peer_id != multiplayer.get_unique_id():
    return  # only on the parrier's screen
HitFx.spawn(&"shield", hurtbox.global_position, self)
```

### Parry flash VFX

`scenes/vfx/parry_flash.tscn` is **not** authored yet. When it lands,
spawn it from a `parried` listener on either side. Suggested placement:

- On the parrier: small upper-body deflect arc (matches `parry_flash`
  animation). Anchored to the parrier's chest hurtbox.
- On the attacker: a sharper "your weapon was knocked aside" pulse at
  the active hitbox position when the parry fired. Anchored to the
  attacker's `%AttackHitbox`.

Until that scene exists, the parry effect is purely mechanical (zero
damage + ParryRecoilState) — visible because the attacker rebounds, but
without the satisfying flash.

### Posture-break VFX / SFX

The `posture_broken` signal fires on the actor whose meter just maxed.
Local-only consumer guidance:

- Spawn a brief "shock burst" VFX at the actor's chest. Suggested:
  `scenes/vfx/posture_break_burst.tscn` (not authored).
- Trigger a low-frequency growl SFX (`posture_break_growl`).
- Play a brief screen flash on the affected peer's camera if it's the
  controlling avatar (the parrier already gets the cue from their swing,
  the broken-actor peer benefits from a "you got pushed too far" beat).

### Posture HUD styling

`scenes/ui/posture_bar.tscn` uses a vanilla `ProgressBar` modulated to a
warm orange (`Color(0.95, 0.55, 0.15, 1)`) so it visually contrasts the
yellow `HealthBar` directly above it (anchored bottom-center, 24 px above
the health bar). Pulse near break uses a warmer red (`Color(1.0, 0.4,
0.2, 1)`) at 4 Hz.

To restyle: open `posture_bar.tscn`, swap the `ProgressBar`'s `theme_*`
properties or its surface texture. The script-side colours
(`RESTING_COLOR`, `PULSE_NEAR_BREAK_COLOR`) are constants in
`posture_bar.gd` — edit there to retune the pulse curve.

To move it: edit the `offset_top` / `offset_left` on the root `Control`
in the `.tscn`. Default places the bar bottom-centered; move it to
top-center to match Sekiro convention if preferred.

---

## Parry causality (the load-bearing diagram)

This was the hard one called out in the per-tier work table. The fix:
record the parrier's press tick as a `state_property`, let the host on a
later tick consult it.

```
parrier (peer A)                  host (peer 1)                  attacker (peer B)
─────────────────                 ──────────────                  ────────────────

T  press F                        ─                              ─
   BlockState.enter
   actor.block_press_tick = T   ──→   (state_property syncs)
                                                                 (clients receive
                                                                  block_press_tick = T)

T+N (host's hit lands)            ─                              T+N: swing connects
                                  attack_state.gd:_handle_hits
                                    hurtbox.get_actor() = parrier
                                    parrier.take_damage(dmg, attacker)
                                      is_blocking_against(attacker.pos) = true
                                      since_press = T+N - T ≤ PARRY_WINDOW_TICKS?
                                        yes → parry: dmg = 0
                                              attacker.gain_posture(+30)
                                              ForcedRecovery.apply(attacker)
                                                → attacker._state_machine.transition(ParryRecoilState)
                                  (state_property syncs)         attacker enters
                                                                 ParryRecoilState locally
                                                                 because state is in
                                                                 state_properties
```

What makes this rollback-safe:

- `block_press_tick` is in `RollbackSynchronizer.state_properties` on
  PlayerActor. Host and clients carry the same value when resimulating.
- The state machine's `state` is also in `state_properties`. Host's
  decision "transition the attacker into ParryRecoilState" gets
  resimulated identically on every peer.
- The parry's local-only effects (zero damage, posture spike, VFX) are
  all expressible as deterministic functions of the synced values.
- `parried.emit(...)` on both sides is gated by `_is_resimulating()`
  inside `Actor.take_damage`, so resims don't double-fire FX.

What it does NOT cover (limitations):

- A parry off the dual-write `incoming_damage` path doesn't fire — the
  legacy `apply_incoming_damage` RPC carries `source_peer: int`, not
  `source: Node`. That leg always passes `null` source into
  `take_damage`, which falls through the source-known branch in
  `actor.gd:188` and resolves as plain damage. In practice this means
  minion-on-avatar hits are NOT blockable / parryable in Tier C. Player
  swings against minions or other avatars (the
  `attack_state.gd:_handle_hits` leg) DO carry the source actor and DO
  resolve correctly.
- To unblock the dual-write leg, extend `apply_incoming_damage` to
  carry the source peer's avatar reference (not the peer id) by
  resolving it on the receiving end via `GameState.avatar_peer_id` or
  similar. Deferred — minion-attacker block isn't gameplay-critical
  yet, and the parser fix is one helper.

---

## How to test

The defense pass is avatar-side, but the existing `scenes/test/war_table_test.tscn`
harness only carries an Overlord. To exercise Block / Parry / Posture-break
end-to-end, you need either:

- A live lobby (host + ≥1 client) where one peer has claimed the Avatar
  via the tower scene, or
- A new `scenes/test/avatar_combat_test.tscn` harness analogous to the war-
  table one — instances a real `AvatarActor` plus a few hostile
  `MinionActor`s. Not authored as part of Tier C; deferred to whoever
  iterates next on the avatar feel pass.

The test cases below assume a live lobby with the avatar claimed; in a
single-peer harness, the dual-write damage path may not behave
identically (see "Known limitations" — minion→avatar block doesn't fire
yet, by design).

### Block reduces damage

1. Boot host + one client. Have the client claim the Avatar.
2. Spawn a hostile minion close enough to attack you (debug pause-menu
   button, or a starting-minion spec).
3. Hold **F** as the minion attacks. Per "Known limitations" the
   reduction won't fire on this leg yet (sourceless dual-write). For a
   guaranteed-source test, walk into a second avatar and let them
   attack you with LMB while you hold F.
4. The damage applied should be 30% of the unblocked amount; the
   posture bar (bottom-center) ticks up by 12 per blocked hit.

### Tap-block parry

1. Same setup. Have a second avatar swing at you with LMB.
2. **Tap F** (press and release within ~200 ms) just before the hit
   connects.
3. Successful parry: zero damage applied, the swinging avatar enters
   ParryRecoilState for ~0.6 s, the swinger's posture bar gets +30.
4. Check the console — the `parried` signal fires on both actors.

If F is pressed >6 ticks before the hit lands or the press tick is
>6 ticks behind the hit-application tick, the hit resolves as a normal
block instead. Tune `PARRY_WINDOW_TICKS` in `scenes/actors/actor.gd`
if the window feels wrong.

### Posture break

1. Same setup. Hold F continuously while a second avatar swings at
   you several times.
2. After ~9 blocked hits (12 × 9 = 108, just over the `max_posture =
   100` cap), the avatar enters PostureBrokenState.
3. While in PostureBrokenState, the avatar is uninterruptible, plays
   the broken animation (or stagger fallback), and `is_ripostable =
   true`. After 30 ticks (~1 s) it auto-recovers to IdleState.
4. Verify state visually + via the debug overlay's actor-state readout
   (F3 toggles the overlay).

### Backstep

1. With the Avatar claimed and on the ground:
2. Hold **F** and press **C** (roll).
3. Avatar performs a BackstepState — short retreat away from the
   camera-forward direction (or away from the locked target if hard-
   locked onto something), shorter distance and longer recovery than
   a normal roll. The i-frame window cuts off after 6 ticks; the
   recovery tail is unprotected.
4. Release F before pressing C → normal roll fires (RollState).

### Tier B's behind-attack lock-break (free correctness win)

This was plumbed in Tier B but dormant because Tier A's `took_damage`
emit always passed `null` source. Tier C now propagates the actual
attacker through. To verify:

1. Lock onto a minion in front of you (middle mouse).
2. Have a *different* minion attack you from behind.
3. The hard-lock drops the moment the behind-attack lands (per
   `Targeting.HARD_LOCK_BREAK_BEHIND_DEG`).

This is the side-effect Tier B's doc predicted — verify it as a free
correctness win once Tier C lands. (Caveat: this currently requires
the attacker to be a player swing, not a minion swing, because
minion→avatar damage uses the source-stripping `apply_incoming_damage`
RPC — same limitation as block / parry on minion hits.)

### Posture HUD pulse

In a quick smoke test (any scene where the avatar HUD is visible):

1. Stand still long enough for posture to drain to 0.
2. Take a single unblocked hit (4 posture). The bar should display
   the 4-posture sliver in resting orange.
3. Trigger sustained damage so posture climbs within 5 of max — the
   bar should pulse at 4 Hz between resting orange and warm red.

---

## Known limitations / followups

- **Riposte attack is Tier D's job.** PostureBrokenState sets
  `is_ripostable = true` on the actor; there is no system reading it
  yet. When Tier D adds the heavy-attack-vs-broken-target logic, that
  reader closes the loop. No changes needed in Tier C's code.
- **Stamina is intentionally absent.** Per `avatar-combat.md` §3, we
  ship posture without stamina and revisit only if combat feels too
  free. BlockState has no stamina cost; you can hold guard
  indefinitely, only posture pressure breaks you.
- **Block animation falls back to the stagger clip** (configured on
  the BlockState node in `player_actor.tscn`). It's visually wrong but
  the state itself is correct. Same fallback for PostureBrokenState
  and ParryRecoilState. Author the named clips when art bandwidth
  allows.
- **Parry SFX/VFX are documented but not authored.** See "Asset plug-in"
  for hook sites. The mechanical parry works without them; the
  feedback feels thin until the flash + ding land.
- **Minion-attack-on-avatar block doesn't fire** because the dual-write
  damage path passes `null` source. See "Parry causality" — fix when
  `apply_incoming_damage` is extended to carry the actor reference.
  Workaround for testing: swap to a second-avatar harness (lobby +
  two clients) where avatar-on-avatar hits route through the source-
  carrying path.
- **Posture sync on minions is rate-limited to 10 Hz** because the
  existing `_sync_all_minions` RPC fires at that cadence. Clients see
  posture values up to 100 ms stale. Acceptable for a meter; tighten
  the rate (or add a one-shot `notify_posture(id, value)` RPC) if
  designers complain.
- **Posture does not decay on minions.** `Actor._rollback_tick` is
  invoked only by the rollback loop, which PlayerActor opts into;
  MinionActor's `_physics_process` calls
  `_state_machine._rollback_tick` directly without first running
  Actor's hook. Minion posture stays where it was set until they take
  more hits or die. To enable minion posture decay, MinionActor's
  `_physics_process` should call `_decay_posture()` on host before
  the state machine tick. Deferred — minion-as-victim posture is not a
  Tier C scope concern (Tier D's riposte targeting reads the broken
  state directly, no decay required).
- **`gain_posture` only triggers a break when the state machine
  carries `PostureBrokenState`.** Plain MinionActors based on
  `actor.tscn` (no posture state) cap their posture silently. To make
  a specific minion ripostable, drop the state into its scene's
  `RewindableStateMachine` (and ParryRecoilState if you want it to
  parry too). Boss riposte is a deliberate Tier D follow-up.
- **`damage_reduction_against` is the hook for Tier E faction wards
  and Tier G damage-type resistances.** Currently only used for the
  block reduction. Subtypes can override it for ability-driven
  defense (e.g. Eldritch invulnerable phase, Undeath partial null).
- **Posture-bar placement is opinionated.** Bottom-center, 24 px above
  the health bar. Sekiro puts posture top-center on the target — if
  we add a "selected target" HUD later (Tier B's reticle is the
  starting point), surfacing the target's posture there is a
  follow-up.
- **HUD is bound under `AvatarHUD`.** Both Avatar and Overlord
  scenes use distinct HUDs; the OverlordHUD does NOT receive a
  posture bar (overlords are not melee combatants). When the
  overlord first-person body gains its own posture (Tier E faction
  passive?), copy `posture_bar.tscn` into `OverlordHUD` and bind to
  the overlord actor.
- **Block facing test ignores Y axis.** Jumping over a low attacker
  doesn't break the block cone. This is intentional — vertical
  defense against low/high attacks is not a Tier C concern. Boss
  AoE pillar attacks etc. should configure `is_blocking_against`
  per-attack via overriding `damage_reduction_against` if Tier G
  needs vertical separation.
- **`ForcedRecovery.apply` uses an actor `meta` to pass the duration**
  rather than a parameter on the state itself. Meta is local-only;
  clients use `RECOVERY_TICKS_DEFAULT` on resim. The duration is
  cosmetic (the state syncs as state_property), so this is fine.
  If a future caller wants to cache the duration into a synced
  property, add it as a state_property on Actor and read in
  ParryRecoilState.enter.
