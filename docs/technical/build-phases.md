# Build Phases — MVP-First Iteration

**Philosophy:** Each tier is a playable game with a win condition. Social and Overlord tools come before combat polish — 3 out of 4 players are always Overlords, so their experience matters most. Debug tooling is first-class, not an afterthought. Greybox everything — art comes last.

---

## Tier 0: The Board is Set [COMPLETE]

**Goal:** Players connect. One is the Avatar. Others are Overlords in their towers. The Avatar can reach the gem and "win." Solo-testable with dummy players.

**Win condition:** Avatar walks to the gem in the Capitol and interacts with it. You win. (No combat, no bosses — just reach it.)

### Debug tooling
- [x] F3 debug overlay (network, factions, players, FPS, Avatar status, influence, minions, territory, boss)
- [x] **Dummy player system** — F2 to add bot players, idle in towers
- [ ] **Debug console** — Key commands: force Avatar transfer, teleport, spawn at location

### Core
- [x] Project setup (Godot 4.6, netfox)
- [x] P2P lobby with faction selection
- [x] 4-player max enforcement
- [x] Overlord 1st-person tower view (existing)
- [x] 4 towers spawn players as Overlords
- [x] **Avatar as separate shared entity** — Paladin vessel with 3rd-person camera, own movement states, transferable input authority
- [x] **Avatar claim** — Press E at tower interactible to claim the Avatar
- [x] **Control transfer** — Claiming Avatar disables Overlord input/camera, enables Avatar camera/input for that peer
- [x] **Avatar movement syncs** across all clients
- [x] **The gem** — Interactible at map center, Avatar touches it and presses E to win
- [x] **Win screen** — Victory/defeat overlay with return to menu
- [x] **Match flow** — Win screen → back to lobby (disconnect and return)

**Riskiest thing:** Mode split + camera switching over network.

---

## Tier 1: The Tower is Alive

**Goal:** Overlords have things to do. Palantir and Mirror are functional. The Avatar can be watched and talked about. Social gameplay works.

**Win condition:** Same as Tier 0 (reach the gem), but now Overlords can watch you do it and talk about it.

### Debug tooling
- [ ] **Mirror playback inspector** — Debug panel showing all recorded messages, timestamps, recipients
- [ ] **Palantir force-activate** — Debug command to enable/disable Palantir without walking to it

### Core
- [x] **Tower interior** — Greybox room with interactible stations (walk up and press E)
- [x] **Palantir** — Interact to watch the Avatar in real-time via SubViewport. Avatar gets a visual cue (eye icon, sound) that they're being watched, and can see how many watchers.
- [x] **Mirror** — Stand in front, record button captures pose track + mic audio with reverb. Plays back as ghost reflection in Mirror3D. Sends to selected Overlord(s). Recipient gets notification, can watch playback.
- [x] **Tower balcony** — Overlord can walk to a balcony and directly observe a scaled-down view of the map below. No UI overlay — you physically look out and see the world.
- [x] **Avatar transfer (simple)** — Avatar can voluntarily return to tower (recall). Control passes to next player by influence (or round-robin for now).

**Riskiest thing:** Mirror recording — mic capture + SubViewport + audio effects + network delivery. Prototype this early.

---

## Tier 2: Blood on the Ground

**Goal:** Avatar can fight and die. Death triggers control transfer. The core loop turns. Combat is basic but functional.

**Win condition:** Reach the gem, but now there are neutral enemies guarding it. Fight through them or die trying. On death, next player gets a turn.

### Debug tooling
- [x] **God mode** — F4 toggles invincibility for Avatar
- [x] **Spawn enemy** — F6 spawns enemy at camera target (now synced via EnemyManager)
- [x] **Kill Avatar** — F5 force-kills Avatar to test transfer flow
- [x] **Influence display** — All players' influence scores visible in F3 debug panel
- [x] **Spawn minion** — F7 spawns minion at camera target
- [x] **Add influence** — F8 adds 10 influence to self

### Core
- [x] **Basic melee attack**
  - Light attack bound to left click (Avatar-only, Overlords cannot attack)
  - Attack plays a commitment animation — no cancel once started
  - Hitbox spawns on a specific animation frame window
  - Hitbox damages any damageable body it overlaps
  - Stamina cost per attack; can't attack at zero stamina
  - Stamina regens passively over time
- [x] **HP and damage**
  - Avatar has an HP value displayed in debug overlay (HUD later)
  - Taking damage reduces HP; HP floors at 0
  - Death state triggers at 0 HP (no knockback/hitstun yet)
  - No healing for now
- [x] **Simple neutral enemy**
  - Enemy scene with HP, a patrol point, and an aggro radius
  - Idles at patrol point until Avatar enters aggro range
  - Chases Avatar while in aggro range
  - Has a melee attack with its own hitbox and commitment animation
  - Takes damage from Avatar attacks; dies at 0 HP
  - Death plays animation then frees the node
  - Hand-placed in the world scene (not procedural)
