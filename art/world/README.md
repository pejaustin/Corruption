# World blockout (PLACEHOLDER)

A placeholder world so the real one can be sculpted by hand. Nothing here is Austin's design: the layout is read by
eye off his sketch (`source/reference/world-sketch-original.jpg`), the shapes are stand-ins, and the old place-name
spellings were unconfirmed (ticket #606; Austin's spellings on his markers are now authoritative). The pipeline is in the doc "Corruption open world: Blender to Godot plan".

## Austin's map (2026-10-09, second version)

`source/world_landscape.blend` is **Austin's own hand-made map** (`corruption-map.blend`), not the generated blockout.
**+Y is north** (he rotated it); 1 unit = 1 m. His objects, spelled as he typed them:

- **Ground:** `geo`, the terrain mesh (52 x 52 grid, 2000 x 2000 m, z scale 3).
- **Forest areas:** `elder wood`, `northwood` (any mesh with `wood` in its name is a forest).
- **Water:** `Pale River` (river), `The Still Lake` (lake) (any mesh with `river` or `lake` in its name is water).
- **POI markers: every empty in the landscape file is a POI marker, except tower markers (names ending in `Tower`).** Its snake_case name (lowercase, spaces to `_`,
  apostrophes dropped: `Avequel'la` -> `avequella`, `Naf Ishun` -> `naf_ishun`, `Hell's Mouth` -> `hells_mouth`) is its POI
  file `pois/<snake>.blend`. Markers: `Ale Bend`, `Avequel'la`, `Entbridge`, `far harbor`, `Forest Ruins`, `Hell's Mouth`,
  `Hopes Gate`, `Lastford`, `Mountain Pass`, `Naf Ishun`, `Teshfield`, `Valley Cross`, `Veilton`.

I only added placeholder texturing (`tools/blender/texture_austin_map.py`): `geo` gets `ground_placeholder` (grass; sand below
26.8% of the height range; water texture below 20.6%; snow above 79%; rock where the world-space slope exceeds 0.30, all as
fractions of the range so they follow his vertical scale); the water meshes get `water_placeholder` (water texture); the forest
meshes get `forest_placeholder` (`leaf_pine` darkened, PLACEHOLDER: no forest texture exists). All textures are 32 px
`textures/*.png`, Closest-filtered, loaded by relative path, on a new world-space `WorldUV` layer (one tile = 8 m) with a new
`Col` vertex colour. His `UVMap`s, vertices, names, transforms and object list are unchanged (vertex + matrix checksums of every
mesh are identical before/after; the script prints `GEOMETRY_UNCHANGED True`). His untouched file is
`source/reference/corruption-map-original.blend`; the earlier generated blockout is
`source/world_landscape_generated_placeholder.blend` (the generators `build_*.py` / `world_data.py` still use its old names).
The ground's texture choice is now vertex-painted (see "Painting the ground"); the old height / slope rule is gone.
Previews: `render_previews.py` (top-down ortho, +Y up, plus low views; it adds temporary markers and labels, not saved).

## Godot export (`tools/blender/export_landscape.py`)

`blender.exe -b source/world_landscape.blend --python tools/blender/export_landscape.py -- <repo_root>` writes
`export/world_landscape.glb` (imported by Godot; `source/` is `.gdignore`d). It never saves the .blend and prints
`GEOMETRY_AND_NAMES_UNCHANGED True` (checksum of every vertex, matrix and name before vs after). +Y north becomes -Z north.
The glb holds every mesh and every empty (POI markers keep Austin's spellings as node names), vertex colour `Col`, and
materials by name.

- **Materials:** Blender's node trees do not survive glTF, so `world_landscape.glb.import` maps the three names to
  `materials/ground_placeholder.tres` (shader `shaders/world_ground.gdshader`: world-space 8 m tiles, nearest, the `Splat`
  layer picks the texture, times the `Col` tint), `water_placeholder.tres` and `forest_placeholder.tres`
  (StandardMaterial3D, world triplanar, nearest).
- **Ground layers in Godot:** the glTF importer only maps `COLOR_0` to `COLOR`, so on `geo` the export script (in memory,
  never saved) writes `Splat` as `COLOR_0` and `Col` as UV (r, g) + UV2 (b), dropping `geo`'s `UVMap` / `WorldUV` from the
  export (the shader tiles by world position). The shader reads `COLOR.rgb` and `vec3(UV, UV2.x)`. Optional 2nd arg to
  the script = a scratch `.glb` path.
- **Collision:** only `geo`, set in the `.glb.import` (`PATH:geo`: generate physics, static body, trimesh), not by renaming.
  Forests and water are flat patches and have none.
- **Scene:** `scenes/world/open_world/open_world.tscn` (a `NavigationRegion3D` around the glb, sun, sky, fog; all
  PLACEHOLDER). The navmesh `open_world_navmesh.res` is baked from `geo`'s collision by
  `godot --headless --path . -s res://tools/bake_open_world_navmesh.gd` (agent height as in `world.tscn`; cell size 1 m and
  max climb 1 m are PLACEHOLDER tuning. Climb must be at least cell size x tan(max slope): with 2 m cells and the old
  0.5 m climb, any slope over ~14 degrees split the mesh into 110 islands and cut off Avequel'la. Now one walkable mesh;
  tower floors bake as their own islands). Re-bake after any geometry change.
- **Re-import headless:** with a Blender path unset, `godot --headless --import` stops at the `.blend` files; temporarily set
  `import/blender/enabled=false` under `[filesystem]` in `project.godot` for the import, then revert it.
- **Screenshots:** needs a rendering Godot (no headless). `WORLD=res://scenes/world/open_world/open_world.tscn SHOT_FAR=6000
  SHOTS="overview:0,2900,0:0,0,0:50" godot --path . res://tools/shots/shot.tscn`.

## Curved world (PLACEHOLDER tuning)

Ground, water, forests and the castle kit (so towers) bend down with horizontal distance from the camera
(`shaders/curved_world.gdshaderinc`: `world.y -= d^2 / (2R)`, `R = horizon^2 / (2 x eye height)`). Change it live in
**Project Settings > Globals > Shader Globals**: `curve_horizon_m` (default 1500; 0 = off) is the distance at which ground at
eye level has dropped by `curve_eye_height_m` (default 40). In the editor the camera is the editor camera, so it follows you.
Collision, navmesh and gameplay are NOT bent (look only).

- **Bent:** `world_ground.gdshader`; `water_placeholder.tres` / `forest_placeholder.tres` (now ShaderMaterials on
  `shaders/world_triplanar.gdshader`, same look); every `.fbx` in `assets/world/env/mod-castle/` (materials extracted to
  `curved_materials/`, shaders `shaders/curved_kit*.gdshader`). Repeat or extend with `tools/curve_kit_materials.gd`.
- **Not bent yet (they float above the bend when far):** anything with its own StandardMaterial3D: desk, ledger, balcony,
  summoning slot, mirror, corruption site, map floor and map lines, crystal ball and table glb, units. To add one, give it a
  ShaderMaterial that does `#include "res://shaders/curved_world.gdshaderinc"` and calls `curve_bend(VERTEX, MODEL_MATRIX,
  CAMERA_POSITION_WORLD)` in `vertex()`.
- Shots: the 5th field of a `SHOTS` entry sets `curve_horizon_m` for that shot (`...:fov:1500`).

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
  `tools/blender/world_data.py` and regenerate (that loses hand edits).
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

## Regenerate

`tools/blender/build_all.sh` (Blender 4.5; set `BLENDER=` if it is not at the Windows default) rebuilds props, POIs and
the landscape; **this overwrites the .blend files, so only run it before hand edits**, or into a copy. The
parts: `build_props.py`, `build_pois.py` (+ `poi_shapes.py`), `build_landscape.py` (+ `world_data.py`, which holds the
sketch coordinates, rivers, roads, mountains and forests). `render_previews.py` makes the top-down and low-angle PNGs.

## Not here yet

Tile export and `_far` copies (#605), the scale test (#603), final names (#606), and any real art.

## Tower locations (Austin, 2026-10-09)

The four towers: **Volcano Tower** and **Forest Tower** are their own empties in `world_landscape.blend` (the `Hell's Mouth`
empty marks the volcano POI, not the tower). The **Avequel'la** tower stands at the centre of the ruined city, so it uses
the `Avequel'la` POI marker (later its POI file, or one linked from it). **Naf Ishun** uses its POI marker. Empties whose
names end in `Tower` are tower markers, not POIs (no `pois/` file). In Godot, `open_world.tscn` instances
`scenes/world/env/tower.tscn` as a child of each of these four marker nodes.
