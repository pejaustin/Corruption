# Avatar Combat

**Build status:** Partial — core loop playable, depth + feedback layers TBD. See [Status by System](#status-by-system).

The Avatar is the player's third-person presence in the world: a shared vessel that overlords claim from the tower. Combat goal is **deliberate, commitment-based melee** that survives 4-way PvP. This doc is the single source of truth for what's built, what's planned, and how the pieces fit together.

Cross-references: [Action Gating](../technical/action-gating.md) · [Attack Hitboxes](../technical/attack-hitboxes.md) · [Hurtboxes](../technical/hurtboxes.md) · [Netfox Reference](../technical/netfox-reference.md) · [Faction Design](faction-design.md) · [Progression / Loot](progression-loot.md)

---

## Design Pillars

1. **Commitment over reaction.** Swings have wind-up and recovery. You read your opponent and choose; you don't mash.
2. **Telegraph + counterplay.** Every dangerous action is readable. Power comes with a window.
3. **Asymmetry inside a shared core.** All four factions share the same input verbs and frame timings. Variation lives in abilities, stats, and faction-flavored modifiers — not in fighting-game-tier matchup spaghetti.
4. **Rollback-friendly by construction.** Every system designed against the [netfox constraints](../technical/netfox-reference.md). No animation-finished signals for damage; no delta accumulators for state durations; no per-frame-only state.
5. **PvP-first.** No system relies on enemies being scripted — boss/PvE counterplay is downstream of the PvP-safe core.

## Reference Frame

| Game | What we take | What we don't |
|---|---|---|
| Dark Souls 1–3 | Stamina-gated commitment, i-frame roll, weapon-as-moveset | Long recovery on heavies (PvP-hostile) |
| Sekiro | Posture meter as second health bar, parry-centric reads | Block-as-default (we want choice between block and dodge) |
| Elden Ring | Jump attack, guard counter, charged R2 | Ash-of-Art per-weapon abilities (we use faction abilities instead) |
| Bloodborne | Aggression rewarded, dodge-cancels, gun-parry analog | Rally health (overcomplicates PvP) |
| Monster Hunter | Per-region hurtbox damage, animation-driven hitboxes | Locked attack chains (too restrictive) |
| DMC / Bayonetta | Visual feedback on connect, hitstop | Cancel-everything style meter (breaks reads in PvP) |

---

## Status by System

| System | Status | Where it lives |
|---|---|---|
| Attacks (single swing) | Done | `scenes/actors/player/states/attack_state.gd` |
| Attack hitbox profiles | Done | `scripts/combat/attack_hitbox.gd` |
| Per-region hurtboxes | Done | `scripts/combat/hurtbox.gd` |
| Action gating (lock/immune) | Done | `docs/technical/action-gating.md` |
| Input buffering | Done | `scripts/avatar_input.gd` (12-tick window) |
| Roll dodge + i-frames | Done | `scenes/actors/player/states/roll_state.gd` |
| Stagger / hitstun | Done | `StaggerState`, `Actor.try_stagger` |
| Abilities (3 slots, cooldown) | Done | `scripts/avatar_abilities.gd` + `data/abilities/*.tres` |
| Animation pipeline | Done | `docs/technical/3d-asset-pipeline.md` |
| Rollback netcode | Done | `RollbackSynchronizer` on Avatar |
| Death / takeover transfer | Done | `scenes/actors/player/avatar/avatar_actor.gd` |
| Light/Heavy split | Done — needs `light_*`, `heavy_*` clips | `scenes/actors/player/states/light_attack_state.gd`, `heavy_attack_state.gd` |
| Combo strings | Done — needs `light_1/2/3` clips with combo-window method tracks | `scenes/actors/player/states/light_attack_state.gd` (`combo_step` state_property) |
| Charge attack | Done — needs `heavy_charge_loop` / `heavy_charge_release` clips | `scenes/actors/player/states/charge_windup_state.gd`, `charge_release_state.gd` |
| Sprint attack / jump attack | Done — needs `sprint_attack` / `jump_attack` clips | `scenes/actors/player/states/sprint_attack_state.gd`, `jump_attack_state.gd` |
| Block | Done — needs `block_*` clips | `scenes/actors/player/states/block_state.gd` |
| Parry | Done — needs `parry_flash` / `parry_recoil` clips | `scenes/actors/actor.gd:take_damage` + `scripts/combat/forced_recovery.gd` |
| Backstep | Done — needs `backstep` clip | `scenes/actors/player/states/backstep_state.gd` |
| Stamina meter | TBD (deferred per design pillar §3) | — |
| Posture meter (Sekiro-style) | Done — HUD bar wired into AvatarHUD | `scenes/actors/actor.gd:gain_posture/_decay_posture`, `scenes/ui/posture_bar.tscn` |
| Posture-broken state | Done — needs `posture_broken` clip | `scenes/actors/states/posture_broken_state.gd` |
| Lock-on / target tracking | Done (hard-lock + cycle); soft-lock plumbed but disabled | `scripts/combat/targeting.gd`, `scripts/avatar_camera.gd:_tick_lock_follow`, `scenes/ui/lock_on_reticle.tscn` |
| Strafe locomotion (target-relative basis) | Done — needs strafe clips for full feel | `scenes/actors/player/states/move_state.gd` |
| Directional roll | Done — needs `roll_back/_left/_right` clips | `scenes/actors/player/states/roll_state.gd` |
| Camera shake / FOV punch | Done | `scripts/avatar_camera.gd:shake()` + attack/avatar hookups |
| Hitstop | Done | `Actor.hitstop_until_tick` state-prop; freezes `AnimationPlayer.speed_scale` per tick |
| Hit FX (particles, sound) | Partial — code only, asset wiring pending | `scripts/combat/hit_fx.gd` + `scenes/vfx/hit_spark_*.tscn`; sound deferred |
| Damage numbers | Done | `scripts/ui/damage_numbers.gd` autoload + `scenes/ui/damage_number.tscn` |
| Knockback / launch | TBD | — |
| Critical / weak-point hits | TBD (hurtbox supports it) | — |
| Faction-specific movesets | Asset-only (state machine is library-agnostic; see tier-e-implementation.md) | `scripts/faction_profile.gd:animation_library_name` |
| Faction asymmetry — stats on FactionProfile | Done | `scripts/faction_profile.gd:30-87`, `data/factions/*.tres` |
| Faction passive resource | Done | `scripts/faction_passive.gd`, `scripts/faction_passive_*.gd`, `data/factions/passives/*.tres` |
| Slot-4 ultimate (charge-gated) | Done — needs HUD slot + per-faction VFX | `scripts/avatar_abilities.gd:SLOT_ULTIMATE`, `data/abilities/ultimate_*.tres` |
| `ultimate_charge: int` state_property | Done | `scenes/actors/actor.gd:75`, `scenes/actors/player/player_actor.tscn:30` |
| Resource economy (`GameState.corruption_power`) | Done — DORMANT (cost=0 on shipped abilities) | `scripts/game_state.gd:36-46`, `scripts/avatar_ability.gd:cost,cost_resource` |
| Riposte / execution | Done — needs `riposte_attacker` / `riposte_victim` paired clips | `scenes/actors/player/states/riposte_attacker_state.gd`, `scenes/actors/states/riposte_victim_state.gd` |
| Downed / last-stand | TBD | — |

---

## Core Loop (target feel)

> *Spacing → telegraph → commit → punish or be punished.*

A typical engagement looks like:

1. **Approach** — sprint or walk, mind your stamina (TBD). Camera tracks soft-lock target if any (TBD).
2. **Telegraph read** — opponent winds up. You can: dodge through, block (TBD), parry the active frame (TBD), or trade with hyper-armor frames on your own swing (animation-gated).
3. **Punish window** — on whiff or after a parry, opponent has recovery you can hit through. A successful punish should be ~30–40% of opponent HP, not chip damage.
4. **Posture pressure** — repeated blocks/parries fill posture (TBD); a posture break opens an execution / riposte window (TBD) — large damage, brief vulnerability for the attacker.
5. **Ability inflection** — once per cooldown, an ability changes the math: lifesteal, AoE, stealth, etc. Abilities are *not* the main damage source — they're punctuation.

Engagements should resolve in ~3–6 exchanges, not 30. Faster than Dark Souls, slower than fighting games. Closer to Sekiro's pace.

---

## 1. Attacks

**Current:** Single uncancellable swing committed on press. Damage window is `hitbox_start_ratio` → `hitbox_end_ratio` (defaults 0.25–0.6). Damage = `actor.get_attack_damage()` × ability multiplier × per-profile multiplier × per-hurtbox multiplier. Server polls `hitbox.get_new_hits()` each tick; clients see damage via dual-write RPC.

**TBD:**

- **Light vs Heavy** — separate inputs, separate animations, separate stamina cost (when stamina lands). Heavy is slower wind-up, more damage, often staggers if not stagger-immune.
- **Combo string** — pressing light again during a "combo window" near the end of a swing chains into a follow-up. Three-hit cap, last hit always heaviest. Buffered presses already supported by input buffer.
- **Charge attack** — hold heavy to charge, release for stronger hit. Visible body pose at full charge. Cancellable into roll (cost: lose charge).
- **Sprint attack** — light/heavy while sprinting plays a different animation; commits the sprint into the swing. Closes distance.
- **Jump attack** — attack while airborne plays an overhead. Hits ground targets. Modest stagger immunity on landing frame so you trade up against held attacks.
- **Riposte / execution** — context-sensitive heavy on a posture-broken or staggered enemy. Long animation, full i-frames, big damage, locks the victim.

**Design questions:**

- Combo windows authored on the animation (method tracks) vs. timed in script? **Lean: animation tracks** — consistent with existing `lock_action` / hitbox approach.
- Do combos branch (light → heavy → light vs light → light → heavy)? **Lean: no branches**, one canonical 3-hit string per faction. Keeps the read space small.
- Recovery-cancel into block? Into roll only? **Lean: roll only**, block needs its own commitment.

---

## 2. Defense

**Current:** Roll only. 0.4s (12 ticks @ 30Hz). `stagger_immune = true` for the full duration → blanket i-frames. Roll is uninterruptible (empty `cancel_whitelist`).

**TBD:**

- **Block** — hold a button to enter `BlockState`. Reduces incoming damage (e.g. 70%), refunds stagger to a posture meter. Costs stamina per hit. Breaks at posture-zero.
- **Parry** — tap-block within a small active window (~6 ticks) deflects the incoming attack: attacker takes a posture hit and a brief recovery. Visual flash + audio cue.
- **Perfect dodge** — last 2 frames of the i-frame window granting a damage buff or stamina refund (DMC-style "Royal Guard"). Optional polish.
- **Backstep** — directional input + roll = quick i-frame backstep with shorter distance. For spacing.
- **Guard break** — heavy attack against a blocking opponent staggers them through the block. Counter to block-spam.

**Design questions:**

- Directional block (face the right way) or omnidirectional? **Lean: omnidirectional facing-cone**, ~120° front. Souls-style.
- I-frames on block startup? **Lean: no.** Block has to lose to mix-ups.
- Parry as a separate input or "tap-block"? **Lean: tap-block** — fewer buttons, established convention.

---

## 3. Stamina

**Current:** Not implemented. Movement, attacks, and roll are unlimited.

**Proposed:**

- Single pool (e.g. 100). Regenerates after a short idle window (~0.5s after last action).
- Costs: roll ~25, light ~15, heavy ~25, sprint drains over time, block consumes per damage absorbed.
- At 0 stamina: no roll, no attack, sprint cancels. Block converts to a "weak block" that lets full damage through.

**Alternative — skip stamina (Sekiro path):**

Replace stamina with the **posture meter** (see §4). Sprint and roll are free; attacks are gated by commitment alone. Trades a familiar Souls verb for a tighter pace.

**Recommendation:** start without stamina; add the posture meter first. If fights feel mash-y, slot stamina in afterward. Less code is less rollback risk.

---

## 4. Posture / Poise

**Current:** Static `stagger_immune` flag set by animation method tracks. No meter; no accumulation. `MinionActor.stagger_invulnerable` exists as a coarser bypass for boss-style fights.

**Proposed (Sekiro-style):**

- Per-actor posture meter (e.g. 100). Fills on:
  - Successful block (proportional to incoming damage)
  - Parried recoil (less)
  - Heavy hits taken
- Meter drains during idle.
- At full meter: actor is **posture-broken** — forced into a short stagger animation, vulnerable to riposte.

**Why a meter, not Souls poise:**

In 4-way PvP, hidden HP-tied poise creates feel-bad reads ("did my hit poise-break or not?"). A visible meter telegraphs intent: "I am one block away from breaking, I should disengage."

**Sync:** meter is a `state_property` on the avatar (rollback-synced). Increments on damage application, ticks down per `_rollback_tick`.

---

## 5. Hit Reaction & Feedback

**Current:** None. Successful hits play the attack's existing animation; the target enters StaggerState if not immune; that's it. No screen feedback, no sound, no particles, no numbers.

**TBD (in priority order — biggest feel uplift first):**

1. **Hitstop** — on every successful damage application, freeze the attacker's animation for 3–6 frames. Synced via a one-shot `hitstop_until_tick` state property so rollback handles it. Single biggest "game feels good" lever.
2. **Hit particles** — small spark/blood burst at the hitbox point on connect. Cosmetic-only (skip during rollback resimulation).
3. **Hit sounds** — per-weapon-class impact sounds, layered with material (flesh / armor / shield).
4. **Camera shake** — small punch on hit dealt, larger on hit received. Only on the *hit-feeling* peer (don't sync — it's local feedback).
5. **Hit-flash** — brief shader pulse on the hurtbox-owning model (white/red flash). Cheap and very legible.
6. **Damage numbers** — opt-in HUD floater. Useful in debug; arguably ship-worthy in a PvP arena game (telegraphs ability strength).
7. **Killing-blow flourish** — slight slowdown + camera punch on a kill. Cheap drama.

**All of this is local-only feedback** — never gates damage or rollback. If a peer rewinds past a hitstop, the audio/particle is just a stale presentation glitch and resyncs on the next tick.

---

## 6. Lock-on / Targeting

**Current:** Free 3rd-person camera (`scripts/avatar_camera.gd`). No reticle, no soft-lock, no target tracking.

**Proposed:**

- **Soft-lock** by default — small assist on the camera and on movement direction toward the nearest enemy in front. Always on, subtle.
- **Hard-lock** on a button press — locks camera to a target, binds movement to a target-relative basis (strafe + circle). Same button cycles to next target with right-stick / mouse-wheel input.
- **Target loss conditions:** target dies, leaves max range (~25m), occluded for >0.5s, manual cancel.
- **PvP rule:** lock-on always available, but *only* the locker's camera is affected. The target receives no cue (no "you are being locked-on" indicator) — fits the deception/dark-lord theme. Open question: should overlords' War Table see a peer's locked target as a hint? Probably yes, info-warfare vibes.

**Why this matters for combat math:** several other systems collapse if there's no notion of "the enemy I am fighting" — riposte targeting, parry direction, lock-strafing animations. Lock-on is a prerequisite for §1 (riposte) and §2 (directional parry) reaching their full form.

---

## 7. Damage Model

**Current:**

- Flat damage: `actor.get_attack_damage() * ability_mult * hitbox_profile_mult * hurtbox_profile_mult`.
- StaggerState 0.5s default, configurable per actor.
- Hurtbox profiles support per-region multipliers but no actors currently wire `Head` / `Torso` / `Legs` profiles.
- No knockback. Velocity unchanged on hit.

**TBD:**

- **Critical / weak-point hits** — wire a `Head` hurtbox profile per Avatar model with `&"Head" : 1.5`. Existing infrastructure already supports it; just needs scene-level setup.
- **Knockback / launch** — heavy attacks impart velocity on the victim. Distinct from stagger (animation lock) — a knockback just shoves. Synced via the existing `velocity` state_property.
- **Damage types** — physical / fire / corruption / divine. Per-faction abilities already trend this way; codifying it lets armor/resistance work later. Currently implicit.
- **Resistance / armor** — flat reduction or % reduction per damage type. Per-actor; per-Avatar-faction adjustable. Held off until armor/loot is real.
- **Friendly fire** — currently *enabled* between Avatar and same-faction minions (host-authoritative `take_damage` doesn't filter by faction). Decide deliberately: enabled adds chaos to 4-way PvP, disabled simplifies aiming. **Lean: enabled** — we are dark lords.
- **DOT / status** — bleed, poison, burn. Built on existing `take_damage` + a per-target ticker. Lean on AbilityEffect framework — DOTs are just timed effects scenes.

---

## 8. Movement in Combat

**Current:** Walk, run, jump, fall, roll. Roll has full i-frames.

**TBD:**

- **Directional roll** — currently rolls in input direction; fine. But want a `BackstepState` distinct from a forward roll (shorter distance, longer recovery, similar i-frames).
- **Sprint cancels** — sprint into roll: free. Sprint into attack: see §1 sprint attack.
- **Roll cancel chains** — roll into roll without recovery? **Lean: no.** Recovery between rolls is part of stamina pressure (when stamina exists).
- **Slide / vault** — under low cover, over fences. Probably never. Costs animation work.
- **Climb** — never.

---

## 9. Camera

**Current:** Third-person orbit, mouse + right-stick, fixed offset.

**TBD:**

- Lock-on integration (§6).
- **Hit camera punch** — small FOV bump or shake on landing/receiving heavy hits.
- **Recovery framing** — wider FOV during recovery from a big hit so player sees what's coming.
- **Auto-rotate behind** — on sprint, smoothly orient camera behind the avatar. Fight against motion sickness in chase scenarios.
- **Wall-collision smoothing** — already a Godot `SpringArm3D` problem; verify the existing camera handles it.

---

## 10. Abilities

**Current:** 3 slots (Secondary Ability, Item 1, Item 2). `AbilityData` resource (`id`, `display_name`, `cooldown`, `effect_scene`). Activation flow: input → RPC to host → cooldown check → RPC `_do_activate` → spawn `AbilityEffect` scene as child → `effect.activate(actor)`. AvatarAbilities aggregates queries (damage mult, lifesteal, invisible, channeling) across active effects. See `data/abilities/*.tres` for the current catalog.

**TBD:**

- **Resource cost beyond cooldown** — per-faction resource (e.g. corruption power) gated on map sites or kills. Currently abilities are just cooldown-gated, which means infinite over a long fight.
- **Ability upgrades** — currently `UpgradeData` only buffs minion HP / damage etc. An ability-upgrade tier (longer Hellfire, lifesteal % up) is missing.
- **Slot 4 — ultimate** — long cooldown, decisive ability per faction. Charges via combat (kills, damage taken).
- **Per-ability animation slot** — currently abilities likely play the avatar's idle/move; want a dedicated `AbilityState` (in fact `ChannelState` exists, see `scripts/states/movement/`) wired to specific abilities for windup feel.

---

## 11. Faction Asymmetry

| Faction | Avatar identity | Combat lever |
|---|---|---|
| Undeath | Medium combat, attrition | Lifesteal on hit (built — `life_drain`) and/or trickle regen out of combat |
| Demonic | Strongest combat, aggressive | Highest base damage, shorter cooldowns, heavier hyper-armor windows |
| Nature/Fey | Weak combat, evasive | Camouflage, faster roll, longer i-frames, mobility kit |
| Eldritch | Weakest combat, utility | Ritual / debuff abilities, shorter cooldowns at HP cost |

**TBD design choice:**

- **Same moveset, different stats** — cheap. One animation set; tune `attack_damage`, `roll_distance`, ability roster.
- **Same moveset, faction-modified swing** — medium. Same animations, but ability/passive modifies frame data or adds an effect (e.g. Demonic's heavy gets +1 hit, Fey's swings throw a vine).
- **Different moveset per faction** — expensive. Separate animation sets, separate state tuning.

**Lean: Tier 1 ships "same moveset, different stats + ability roster"**, then upgrade to per-faction swing modifiers if PvP feels samey. Avoid full moveset divergence unless playtests demand it.

---

## 12. Networking

**Current:** Avatar state, transform, hp, input, camera basis are rollback-synced. Damage uses dual-write (host applies + RPC to controlling peer). Authority transfers with the controlling peer via `set_multiplayer_authority`. See [netfox-reference](../technical/netfox-reference.md).

**TBD:**

- **Hitstop sync** — needs a `hitstop_until_tick` state property so rollback resimulates the animation freeze deterministically.
- **Posture meter** — state property when added.
- **Knockback velocity** — already in the synced `velocity` state property; just needs the application code to set it host-side.
- **Lock-on target** — *not* state-synced; it's purely camera/local. If "overlord sees who you're locked onto" becomes a feature, sync at low rate (e.g. every 10 ticks) — not rollback-critical.
- **Anti-cheat surface** — damage, ability cooldown, hp are all host-authoritative; clients can spoof input but can't fabricate damage. Adequate for indie PvP.

---

## 13. PvP-Specific Concerns

- **1vN combat math.** Three opponents at once shouldn't be a guaranteed loss for the Avatar. Mitigations: i-frame roll already breaks crowd damage; an ability that hits multiple targets per faction; commitment penalty on the *attackers* (one swings, others can't all swing simultaneously without trading).
- **Hostile takeover edge cases.** Avatar dies mid-attack: the swing's animation finishes locally on the killing tick, but the avatar is now controlled by the killer's owner. Verify the `RewindableStateMachine` re-enters cleanly and there's no orphaned hitbox active. Test case for the war-table harness when extended.
- **Hide-and-spam ability.** Eldritch ability spam from cover is a likely degenerate strategy. Counter: ability cooldowns long enough that you can't sustain ranged poke. Possibly cooldowns *increase* outside line-of-sight to a minion (information-warfare flavor — abilities want eyes).
- **Lock-on in 4-way.** If A locks B, and C engages A, lock-on shouldn't make A oblivious to C. Camera must still allow free look while soft-locked; hard-lock should release on damage taken from outside the locked direction.
- **Anti-camp.** Avatar respawns at a fixed origin (`Vector3(0.1, 0.04, -0.06)`). If everyone camps spawn, fight is over. Mitigation: brief respawn invuln (~2s) and/or random respawn within tower zones.

---

## 14. Boss / PvE Counterplay

Bosses (Guardian, Corrupted Seraph) are downstream of the Avatar's verbs. New Avatar capabilities → new boss design space:

- Once parry exists, bosses gain parryable attacks (telegraphed with audio + visual).
- Once posture exists, bosses have a posture meter — execute on break.
- Once charge exists, charge-canceling boss windups gives a high-skill option.

Boss telegraph design lives in [boss-mechanics.md](boss-mechanics.md); changes there should be staged after the corresponding Avatar verb lands.

---

## 15. Death / Respawn

**Current:** Death triggers transfer. Killer attribution: minion → minion's owner takes the Avatar; else highest influence; else round-robin. Respawn at fixed origin, full HP, IdleState. See `avatar_actor.gd:59–98`.

**TBD:**

- **Downed state** — brief window before death where teammates' minions can revive (or the controlling peer can spend a resource to self-revive). Adds drama, smooths bad luck. Probably faction-flavored: Undeath self-revives, Demonic doesn't.
- **Respawn delay** — currently instant. A 3–5s delay gives the new owner time to orient.
- **Respawn invuln** — see anti-camp above.
- **Last-stand mode** — at <10% HP, brief damage / speed buff. Souls-in-PvP risk; might cut.

---

## Roadmap

Tiered the same way as `docs/technical/build-phases.md`. Each tier should leave the game in a playable state.

### Tier A — Feel pass *(ship first; lowest risk, highest perceived uplift)*

- Hitstop on damage application (host-authoritative, syncs via state property)
- Hit-flash shader on hurtbox owner
- Hit particles + impact sounds (local-only)
- Camera shake on hit dealt/received
- Damage numbers (debug overlay first; promote to HUD later)

### Tier B — Targeting pass

- Soft-lock camera assist
- Hard-lock state with target cycling
- Target-relative movement (strafe / circle)
- Lock-aware roll directionality

### Tier C — Defense pass

- BlockState (hold to guard, omnidirectional front cone)
- Parry window (tap-block early frames)
- Backstep variant of roll
- Posture meter (visible HUD bar) — fills on block/parry, drains over time
- Posture-break stagger window

### Tier D — Attack depth pass

- Light/Heavy split (distinct inputs, animations, frame data)
- 2–3 hit combo string per faction
- Charge heavy
- Sprint attack, jump attack
- Riposte / execution on broken posture or back-attack

### Tier E — Faction asymmetry

- Per-faction stat tuning (HP, damage, roll distance, attack speed)
- Faction-modified swing effects (Demonic +1 hit, Fey throws vine, etc.)
- Faction-specific ultimate (slot 4)
- Ability resource economy beyond cooldown

### Tier F — PvP polish

- Respawn invuln + delay
- Anti-camp spawn variation
- Friendly fire decision finalized
- High-latency mitigations (verify dual-write damage holds at 200+ ms)
- Hostile-takeover edge-case testing in war-table harness

### Tier G — PvE depth (after PvP feels right)

- Boss telegraph rework with parry/posture integration
- Critical / weak-point hurtbox profiles wired per actor
- Status / DOT effects (bleed, burn, corruption stack)

---

## Per-Tier Systems Work

Implementation slices for each [roadmap](#roadmap) tier — what scripts, state_properties, scenes, inputs, and data resources need to land. Italicized **Risk** lines flag the architecture choices worth thinking about before writing code, not just clerical work.

### Tier A — Feel pass

Goal: every successful hit feels like a hit.

| Work | Where |
|---|---|
| `hitstop_until_tick: int` state_property | `PlayerActor`, `MinionActor` (host sets in `take_damage`) |
| Pause animation while `NetworkTime.tick < hitstop_until_tick` | `Actor._on_display_state_changed` / `_rollback_tick` |
| Hit-FX spawner helper | new `scripts/combat/hit_fx.gd` — spawns spark + sound at contact point |
| Hit spark scenes | new `scenes/vfx/hit_spark_flesh.tscn`, `_armor.tscn`, `_shield.tscn` |
| Hit-flash shader uniform | extend existing model material; `hit_flash_intensity` ticked locally |
| Camera shake API | extend `scripts/avatar_camera.gd` with `shake(amplitude, duration)`; ticked local-only |
| Damage signal + number floater | `Actor` emits `took_damage(amount, source)`; new `scripts/ui/damage_numbers.gd` autoload subscribes |
| Reaction-variety wiring | StaggerState picks `hit_react_light` vs `hit_react_heavy` from incoming damage |
| Footstep / roll-dust / land-dust hooks | animation method tracks call a `_spawn_dust(StringName)` forwarder on Actor |

*Risk:* hitstop must be authoritative + rollback-synced or rewinds will desync the "pause." Local FX (sparks, shake, dust) must be **rollback-skip**: gate by `if NetworkRollback.is_resimulating(): return` so resimulation doesn't stack particles.

---

### Tier B — Targeting pass

Goal: the camera knows what fight you're in.

| Work | Where |
|---|---|
| `Targeting` component | new `scripts/combat/targeting.gd`, child of `AvatarActor` |
| `current_target: Actor` (local-only, not synced) | on `Targeting` |
| Soft-target picker | `find_best_target(forward_dir, max_angle, max_range)` — scored by angle + distance |
| Hard-target cycle | `cycle_target(direction: int)` left/right; fallbacks when off-screen |
| Lock-on input | new `toggle_lock` action; right-stick click / middle-mouse |
| Camera follow-target mode | extend `scripts/avatar_camera.gd` with `look_at_target` mode and a damped chase |
| Reticle scene | new `scenes/ui/lock_on_reticle.tscn` — billboarded sprite anchored to target chest bone |
| Strafe locomotion | `MoveState` reads `targeting.is_locked` and switches to strafe animation set + target-relative movement basis |
| Roll directionality | `RollState` reads input direction in target-relative basis when locked; picks `roll_back` / `roll_left` / etc. |
| Target-loss rules | `Targeting._tick`: drop on death, occlusion >0.5s, range >25m, manual cancel, hit from behind (hard-lock only) |

*Risk:* the only feature with **no rollback footprint** in this whole roadmap — target is purely camera/local. Resist the urge to sync; let info-warfare doc decide later if overlords get to see who you've locked.

---

### Tier C — Defense pass

Goal: defense is a real choice, not a get-out-of-jail roll.

| Work | Where |
|---|---|
| `BlockState` | new `scenes/actors/player/states/block_state.gd` — held button, front-cone facing check |
| `BackstepState` | new `scenes/actors/player/states/backstep_state.gd` — variant of RollState |
| `PostureBrokenState` | new — long stagger, marked ripostable |
| `posture: int` state_property | `PlayerActor`, `MinionActor` |
| `max_posture: int`, `posture_decay_per_tick: float` | `Actor` exports |
| Posture accumulation in `take_damage` | full hit +small, blocked hit +medium, parried hit +large *on attacker* |
| Posture decay tick | `_rollback_tick` on Actor when not in combat |
| Posture HUD bar | new `scenes/ui/posture_bar.tscn` |
| Block facing check | `Actor.is_blocking_against(source_pos) -> bool` (dot product vs front cone, e.g. ±60°) |
| Block damage reduction | `take_damage` consults `is_blocking_against` and scales damage (e.g. ×0.3) |
| Parry window | `BlockState._enter_tick + PARRY_WINDOW_TICKS` (~6 ticks); attacker forced into extended recovery on parry |
| Parry effect on attacker | new `scripts/combat/forced_recovery.gd` — sets `action_locked = true` on attacker for N ticks via authority RPC |
| `block` input | new action; new `parry_input` if separated, otherwise a tap-vs-hold check on block |

*Risk:* parry causality across peers is the hard one. Tap-block lands on parrier's tick T; attack hit registered host-side on tick T+N (because of input delay). Must reconcile authoritatively: host sees "did parrier press block during my swing's parry-window-relative-to-active-start?" The cleanest approach is to record the parrier's `block_press_tick` as a state_property and let the attacker's hitbox-application logic on the host check that window.

---

### Tier D — Attack depth pass

Goal: you have a moveset, not a single button.

| Work | Where |
|---|---|
| Split `AttackState` | into `LightAttackState`, `HeavyAttackState`, `SprintAttackState`, `JumpAttackState` |
| Charge states | `ChargeWindupState` (held) → `ChargeReleaseState` (release-driven, picks anim by `charge_level`) |
| Riposte pair | `RiposteAttackerState` + `RiposteVictimState` (position-snapped, paired animations) |
| `combo_step: int` state_property | `PlayerActor` — 0/1/2; reset on idle/take-damage/timeout |
| `charge_start_tick: int` state_property | `PlayerActor` |
| Combo window method tracks | animation calls `_combo_window_open()` / `_combo_window_close()` on Actor |
| Buffered chain consumption | LightAttackState reads buffered light input during open window → transitions to next combo step |
| Heavy-attack input | new `heavy_attack` action; renames existing `primary_ability` → `light_attack` |
| Riposte trigger | heavy press near posture-broken target within range + facing → forces both states |
| Per-attack stat block | extend each Attack*State with exported `damage_mult`, `posture_damage`, `hitbox_start_ratio`, `hitbox_end_ratio`, `hyper_armor_start/end` |
| Sprint-attack entry | `MoveState`: light/heavy press while sprinting → SprintAttackState (skip normal attack) |
| Jump-attack entry | `JumpState`/`FallState`: attack press → JumpAttackState |

*Risk:* deciding whether to keep stats on the state scripts (current pattern, pragmatic) vs. extracting an `AttackData` Resource per swing (cleaner, balance-CSV-friendly via the new `balance_csv.gd`). **Lean: extract `AttackData`.tres once we have ≥3 attacks per faction**; it pays for itself when the balance CSV pipeline lights up. Until then, stay on state-export.

Also worth pausing on: are sprint/jump attacks *separate states* or *modifiers* on LightAttackState that pick a different animation? Separate states are clearer; modifiers are less code. **Lean: separate states** because each has unique entry/exit conditions and movement integration.

---

### Tier E — Faction asymmetry

Goal: factions feel mechanically different without forking the entire combat code.

| Work | Where |
|---|---|
| Combat stats on `FactionProfile` | extend resource: `avatar_hp`, `avatar_base_damage`, `attack_speed_mult`, `roll_distance`, `roll_iframe_ticks`, `max_posture` |
| Avatar applies faction stats on claim | `AvatarActor._on_controller_changed` reads `FactionData.get_profile(faction)` and applies |
| `FactionPassive` resource | new `scripts/faction_passive.gd` — hooks `on_attack_connect(actor, target, hit_info)`, `on_take_damage(actor, amount)`, `on_kill(actor, target)` |
| Per-faction passive .tres | `data/factions/passives/*.tres` — Demonic add-hit, Fey vine bleed, Eldritch every-3rd-debuff, Undeath sustain |
| Ability ultimate (slot 4) | extend `AvatarAbilities` to 4 slots; charge-gated rather than cooldown-gated |
| `ultimate_charge: int` state_property | `PlayerActor`; incremented on kills, damage taken |
| Resource economy | `GameState.corruption_power[peer_id]` (or per-faction-named) — replenished by territory/kills |
| Ability cost extension | optional `cost: int` + `cost_resource: StringName` on `AvatarAbility`; activation gated |
| Per-archetype moveset (if pursued) | new animation library + scene-level wiring; no new code if state machine already covers verbs |

*Risk:* **avoid building a deep ability-cost/resource system before playtesting whether long cooldowns alone are enough.** This tier has the most temptation to overdesign. Ship faction stats + passives first; revisit resource costs only if 1v1 ability spam is a real problem.

---

### Tier F — PvP polish

Goal: the 4-way doesn't break in degenerate ways.

| Work | Where |
|---|---|
| `respawn_invuln_until_tick` state_property | `PlayerActor` — `take_damage` no-ops while set |
| Respawn delay | `_respawn` schedules transition to IdleState N ticks later; could route via existing `DeathState` exit timing |
| Spawn-point picker | `RESPAWN_POSITION` → `Array[Vector3]`; pick the one farthest from any alive opponent |
| FF filter | `Actor.damage_filter(attacker, victim) -> bool`; default same-peer-same-faction = false; configurable per match |
| Lag tolerance audit | exercise dual-write damage at 200/400ms simulated latency in the war-table harness |
| Hostile-takeover edge tests | new harness scenarios in `scenes/test/` — Avatar dies mid-attack, mid-roll, mid-charge, mid-riposte |
| Anti-degen: out-of-LOS cooldown | optional `KnowledgeManager`-aware cooldown extension for Eldritch ranged-poke abilities |

*Risk:* the FF rule is a *gameplay* decision dressed as a code change. Decide it explicitly with playtest data, then code; don't pick a default and hope.

---

### Tier G — PvE depth

Goal: bosses aren't just a damage-sponge wall.

| Work | Where |
|---|---|
| `TelegraphIndicator` cosmetic | new `scenes/vfx/telegraph_arc.tscn` — visible warning before boss active frames |
| Per-region hurtboxes wired on every actor | scene work — three `CollisionShape3D`s under each `Hurtbox`, `profile_damage = { Head: 1.5, Legs: 0.75 }` |
| `StatusEffect` resource | new `scripts/combat/status_effect.gd` — `apply(actor)`, `tick(actor, delta)`, `expire(actor)` |
| Per-status .tres | `data/status/{bleed,burn,corruption,...}.tres` |
| `StatusController` component | new node child of Actor — owns `Array[StatusEffect]`, ticks each, removes expired |
| Status sync | `active_status_ids: PackedStringArray` state_property + per-status `_enter_tick` latch; effect data is constant, so syncing IDs + start ticks is enough |
| Boss parry/posture integration | once parry exists (Tier C), bosses gain `parryable` flag on specific attacks; posture meter applies as normal |
| Per-attack damage type | adds `damage_type: StringName` on AttackData (or attack state); StatusController and resistance reads it |

*Risk:* `StatusController` as a generic system is the right abstraction once there are ≥3 status effects. Resist building it for the first one — bleed alone can live on a one-off effect scene. Promote to the generic system on the second status that needs it.

---

### Cross-tier infrastructure (build alongside whichever tier hits it first)

A few systems aren't tier-specific — they get incrementally extended as tiers land:

- **`AttackData` resource** — one `.tres` per swing, exported via `balance_csv.gd`. Deferred from Tier D's per-state-export approach. Becomes valuable around the 3-attacks-per-faction mark.
- **`Actor.damage_filter`** — gate point for FF, friendly-status-immunity, ally-buff-target rules. Built minimally in Tier F; Tier G adds damage-type resistance reads through it.
- **`RollbackVfxGate`** helper — `if NetworkRollback.is_resimulating(): return` is needed in dozens of FX call sites. One helper avoids per-site forgetting.
- **HUD coordinator** — Tiers A (damage numbers), B (reticle), C (posture bar), E (ultimate charge meter) all add HUD layers. Probably worth a `HUDManager` autoload by Tier C to keep z-order and animation states sane.

---

## Open Questions

- **Stamina vs no-stamina.** Default lean: ship without; revisit after Tier C if combat feels mash-y.
- **Lock-on visibility to opponents.** Hidden (deception flavor) vs visible (counterplay). Lean: hidden, but optionally surfaced through the War Table to overlords as info warfare.
- **Friendly fire.** Lean: on. Confirm in playtests.
- **Avatar progression persistence across transfers.** GDD-era question. Lean: progression is *per-faction*, stored on `GameState` indexed by `peer_id`, so the avatar itself is a stateless vessel and the controlling peer's faction-tier carries over.
- **Loot interaction.** See [progression-loot.md](progression-loot.md). Avatar combat doesn't currently care about loot; if held items become stat-bearing, that doc owns the reconciliation.
- **Combo branching.** Lean: no, single canonical 3-hit string. Revisit only if movesets diverge enough that branching adds clarity rather than cognitive load.

---

## Asset Checklist

Concrete list of art / animation / audio / VFX work needed to support every system in this doc. Tier markers (`[A]`–`[G]`) refer to the [roadmap](#roadmap) — assets without a marker are required for the existing Tier-0 core. *Need-by-tier ≠ "must commission today"*; it's a sequencing hint.

### Animations (per Avatar model)

Animation names follow the existing `<library>/<clip>` convention from the [3D asset pipeline](../technical/3d-asset-pipeline.md). All clips need root-motion off (movement is delta-driven), Z-forward, and a visible attack arc that crosses the AttackHitbox volume between the labeled active-start / active-end keys.

**Locomotion** *(have most of this; verify each Avatar model carries it)*

- `idle` — looping, neutral combat pose (slight weapon-up bias)
- `walk_forward`, `walk_back`, `walk_left`, `walk_right` — strafe set, looping
- `run_forward`, `run_back`, `run_left`, `run_right` — same set, faster
- `sprint` — straight-ahead only, looping
- `turn_left_90`, `turn_right_90`, `turn_180` — in-place, optional polish

**Air / traversal**

- `jump_start`, `jump_loop`, `jump_land` — split clips, not one
- `fall_loop` — long airtime
- `land_heavy` — for >2m drops, brief recovery

**Defense**

- `roll_forward` (have); `roll_back`, `roll_left`, `roll_right` — directional set `[B/C]`
- `backstep` — short i-frame retreat `[C]`
- `block_enter`, `block_loop`, `block_hit_light`, `block_hit_heavy`, `block_break` `[C]`
- `parry_flash` — small upper-body deflect, one-shot `[C]`

**Offense (light moveset)** *(have one swing; need full string)*

- `light_1`, `light_2`, `light_3` — combo string, each clip ends in a "combo window" tail `[D]`
- `heavy` — slow, big arc `[D]`
- `heavy_charge_loop` — held-charge pose `[D]`
- `heavy_charge_release` — explosive release `[D]`
- `sprint_attack` — running plunge / shoulder-charge `[D]`
- `jump_attack` — overhead from air, plays into landing recovery `[D]`

**Reactions**

- `hit_react_light`, `hit_react_heavy` — currently one StaggerState animation; want two `[A]`
- `hit_react_knockback` — pushed back several meters `[D]`
- `posture_broken` — unbalanced loopable, plays during execution window `[C]`
- `riposte_attacker` + `riposte_victim` — paired animations, root positions matter `[D]`
- `death` — generic; faction-flavored variant later `[E]`

**Channel / ability**

- `channel_loop` — used by current `ChannelState`
- One per ability with a unique pose: at minimum `cast_quick`, `cast_held`, `cast_heavy` so AbilityEffect scenes can pick

### Weapon archetypes

Weapons aren't formalized in code yet. Treat this as the **target taxonomy** when factions get distinct movesets `[E]`. Each archetype is one moveset (light combo + heavy + sprint/jump variants) plus its own VFX kit. Pick archetypes per faction; multiple factions can share an archetype with reskins.

| Archetype | Suggested faction | Reach | Distinguishing feature |
|---|---|---|---|
| One-handed sword | (default / Undeath) | medium | Balanced; baseline frame data |
| Two-handed greatweapon | Demonic | long | Slow, hyper-armor on heavies, big posture damage |
| Paired daggers | Nature/Fey | short | Fast string, weak posture, mobility cancels |
| Polearm / scythe | Undeath alt | long | Sweeping arcs, hits multiple targets |
| Staff / focus | Eldritch | short | Weak melee, but ability-amped — most swings dispense effects |

For each archetype you commit to, you owe:

- **A.** A moveset of animations from the offense list above (light_1–3, heavy, sprint_attack, jump_attack, charge_loop, charge_release).
- **B.** A weapon-trail particle system, weapon-specific impact VFX, weapon-specific whoosh + impact SFX.
- **C.** A weapon mesh authored with a `weapon_grip` socket / bone matching the avatar's hand bone, plus an `AttackHitbox` shape/profile sized to the weapon's reach.

### Particle effects (VFX)

Cosmetic-only; never gates damage. All effect scenes live under `scenes/abilities/` (existing) or a new `scenes/vfx/` for non-ability cosmetics.

| FX | When | Tier |
|---|---|---|
| Hit spark — flesh | Damage applied, victim has flesh hurtbox tag | `[A]` |
| Hit spark — armor | Same, armor tag | `[A]` |
| Hit spark — shield | Block absorbs damage | `[C]` |
| Weapon trail | Active window of any swing; per archetype | `[A]` for default, `[E]` per archetype |
| Charge buildup glow | Heavy charge_loop; intensifies to release | `[D]` |
| Parry flash | On successful parry; on both attacker (deflected) and parrier (success) | `[C]` |
| Posture break burst | Posture meter hits max; large, audible | `[C]` |
| Riposte impact | On riposte connection — bigger than a normal hit | `[D]` |
| Roll dust puff | Roll start; surface-tinted | `[A]` |
| Footstep dust | Per-step, surface-tinted, sprint only initially | `[A]` |
| Land dust | jump_land, scaled by fall distance | `[A]` |
| Damage-type FX overlay | Fire, corruption, nature, divine — applied on the hit-spark color/particles | `[F]` |
| Death dissolve | Per-faction flavor (rot, ash, leaves, voidscape) | `[E]` |
| Hit-flash shader | Brief white/red pulse on hurtbox-owner mesh | `[A]` |

### Sound effects (SFX)

| Sound | When | Tier |
|---|---|---|
| Footstep × surface (4 surfaces × 2 paces) | Walk/run loops | `[A]` |
| Cloth roll / dodge whoosh | Roll, backstep | `[A]` |
| Weapon whoosh × archetype | Active window of swings | `[A]` for default |
| Impact × material × damage type | Damage applied | `[A]` for flesh + physical, `[F]` for full grid |
| Block clang | Damage absorbed by block | `[C]` |
| Parry ding | Successful parry, distinct from clang | `[C]` |
| Stagger grunt | Enter StaggerState | `[A]` |
| Posture-break growl | Posture meter break | `[C]` |
| Charge whir | Heavy charge_loop | `[D]` |
| Riposte stab | Riposte connection | `[D]` |
| Death sound | Per-faction | `[E]` |
| Ability casts | One per ability — most exist via effect scenes; audit gaps |  |

### Models / Meshes

- **Avatar base mesh** — one shared rig today; split per-faction visuals when art bandwidth allows `[E]`. Bones the combat code touches: `RightHand` / `weapon_grip` (AttackHitbox parent), `Spine` / `Chest` (Hurtbox center), `Head` (Head hurtbox profile, when wired). Match bone names across faction skins so scenes don't fork.
- **Weapon meshes** — per archetype. Authored with the grip oriented for `weapon_grip` socket. Include an LOD (or a low-tri version) for distant overlords watching from the war table.
- **Hurtbox profile shapes** — three `CollisionShape3D`s under `Hurtbox`: `Head` (small sphere), `Torso` (capsule), `Legs` (capsule). Wire `profile_damage = { &"Head": 1.5, &"Legs": 0.75 }` per Avatar model `[F]`. Currently single-shape; the multi-profile machinery is already in place ([hurtboxes.md](../technical/hurtboxes.md)).

### HUD / UI assets

- Health bar — exists in some form; verify per-Avatar styling
- Stamina bar `[B/C]` — only if stamina ships
- Posture bar `[C]` — Sekiro-style; bigger than stamina, top-center placement candidate
- Lock-on reticle `[B]` — small targeting glyph anchored to locked target's chest bone
- Cooldown ring × 3 (or 4 if ultimate ships) — already partially in HUD; verify ability icons present
- Damage number floater `[A]` — debug-toggle first, opt-in HUD later
- Hit-direction indicator (red arc when hit from off-screen) `[F]` — anti-camera-loss, helpful in 1vN

### Per-animation method-track checklist

When authoring a new offensive animation (or editing an existing one), add these AnimationPlayer method-call tracks. Frame numbers are illustrative; actual timing comes from the animator. See [action-gating](../technical/action-gating.md) for the full contract.

| Frame | Method | Why |
|---|---|---|
| active-start | `lock_action` | Commit to the swing — only `cancel_whitelist` (Roll) breaks it |
| active-start | `enable_stagger_immunity` | Hyper-armor through the active window (if desired) |
| active-start | `%AttackHitbox.enable(<profile>)` | Open damage window |
| active-start | VFX spawn — weapon trail on, charge release burst, etc. | Cosmetic |
| active-start | SFX — whoosh, charge release | Cosmetic |
| active-end | `%AttackHitbox.disable` | Close damage window |
| active-end | `disable_stagger_immunity` | Drop hyper-armor |
| active-end | `unlock_action` | Recovery is cancellable |
| recovery-mid | (combo systems `[D]`) `_combo_window_open` | Buffered next-attack press chains; placeholder name |
| recovery-end | (combo systems `[D]`) `_combo_window_close` | Buffer expires for this swing |

If a method key is missed, `lock_action` and `stagger_immune` self-clear on next state entry — but missing a `%AttackHitbox.disable` will leave the hitbox active across the recovery and into the next state. **Always pair enable with disable in the same animation.**

### Authoring order (suggested)

If you're sitting down to make assets and want to maximize "the game feels better tomorrow":

1. Hit-flash shader + hit spark particle + flesh impact SFX → wire into existing AttackState (Tier A starts paying off immediately).
2. Footstep dust + roll dust + sprint whoosh → locomotion finally has texture.
3. Two reaction animations (`hit_react_light`, `hit_react_heavy`) so StaggerState reads as variable severity.
4. Block animation set + block clang SFX → unlocks Tier C work.
5. Light combo string (`light_1`/`2`/`3`) — biggest combat-depth unlock for the same animator-hour budget.

Skip per-archetype movesets until at least one faction has a fully-built combat loop you've playtested.

---

## Appendix: Where the verbs are wired

| Verb | Input | State | Files |
|---|---|---|---|
| Move | WASD / left stick | `MoveState` | `scenes/actors/player/states/move_state.gd` |
| Sprint | `run` held | `MoveState` (modifier) | same |
| Jump | `jump` press | `JumpState` → `FallState` | `jump_state.gd`, `fall_state.gd` |
| Roll | `roll` press (buffered) | `RollState` | `roll_state.gd` |
| Attack | `primary_ability` press (buffered) | `AttackState` | `attack_state.gd` |
| Channel ability | varies | `ChannelState` | `channel_state.gd` |
| Ability slot 1–3 | secondary / item1 / item2 | spawn `AbilityEffect` scene | `scripts/avatar_abilities.gd` |
| Take damage | external | → `try_stagger` → `StaggerState` | `actor.gd`, `stagger_state.gd` |
| Die | hp ≤ 0 | `DeathState` → transfer | `avatar_actor.gd:59` |

When adding a new verb (block, charge, riposte, parry, ...), follow the existing pattern: a new state file under `scenes/actors/player/states/`, registered in the `RewindableStateMachine`, with input gathered in `avatar_input.gd` and damage / immunity routed through `try_transition` / `try_stagger`. See [action-gating.md](../technical/action-gating.md) for the contract.
