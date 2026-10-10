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
| The first map: 18 points (4 towers, 4 roads, the 3 sites, the city, 2 villages, 2 mines, an unknown ford and crossing), their labels and links | The first map's points, settlements, sites and city | `scenes/world/world.tscn` `World/MapPoints` | #584 |
| Advisor lines: goal names, questions, report sentences, dispatch/refusal lines | The advisor's voice | `scripts/orders/order_goal.gd`, `scripts/interactibles/advisor_handoff.gd`, `scripts/knowledge/knowledge_manager.gd` | #585 |
| Boss form: one stand-in type, scaled by sites held (a skeleton in the Undead colours) | The Undead boss form and how sites feed it | `data/minions/boss_form.tres`, `scenes/actors/minion/types/boss_form.tscn`, `scenes/world/places/holy_site.gd` | #583 |
| Maneuvers: three entries that only record being learned | The list of maneuvers and what each does | `data/maneuvers/*.tres` | #581 |
| Relics: two entries (a runner on first hit; one more route point) and where they lie (one at each of two sites) | The list of relics, what each does, where they are | `data/relics/*.tres`, `scenes/world/world.tscn` (`RelicAvatarSite`, `RelicBossSite`) | #580, #584 |

## Art and look

| What | Stands in for | Where | Ticket |
|---|---|---|---|
| World blockout: the whole landscape (heights, mountains, rivers, roads, forests, coast), the stand-in shape of every place, the props and the 32 px textures, all read off the sketch by eye | The world's real geography and art | `art/world/` (see its README), generators in `tools/blender/` | #604 |
| Textures on Austin's hand-made map: `geo` is vertex-painted (`Splat` layer: black grass, red rock, green dirt, blue sand; the channel -> texture mapping and the 50% threshold are guesses, seeded from the old height / slope look); `Pale River` and `The Still Lake` water; `elder wood` and `northwood` darkened `leaf_pine` (no forest texture exists); nearest-filtered, 8 m tile size is a guess | His real ground art | `art/world/source/world_landscape.blend`, `tools/blender/add_splat.py`, `tools/blender/texture_austin_map.py` | #604 |
| Open-world scene: sun, sky and fog, and the navmesh tuning (1 m cells, agent radius 0.5 m, height 0.4 m, climb 1 m, walkable on `geo` and tower floors) | The world's real lighting and nav settings | `scenes/world/open_world/open_world.tscn`, `open_world_navmesh.res`, `tools/bake_open_world_navmesh.gd` | #605 |
| Godot ground shader and water/forest materials: the splat channel mapping, 50% threshold and 8 m tile | His real ground art | `shaders/world_ground.gdshader`, `art/world/materials/` | #605 |
| World size, 2000 m x 1500 m | The real world scale, decided by the scale test | `tools/blender/world_data.py` `WORLD_W/WORLD_H`, `world_root` in `world_landscape.blend` | #603 |
| `pois/*.blend` files with no marker in Austin's map yet (`northwood`, `old_gate`, `elder_woods`, `holy_site`, `graveyard`), and the old spellings still in the generated blockout (`world_data.py`, `build_pois.py`). His marker names (2026-10-09) are authoritative for the other 13 | Which of these places he wants, and their names | `art/world/pois/`, `tools/blender/world_data.py` | #606 |
| Seat colours (one per tower) and the good faction's colour | How players tell each other apart | `scripts/game_constants.gd` `SEAT_COLORS`, `GOOD_COLOR` | — |
| Site marker (stone disc + tinted crystal) and the beacon (a coloured column of light) | Site and beacon art | `scenes/sites/corruption_site.gd` | #553 |
| Desk look (box table and red book) | Desk and book art | `scenes/interactibles/desk.tscn` | #570 |
| Balcony look (stone post and brass spyglass) | Balcony art | `scenes/interactibles/balcony.tscn` | — |
| Balcony wording ("Press E to look out", "E / Q to return") | The balcony's UI copy | `scripts/interactibles/balcony.gd` | — |
| Sky, sun and moon colours, night light and ambient levels | Day/night look | `scripts/day_night.gd` | #574 |
| Ruined tower = hidden roof pieces, revealed as sites are held | Tower restoration stages | `scenes/world/env/tower.gd` | #567 |
| Map floor illustration (parchment + terrain contours), point discs, chess pieces, ink ribbons | Map art | `scenes/map/` | #534, #538 |
| Held scroll (a cylinder at the corner of the view); advisor subtitles and choice panel | Scroll and dialogue look | `overlord_actor.gd`, `scenes/ui/advisor_dialogue.gd` | — |
| Mirror ring: a pulsing purple halo quad plus light, and a synthesized two-tone chime | How a ringing mirror looks and sounds (Q34: "chimes or glows") | `scripts/interactibles/mirror.gd` `_setup_ring_effects`, `_make_chime` | #569 |
| Mirror prompt and notice text ("Press E to call", "No answer. Recording a message.", "Line busy.", "Call ended.", ...) | The mirror's UI wording | `scripts/interactibles/mirror.gd` `get_prompt_text` and call handlers | #569 |
| Palantir viewers as translucent spheres in their seat colour, at their camera | How a viewer's "ghostly orb" looks (Q19) | `scenes/actors/player/avatar/avatar_actor.gd` `WATCHER_ORB_*`, `_create_watcher_orb` | #558 |
| A floating yellow text flash over the Paladin when he resists a strike | How his resistance shows (Q18) | `avatar_actor.gd` `_build_resist_label`, `RESIST_FLASH_*` | #557 |
| A thin "Hold" bar above the Paladin's health bar | How the owner sees their hold fading (Q15) | `scenes/ui/avatar_hud.gd` `_build_hold_bar` | #555 |
| Holy site: a pale translucent disc on the ground at the city centre | Holy site art | `scenes/world/places/holy_site.gd` `_build_look` | #559 |
| Treasure room: a grid of box crates, one per good (up to 200), and a floating "Goods: N" plaque; ledger: a wooden stand with a flat book | Treasure room and ledger art | `scripts/interactibles/treasure_room.gd`, `scenes/interactibles/ledger.tscn` | #565 |
| Relic on the ground: a small glowing gold sphere | Relic art | `scenes/world/places/relic_place.gd` | #580 |
| Boss forms are always AI-driven; no player-controlled boss yet | Playing a boss form | `scenes/world/places/holy_site.gd` | #560, #583 |

