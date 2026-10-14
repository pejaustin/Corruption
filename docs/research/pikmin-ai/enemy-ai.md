# Pikmin enemy AI

Source: Pikmin 2 decomp (`pikmin2/`, main) and Pikmin 1 decomp (`pikmin/`, comparison), both under `/home/app/yumekara-jo/workshop/pikmin-decomp/`. Read 2026-10-13. Paths below are relative to those roots. Numbers are constructor defaults from the code; the real per-enemy values live in `enemyParm.txt` archive files that are not in the repo. Everything here is description of the reference, not a Corruption decision.

## 1. How it works (Pikmin 2)

### 1.1 Two stacked state machines

- **Lifecycle FSM (shared by every enemy).** `EnemyBaseFSM` states: DropX (5 variants), Appear, Living, Stone, Earthquake, Fit (`pikmin2/include/Game/EnemyBase.h:701`, registered at `pikmin2/src/plugProjectYamashitaU/enemyBase.cpp:782`). `onInitPost` picks the start state from the placement's "birth type" (`enemyBase.cpp:1075`). Only **Living** calls the enemy's own code.
- **Behaviour FSM (per enemy type).** `Obj::doUpdate()` is one line: `mFsm->exec(this)` (e.g. `pikmin2/src/plugProjectYamashitaU/ChappyBase.cpp` `Obj::doUpdate`). Each enemy builds its own `EnemyStateMachine` with an enum of states and `registerState` calls (`chappyState.cpp:12`). Generic machinery: `EnemyStateMachine::transit` runs `cleanup` on the old state, stores `mPreviousID`, runs `init(obj, arg)` on the new one (`pikmin2/src/plugProjectYamashitaU/enemyFSM.cpp:138`). States are objects shared by all instances of a type; per-instance data lives on the enemy (`mTargetCreature`, `mAlertTimer`, `mNextState`...), not in the state.
- **Statelessness gotcha they hit:** states keep a `mNextState` on the *enemy* and use "finish the animation, then transit when the END key event arrives" (`chappyState.cpp:288`, Turn exec). Decisions are made continuously, but transitions are deferred to animation boundaries, so an enemy never snaps mid-motion. A death check (`mHealth <= 0 -> Dead`) is repeated at the bottom of every state's exec (`chappyState.cpp:158,330,429`).

### 1.2 Living tick order, damage commit, and AI gating

`LivingState::update` (`enemyBase.cpp:478`):
1. If the enemy is "culling off" (visible, or a Pikmin is in its grid cell, or flagged non-cullable), run `doUpdate()` (the behaviour FSM) and `doUpdateCommon()`.
2. Run always-on work (queued bitter-spray -> Stone).
3. If alive: `lifeRecover()` (regen `max * regenRate` per tick, `enemyBase.cpp:2397`), then `injure()`.
4. Optional `mExistDuration` timer that force-kills (used for summoned enemies in versus).

**Damage is buffered.** Callbacks during the frame call `addDamage(amount, flickSpeed)`, which only adds to `mInstantDamage`, adds `flickSpeed` to `mFlickTimer`, and sets the `EB_TakingDamage` flag (`enemyBase.cpp:2743`). `injure()` runs after the AI tick and subtracts the sum from health (`enemyBase.cpp:2720`). So states see "I was hit this tick" as a flag and read `mHealth <= 0` next tick. `Invulnerable` skips both.

**AI gating (LOD).** `isCullingOff()` = no-cull flag unset OR visible-in-any-viewport OR a Pikmin in the cell OR dropping (`enemyBase.cpp:1831`). Off-screen enemies with no Pikmin nearby **do not run `doUpdate` at all**; their AI is frozen, not simplified. `Creature::updateLOD` sets visible/mid/far from camera frustum + projected screen size using `mLodParm.mFar/mClose` (e.g. Chappy 0.2/0.075, `ChappyBase.cpp` `onInit`; `pikmin2/src/plugProjectKandoU/creatureLOD.cpp:39`). `State::animation` counts culled enemies, skips model/collision updates, and fades effects (`enemyBase.cpp:67`). Enemies that must keep moving off-screen (patrollers, big bosses) clear the `EB_Cullable` flag in `onInit` (Spotty Bulbear: `pikmin2/src/plugProjectNishimuraU/KumaChappy.cpp` `onInit`; Beady Long Legs on death: `DamagumoState.cpp:31`). The cull radius is a per-type param (`mOffCameraRadius`, default 40; `EnemyParmsBase.h:63`).

### 1.3 Parameter system (data-driven tuning)

