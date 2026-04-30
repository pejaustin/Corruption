# Tier F — PvP Polish: Implementation Notes

Code-side roadmap for the [avatar-combat.md Tier F](../systems/avatar-combat.md#tier-f--pvp-polish)
PvP polish pass. Every system in the table below ships behind a default that
preserves Tiers A–E behavior — flip the relevant flag (or set the relevant
per-ability export) to opt new content into the new gate.

**Architectural notes:**

- **`respawn_invuln_until_tick` is a state_property on PlayerActor.** Set
  host-side by `AvatarActor._apply_respawn`; checked at the top of
  `Actor.take_damage`. Rollback resimulation reproduces the no-op
  deterministically.
- **`DamageFilter.allow` is a static helper, not a method on Actor.** It's
  consulted in two places: the unified `Actor.take_damage` gate (catches
  attacker-known paths — avatar swings, minion swings carrying `actor` as
  source, ability AoEs) and the minion-vs-avatar dual-write in
  `scenes/actors/minion/states/attack_state.gd` (the `incoming_damage` leg
  loses the source ref by the time `_rollback_tick` drains it, so we filter
  before writing). Per-callsite duplication is intentional — the dual-write
  is the only place where the source-attribution drops.
- **Friendly-fire flag lives on `GameState` as a `static var`.** Pattern
  borrowed from `KnowledgeManager.INFINITE_BROADCAST_RANGE` /
  `INSTANT_COMMANDS` — runtime-mutable so the pause-menu Debug button (and
  test harnesses) can flip without restart. Host writes via
  `GameState.toggle_friendly_fire` → broadcasts via `_set_friendly_fire` RPC.
- **Respawn flow split into two phases.** `_respawn` (RPC, fires immediately
  on death-transfer) only schedules a host-side timer; `_do_respawn` runs
  after `RESPAWN_DELAY_TICKS * NetworkTime.ticktime` seconds and computes
  the spawn position from the live opponent set, then RPCs `_apply_respawn`
  to teleport + restore HP + grant invuln on every peer at the same tick.
- **`RESPAWN_POSITIONS: Array[Vector3]` ships with placeholder anchors.** The
  array currently carries the legacy origin plus three offset candidates so
  the picker has options to choose between. Designers should replace these
  with map-authored Marker3D positions per tower; that's a content task,
  not a code change.
- **Anti-degen LOS extension is OPT-IN per ability.** No shipped ability
  sets `requires_los = true`. The simple raycast implementation lives on
  `AvatarAbilities._has_hostile_los`; a `KnowledgeManager`-aware version
  (using each peer's `WorldModel` belief instead of physics raycast) is a
  documented follow-up.

---

## Status

| System | Code | Asset hookup | File(s) |
|---|---|---|---|
| `respawn_invuln_until_tick` state_property | Done | n/a | `scenes/actors/actor.gd:respawn_invuln_until_tick`, `scenes/actors/player/player_actor.tscn` (state_properties array) |
| Respawn invuln gate in `take_damage` | Done | n/a | `scenes/actors/actor.gd:take_damage` |
| `RESPAWN_INVULN_TICKS` const (60 ticks ≈ 2s) | Done | Tune by editing const | `scenes/actors/actor.gd:RESPAWN_INVULN_TICKS` |
| Respawn delay (90 ticks ≈ 3s) | Done | n/a | `scenes/actors/player/avatar/avatar_actor.gd:RESPAWN_DELAY_TICKS,_respawn,_do_respawn` |
| `RESPAWN_POSITIONS` candidate array | Done | Designers replace with map-authored anchors | `scenes/actors/player/avatar/avatar_actor.gd:RESPAWN_POSITIONS` |
| `_pick_respawn_position` (max-min-distance to opponents) | Done | n/a | `scenes/actors/player/avatar/avatar_actor.gd:_pick_respawn_position` |
| `_apply_respawn` RPC | Done — teleport + HP restore + invuln + Idle transition | n/a | `scenes/actors/player/avatar/avatar_actor.gd:_apply_respawn` |
| `DamageFilter.allow` static helper | Done | n/a | `scripts/combat/damage_filter.gd` |
| FF gate in `Actor.take_damage` | Done | n/a | `scenes/actors/actor.gd:take_damage` |
| FF gate in minion attack dual-write | Done | n/a | `scenes/actors/minion/states/attack_state.gd:_check_hits` |
| `GameState.friendly_fire_enabled` (static var, default true) | Done | Flip via debug menu or test harness | `scripts/game_state.gd:friendly_fire_enabled` |
| `GameState.toggle_friendly_fire` / `set_friendly_fire` / `_set_friendly_fire` RPC | Done | n/a | `scripts/game_state.gd` |
| `friendly_fire_changed` signal | Done | HUD listeners can subscribe | `scripts/game_state.gd:friendly_fire_changed` |
| `DebugManager.toggle_friendly_fire` | Done — host-only | n/a | `scripts/debug_manager.gd:toggle_friendly_fire` |
| Pause-menu "Friendly Fire" button | Done — disabled for clients, label reflects state | Designers can re-style in editor | `scenes/menus/in_game_menu.tscn` (BtnFriendlyFire), `scripts/menus/in_game_menu.gd:_on_friendly_fire_pressed` |
| `AvatarAbility.requires_los` / `los_cooldown_mult` | Done — opt-in, default false / 1.5 | Set on per-ability `.tres` to enable | `scripts/avatar_ability.gd` |
| LOS check in `AvatarAbilities._do_activate` | Done | n/a | `scripts/avatar_abilities.gd:_do_activate,_has_hostile_los` |
| Hostile-takeover edge test harness | Done | n/a | `scenes/test/takeover_edge_test.tscn`, `scripts/test/takeover_edge_test_controller.gd` |
| Lag-tolerance audit checklist | Done — documented below | n/a | This file § Lag-tolerance |

`avatar-combat.md` has the system-level "Status by System" table; this file
is the file-level cross-reference.

---

## What works without art

You can plug Tier F into the existing avatar today and see all of:

- **Respawn delay + invuln.** Kill the avatar (Esc → Debug → Kill Avatar
  on host, or use the takeover-edge harness's `K` hotkey). After the
  hostile-takeover transfer fires, the avatar enters a ~3s pause; a fresh
  controller then claims the body, which spawns at one of the candidate
  positions and is invulnerable for ~2s. Confirm via the harness HUD's
  "Invuln: yes (Nticks)" line.
- **Anti-camp spawn picker.** Position a hostile minion near each candidate
  spawn; kill the avatar. The picker selects the candidate furthest from
  any alive opponent; with one minion in the world, the avatar always
  respawns on the opposite side of the map.
- **FF toggle.** Host opens pause menu, clicks "Friendly Fire: ON" → label
  flips to "Friendly Fire: OFF". Spawn two minions of the same faction +
  same owner; let them attack each other → no damage. Flip back → damage
  resumes. Cross-faction PvP unaffected.
- **LOS cooldown extension (opt-in).** Edit any `data/abilities/*.tres`,
  set `requires_los = true`. Cast the ability while a hostile is in line-
  of-sight → cooldown logs nominal value. Cast while behind cover (no
  hostile visible) → cooldown logs `nominal × los_cooldown_mult` (1.5×
  default).

What does NOT work yet (gameplay-decision-gated):

- **Map-authored spawn anchors.** `RESPAWN_POSITIONS` ships with placeholder
  values around the origin. Replace per-map / per-tower with Marker3D
  positions exported from the world scene; the picker picks from whatever
  array is in the const.
- **`KnowledgeManager`-aware LOS.** Current LOS is a single-frame physics
  raycast. The information-warfare layer (`KnowledgeManager` per-peer
  `WorldModel`) holds richer "did I see this?" state but the LOS gate
  doesn't consult it — it just asks the physics layer "is the line clear
  right now?". Promotion to belief-based LOS is documented as a follow-up.
- **Spawn-point picker doesn't consider minion threat density.** Only
  living `Actor`s in the actors group are scored. Once minion threat
  weighting matters (e.g. respawn far from a swarm even if the avatar's
  own swarm), extend `_pick_respawn_position` with a weighted sum.
- **Last-stand / downed state.** Tier F scope was respawn polish + FF +
  edge-case harness. `Downed / last-stand` is still TBD per the system
  status table.

---

## Asset plug-in instructions

### Spawn-point markers

Designers add `Marker3D` nodes under each tower / map region with a stable
name (e.g. `RespawnAnchor_Undeath`, `RespawnAnchor_Demonic`). Currently the
avatar's `RESPAWN_POSITIONS` is a hard-coded const — promote it to a
`@export var respawn_positions: Array[Vector3]` (or `Array[Marker3D]`) once
the world scene exposes them. Until then, edit the const directly per
tier-F-implementation.md.

### Respawn animation hookup

`DeathState` already plays the actor's death animation on entry; the new
respawn flow doesn't add a dedicated "rising" animation. If designers want
one:

1. Author a `<library>/respawn_rise` clip on each avatar's animation
   library.
2. Add a `RespawnRiseState` extending `ActorState` mirroring `StaggerState`.
3. In `AvatarActor._apply_respawn`, transition to `RespawnRiseState`
   instead of `IdleState`. The state's `tick()` self-exits to `IdleState`
   after the clip finishes.

The current flow (Death → 3s timer → Idle with invuln) is sufficient
without art.

### Friendly-fire visual indicator

When `GameState.friendly_fire_enabled = false`, the avatar HUD should show
a status icon (e.g. shield with a slash). Hook listener:

```gdscript
GameState.friendly_fire_changed.connect(_on_ff_changed)

func _on_ff_changed(enabled: bool) -> void:
    %FfIndicator.visible = not enabled
```

Place the indicator in `avatar_hud.tscn` once art lands.

---

## How to test

### Respawn delay + invuln + spawn picker

1. Open `scenes/test/takeover_edge_test.tscn` in the editor and press F6.
   The harness claims the avatar as peer 1.
2. Press `K` to kill the avatar. Wait ~3 seconds. The avatar should:
   - Stay in `DeathState` for the delay window.
   - Teleport to one of the four `RESPAWN_POSITIONS` candidates.
   - Show "Invuln: yes (Nticks)" in the HUD for ~2s.
   - Have full HP.
3. Spawn an opponent — adjust the harness scene to add a hostile minion at
   a known position (e.g. `Vector3(8, 0, 8)`). Kill the avatar; verify the
   picker chose a candidate further from that position. Run multiple kills
   with the minion at different positions to confirm the picker scores
   correctly.
4. While invuln is active (countdown visible in HUD), have the opponent
   strike the avatar. HP should not change. After the countdown hits zero,
   damage applies normally.

### Friendly-fire toggle

1. In a multi-peer session (or via `DebugManager.add_dummy_player`), spawn
   two avatars (or two same-faction minions of the same owner).
2. Open the pause menu (Esc). Click "Friendly Fire: ON" → it flips to
   "OFF". Console echoes the state on the host.
3. Have the same-faction actors attack each other → no HP change.
4. Flip back → damage resumes.
5. Cross-faction PvP should always work regardless of the toggle.

### Hostile-takeover edge cases

1. Open `scenes/test/takeover_edge_test.tscn` in editor; F6.
2. Run each scenario:
   - **`1` — IdleState kill:** baseline. Verify clean Death → respawn.
   - **`2` — Mid-LightAttack kill:** verify the harness logs `OK:
     AttackHitbox disabled cleanly`. If it logs `WARN: AttackHitbox still
     active after death`, that's an orphaned hitbox bug to fix.
   - **`3` — Mid-Roll kill:** verify after the respawn settles, the avatar
     is in `IdleState` (not Roll). Inspect `_state_machine.state` via the
     remote scene tree.
   - **`4` — Mid-ChargeWindup kill:** the harness logs the
     `charge_start_tick` before the kill. After respawn, verify it's `-1`
     (cleared on respawn via `activate(peer_id)` if the takeover involved
     a different peer — for the harness's same-peer takeover case, a
     manual `_reset` clears it).
   - **`5` — Mid-Riposte kill:** verify the avatar exits cleanly and
     respawn proceeds. If a riposte-victim minion exists, it should also
     exit `RiposteVictimState`.
3. Press `R` between scenarios to reset the avatar to a clean state.
4. Document any anomalies in this file's "Known limitations" section
   below — don't speculatively patch.

### Lag-tolerance audit

The `addons/netfox/extras/network-simulator.gd` simulator can inject
artificial latency. Procedure:

1. Add a `NetworkSimulator` autoload (or as a child of the world scene)
   with `incoming_latency_ms = 200` (or 400).
2. Run a 2-peer session — one host, one client.
3. Trade hits between two avatars: have each peer initiate light combos
   alternately. Verify on each peer's screen:
   - Hitstop pause aligns with the same animation frame on both sides.
   - Parry windows reconcile authoritatively (host decides who parried
     whom; clients re-render).
   - Charge release ticks align — both peers see the explosion at the
     same `NetworkTime.tick`.
   - Respawn delay + invuln are consistent — neither peer can damage the
     other during the invuln window.
4. Increase to 400ms; rerun. Tier A's hitstop, Tier C's parry, Tier D's
   charge are the most sensitive; Tier F's invuln/respawn are the
   least sensitive (host-authoritative timer + state_property propagation).

#### Lag-tolerance checklist

Per `state_property` on the avatar / minion, a one-line note on host vs
client authorship and visible artifacts at high latency:

| State_property | Authority | Observable at 200/400ms |
|---|---|---|
| `:transform` | host (movement) + client (input prediction) | Standard rollback rubberband on contested moves; mitigated by netfox interpolation. |
| `:velocity` | host | Ditto — clients predict; resync within rollback window. |
| `:hp` | host (`take_damage`) | Dual-write RPC + state-prop sync: client sees damage at T (RPC) and re-confirmed at T+latency (state-prop). No artifact in normal play. |
| `:hitstop_until_tick` | host | Animation pause may briefly desync at T then re-align by T+latency. Cosmetic only. |
| `:posture` | host | Posture meter HUD lags by latency; no gameplay impact (parry / break decisions are host-authored). |
| `:posture_break_tick` | host | Latch tick → broken state on entry. Resim-safe. |
| `:block_press_tick` | client (input) → state-prop sync | Parry causality reconciled host-side using this latch; high latency means parry windows feel slightly more generous to the parrier (their press tick predates the host's swing-tick by latency). |
| `:combo_step` | host (set in attack states) | Combo HUD readout lags by latency. |
| `:charge_start_tick` | host (state entry) | Charge buildup visible client-side via `NetworkTime.tick - charge_start_tick`; high latency means client briefly under-displays the buildup before snapping forward. |
| `:ultimate_charge` | host (`add_ultimate_charge` in `take_damage`) | HUD lags by latency. Ultimate availability is host-decided; clients can't prematurely cast. |
| `:respawn_invuln_until_tick` | host (`_apply_respawn`) | Invuln window respected on both peers — both check `NetworkTime.tick < respawn_invuln_until_tick` against their local tick clock, which netfox keeps within 1–2 ticks across peers. |
| `RewindableStateMachine:state` | host + client (input drives both) | Rollback handles. Observable rubberband on contested transitions; canonical state always wins. |

Damage RPCs (`apply_incoming_damage`) are dual-written: direct write +
RPC. At high latency, the client may render the hit slightly before the
state-prop confirms it, but the canonical hp comes from the state-prop
sync, so any RPC-write divergence resolves within rollback.

The Friendly Fire flag is a `static var` mirrored via a reliable RPC.
Toggling it during a fight could cause a brief asymmetry where a hit in
flight applied on one peer but was filtered on another. Acceptable
artifact: FF toggling is a debug / pre-match action, not a per-second
gameplay verb.

---

## Known limitations / followups

- **Anti-degen LOS gate is opt-in per-ability; nothing currently uses it.**
  The hook is in place (`AvatarAbility.requires_los`,
  `AvatarAbilities._has_hostile_los`). Designers should set it on
  Eldritch ranged-poke abilities in `data/abilities/*.tres` once those
  abilities exist. The LOS check is a simple physics raycast; promote to
  `KnowledgeManager`-aware (per-peer belief instead of physics truth)
  once the courier system is robust enough that "the avatar's belief"
  is meaningfully different from "physics truth."
- **Spawn-point picker uses Avatar position only.** Living `Actor`s in the
  actors group are scored by raw distance. To consider minion threat
  density (respawn far from a swarm), extend `_pick_respawn_position`
  with a weighted sum over the surrounding actors.
- **Hostile-takeover edge cases: harness exists; results not yet captured.**
  Run all five scenarios against a freshly-built avatar and document
  results here. Known-suspect scenarios:
  - **Mid-Roll:** `RollState.stagger_immune = true` for the full duration.
    The respawn flow transitions to IdleState which clears the flag, but
    if the new-owner takeover happened on the killing tick before the
    state machine processed the transition, there's a one-tick window
    where `stagger_immune` may carry. Verify with scenario 3.
  - **Mid-Charge:** `charge_start_tick` is a state_property that resets
    to -1 on damage in `Actor.take_damage`. Lethal damage (hp ≤ 0) routes
    to `_die` before the reset path; verify the field is -1 after respawn.
  - **Mid-Riposte:** the riposte attacker / victim are paired states.
    Killing the attacker mid-riposte should release the victim's
    `RiposteVictimState` lock; verify `victim.try_transition` succeeds.
- **Respawn delay uses a wall-clock `SceneTreeTimer`.** The timer fires
  off the rollback loop; in normal play the netfox tick clock and wall
  clock are in lockstep (30Hz physics tick), but heavy stalls could
  desync. If this becomes visible, replace with a netfox-tick-based
  scheduler (e.g. record `_respawn_at_tick = NetworkTime.tick + DELAY`
  and check inside `_rollback_tick`).
- **`RESPAWN_POSITIONS` is a const array.** Designers can't tweak it from
  the inspector. Promote to `@export var respawn_positions: Array[Vector3]`
  on a per-tower component (or read from world-scene Marker3D children)
  once the map ships per-tower spawn anchors.
- **FF flag on a `static var` doesn't survive instance restarts.** The
  default is restored on `GameState.reset()`. For per-match persistence,
  promote to a `MatchSettings` resource passed at lobby time.
- **DamageFilter is fail-open on missing fields.** If a future actor
  subtype lacks `controlling_peer_id` AND `owner_peer_id` AND `faction`,
  FF will pass through. Acceptable since every shipped actor has at
  least `faction`.
- **LOS raycast hits world geometry only.** Collision masks aren't
  filtered — anything on the ray-query default mask occludes. If the
  scene has thin decorative meshes that shouldn't break LOS, set up a
  dedicated occlusion layer and pass `query.collision_mask` to the
  raycast in `_has_hostile_los`.
