# Placeholders

Everything here stands in for something Austin hasn't designed yet (CLAUDE.md, "Austin designs; placeholders are
marked"). Each entry is marked `PLACEHOLDER:` at its source, except in `.tscn`, `.tres` and `project.godot`: the Godot editor deletes
comments when it saves those, so their placeholders are listed under "Scenes and resources" below by file and node instead. Only Austin replaces one; when he does, drop the entry.
Numbers are collected for the playtest ticket (#587); content is Austin's to write later and has no tickets (Austin, 2026-10-12).

## Content (Austin's to write)

| What | Stands in for | Where | Ticket |
|---|---|---|---|
| Each temple's and runestone's `grant` (crystal upgrade / runestone power): one default `placeholder_grant` that does nothing yet | What each temple's crystal and each runestone's sealed Dark Lord gives (per site, Austin 2026-10-12) | `scenes/sites/corruption_site.gd` `grant`, set per site in `world.tscn` | |
| Each burial ground's `troop_trait`: one default `placeholder_trait`, recorded on mining but not yet applied to raised troops | What troops each crypt, ancient battlefield and graveyard makes (per burial ground, Austin 2026-10-12) | `scenes/sites/burial_ground.gd` `troop_trait` | |
| Temple and runestone stats (thresholds, timings) carried over from the old avatar and boss site stand-ins; the temple keeps AVATAR_CONTROL, the runestone BOSS_POWER | Temple and runestone tuning | `data/sites/temple.tres`, `data/sites/runestone.tres` | |
| Which site type stands where, and how many | The first map's sites | `scenes/world/world.tscn` (`SiteChapel`, `SiteAvatar`, `SiteBoss`) | |
| Good-faction growth flavour lines | Flavour moments as the good faction grows | `scripts/good_faction.gd` `FLAVOUR_LINES` | #562 |
| Which undead the summoning circle raises, one body each | Unit types and their cost in remains | `scripts/interactibles/summoning_circle.gd` | — |
| The first map's 18 points (4 towers, 4 roads, the 3 sites, the city, 2 villages, 2 mines, an unknown ford and crossing), their labels and links, and WHERE each stands on Austin's 2 km map (Austin 2026-10-10: towns are sources of resources and humans; ~20 corruptible sites and graveyards are planned, none placed): towers on his four tower sites (slot 0 Naf Ishun, 1 Forest Tower, 2 Volcano Tower, 3 Avequel'la, which way each faces); city and holy site at Hopes Gate; villages at Entbridge and Teshfield; the chapel, avatar and boss sites at Forest Ruins, Ale Bend and Valley Cross; the ford and crossing at Mountain Pass and Lastford; roads, mines, Avatar and holy knights placed by eye (table in `art/world/README.md`) | The first map's points, settlements, sites and city, and which of his places is which | `scenes/world/world.tscn` `World/MapPoints`, `World/Places`, `World/Markers`, `Site*`; `art/world/export/world_landscape_2km.tscn` (tower `slot_index`) | |
| Advisor lines: goal names, questions, report sentences, dispatch/refusal lines | The advisor's voice | `scripts/orders/order_goal.gd`, `scripts/interactibles/advisor_handoff.gd`, `scripts/knowledge/knowledge_manager.gd` | |
| Boss form: one stand-in type, scaled by sites held (a skeleton in the Undead colours) | The Undead boss form and how sites feed it | `data/minions/boss_form.tres`, `scenes/actors/minion/types/boss_form.tscn`, `scenes/world/places/holy_site.gd` | |
| Maneuvers: three entries that only record being learned | The list of maneuvers and what each does | `data/maneuvers/*.tres` | |
| Relics: two entries (a runner on first hit; one more route point) and where they lie (one at each of two sites) | The list of relics, what each does, where they are | `data/relics/*.tres`, `scenes/world/world.tscn` (`RelicAvatarSite`, `RelicBossSite`) | |
| Domination of a neutral Paladin: no site or faction grants the ability yet, and the corruption level it needs is unset | Which site or faction type gives the domination ability (Austin 2026-10-12) | GDD §8 "Taking him" (not built yet) | |
| Good faction's march on towers: from growth step 10, every step sends 6 holy knights (+1 per step after) from the city centre at the tower of whoever holds the most sites | When it marches, how many, which unit, and which tower (Austin, 2026-10-12: late in the round) | `scripts/good_faction.gd` `MARCH_*`, `pick_tower_to_march_on` | |
| The Paladin clearing a temple's dungeon corrupts it at once (Austin: "at once or much faster") | Which of the two | `corruption_site.gd` `paladin_cleared` | |
| Temple dungeon layout: 4 greybox rooms in a row joined by corridors (20 x 20 m, 4 m doors), no art; the same one dungeon for every temple (Austin: temples are each designed easier or harder, none designed yet) | Room count and layout (3-5 rooms), look, per-temple difficulty | `scenes/sites/encounter/temple_dungeon.tscn`, `SiteType.encounter_scene`, `data/sites/temple.tres` | |
| Dungeon enemy mix and counts: 12 foes (holy knights and priests, rising per room, no celestial beings), all spawned when he enters | Which guards, priests and minor celestials are in which room, how many | `EncounterSpawn` markers in `temple_dungeon.tscn` | |
| The Priest: a holy knight model with its own stats (40 HP, 10 damage), good faction so the Paladin resists striking it below control level 3 | The priest's name, look and stats | `data/minions/priest.tres`, `scenes/actors/minion/types/priest.tscn` | |
| Runestone arena: one 40 x 40 m greybox room, no art, the same for every runestone | The arena's shape and look, per runestone | `scenes/sites/encounter/runestone_arena.tscn`, `data/sites/runestone.tres` | |
| The sealed Dark Lord is the existing boss-form stand-in (skeleton model) with 400 HP and 25 damage set on its spawn marker; it has no moves of its own | The Dark Lord's look, moves, health and the power it gives | `DarkLord` marker in `runestone_arena.tscn`, `data/minions/boss_form.tres` | |
| Entering and leaving: press E at the site's door area (within 6 m, aimed at it) while driving him; the encounter space sits 400 m below the map, he is moved in and, on a win, a defeat or losing him, moved back to where he entered. Others can't enter while he is inside | How he enters, where he leaves, whether others see it | `scenes/sites/encounter/site_encounter.gd` (`SPACE_Y`, `ENTER_RADIUS`, prompt wording), `site_encounter.tscn` | |
| Encounter navmeshes are baked from the greybox colliders (agent radius 0.6) | Re-bake after any layout change | `tools/bake_encounter_navmesh.gd`, `scenes/sites/encounter/placeholder/` | |
| Backdrop around the map: a generated low-poly ring (mountain walls N and S, rolling hills W, sea E, per Austin 2026-10-12) out to 5 km; its shapes, heights, corner blends, radius and rock/sand colouring | The land, mountains and sea beyond the map as Austin sculpts them | `art/world/source/world_backdrop.blend`, `tools/blender/build_backdrop.py` (constants) | #620 |
| Burial grounds: a crypt under the temple and an ancient battlefield under the runestone, 12-14 m off; one body per 30 s while the parent is held, 20 bodies each; towns have none yet (town control is not built) | Where burial grounds stand, mining rate and depth | `world.tscn` `SiteAvatar/BurialGround`, `SiteBoss/BurialGround`; `burial_ground.gd` | |

## Art and look

| What | Stands in for | Where | Ticket |
|---|---|---|---|
| World blockout: the whole landscape (heights, mountains, rivers, roads, forests, coast), the stand-in shape of every place, the props and the 32 px textures, all read off the sketch by eye | The world's real geography and art | `art/world/` (see its README), generators in `tools/blender/` | #604 |
| Textures on Austin's hand-made map: `geo` is vertex-painted (`Splat` layer: black grass, red rock, green dirt, blue sand; the channel -> texture mapping and the 50% threshold are guesses, seeded from the old height / slope look); `Pale River` and `The Still Lake` water; `elder wood` and `northwood` darkened `leaf_pine` (no forest texture exists); nearest-filtered, 8 m tile size is a guess | His real ground art | `art/world/source/world_landscape.blend`, `tools/blender/add_splat.py`, `tools/blender/texture_austin_map.py` | #604 |
| Open-world scene: sun, sky and fog, and the navmesh tuning (2 km: 1 m cells, climb 1 m, vertices put on the ground and edges split (40 m flat, down to 8 m on slopes; ~30k triangles), agents search 131072 polygons and reach a waypoint within 2.5 m; 6 km: 1.5 m cells (1.25 and finer make the bake fail), climb 1.5 m, slope limits scaled with the map's extra steepness, baked without the towers like 400 m (0.5 m cells); agent radius 0.5 m, height 2.9 m, a little over the 2.86 m capsule, so ground under low overhangs is not walkable (climb >= cell x tan(slope) or slopes split the mesh), walkable on `geo` and tower floors) | The world's real lighting and nav settings | `scenes/world/open_world/open_world_<size>.tscn`, `open_world_<size>_navmesh.res`, `tools/bake_open_world_navmesh.gd` | #605 |
| Godot ground shader and water/forest materials: the splat channel mapping, 50% threshold and 8 m tile | His real ground art | `shaders/world_ground.gdshader`, `art/world/materials/` | #605 |
| Water (Austin, 2026-10-12: river and sea block, crossings at the river towns): the look (`water_body.tscn` uses `water_placeholder.tres`), the levels (river 1 m under its banks, lake 0.3 m under its rim, sea at the ocean plane), the crossing spots (middle of the river nearest each town; Hopes Gate one per branch) and size (`radius_m` 20 m, Entbridge 45 m), the bank walls (4 m over the bank), the sink depths in `carve_water.py` (river 3 m, lake 4 m, sea 8 m under the plane; banks 6 / 15 / 40 m) | The real water, crossings and shores | `scenes/world/water/`, `scripts/build/world_areas.gd`, `tools/blender/carve_water.py`, `art/world/export/world_landscape_2km.tscn` | #615 |
| Curved world: horizon and eye height per world size (2 km: 1500 m / 40 m; the size builder scales horizon by the width, eye height by the height: 400 m 300 / 8, 6 km 4500 / 200) (R = horizon^2 / (2 x eye height)), and the whole look of the bend | How far the world curves away, or whether it does | `WorldCurve` node in each world scene (`scripts/world_curve.gd`; `project.godot` `[shader_globals]` is the fallback), `shaders/curved_world.gdshaderinc` | |
| The look of every place: `pois/<snake>.blend` blockouts exported to glb (`export/<snake>.glb`) with a stand-in curved-world material per texture (`materials/poi/mat_*.tres`, shader `shaders/poi_uv.gdshader`); each POI's `ground` patch and the ground slab of its collision proxy are left out of the export (`geo` is the ground); the place scenes `art/world/pois/<snake>.tscn` are empty inheriting shells | What each place looks like, its collision, and what Godot-only things it holds | `art/world/pois/`, `tools/blender/export_pois.py`, `art/world/pois/poi_post_import.gd` | |
| Places and sites that stood inside a POI's buildings moved off them (Valley Cross: BossSite, SiteBoss, RelicBossSite 22 m north; Entbridge: SettlementSE 16 m north-west of its marker; Teshfield: SettlementNW 12 m; Forest Ruins: Chapel and SiteChapel 6 m east), found by clearance probes, not designed; the Avequel'la and Naf Ishun POI blockouts stand around their towers (the castle's 54 x 46 m collision overlaps the tower's base) | Where each place's centre really is | `scenes/world/world.tscn` | |
| Forests and water grown from his guide outlines (`elder wood`, `northwood`, `Pale River`, `The Still Lake`): the trees are `props.blend` `tree_cone` / `tree_lollipop` at random (half each), one per 100 m2 on a jittered grid, scale 0.8 to 1.3, 0.2 m sunk, none within 60 m of a marker, none on slopes over 0.9, none in water, in 200 m chunks hidden beyond 500 m / 1500 m / 3500 m (400 m / 2 km / 6 km), no collision (units walk through), no shadows; the lake is a flat surface 0.3 m (times the size's height factor) over the median ground height of its outline (no basin is carved); the river is its footprint cut to 12 m triangles (times the width factor) and draped 0.25 m (times the height factor) over the ground (no channel carved, no collision, units wade through) | The real forests, tree looks, density and water | `scripts/build/world_areas.gd` consts, `art/world/export/areas_<size>.json`, `art/world/export/world_areas_<size>.tscn` | |
| World size, 2000 m x 1500 m | The real world scale, decided by the scale test | `tools/blender/world_data.py` `WORLD_W/WORLD_H`, `world_root` in `world_landscape.blend` | #603 |
| `pois/*.blend` files with no marker in Austin's map yet (`northwood`, `old_gate`, `elder_woods`, `holy_site`, `graveyard`), and the old spellings still in the generated blockout (`world_data.py`, `build_pois.py`). His marker names (2026-10-09) are authoritative for the other 13 | Which of these places he wants, and their names | `art/world/pois/`, `tools/blender/world_data.py` | |
| Seat colours (one per tower) and the good faction's colour | How players tell each other apart | `scripts/game_constants.gd` `SEAT_COLORS`, `GOOD_COLOR` | — |
| Site marker (stone disc + tinted crystal) and the beacon (a coloured column of light) | Site and beacon art | `scenes/sites/corruption_site.gd` | #553 |
| Desk look (box table and red book) | Desk and book art | `scenes/interactibles/desk.tscn` | #570 |
| Balcony look (stone post and brass spyglass) | Balcony art | `scenes/interactibles/balcony.tscn` | — |
| Balcony wording ("Press E to look out", "E / Q to return") | The balcony's UI copy | `scripts/interactibles/balcony.gd` | — |
| Fog (where: the woods, Austin 2026-10-13): a dense ground-hugging bank over each wood, shaped by its baked footprint (outline plus 40 m spill, 30 m fade, `tools/bake_forest_fog.gd`, 6 m pixels); how thick by day and at night (volumes x2), its height (full to 3 m above the ground, gone by 14 m), colour, how much sun tints it (0.3), drift speed and direction, wisp size and gaps, how far it is drawn (400 m) and how much it veils the sky (20%); no haze elsewhere | The world's real fog | `scenes/world/fog/world_fog.tscn`, `shaders/drifting_fog.gdshader`, `art/world/export/fog/`, `world.tscn` Environment `volumetric_fog_*` and the sun's `light_volumetric_fog_energy` | #624 |
| Clouds: one drifting layer in the sky shader, lit by the sun or moon; how much sky they cover (45%), their size, softness, colours, how much the sun tints them (0.3), drift speed and direction, the fade toward the horizon; they are left out of the sky's lighting pass | The world's real clouds | `shaders/sky_clouds.gdshader`, `world.tscn` `ShaderMaterial_sky` and `NoiseTexture2D_clouds` | |
| Sky, sun and moon colours, night light and ambient levels | Day/night look | `scripts/day_night.gd` |  |
| Ruined tower = hidden roof pieces, revealed as sites are held | Tower restoration stages | `scenes/world/env/tower.gd` | #567 |
| Map floor illustration (parchment + terrain contours, now baked from his 2 km ground by `tools/bake_map_illustration.gd`: 256 px, shading and 20 m contours), point discs, chess pieces, ink ribbons | Map art | `scenes/map/` | #534, #538 |
| Held scroll (a cylinder at the corner of the view); advisor subtitles and choice panel | Scroll and dialogue look | `overlord_actor.gd`, `scenes/ui/advisor_dialogue.gd` | — |
| Mirror ring: a pulsing purple halo quad plus light, and a synthesized two-tone chime | How a ringing mirror looks and sounds (Q34: "chimes or glows") | `scripts/interactibles/mirror.gd` `_setup_ring_effects`, `_make_chime` | #569 |
| Mirror prompt and notice text ("Press E to call", "No answer. Recording a message.", "Line busy.", "Call ended.", ...) | The mirror's UI wording | `scripts/interactibles/mirror.gd` `get_prompt_text` and call handlers | #569 |
| Palantir viewers as translucent spheres in their seat colour, at their camera | How a viewer's "ghostly orb" looks (Q19) | `scenes/actors/player/avatar/avatar_actor.gd` `WATCHER_ORB_*`, `_create_watcher_orb` | #558 |
| A floating yellow text flash over the Paladin when he resists a strike | How his resistance shows (Q18) | `avatar_actor.gd` `_build_resist_label`, `RESIST_FLASH_*` | #557 |
| A thin "Hold" bar above the Paladin's health bar | How the owner sees their hold fading (Q15) | `scenes/ui/avatar_hud.gd` `_build_hold_bar` | #555 |
| Holy site: a pale translucent disc on the ground at the city centre | Holy site art | `scenes/world/places/holy_site.gd` `_build_look` | #559 |
| Treasure room: a grid of box crates, one per good (up to 200), and a floating "Goods: N" plaque; ledger: a wooden stand with a flat book | Treasure room and ledger art | `scripts/interactibles/treasure_room.gd`, `scenes/interactibles/ledger.tscn` | #565 |
| Relic on the ground: a small glowing gold sphere | Relic art | `scenes/world/places/relic_place.gd` | |
| Boss forms are always AI-driven; no player-controlled boss yet | Playing a boss form | `scenes/world/places/holy_site.gd` | #560 |
| No look for a stuck group's piece: the model has it (`WorldModel.piece_state` = `&"stuck"`, the piece stays where they gave up) and its prompt shows "(stuck)" from the report's status, but it is drawn like a confirmed piece | How a stuck group looks on the map floor | `scripts/knowledge/world_model.gd`, `scenes/map/map_piece.gd` `refresh` | #627 |
| A stranded courier (home unreachable too) stands where it stopped, never rejoins the courier pool, and its owner hears only "a courier is lost" (what it carried never arrives; its undelivered orders show as lost) | What happens to a courier that cannot get home | `scripts/knowledge/courier_errand.gd`, `knowledge_manager.gd` `courier_stranded` | #627 |

## Wording

| What | Stands in for | Where | Ticket |
|---|---|---|---|
| Desk book strings (prompts, tab names "All"/"Notes", empty-page and notes hints) and the mm:ss match-time format | The desk's copy | `scripts/interactibles/desk.gd` | #570 |
| Palantir prompts ("Press E to scry", "The Paladin is yours (hold N%). E to take control, Q to return", "E to overpower his hold", "Overpowering him: N%", "Q to return") | The Palantir's copy | `scripts/interactibles/palantir.gd` `get_prompt_text` | #558 |
| "He resists" (his refusal), "Hold" (HUD bar label), "(N watching)" | The Paladin's feedback copy | `avatar_actor.gd` `RESIST_TEXT`, `_update_watcher_label`; `avatar_hud.gd` `HOLD_LABEL` | #557 |
| Win and draw screen text ("You beat the gauntlet. VICTORY!", "<name> beat the gauntlet. DEFEAT.", "The city centre can no longer be corrupted. DRAW.") | The ending's copy | `scripts/menus/win_screen.gd` | #559 |
| Ledger strings ("Press E to read the ledger", "Ledger", "In the treasure room: N", "<place>: N goods, written mm:ss ago", "No report of goods held elsewhere.") and the treasure plaque ("Goods: N") | The ledger's and treasure room's copy | `scripts/interactibles/ledger.gd`, `treasure_room.gd` | #565 |
| Advisor teaching and goal lines ("Have a leader teach another group...", "Bring back what lies here", teaching and relic report lines) | The advisor's voice | `advisor_handoff.gd`, `order_goal.gd`, `group_manager.gd`, `field_work.gd` | |
| A courier's errand ("The courier could not reach group N: the way was blocked near X.", "The courier saw group N but could not reach them near X; your orders were not handed over.", "Group N is stuck near X; they have not arrived.", "Group N was seen on its way / where you sent them / coming home", "The courier could not finish its route", "A courier is lost", record title "A courier's errand") | The advisor's voice, desk `courier` records | `scripts/knowledge/knowledge_manager.gd` `_errand_notes`, `courier_stranded`, `_report_title` | #627 |

## Tuning (playtest ticket #587)

| Value | Where |
|---|---|
| Pace presets: unit speed ×1.0 / ×0.4; good-faction growth every 360 s / 1200 s | `scripts/match_config.gd` |
| Starting group size 4; starting couriers 2; 3 route points per order | `scripts/match_config.gd` |
| Assessing groups watch 20 s; stuck after 8 s without progress | `scripts/groups/group_manager.gd` |
| A group under orders gives up and forms ranks after 45 s without getting 1 m closer to its next point (fighting pauses the count) | `scripts/groups/group_manager.gd` `GIVE_UP_SECONDS` |
| A courier turns home after 30 s without getting 1 m closer to its stop (the same on the way home, then it stops); stranded, it is reported lost after 60 s; it recognises its group within 40 m in line of sight (eyes 1.5 m up) | `scripts/knowledge/courier_errand.gd` `GIVE_UP_SECONDS`, `PROGRESS_METRES`, `LOST_SECONDS`, `SIGHT_METRES`, `EYE_HEIGHT` |
| Courier training 90 s; teaching 120 s; successor keeps each maneuver at 50% and half the experience | `scripts/groups/training.gd` |
| Ink takes 3 s to darken; pieces show "?" after 90 s | `scenes/map/map_floor.gd` |
| Site thresholds, corrupt / slip / purify times per type | `data/sites/*.tres` |
| The Paladin counts as 12 troops at a site | `scenes/sites/corruption_site.gd` `AVATAR_STRENGTH` |
| Beacon lasts 20 s | `scenes/sites/corruption_site.gd` `BEACON_SECONDS` |
| Good faction: thresholds +15% per growth step, a site goes dark every 2 steps, draw at step 15 | `scripts/good_faction.gd` |
| Tower whole at 4 sites held; a ruin shows a quarter of its roof | `scenes/world/env/tower.gd` |
| Mirror: ring timeout 20 s, live pose 20 Hz, live voice ~11 kHz in 0.1 s packets, status notice 5 s, chime every 2 s, glow 1 pulse/s | `scripts/interactibles/mirror.gd` consts |
| Paladin contest: open for 60 s after a held Paladin is defeated; troops within 10 m; strength 3 to begin; 15 s at that strength (faster with more); a stalled takeover fades over 30 s | `scenes/actors/player/avatar/paladin_hold.gd` `CONTEST_SECONDS`, `TAKEOVER_*` |
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
| Tower trickle (a steady trickle is Austin's, 2026-10-12): one default unit every 45 s, paused while you have 6 fighting units | Trickle rate, cap and unit type | `scenes/world/env/tower.gd` `TRICKLE_*` | |
| Contested takeover of the Paladin: the player with the most troop strength near him progresses, a tie freezes everyone; his company (troops of his own allegiance) present freezes it | How the contest over a defeated, held Paladin resolves (Q14) | `paladin_hold.gd` `_tick_takeover` | #573 |
| Control tiers: level 1 walk; 2 + attack; 3 + run, roll, jump; 4 + abilities. Below level 3 he refuses to strike the good faction | Which action sits in which tier (tiers plus resistance, temple crystals raise control: Austin, 2026-10-12) | `avatar_actor.gd` `CONTROL_UNLOCKS`, `RESIST_GOOD_BELOW_LEVEL` |  |
| An owned Paladin driven by the AI obeys the same tiers (at level 1 he only walks, and he skips targets he would resist) | Whether the tiers bind him when left alone (Q17/Q18) | `avatar_ai.gd` `_fight`, `_update_target` |  |
| Overpowering needs strictly more AVATAR_CONTROL sites than his owner (the good faction counts as none) and runs only while you keep looking through a Palantir; stop looking and it is lost | How "overpower with raw corruption" works (Q14) | `paladin_hold.gd` `can_overpower`, `_tick_overpower` | #554 |
| A player who takes him (takeover or overpower) gets him at full HP | Whether he heals on changing hands | `avatar_actor.gd` `_on_avatar_owner_changed` | #554 |
| His abilities are the Undead profile's avatar abilities whoever holds him | Which abilities the Paladin has | `avatar_actor.gd` `ABILITY_PROFILE_FACTION` |  |
| The gauntlet starts when his owner has him alive inside the holy site's 10 m; it ends (no winner) if he changes hands another way | When exactly the gauntlet starts and aborts | `holy_site.gd` | #559 |
| Bosses fight one at a time, weakest first; a boss that dies is replaced by the next; the Paladin falling to any boss hands him to that boss's player | How the gauntlet is staged (Q20, Q28) | `holy_site.gd` | #560, #561 |
| After the match is won the holy site starts no more gauntlets | Whether play continues after a win | `holy_site.gd` | #559 |
| The advisor picks who teaches whom: the best-taught leader at home teaches one maneuver to the home group knowing the fewest of his | How a player chooses a teacher and a student | `group_manager.gd` `begin_teaching` | #547 |
| Relics lie at sites and are fetched with a "bring back what lies here" goal; the group that brings one home keeps its effect; one falls back where it lay if its carrier dies | How relics are found and carried (Q35) | `field_work.gd` `_retrieve`, `relic_place.gd` | |
| Nobles are never taken as captives, and a group out to make an offer does not attack them | How offers and captures treat nobles | `field_work.gd` `_capture`, `minion_actor.gd` `parley_mode` | |
| Unclaimed at full strength he hunts the nearest held site (never a tower) and fights there, alone (no army yet); he recovers at a `holy_site`-group node or the world origin (the first map's city) | "He leads armies out to hunt and remove corruption" / where the good faction recovers him (Q16) | `avatar_ai.gd` `_drive_unclaimed`, `get_city_centre` | #556 |
| Advisor stand-off spacing: station range 4 m, stand-off 1.8 m, min 1.6 m from the overlord, 1 m clear of the line, 1 m clear of the walk past the overlord, 1 m floor margin, 1 s retarget dwell, 0.8 m arrival radius | How close and where the advisor stands near stations (tuning) | `advisor_placement.gd` consts | |
| Expected-piece look (translucent) and missing-piece look (grey, "?"), the prompt notes "should be here by now" / "missing: nobody has found them" | Art for expected/missing/confirmed pieces on the map floor | `map_piece.gd` `refresh`, `_belief_note` | #541 |
| Expected walking speed 3.5 m/s, contradiction radius 25 m, arrived radius 12 m, confirmed look lasts 10 s | How the map extrapolates and judges a group's position (tuning) | `world_model.gd` consts | #541 |
| A courier looks at up to 3 more places along the group's route, waiting half the usual time at each, before reporting a group missing | How long a courier searches (tuning) | `knowledge_manager.gd` `COURIER_SEARCH_POINTS`, `courier_arrival_state.gd` `SEARCH_WAIT_FRACTION` | #541 |
| The goal "Check that my orders were followed" and the courier line "Could not find group N where you thought it was, nor along its route" | Advisor wording | `order_goal.gd` `NAMES`, `knowledge_manager.gd` `_report_lines` | #541 |

## Tuning (2 km game world)

Numbers I changed so the old tuning fits the 2 km map; none is designed (playtest ticket #587).

| Value | Now | Was | Where |
|---|---|---|---|
| Balcony lookout far plane | 3500 m | 1500 m | `scenes/interactibles/balcony.tscn` |
| Sun shadow distance | 400 m | 100 m (default) | `scenes/world/world.tscn` `DirectionalLight3D` |
| Map floor: enemy sightings sharing one piece | 4% of the world's width (80 m at 2 km) | 15 m | `scenes/map/map_floor.gd` `ENEMY_CLUSTER_FRACTION` |
| Map floor: the world rectangle it shows | 2000 x 2000 m | 360 x 360 m | `scenes/map/map_floor.gd` `world_rect` |
| Navmesh polygons a path search may visit | 131072 (the 6 km mesh has ~66k, over the old 65536) | 4096 (engine default) | `group_manager.gd` `PATH_SEARCH_POLYGONS`, minion and avatar agents |
| Navigation map: edge connection margin and link connection radius | 2 m, 2.5 m | 0.25 m, 1 m (engine defaults) | `project.godot` `[navigation]` |
| Each tower's jump-off link (summoned units jump from the balcony to the ground) lands at the ground below that tower | per tower | 40 m below the balcony | `art/world/export/world_landscape_2km.tscn` `JumpPoint` overrides |
| Waypoint reached within (the navmesh sits up to ~1 m off the ground) | 2.5 m minions, 2 m Avatar | 1 m, 0.5 m | `minion_actor.tscn`, `avatar_actor.tscn` `path_desired_distance` |
| A chasing or walking minion re-paths only once its goal has moved (each re-path is a full search of the navmesh; every tick was dropping the game to 3 FPS in fights) | 1.5 m | every tick | `chase_state.gd`, `advisor_follow_state.gd` `REPATH_DISTANCE` |

## Tuning (400 m and 6 km game worlds, Austin, 2026-10-10)

`scenes/world/world_400m.tscn` and `world_6km.tscn` are built from the 2 km scenes by `scripts/build/build_world_sizes.gd` (see
`art/world/README.md`, "Sizes"): the layout is the 2 km one scaled around the origin (400 m: 0.2 wide, 0.2 tall; 6 km: 3 wide,
5 tall), placed on that size's ground. None of it is designed; the numbers are mine.

| Value | 400 m | 2 km | 6 km | Where |
|---|---|---|---|---|
| Sun shadow distance | 200 m | 400 m | 800 m | `SIZE_TUNING` in `build_world_sizes.gd` |
| Balcony lookout far plane | 800 m | 3500 m | 10500 m | `SIZE_TUNING`, set per tower in `world_landscape_<size>.tscn` |
| Map floor rectangle and picture | 400 x 400 m | 2000 x 2000 m | 6000 x 6000 m | `MapFloor.world_rect`, `illustration` per tower in `world_landscape_<size>.tscn`; picture by `tools/bake_map_illustration.gd` |
| A tower that does not fit the smaller or steeper ground (its gate off the ground, or its units cannot walk out) is turned in 15 degree steps; the yaw is the 2 km placeholder anyway | | | | `_turn_to_fit` in `build_world_sizes.gd`, `YAW_STEP_DEGREES`, `FIT_*` |
| Roads, mines and the Avatar, which are not on his markers, move off ground steeper than 0.45 | | | | `_walkable_spot` in `build_world_sizes.gd` |
| Anything within 60 m of a marker (2 km coordinates) keeps its real offset from it at 400 m and 6 km instead of scaling (POIs keep their size) | | | | `_place`, `POI_BOUND_M` in `build_world_sizes.gd` |
| A POI closer than 60 m (that size) to a tower on another marker is left out of that size (400 m: Hell's Mouth, 20 m from the Volcano Tower) | | | | `POI_TOWER_CLEAR_M` in `build_world_sizes.gd` |
| A node placed by eye whose ground the navmesh leaves over 1 m away moves to the nearest spot it does not (6 km: RoadWest 16 m, RoadNorth 6 m) | | | | `NAV_SNAP_M` in `build_world_sizes.gd` |
| Anything within 100 m of a tower (2 km coordinates) keeps its offset from the tower instead of scaling | | | | `TOWER_BOUND_M` |
| Camera far plane of the overlord and Avatar | engine default (4000 m) at every size | | | their camera scenes (not scaled) |

Known: at 6 km the Volcano Tower (slot 2) stands on ground the baked mesh does not connect to the rest of the map, so units
summoned there cannot walk out (`test_world_layout` fails two checks for it); no yaw fixes it.


## Movement and pathing tuning (audit 2026-10-13)
- PLACEHOLDER: tuning — all in code, marked `PLACEHOLDER: tuning`: `ChaseState` (FORCED_REPATH_INTERVAL, ENGAGE_MARGIN, UNREACHABLE_GAP), `IdleState` (REENTER_MARGIN), `MinionState` (MAX_VERTICAL_REACH, MAX_NAV_GAP, IGNORE_SECONDS, SCAN_INTERVAL, SCAN_STAGGER_MSEC), `AvatarAI` (reach, blacklist and no-progress numbers), `MinionActor` (stuck-check and Run-to-Idle numbers, floor_max_angle 53.2 deg), `JumpState.MAX_AIR_TIME`, `RetreatState.REPATH_DISTANCE`, bake `AGENT_HEIGHT` 3.1 / `AGENT_RADIUS` 0.7 (2 km navmesh not rebaked yet).

## Scenes and resources (no comments in these files; moved here 2026-10-13)

- `art/world/export/world_backdrop_2km.tscn`, whole file: the backdrop is generated (tools/blender/build_backdrop.py) for Austin to sculpt in art/world/source/world_backdrop.blend
- `art/world/pois/ale_bend.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Ale Bend's place scene. Its look is art/world/pois/export/ale_bend.glb (from ale_bend.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/avequella.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Avequel'la's place scene. Its look is art/world/pois/export/avequella.glb (from avequella.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/entbridge.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Entbridge's place scene. Its look is art/world/pois/export/entbridge.glb (from entbridge.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/far_harbor.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is far harbor's place scene. Its look is art/world/pois/export/far_harbor.glb (from far_harbor.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/forest_ruins.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Forest Ruins's place scene. Its look is art/world/pois/export/forest_ruins.glb (from forest_ruins.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/hells_mouth.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Hell's Mouth's place scene. Its look is art/world/pois/export/hells_mouth.glb (from hells_mouth.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/hopes_gate.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Hopes Gate's place scene. Its look is art/world/pois/export/hopes_gate.glb (from hopes_gate.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/lastford.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Lastford's place scene. Its look is art/world/pois/export/lastford.glb (from lastford.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/mountain_pass.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Mountain Pass's place scene. Its look is art/world/pois/export/mountain_pass.glb (from mountain_pass.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/naf_ishun.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Naf Ishun's place scene. Its look is art/world/pois/export/naf_ishun.glb (from naf_ishun.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/teshfield.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Teshfield's place scene. Its look is art/world/pois/export/teshfield.glb (from teshfield.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/valley_cross.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Valley Cross's place scene. Its look is art/world/pois/export/valley_cross.glb (from valley_cross.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `art/world/pois/veilton.tscn`, whole file: Created by scripts/build/build_world_sizes.gd, once, and never rewritten: this is Veilton's place scene. Its look is art/world/pois/export/veilton.glb (from veilton.blend, Austin edits that); add Godot-only things (lights, sites, sounds) here. the look is a blockout stand-in, not designed by Austin
- `data/maneuvers/placeholder_a.tres`, whole file: not designed by Austin (ticket #581)
- `data/maneuvers/placeholder_b.tres`, whole file: not designed by Austin (ticket #581)
- `data/maneuvers/placeholder_c.tres`, whole file: not designed by Austin (ticket #581)
- `data/minions/boss_form.tres`, whole file: boss forms are not designed (ticket #583). One stand-in type, scaled in the gauntlet by the sites its player holds (HolySite._scale_boss).
- `data/minions/priest.tres`, whole file: the Goddess's priest — name, stats and look are not designed (temple dungeons). Good faction, so the Paladin resists striking it below control level 3 (AvatarActor).
- `data/relics/placeholder_a.tres`, whole file: not designed by Austin (ticket #580)
- `data/relics/placeholder_b.tres`, whole file: not designed by Austin (ticket #580)
- `project.godot`, `3d/default_edge_connection_margin` on section `[navigation]`: tuning — the 2 km map's towers stand at different heights above their ground, so the towers' own navmesh (cell 0.25) and the world's (cell 1) only join within these distances (the tower's jump-off link lands on the ground).
- `scenes/actors/minion/minion_actor.tscn`, BoxMesh `BoxMesh_carry`: art — a box on the back while carrying; the script tints it by what it is.
- `scenes/actors/minion/minion_actor.tscn`, `path_desired_distance` on `NavigationAgent3D`: tuning — the 2 km map's navmesh has ~24k polygons; the default 4096 gave up on long routes, and the mesh sits up to ~1 m off the ground in places, so a waypoint counts as reached within 2.5 m (the default 1 m made units oscillate at a spot where the path's first point was 1 m below them)
- `scenes/actors/minion/types/boss_form.tscn`, whole file: art — a skeleton stands in for a boss form (ticket #583)
- `scenes/actors/minion/types/noble.tscn`, whole file: art — a holy knight stands in for a noble
- `scenes/actors/minion/types/priest.tscn`, whole file: art — a holy knight stands in for a priest
- `scenes/actors/minion/types/thrall.tscn`, whole file: art — a skeleton stands in for a thrall
- `scenes/actors/minion/types/villager.tscn`, whole file: art — a holy knight stands in for a villager
- `scenes/actors/player/avatar/avatar_actor.tscn`, `path_desired_distance` on `NavAgent`: tuning — path_desired_distance was 0.5; the 2 km navmesh sits up to ~1 m off the ground
- `scenes/actors/player/avatar/avatar_actor.tscn`, `path_search_max_polygons` on `NavAgent`: tuning — the 2 km map's navmesh has ~24k polygons; the default 4096 gave up on long routes
- `scenes/actors/player/avatar/avatar_actor.tscn`, node `ResistLabel`: wording — flashed when he refuses an order he resists.
- `scenes/actors/player/avatar/watcher_orb.tscn`, SphereMesh `SphereMesh_orb`: art — a ghostly orb at a remote viewer's scry camera; the script tints it with the viewer's colour. One is instanced per viewer.
- `scenes/actors/player/overlord/overlord_actor.tscn`, CylinderMesh `CylinderMesh_scroll`: art — a rolled scroll held at the bottom right of the view.
- `scenes/interactibles/balcony.tscn`, node `LookoutPivot`: The lookout rig: turned with the mouse while the balcony is open. tuning — where the lookout sits, the wide view and a far plane long enough for beacons over sites anywhere on the 2 km map and the backdrop around it (5 km out; was 3500 m).
- `scenes/interactibles/crate.tscn`, BoxMesh `BoxMesh_crate`: art — a plain box; one is instanced per good in the treasure room.
- `scenes/interactibles/desk.tscn`, StyleBoxFlat `StyleBoxFlat_paper`: look — the book's paper, ink and sizes.
- `scenes/interactibles/desk.tscn`, node `BookLayer/Panel/Column/Scroll/Body/NotesEdit`: wording — the notes hint.
- `scenes/interactibles/desk_entry.tscn`, node `DeskEntry`: look — one record in the desk book: a heading and its text.
- `scenes/interactibles/desk_tab_button.tscn`, StyleBoxFlat `StyleBoxFlat_tab`: look — one tab on the desk book (the selected tab shows paper).
- `scenes/interactibles/ledger.tscn`, node `Ledger`: art — a stand with a flat book
- `scenes/interactibles/ledger.tscn`, node `LedgerLayer`: The open page: hidden until E at your own ledger. look and wording — paper, ink and sizes.
- `scenes/interactibles/ledger_line.tscn`, node `LedgerLine`: look — one line of the ledger page.
- `scenes/interactibles/mirror.tscn`, StandardMaterial3D `StandardMaterial3D_ring`: art direction — the stand-in ring look: a pulsing coloured halo quad and light on the mirror (the script drives their alpha and energy).
- `scenes/interactibles/mirror.tscn`, node `Model/Mirror3D/ChimePlayer`: art direction — the stand-in chime is two synthesized sine tones (the script fills in the stream).
- `scenes/interactibles/scry_rig.tscn`, node `ScryPivot`: The palantir's scrying camera: orbits the Paladin. The pivot is moved onto him and turned with the mouse; the camera sits behind and above (CamRot pitches it). Instanced when someone looks in and freed when they stop. tuning — the orbit distance and height.
- `scenes/interactibles/treasure_room.tscn`, node `Crates`: art and layout — a crate per good is instanced under here, stacked by the script
- `scenes/interactibles/treasure_room.tscn`, node `Plaque`: wording and spot — the plaque says the exact number of goods
- `scenes/map/map_floor.tscn`, PlaneMesh `PlaneMesh_floor`: art — the illustration is generated from Austin's ground heights (hill shading on parchment; tools/bake_map_illustration.gd) until his map art (ticket #534). The script sizes the plane to floor_size.
- `scenes/map/map_line_pencil.tscn`, whole file: art direction — the pencil line of the order being drafted.
- `scenes/map/map_line_route.tscn`, whole file: art direction — thin pencil road between two known points.
- `scenes/map/map_piece.tscn`, CylinderShape3D `CylinderShape3D_piece`: art — a primitive chess piece tinted by owner.
- `scenes/map/map_piece_avatar.tscn`, whole file: art — the Paladin's piece: the same chess piece, 1.6 times larger.
- `scenes/map/map_point_marker.tscn`, CylinderShape3D `CylinderShape3D_marker`: art — an ink disc with the point's name written beside it.
- `scenes/sites/corruption_site.tscn`, CylinderMesh `CylinderMesh_base`: art — a stone disc, a pillar tinted by holder, and a beacon of light.
- `scenes/sites/encounter/runestone_arena.tscn`, whole file: RunestoneArena placeholder runestone arena — layout, room count, enemy mix and counts, look: all stand-ins, not designed (PLACEHOLDERS.md). Greyboxed with primitive meshes. Navmesh baked by tools/bake_encounter_navmesh.gd into runestone_arena_navmesh.res.
- `scenes/sites/encounter/site_encounter.tscn`, whole file: how entering works — an interact prompt at the site (E, aimed at it). Not designed.
- `scenes/sites/encounter/temple_dungeon.tscn`, whole file: TempleDungeon placeholder temple dungeon — layout, room count, enemy mix and counts, look: all stand-ins, not designed (PLACEHOLDERS.md). Greyboxed with primitive meshes. Navmesh baked by tools/bake_encounter_navmesh.gd into temple_dungeon_navmesh.res.
- `scenes/ui/advisor_dialogue.tscn`, node `AdvisorDialogue`: wording and look — the advisor's character is Austin's (#585).
- `scenes/ui/avatar_hud.tscn`, node `HoldBar/HoldLabel`: wording — label on the hold bar.
- `scenes/world/env/tower.tscn`, node `TreasureRoom`: where the treasure room and ledger stand in the hall (ticket #565)
- `scenes/world/fog/world_fog.tscn`, node `WorldFog`: the whole fog look and how thick (PLACEHOLDERS.md "Fog"); where: the woods (Austin, 2026-10-13)
- `scenes/world/places/body.tscn`, BoxMesh `BoxMesh_slab`: art — a pale slab.
- `scenes/world/places/holy_site.tscn`, CylinderMesh `CylinderMesh_disc`: art — a pale disc on the ground marks the holy site. The script sizes the disc to the site's radius.
- `scenes/world/places/relic_place.tscn`, SphereMesh `SphereMesh_gem`: art — a small gold gem on the ground.
- `scenes/world/places/resource_site.tscn`, BoxMesh `BoxMesh_stack`: art — a crate stack that grows with the pile.
- `scenes/world/world.tscn`, ShaderMaterial `ShaderMaterial_sky`: clouds (PLACEHOLDERS.md "Clouds"); the sky colours below are the ones set in the editor before the clouds
- `scenes/world/world.tscn`, `volumetric_fog_enabled` on `Environment_s4jie`: volumetric fog look (thin haze everywhere; length = how far it is drawn, beyond that the view is clear)
- `scenes/world/world.tscn`, `light_volumetric_fog_energy` on `DirectionalLight3D`: fog look, how much the sun tints the fog (1 = fully)
- `scenes/world/world.tscn`, `directional_shadow_max_distance` on `DirectionalLight3D`: tuning — shadows reach this far (the default is 100 m; the map is 2 km)
- `scenes/world/world.tscn`, node `World/Atmosphere/WorldFog`: the fog (scenes/world/fog/, PLACEHOLDERS.md "Fog")
- `scenes/world/world.tscn`, node `World/Atmosphere/WorldBackdrop`: the land, mountains and sea around the map (art/world/README.md "Backdrop around the map", #620)
