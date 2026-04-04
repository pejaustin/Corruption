# Corruption — Game Design Document

**Version:** 0.1  
**Last updated:** April 3, 2026  
**Author:** Austin  
**Engine:** Godot  
**Status:** Pre-production

---

## 1. Vision

### One-line pitch
A PvP Dark Lord simulator where four players compete to corrupt the land of the good.

### Vision statement
Corruption puts players in the role of rival dark forces, each vying to be the one who finally breaks the last bastion of good in the realm. The game creates a constant tension between direct action and strategic scheming through its core asymmetry: at any moment, only one player controls a Corrupted Avatar on the ground, while the other three plot and maneuver from their towers as Overlords. The result is a game that feels like a competitive Souls-like RPG and a dark fantasy war room at the same time — and every player is always doing one or the other.

### Design pillars
1. **Asymmetric tension** — The Avatar/Overlord split means players are always in different modes with different capabilities, creating natural conflict and drama.
2. **Earned power** — Nothing is given. Avatar control is taken. Territory is conquered. The gem must be stolen.
3. **Dark lord fantasy** — Every player should feel like the villain protagonist of their own story, commanding forces, scheming against rivals, and pursuing ultimate power.

### Player experience goals
- **As the Avatar:** I feel powerful but exposed. I'm making progress, but I know three rivals are watching and scheming. Every dungeon could be trapped. Every NPC could be compromised.
- **As the Overlord:** I feel cunning but constrained. I can see the board, move pieces, forge and break alliances — but I can't act directly. I need the Avatar to fall so I can take my turn.

---

## 2. Core loop

### The fundamental cycle

```
AVATAR ACTIVE (1 player)          OVERLORDS WATCHING (3 players)
─────────────────────────          ────────────────────────────────
Explore the world (3rd person)     Command minions from tower (1st person)
Fight enemies, collect loot        Upgrade domain and defenses
Beat bosses, learn skills          Sabotage rivals / set traps
Buy items, trigger NPC events      Diplomacy — forge or betray alliances
Attempt the gem heist              Upgrade own avatar abilities for next turn
         │                                        │
         └──── Avatar defeated or recalled ────────┘
                        │
              Next Avatar is EARNED
              (by the player who took it)
                        │
              New Avatar enters the world
              Previous holder becomes Overlord
```

### Avatar control transfer
- Only one Avatar can be active at a time.
- Avatar control is **earned** — you take it from the current holder.
- **Two transfer paths:**
  1. **Hostile takeover** — A Corruptor's minions defeat the current Avatar. The owning Corruptor takes control.
  2. **Influence fallback** — If the current Avatar is defeated by neutral enemies (or the holder otherwise loses control), Avatar passes to the Corruptor with the highest **ambient influence**.

### Ambient influence
- The resource that determines Avatar succession and contributes to the win condition.
- **Two sources:**
  1. **Territory control** — corrupted land area. More territory = more influence.
  2. **Minor gems** — found at human settlements, temples, and holy sites across the map. Connected to the main gem. Captured and "tapped" for corruption.
- **Key rule:** Overlords can use minions to clear and hold territory around a gem site, but **only the Avatar can confirm a gem capture**. This means a player can prepare a site during Overlord time, but they're vulnerable to being usurped until they can lock it down with their next Avatar turn.

### The clock — Divine Intervention
- There is no arbitrary timer. Match pacing is a natural consequence of game mechanics.
- **Target match length:** ~90 minutes average, ~2 hours maximum.
- The neutral "good" faction actively works to **purify corruption** and reclaim territory. If total corruption across all players drops too low or stagnates, the gods trigger **divine intervention**, sealing the gems permanently. All players lose.
- This creates natural pacing: early game is a land grab, mid game is fighting over gems and Avatar control, and late game has divine intervention bearing down if nobody has closed it out.

---

## 3. Game modes

### 3a. Avatar mode

**Perspective:** Third-person 3D  
**Genre feel:** Souls-like action RPG  
**Player count:** 1 (the active Avatar holder)

**Core activities:**
- **Combat** — Real-time melee/ranged fighting against neutral faction enemies, bosses, and rival minions.
- **Exploration** — Navigate the shared world, discover locations, find loot and items.
- **Progression** — Level up, learn skills, equip gear. Progress persists across Avatar sessions.
- **NPC interaction** — Trigger events, buy/sell at merchants, gather intelligence.
- **The heist** — Infiltrate the capitol city, reach the gem, and corrupt it. This is the endgame action.

