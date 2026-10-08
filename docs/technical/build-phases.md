# Build Phases — MVP-First Iteration

**Philosophy:** Each tier is a playable game with a win condition. Social and Overlord tools come before combat polish — 3 out of 4 players are always Overlords, so their experience matters most. Debug tooling is first-class, not an afterthought. Greybox everything — art comes last.

This file tracks the **tier history and standing test checklists**. The forward plan is **`mvp-roadmap.md`** (sibling file, created 2026-06-10). Completed-work detail, verification records, and design-call history live in `changelog.md`. War-table build steps + phase plan: `docs/systems/war-table.md`.

> **▶ FORWARD PLAN MOVED (2026-06-10):** what-to-build-next now lives in **`docs/technical/mvp-roadmap.md`** (Path to MVP). This file keeps the tier history and the standing test checklists — they still gate the roadmap's M0. Test state: possession Phases A–C implemented; the 2026-06-09 smoke pass confirmed the loop (flag removed) but the **formal checklists are unticked** — run **`docs/technical/test-plan-corruption-avatar.md`**, then tick the Phase A/B/C + gem-site boxes below. Open repro hunt: an avatar war-table order once produced no courier; dispatch now logs `[KnowledgeManager] Courier N dispatched…` so the next failure names its stage.

## Progress Tracker

| Tier | Name | Win Condition | Status | Playable? |
|------|------|---------------|--------|-----------|
| 0 | The Board is Set | Walk to gem | **Complete** | Yes |
| 1 | The Tower is Alive | Walk to gem (with social tools) | **Core complete** | Yes |
| 2 | Blood on the Ground | Fight to gem (combat + transfer) | **Complete** | Yes |
| 3 | The Dark Lords Scheme | Beat guardian boss (minions + gem sites) | **Impl complete** — war-table layer verified 2026-06-05; rest needs testing | Yes |
| 4 | Corruption Has a Face | Full 2-boss endgame + factions | **Impl complete** — altars/circles verified; rest blocked on editor setup | Ready to test |
| 5 | Polish & Content | Complete game | Not started | - |

---

## Tier 0: The Board is Set [COMPLETE]

**Win condition:** Avatar walks to the gem in the Capitol and interacts with it.

Done: P2P lobby + faction selection, 4 towers spawning Overlords, shared Avatar entity with claim/transfer and synced movement, gem win interactible, win screen → lobby flow, F3 debug overlay, F2 dummy players.

Open:
- [ ] **Debug console** — Key commands: force Avatar transfer, teleport, spawn at location

## Tier 1: The Tower is Alive [CORE COMPLETE]

**Win condition:** Same as Tier 0, but Overlords can watch and talk about it.

Done: greybox tower interior with E-interactible stations, Palantir (watch Avatar via SubViewport, watched-cue), Mirror (pose + mic recording with reverb, send/playback per Overlord), balcony overlooking the map, voluntary Avatar recall.

Open:
- [ ] **Mirror playback inspector** — Debug panel showing recorded messages, timestamps, recipients
- [ ] **Palantir force-activate** — Debug command to enable/disable Palantir without walking to it

## Tier 2: Blood on the Ground [COMPLETE]

**Win condition:** Fight through neutral enemies to the gem; on death, the next player gets a turn.

Done: committed melee attack with stamina + animation-driven hitboxes, HP/damage/death, neutral enemy AI (patrol/aggro/attack), Avatar death → transfer with full mode-swap cycle (round-robin at the time; replaced by the possession model 2026-06-09), host-authoritative combat sync via rollback. (The Tier 2 EnemyManager was later absorbed: neutral enemies are NEUTRAL-faction minions via `MinionManager.spawn_neutral_minion`.) Debug: god mode (F4), spawn enemy (F6), kill Avatar (F5), spawn minion (F7), +corruption (F8).

## Tier 3: The Dark Lords Scheme [IMPL COMPLETE]

**Goal:** Overlords project power onto the map. Minions exist. Gem sites matter. Corruption determines who gets the Avatar.
**Win condition:** Reach the gem and defeat a single guardian boss, debuffed by total corruption.

> **Corruption model (changed 2026-06-05):** the old per-player "influence" score was renamed **Corruption**, and the grid-based territory system was removed. Corruption is earned ONLY from held gem sites (0.5/s trickle). Per-player corruption decides Avatar succession; the summed total debuffs the Guardian Boss; holding zero sites runs the divine-intervention loss timer.

Done (war-table command layer **verified 2026-06-05** — see changelog): minion spawning via Summoning Circle slots, per-tower spawn/rally markers, minion AI state machine, War Table single-shot-E command flow (draft → readied → dispatched), Advisor handoff + batched couriers, info-couriers, broadcast-range belief model with staleness badges, reality overlay, belief privacy, client-peer parity.

