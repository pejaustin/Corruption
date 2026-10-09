# GDD v2 overhaul — work plan and status

Branch `gdd-v2-overhaul`. Rebuilds the game around `docs/GDD.md` (Austin, 2026-10-08). Anything that is Austin's to
design (site types, relics, maneuvers, advisor lines, the map and its locations, unit types, boss forms, tuning
numbers) goes in as a marked placeholder; see `PLACEHOLDERS.md`. The GDD's §11 open questions stay open: where the
build needs an answer to run, it uses a placeholder rule and says so.

## What changes, by GDD section

| GDD | Old build | Overhaul |
|---|---|---|
| §1 Undead only, PvP | 4 selectable factions; hostility by faction | Everyone is Undead; hostility by **allegiance** (owning peer; the good faction is its own side). Player colours by seat. Match pace setting (normal / slow). |
| §2 The tower | War table, palantir, mirror, summoning circle, upgrade altar | Ruined tower that rebuilds as you hold sites; stations: advisor, map floor, palantir, mirror, balcony, summoning circle, desk with books, treasure room + ledger. Upgrade altar removed. |
| §3 Map and orders | Table diorama, click-to-draft, paper, advisor handoff | Stone-floor map with discrete map points (known / undiscovered), chess pieces you can move to plan, walk a path, scroll of orders in hand, advisor asks the goal, ink path. |
| §4 Couriers | Couriers deliver moves; friendly units broadcast live | No live broadcast: everything you know arrives by courier or at the tower. Courier pool is scarce; couriers can die or be captured; "go and come back"; reports fill in map points. Courier training. |
| §5 Troops | Summon for resources; auto raise-dead on kill | Humans (good faction) leave bodies; bodies carried to the tower (or a site after an upgrade) are raised at the circle. Thralls from live captives at a corrupted chapel. Nobles bought with goods + a promise. Training / relics / paid gear instead of a bought tech tree. |
| §6 Goods | Resource number ticking up | Resource locations worked by an overseer; goods pile up there; haul orders; treasure room shows the tower exactly; ledger shows the latest reports. |
| §7 Corruption sites | Gem sites feed a corruption score | Corruption is not a resource. Typed sites each grant one capability. Take: minimum strength present, more goes faster, Avatar much faster. Lose: rivals, purification, or slipping back when unguarded. Beacons. Your tower is a permanent site. |
| §8 The Paladin | Claim at tower; ownership moves on kill | Takeover by beating him and turning him like a site (or overpowering), contested when low. Hold fades unless near your corruption; 0 HP wipes it. Unclaimed AI recovers / hunts corruption. Control tiers lock actions; he resists attacking the good faction. Palantir watchers as orbs. |
| §9 Winning | Two fixed bosses debuffed by total corruption | Paladin enters the holy site → boss gauntlet of the other players' boss forms, weakest first by sites held (boss sites weigh more); a boss who wins takes the Paladin home. Draw: the good faction grows; sites go unusable, thresholds rise, the city centre locks. |
| §10 Diplomacy | Recorded 10 s messages, anim-name playback | Live calls that ring the rival's mirror, falling back to a recorded message; skeleton pose capture. |

## Phases

Each phase is its own commit (or few), pushed as it lands. Status is kept here.

0. **Foundation:** allegiance hostility, Undead-only lobby, seat colours, match pace config, remove the corruption
   score / resources / upgrade altar / faction-gated abilities, placeholder registry.
1. **Corruption sites:** `CorruptionSite` + `SiteType` data, capabilities, beacons, the tower as a permanent site, the
   tower rebuilding with sites held.
2. **Information:** remove live broadcast; reports only by courier / at the tower; courier pool and training; capture;
   map points discovered by reports.
3. **Map and orders:** floor map, map points, movable pieces, walked paths, scroll of orders, advisor goal dialogue,
   ink paths, order goals (go here, assess and return, corrupt site, haul).
4. **Troops and humans:** bodies, carrying, raising at the circle, thralls at a chapel, nobles.
5. **Goods:** resource locations, overseers, piles, hauling, treasure room, ledger.
6. **The Paladin:** takeover, hold decay, control tiers and resistance, unclaimed AI, watcher orbs.
7. **Endgame:** holy site, gauntlet, comeback, good-faction growth and draw.
8. **Tower stations:** balcony, desk with books, treasure room, day / night.
9. **Mirror:** live calls, ringing, skeleton pose.
10. **Getting better:** leaders, maneuvers, teaching, succession; relics; paid gear.

## Status

- [x] 0 Foundation
- [x] 1 Corruption sites
- [x] 2 Information
- [x] 3 Map and orders
- [x] 4 Troops and humans (bodies, remains, thralls at a chapel, nobles; `tools/tests/test_fieldwork`)
- [x] 5 Goods (resource locations, overseers, hauling, treasure room, ledger; `test_fieldwork`, `test_treasure`)
- [x] 6 The Paladin (takeover, hold, control tiers, shared Palantir; `test_paladin`)
- [x] 7 Endgame (holy site, boss gauntlet, comeback, draw lock; `test_endgame`). Boss forms are AI-driven
  stand-ins; **player-controlled boss forms are not built**.
- [x] 8 Tower stations (balcony, day/night, desk, treasure room + ledger; `test_balcony`, `test_desk`, `test_treasure`)
- [x] 9 Mirror
- [x] 10 Getting better (leader experience, maneuvers, teaching, relics; `test_growth`). Paid gear is not built.

Tests (`tools/tests/`): sites, orders, desk, mirror, fieldwork, paladin, balcony, endgame, treasure, growth.

Still open: player control of boss forms (#560), every placeholder in `PLACEHOLDERS.md`, how the Paladin gets to the
winner's tower (#576), the GDD §11 questions, and real multi-peer testing of the mirror and Palantir voice.

## Checking it

Headless boot check (no editor, so no files rewritten): from the repo root,
`godot --headless --path . --quit-after 300`. A fresh clone needs the editor opened once so the netfox autoload UIDs
resolve.
