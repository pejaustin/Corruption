# World blockout (PLACEHOLDER)

A placeholder world so the real one can be sculpted by hand. Nothing here is Austin's design: the layout is read by
eye off his sketch (`source/reference/world-sketch-original.jpg`), the shapes are stand-ins, and the old place-name
spellings were unconfirmed (ticket #606; Austin's spellings on his markers are now authoritative). The pipeline is in the doc "Corruption open world: Blender to Godot plan".

## Austin's map (2026-10-09, second version)

`source/world_landscape.blend` is **Austin's own hand-made map** (`corruption-map.blend`), not the generated blockout.
**+Y is north** (he rotated it); 1 unit = 1 m. His objects, spelled as he typed them:

- **Ground:** `geo`, the terrain mesh (52 x 52 grid, 2000 x 2000 m, object scale (1000, 1000, 3)). The 400 m map is its own file, see "Sizes".
- **Forest and water guides:** `elder wood`, `northwood`, `Pale River`, `The Still Lake` are rough outlines of where
  forests and water go (their X/Y only), not meshes to use (Austin, 2026-10-10). The glb skips them. Their footprints were
  exported once to `export/areas_<size>.json` and grew the stand-in trees and water now in the landscape scenes.
- **POI markers: every empty in the landscape file is a POI marker, except tower markers (names ending in `Tower`).** Its snake_case name (lowercase, spaces to `_`,
  apostrophes dropped: `Avequel'la` -> `avequella`, `Naf Ishun` -> `naf_ishun`, `Hell's Mouth` -> `hells_mouth`) is its POI
  file `pois/<snake>.blend`. Markers: `Ale Bend`, `Avequel'la`, `Entbridge`, `far harbor`, `Forest Ruins`, `Hell's Mouth`,
  `Hopes Gate`, `Lastford`, `Mountain Pass`, `Naf Ishun`, `Teshfield`, `Valley Cross`, `Veilton`.

I only added placeholder texturing (`tools/deprecated/blender/texture_austin_map.py`, one-time): `geo` gets `ground_placeholder` (grass; sand below
26.8% of the height range; water texture below 20.6%; snow above 79%; rock where the world-space slope exceeds 0.30, all as
fractions of the range so they follow his vertical scale); the water meshes get `water_placeholder` (water texture); the forest
meshes get `forest_placeholder` (`leaf_pine` darkened, PLACEHOLDER: no forest texture exists). All textures are 32 px
`textures/*.png`, Closest-filtered, loaded by relative path, on a new world-space `WorldUV` layer (one tile = 8 m) with a new
`Col` vertex colour. His `UVMap`s, vertices, names, transforms and object list are unchanged (vertex + matrix checksums of every
mesh are identical before/after; the script prints `GEOMETRY_UNCHANGED True`). His untouched file is
`source/reference/corruption-map-original.blend`; the earlier generated blockout is
`source/world_landscape_generated_placeholder.blend` (its generators are in `tools/deprecated/blender/`).
The ground's texture choice is now vertex-painted (see "Painting the ground"); the old height / slope rule is gone.
Previews: `render_previews.py` (top-down ortho, +Y up, plus low views; it adds temporary markers and labels, not saved).

## Sizes: 400 m and 2 km, separate works (Austin, 2026-10-13)

**2 km is the working size.** 400 m (quick tests) and 2 km are now **worked on separately**: each has its own Blender map
and its own Godot landscape scene, and nothing copies one into the other. **6 km is legacy**: not maintained, not for the
MVP; its files (`world_landscape-6k.blend`, `export/world_landscape_6km.*`, `world_areas_6km.tscn`, `areas_6km.json`,
`scenes/world/world_6km.tscn`) stay as they are and are not regenerated. The host still picks the size in the lobby
(`MatchConfig.WorldSize`, `GameState.world_size`).

| Size | Blender map (ground) | Landscape scene (everything else) | Game world |
|---|---|---|---|
| 2 km | `source/world_landscape.blend` | `export/world_landscape_2km.tscn` | `scenes/world/world.tscn` |
| 400 m | `source/world_landscape_400m.blend` (made once from the 2 km map at 1/5, 2026-10-13) | `export/world_landscape_400m.tscn` | `scenes/world/world_400m.tscn` |

## From Blender to Godot: `tools/export_world.sh`

The one live export script (Austin, 2026-10-13: "take the world geo and the outer boundary blender files, build glbs, and
reimport them"):

```
tools/export_world.sh [2km|400m|all]      # default 2km
```

It exports `geo` from the size's map to `export/world_landscape_<size>.glb` (`tools/blender/export_landscape.py`) and the
backdrop (`source/world_backdrop.blend` -> `export/world_backdrop_2km.glb`, `tools/blender/export_backdrop.py`; at 400 m only if a
`world_backdrop_400m.blend` exists, there is none), then re-imports: if a Godot editor is open on the project it says "focus
the Godot editor to reimport", otherwise it runs a headless import with the `.blend` importer switched off in
`project.godot` (a headless import stops at the first `.blend` without a Blender path) and puts `project.godot` back, even on
failure. Env: `GODOT`, `BLENDER` (defaults: `godot` / `/Applications/...` on a Mac, the Windows Blender under WSL).

Nothing else is exported or placed by script any more: markers, towers, POIs, crossings, bridges, forests and water are
nodes in the landscape scene, edited in the Godot editor. The old pipeline (`sync_world_sizes.sh`, the size build, the
areas build, the POI export, the carve) is in `tools/deprecated/` (one-time use, not maintained).

### After which edit

| You changed | Then |
|---|---|
| The ground in Blender (`geo`, its paint) | save, `tools/export_world.sh [size]`, then rebake that size's navmesh and map picture (below) |
| The backdrop (`world_backdrop.blend`) | save, `tools/export_world.sh` (nothing to bake: it is off the navmesh) |
| Anything in a landscape scene: a marker, tower, POI, bridge, ford, a water blocker | save the scene, then rebake that size's navmesh |
| A POI's Godot scene (`pois/<snake>.tscn`) or a shared scene (tower, map floor) | nothing (the landscapes instance them); rebake if its collision changed |

Standalone tools, run by hand after ground or water changes (they are not part of `export_world.sh`):

- **Navmesh:** bake it in the editor: open `world.tscn` (or `world_400m.tscn`), select `World/Nav`, **Bake NavigationMesh** (Austin, 2026-10-13; the bake settings are on that region's NavigationMesh resource); it writes `scenes/world/world_navmesh.res` / `world_400m_navmesh.res`.
- **Map-floor picture:** `SIZE=2km|400m godot --headless --path . -s res://tools/bake_map_illustration.gd`, then re-import.

## The landscape scene (`export/world_landscape_<size>.tscn`)

```
WorldLandscape (Node3D)
├── Ground            the geo-only glb (Ground/geo; its trimesh collision is set in the .glb.import)
├── <marker> ...      one Node3D per place, named as Austin spelled it (Naf Ishun, Avequel'la, Forest Tower,
│   ├── POI           Volcano Tower, Hell's Mouth, far harbor, ...): what hangs under it (the place's
│   └── Tower         pois/<snake>.tscn, a tower with its slot_index)
├── Forests/<wood>/chunk_*   stand-in trees (MultiMeshInstance3D, no collision)
├── Waters/<body>     water_body.tscn per water: Surface (the look) and Blockers (navmesh blockers)
└── BridgeWoodRound*  Austin's bridges (2 km)
```

Until 2026-10-13 the markers were empties in the glb and the size build placed things under them; the conversion kept
every node, transform, property and unique id (checked node by node, including through `world.tscn` / `world_400m.tscn`).
400 m keeps the old 400 m export's sea look as an `Ocean` node.

### POI scenes

Every marker that does not end in `Tower` has a place scene `pois/<snake>.tscn` (snake_case of the marker's name),
an inherited scene of `pois/export/<snake>.glb` (from `pois/<snake>.blend`; the exporter is now
`tools/deprecated/blender/export_pois.py`, not maintained). Add Godot-only things (lights, sounds, sites) in the `.tscn`. The
scene's materials come from `pois/poi_post_import.gd` (`mat_<texture>` -> `materials/poi/mat_<texture>.tres`, shader
`shaders/poi_uv.gdshader`). The POI collision is parsed by the navmesh bake, so units walk around buildings. No
`.gdignore` in `pois/`: it would hide the scenes and glbs too.

### Water: blockers and bridges (Austin, 2026-10-13)

**No bank walls** (Austin, 2026-10-13: "get rid of walls"): bodies can walk into water; only the navmesh keeps units out.

- **Blockers** are plain `NavigationObstacle3D` nodes under `Waters/<body>/Blockers` (carve, no avoidance). A blocker only
  carves within its vertical band (from its `position.y` up `height`): Recast marks the spans whose top lies in it. Each band
  runs from under the lowest ground inside it to just over the water (`WATER_CLEARANCE_M`, 0.3 m, PLACEHOLDER). So ground
  above the water inside an outline stays walkable (e.g. the hill under the Forest Tower once restored), and so do bridge
  decks above the band.
  - The sea (`Glittering Ocean`): one band up to the sea level + 0.3 m. 400 m: under `Waters/Glittering Ocean/Blockers`
    (the look is the `Ocean` node).
  - Pale River: the outline cut into 25 m squares (5 m at 400 m), each with its own band up to the highest river surface
    in it + 0.3 m, so the bands follow the river down its length.
  - The Still Lake: no blocker (it can be waded, #615).
  They were written once (2026-10-13, `tools/deprecated/gen_water_blockers.gd`, from the guide outlines in
  `export/areas_<size>.json` and the surface meshes); they are ordinary nodes now: move or reshape them in the editor and
  rebake. Nothing regenerates them.
- **Bridges** (`scenes/world/env/bridge_woodRound.tscn`, collision: ramps up to the deck and rails along both sides, layer 1) are parsed by the bake
  like the ground: place one across the water, rebake, and its deck joins the banks.
- **No fords** (Austin, 2026-10-13): rivers are crossed by bridges only. The flat ford slabs left vertical edges that
  bodies could not climb and baked as islands, so groups halted before them.

Forests: `Forests/<wood>/chunk_*` are stand-in trees grown once from the guide outlines (200 m chunks, hidden beyond
1500 m at 2 km / 500 m at 400 m, no collision, no shadows); they are plain nodes now. The water surfaces are as they were
generated (river 1 m under its nearest bank, lake 0.3 m under its rim, sea at the ocean plane; all PLACEHOLDER).

## Godot export details

- **`tools/blender/export_landscape.py`** (run by `export_world.sh`) exports only `geo`. It never saves the .blend and prints
  `GEOMETRY_AND_NAMES_UNCHANGED True` (checksum of every vertex, matrix and name before vs after). The authored size is read
  from `geo`'s scale (2 km: (1000, 1000, 3); 400 m: (200, 200, 0.6)); a file authored at its preset exports as it is.
  +Y north becomes -Z north.
- **Materials:** Blender's node trees do not survive glTF, so `world_landscape_<size>.glb.import` maps the names to
  `materials/ground_placeholder.tres` (shader `shaders/world_ground.gdshader`: world-space 8 m tiles, nearest, the `Splat`
  layer picks the texture, times the `Col` tint), `water_placeholder.tres` and `forest_placeholder.tres`.
- **Ground layers in Godot:** the glTF importer only maps `COLOR_0` to `COLOR`, so on `geo` the export script (in memory,
  never saved) writes `Splat` as `COLOR_0` and `Col` as UV (r, g) + UV2 (b), dropping `geo`'s `UVMap` / `WorldUV` from the
  export (the shader tiles by world position). The shader reads `COLOR.rgb` and `vec3(UV, UV2.x)`.
- **Collision:** only `geo`, set in the `.glb.import` (`PATH:geo`: generate physics, static body, trimesh).
- **Navmesh bake:** the editor's built-in bake on `World/Nav` (Austin, 2026-10-13). Its settings live on the region's
  NavigationMesh resource (cells, agent 3.1 m tall and 0.7 m wide, climb, the collision mask that leaves out the
  towers' boundary layer). How closely the mesh follows the ground is Recast's detail mesh: `detail_sample_distance` and
  `detail_sample_max_error` (default 1 m off the ground). The old custom tool post-processed for this instead and is
  deprecated (`tools/deprecated/bake_open_world_navmesh.gd`).
- **Screenshots:** needs a rendering Godot (no headless). `WORLD=res://scenes/world/open_world/open_world_2km.tscn SHOT_FAR=6000
  SHOTS="overview:0,2900,0:0,0,0:50" godot --path . res://tools/shots/shot.tscn`.

## Backdrop around the map (ticket #620)

**Settled (Austin, 2026-10-12):** the world must not visibly stop from the high lookouts, and the edge is real geometry,
not just fog; GameCube / Wii / PS2-era vistas are the reference. Beyond the map: **north a mountain wall, east ocean (the
Glittering Ocean carries on), south a mountain wall, west rolling hills.** I generate a stand-in; Austin sculpts it.

- `source/world_backdrop.blend` (2 km scale, +Y north): `backdrop`, a low-poly ring of land from the map's square edge
  (tucked 12 m under `geo` and 1.5 m below it, so editing `geo` never opens a crack) to a circle 5 km from the centre,
  rows further apart outward; `backdrop sea`, water at the Glittering Ocean's level (0.25 m below, no z-fighting where
  they overlap). Splat/Col corner colours as on `geo`. **Austin's to sculpt**; regenerating needs `--force` and loses it:
  `tools/deprecated/blender/build_backdrop.py` (one-time use, not maintained).
- `tools/blender/export_backdrop.py` -> `export/world_backdrop_<size>.glb` (size presets as `geo`; never saves the
  .blend); `tools/export_world.sh` runs it. The .glb.import maps `ground_placeholder` / `water_placeholder` (both
  curved) and makes no collision; `export/world_backdrop_2km.tscn` turns off its shadows. Not walkable, not on the navmesh.
- **After sculpting:** save the .blend, then `tools/export_world.sh` (nothing to bake, the backdrop is off the navmesh).
- The balcony lookout's far plane is 6 km so it reaches the ring's far edge.
- The curved-world bend (`WorldCurve`) hides the ring past the horizon like a planet; with the bend off the ring ends at the
  far plane, so the far rows should stay high (mountains) or be fogged.
- PLACEHOLDER: every shape (heights, distances, noise, corner blends), the ring's radius and the rock/sand rule.
- The map's north-east sea floor (east edge north of the Glittering Ocean, y > 503 m in Blender) is above the sea level
  with no water over it, so it shows as two dry slabs against the backdrop sea.

## Curved world (PLACEHOLDER tuning)

Ground, water, forests and the castle kit (so towers) bend down with horizontal distance from the camera
(`shaders/curved_world.gdshaderinc`: `world.y -= d^2 / (2R)`, `R = horizon^2 / (2 x eye height)`). Change it live in
the `WorldCurve` node under `World/Atmosphere` in each world scene (`scripts/world_curve.gd`, @tool, so the editor shows it):
`horizon_m` (0 = off) is the distance at which ground at eye level has dropped by `eye_height_m`. `world.tscn` (2 km) is 1500 / 40;
`world_400m.tscn` has its own node (300 / 8; 6 km legacy 4500 / 200); edit each size's node. **Project Settings > Globals > Shader Globals** (`curve_horizon_m` 1500,
`curve_eye_height_m` 40) is only the fallback for scenes without the node. In the editor the camera is the editor camera, so it follows you.
Collision, navmesh and gameplay are NOT bent (look only).

- **Bent:** `world_ground.gdshader`; `water_placeholder.tres` / `forest_placeholder.tres` (now ShaderMaterials on
  `shaders/world_triplanar.gdshader`, same look); every `.fbx` in `assets/world/env/mod-castle/` (materials extracted to
  `curved_materials/`, shaders `shaders/curved_kit*.gdshader`). Repeat or extend with `tools/curve_kit_materials.gd`.
- **Not bent yet (they float above the bend when far):** anything with its own StandardMaterial3D: desk, ledger, balcony,
  summoning slot, mirror, corruption site, map floor and map lines, crystal ball and table glb, units. To add one, give it a
  ShaderMaterial that does `#include "res://shaders/curved_world.gdshaderinc"` and calls `curve_bend(VERTEX, MODEL_MATRIX,
  CAMERA_POSITION_WORLD)` in `vertex()`.
- Shots: the 5th field of a `SHOTS` entry sets `curve_horizon_m` for that shot (over the world's own) (`...:fov:1500`).

## Painting the ground

`geo` has two colour layers (Object Data > Color Attributes; click a layer to make it active):

- **`Splat`** picks the texture. **PLACEHOLDER mapping** (Austin has not chosen the textures): black = grass, **red = rock,
  green = dirt, blue = sand**. A channel counts as painted at 50% or more (hard edge, no blend); grass is what no channel
  claims; if channels overlap, sand beats dirt beats rock. Paint pure red / green / blue; erase with black.
- **`Col`** is the tint / shading multiplied over the texture (white = untouched).

To paint: select `geo`, Vertex Paint mode (Ctrl+Tab), click `Splat` in Color Attributes (it is the active layer; `Col` is
only the display layer), pick a colour, brush. Material Preview shows the textures live. Then save and run
`export_landscape.py` (above). `tools/blender/add_splat.py` created `Splat` seeded from the old look (rock on the old steep
faces, sand in the old shore band, grass elsewhere; the old sea-water and snow bands have no channel, so they became sand
and grass) and rebuilt the `ground_placeholder` material; re-running keeps your paint, `--reseed` overwrites it.

## Files

| File | What |
|---|---|
| `source/world_landscape.blend` | The whole landscape in ONE file, 1 unit = 1 m. Faceted ground, flat sea, rivers/lakes (flat water strips in carved channels), roads, forests (linked tree instances), `poi_<name>` markers, `tower_slot_1..4`, the sketch under the ground, a 1.8 m figure. `source/.gdignore` keeps Godot from importing it; tiles come from the export script (#605). |
| `props.blend` | Shared prop library: `tree_cone`, `tree_lollipop`, `rock`, `ruin_wall`, `fence`, `grave_marker` (collections, marked as assets). Landscape and POI files **link** these (File > Link / Asset Browser), never copy. |
| `pois/<snake_name>.blend` | One per POI marker in Austin's map: `ale_bend`, `avequella`, `entbridge`, `far_harbor`, `forest_ruins`, `hells_mouth`, `hopes_gate`, `lastford`, `mountain_pass`, `naf_ishun`, `teshfield`, `valley_cross`, `veilton`. `forest_ruins` and `mountain_pass` are fresh copies of `_template`; the rest were renamed from the earlier placeholder spellings (`avequalla`, `nofishun`, `hopes_gates`, `entwar`, `unnamed_harbour`, `alebend`). |
| `pois/northwood`, `old_gate`, `elder_woods` | **No marker yet** in Austin's map (kept from the sketch; `northwood` and `elder wood` exist as forest meshes only). |
| `pois/_template.blend`, `holy_site.blend`, `graveyard.blend` | Starters (also no marker): duplicate `_template` for a new kind; the other two are generic holy-site and graveyard starters. |
| `textures/*.png` | 32 px tiling pixel textures (grass, rock, sand, dirt, snow, ash, water, stone, roof, plaster, wood, bark, leaves, lava, canvas). Nearest filtering; vertex colour (`Col`) tints and shades them. |

## The world

- **Size is a placeholder: 2000 m x 1500 m** (the sketch's aspect), until the scale test (#603) decides. Everything is
  parented under the `world_root` empty (scale it to rescale the lot), or change `WORLD_W` / `WORLD_H` in
  `tools/deprecated/blender/world_data.py` and regenerate (that loses hand edits; deprecated).
- +X east, +Y north (Godot: -Z north after export), map centre at the origin. Sea sits in the east at z = 0; the NE and
  north-west are mountain ranges (up to ~135 m); the volcano at Hell's Mouth has a lava pool; the SW ash plain stands
  for the arc marks. Rivers: one from the NW through Teshfield and Hope's Gates to the sea at Entwar (plus the Northwood
  streams and the Avequel'la lake), one across the south through Lastford to the south-east coast.
- Roads are dirt strips draped over the ground; they cross rivers as flat decks.
- Object names follow the Godot import suffixes: `-noimp` (reference plane, scale figure, sun, PLACEHOLDER text),
  `-col` / `-colonly` / `-navmesh` / `-occ` are for the tile export and your hand edits (nothing is marked `-col` on
  the landscape: ground collision is cut per tile later).
- Every file has a `PLACEHOLDER-noimp` text object and a `PLACEHOLDER` custom property.

## The four towers

`tower_slot_1..4` are UNPLACED: arrows in a column just outside the west edge of the map (x = -1080), custom property
`placed = False`. Once the scale is set, drag each onto the map (and delete the label text). I did not place them.

## POIs

`poi_<name>` empties in `world_landscape.blend` mark where each place is on the ground (with a small stand-in shape
as a child). The matching `pois/<name>.blend` is where you build the place itself: origin = the POI's ground centre,
collections `Visual`, `Collision (-col)`, `Markers` (empties Godot owns: `site`, `spawn`) and `Reference (-noimp)`
(1.8 m figure, preview sun). Props are linked from `props.blend`. The `poi_` marker's `poi_file` property names its file.
Sketch icons with no name (the barns, windmill, beehive hut and the building north of Hope's Gates) are not marked.

## Regenerate (deprecated)

The first placeholder blockout's generators (`build_all.sh`, `build_props.py`, `build_pois.py`, `build_landscape.py`, ...)
are in `tools/deprecated/blender/` (one-time use, not maintained; they overwrite the .blend files). `tools/blender/render_previews.py`
still makes top-down and low-angle PNGs.

## Not here yet

Tile export and `_far` copies (#605), the scale test (#603), final names (#606), and any real art.

## Tower locations (Austin, 2026-10-09)

The four towers: **Volcano Tower** and **Forest Tower** are their own empties in `world_landscape.blend` (the `Hell's Mouth`
empty marks the volcano POI, not the tower). The **Avequel'la** tower stands at the centre of the ruined city, so it uses
the `Avequel'la` POI marker (later its POI file, or one linked from it). **Naf Ishun** uses its POI marker. Empties whose
names end in `Tower` are tower markers, not POIs (no `pois/` file). In Godot, `world_landscape_<size>.tscn` instances
`scenes/world/env/tower.tscn` as a child of each of these four marker nodes.

## Game world on the 2 km map (PLACEHOLDER layout, 2026-10-10)

`scenes/world/world.tscn` holds `world_landscape_2km.tscn` under `World/Nav`; the Terrain3D ground and the runtime navmesh
bake are gone. The navmesh is `scenes/world/world_navmesh.res`, baked in the editor on `World/Nav` (re-bake after any ground, tower,
bridge, ford or water change). Towers: units summoned in a tower jump from its balcony (a `NavigationLink3D`, `JumpPoint`) to the ground; each tower stands at a
different height above its ground, so `world_landscape_2km.tscn` overrides the link's landing per tower, and `project.godot`
widens the navigation edge margin (2 m) and link radius (2.5 m). `test_world_layout` checks a unit can walk out of every tower.
Agents and path queries search 32768 polygons (the
engine's 4096 gave up on long routes) and count a waypoint as reached within 2.5 m.

**Towers:** one tower per tower site, instanced under his markers in `world_landscape_2km.tscn`. Each has `slot_index`, which
pairs it with the `MinionRallyPoint` at the same position under `World/Markers`, the `MapPoint` whose `tower_slot` matches, and
the player who joined in that order. Which slot is which site, and which way each tower faces (toward the map centre unless
the ground is steep), are placeholders.

| Old point (`point_id`) | Now at | On his marker? |
|---|---|---|
| TowerEast / South / West / North | slot 0 Naf Ishun, 1 Forest Tower, 2 Volcano Tower, 3 Avequel'la (at each tower's courier spawn) | yes |
| City, HolySite, Places/City | Hopes Gate | yes |
| SettlementSE, SettlementNW | Entbridge, Teshfield | yes, 16 m and 12 m off (out of the POI's buildings) |
| Chapel (SiteChapel), AvatarSite (SiteAvatar), BossSite (SiteBoss, RelicBossSite) | Forest Ruins (6 m east), Ale Bend, Valley Cross (22 m north) | yes |
| Ford, Crossing | Mountain Pass (20 m east of his marker, at the foot of the pass), Lastford | yes |
| RoadEast / South / West / North | between each tower and its nearest place, by eye | no |
| MineSE, MineNW | ~55 m from Entbridge and Teshfield | no |
| Avatar, HolyKnights | beside Hopes Gate | no |

Unused markers: Veilton, Hell's Mouth, far harbor, Valley Cross's neighbours. The war table's floor shows the whole map.