Done (impl complete, **not yet verified**): corruption tracking, gem sites, hostile takeover, corruption fallback, guardian boss, astral projection — see Testing TODO.

## Tier 4: Corruption Has a Face [IMPL COMPLETE]

**Goal:** Factions feel different in both modes.
**Win condition:** Two back-to-back bosses; divine intervention lose condition active.

Done (verified 2026-06-05): Summoning Circle + Upgrade Altar slot-based flows incl. client purchase RPC. Done (impl complete, not yet verified): faction rosters/abilities/Overlord tools, Undeath raise-dead, two-boss endgame, divine intervention — see Testing TODO. (Eldritch ritual stations were CUT 2026-06-10 — never part of the original plan; code + data deleted.)

Open:
- [ ] **Neutral faction detection asymmetry** — Nature/Fey stealth past priests
- [ ] **Balance dashboard** — Faction win rates, average corruption, minion efficiency

## Avatar Possession Rework [PLANNED — design locked 2026-06-05]

Cross-tier change: the Avatar becomes an optionally controllable minion (ownership/control split, neutral start, no round-robin, full minion AI when released, war-table pawn, corruption-fed upkeep gauge). Full design + phasing: `docs/systems/avatar-possession.md`. **This is the default avatar model as of 2026-06-09** — the `AVATAR_AS_MINION` flag and the legacy hot-seat path were removed after first hands-on testing.

- [x] **Phase A** — ownership/control split, neutral start, Q = release-keep-ownership, death rules (impl 2026-06-05, untested)
- [x] **Phase B** — host-driven AI brain (input synthesis via `before_tick_loop`) (impl 2026-06-05, untested)
- [x] **Phase C** — war-table pawn + command routing (reserved `AVATAR_ID` in KnowledgeManager) (impl 2026-06-09, untested)
- [ ] **Phase D** — upkeep gauge (drains over time, fed by corruption income, empty → neutral)

#### Phase A testing (default behavior — F3 shows the Owner | Controller line)
- [ ] Claim at tower → own + possess in one step (F3: Owner = Controller = you)
- [ ] Q → release: overlord body resumes, avatar stands in the field in YOUR faction, F3 Controller = "released"
- [ ] Claim station now reads "possess your Avatar"; re-possess works
- [ ] Re-possessing does NOT heal the avatar (take damage, Q, re-possess, check HP)
- [ ] Released avatar is damageable; minions aggro it
- [ ] Kill Avatar debug button (= neutral kill) → ownership reverts to neutral, dormant husk, claimable again
- [ ] Hostile takeover (2-peer/dummy): rival minion kill → rival gains OWNERSHIP, nobody auto-possesses, rival can possess at their tower
- [ ] Own-minion kill (friendly fire) does NOT transfer ownership

#### Phase B testing (AI brain — host session, avatar claimed then released with Q)
- [ ] Released avatar stands idle; "Spawn Enemy at Camera" within ~10m → avatar aggros, chases, melees it dead
- [ ] Avatar returns to idle after the kill (no twitching/spinning — watch the model facing)
- [ ] "Order Avatar to Camera" → avatar runs/walks to the point, fighting hostiles en route, stops on arrival
- [ ] Possessing mid-AI-fight takes over cleanly (AI orders void); Q hands back to AI
- [ ] 2-peer: client sees the AI avatar move/attack smoothly (input syncs from host authority)
- [ ] AI avatar killed by spawned enemy (neutral) → ownership reverts; by rival minion → rival owns
- [ ] Rollback sanity: no rubberbanding on the controlling client when possessing right after AI control

#### Phase C testing (war-table pawn — avatar claimed then released with Q)
- [ ] Released avatar appears on the owner's war table as a distinct oversized piece with "AVATAR" badge, faction-tinted
- [ ] Piece prompt reads "[E] select Avatar"; E toggles selection (yellow tint)
- [ ] Select avatar → E on empty map → draft arrow appears; Paper → Advisor dispatches a courier; courier reaches the avatar → avatar walks to the target
- [ ] Same flow with `INSTANT_COMMANDS` ON (T in test harness / debug toggle) → avatar moves immediately on map click
- [ ] Mixed selection (avatar + minions) → one draft; all units arrive at the target
- [ ] Avatar piece is NOT selectable on a rival's table (renders as enemy piece, no prompt)
- [ ] Possessing the avatar voids pending AI orders (clear_orders); the piece stays on the board while possessed
- [ ] Avatar dies / reverts to neutral → piece disappears from all tables; reappears on re-claim
- [ ] With `INFINITE_BROADCAST_RANGE` OFF: owner always sees own avatar; rival's table only shows it within broadcast range of rival units (stale "?" when out of range)