## Wording

| What | Stands in for | Where | Ticket |
|---|---|---|---|
| Desk book strings (prompts, tab names "All"/"Notes", empty-page and notes hints) and the mm:ss match-time format | The desk's copy | `scripts/interactibles/desk.gd` | #570 |
| Palantir prompts ("Press E to scry", "The Paladin is yours (hold N%). E to take control, Q to return", "E to overpower his hold", "Overpowering him: N%", "Q to return") | The Palantir's copy | `scripts/interactibles/palantir.gd` `get_prompt_text` | #558 |
| "He resists" (his refusal), "Hold" (HUD bar label), "(N watching)" | The Paladin's feedback copy | `avatar_actor.gd` `RESIST_TEXT`, `_update_watcher_label`; `avatar_hud.gd` `HOLD_LABEL` | #557 |
| Win and draw screen text ("You beat the gauntlet. VICTORY!", "<name> beat the gauntlet. DEFEAT.", "The city centre can no longer be corrupted. DRAW.") | The ending's copy | `scripts/menus/win_screen.gd` | #559 |
| Ledger strings ("Press E to read the ledger", "Ledger", "In the treasure room: N", "<place>: N goods, written mm:ss ago", "No report of goods held elsewhere.") and the treasure plaque ("Goods: N") | The ledger's and treasure room's copy | `scripts/interactibles/ledger.gd`, `treasure_room.gd` | #565 |
| Advisor teaching and goal lines ("Have a leader teach another group...", "Bring back what lies here", teaching and relic report lines) | The advisor's voice | `advisor_handoff.gd`, `order_goal.gd`, `group_manager.gd`, `field_work.gd` | #585 |

## Tuning (playtest ticket #587)

