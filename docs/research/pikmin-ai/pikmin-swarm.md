# Pikmin AI and swarm following

Source: Pikmin 2 decomp (`pikmin2/`, main) and Pikmin 1 (`pikmin/`, comparison), read 2026-10-13. Paths are under `workshop/pikmin-decomp/`. Constants are `Parm` defaults in headers; the game also loads overrides from text files at runtime, so treat them as order-of-magnitude. World units: a Pikmin's hit size is 6-10 (`PikiParms.h` mHitSizeMin/Max), its run speed 120 per second, so read every radius as "body-lengths".

## 1. Layering

Three layers, top to bottom.

1. **Body FSM** (`pikmin2/src/plugProjectKandoU/pikiState.cpp`). About 33 states (`PikiState.h:26-60`): Walk, LookAt (whistled), Flying (thrown), Flick, Blow, Panic, Drown, Dying, Hanged, Emotion, Pressed, and so on. These are physical/reactive conditions, not goals. Only one state runs the brain: `PikiWalkState::exec` just calls `mBrain->exec()` (`pikiState.cpp:157`). Every other state owns the Pikmin outright and returns to Walk plus a brain action when done (e.g. `PikiFlyingState::bounceCallback`, `pikiState.cpp:2297`, lands then runs the idle scan).
2. **Brain** (`aiAction.cpp:84-196`, `PikiAI.h:93-109`). A flat array of 14 big actions indexed by an enum (Formation, Free, Enter, Exit, Transport, Attack, BreakGate, BreakRock, Crop, Weed, Bridge, Teki, Rescue, Battle). Exactly one is current: it is **not a stack**. `Brain::start(id, arg)` calls `cleanup()` on the old one, sets the new one, calls `init(arg)` (`aiAction.cpp:150`). Actions are pre-allocated per Pikmin, so switching allocates nothing. `exec()` returns Continue / Success / Fail (`PikiAI.h:113-115`).
3. **Primitives** (`aiPrimitives.cpp`). Small reusable actions owned by a big action as members and driven by it: ApproachPos, GotoPos, GotoSlot, PathMove (spline + pathfinder), StickAttack, Gather, Climb, FollowVectorField. A big action is a hand-written mini state machine over primitives (Attack: adjust -> stick-attack or jump-adjust; Transport: slot -> lift -> move, `aiTransport.cpp:96`).

**What happens when an action ends** (`aiAction.cpp:84-148`): on Success or Fail the brain first tries a forced idle scan (`invokeAIFree` with force flag). If that finds a job, it starts it. Otherwise it reads the finished action's `getNextAIType()`: Formation means "find the nearest living leader within 300 and rejoin" (`searchOrima`, `aiAction.cpp:197`), Free means "go idle". Default is Formation (`PikiAI.h:156`); `ActFree` overrides it with a value that matches neither case, so nothing is started. So a worker finishing a job picks another nearby job before it goes back to the leader. Success also fires an `emotion_success()` hook that moves the body FSM into a short Emotion state.

**Pikmin 1 differs in structure, not spirit** (`pikmin/src/plugPikiKando/aiAction.cpp`). It has a tree: `TopAction` holds ~32 child actions in an array; composites `AndAction` (all children in sequence) and `OrAction` (first child that works) exist (`aiAction.cpp:121,161`). Messages (`MsgCollide`, `MsgWall`, `MsgAnim`) are routed to the current action by `Action::procMsg` (`aiAction.cpp:31`). When an action finishes, `TopAction::exec` (`aiAction.cpp:314-400`) uses a per-Pikmin `mActionState` to decide where to go next:
- 0: rejoin the squad unconditionally;
- 1: rejoin only if the leader is within `mPostWorkJoinPartyRange` = 250 (`PikiMgr.h:113`);
- 2: go idle.
The caller that started the job chose the value. P2 collapses this into `getNextAIType`.

### How actions are chosen and interrupted

Three entry points, all ending in `Brain::start`.