## Tier 5: Polish & Content [NOT STARTED]

- [ ] **UI/UX pass** — HUD, faction-themed menus, corruption display
- [ ] **Audio** — Combat, ambient tower atmosphere, faction themes, Mirror reverb tuning
- [ ] **Art pass** — Replace greybox with final assets
- [ ] **Balance pass** — Faction tuning, boss difficulty, match pacing, divine intervention timing
- [ ] **Additional maps** — Second hand-crafted map with different balance (asymmetric start positions)
- [ ] **All 4 factions fully implemented**
- [ ] **Progression/loot system** — Gear, skills, Avatar power growth within a match

---

## Editor TODO — Nodes to Add in Scenes

Scripts are implemented but these nodes/scenes need to be created or wired up in the editor before testing.

### Tier 3

- [x] `GemSite` ×3 placed in `world.tscn` (2026-06-05) — scene root, ~30-40m ring around the Capitol. QoL: all three still have the default `site_name = "Gem Site"` (prompts are indistinguishable); optionally reparent under `World/Interactables/`
- [x] `GuardianBoss` — instanced at `World/Enemies/GuardianBoss` near the Capitol. (Phase-2 boss `corrupted_seraph.tscn` is an inherited scene — no script override needed.)
- `AstralProjection` — **DEFERRED 2026-06-10**: boss-room activation isn't ready; MVP uses a HUD notification ("the Guardian is under attack — scry to watch") + Palantir instead. The pre-built `scenes/astral_projection.tscn` stays on disk for later.
- [x] `MinionManager` node at game-scene root (verified in `world.tscn` 2026-06-10). No `EnemyManager` exists anymore — neutral enemies spawn through `MinionManager.spawn_neutral_minion` as NEUTRAL-faction minions

### Tier 4

- [x] `BossManager` (Node, scene root) — placed 2026-06-10 (Austin); `initial_boss` wired to `World/Enemies/GuardianBoss` via tscn edit — verify in-editor. Optional: `seraph_spawn_point` (defaults to initial boss position), `seraph_scene` override (defaults to `corrupted_seraph.tscn`)
- [x] `DivineIntervention` (Node, scene root) — placed 2026-06-10 (Austin)

Placed already: `WarTable` + `WarTableRange` and `UpgradeAltar` in `tower.tscn` (tune `map_world_center`/`size` per tower once per-overlord AOs are designed; reposition altar to taste).

---

## Testing TODO — Verify In-Game

Implementation-complete systems not yet confirmed in a live session. Items marked **[blocked]** depend on Editor TODO entries above. The war-table command layer, advisor/courier loop, summoning slots, and upgrade-altar flow were all verified 2026-06-05 — records in `changelog.md`.

### Tier 3

#### Corruption tracking
- [x] "+10 Corruption" pause-menu button bumps the local peer's score live in the F3 overlay (verified 2026-06-05)
- [ ] All peers' corruption + total visible in F3 panel (multi-peer session)
- [ ] Corruption persists across Avatar transfers within a match
- [ ] GuardianBoss debuff scales with total corruption (cross-check with boss panel)
- [ ] Held gem site regens 0.5/s corruption to the holder, stopping at max (Σ held-site contributions)

#### Minor gem sites (contest-gated capture, reworked 2026-06-05)
- [ ] Uncontested NEUTRAL site: Avatar holds E and captures — no friendly minions required
- [ ] Hostile minion (other faction or neutral) within `contest_radius` blocks capture; prompt reads "contested"
- [ ] Hostile arriving mid-channel breaks the channel
- [ ] Channel completion starts corruption regen for the capturing peer
- [ ] Regen stops at max corruption (one site → climbs to 7 and holds; F3 shows `current / max`)
- [ ] Holding a second site raises the max AND the combined regen rate
- [ ] Capture state syncs to all peers
- [ ] F3 "Gem Sites" panel shows held/total count
- [ ] Harness `capture_channel_test.tscn`: [2] spawns a hostile at the site → contest gate + channel break

#### Hostile takeover
- [ ] Minion (with kill credit) damaging Avatar to 0 HP triggers takeover
- [ ] That minion's owner becomes Avatar; previous Avatar peer returns to Overlord
- [ ] Camera/input swap completes cleanly on both peers
- [ ] Works distinctly from neutral-kill case (does NOT fall through to corruption fallback)

#### Corruption fallback
- [ ] Avatar dies to a neutral enemy (no owned minion in kill credit)
- [ ] Highest-corruption peer takes over as Avatar
- [ ] Tiebreak between equal-corruption peers is deterministic
- [ ] Mode swap mirrors the hostile-takeover transfer