- [x] **Avatar death → transfer**
  - 0 HP triggers death animation/state
  - Avatar is disabled after death (hidden, no collision, no input)
  - Control transfers to next player via round-robin (existing `game_state.gd`)
  - New Avatar owner gets camera/input swap to Avatar mode
  - Avatar respawns at a fixed point (TBD: Capitol center or tower)
  - Previous controller returns to Overlord mode
- [x] **Mode switch at runtime**
  - Fixed respawn clobbering new Avatar activation after death transfer
  - Claim → death → transfer → re-claim cycle verified
- [x] **Animation-driven hitboxes** — Hitbox window driven by animation progress ratio instead of timers
- [x] **Combat sync**
  - Attack animations visible to all clients (state machine synced via rollback)
  - Hitbox activation/deactivation synced (host-authoritative)
  - Damage is host-validated
  - Enemy HP and death synced to all clients via EnemyManager RPCs
  - No desync on hit — if host says hit, all clients see the hit

**Riskiest thing:** Combat sync over P2P with rollback. Tight latency tolerance.

---

## Tier 3: The Dark Lords Scheme

**Goal:** Overlords can project power onto the map. Minions exist. Territory matters. Influence determines who gets the Avatar.

**Win condition:** Reach the gem and defeat a single guardian boss (simplified). Boss is debuffed by total corruption. Overlords can send minions to help or hinder.

### Debug tooling
- [x] **Spawn minion** — F7 spawns minion at camera target
- [x] **Set influence** — F8 adds influence to self
- [ ] **Territory paint** — Debug tool to mark areas as corrupted
- [x] **Boss health/debuff display** — Boss stats visible in F3 debug overlay

### Core (tested)
- [x] **Minion spawning** — Summoning Circle interaction in tower. Spend resources. MinionManager handles sync.
- [x] **Per-tower spawn + rally markers** — Each tower owns a `MinionSpawnPoint` (summons appear there). `MinionRallyPoint`s live under `World/Markers` and are paired with towers by child order. Rally is only visible to, and only movable by, the owning overlord.
- [x] **Basic minion AI** — State machine: idle, move_to (NavigationAgent3D with direct-steer fallback), jump (JumpableLink traversal), attack, die