- `EnemyParmsBase::Parms` is one block of ~45 typed, ranged, defaulted fields: id tag, debug label, default, min, max (`pikmin2/include/Game/EnemyParmsBase.h:52`). Groups: life (health, regen, "alert life"), body (cell radius, Pikmin-damage radius, LOD radius, mass), movement (speed, turn rate, max turn angle), **perception** (territory, home radius, private radius, sight radius, sight height "fov", view angle, search distance/height/angle), **shake-off** (knockback, damage, range, chance, 4 blow/stick tiers), **attack** (max range, max angle, hit radius, hit angle, damage), alert duration, bitter (freeze) duration, earthquake-stun chance/duration/damage.
- Each enemy extends it with a `ProperParms` block of its own fields (Chappy: foot range, poison damage, wake radius; Kogane: min/max appear/travel/stop time; Emperor: ~25 fields; `ChappyBase.h:125`, `Kogane.h:123`, `KingChappy.h:78`).
- Loaded from a text file at manager init: `<name>/enemyParm.txt` read via a stream into the parameter tree (`enemyMgrBase.cpp:373,406`, `enemyParmsBase.cpp:12`). One parameter object per type, shared by every instance of it (`setupParms` assigns the same pointer to each enemy). Collision shapes load from a sibling `enemyColl.txt` (`enemyMgrBase.cpp:432`). A table `EnemyInfo` maps the enemy id to names and flags (`enemyInfo.h:55`).
- Placement overrides come from the level's spawner, not the param file: count, spawn radius, facing, birth type (wait hidden, drop on approach...), size/territory spacing (see 1.9).
- Pikmin 1 equivalent: the same idea in code. `TaiChappyParameters` sets ~45 int/float defaults per enemy variant in a constructor (`pikmin/src/plugPikiNakata/taichappy.cpp:89`); variants (Red/Black/Catfish) are three constructors that differ in life, ranges, swallow count, crying period.

### 1.4 Perception and target choice

All of this is per-enemy and **stateless between ticks**; there is no shared blackboard, no group aggro, no threat table.

- **Search (acquire).** `EnemyFunc::getNearestPikminOrNavi(self, searchAngle, searchRadius, ...)` loops every live Pikmin and every Navi, keeps those whose angular offset from the enemy's facing is within `searchAngle` and whose **flat (XZ) distance** is under the radius, returns the closest; a Pikmin wins over a Navi if both are found (`pikmin2/src/plugProjectYamashitaU/enemyAction.cpp:119`, helpers 17 and 67). Pikmin held in another enemy's mouth, dead, or non-Pikmin followers are excluded by `isSearchable` (`Piki.h:243`). Callers pass an optional condition object to filter further (e.g. "not already stuck to me").
- **Re-run each tick.** Chappy's Turn/Walk/Attack/GoHome states each call the search again every tick and overwrite `mTargetCreature` (`chappyState.cpp:288,370,525`). The target is "whoever is closest right now". There is no stickiness.
- **Drop test (lose target).** `isTargetOutOfRange(target, angle, privateR, sightR, sightHeight, viewAngle)` (`EnemyBase.h:524`) is true when
  `(flatDist > privateR AND flatDist > sightR AND |dy| < sightHeight) OR NOT angleWithin(viewAngle)`.
  Read literally: the cone is a hard gate; inside the cone, the target is lost once it is past *both* radii. (The `|dy| < height` term is as decompiled; treat the vertical handling as odd.) Losing the target sends the enemy home.
- **Two angles.** `mViewAngle` gates keeping a target; `mSearchAngle` gates acquiring one (defaults 90 and 120 degrees, `EnemyParmsBase.h:75-77`).
- **Alert widening.** Chappy's `cautionProc` (every state but Sleep/Dead calls it, `chappyState.cpp:46`): if any Pikmin/Navi is within the private radius (default 70) **or** health < `lifeBeforeAlert` (30), reset `mAlertTimer`. While the timer is under `alertDuration` (15 s), view and search angle are both forced to 180 degrees (all-around); afterwards they snap back to the parameter values. This is how "it noticed me / got hit" is modelled: a widening of the cone, not a new target.
- **Attackable test.** `isTargetAttackable(target, maxRange, maxAngle)` = squared distance inside range AND facing offset within angle (`EnemyBase.h:500`). Default range 70, angle 15 degrees: tight cone.
- **Presence checks without a target.** `isTherePikmin` / `isThereOlimar(self, radius)` are plain sphere-radius boolean checks (3D distance, not flat; `enemyAction.cpp:367,390`). Used for wake/appear triggers rather than chasing.
- **Variants.** Orange Bulborb wakes from sleep by radius (400) instead of by being hit (`ChappyBase.cpp` `isWakeup`, `chappyState.cpp:46`). Hermit Crawmad scans only a limited arc and radius (`jigumoState.cpp:60`). Long Legs only targets Pikmin that are **not** latched to a client (`Damagumo.cpp:309`).

### 1.5 Territory, home, and returning (the leash)

