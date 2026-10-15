# Hits and damage: research and strategies (2026-10-15)

Research for an interview with Austin. Nothing here is settled until attributed to him. Settled answers move to
`docs/GDD.md` (design) or a technical doc (implementation).

## 1. What Corruption does today (master @ b6984d9)

- **Two hit systems.** The Paladin's sword is an `AttackHitbox` (`Area3D`) on the `RightHand` bone; the host polls
  `get_overlapping_areas()` while the attack state's window is open (`scenes/actors/player/states/attack_state.gd`).
  The boss ignores its own `AttackHitbox`: a blow is a maths box `reach` x `width` in front of him, tested against every
  hostile actor's position each tick of the active phase (`boss_actor.gd` `strike_targets`).
- **Windows.** Paladin: fraction of the clip (0.25 to 0.6). Boss: seconds in `BossAttack` (windup, active, recovery);
  the clip is stretched to fit and its hit frame is not matched to the active window (marked PLACEHOLDER).
- **Authority.** The host alone decides every hit, on its own view of positions. Damage to rollback bodies is queued in
  `incoming_damage` and drained inside the rollback tick; the Paladin's driver also gets an RPC.
- **One hit per swing:** per-window hit log (hitbox) or `_swing_hits` (boss).
- **Damage model:** flat int HP, times multipliers (swing, profile, hurtbox region, abilities). Boss never staggers;
  others stagger on any hit.
- **Gaps against GDD C1/C8:** no stamina, poise, block, parry, armor or lock-on yet. **The roll has no i-frames**: it
  is stagger-immune only, so a boss blow during a roll still lands.
- **Rollback problems:** `Area3D` overlaps update once per physics frame, never during a netfox resimulation, so they
  only work because hits are host-only and unpredicted. A lagging Paladin sees a blow land after he thought he rolled
  clear (the host saw him later than he did).

## 2. What the industry does

- **FromSoftware (modding tools, DSAnimStudio/Smithbox):** every animation has an event track (TAE): attack windows,
  i-frames, hyperarmor, input/cancel windows, effects. Attack shapes are spheres/capsules on attach points
  ("DummyPoly") on the weapon or body. Windows are authored on the clip, not in code.
- **Fast weapons tunnel** through thin targets at low tick rates; the fix is sweeping the shape from last tick's
  position to this tick's (Unreal melee-trace plugins, Roblox raycast-from-last-position).
- **Damage:** Elden Ring = per damage type (attack - flat defense) x absorption %, summed. Separate hidden **stance
  damage** per attack breaks enemy poise; player poise + per-attack **hyperarmor** decide flinching. Sekiro replaces
  stamina with **posture** (block/deflect fill it; full = deathblow). Lies of P: blocked damage becomes recoverable
  "regain" HP; perfect guard costs nothing. Monster Hunter: per-body-part hitzone multipliers.
- **Hitstop:** attacker and victim freeze a few frames on contact; sells weight, but slows pace if overused.
- **Networking:** Dark Souls is attacker-decides ("phantom" positions ~1 RTT old): responsive swings, notorious lag
  backstabs. Mordhau: server decides with lag compensation. For Honor: deterministic simulation with rollback-like
  "time travel" (GDC 2019). Fighting games: rollback, frame data in ticks.

## 3. What Godot/netfox projects do

- Standard Godot: hitbox `Area3D` (mask only) + hurtbox `Area3D` (layer only), team layers. Fine offline.
- In netfox rollback, signals and overlap lists are wrong (no physics step during resim). netfox's examples query
  physics directly inside `_rollback_tick` (`intersect_ray`; for melee, `intersect_shape` or `ShapeCast3D` with
  `force_shapecast_update()`).
- **Damage as rolled-back state** (rollback-fps example): `health` in `state_properties`, the attacker's tick changes
  it and calls `NetworkRollback.mutate(victim)` so the victim resimulates from that tick. Effects (sound, flash, numbers)
  fire once via `is_fresh` or `RewindableAction` `CONFIRMING`, undone on `CANCELLING`. Don't deal damage from
  *predicted* remote input (`is_predicting()`).
- For bone-accurate hits under rollback, the pose must be reproducible per tick: animation time as rolled-back state,
  `seek()` each tick, read the bone, or bake per-tick shape transforms. No netfox melee example exists.

## 4. Strategies (one choice per row, for the interview)

| Topic | Options |
|---|---|
| Who decides a hit | **Host decides** (today) / **attacker decides** (Dark Souls) / **predicted + host confirms** (netfox rollback) |
| Where a blow is | **Weapon/limb shapes on bones**, swept per tick / **fixed shape per attack** placed in the scene / mix: bones for the Paladin, fixed for the boss |
| How windows are authored | **Keys on the animation** (TAE style: active, i-frames, hyperarmor, combo) / **numbers in data** (ticks or seconds, CSV) |
| Defence | i-frames on roll; block; parry/deflect; stamina vs posture |
| Damage numbers | flat HP / HP + poise-stance / HP + posture; flat vs % armor |
| Feel | hitstop or not; who flinches on what |