### Core (impl complete — ready to test)
- [x] **Minion commands** — War Table: top-down map view, click to set waypoints for all minions (also relocates the sender's rally). Clicks now route through `KnowledgeManager.issue_move_command`; with `INSTANT_COMMANDS=true` the behavior is identical to the old direct path. See `docs/systems/war-table.md` for the information-warfare layer (`WorldModel`, diorama rendering, courier plans).
- [x] **Territory system** — Grid-based corruption spreads from minion presence, decays without them
- [x] **Influence tracking** — GameState tracks per-peer influence, displayed in debug overlay
- [x] **Minor gem sites** — GemSite interactible: minions clear, Avatar confirms capture, grants passive influence
- [x] **Hostile takeover** — Minion kills Avatar → that minion's owner becomes Avatar
- [x] **Influence fallback** — Avatar dies to neutrals → highest influence peer takes over
- [x] **Guardian boss** — GuardianBoss at Capitol, debuffed by total corruption, defeat to win
- [x] **Astral projection** — SubViewport spectator overlay auto-activates during boss fight

**Riskiest thing:** Minion AI + networking. Keep it dead simple — state machine with patrol/aggro/attack.

---

## Tier 4: Corruption Has a Face

**Goal:** Factions feel different. Picking Undeath vs Demonic changes how you play both modes.

**Win condition:** Full endgame — two back-to-back bosses, debuffed by corruption. Divine intervention lose condition active.

### Debug tooling
- [x] **Faction swap** — F9 cycles faction mid-game for testing
- [x] **Corruption boost** — F10 adds corruption around origin
- [ ] **Balance dashboard** — Faction win rates, average influence, minion efficiency

### Core (impl complete — ready to test)
- [x] **Faction-specific minion rosters** (all 4 factions) — FactionData with unique stats, costs, traits
- [x] **Faction-specific Avatar abilities** (all 4 factions) — AvatarAbilities with cooldowns, damage mults, lifesteal, camouflage
- [x] **Faction-specific Overlord tools** — Summoning Circle shows roster, Eldritch dominate, Demonic single-minion command, Nature/Fey info advantage
- [ ] **Neutral faction detection asymmetry** — Nature/Fey stealth past priests
- [x] **Eldritch ritual mechanic** — RitualSite interactible, Avatar channels to unlock bonuses (domination discount, corruption surge, eldritch vision)
- [x] **Undeath raise-dead mechanic** — Ghoul trait spawns skeletons from killed enemy minions
- [x] **Two-boss endgame** — BossManager: Capitol Guardian → Corrupted Seraph sequence
- [x] **Divine intervention** — DivineIntervention node: lose if corruption stays below threshold for 60s
- [x] **Upgrade Altar** — Tower interactible: 5 upgrade types (minion HP/DMG, resource rate, Avatar HP/DMG)

---

## Tier 5: Polish & Content

**Goal:** The game feels good. Art, audio, UI, balance.

- [ ] **UI/UX pass** — HUD, faction-themed menus, influence display
- [ ] **Audio** — Combat, ambient tower atmosphere, faction themes, Mirror reverb tuning
- [ ] **Art pass** — Replace greybox with final assets
- [ ] **Balance pass** — Faction tuning, boss difficulty, match pacing, divine intervention timing
- [ ] **Additional maps** — Second hand-crafted map with different balance (asymmetric start positions)
- [ ] **All 4 factions fully implemented**
- [ ] **Progression/loot system** — Gear, skills, Avatar power growth within a match

---

## Progress Tracker

| Tier | Name | Win Condition | Status | Playable? |
|------|------|---------------|--------|-----------|
| 0 | The Board is Set | Walk to gem | **Complete** | Yes |
| 1 | The Tower is Alive | Walk to gem (with social tools) | **Core complete** | Yes |
| 2 | Blood on the Ground | Fight to gem (combat + transfer) | **Complete** | Yes |
| 3 | The Dark Lords Scheme | Beat guardian boss (minions + territory) | **Impl complete** | Ready to test |
| 4 | Corruption Has a Face | Full 2-boss endgame + factions | **Impl complete** | Ready to test |
| 5 | Polish & Content | Complete game | Not started | - |

---

## Editor TODO — Nodes to Add in Scenes

Scripts are implemented but these nodes/scenes need to be created or wired up in the editor before testing.

### Tier 3

**tower_scene.tscn — root level:**
- [ ] `MinionManager` (Node) — already added, script `scripts/minion_manager.gd` attached
- [ ] `EnemyManager` (Node) — already added, script `scripts/enemy_manager.gd` attached
- [ ] `TerritoryManager` (Node) — already added, script `scripts/territory_manager.gd` attached

**tower.tscn — inside each tower:**
- [x] `WarTable` — Already placed in `tower.tscn`. Contains `MapViewPoint`, `StandPoint`, and `Map` (WarTableMap) children. Inside each tower scene also sits a `WarTableRange` (@tool MeshInstance3D) wired to `WarTable/Map` that draws a semi-transparent BoxMesh over the effective map region. Tune `Map World Center` / `Map World Size` per tower once per-overlord AOs are designed.
- [ ] `GemSite` (x2-3 in world) — Create as Area3D with CollisionShape3D (sphere, radius ~4). Attach `scripts/interactibles/gem_site.gd`. Place in `World/Interactables/`. Set `site_name` export

**tower_scene.tscn — World/GuardianBoss:**
- [ ] Instance `scenes/actors/enemy/guardian/guardian_boss.tscn`, rename to `GuardianBoss`. Place near Capitol/gem area. (Phase-2 boss `corrupted_seraph.tscn` is an inherited scene — no script override needed.)

**tower_scene.tscn — CanvasLayer:**
- [ ] `AstralProjection` (Control) — Attach `scripts/astral_projection.gd`. Needs SubViewportContainer child with SubViewport containing a Camera3D

### Tier 4

**tower_scene.tscn — root level:**
- [ ] `BossManager` (Node) — Attach `scripts/boss_manager.gd`. Set `initial_boss` export to the world's `GuardianBoss` node. Optionally set `seraph_spawn_point` (defaults to the initial boss's position) and override `seraph_scene` (defaults to `corrupted_seraph.tscn`).
- [ ] `DivineIntervention` (Node) — Attach `scripts/divine_intervention.gd`

**tower.tscn — inside each tower:**
- [ ] `UpgradeAltar` — Create as Area3D with CollisionShape3D. Attach `scripts/interactibles/upgrade_altar.gd`. Place near other tower interactibles. Needs a visual mesh (greybox cube/pedestal). Upgrade catalog is authored as `UpgradeData` resources under `res://data/upgrades/` (`minion_vitality.tres`, `minion_ferocity.tres`, `dark_tithe.tres`, `avatar_fortitude.tres`, `avatar_might.tres`).

**World/Interactables/ (place 2-3 in the world):**
- [ ] `RitualSite` — Create as Area3D with CollisionShape3D (sphere, radius ~3). Attach `scripts/interactibles/ritual_site.gd`. Set the `ritual` export to one of `res://data/rituals/*.tres` (`domination_mastery.tres`, `corruption_surge.tres`, `eldritch_vision.tres`). Needs a visual mesh (greybox cylinder/rune circle). Place away from Capitol — these should be risky detours

### Notes

- All interactibles should inherit from `scenes/interactibles/interactable.tscn` or at minimum be an Area3D with a CollisionShape3D child
- Interactibles no longer use Label3D — prompts route through the InteractionUI autoload to the HUD RichTextLabel
- The `InteractionPrompt` RichTextLabel in CanvasLayer is already set up in tower_scene.tscn
- `InteractionUI` autoload is registered in project.godot
- War Table uses the overlord's own camera — tweened to `MapViewPoint` during takeover. No separate Camera3D required. The `Map` child renders WorldModel belief as chess-piece markers; `WarTableRange` visualizes the effective map region in-editor and in-game.
