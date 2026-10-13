# Deprecated world tools

One-time use, not maintained (Austin, 2026-10-13). They got the map, POIs, sizes, forests and water into the game once;
from now on those live in the Godot scenes (`art/world/export/world_landscape_<size>.tscn`) and are edited there. The
only live export is `tools/export_world.sh`. Godot ignores this folder (`.gdignore`); paths inside the scripts are the
old ones, so they may not run as they are. Don't run them on the current scenes: several re-place or regenerate things.

- `sync_world_sizes.sh`: the old one-step export + import + bake + size build. One-time use, not maintained (Austin, 2026-10-13).
- `build_world_sizes.gd`: made the 400 m and 6 km scenes from the 2 km ones (re-placed markers, POIs, towers, roads). One-time use, not maintained (Austin, 2026-10-13).
- `world_areas.gd`: grew forests and water (surfaces, blockers, bank walls) from the guide outlines into `world_areas_<size>.tscn`. One-time use, not maintained (Austin, 2026-10-13).
- `build_placeholder_roads.gd`: drew the stand-in roads into `world.tscn`. One-time use, not maintained (Austin, 2026-10-13).
- `bake_forest_fog.gd`: fog masks from the forest guide outlines (`areas_2km.json`). One-time use, not maintained (Austin, 2026-10-13).
- `make_400m_blend.py`: made `art/world/source/world_landscape_400m.blend` from the 2 km map. One-time use, not maintained (Austin, 2026-10-13).
- `gen_water_blockers.gd` + `apply_water_blockers.py`: wrote the height-limited water blockers and the Ford heights into the landscape scenes and removed the bank walls. One-time use, not maintained (Austin, 2026-10-13).
- `blender/build_all.sh`, `build_landscape.py`, `build_pois.py`, `build_props.py`, `poi_shapes.py`, `world_data.py`: generated the first placeholder blockout. One-time use, not maintained (Austin, 2026-10-13).
- `blender/texture_austin_map.py`: added the placeholder textures to Austin's map. One-time use, not maintained (Austin, 2026-10-13).
- `blender/carve_water.py`: sank the ground under the water guides. One-time use, not maintained (Austin, 2026-10-13).
- `blender/build_backdrop.py`: generated `world_backdrop.blend`. One-time use, not maintained (Austin, 2026-10-13).
- `blender/export_pois.py`: exported the POI blockouts and props to glb. One-time use, not maintained (Austin, 2026-10-13).
- `blender/corruption_world_sync.py`: Blender add-on that exported every size on save. One-time use, not maintained (Austin, 2026-10-13).