- Spawn sets `mHomePosition = birth position` (`enemyBase.cpp:1470`, birth).
- Three radii in params: `homeRadius` (default 15, "I am home"), `territoryRadius` (200, "too far from home"), plus the perception radii above (`EnemyParmsBase.h:71-74`).
- Chappy leash logic (`chappyState.cpp:370`, Walk exec): chasing continues while a target is valid; independently, **if distance-from-home > territory radius -> TurnToHome**, whatever the target. Tested only in the walking state; the other states (turn, attack) simply return to Turn/Walk afterward, so the leash is enforced at the next walk tick, not instantly.
- Return: `TurnToHome` rotates toward home (slowed by crowding, see 1.7), then `GoHome` walks there at normal speed (`chappyState.cpp:634,733`). While going home it **keeps scanning** and reacts: attackable target -> Attack; any other target -> Walk (chase again); damaged -> Turn. So the leash does not make the enemy invulnerable or deaf; it just gives home as the fallback goal. Arrival (`dist < homeRadius`) -> Sleep (constrained, anim idle, effect), which also clears the target.
- Pikmin 1 uses two numbers as hysteresis: leave the chase when beyond `DangerTerritoryRange` (Chappy 500), consider "home" reached when inside `SafetyTerritoryRange` (80) (`pikmin/src/plugPikiNakata/taichappy.cpp:130`; conditions at `taijudgementactions.cpp:93-103`). Distance is measured from the nest position stored in the placement's personality (`TekiPersonality::mNestPosition`).

### 1.6 Attack windows and hit resolution

- **Animation-keyed windows.** Animations carry key events (`KEYEVENT_2`, `_3`, `_4`, `END`). The state's exec reads the current key and does the damage on the exact key (Chappy attack: key 2 = bite resolve, key 3 = swallow, key 4/END = decide next; `chappyState.cpp:470`). No frame counters.
- **Resolution at the key, not continuous.** At the bite key Chappy calls `attackNavi(self, hitRadius, hitAngle, damage)` (loops Navis, 3D distance < radius and facing within angle, damages all that match; `enemyAction.cpp:296`) and `eatPikmin(self)` (loops Pikmin, checks each against free **mouth slots** with a radius around the slot joint; `enemyAction.cpp:224`). Swallowing is capacity-limited by slots: Chappy has 5 slots of radius 35 (`ChappyBase.cpp` `initMouthSlots`). A Pikmin that is eaten is excluded from targeting (`isSearchable`), and killed on the swallow key (`swallowPikmin`, `enemyAction.cpp` ~line 255).
- **Miss branch.** If the bite key finds nothing (`attackCheck == 0`), the enemy switches to a "WaitAct2" recovery animation and does a small ground-pound flick (`chappyState.cpp:470`, attack exec). A miss costs time.
- **Held-active variant.** Hermit Crawmad's lunge turns collision on at the key, then each tick during the active phase calls `attackNavi` and `eatPikmin` until it either eats something (-> Carry) or reaches the fixed goal point recorded at the start of the lunge (`jigumoState.cpp:314`). Goal is set at attack start and only re-aimed while the "turn" flag is on (before the key).
- **Contact damage.** Long Legs does damage purely through its leg colliders: `collisionCallback` sends a `Press` interaction to every Navi/Pikmin the leg overlaps, gated by `isCollisionCheck(part)` so only the foot part counts (`Damagumo.cpp:223`).
- **Per-source throttle.** A Navi's `InteractAttack` on an enemy is accepted once per Navi per tick via `EB_AttackingNavi0/1` flags cleared at the top of Living update (`enemyInteractBattle.cpp:40`; `enemyBase.cpp:478`). Pikmin hits have no such gate: every Pikmin hit adds damage.
- **Weak spots.** `damageCallBack` can scale damage by which collider was hit: Chappy takes 25% damage and a 0.2 flick increment when no body part is hit (the Navi-thrown-object case), full damage and 1.0 when a part is hit (`ChappyBase.cpp` `damageCallBack`). Long Legs takes damage **only** from Pikmin that are latched on (`Damagumo.cpp:205`).

### 1.7 Being swarmed: shake-off

- Counter `mStuckPikminCount` goes up/down on stick start/end (`enemyBase.cpp:2698`).
- `mFlickTimer` is "blows received since the last shake": each `addDamage` adds `flickSpeed` (usually 1), and the shake action resets it to 0. No decay over time.
- `isStartFlick` (`enemyAction.cpp:326`) compares rounded blows to a tier table chosen by stuck count: stuck < 3 -> need > 3 blows; < 5 -> > 8; < 10 -> > 15; else > 30 (params `ip01..ip07`, `EnemyParmsBase.h:94`). So a lightly attached enemy shakes quickly; a heavily covered one needs many more blows, which a large group delivers fast anyway. Pikmin 1 uses the same idea inverted: number of Pikmin in the *lower range* picks the number of damage events needed (`pikmin/src/plugPikiNakata/tekibteki.cpp:1640`, `TPI_FlickPikiCount1..3`, `FlickDamageCount1..4`).
- Flick action runs a Flick state; on its anim key it calls three helpers (`chappyState.cpp:589`, `ChappyBase.cpp` `flickStatePikmin`):
  - `flickStickPikmin(chance, knockback, damage, angle)`: each latched Pikmin independently with probability `shakeChance` (default 1.0) gets an `InteractFlick` (`enemyAction.cpp:153`).
  - `flickNearbyPikmin(range, ...)`: every Pikmin within the range (default 120) is knocked back, latched or not (`enemyAction.cpp:177`). Knockback direction is `faceDir + PI`; negative-angle sentinel `-1000` means "use each victim's own heading".
  - `flickNearbyNavi` same for Navis.