**Faction-specific Avatar behavior:**
- **Demonic** — Strongest Avatar. The brawler. Wants to fight and push objectives directly.
- **Undeath** — Medium Avatar. Needs Avatar time to confirm gem captures and bolster the swarm.
- **Nature/Fey** — Weak in combat, but can **stealth into human settlements** undetected. Priests only sense demonic/undead/eldritch corruption — Nature reads as natural, not evil. Their Avatar purpose is infiltration, not fighting.
- **Eldritch** — Weakest in direct combat, but some of the faction's most powerful abilities **require the Avatar to activate** (e.g., summoning high-quality minions, performing rituals). The Eldritch player grabs Avatar, performs a ritual, then may intentionally give it back to return to tower scheming.

**Key questions to resolve:**
- What does the Avatar's skill tree look like? Is it faction-specific?
- How does loot work — random drops, fixed locations, crafting?
- What happens to your progress if you lose the Avatar? Do you keep levels/gear for next time?
- How does the Avatar interact with other players' minions and traps?

### 3b. Overlord mode

**Perspective:** First-person 3D (inside your tower)  
**Genre feel:** Dark fantasy war room / strategy  
**Player count:** 3 (everyone not currently the Avatar)

**Core activities:**
- **Minion management** — Spawn, command, and position minions in the world.
- **Domain upgrades** — Build and improve your tower and surrounding territory.
- **Sabotage** — Set traps, ambush the Avatar, interfere with rival Overlords.
- **Diplomacy** — Communicate with other players. Forge alliances, make deals, betray.
- **Avatar preparation** — Upgrade your own Avatar abilities so you're ready when your turn comes.

**Faction-specific Overlord behavior:**
- **Undeath** — Weakest Overlord tools. Limited access to complex tower mechanics. Compensates with cheap, expendable minion hordes and the ability to raise fallen enemy minions.
- **Demonic** — Medium Overlord depth. Straightforward tools matching their brute-force playstyle. Highly visible actions — hard to hide what they're doing on the board.
- **Nature/Fey** — High Overlord depth. Best tools for map visibility and territory control. Can see more of the board than any other faction.
- **Eldritch** — Highest Overlord depth. Best sabotage tools. Can dominate other players' minions and human NPCs. The puppet master — most powerful from the tower.

**Key questions to resolve:**
- What does the tower interior look like? Is it a literal room you walk around in, or more of a UI overlay?
- How do you command minions — direct control? Waypoints? Zones of influence?
- What communication tools exist between players?
- Can Overlords directly attack each other's towers, or only via minions?

---

## 4. The world

### Overview
The game takes place in a shared fantasy realm controlled by a neutral "good" faction. This faction is antagonistic to all players — its forces are the primary PvE content and the defenders of the gem.

**World structure:**
- **Hand-crafted maps.** One map for launch, with the possibility of additional maps in the future. Different maps can be used to tweak game balance (e.g., one faction starts closer to the capitol, others farther away).
- One continuous map per match.
- The **capitol city** sits at the center, housing the gem. It's the most heavily defended location.
- Each player has a **tower** on the periphery — their home base and Overlord mode location.
- Between the towers and the capitol: wilderness, dungeons, neutral settlements, contested territory.
- **Minor gem sites** are scattered at human settlements, temples, and holy sites throughout the map.

### The neutral faction ("The Good")
- Not player-controlled. AI-driven.
- Functions as both PvE content (enemies to fight, bosses to beat) and the final obstacle (capitol defense).
- **Actively reclaims territory** — purifies corruption over time if left undefended. This is the engine behind the divine intervention clock.
- **Detection is asymmetric by faction:**
  - Priests detect Demonic corruption easily (highly visible)
  - Priests detect Undeath and Eldritch corruption normally
  - **Priests cannot detect Nature/Fey corruption** — it reads as natural, not evil. Nature/Fey Avatars can infiltrate human settlements undetected.
- Neutral NPCs can be **dominated by Eldritch** faction (Overlord ability).
- *[OPEN QUESTION: Does the neutral faction scale in difficulty over time beyond the divine intervention mechanic?]*

### The capitol city and the gem
- The gem is the win condition objective. It's in the center of the most fortified location.
- Capturing it requires significant Avatar power (levels, gear, skills) — but also strategic preparation.

