# World blockout (PLACEHOLDER)

A placeholder world so the real one can be sculpted by hand. Nothing here is Austin's design: the layout is read by
eye off his sketch (`source/reference/world-sketch-original.jpg`), the shapes are stand-ins, and the place-name
spellings are unconfirmed (ticket #606). The pipeline is in the doc "Corruption open world: Blender to Godot plan".

## Austin's map (2026-10-09)

`source/world_landscape.blend` is now **Austin's own hand-made map** (`corruption-map.blend`), not the generated blockout.
It is one ground mesh, `Plane` (52 x 52 vertices, scaled to 1000 x 1000 m, heights -21 m to +51 m, 1 unit = 1 m), saved in
Edit Mode. Nothing else: no `poi_<name>` markers, `tower_slot_1..4`, roads, rivers, forests or scale figure (they were not
added to his file). I only added placeholder texturing (`tools/blender/texture_austin_map.py`): material
`ground_placeholder` (grass; sand below z = -1.5 m; water texture below z = -6 m, the low basins; snow above 36 m; rock where
the world-space slope exceeds 0.30), all Closest-filtered `textures/*.png` loaded by relative path, tinted by a new `Col` vertex
colour; a new `WorldUV` UV layer (world-space planar, one 32 px tile = 8 m) drives it. His `UVMap`, vertex positions, name and
transform are unchanged (vertex checksum identical before/after). His untouched file is `source/reference/corruption-map-original.blend`;
the earlier generated blockout is `source/world_landscape_generated_placeholder.blend` (the POI files still match that one).
The texturing is a Blender shader mix; for Godot it will need baking or a matching shader (#605).

## Files

| File | What |
|---|---|
| `source/world_landscape.blend` | The whole landscape in ONE file, 1 unit = 1 m. Faceted ground, flat sea, rivers/lakes (flat water strips in carved channels), roads, forests (linked tree instances), `poi_<name>` markers, `tower_slot_1..4`, the sketch under the ground, a 1.8 m figure. `source/.gdignore` keeps Godot from importing it; tiles come from the export script (#605). |
| `props.blend` | Shared prop library: `tree_cone`, `tree_lollipop`, `rock`, `ruin_wall`, `fence`, `grave_marker` (collections, marked as assets). Landscape and POI files **link** these (File > Link / Asset Browser), never copy. |
| `pois/<name>.blend` | One per sketch place: `avequalla`, `nofishun`, `northwood`, `old_gate`, `teshfield`, `veilton`, `valley_cross`, `hopes_gates`, `alebend`, `entwar`, `elder_woods`, `lastford`, `hells_mouth`, `unnamed_harbour`. |
| `pois/_template.blend`, `holy_site.blend`, `graveyard.blend` | Starters: duplicate `_template` for a new kind; the other two are generic holy-site and graveyard starters. |
| `textures/*.png` | 32 px tiling pixel textures (grass, rock, sand, dirt, snow, ash, water, stone, roof, plaster, wood, bark, leaves, lava, canvas). Nearest filtering; vertex colour (`Col`) tints and shades them. |

## The world

- **Size is a placeholder: 2000 m x 1500 m** (the sketch's aspect), until the scale test (#603) decides. Everything is
  parented under the `world_root` empty (scale it to rescale the lot), or change `WORLD_W` / `WORLD_H` in
  `tools/blender/world_data.py` and regenerate (that loses hand edits).
- +X east, +Y north (Godot: -Z north after export), map centre at the origin. Sea sits in the east at z = 0; the NE and
  north-west are mountain ranges (up to ~135 m); the volcano at Hell's Mouth has a lava pool; the SW ash plain stands
  for the arc marks. Rivers: one from the NW through Teshfield and Hope's Gates to the sea at Entwar (plus the Northwood
  streams and the Avequal'la lake), one across the south through Lastford to the south-east coast.
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