#### Guardian boss
- [ ] Boss spawns at the placed location
- [ ] HP/damage scaled by total corruption (debuff visible in F3 boss panel)
- [ ] Avatar attacks land; boss attacks reduce Avatar HP
- [ ] Boss death triggers Tier 3 win condition

#### Astral projection — **[DEFERRED 2026-06-10: MVP uses HUD scry notification instead]**
- [ ] SubViewport overlay auto-activates when the boss engages
- [ ] Spectator camera follows the active Avatar for non-Avatar peers
- [ ] Overlay clears on boss death / match end

#### Forced retreat + return-to-tower update — **[DEFERRED 2026-06-05: build + test later]**

Setup: flip `can_retreat = true` on a combat type's `.tres` (e.g. `data/minions/skeleton.tres`); harness has the tower binding.

- [ ] HP below `retreat_hp_threshold * max_hp` breaks combat at the next Idle/Chase/Attack tick → `RetreatState` navigates to the owner's `MinionSpawnPoint`, no aggro en route
- [ ] On arrival: `_field_log` flushes via `KnowledgeManager.flush_observations` (sightings appear on table with `source = &"return"` — visual differentiation is a polish TODO), partial-heal to 50%, back to Idle, no immediate re-trigger
- [ ] No spawn point bound → falls back to Idle, log retained for next attempt
- [ ] `can_retreat = false` types fight to the death as before; `_observe()` never logs friendlies
- [ ] Info-courier premature retreat: HP loss past its threshold mid-flight sends it home early with its log

### Tier 4

#### Faction-specific minion rosters
- [ ] All 4 factions load distinct rosters from `FactionData`
- [ ] Costs / stats / traits differ per faction (spot-check all four)

#### Faction-specific Avatar abilities
- [ ] Each faction's Avatar has its own ability set (cooldowns, damage mults, lifesteal, camouflage)
- [ ] Activation triggers the right `AbilityEffect` scene under `scenes/abilities/`
- [ ] Combat queries on `AvatarAbilities` aggregate correctly across `_active`
- [ ] `abilities.cancel(&"id")` ends an effect early

#### Faction-specific Overlord tools
- [ ] Eldritch: domination via Summoning Circle
- [ ] Demonic: single-minion direct command works
- [ ] Nature/Fey: information advantage visible in War Table / map
- [ ] Tools gated correctly — only the matching faction's overlord can use them

#### Undeath raise-dead mechanic
- [ ] Ghoul-trait kill → skeleton spawns under the killer's owner, inherits faction, behaves normally
- [ ] No skeleton from non-Ghoul kills

#### Two-boss endgame
- [ ] `initial_boss` resolves to the world's GuardianBoss; phase-1 death spawns `CorruptedSeraph`; phase-2 death wins the match

#### Divine intervention
- [ ] Timer arms after the first gem capture; zero sites held for 60s → loss screen for all peers
- [ ] Re-holding a site recovers the timer at 2× speed and clears the warning

#### Upgrade Altar — effect verification (flow verified 2026-06-05)
- [ ] **Effect: minion HP / damage** — levels feed `get_upgrade_multiplier(peer, kind)` into spawned minions
- [ ] **Effect: resource rate** — increases the buying peer's resource regen
- [ ] **Effect: avatar HP / damage** — apply when the upgrading peer is in Avatar mode

---

## Known issues / QoL backlog

Carried over from the 2026-06-05 test pass. Small, unscheduled.

- [ ] **QoL: ghost-popup auto-close should clear selection** — when the stack inspector's grace timer closes the popup, reset the selection; walking away mid-composition shouldn't leave a stale half-selection
- [ ] **QoL: pending ghosts need a disabled state** — a ghost whose member already has a pending order is filtered from selection but still lights up on focus; dim it so it reads as unselectable
- [ ] **BUG (repro unknown): order issued but no courier spawned** — observed once in the harness 2026-06-05; `issue_move_command`'s early-outs now push_warning, so the next repro will name itself. Check arrow color at failure time (red/amber/black = stage it died at)
- [ ] **Build + test `can_retreat` retreat-flush** — see the [DEFERRED] section above

## Notes

- All interactibles inherit `scenes/interactibles/interactable.tscn` (or at minimum Area3D + CollisionShape3D); every interactable is single-shot E — no modal enter/use/exit flows
- Prompts route through the `InteractionUI` autoload to the HUD RichTextLabel (no Label3D); empty prompt text hides the label
- The War Table has no camera takeover — first-person + discrete child Interactables (Piece/Ghost/MapTarget/Paper/Reset); `WarTableRange` visualizes the map region in-editor and in-game
