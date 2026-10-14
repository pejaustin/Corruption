# Milestone tests

Run these before a version or a big milestone, or when asked. They are slow: each loads the real world as an offline host.
Everyday tests are the GUT fast tier (`tools/gut.sh`, see CLAUDE.md "Tests").

| Test | What it plays through |
|---|---|
| `test_world_layout.tscn` | Austin's map: four towers in their slots, every place on the ground and the navmesh, reachable from every tower |
| `test_orders.tscn` | the order loop: map floor, advisor, courier, corrupting the chapel, the courier's report, a missing group, scouting |
| `test_endgame.tscn` | the gauntlet in the real world, the good faction's late army, the draw |
| `test_palantir.tscn` | reaching the Palantir with the overlord's interaction ray and real key presses |

Run one with `godot --headless --path . res://tests/integration/<name>.tscn` (exit code = failed checks; a fresh clone
needs one `godot --headless --import` first). `WORLD_SIZE=400m|6km` picks the world size.

Also at milestones: `tools/net/smoke.sh` (four networked players) and the input playtests in `tools/playtest/`.