- While in Flick the `EB_FlickEnabled` flag is off so blows cannot re-trigger it; restored in cleanup. The state returns to `mPreviousID`, i.e. whatever it was doing (`chappyState.cpp:613`).
- **Crowd resistance on turning.** Chappy's turn rate is scaled by `1 - 0.9 * min(10, nearby Pikmin)/10` using the number of Pikmin within the `footRange` (50) (`chappyState.cpp:248`). More attackers around its feet = it pivots up to 90% slower, which makes it easy to surround and hard to escape.
- Emperor Bulblax adds a Navi-proximity term: every Navi inside `invisibleRange` adds 0.1 to the flick timer per tick, so standing next to it is itself a flick pressure (`kingChappy.cpp:~990`, `walkFunc`).

### 1.8 Stun, fall, freeze, death

- **Purple earthquake (stun).** An `InteractEarthquake` -> `earthquakeCallBack` transitions Lifecycle to Earthquake (a hop; velocity set up) unless flying/dead/constrained/no-interrupt (`enemyBase.cpp:2839`, `619`). After 3 ticks on the floor it rolls `purpleStunChance` (5%) -> Fit (stunned, behaviour paused, events backed up and restored on exit, wobble animation, duration `purpleStunDuration` 10 s) else back to Living (`enemyBase.cpp:645,539,593`). Fit ends early if dead or a bitter spray is queued. The per-enemy FSM is not stepped during Fit: `doUpdate` is only called once at entry.
- **Bitter spray (freeze).** `dopeCallBack` -> Stone state (`enemyBase.cpp:2856,683`): hide the model (stone prop replaces it), stop motion, constrain, back up event flags; during Stone, damage taken is multiplied by `getDamageCoeStoneState()` (1.5; `EnemyBase.h:262`, applied in `enemyInteractBattle.cpp:61`); after `bitterDuration` (1 s) the stone shakes then breaks -> Living. If the enemy has `EB_NoInterrupt` (mid-attack) the spray is **queued** (`EB_BitterQueued`) and applied when allowed. Dying while bittered drops berries by an enemy-class table.
- **Interruptibility.** A flag set by animation key events marks windows where nothing can interrupt (Spotty Bulbear's Rebirth uses `EB_NoInterrupt` keys 3/4 to open and close it; `KumaChappyState.cpp:83`).
- **Drop-in birth.** Enemies placed with a "drop" birth type start suspended 300 units up, hidden, waiting; they fall when a Pikmin or Navi gets within the private radius (variants: Pikmin only, Navi only, carrying-treasure only, earthquake only) (`enemyBase.cpp:109,150,179`). Stage hazards that become enemies at a trigger.
- **Death.** State code checks `mHealth <= 0` -> a Dead state: `deathProcedure()` (flag off damage anim, mark not-alive so it is no longer targetable, throw up its item drop, play death motion; `enemyBase.cpp:2506`), key events for rumble / item toss, and `kill()` on the END key. `onKill` then spawns death effects and either `becomeCarcass()` (becomes a carryable pellet the Pikmin haul home; `enemyBase.cpp:1214,1270`) or just leaves. Death by bitter produces berries instead.
- **Revive.** Spotty Bulbear's `doUpdateCarcass` runs while its body is a carcass: after 30 s a health gauge appears and fills over 10 s; at full it destroys the carcass pellet, re-births itself, and enters a Rebirth state (shakes off nearby Pikmin) (`KumaChappy.cpp` `doUpdateCarcass`).

### 1.9 Spawning groups and home position

- A placement record: enemy id, count N, spawn shape (0 point / 1 circle), appear radius, facing, birth type, drop item, `enemySize` used as min spacing (default 35) (`pikmin2/include/Game/gameGenerator.h:364`; `genEnemy.cpp` `generate`).
- Positions: if circle, random point in radius per enemy; then 5 relaxation passes pushing any pair closer than the spacing apart by half the deficit each; snap to ground. Each enemy is born with `mHomePosition` = its own spawn point, so members of a group **patrol their own spots**, not a shared centre.
- The generator remembers `mDeathCount`; re-generation only spawns `N - deaths`, i.e. camps refill only the dead.
- Pikmin 1 puts per-instance overrides (`SIZE`, `STRENGTH`, `TERRITORY_RANGE`, pellet drop counts and chances, nest position) into a `TekiPersonality` loaded with the placement (`pikmin/src/plugPikiNakata/tekipersonality.cpp:15-40`).

### 1.10 Group and swarm behaviour

Pikmin 2 has **no group AI**. Members of a group do not share targets, alerts, or formation. The only "group" effects are: spawn spacing (1.9); enemy-vs-enemy collision rules (Chappy ignores collisions with other Chappies, Pelplants, eggs; `ChappyBase.cpp` `collisionCallback`); one enemy's `mSfxEmotion == Excitement` making a neighbour's collision count; and a loose parent/child relation object for the Bulbear family (`ChappyRelation.h`, a plain owner pointer). Pack-feel comes from many enemies independently seeing the same player. Emergent: several Chappies each re-target the nearest Pikmin every tick, so they split Pikmin among themselves by proximity without coordination.

### 1.11 Route-graph walkers

- **Spotty Bulbear patrol** (`pikmin2/src/plugProjectNishimuraU/KumaChappy.cpp` `setNearestWayPoint`, `setLinkWayPoint`, `updateTargetDistance`; states `TurnPath`/`WalkPath` in `KumaChappyState.cpp:476,631`): the map ships a waypoint graph (`mapMgr->mRouteMgr`). On spawn the enemy snaps to the nearest waypoint (excluding closed ones), sets that as the walk target, and steps. On reaching a waypoint (distance < the waypoint's own radius) it picks a **random outgoing neighbour that is not the one it just came from and is not flagged Closed**; if there is none it backtracks; if it has no waypoint it falls back to the nearest. A 5-second no-progress timer re-snaps to the nearest waypoint (stuck recovery). Every tick on a path it moves `mHomePosition` to a point one home-radius ahead of its face direction, so the generic "go home" always means "keep walking forward". Seeing a target (sight radius, with the widened-angle alert trick tied to a 15 s timer) switches to the ordinary Turn/Walk/Attack states; losing it goes to a `Lost` state (idle look-around) and then `setNearestWayPoint` to rejoin the graph.
- **Wraith (BlackMan)** (`pikmin2/src/plugProjectMorimuraU/blackMan.cpp:1056-1300`): on arrival at a waypoint, waits for a cooldown, then picks the next waypoint by the current **phase** (`mEscapePhase`):
  - 0: random among open neighbours with 2+ links;
  - 1: neighbour closest to any Pikmin that is latched on, or to the active Navi (flee-from-damage, bias toward the player's group);
  - 2: neighbour closest to the active Navi (hunt);
  - 3: neighbour with the largest dot-product on a "turn right" vector (circling);
  - 4: follow a precomputed path from a pathfinder (scripted travel).
  The phase changes when its roller (a separate enemy object) dies (`isTyreDead` -> phase 2) or by a stage parameter. It never leaves the graph; local steering is only `walkToTarget` toward the next node, and a `mRouteFindTimer` rate-limits re-picks (120 ticks).
- The graph is the same one the Pikmin use for pathing, with `Closed` flags set by gates/bridges. The reuse means closing a route steers enemies away for free.

### 1.12 Other patterns seen

- **Ambush/hide (Hermit Crawmad).** Waits hidden underground, collision and "alive" off, immune to bitter spray, scale/model hidden. Becomes active when a Navi or Pikmin is within the **territory** radius (`jigumoState.cpp:124`). Surfaces at its home point, checks for targets in view cone and sight radius (`StateWait`, `jigumoState.cpp:60`), and either attacks or hides again (re-hide is a state with a fixed timer, `mHidingTime`). Health is topped up (+5) while hidden if under 1.
- **Wanderer on timers (Iridescent Flint Beetle, `KoganeState.cpp`).** No target at all. Each Move picks a heading = current facing + random offset within `turnAngle`, walks a random time between min and max travel, then Wait for a random stop time, then Move; it fades out after `maxAppearTime`. Appears only when a Pikmin/Navi is inside sight radius (`isAppear`, `Kogane.cpp:356`). Walks toward a point 1000 units ahead rather than a real target.
- **Roam in a ring (Beady Long Legs, `Damagumo.cpp:309`).** If inside territory: target the nearest unattached Pikmin in view, else pick a new random point in the **annulus between homeRadius and territoryRadius** whenever the current one is within 25 units; if outside territory: target home. Walk and Wait alternate on a 3.25 + random(3.25) second timer (`DamagumoState.cpp:325`). The sleeping version (`Stay`) is just "wait until a Pikmin or Navi is inside the private radius, then Land".
- **Emperor Bulblax (`kingChappy*.cpp`).** Underground `HideWait` until a Navi/Pikmin triggers an appear check (rate-limited by `timeToAppearance`); chases using territory (200) test from home; a "no target for N ticks" counter (`periodOfIncubation`) or leaving territory sends it home to `Hide`. No separate phase states. Health < 50% adds a probability (`flickShoutRate`) that a shake becomes a war-cry (stronger) instead of a plain flick; death has a `deathRate` chance to go through a war-cry first (`kingChappy.cpp:~1005-1045`). A `isBig` variant is the same code with a different parameter set (life, scale, speed, turn).
- **Beady Long Legs health stages.** Health ratio thresholds 0.35 and 0.175 only change sound cues and a smoke effect (`Damagumo.cpp:775,869`); the behaviour FSM has the same states at all health. Death spawns items and enemies by animation key.

## 2. Pikmin 1 comparison (data-driven)

- **State = list of parallel rules.** `TaiState` holds an array of `TaiAction`s; each tick runs *all* of them in order, and the first one that returns true **and** carries a next state causes the transition; a special value means "return to the previous state" (`pikmin/src/plugPikiNakata/tai.cpp:115`). `TaiSerialAction` strings sub-actions into a sequence (`tai.cpp:51`). Events (damage, collision) are delivered separately via `eventPerformed` and go through the same list (`tai.cpp:213`).
- **Actions are tiny reusable nodes:** movement (`TaiGoingHomeAction`), judgement (`TaiOutsideTerritoryAction`, `TaiTargetVisibleNaviPikiAction`, `TaiAttackableNaviPikiAction`, `TaiFlickAction`), timer, motion, attack, effect, message (`TAI/*Actions.h`). A strategy file builds each action once and composes states by listing them (`taichappy.cpp` `TaiChappyStrategy` ctor, ~line 305). Target selection is itself an action: the judgement writes the creature into a numbered per-enemy "creature pointer" slot (`taijudgementactions.cpp:109`), later actions read slot 0.
- **Conditions are objects** (`TekiConditions.h`: Visible, Attackable, LowerRange, Recognition, And, Not, Sticker...) passed into generic search helpers, which is the origin of Pikmin 2's `Condition<Piki>*` arguments.
- **Result:** Pikmin 1 AI is closer to a behaviour table assembled in code; Pikmin 2 replaced it with hand-written per-state `exec` functions on a plain FSM plus a shared helper library. Parameters moved from code constructors to text files, and the perception set stayed nearly identical (visible range/angle/height, attackable range/angle, two territory ranges, flick tiers).

## 3. Patterns studied

| Enemy | Pattern | Perception / leash | Notes |
|---|---|---|---|
| Red Bulborb (`chappyState.cpp`) | Sleep -> Turn -> Walk -> Attack -> Flick; TurnToHome/GoHome | Nearest in search cone each tick; lost by view/sight; leash at territory 200; alert timer widens cone to 180 | Baseline; 9 states; mouth slots; crowd slows turning |
| Orange Bulborb | Same FSM, different wake rule | Wakes by 400-unit radius, not by being hit | Variant by switch on type id |
| Spotty Bulbear (`KumaChappy*.cpp`) | Route-graph patrol + chase | Random-neighbour waypoint walk; `Lost` state; stuck timer | Never culled; revives from carcass |
| Hermit Crawmad (`jigumo*.cpp`) | Hidden ambusher | Territory radius to surface; view cone to pick prey | Collision only during the lunge; fixed goal point |
| Iridescent Flint Beetle (`Kogane*.cpp`) | Timed wander, no combat | Sight radius to appear only | Random heading drift + stop timers |
| Beady Long Legs (`Damagumo*.cpp`) | Slow boss, annulus roam, stomp | Private radius wakes; roams home..territory | Takes damage only from latched Pikmin; stomps via leg colliders |
| Emperor Bulblax (`kingChappy*.cpp`) | Boss ambusher with hide/reset | Territory leash + no-target counter -> Hide | HP<50% adds roar chance; big variant = other params |
| Wraith (`blackMan*.cpp`) | Route-graph hunter with phases | Waypoint choice by phase mode | Phase switch when roller part dies |
| Pikmin 1 Chappy (`taichappy.cpp`) | Action-list strategy | Danger/safety territory pair | Tiered flick from nearby count |

## 4. What Corruption could take (options)

Context from the repo: minions already have throttled scanning with a staggered interval, a per-target ignore list, a vertical-reach cut, navmesh reachability check, animation-ratio hitbox windows, and states Idle/Chase/Attack/Jump/Retreat on a `RewindableStateMachine` (`scenes/actors/minion/states/minion_state.gd`, `attack_state.gd`, `chase_state.gd`). `docs/systems/minion-ai.md` (superseded by the GDD, reference only) lists stationed-guard and patrol-with-leash as planned behaviours. Each option below is independent.

**A. Home / territory / leash as three numbers.**
- *What:* `home_position`, `home_radius`, `territory_radius`. Leash = distance from home beyond territory sends the unit to a `ReturnHomeState`; "arrived" = inside `home_radius`, then back to station idle. In `GoHome` keep scanning and re-engage if something is attackable (P2), instead of ignoring enemies.
- *Godot:* two floats on the `MinionType` resource, `home_position` set at spawn; `ReturnHomeState` is a copy of `ChaseState` with the destination fixed to home and the target scan on. The leash check can live in `Chase` only (as P2 does) or in `MinionState.tick` for all states.
- *Trade-offs:* leash only checked while walking means a unit mid-attack can drift past territory (usually fine, cheaper). Two radii (home vs territory) prevent flip-flopping at the edge; Corruption's `Idle`/`Chase` already uses a similar hysteresis margin for waypoints. P1's variant uses a pair (leave beyond danger, rearm inside safety) that is the same idea with different names.

**B. Perception cone with an alert widening.**
- *What:* separate `view_angle` (keep) and `search_angle` (acquire), `sight_radius` and a smaller `private_radius` that always notices; a timer widens both to 360 for N seconds after something is noticed or the unit is hit, then reverts (P2 `cautionProc`).
- *Godot:* `MinionActor.can_see(candidate)` already exists; add the cone and an `alert_timer` (rewindable int ticks so netfox can resimulate). Alert reset when `take_damage` or an enemy inside `private_radius`.
- *Trade-offs:* gives sneakable camps and a readable "it saw me" moment with almost no state; the cone needs facing, so units need a smoothed facing direction (they have `face_direction`). Low-information RTS: view cone may not be visible to the player, so it matters mostly for flavour/timing.

**C. Sticky target vs recompute-nearest.**
- *What:* P2 recomputes the nearest each tick and drops via the out-of-range test; Corruption's scan is throttled and keeps the target while valid. Options: keep as is; add a stickiness rule (keep target unless a new one is X% closer); or add a "drop test" (out of cone and past both radii -> forget).
- *Godot:* edit `find_hostile_target` / `_scan_for_target`; the ignore list (`ignore_target`) already covers the "unreachable" drop.
- *Trade-offs:* pure nearest is cheap and stateless but ping-pongs in crowds; stickiness reduces thrash, adds one variable.

**D. Swarm resistance and shake-off.**
- *What:* count attackers engaged on a unit (the analogue of stuck Pikmin) and a counter of hits since the last shake; a tier table (count -> required hits) triggers a `FlickState` that knocks back all attackers within a radius and resets the counter, with a per-attacker probability for the "latched" set and 100% for the nearby ones (P2 `isStartFlick` + `flickStickPikmin` + `flickNearbyPikmin`). Optional: turn rate scaled down by nearby attackers.
- *Godot:* `FlickState` on the minion/boss state machine; the tier table is an exported `Array[Vector2i]` or small Resource; knockback via the existing damage pipeline (`Actor.incoming_damage` plus an impulse). Hit counters must be rewindable properties.
- *Trade-offs:* makes mass attacks self-limiting and gives bosses a "get off me" beat; but needs each attacker to count as "attached" (engaged melee targets) and needs a way to show it. Knockback on many units under rollback is more state to sync.

**E. Damage buffering with an explicit commit.**
- *What:* callbacks only accumulate damage and set a `was_hit` flag; health changes once per tick after the AI step (P2 `addDamage` / `injure`). Optional: per-source-per-tick gate so the same attacker can't hit twice in one tick.
- *Godot:* `Actor.incoming_damage` already acts like the buffer; the option is to define where it is drained relative to state `tick` and expose `was_hit` for states to read (wake from sleep, alert widening, retreat trigger).
- *Trade-offs:* removes order-of-evaluation bugs between attackers and states; small cost.

**F. Animation-key attack resolution and grab slots.**
- *What:* resolve the hit at a keyed instant (geometry query at that frame) rather than continuously; `eat`-style grabs use N slots so at most N victims; a missed swing enters a recovery animation that costs time.
- *Godot:* `AttackHitbox` already supports enable/disable windows and animation method-track keys; the option is to add a one-shot `resolve_at_key` mode and a `max_victims` cap, plus a "nothing hit" branch to a short vulnerable state.
- *Trade-offs:* one-shot is cheaper and easier to read, but an enemy that moves out of the arc in the window dodges it; held-active (Crawmad) is more forgiving for the attacker.

**G. Ambush / sleep / hide states.**
- *What:* `Sleep` (idle, constrained) with a wake rule per type (hit, or radius), `Hide` (collision off, untargetable, immune to status effects) surfacing when a hostile enters a radius, with a re-hide timer if nothing is in view (Crawmad, Emperor, Orange Bulborb).
- *Godot:* new states; set `can_take_damage()` false and collision layers off while hidden (the target scan already skips actors with `can_take_damage() == false`). Wake rule as `wake_radius` plus `wake_on_hit` fields.
- *Trade-offs:* cheap, strongly readable ambush; costs an extra untargetable state that other systems (retreat, capture) must respect.

**H. Wander patterns.**
- *What:* three small patterns: random-heading drift with random move/stop timers (Flint Beetle); random point in the ring between home radius and territory radius, re-picked on arrival (Long Legs); waypoint random walk (see I).
- *Godot:* `WanderState` with `nav_agent.target_position = random_point_in_annulus(home, r_in, r_out)`, snapped with `NavigationServer3D.map_get_closest_point`; timers as rewindable ticks.
- *Trade-offs:* the ring approach keeps a patrol inside the leash by construction, so it composes with option A without a graph; timers add randomness that must come from a seeded/rollback-safe source on the host.

**I. Route-graph patrol and phase-selected routing.**
- *What:* a graph of waypoints with a `closed` flag; on arrival pick the next node by a rule: random non-backtracking neighbour (Spotty Bulbear), or a rule chosen per phase (random / toward latched attackers / toward the player's avatar / circle) (Wraith). Per-node radius for arrival. Stuck timer to re-snap to the nearest node. Seeing a target hands over to the combat states; losing it goes to a `Lost` state then rejoins the graph.
- *Godot:* waypoints as `Marker3D` nodes with `neighbors: Array[NodePath]` or a `Resource` graph; `PatrolState` holds `current_wp`, `prev_wp` (rewindable ints); `Lost` state is a short idle then nearest-waypoint snap. This is the "PatrolBehavior" slot in `docs/systems/minion-ai.md`.
- *Trade-offs:* deterministic, authorable, and gate-aware (closed nodes) but needs authored graphs per camp; the ring wander (H) needs none. Re-using the graph for player pathing would make closing it affect both, as in P2.

**J. Parameter block: shared base + per-type extension.**
- *What:* one base parameter set with ranged, defaulted fields for every enemy (life, regen, speeds, perception radii/angles, attack range/angle/hit radius/damage, shake tiers, alert duration), plus a per-type extension block. Variants (orange, big) are alternate parameter sets over the same states, with a few type-switches in code for exceptions.
- *Godot:* `MinionType` already holds stats; the option is to add a `PerceptionParams` / `TerritoryParams` sub-resource with `@export_range` hints, and subclass the resource for bosses. Variants as inherited `.tres`.
- *Trade-offs:* tuning without code; cost is one more sub-resource to keep in sync with the unit scenes.

**K. AI gating by relevance.**
- *What:* run per-unit AI only when on screen, or when an opposing unit is near (P2 culls `doUpdate` otherwise), with an opt-out flag for things that must keep moving (patrols, bosses). Off-screen units are frozen rather than simplified.
- *Godot:* `VisibleOnScreenNotifier3D` or a spatial grid; the flag becomes `always_tick`. Alternative: reduce rather than skip (lower scan rate, no animation), already partly done by `SCAN_INTERVAL`.
- *Trade-offs:* big savings for large overworlds, but freezing off-screen camps means they do not patrol or respond unless something wakes them; in a game with fast-forwarded or remote-viewed (Palantir) fights, "visible" must include remote cameras, and under netfox the host must make the same decision for all peers.

**L. Layered status over behaviour.**
- *What:* a thin lifecycle layer (spawn -> appear -> living -> stunned/frozen -> dead) underneath the per-type behaviour FSM; stun/freeze states pause the behaviour FSM and restore its event flags on exit; "no-interrupt" windows queue the effect until allowed.
- *Godot:* a stun/freeze flag consulted at the top of `MinionState.tick` (like `check_retreat`), or a second state machine; queued effects as a rewindable field.
- *Trade-offs:* keeps behaviour states free of status logic and avoids editing every state (the exact tax `minion-ai.md` describes for retreat); the cost is a second source of truth for "what is this unit doing".

**M. Boss phases and parts.**
- *What:* P2 bosses show three styles: (1) thresholds that only change presentation (Long Legs 35%/17.5% sound and smoke); (2) a probability gate on a stronger variant of a reaction below a health fraction (Emperor roar below 50%); (3) a separate integer phase that changes the target-selection rule and flips when a part dies (Wraith). Damage routing by part: only latched attackers hurt Long Legs; non-weak-point hits do 25%.
- *Godot:* boss resource gets `phase_thresholds: Array[float]` and a `phase` int on the boss actor (rewindable); states read `phase` to choose targets or actions. Part health as child actors. Matches the existing scene-inheritance approach in `docs/systems/boss-mechanics.md` without a script override.
- *Trade-offs:* thresholds-for-presentation is almost free; behaviour-changing phases need new states or a rule table per phase; part kills need part actors and sync.

**N. Camp spawning.**
- *What:* a camp record with member count, spawn shape and radius, min spacing relaxed over a few passes, per-member `home_position` = own spawn point; the camp remembers deaths and re-spawns only the dead.
- *Godot:* a `CampSpawner` Node3D with exported fields; spacing pass in `_ready`; `death_count` on the camp.
- *Trade-offs:* trivial and yields natural spread; per-member homes make members drift independently, a shared home would hold them tighter.

**O. Regen and revive.**
- *What:* regeneration of `max_hp * rate` per tick whenever alive (P2 applies it every tick, tuned low), and optional timed revival from a corpse with a visible gauge (Spotty Bulbear).
- *Godot:* `Actor` `hp` regen in `_physics_process` on host; revive as a `CorpseActor` with a timer.
- *Trade-offs:* regen makes hit-and-run weak; revive creates a world object that must be cleaned up.

**P. Data-defined transition tables (the Pikmin 1 route).**
- *What:* state = ordered list of (trigger, next-state) rules evaluated every tick, first match wins, with a "return to previous" target; triggers are small reusable objects (OutsideTerritory, TargetVisible, Attackable, Timer, HealthZero...).
- *Godot:* `Trigger` resources with `check(actor) -> bool` and a `StateRules` resource per state, evaluated in `MinionState.tick` before the state's own motor code. Addresses the "data-driven authoring" open question in `minion-ai.md` for simple behaviours (guard, patrol) without new GDScript per behaviour.
- *Trade-offs:* behaviours become data and composable; harder to debug than readable `tick()` code, and the P1 version had to hand-build the lists in code anyway. Per-tick evaluation of many triggers costs more than a coded state. P2's authors went the other way (coded states + shared helpers) for the complex enemies.

## 5. Open questions

- Real per-enemy numbers (sight, territory, shake tiers, speeds) are in game archives not present here, so only constructor defaults are known; there is no way from this repo to see how an actual Red Bulborb is tuned.
- The `isTargetOutOfRange` expression is taken as decompiled (`pikmin2/include/Game/EnemyBase.h:524`); the height term reads oddly and may not match intent. Treat the vertical handling as unverified.
- P2 resolves "which animation key means hit" in the (unprovided) animation data; the decomp only shows key numbers (2/3/4/END), not frame times.