- **Idle scan** `Piki::graspSituation_Fast` (`pikiAI.cpp:33`) called through `invokeAIFree` / `checkInvokeAI` (`pikiAI.cpp:840-905`). Only runs for Free Pikmin (and for the Brain's post-action fallback). See section 5.
- **Contact while following** `Piki::invokeAI(CollEvent*, isNaviSwarming)` (`pikiAI.cpp:609`). A following Pikmin that bumps something interactable while the leader is "commanding" starts the matching job at once (attack an enemy touched, carry a pellet touched, break the gate, and so on). The flag `isNaviSwarming` is true only when the leader is actively pushing the formation (`ActFormation::collisionCallback`, `aiFormation.cpp:560-575`, minus a 45-frame cooldown right after joining, `aiFormation.cpp:79`). A Pikmin still walking into formation (`mSortState != FORMED`) ignores plain contact pickups (`pikiAI.cpp:615`). Net effect: the squad does nothing on its own while the leader is idle or standing, and does work where the leader pushes it.
- **Thrown landing** `PikiFlyingState::collisionCallback` and `bounceCallback` (`pikiState.cpp:2297-2370`). The thrown Pikmin latches onto enemy parts it hits (with a crush interaction first if falling), otherwise on landing runs the contact check with swarming = true, else idle scan, else Free.

Interrupts are not preemption by priority. The body FSM gates them: each state exposes `callable()` (can be whistled), `invincible()`, `dopable()`, `releasable()`, `transittable()` (`PikiState.h:79-130`). The whistle (`InteractFue::actPiki`, `interactPiki.cpp:68-195`) checks `callable` and that the Pikmin is not already in formation (unless merging parties), tears down the current action (`cleanup`, `clearCurrAction`), assigns the leader, and moves the FSM to LookAt. So "interrupt" = interaction message -> state veto or accept -> hard reset of the brain.

### Interaction / message system

`Creature::stimulate(Interaction&)` is double dispatch: each interaction subclass (`Interaction.h`, `interactPiki.cpp`) has `actPiki`, `actNavi`, `actItem` overloads, so the same message (`InteractFue` whistle, `InteractDope`, `InteractWind`, `InteractBomb`, `InteractAttack`, `InteractKaisan` dismiss, `InteractSuck`) means different things to different receivers. Each `actPiki` first asks the current FSM state (`invincible`, `dead`, `callable`) and returns bool (accepted). Effects are state transitions with a typed arg struct (`BlowStateArg`, `DopeStateArg`). The sender never knows the receiver's internals. Callbacks (`collisionCallback`, `platCallback`, `wallCallback`, `bounceCallback`) are routed to the current brain action as virtuals on `Action` (`PikiAI.h:157-161`); the action decides what a collision means to it.

## 2. The formation (CPlate)

### Data

`Game::CPlate` (`gameCPlate.cpp`) belongs to the leader (`Navi::mCPlateMgr`, `navi.cpp:84`, capacity `MAX_PIKI_COUNT`, joining hard-capped at 100 slots, `gameCPlate.cpp:171`). It is an ordered array of slots; slot index = queue position. Each slot holds the Pikmin and a listener (the Pikmin's Formation action), and the plate calls `listener->inform(newIndex)` whenever the index changes (`releaseSlot` shifts everything after it down; `swapSlot` swaps). So Pikmin never search for a slot; the plate tells them. A Pikmin only has to compute the world position of its index and walk there (`getSlotPosition` = slot offset + plate base position).

### Slot geometry (`refresh`, `refreshSlot`, `gameCPlate.cpp:385-510`)

- Slot cell size `mMaxPositionSize` = 6 (halved for 10 frames after `shrink()`, used when squeezing through a narrow platform such as a finish gate, `navi.cpp:599`). A cell is 2 x 6 = 12 wide.
- Formation is a **disc packed in rows**. Rows are perpendicular to the leader's facing and start at the leader's side. Row k has width `2*val+1` slots where `val` comes from the chord of a circle of radius `mMoveStickRadius` at that row's offset (a row near the middle is wide, rows near the ends are narrow). Slot order alternates left/right per row so Pikmin fill from the centre line outward. Rows stop when `activeGroupSize` slots are placed.
- Radius scales with the square root of the head-count (`mMaxRadius = 2.1 * cell * sqrt(n/pi)`). A stick tilt strength interpolates between a **tight ball** (radius from `2.1*cell*sqrt(n/pi)`) and a **long wide blob**; `mBaseRadius` is the distance from the leader to the formation centre, derived so disc area stays about constant (`4*n*cell^2 / (pi*moveStickRadius)`), capped by `mLengthLimit` = 130 (`CPlate.h:36-43`).
- Plate position: `base = leader_pos + dir * (baseRadius + startingOffset*scale)`; `startingOffset` is 17.5, tripled after the stick has been held 40 frames, zeroed when the leader is moving faster than 5 (`gameCPlate.cpp:107-130`, `navi.cpp:2158`). Direction `dir` is the **stick (cursor) direction**, smoothed: if the new direction is within 120 degrees of the old, it moves 40% of the angular gap per frame, otherwise snaps (`navi.cpp:2121-2146`). With the stick neutral and the leader walking, it points opposite the leader's facing, so the squad trails.

### Assignment and ordering

- Joining: new Pikmin gets the next index (the back of the queue) (`getSlot`).
- Sorting: `sortByColor` (`gameCPlate.cpp:296`) bubble-sorts by (type rotated so the held type comes first, then growth stage). Triggered on pick-up by the leader, not every frame.
- Re-sorting by distance: `rearrangeSlot` (`gameCPlate.cpp:351`) is an insertion sort by distance to the leader. Run **once** when the leader stops commanding and nearest follower is further than the "change formation" range (40), so the nearest Pikmin take the front slots after a long walk (`navi.cpp:2208-2240`).
- Leader-distance states use hysteresis counters (`mCStickState`, `mCStickIncrement`), preventing flicker: nearest follower within `mPikiWaitRange` 15 (idle plate), within `mPikiChangeFormationRange` 40 (plate follows only its own heading, `setPosGray`), beyond that (re-sort).

### How a follower moves to its slot (`ActFormation::exec`, `aiFormation.cpp:270-570`)

Run every frame while following. Let `d` = flat distance to slot. Order of checks:

1. Early fails: no slot, leader dead, leader carrying a pellet (the leader hand-off case), another leader in follow state without a controller (`aiFormation.cpp:271-298`).
2. Stumbling animation takes over for its duration, velocity damped by 0.955 per frame (`aiFormation.cpp:300-309`). Trip chance: after 100 units of travel while above 110 speed, 1% x 30%; Bulbmin never trip (`aiFormation.cpp:343-366`).
3. Wall fallback: if blocked by a wall (counter of wall callbacks > 3 in the last 50 frames) and `d > 60`, follow the leader's **footmark trail** (breadcrumbs the leader leaves) to the nearest crumb instead of the slot (`aiFormation.cpp:312-338`). Cheap detour without a navmesh query.
4. Join phase (`d < 60`, leader stopped, not yet sorted): all joining Pikmin walk to the **leader's position** (not their slot) at full speed until within 40, then count as formed. After the leader has stood still `mPikiLoseNumbnessTime` 5 s (minus up to 2 s random) they get a "numb" flag so they stop clustering (`aiFormation.cpp:369-415`). After formed, they face the leader (angle error x 0.3 per frame).
5. Distance bands near the slot (`aiFormation.cpp:418-522`):
   - `d <= 7`, or `d <= 15` while a 6-frame counter has not tripped: **stand**. Zero target velocity, turn to face the leader. This is the dead-band; the counter resets when `d > 15`. Being in this band marks the Pikmin as formed.
   - `d < 15` otherwise: **brake**. Computes stopping distance from current speed and the Pikmin's acceleration (`10/accel` stopping time model): if inside it, stop; if inside the "could stop at full speed" distance, set a speed from `v = 0.5*sqrt(v^2 + 8*(10/accel)*d) + v` (a braking profile); else full speed. 
   - else: **full speed** at the slot direction.
6. **Separation / avoidance of the leader**: if the Pikmin is on the leader-side of the plate (dot of leader->plate direction and leader->Pikmin is positive, i.e. it is in front of the leader, between leader and plate), it adds a **sideways impulse** perpendicular to the leader->Pikmin line, left or right by slot index parity (`slotID & 1`), at half speed, and then restores the magnitude (`aiFormation.cpp:481-500`). The impulse is zeroed if the stick is not neutral (`newVer`). So followers pass the leader on alternating sides instead of through him, with no pairwise avoidance. Pikmin-to-Pikmin separation is only the physics body collision; there is no boid steering in P2 (P1's `getAvoid` is used only in idle/escape actions).
7. Lost-follower check, last in the frame (`aiFormation.cpp:528-545`): `d < 600` ("white" distance, `PikiParms.h:47`): fine, reset timers. `600 <= d < 1000` ("gray"): start a 10 s lost timer; the first time, **release the slot and reacquire one at the back of the queue**; fail after 10 s or if no slot. `d >= 1000`: fail immediately. Failure -> Brain picks idle scan then Free. Free Pikmin have their own tighter distances (200 / 800) used in the Free state for ownership.

Speed: running `getSpeed(1.0)` = `Parm.RunSpeed` 120 for leaf, bud 140, flower 170 (`piki.cpp:634-660`); partial speeds interpolate between walk (84) and run. Leader 160. So followers are slower than the leader on leaf and faster on flower, and the formation stretches or tightens through the plate's own geometry, not through speed matching.

Pikmin 1 (`pikmin/src/plugPikiKando/aiCrowd.cpp:233-530`) is the same algorithm almost line for line (ActCrowd): same bands (7 / 15 / 60), same trip roll (0.9999), same side impulse, same slip/break ranges (600 / 1000, `PikiMgr.h:82-84`), same 10 s lost time. Differences: lost follower also gets an async path-find to the leader (`initRouteMove`, `exeRouteMove`); idle followers play a "bored" select action after the leader has stood still `mPikiImpatienceTime` 8 s; P1 has no footmark trail.

### P1's other formation system (`formationMgr.cpp`)

A separate, unrelated `FormationMgr` (not the squad) with swappable **arrangers**: Circle, Pyramid, Line, Wing (`formationMgr.cpp:~340-520`). Each arranger fills up to 300 `FormPoint`s (local x/z offsets) at init. Members get a point by **priority** (`getFormPoint`, `formationMgr.cpp:115`): a lower-priority member already holding a point gets bumped back ("slide") when a higher-priority one arrives. `getFormationPri()` is per creature. The group rotates with the leader and the points rotate with it. Used for non-squad cases (the follow in demos and `ActFormation`). It is the cleanest example of "leader chooses a formation type; slots are data".

## 3. Whistle, call, dismiss

- **Whistle** (`naviWhistle.cpp`): a cursor circle on the ground, `mNaviOffsetVec` clamped to 100 from the leader, moving at 300/s. While held, the radius **grows linearly over `mMaxCallTime` 0.45 s from 5 to 90** (200 with the upgrade) (`naviWhistle.cpp:143-190`), then the whistle ends and fades over 1 s. Each frame the whistle is active `Navi::callPikis` (`navi.cpp:1602`) sphere-queries the spatial grid at (cursor, current radius) and sends `InteractFue(isNewToParty=true, combine=false)` to every Pikmin in it. Idempotent because already-formed members are rejected by `actPiki`. Cost is only the active whistle's cell query.
- **Call reaction**: whistled Pikmin go to LookAt: wait a random 0-0.3 s (`pikiState.cpp:1366`), play a "notice" animation, then start Formation with the leader (`pikiState.cpp:1385`). The random delay makes a crowd not snap in unison.
- **Touch to join**: a Free Pikmin touched by the active leader gets the same message (`ActFree::collisionCallback`, `aiFree.cpp:153`), after a rumble. Same reaction path.
- **Dismiss** (`Navi::releasePikis`, `navi.cpp:1955-2090`): sends `InteractKaisan` to the other leader's party, collects all releasable members, **groups by type**, computes each type's centroid and a spread radius `sqrt(n) * 6.25`, then relaxes the centroids four times so groups don't overlap the leader, the other leader, or each other (push out until separation >= 20). Each Pikmin receives its group's centroid as a "gather" target in a `Free` action: walk at 0.6 speed until inside 0.6 x radius or 5 s elapsed, then wait (`ActGather::exec`, `aiPrimitives.cpp:1778`; `aiFree.cpp:72`). Result: separate piles per type that stand a respectful distance from the leader. 60-frame disband timer blocks re-dismissal.

## 4. Idle (Free) behaviour

`ActFree` (`aiFree.cpp`): on entry drops the leader reference, sets a "pastel" look (idle visual marker), shows a radar blip. Each frame: zero velocity, try `invokeAIFree` (job scan), if nothing: decrement a delay timer; when it reaches 0, each frame 50% chance to start `ActBore` (idle animations). Post-gather delay is 150 + rand(30) frames; post-bore delay 90. Scan finding something aborts the bore. Pikmin do not wander.

## 5. Idle auto task selection and target scoring

One function does it: `Piki::graspSituation_Fast` (`pikiAI.cpp:33-300`; the slow all-list version is dead code, `pikiAI.cpp:307`).

- **Gate**: skipped during cutscenes (wild Pikmin exception); `mPikiUpdateContext.updatable()` throttle (section 7).
- **One spatial query**: sphere radius **300** around the Pikmin through the cell grid. Each object is classified by type; each category has its own range, and the search keeps the **single closest** across all categories (`minDist` starts at 400; every branch compares to the shared `minDist` and updates it). So priority between categories is purely distance, not a ranking table; categories differ only in their allowed maximum:
  | Target | Max range | Extra conditions |
  |---|---|---|
  | Enemy (living, not flying) | 60 | height difference < 30; not in water unless Blue; `pikiAI.cpp:240-290` |
  | Pellet / corpse | 30 | has a free carry slot; not already captured; not `discoverDisabled`; not in water unless Blue |
  | Gate | 40 | not recently poisoned |
  | Bridge | 100 | workable from here |
  | Rock/geyser/clog/treasure | 30 | treasure visible (White sees buried) |
  | Plant | 30 | alive |
  | Drowning Pikmin (Blue only) | 140 | |
  | Rival Pikmin (versus) | 70 | different team, not already fighting |
  Distances use sphere-to-sphere (`calcSphereDistance`) or a per-object "work distance" (to the nearest working edge), so a big object is reachable from further than its centre.
- **No scoring weights, no value**: nothing about reward, danger, or crowding. Danger avoidance is implicit: the enemy range is only 60 and Pikmin never path to enemies that are flying/underground.
- **Result**: `Brain::start(action, arg)`; for pellets, `Action::init` of Transport then picks its slot (section 6).
- **P1** (`pikmin/src/plugPikiKando/piki.cpp:901-1260`): same idea. Enemy range `mIdleAttackSearchRange` = 100 (`PikiMgr.h:90`) with `roughCull` pre-reject; per-category passes with separate bests, then arbitrates by a fixed order (enemy first, then rescue/mushroom, then map objects); `minDist` initial 12800. Fully scanned the object lists per Pikmin, which is why P2 uses the grid.
- **Boredom memory (P1)**: `TopAction::ObjBore` (`aiAction.cpp:520-560`) keeps up to 5 recent object IDs with a boredom value 0..1; maxed-out objects are ignored by idle choices. A cheap anti-oscillation device.

## 6. Group carry (`ActTransport`, `ActPathMove`, Pellet)

### Required count and slots

- Each carryable has `min` and `max` carrier counts from its config (`pelletMgr.cpp:831-853`, slot count = max, at most 128, `pelletMgr.cpp:797`). Purple counts as **10** carriers for the count (`PikiMgr::getColorTransportScale`, `pikiMgr.cpp:496`; `Pellet::getTotalCarryPikmins`, `pelletMgr.cpp:2007`).
- **Slots are a ring**: slot i is at angle `i * 2pi / slotCount + angleOffset`, radius = the object's configured pick radius, height by which face is down (`pelletMgr.cpp:2102-2140`). Free slots are tracked as a bit set. A Pikmin takes the **nearest free slot to where it stands** (`getNearFreeStickSlot`, `aiPrimitives.cpp:259`). The very first carrier takes slot 0 and the **whole ring rotates** so slot 0 is on the side that Pikmin walked up from (`mAngleOffset`, `aiPrimitives.cpp:309-318`), so the first arrival never has to walk around.
- Approach: `ActGotoSlot` (`aiPrimitives.cpp:247`) walks straight to the slot, checks it has not "stuck" within 40 units (60 frames without arriving = fail), grabs at <= 6 units and < 20 vertical, attaches (`startStick`).

### Handshake and lift

1. `ActTransport` state SLOT -> LIFT -> MOVE (`aiTransport.cpp:96-215`).
2. LIFT: each carrier plays a looping pick animation and marks itself "lift ready" on an animation key. Carrying capacity is the sum of ready carriers' scale; the lift commits when the Pikmin's own ready flag is set **and** total ready >= `min` (`execLift`, `aiTransport.cpp:295-335`). If under `min`, each pick-loop end decrements a random 5-8 loop timer; at zero the Pikmin gives up (Fail -> idle scan). Under-staffed pellets therefore attract extras for a few seconds, then disperse.
3. MOVE: if total carriers drops below `min` mid-carry, the Pikmin fails, the pellet's velocity is zeroed (`aiTransport.cpp:140-150`).

### Who owns the path

Only the **first Pikmin stuck to the object** (found by walking the sticker list, `isStickLeader`, `aiTransport.cpp:260-280`) runs `ActPathMove`. All others merely ride the attachment, doing nothing in `exec` except checking that they are still stuck and exiting with Success when the carry ends. Path cost per object, not per carrier. Ownership is re-evaluated every frame: if the owner leaves, the next stuck Pikmin in the sticker list sees `isStickLeader()` true and starts the path move itself (`aiTransport.cpp:150-175`).

### Moving the object

- `ActPathMove` (`aiPrimitives.cpp:630-1300`): requests an async pathfinder job over the waypoint graph from the nearest open waypoint to the goal's waypoint (flags: must be open, not unfinished bridges; **all-Blue crews may path through water**, `isAllBlue`, `aiPrimitives.cpp:1325`). While waiting it sets zero pull.
- Moving along the waypoint path as a Catmull-Rom spline through successive waypoints, each with a **corridor radius** (`crMove`, `aiPrimitives.cpp:1305-1410`). If the object drifts from the spline by more than 30% of corridor width, a steering term back to the centre line is blended in proportionally (weights `1-comp` tangent, `comp` correction); beyond 2x width and 130 units away, it does nothing and hopes. Advances waypoint when within 6 units of the next control point. In the last stretch (`execMoveGoal`, `aiPrimitives.cpp:805`) it heads straight at the goal and releases everyone when within 10 units.
- Blocked waypoint (gate closed, bridge not built): enters a pacing mode orbiting a point 160 units short, at half speed (`execMoveGuru`, `aiPrimitives.cpp:966`). Wall stuck (wall timer > 99 frames and moved < 1): blacklists the starting waypoint link and re-paths (`aiPrimitives.cpp:920-940`).
- Pathfinding rechecks are triggered by context change (versus mode), not by timer.

### Speed formula (`getCarrySpeed`, `aiPrimitives.cpp:771-800`)

```
maxSpeed = RunSpeed * 0.7      (84)
minSpeed = RunSpeed * 0.35     (42)
power    = sum over carriers of (1.0, +0.5 bud, +1.0 flower; purple 0.5, white 1.5)
speed    = minSpeed + ((1 + power - min) / max) * (maxSpeed - minSpeed)
```
Roughly linear in "carrier power above the minimum", normalised by the max count. Special-cased: carrying a leader or a versus cherry = full run speed. The carried object is moved by setting its velocity, not by the Pikmin moving; the carriers' own bodies are glued to their slots.

### Contested carry

`PelletCarry` (`pelletCarry.cpp:30-70`) holds one "pull" at a time: a state, a velocity and a strength. A new puller with **strictly higher strength** (total carry power) steals it and the object freezes 0.5 s (`mTimer`); equal or lower is refused, and the loser's `pull` returns false, so its Pikmin drops the object (`endPick(false)`), then fail -> idle scan. This is how a pile of Pikmin and an enemy tug the same object. Used also with enemy carriers.

### Where it goes

Non-treasure pellets: the goal home is the base of the **plurality colour of the current carriers** (ties broken at random), recomputed when pathfinding is (re)initialised (`getPelletGoal`, `pelletMgr.cpp:1939`). `InteractSuck` at the goal consumes the object.

## 7. Attack

- **Choosing**: idle scan (section 5) or contact while swarming; arg is the target creature (+ optional collision part).
- **`ActAttack::init`** (`aiAttack.cpp:51`): already latched -> stick attack; else 20% "jump adjust", 80% "adjust".
- **Adjust** = `ActApproachPos` to the target's body sphere with extra standoff 10, elastic speed (`aiAttack.cpp:73-98`; `aiPrimitives.cpp:104`): if closer than the radius, back up at half speed (`-0.5`); if farther than radius + 6, move at `0.5 + 0.5*min(1, 0.01*d)` of run speed (far = faster); between: stop and finish when facing within 18 degrees. Also fails if vertical gap > 20. The Pikmin keeps re-reading the target's current position each frame (`aiAttack.cpp:227`), so it tracks a moving target.
- **Jump adjust**: the same approach with a 2 s timeout, then a hop with fixed velocity (100 horizontal, 200 up) toward the target (`initJump`, `aiAttack.cpp:107`). On the collision callback with a stickable part it latches (`startStick`). Landing without hit resets to Adjust.
- **Stick attack** (`ActStickAttack`, `aiPrimitives.cpp:1478`): once latched to a collision part of the enemy, plays the attack animation and fires one `InteractAttack(damage, part)` per animation cycle on a key event; the enemy's `stimulate` returns whether it hurt (a miss plays a whiff effect). Wild (never-owned) Pikmin deal 0 damage. Ends Success when the enemy dies; Fail if it fell off or the animation ended unexpectedly; the Attack action then re-adjusts (`aiAttack.cpp:230-240`).
- **Target lost to flying/underground**: switches to a search animation (50/50 of two) and then Fails (`aiAttack.cpp:200-225`).
- **No explicit crowd limit on a target**: every nearby free Pikmin adds itself; spacing comes from latching onto distinct collision parts and from stickability. Damage per hit is per colour (Red 15, others 10; poison/flower adds).
- Dying Pikmin and other negative states are state-machine matters, not brain: knockdown (`Flick`), blow (`Blow`), crush (`Pressed`); their `exit` calls the idle scan again and, if the leader is within range, a rejoin (`pikiState.cpp:2593`, `2808`).

## 8. Panic / flee

`PikiPanicState` (`pikiState.cpp:838-1150`). Types: fire, water, gas, generic. The body takes over entirely (brain suspended): picks a heading, runs at full speed on that heading, and **re-rolls a heading change every 0.2-0.4 s** by +-30-45 degrees (alternating sign by Pikmin index parity) with a sound (`panicRun`, `pikiState.cpp:968-1010`). Fire/water/gas have a death timer `mPanicMaxTime` 3 s (+0-10%); generic panic has a short "noticing" pause (0-0.3 s + an animation) and then just ends back in Walk -> brain. The whistle can recall a Pikmin that a lure effect has taken over only if its state is Panic (`interactPiki.cpp:130-140`); other panic types are not callable by default. No pathfinding, no avoidance, fully local. Gas uses a separate "lobster" backward-scuttle. P1's `ActEscape` (`pikmin/.../aiEscape.cpp`) is the brain-level flee: run directly away from a target for 4-6 s, switching to a perpendicular "avoid" heading whenever `getAvoid` reports an obstacle.

Other fallback behaviours with no leader: P1 `ActRandomBoid` (`aiRandomBoid.cpp:107`) is a timer-driven wanderer (states Boid / Idle / Stop / Random with randomised 20-60 frame timers and an obstacle avoid vector). P2 has none; idle Pikmin stand still.

## 9. Per-frame budgeting for hundreds of units

- **Round-robin buckets** (`updateMgr.cpp`, `pikiMgr.cpp:39`): `UpdateMgr` with 10 clients slots; each Pikmin joins the least-populated slot when spawned (`addClient`, `updateMgr.cpp:131`), the manager advances a counter every frame, and `updatable()` is true when the Pikmin's slot equals the counter (`updateMgr.cpp:98`). Gated this way: the idle job scan (`invokeAIFree`, `pikiAI.cpp:840`) and the head-look query (`piki.cpp:1352`). So each idle Pikmin scans once every 10 frames; with 100 Pikmin about 10 scans per frame. A flag lets some Pikmin (thrown) force themselves always active.
- **What runs every frame regardless**: FSM `exec`, brain `exec` (cheap for formation: arithmetic only), movement/physics integration.
- **Leader-owned shared work**: slot geometry computed once per plate per frame, not per follower; the follower only reads its slot position.
- **Spatial grid** (`CellIterator`, `cellPyramid`) for every neighbour query (whistle, idle scan, pellet lookups) instead of iterating all objects.
- **Visual LOD**: `Creature::updateLOD` (`creatureLOD.cpp:39`) classes each unit by viewport visibility and screen size (Far 0.07, Close 0.02 thresholds); `doColorChange` and similar skip invisible Pikmin (`piki.cpp:1200`). AI is not LOD-skipped.
- **Pathfinding budget**: path requests are asynchronous handles with limited concurrency; only one request per carried object, none for followers (they steer directly to the slot, with the footmark crumb as the only wall fallback).
- No pairwise separation steering: crowding is solved by slot geometry, the side-impulse around the leader, and rigid body collision.

## 10. What Corruption could take

Existing code referenced: `minion_actor.gd`, `states/chase_state.gd` (nav agent + RVO, stuck detection), `states/minion_state.gd` (`find_hostile_target`, scan throttle 0.25 s + 100 ms stagger, `MAX_VERTICAL_REACH` 4, ignore list), `scripts/minion_manager.gd:554` (`_assign_formation_waypoints`, static grid of waypoints set once per order), `scripts/groups/group_manager.gd` (group tick 0.25 s, centroid-based progress, `goal_handlers`), `scripts/groups/field_work.gd` (one body per unit, nudged by `waypoint = body.position`), `docs/systems/minion-ai.md` (proposed `MinionBehavior` resource). These are options for the designer; none is a recommendation.

### A. Layer split: body states / task actions / primitives
- **What**: keep the existing `RewindableStateMachine` for physical conditions (idle, chase, jump, death, stagger); add a task layer with a Success/Continue/Fail result and a "what next" hint on finish (rejoin leader, go idle, rescan).
- **Maps to**: the proposed `MinionBehavior` in `minion-ai.md` is the task layer. The finish rule (after Success/Fail: try nearby job, else rejoin leader, else idle) is the part not yet in that doc. `GroupManager.goal_handlers` are already "actions at group scale" returning done-or-not.
- **Trade-offs**: cheap and testable; a single current task (no stack) is simple but loses "return to what I was doing", which P1's `mActionState` (0/1/2 = always rejoin / rejoin if near / go idle) patched with a per-job flag set by whoever started it.

### B. Interactions as typed messages with state veto
- **What**: one method `stimulate(Interaction)` on the actor; subclasses (`Hit`, `Whistle`/recall, `Scare`, `Capture`, ...) implement per-receiver-kind handling; the current state answers "can I take this" (`callable`, `invincible`, `releasable`).
- **Maps to**: `take_damage` plus ad hoc `ignore_target`; could be a `RefCounted` hierarchy with `act_minion(m)`, `act_human(h)`, `act_body(b)`.
- **Trade-offs**: removes `if state == X` scattered through senders; costs an allocation per message (use pooled/immutable objects, or plain `Dictionary` for rare ones).

### C. Leader-owned slot plate instead of one-shot waypoints
- **What**: the group (or its leader) owns an ordered slot list; each frame it computes the slot offsets from (n, heading, spread) and pushes only a slot *index*; followers read `plate.slot_position(index)`. Slot list order = priority; leaving shifts everyone down and notifies; join goes to the back; periodic distance re-sort.
- **Maps to**: replaces `_assign_formation_waypoints` (static, snapshot). New `FormationPlate` RefCounted in `scripts/groups/`, owned by `UnitGroup`; slot update inside `GroupManager._tick_group` or each physics frame. Followers keep `minion.waypoint` semantics: set `waypoint = plate.slot(i)` only when the slot moved more than `REPATH_DISTANCE` (ChaseState already re-paths on that).
- **Shape generators**: disc-packed rows with chord widths for a ball/blob (section 2); P1 has circle, pyramid, line, wing "arrangers" as pure functions n -> offsets (`formationMgr.cpp`). Which shapes exist and which a leader can use is a design matter (maneuver content is Austin's, #581); the mechanism only needs "shape = function(n, params) -> offsets".
- **Priority bump** (P1): slot goes to the higher-priority creature, bumping the occupant back, giving "veterans toward the front" or "heavy units first" for free from a single integer.
- **Trade-offs**: per-frame cost O(n) per group, not per unit; nav targets move every frame (needs the hysteresis in D). Networked: send plate params + heading, not n positions (the minion sync is already unreliable position broadcasts).

### D. Follower movement bands (cheap, no RVO)
- **What**: stand (<= ~0.6 body-lengths of slot, dead-band), brake (< ~1.2: speed from `v = 0.5*sqrt(v^2 + 8*a'*d) + v`), full speed otherwise; face the leader when standing; sideways nudge by slot parity when between leader and plate; a counter (6 frames) to stop flicker at the dead-band edge.
- **Maps to**: `chase_state.gd` currently relies on `NavigationAgent3D.set_velocity` (RVO) and an elaborate "stuck means arrived" backup (`STUCK_*` constants, path-end commit). Close to the slot, replace nav + RVO with direct steering; keep nav for far.
- **Trade-offs**: removes much of the orbit/pile-up handling in `chase_state.gd`; loses avoidance of terrain unless the slot is snapped to the navmesh (already done by `_snap_to_navmesh`). Tune numbers (7 / 15 / 60 in P2 units) as playtest items.

### E. Catch-up and lost followers
- **What**: two radii (slip, break) and a lost timer: inside slip all fine; between: once, give up the slot and re-queue at the back, start a timer; beyond break or timer elapsed: leave the formation (to idle, or to "find a leader"). P2 also gives footmark-trail steering when a wall blocks.
- **Maps to**: `GroupManager` stall detection is group-level (`STALL_SECONDS` 8); per-member lost handling does not exist. A leaver could become a straggler that auto-rejoins the nearest friendly group's plate within a search radius (P2: nearest leader within 300). `_halt` / "stuck" status already models the group going confused.
- **Trade-offs**: makes dispersal a gameplay-visible mechanic; "lost" units need a defined fate (design, not decided here). Breadcrumb trail is cheap (ring buffer of leader positions every N metres) and is a deterministic detour substitute for per-unit path queries.

### F. Dismiss/rest grouping
- **What**: on release, group by unit type, centroid per type, radius = k*sqrt(n), push groups apart by iterating a few relaxation passes, each unit walks at reduced speed to its group's circle, stops after a timeout.
- **Maps to**: `_arrive` / `holding` state at a destination; right now units stand at their grid slot. A pile-per-type resting layout is the P2 version.
- **Trade-offs**: purely cosmetic/readability for a low-info game; `get_centroid` already exists.

### G. Idle scan: budget and range model
- **What**: replace `get_tree().get_nodes_in_group(&"actors")` scan (O(all actors) per unit) with a spatial query and per-category max range, nearest wins; stagger by buckets (id % 10 against a frame counter) instead of timers.
- **Maps to**: `MinionState._scan_for_target`. Options: (1) `Area3D` on each unit (physics cost), (2) a shared uniform grid dictionary maintained by `MinionManager` (cell = ~aggro_radius), (3) `PhysicsDirectSpaceState3D.intersect_shape` with a mask (one call per scan).
- **Trade-offs**: the 0.25 s timer + random stagger already approximates the bucket idea; buckets give a hard cap per frame, timers a soft one. P2's category table (different ranges for enemy, body, pickup) is easier to tune than one `aggro_radius` for everything.

### H. Auto-pickup of bodies by idle undead
- **What**: P2 pellets are claimed by whichever free Pikmin is nearest within a small range (30) with a free carry slot; swarming (contact with leader) lets squad members pick things up out of that range. Idle pickup is "nearest object in category range that still has a free slot and is not claimed".
- **Maps to**: `FieldWork._gather_dead` today is order-driven: within `WORK_RADIUS` 20 of the destination each unit sets `waypoint` to the nearest free body and picks it up at 2 m. Options: (1) keep it order-driven; (2) add a small-range opportunistic pickup for idle/holding units; (3) per-body reservation to prevent two units claiming the same body.
- **Trade-offs**: (2) makes holding groups helpfully tidy but spawns work no order asked for; with a low-information design this may read as noise. (3) is needed under any option when two units race (today `free.erase(b)` handles it within one handler call).

### I. Multi-carrier objects
- **What**: payload has `min`/`max` carriers; slots on a ring; first arrival rotates the ring; nearest free slot; lift handshake (each ready; commit at >= min; give up after random 5-8 s if short); only one carrier ("path owner") navigates and drives the payload; the rest are parented to it; speed = lerp(min_speed, max_speed, (1 + power - min)/max); payload drops if carriers fall below min; contested pull = higher total strength wins and the loser drops.
- **Maps to**: `MinionActor.carrying` is currently solo (`set_carrying`). A heavy/living captive could be a `Carryable` node with `slots`, a `CharacterBody3D` the owner nav-agent drives, carriers as children (so per-carrier navmesh cost is zero), carrier "power" a stat on `MinionType`. The existing rule "hurting the carrier hurts the captive" would be a share of damage routed through the carrier's slot.
- **Trade-offs**: big new surface (slots, handshake, owner hand-off, networking of attachments); whether any payload needs more than one carrier is a design question for Austin. The minimal cut is sections "path owner" + "speed from count" only.

### J. Latching attack vs standing melee
- **What**: approach with elastic speed to standoff, optional jump, then attach to a part of the target and attack in place; attackers occupy different parts so no ring spacing is needed.
- **Maps to**: `attack_state.gd` / `chase_state.gd` (`ENGAGE_MARGIN` comment: RVO held chasers 2.4 m out). Latching would sidestep that class of bug (units stay attached; attack = animation event). Needs hurt-box parts on humans/enemies and kinematic parenting.
- **Trade-offs**: heavy on animation/hitbox data; may feel wrong for ranged or cavalry-like units. Elastic approach (`0.5 + 0.5*min(1, 0.01*d)`) is a drop-in for chase speed without any latching.

### K. Panic as a body-state
- **What**: a fully local state that overrides the task layer: pick a heading, run, re-roll heading ±~30-45° every 0.2-0.4 s, per-instance parity for left/right, a timer, no pathing; a recall may or may not interrupt (design choice); ends by returning to the task layer.
- **Maps to**: `retreat_state.gd` is purposeful (navigate to spawn marker). Panic is a different, cheap state (no nav). A morale-type trigger is a design question.
- **Trade-offs**: very cheap for hundreds of units; looks chaotic by design; needs terrain/edge protection since nothing paths.

### L. Throttle and bucket rules that carry over
- Gate expensive per-unit work by a bucket (round-robin counter), but let units in important states (thrown, fighting) force-active.
- Compute shared work once at the leader (slot positions, dismiss layout).
- One path request per payload, not per carrier; steer followers directly.
- Turn off RVO for followers inside the formation (nav `avoidance_enabled`), rely on slot geometry + the side nudge.
- Tie `MinionActor._observe` (0.25 s) and the group tick (0.25 s) to the same bucket scheme if profiling shows spikes.
- **Trade-offs**: all are profile-first; the repo's `get_nodes_in_group` scan is the first suspect at hundreds of units.

### M. Recall radius growth (only if any direct command exists)
- **What**: the call radius grows from small to max over ~0.45 s; units notice after random 0-0.3 s then play a short animation before joining.
- **Maps to**: nothing today (orders go through couriers; there is no direct hail). Mention only if a short-range "rally" on a group leader is wanted: the leader is an AI actor, so the "whistle" becomes a leader pulse to its own group or to stragglers. The random notice delay is the part that makes a crowd read as individuals.

## 11. Open questions

- Which of the defaults in `PikiParms.h` / `NaviParms.h` are overridden by game data files is not visible in the decomp (the parameter classes load from text at runtime), so the constants here are defaults only.
- The decomp's `Navi` plate is tuned for a player-driven stick (direction, strength, held time); Corruption's leaders are AI and give orders via couriers, so what stands in for "stick direction" (route heading, order, or fight state) is a design choice, not something the source answers.
