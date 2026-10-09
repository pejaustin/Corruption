# Placeholders

Everything here stands in for something Austin hasn't designed yet (CLAUDE.md, "Austin designs; placeholders are
marked"). Each entry is marked `PLACEHOLDER:` at its source. Only Austin replaces one; when he does, drop the entry.
Numbers are collected for the playtest ticket (#587); content questions have their own tickets.

## Content (Austin's to write)

| What | Stands in for | Where | Ticket |
|---|---|---|---|
| Site types other than the corrupted chapel: an unnamed Avatar-control site and an unnamed boss-form site | The list of site types and what each grants | `data/sites/avatar_site.tres`, `data/sites/boss_site.tres` | #579 |
| Which site type stands where, and how many | The first map's sites | `scenes/world/world.tscn` (`SiteChapel`, `SiteAvatar`, `SiteBoss`) | #584 |
| Good-faction growth flavour lines | Flavour moments as the good faction grows | `scripts/good_faction.gd` `FLAVOUR_LINES` | #562 |
| Which undead the summoning circle raises, one body each | Unit types and their cost in remains | `scripts/interactibles/summoning_circle.gd` | — |

## Art and look

| What | Stands in for | Where | Ticket |
|---|---|---|---|
| Seat colours (one per tower) and the good faction's colour | How players tell each other apart | `scripts/game_constants.gd` `SEAT_COLORS`, `GOOD_COLOR` | — |
| Site marker (stone disc + tinted crystal) and the beacon (a coloured column of light) | Site and beacon art | `scenes/sites/corruption_site.gd` | #553 |
| Desk look (box table and red book) | Desk and book art | `scenes/interactibles/desk.tscn` | #570 |
| Ruined tower = hidden roof pieces, revealed as sites are held | Tower restoration stages | `scenes/world/env/tower.gd` | #567 |
| Mirror ring: a pulsing purple halo quad plus light, and a synthesized two-tone chime | How a ringing mirror looks and sounds (Q34: "chimes or glows") | `scripts/interactibles/mirror.gd` `_setup_ring_effects`, `_make_chime` | #569 |
| Mirror prompt and notice text ("Press E to call", "No answer. Recording a message.", "Line busy.", "Call ended.", ...) | The mirror's UI wording | `scripts/interactibles/mirror.gd` `get_prompt_text` and call handlers | #569 |

## Wording

| What | Stands in for | Where | Ticket |
|---|---|---|---|
| Desk book strings (prompts, tab names "All"/"Notes", empty-page and notes hints) and the mm:ss match-time format | The desk's copy | `scripts/interactibles/desk.gd` | #570 |

## Tuning (playtest ticket #587)

| Value | Where |
|---|---|
| Pace presets: unit speed ×1.0 / ×0.4; good-faction growth every 360 s / 1200 s | `scripts/match_config.gd` |
| Starting group size 4; starting couriers 2 | `scripts/match_config.gd` |
| Site thresholds, corrupt / slip / purify times per type | `data/sites/*.tres` |
| The Paladin counts as 12 troops at a site | `scenes/sites/corruption_site.gd` `AVATAR_STRENGTH` |
| Beacon lasts 20 s | `scenes/sites/corruption_site.gd` `BEACON_SECONDS` |
| Good faction: thresholds +15% per growth step, a site goes dark every 2 steps, draw at step 15 | `scripts/good_faction.gd` |
| Tower whole at 4 sites held; a ruin shows a quarter of its roof | `scenes/world/env/tower.gd` |
| Mirror: ring timeout 20 s, live pose 20 Hz, live voice ~11 kHz in 0.1 s packets, status notice 5 s, chime every 2 s, glow 1 pulse/s | `scripts/interactibles/mirror.gd` consts |

## Rules standing in for open questions (GDD §11)

| Rule | Open question | Where | Ticket |
|---|---|---|---|
| A sacked tower is only flagged (`CorruptionSite.sacked`); it spawns nothing yet | What the tower spawns after a sack, and how often | `scenes/sites/corruption_site.gd` | #577 |