| Value | Where |
|---|---|
| Pace presets: unit speed ×1.0 / ×0.4; good-faction growth every 360 s / 1200 s | `scripts/match_config.gd` |
| Starting group size 4; starting couriers 2; 3 route points per order | `scripts/match_config.gd` |
| Assessing groups watch 20 s; stuck after 8 s without progress | `scripts/groups/group_manager.gd` |
| Courier training 90 s; teaching 120 s; successor keeps each maneuver at 50% and half the experience | `scripts/groups/training.gd` |
| Ink takes 3 s to darken; pieces show "?" after 90 s | `scenes/map/map_floor.gd` |
| Site thresholds, corrupt / slip / purify times per type | `data/sites/*.tres` |
| The Paladin counts as 12 troops at a site | `scenes/sites/corruption_site.gd` `AVATAR_STRENGTH` |
| Beacon lasts 20 s | `scenes/sites/corruption_site.gd` `BEACON_SECONDS` |
| Good faction: thresholds +15% per growth step, a site goes dark every 2 steps, draw at step 15 | `scripts/good_faction.gd` |
| Tower whole at 4 sites held; a ruin shows a quarter of its roof | `scenes/world/env/tower.gd` |
| Mirror: ring timeout 20 s, live pose 20 Hz, live voice ~11 kHz in 0.1 s packets, status notice 5 s, chime every 2 s, glow 1 pulse/s | `scripts/interactibles/mirror.gd` consts |
| Paladin takeover: begins at or below 30% HP; troops within 10 m; strength 3 to begin; 15 s at that strength (faster with more); a stalled takeover fades over 30 s | `scenes/actors/player/avatar/paladin_hold.gd` `TAKEOVER_*` |
| Paladin hold fades from full to nothing over 300 s away from your sites; overpowering takes 240 s at a Palantir | `paladin_hold.gd` `HOLD_SECONDS`, `OVERPOWER_SECONDS` |
| Paladin at zero HP lies 5 s, then gets up where he fell with 25% HP | `scenes/actors/player/avatar/avatar_actor.gd` `RECOVER_DELAY`, `RECOVER_HP_FRACTION` |
| Unclaimed Paladin goes home below 50% HP (stays until whole), regenerates 5 HP/s within 6 m of the city centre | `scenes/actors/player/avatar/avatar_ai.gd` `RECOVER_BELOW_FRACTION`, `RECOVER_RADIUS`, `REGEN_PER_SECOND` |
| Control levels 1–4 (1 + AVATAR_CONTROL sites held, capped at 4); resist flash 1.2 s | `avatar_actor.gd` `CONTROL_LEVEL_MAX`, `RESIST_FLASH_SECONDS` |
| Palantir voice ~11 kHz in 0.1 s packets | `scenes/actors/player/avatar/paladin_voice.gd` `VOICE_RATE`, `CHUNK_SECONDS` |
| Balcony: lookout 5 m above and 3 m out from the post, 90° view, 1500 m far plane, mouse speed 0.004, pitch -60..40° | `scripts/interactibles/balcony.gd` consts |
| Day/night: a day lasts 600 s, starts at 0.4, resync every 10 s; night light energy 0.25 (day 1.0), night ambient 0.9 | `scripts/day_night.gd` consts |
| Gauntlet: a held site counts 1 toward strength, a boss-type site 2; a boss has 300 HP and 20 damage, +25% HP and +10% damage per point of strength; appears 8 m from the centre; the Paladin is held at the winner's tower for 0.5 s | `scenes/world/places/holy_site.gd` consts |
| Experience: a kill earns the killer's nearest group (within 25 m) 1 XP, fighting 0.05 XP per second; the three maneuvers need 5 / 15 / 30 XP | `scripts/groups/training.gd`, `group_manager.gd` `KILL_CREDIT_RADIUS`, `data/maneuvers/*.tres` |
| Treasure room shows up to 200 crates (5 x 4 per layer) | `scripts/interactibles/treasure_room.gd` consts |

## Rules standing in for open questions (GDD §11)

