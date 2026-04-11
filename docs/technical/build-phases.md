# Build Phases — MVP-First Iteration

**Philosophy:** Each tier is a playable game with a win condition. Social and Overlord tools come before combat polish — 3 out of 4 players are always Overlords, so their experience matters most. Debug tooling is first-class, not an afterthought. Greybox everything — art comes last.

---

## Tier 0: The Board is Set [COMPLETE]

**Goal:** Players connect. One is the Avatar. Others are Overlords in their towers. The Avatar can reach the gem and "win." Solo-testable with dummy players.

**Win condition:** Avatar walks to the gem in the Capitol and interacts with it. You win. (No combat, no bosses — just reach it.)

### Debug tooling
- [x] F3 debug overlay (network, factions, players, FPS, Avatar status)
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
- [ ] **God mode** — Toggle invincibility for Avatar
  - Key binding toggles a flag that prevents Avatar HP from decreasing
- [ ] **Spawn enemy** — Debug command to place neutral enemies
  - Key command places an enemy at a raycast target from the camera
- [ ] **Kill Avatar** — Force death to test transfer flow
  - Instant death trigger, bypasses HP — tests the full death→transfer chain
- [ ] **Influence display** — Show all players' influence scores in debug overlay
  - All players' influence visible in the F3 debug panel

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
- [ ] **Mode switch at runtime**
  - Existing Tier 0 claim/recall still works cleanly with the death→transfer flow
  - Verify no regressions when cycling through claim → death → transfer → re-claim
- [ ] **Combat sync**
  - Attack animations visible to all clients
  - Hitbox activation/deactivation synced (host-authoritative)
  - Damage is host-validated
  - Enemy HP and death synced to all clients
  - No desync on hit — if host says hit, all clients see the hit

**Riskiest thing:** Combat sync over P2P with rollback. Tight latency tolerance.

---

## Tier 3: The Dark Lords Scheme

**Goal:** Overlords can project power onto the map. Minions exist. Territory matters. Influence determines who gets the Avatar.

**Win condition:** Reach the gem and defeat a single guardian boss (simplified). Boss is debuffed by total corruption. Overlords can send minions to help or hinder.

### Debug tooling
- [ ] **Spawn minion** — Place minions for any player via debug
- [ ] **Set influence** — Manually adjust player influence scores
- [ ] **Territory paint** — Debug tool to mark areas as corrupted
- [ ] **Boss health/debuff display** — Show boss stats in debug overlay

### Core
- [ ] **Minion spawning** — Summoning Circle interaction in tower. Spend resources.
- [ ] **Basic minion AI** — Move to waypoint, aggro on enemies, attack, die
- [ ] **Minion commands** — War Table: click to set waypoints, assign attack/defend
- [ ] **Territory system** — Corruption spreads from minion presence. Decays without them.
- [ ] **Influence tracking** — Territory + gem sites = influence score
- [ ] **Minor gem sites** — Fixed locations. Overlord clears with minions, Avatar confirms capture.
- [ ] **Hostile takeover** — Overlord's minion kills Avatar → that Overlord becomes Avatar
- [ ] **Influence fallback** — Avatar dies to neutrals → highest influence takes over
- [ ] **Guardian boss** — One boss at the Capitol, debuffed by total corruption. Defeat it to win.
- [ ] **Astral projection** — Other players spectate boss fight, can heckle via Mirror

**Riskiest thing:** Minion AI + networking. Keep it dead simple — state machine with patrol/aggro/attack.

---

## Tier 4: Corruption Has a Face

**Goal:** Factions feel different. Picking Undeath vs Demonic changes how you play both modes.

**Win condition:** Full endgame — two back-to-back bosses, debuffed by corruption. Divine intervention lose condition active.

### Debug tooling
- [ ] **Faction swap** — Change faction mid-game for testing
- [ ] **Corruption decay rate** — Adjustable slider for divine intervention tuning
- [ ] **Balance dashboard** — Faction win rates, average influence, minion efficiency

### Core
- [ ] **Faction-specific minion rosters** (at least 2 factions)
- [ ] **Faction-specific Avatar abilities** (at least 2 factions)
- [ ] **Faction-specific Overlord tools** (at least 2 factions)
- [ ] **Neutral faction detection asymmetry** — Nature/Fey stealth past priests
- [ ] **Eldritch ritual mechanic** — Avatar performs rituals to unlock Overlord abilities
- [ ] **Undeath raise-dead mechanic** — Raise fallen enemy minions
- [ ] **Two-boss endgame** — Full back-to-back boss sequence
- [ ] **Divine intervention** — Lose condition when total corruption drops too low
- [ ] **Upgrade Altar** — Tower upgrades and Avatar prep between turns

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
| 2 | Blood on the Ground | Fight to gem (combat + transfer) | Not started | - |
| 3 | The Dark Lords Scheme | Beat guardian boss (minions + territory) | Not started | - |
| 4 | Corruption Has a Face | Full 2-boss endgame + factions | Not started | - |
| 5 | Polish & Content | Complete game | Not started | - |