**The final boss fight:**
- The Avatar must defeat **two bosses back-to-back** in Souls-like combat.
- Boss difficulty is **debuffed by corruption:**
  - **Total corruption** across all players reduces boss strength (all players indirectly contribute).
  - **Personal corruption** (the attempting player's own influence) provides additional debuffs.
  - **Map interactions** — corrupting holy sites and capturing minor gems near the capitol weakens its defenses.
- If the Avatar is defeated, control passes to the **next highest influence player**, who starts a fresh attempt (bosses reset to their current debuffed state).
- This means the entire match is effectively a long boss-prep phase — every territory corrupted and gem captured chips away at the final fight.

**Spectator mechanic — Astral Projection:**
- When a player initiates the final boss fight, all other players are **astral projected into the boss room** via their connection to the core gem.
- Spectating players can **watch and heckle** but cannot interfere with the fight.
- Their minion and territory actions continue in the background on autopilot — influence can still shift during the attempt.
- Spectators cannot "steal" the attempt, but if the Avatar falls, the next-in-line inherits control.

---

## 5. Factions

Four asymmetric factions, each representing a different type of corruption.

**Design goals for factions:**
- Each should feel mechanically distinct — different minion types, avatar abilities, overlord tools, and territory bonuses.
- Each should have clear **strengths and weaknesses** that create natural counter-play.
- Each should suggest a different **playstyle** — aggressive, defensive, deceptive, economic, etc.

### Faction roster

| Faction | Corruption type | Playstyle | Minions | Avatar strength | Overlord depth |
|---------|----------------|-----------|---------|----------------|----------------|
| **Undeath** | Necromancy | Swarm / attrition | Cheap, numerous, can raise fallen enemy minions | Medium | Low |
| **Demonic** | Hellfire | Brute force | Expensive, strong, specialized | Strongest | Medium |
| **Nature/Fey** | Wild corruption | Map control / PvE / infiltration | Specialized but weak | Weak (but stealthy) | High |
| **Eldritch** | Madness / Deep One | Puppet master / sabotage | Dominated from other factions + summoned via Avatar rituals | Weakest (but required for rituals) | Highest |

### Faction design principles

**Each faction occupies a unique position across the game's core axes:**

```
                    Undeath     Demonic     Nature/Fey     Eldritch
Avatar desire       Medium      HIGH        Medium         Low (but required)
Avatar strength     Medium      Strongest   Weak           Weakest
Avatar PURPOSE      Confirm     Fight       Infiltrate     Ritual/summon
Map spread          Wide        Focused     Wide           Focused
PvP vs PvE          Mixed       Mixed       PvE            PvP (from tower)
Overlord depth      Low         Medium      High           Highest
Minion style        Cheap horde Strong few  Specialized    Dominated/summoned
```

**Counter-play matrix:**
- **Undeath vs Demonic** — Undeath swarms Demonic's expensive units and raises them. Demonic must fight efficiently or bleed resources.
- **Nature/Fey vs Undeath** — Nature/Fey outpaces Undeath on territory control and can avoid direct confrontation.
- **Eldritch vs Nature/Fey** — Eldritch dominates Nature/Fey's weak minions and bullies them in PvP from the tower.
- **Demonic vs Eldritch** — Demonic's raw power can brute-force through Eldritch's manipulation. Hard to puppet master something that just smashes through your schemes.

### Faction details

#### Undeath
- **Playstyle:** Flood the map with cheap, expendable minions. Quantity over quality.
- **Unique mechanic:** Can **raise fallen enemy minions** — punishes other players for committing forces against you.
- **Avatar role:** Confirm gem captures, bolster swarm presence. Medium combat capability.
- **Overlord role:** Limited tower tools. Compensates with sheer minion throughput.
- **Weakness:** Lack of access to complex Overlord mechanics. Individual minions are weak and can't take complex commands.

#### Demonic
- **Playstyle:** Brute force with strong, specialized units. The beginner-friendly faction — most intuitive for the setting.
- **Unique mechanic:** Strongest individual units in the game. Clear, powerful abilities.
- **Avatar role:** The brawler. Wants to be the Avatar as much as possible. Strongest in direct combat.
- **Overlord role:** Straightforward tools. What you see is what you get.
- **Weakness:** Units are expensive and slow to rebuild. Highly visible on the board — other Overlords always know where Demonic forces are. Struggles to control wide territory.

#### Nature/Fey
- **Playstyle:** Territory control, PvE dominance, and infiltration. Quietly eats up the map.
- **Unique mechanic:** Avatar is **undetectable by human priests** — can stealth into settlements, temples, and holy sites that other factions must fight through. Best at defeating the neutral "good" faction.
- **Avatar role:** Infiltrator, not fighter. Sneaks in to capture minor gems at prepared sites.
- **Overlord role:** Best map visibility of any faction. Excellent territory control tools.
- **Weakness:** Weakest in PvP combat. Crumbles when other players commit forces against them directly.

#### Eldritch / Deep One
- **Playstyle:** Puppet master. Manipulates the board from the tower. Strongest saboteur.
- **Unique mechanic:** Can **dominate other players' minions and human NPCs**. Some of the faction's most powerful abilities (e.g., summoning high-quality minions) **require the Avatar to perform rituals**, creating a unique rhythm: grab Avatar → perform ritual → let it go → exploit results from tower.
- **Avatar role:** Weakest in direct combat, but essential for unlocking faction abilities. A "key that turns the lock," not a weapon.
- **Overlord role:** Most powerful tower in the game. Best sabotage tools. Can pull strings across the entire board.
- **Weakness:** Worst territory control. Can manipulate but can't hold ground.

---

## 6. Multiplayer and networking

### Architecture
- **Peer-to-peer with host model** — one player's machine acts as the server.
- Built on Godot's multiplayer API (ENetMultiplayerPeer).

### Key networking considerations

**State synchronization:**
- Avatar position and combat — high-frequency sync (every physics frame). This is the most latency-sensitive element.
- Minion positions and commands — medium-frequency sync.
- Resource counts, upgrades, timer — low-frequency sync (every few seconds).
- Diplomacy messages — event-driven, reliable delivery.

**Authority model:**
- **Full host authority.** The host validates all game state. This is a competitive PvP game with high stakes — cheat resistance is a must. The latency trade-off for non-host players is acceptable given the 4-player scale.

**Host migration:**
- *[OPEN QUESTION: If the host disconnects, does the game end? Or can another player take over?]*

**Matchmaking:**
- *[OPEN QUESTION: Lobby-based (invite friends)? Random matchmaking? Both?]*
- Minimum viable: lobby with invite codes.

---

## 7. Technical specifications

### Engine and tools
- **Engine:** Godot (version TBD)
- **Language:** GDScript (primary), with C# or GDNative for performance-critical systems if needed
- **Target platforms:** PC (initial), potential console later
- **Networking:** Godot ENet peer-to-peer

### Performance targets
- *[OPEN QUESTION: Target framerate? 60fps? 30fps minimum?]*
- *[OPEN QUESTION: Maximum number of simultaneous entities (minions, NPCs, etc.)?]*

### Key technical risks
1. **Souls-like combat over P2P** — Latency tolerance for action combat is tight (~100-150ms). This is the hardest networking problem in the game.
2. **Dual camera system** — Switching between 1st person (Overlord) and 3rd person (Avatar) for the same player requires careful camera and control management.
3. **AI for neutral faction** — The "good" faction needs to feel threatening and reactive, not just ambient. This is a significant AI investment.
4. **Scope as a solo developer** — Every system needs to be evaluated against realistic development time.

---

## 8. Art and audio direction

*[This section is intentionally sparse — fill in as the visual identity develops.]*

### Visual style
- *[OPEN QUESTION: Realistic? Stylized? Low-poly? What's achievable as a solo dev?]*
- The two perspectives (1st person tower, 3rd person world) may benefit from different visual treatments.

### Audio
- *[OPEN QUESTION: Original soundtrack? Procedural audio? Licensed?]*
- Overlord mode should feel atmospheric and brooding — you're in a dark tower watching the world.
- Avatar mode should feel kinetic and dangerous — Souls-like combat audio.

---

## 9. Build plan

### Development philosophy
- **Modular, testable increments** — each work session should produce something playable or verifiable.
- **Prototype the riskiest things first** — P2P combat sync and the Avatar/Overlord mode switch.
- **Greybox everything** — Art comes last. Get the mechanics working with placeholder assets.

### Phase 0: Foundation (current)
- [ ] Finalize GDD core systems
- [ ] Define factions (at least 2 for prototype)
- [ ] Set up Godot project structure
- [ ] Basic P2P lobby: 4 players can connect

### Phase 1: Core loop prototype
- [ ] Avatar mode: basic 3rd-person character controller with combat
- [ ] Overlord mode: basic 1st-person tower view
- [ ] Mode switch: one player can transition between Avatar and Overlord
- [ ] Networking: Avatar movement syncs across all clients
- [ ] Simple neutral enemies (test combat sync)

### Phase 2: Overlord systems
- [ ] Minion spawning and basic commands
- [ ] Domain upgrade placeholder
- [ ] Communication between players
- [ ] Avatar transfer mechanic (earn/take)

### Phase 3: Game loop
- [ ] Win condition: gem capture and corruption
- [ ] Lose condition: shared timer
- [ ] Full 4-player match flow: lobby → faction select → game → win/loss
- [ ] Basic neutral faction AI

### Phase 4: Faction differentiation
- [ ] Implement at least 2 distinct factions
- [ ] Faction-specific minions, abilities, and territory bonuses
- [ ] Balance pass

### Phase 5: Polish and content
- [ ] Remaining factions
- [ ] World content: dungeons, bosses, NPCs, loot
- [ ] UI/UX pass
- [ ] Audio
- [ ] Art replacement (greybox → final)

---

## 10. Open questions registry

A running list of design decisions that need to be made. Resolve these as development progresses.

| # | Question | Category | Priority | Status |
|---|----------|----------|----------|--------|
| 1 | How does Avatar control transfer work? | Core loop | **Critical** | **Resolved** — Hostile takeover (minions kill Avatar) or influence fallback (highest ambient influence) |
| 2 | How long is a match? | Core loop | High | **Resolved** — ~90 min avg, 2hr max. No arbitrary timer; divine intervention triggers when corruption stagnates |
| 3 | What are the four factions? | Factions | **Critical** | **Resolved** — Undeath, Demonic, Nature/Fey, Eldritch/Deep One |
| 4 | Procedural or hand-crafted world? | World | High | **Resolved** — Hand-crafted. One map for launch, more later. Asymmetric starting positions for balance |
| 5 | Host authority vs. distributed authority? | Networking | High | **Resolved** — Full host authority |
| 6 | What does corrupting the gem involve? | Win condition | High | **Resolved** — Two back-to-back Souls-like bosses, debuffed by total + personal corruption and map interactions |
| 7 | Can Overlords interfere with the gem corruption? | Win condition | High | **Resolved** — No. Astral projected as spectators. Can heckle but not act. Minions/territory on autopilot |
| 8 | What's the information model for Overlords? | Overlord mode | Medium | Partially resolved — Nature/Fey has best visibility, Demonic is most visible. Details TBD |
| 9 | Does the neutral faction scale over time? | World | Medium | Partially resolved — actively reclaims territory, triggers divine intervention. Scaling details TBD |
| 10 | Does Avatar progress persist across sessions? | Progression | Medium | Open |
| 11 | Visual style direction? | Art | Medium | Open |
| 12 | Host migration if host disconnects? | Networking | Medium | Open |
| 13 | Lobby-based or random matchmaking? | Networking | Low | Open |
| 14 | Target framerate and entity count? | Technical | Low | Open |

---

## Appendix A: Reference games

Games to study for specific systems:

- **Dark Souls / Elden Ring** — Avatar combat feel, difficulty, exploration
- **Dungeon Keeper / War for the Overworld** — Overlord fantasy, minion management, dark lord humor
- **Overlord (Codemasters)** — Commanding minions in a fantasy world
- **Crawl** — Asymmetric multiplayer, one player as hero vs. others as monsters
- **Natural Selection 2** — Asymmetric multiplayer with commander + ground troops
- **Tooth and Tail** — Simplified RTS with direct leader control

## Appendix B: Glossary

| Term | Definition |
|------|-----------|
| Avatar | The corrupted champion a player controls directly in 3rd-person mode |
| Overlord | A player in their tower, interacting with the world through proxies |
| Corruptor | A player, regardless of whether they are currently Avatar or Overlord |
| Tower | Each player's home base, where they exist during Overlord mode |
| The Gem | The win condition objective, housed in the capitol city center |
| Minor Gems | Smaller gems at settlements, temples, and holy sites that can be captured for corruption/influence |
| Ambient Influence | A player's accumulated corruption from territory control and captured minor gems. Determines Avatar succession |
| The Good / Neutral faction | AI-controlled faction defending the realm against all players |
| Capitol | The central, most fortified location in the world, containing the gem |
| Divine Intervention | The lose condition — triggered when total corruption drops too low, sealing the gems permanently |
| Astral Projection | Spectator mechanic during the final boss fight — non-active players watch from within the boss room |
| Hostile Takeover | Avatar transfer via minions defeating the current Avatar |
| Influence Fallback | Avatar transfer to the highest-influence player when the current holder loses control to non-player causes |

---

*This is a living document. Update it as design decisions are made and development progresses.*