| Rule | Open question | Where | Ticket |
|---|---|---|---|
| Day and night are flavour only: only light and sky read the clock | Whether day/night changes play | `scripts/day_night.gd` | #574 |
| A sacked tower is only flagged (`CorruptionSite.sacked`); it spawns nothing yet | What the tower spawns after a sack, and how often | `scenes/sites/corruption_site.gd` | #577 |
| Contested takeover of the Paladin: the player with the most troop strength near him progresses, a tie freezes everyone; his company (troops of his own allegiance) present freezes it | How a contested takeover works (Q14) | `paladin_hold.gd` `_tick_takeover` | #573 |
| Control tiers: level 1 walk; 2 + attack; 3 + run, roll, jump; 4 + abilities. Below level 3 he refuses to strike the good faction | Which actions unlock when, and when resistance ends (Q18) | `avatar_actor.gd` `CONTROL_UNLOCKS`, `RESIST_GOOD_BELOW_LEVEL` | #582 |
| An owned Paladin driven by the AI obeys the same tiers (at level 1 he only walks, and he skips targets he would resist) | Whether the tiers bind him when left alone (Q17/Q18) | `avatar_ai.gd` `_fight`, `_update_target` | #582 |
| Overpowering needs strictly more AVATAR_CONTROL sites than his owner (the good faction counts as none) and runs only while you keep looking through a Palantir; stop looking and it is lost | How "overpower with raw corruption" works (Q14) | `paladin_hold.gd` `can_overpower`, `_tick_overpower` | #554 |
| A player who takes him (takeover or overpower) gets him at full HP | Whether he heals on changing hands | `avatar_actor.gd` `_on_avatar_owner_changed` | #554 |
| His abilities are the Undead profile's avatar abilities whoever holds him | Which abilities the Paladin has | `avatar_actor.gd` `ABILITY_PROFILE_FACTION` | #582 |
| The Paladin is taken to the winning boss's tower gate by a plain teleport (held for 0.5 s so netfox accepts it) | How he gets to the winner's tower (Q21) | `holy_site.gd` `_hand_over` | #576 |
| The gauntlet starts when his owner has him alive inside the holy site's 10 m; it ends (no winner) if he changes hands another way | When exactly the gauntlet starts and aborts | `holy_site.gd` | #559 |
| Bosses fight one at a time, weakest first; a boss that dies is replaced by the next; the Paladin falling to any boss hands him to that boss's player | How the gauntlet is staged (Q20, Q28) | `holy_site.gd` | #560, #561 |
| After the match is won the holy site starts no more gauntlets | Whether play continues after a win | `holy_site.gd` | #559 |
| The advisor picks who teaches whom: the best-taught leader at home teaches one maneuver to the home group knowing the fewest of his | How a player chooses a teacher and a student | `group_manager.gd` `begin_teaching` | #547 |
| Relics lie at sites and are fetched with a "bring back what lies here" goal; the group that brings one home keeps its effect; one falls back where it lay if its carrier dies | How relics are found and carried (Q35) | `field_work.gd` `_retrieve`, `relic_place.gd` | #580 |
| Nobles are never taken as captives, and a group out to make an offer does not attack them | How offers and captures treat nobles | `field_work.gd` `_capture`, `minion_actor.gd` `parley_mode` | #586 |
| Unclaimed at full strength he hunts the nearest held site (never a tower) and fights there, alone (no army yet); he recovers at a `holy_site`-group node or the world origin (the first map's city) | "He leads armies out to hunt and remove corruption" / where the good faction recovers him (Q16) | `avatar_ai.gd` `_drive_unclaimed`, `get_city_centre` | #556 |
| Advisor stand-off spacing: station range 4 m, stand-off 1.8 m, min 1.6 m from the overlord, 1 m clear of the line, 1 m floor margin, 1 s retarget dwell, 0.8 m arrival radius | How close and where the advisor stands near stations (tuning) | `advisor_placement.gd` consts | |
| Expected-piece look (translucent) and missing-piece look (grey, "?"), the prompt notes "should be here by now" / "missing: nobody has found them" | Art for expected/missing/confirmed pieces on the map floor | `map_piece.gd` `refresh`, `_belief_note` | #541 |
| Expected walking speed 3.5 m/s, contradiction radius 25 m, arrived radius 12 m, confirmed look lasts 10 s | How the map extrapolates and judges a group's position (tuning) | `world_model.gd` consts | #541 |
| A courier looks at up to 3 more places along the group's route, waiting half the usual time at each, before reporting a group missing | How long a courier searches (tuning) | `knowledge_manager.gd` `COURIER_SEARCH_POINTS`, `courier_arrival_state.gd` `SEARCH_WAIT_FRACTION` | #541 |
| The goal "Check that my orders were followed" and the courier line "Could not find group N where you thought it was, nor along its route" | Advisor wording (#585) | `order_goal.gd` `NAMES`, `knowledge_manager.gd` `_report_lines` | #541 |
