# Pikmin pathfinding and route graphs

Source: C++ decomp at `workshop/pikmin-decomp/` (paths below are relative to it). Pikmin 2 is the main subject (`pikmin2/`); Pikmin 1 (`pikmin/`) is noted where it differs. Everything here is paraphrase; none of it is copied code. Line numbers are from the decomp checkout.

The short version: Pikmin does not path over terrain. Free-roaming units steer straight at a target and let wall collision slide them around obstacles. A hand-authored sparse waypoint graph is used only for one job: hauling a heavy object (treasure, corpse) to its goal. The graph is tiny, its edge state is flipped by gates/bridges, and the search is spread across frames.

---

## 1. How it works

### 1.1 The route graph (data)

- **Node = `WayPoint`**: position, a radius (corridor half-width at that node), a flag byte, up to 8 outgoing links (`mFromLinks`), up to 8 auto-generated reverse links (`mToLinks`), plus a cave-only door index and a list of rooms that contain it. `pikmin2/include/Game/routeMgr.h:50-110`.
- **Flags** (`routeMgr.h:50-62`, setters at `routeMgr.cpp:193-260`): `Closed` (gate/obstacle currently blocks), `Water` (node sits in a water box), `Bridge` (node belongs to an unfinished or finished bridge), `Unvisited` (cave room not yet entered), plus two versus-mode team flags. The "open" state is stored as the *absence* of `Closed`.
- **Links are directed as authored.** The file stores only the "from" list per node. At load, `makeInvertLinks` adds the reverse direction only if a terrain probe says the edge is walkable both ways: ten samples along the segment, and if the ground height jumps by more than 25 units between consecutive samples the reverse link is not made (`routeMgr.cpp:393-455`, called from `GameRouteMgr::read` at `routeMgr.cpp:742`). Result: ledges and drops become one-way edges automatically. Carriers use only the authored direction; two-way searching is an opt-in flag (used by two enemy types, `pathfinder.h:30`).
- **Water is recomputed, not authored.** `refreshWater` clears every node's water flag then re-sets it by sampling the water box at the node (ground height for normal nodes, the node's own height for bridge nodes), radius 4 (`routeMgr.cpp:460-480`). Called at level load (`baseGameSection.cpp:2342`) and when the sea level changes (`gameSeaMgr.cpp:261`).
- **Storage.** Overworld: a binary/text stream loaded into one flat array, read by index (`routeMgr.cpp:742-760`). Caves: each map-piece file carries its own mini graph (`gameMapParts.cpp:353`), stitched at generation time (see 1.7). An editor variant of the manager (`EditorRouteMgr`, `routeMgr.cpp:802+`) allows adding/removing nodes; the game variant is read-only.
- **Hard caps.** 8 outgoing links per node, asserted (`routeMgr.cpp:525`). Node indices are signed 16-bit, so at most about 32k nodes.

### 1.2 How the world edits the graph

Gates, bridges and pressure plates do not touch the pathfinder. They grab the nearest node to their own position and toggle its `Closed` flag.

- Gate: finds the nearest node, closes it, moves the node onto the gate's position; opens it when the gate dies (`itemGate.cpp:115-155`, `:783`).
- Bridge: two nodes (start and end) are flagged `Bridge` and closed at creation; both open on completion, and close again if the bridge is destroyed (`itemBridge.cpp:371-393`, `:197`, `:297`, `:699`).
- Pressure/seesaw floor tiles use the same pattern (`itemDownFloor.cpp:139-147`).
- `getNearestWayPoint` is a plain linear scan over all nodes with an optional line-of-sight check against map and platform collision for candidates under 300 units (`routeMgr.cpp:486-530`). It is only called at setup, so the cost does not matter.

### 1.3 The search (A*, budgeted over frames)

Pikmin 2 (`pikmin2/src/plugProjectKandoU/pathfinder.cpp`):

- **Algorithm:** textbook A* on node indices. Cost to a neighbour = straight-line 3D distance between the two node positions; heuristic = straight-line distance to the goal (`pathfinder.cpp:492`). No per-link weights, no terrain cost, node radius ignored in the cost. Open list is a linked list scanned linearly for the minimum f on each pop (the source comments call it "a bad excuse for a priority queue", `pathfinder.cpp:275`). Fine at a few hundred nodes.
- **Budget:** a fixed pool of 100 search contexts, each with its own node array sized to the full graph (`pathfinder.cpp:31-40`, pool created at `baseGameSection.cpp:2335-2336`). Each frame, every busy context expands exactly **one** node (`pathfinder.cpp:54-72`, the call passes an iteration cap of 1). Latency in frames therefore equals the number of nodes expanded; a path over 40 nodes visited takes 40 frames. Callers poll a state code each frame (`pathfinder.h:14-19`): path ready / no path / busy / bad handle.
- **Handles:** `start` returns an integer handle from a wrapping counter; the caller polls with `check`, reads the result with `makepath`, and must `release` it. Over capacity is a hard panic (`pathfinder.cpp:103-112`). The result is a singly linked list of nodes from start to goal built by walking parent pointers.
- **Edge filtering lives inside the search loop** (`pathfinder.cpp:421-490`). A neighbour is skipped when any of these holds, each controlled by a request flag bit:
  - `RequireOpen` and the neighbour is `Closed`;
  - not `PathThroughWater` and the neighbour is `Water`;
  - not `AllowUnvisited` and the neighbour is `Unvisited` (cave rooms never entered);
  - `DisallowUnfinishedBridges` and moving from a water node onto a `Bridge` node;
  - the two versus-mode team flags.
  So blocked-ness is a per-request predicate over per-node flags, not a graph rebuild.
- **Water rule for carriers:** the carry action sets `PathThroughWater` only if every carrier on the object is a blue or equivalent water-immune type (`aiPrimitives.cpp:894-900` region via `isAllBlue`, set at `aiPrimitives.cpp:572-576`). The carrier mix is evaluated when the search starts; the flag set is a snapshot.
- **Fallback ladder when the search reports no path** (`aiPrimitives.cpp:704-740`): on failure the carry action restarts a search with a looser flag set: `RequireOpen` dropped (closed gates are now traversable on paper), `PathThroughWater` forced on, and from the second failure `AllowUnvisited` added. A counter saturates at 3. The agent then walks the path and waits at the gate (1.5).
- **Pikmin 1 differs fundamentally** (`pikmin/src/plugPikiKando/routeMgr.cpp`): not A*. It is a depth-first walk with backtracking: at each node it picks, among unvisited-in-this-path links, the one whose far end is nearest the goal (squared XZ distance), returns immediately if a link reaches the goal, else descends; dead end means step back. Result is a valid but not shortest path. It is async too: one global `updateASync` budget of 256 loop iterations per frame, split evenly across all queued clients (max 100) (`routeMgr.cpp` `updateASync`/`updateClient`). A sync version exists. The carry code in P1 uses the sync version at pickup with a three-try fallback: avoid water, then allow blocked links, then drop the avoid-water mode (`pikmin/src/plugPikiKando/aiTransport.cpp:575-650`). P1 also has an unfinished precomputed table of "first step toward each onion" per link, stripped in retail (`routeMgr.cpp` `initLinkInfos`), i.e. the idea of caching next-hop-to-goal per node was tried.

### 1.4 Entering and leaving the graph

- **Start node:** not "nearest node" but **nearest edge**. `getNearestEdge` scans every authored link and projects the object's position on the segment, measuring distance to the capsule (radius interpolated between the two ends) (`routeMgr.cpp:533-650`). Filters: skip closed edges when the object is on the far side of a closed node's plane; skip bridge nodes when the object is in water; in caves, skip edges that touch neither the object's current room; avoid links already tried. The start node chosen is the nearer end of the best edge that is not closed (`aiPrimitives.cpp:555-590`).
- **Goal node:** pre-baked per goal object (each home "onion" stores its nearest node when built, `onyonMgr.cpp:682`). Other callers use `getNearestWayPoint` on the goal position (`naviState.cpp:1555-1560`).
- **Snap-back to the graph** (P1): `getSafePosition` clamps a position to the nearest edge corridor and re-seats its height on the ground, used to recover objects that ended up off-mesh (`pikmin/src/plugPikiKando/routeMgr.cpp` `getSafePosition`).
- **Starting from a hole** (P2): if no edge qualifies with the "links already tried" list active, the query is repeated with that list cleared; if still nothing it panics (`aiPrimitives.cpp:580-595`).

### 1.5 Following a path (carry action)

All in `pikmin2/src/plugProjectKandoU/aiPrimitives.cpp`, `ActPathMove`. Who moves: the carried object, not the carriers. The leader carrier runs the action; each frame it computes a desired velocity and "pulls" the object. Other carriers are attached to slots on the object.

- **States:** Pathfinding, Move, MoveGoal (final approach), MoveGuru ("pacing", waiting at a closed node) (`aiPrimitives.cpp:630-660`).
- **While waiting for a path** the object is held still and its pull is zeroed each frame (`:670-700`).
- **Path as a corridor, not a polyline.** Each segment between node i and i+1 is a tapered capsule: radius is the interpolated node radius (`contextCheck`, `:1081-1170`). The object is "on path" if its footprint intersects that capsule or either end circle. This is the stuck/re-plan trigger: if the object is outside the corridor by more than a threshold, the action discards the current search, resets, and plans again from the current position (`crMove`, `:1305+`, re-plan branch around `:1345`).
- **Steering** (`crMove`, `:1305-1450`):
  - Project the object onto the current segment; derive `factor` in [0,1].
  - Compute the lateral offset from the segment axis, normalised by interpolated radius into a 0..1 "pull to centreline" weight. Offsets under 0.3 of the radius count as zero (dead zone), so the object may wander inside the corridor.
  - Desired direction = blend of the spline tangent and the direction back to the axis, weighted by that offset.
  - A Catmull-Rom spline through four control points (previous, current, next, next-next) supplies the tangent, so turns at nodes are smoothed (`sysMath.cpp:135`, `CRSplineTangent`; control refresh `crMakeRefs`, `:1294`). The spline is used for *direction only*; position is never set from it.
  - If the offset is very large (more than twice the radius and over 130 units) it returns without steering (lets physics catch up).
  - If the new direction points backward relative to the segment, it falls back to the plain segment direction.
- **Arrival:** advance to the next segment when the object is within a very small distance (6 units, squared-ish `qdist2`) of the next control point, or when the projection factor reaches 1. Reaching the last-but-one node switches to MoveGoal.
- **Final approach:** straight line at the goal position; carry ends when the horizontal distance is under 10 units (`execMoveGoal`, `:805-855`).
- **Speed:** interpolated between a min and max fraction of run speed by how much carry power exceeds the minimum needed, so more carriers means faster; carrying a captain or a special flagged object goes at full run speed (`getCarrySpeed`, `:771-800`).
- **Closed node ahead (gate not yet destroyed):** the action goes to Guru state: target a point 160 units short of the closed node along the segment, and orbit a 10-unit circle around it, at half speed, until the node's `Closed` flag clears (`execMoveGuru`, `:966-1030`). The path is not re-planned in the meantime; the plan already includes the closed node because of the fallback ladder.
- **Stuck detection:** `Pellet::mWallTimer` rises by 2 per frame while a carried object is in contact with a wall facing against its motion, and falls by 1 otherwise; capped at 100 (`pelletMgr.cpp:1370-1390`, `:1495-1505`). If the timer is over 99 *and* the object moved less than 1 unit since last frame, the action releases its search handle, re-seeds the "tried edges" list with the starting edge so the same start is not picked again, and re-runs the start-node query and a new search (`execMove`, `aiPrimitives.cpp:894-945`).
- **Failure to carry:** if the pull is refused (another puller with greater strength has the object, 1.6), the action drops the pickup and polls until it can pick up again (`exec`, `:630-660`).

Non-carry path users: the player character has a "walk the route to this spot" state that just steps node by node (arrival radius 15 units, speed fixed 150), no corridor logic (`naviState.cpp:1530-1620`); the "pellet return" state teleports-hops an object along path nodes with a 15-unit arrival (`pelletState.cpp:1000-1130`). Two enemy types (a bread-like and a black hole-like) run searches with two-way links to return home (`panModoki.cpp:1220-1340`, `blackMan.cpp:1354-1450`). Several others only read neighbour lists of one node to hop between adjacent nodes (`KumaChappy.cpp:284-350`).

### 1.6 Pull arbitration (carriers vs enemies)

`PelletCarry` (`pelletCarry.cpp`, 99 lines) is a tiny state: who is pulling (idle / carry / another state), the pull velocity, a strength number, a grace timer. `pull(state, velocity, strength)` succeeds if idle, same puller, or strictly stronger; a takeover sets a 0.5 s timer during which the object does not move (velocity zeroed) (`:20-45`, `:68-80`). Strength passed by carriers is their count. Nothing else is needed for tug-of-war with enemies that drag the same object.

### 1.7 Cave generation and the graph

Cave floors are random assemblies of pre-authored map pieces ("units"), each with its own mini route graph and a door node on each doorway.
- Door nodes are flagged and given a door index (`gameMapParts.cpp:1940-1948`).
- When a piece is placed, its nodes are copied to the floor-wide graph with the placement transform; the node height is snapped to terrain (`getMinY`), except door nodes whose height is forced to 0 (`:1985-2050`).
- **Stitching:** if the adjacent piece is already placed, the new piece does not make a new door node; it reuses the neighbour's door node (looked up by the neighbour's door index), and appends its own outgoing links to that shared node (`:1995-2012`, `:2053-2090`; link capacity of 8 asserted at `:3572`-ish).
- Each node also records which room(s) it belongs to (a shared door belongs to two). `setCloseAll` marks every node `Unvisited` at floor start; `openRoom(room)` clears it for every node in the room when the player enters (`routeMgr.cpp:652-680`, `fakePiki.cpp:654-660`). Searches without `AllowUnvisited` therefore only route through explored rooms.
- After all pieces are placed: `makeInvertLinks` runs once over the whole graph (`gameMapParts.cpp:992`).
- Cave placement of "glitchy seesaw" gimmick objects is also done by picking random graph nodes (`gameMapParts.cpp:1150-1190`): the graph doubles as a list of known-walkable spots.

### 1.8 Local movement and terrain (everything off-graph)

- Free movement is velocity-driven. Unit AI sets a target velocity toward a position (`EnemyFunc::walkToTarget`: turn toward the target at a capped rate then set speed along the facing, `enemyAction.cpp:459-480`). No avoidance, no planning.
- Terrain collision is a swept-sphere move against a triangle mesh (`mapMgrTraceMove.cpp:19-170`): step the sphere by velocity*dt, gather triangles from the spatial divider, test each, and on hit push the sphere out along the contact normal and cancel the velocity component into the surface (scaled by a restitution value). A triangle whose normal is steep enough is "floor" (above a floor threshold), nearly vertical is "wall" (below a wall threshold); both are reported so callers can react (e.g. the wall timer in 1.5).
- Sub-stepping: if per-frame travel would exceed the sphere radius, the step is halved, up to 8 sub-steps (`mapMgrTraceMove.cpp:23-50`). Tunnelling guard.
- Falling and recovery (P1): if y < -2000 an object dies, except treasure which is re-seated 30 units above ground at its XZ (`pikmin/src/plugPikiKando/creatureMove.cpp:111-135`).
- Ledges: when the ground triangle is lost, the previous triangle's neighbours are checked; if the neighbour exists and is within an angle threshold it keeps walking, otherwise a "jump/fall" callback fires (`creatureMove.cpp:285-310`).
- The graph radius is only used by the carry action's corridor test and steering; terrain collision never consults it.

### 1.9 Spatial partitioning (finding nearby creatures)

**Cell pyramid** (`pikmin2/src/plugProjectKandoU/cellPyramid.cpp`, `include/Game/cellPyramid.h`):
- A quadtree-like stack of 2D grids (x,z only). Layer 0 is the finest; each next layer is half the resolution. Base cell size is 108 world units for the main creature grid (`baseGameSection.cpp:2346-2350`), 128 for platforms, 170 for cave rooms. If the base grid would exceed 200 cells on a side the cell size is multiplied by 1.5 (`cellPyramid.cpp:1013`).
- **An object lives in exactly one layer**: the first layer whose cell width is at least its bounding diameter (log2 of diameter over base size, rounded up, clamped) (`calcExtent`, `:891-925`). It covers at most 4 cells at that layer (four "legs", each a link in the cell's list); more than that is a panic (`entry`, `:944-995`). Large bodies therefore sit in coarse layers and are found by everything overlapping them.
- **Cell link count bookkeeping:** each cell also keeps counts of piki/navi inside itself and its subtree so empty subtrees can be skipped.
- **Query** (`CellIterator`, `cellIterator.cpp`): for a query sphere, walk every layer from fine to coarse, in each layer iterate the cell rectangle covering the sphere, chain through each cell's object list, skip objects already seen this query (a per-pass integer stamp on the object, since one object may sit in 4 cells), optionally test a user condition, then do a final 2D circle-circle distance check on the XZ plane. The pass counter wraps at 2^26 (`cellIterator.cpp:46-80`, `:140-190`). Alternative query `mapSearch` visits the covering cells at the proper layer plus the parent chain upward and children downward, calling a delegate (`cellPyramid.cpp:28-130`).
- **Collision pairs** (`resolveCollision`): for each non-empty cell, test every object against others in the same cell and against objects in every *ancestor* cell (coarser layers). Each pair is thus visited once, with no children scan. A "magic number" flag stamps the previous partner to avoid duplicate calls. Default mode (`sOptResolveColl = 2`) walks only the non-empty cells via a linked list threaded through them (`:499-555`, `:1142-1235`).
- **Per-object neighbour buffer** (`CollisionBuffer`): a fixed array of the 8 nearest overlapping neighbours, sorted by edge-to-edge distance, with separate insert rules so pikmin-pikmin pairs and pikmin-other pairs are ordered differently (`cellPyramid.cpp:358-470`; capacity set at `pelletMgr.cpp:437`, `fakePiki.cpp:48`, `enemyBase.cpp:875`). Objects marked "not collision-updatable" (static things) skip their own pair loop and instead replay last frame's buffer (`resolveCollision_3`, `:1191-1235`). This is a cheap temporal-coherence trick: static objects pay once.
- **Sweep and prune** (`pikmin2/src/plugProjectKandoU/sweepPrune.cpp`, `include/SweepPrune.h`): every object has four sorted-list nodes (min/max on X and Z) kept ordered by insertion sort, which is near-linear because order changes little frame to frame. Resolve walks the X list; for each object, scan backwards until the object's own opening node is reached, test Z-interval overlap, report pairs through a callback. Present as mode 3 of the collision resolver but **not the default**; it appears to be an alternative that was kept and not used (`cellPyramid.cpp:499-515`, `sweepPrune.cpp`).
- **Pikmin 1 equivalents:**
  - `FastGrid`: a flat byte grid of per-cell occupancy counts for "is anything interesting near me" culling; an AI update is skipped when the 3x3 block around a creature's cell has zero count, or (larger radius variant) a (2n+1)-square block (`pikmin/src/plugPikiKando/fastGrid.cpp:70-165`). Cell shift 12 on a 16-bit coordinate range.
  - `SearchSystem`: per-creature fixed-size `SearchBuffer` of nearest neighbours within 300 units; manager pairs are searched in a hand-ordered list; a grid-distance cull skips pairs that are too many cells apart (`pikmin/src/plugPikiKando/searchSystem.cpp:114-220`, `fastGrid.cpp:140-175`).

### 1.10 Limits and tricks, collected

- 100 concurrent searches; each context holds a full-graph-sized node array (memory scales as contexts x nodes).
- One node expansion per context per frame (P2); 256 loop steps/frame shared across clients (P1).
- Search runs only for carry/return/some enemy-home moves. Idle roaming, chasing, following the leader and attacking use no pathfinder at all.
- Graph radius doubles as an "off-path means re-plan" tolerance.
- Re-planning triggers: left the corridor; wall-contact timer saturated plus no motion; pickup control lost then regained; search reported unreachable (loosened flags).
- One-way edges from terrain probe (drops).
- Closed-node waiting: orbit near the obstacle rather than failing the plan.
- Path result is a linked list of node ids; positions are read live from the graph each frame (so a gate that moves its node, as `itemGate.cpp:118` does, shifts the path).
- Per-level graph, not per-world: no hierarchical levels. Levels are on the order of hundreds of units across, with a few hundred nodes.

---

## 2. What Corruption could take

These are options, not recommendations. Corruption is an RTS on 400 m / 2 km / 6 km worlds with a NavigationRegion3D/NavigationAgent3D setup already in place (`scenes/actors/minion/minion_actor.gd` stuck ladder at lines 134-460; `scripts/minion_manager.gd` navmesh snapping at 585-620). Pikmin's world is small and its graph tiny; scale is the main caveat for every option.

### Option A: Keep NavigationServer3D, borrow the stuck/re-plan rules
- **What:** Pikmin's three re-plan triggers (left the corridor, wall-contact counter with no motion, control regained) are independent of the graph type. The existing `_check_stuck` ladder (re-path, snap to navmesh, drop target) already matches the third and fourth.
- **Godot mapping:** a "corridor deviation" test would compare the unit position to `NavigationAgent3D.get_next_path_position()` / the path polyline from `get_current_navigation_path()`, re-requesting a path when the distance exceeds a width. A "wall timer" would count frames where `move_and_slide()` reports a wall collision whose normal opposes the travel direction.
- **Trade-offs:** cheap, no new data. Does not help blocked-terrain semantics (rivers) because the navmesh has no concept of "closed for this unit class".

### Option B: Per-unit-class navigation layers on one navmesh (water as a layer)
- **What:** Pikmin gates water passability on the carrier mix at search start (`PathThroughWater` flag from `isAllBlue`).
- **Godot mapping:** `NavigationRegion3D.navigation_layers` bitmask (water-crossing region, ford region, bridge region) and `NavigationAgent3D.navigation_layers` set per unit/group. Toggling a region's `enabled` (or its layer bit) at runtime makes a ford, bridge or blocked gate appear and disappear.
- **Trade-offs:** native, fast. Navmesh edits cost a re-bake or region enable/disable plus a sync frame; for 6 km worlds regions must be chunked. Filtering is per-region, so a per-edge flag like Pikmin's is not available; it is per polygon set.

### Option C: Hand-authored sparse "road" graph (AStar3D / AStarGrid) for long hauls only
- **What:** The Pikmin split: dumb steering locally, sparse graph for hauls. Nodes with radius and flags; links directed; flags `closed`, `water`, `unvisited` plus per-request predicates.
- **Godot mapping:** `AStar3D` with `set_point_disabled` for closed gates, `_compute_cost` / `_estimate_cost` overridden for flag predicates (GDScript override for per-request filtering; or several `AStar3D` instances, one per unit class, with disabled flags set per class). Add directed links via `connect_points(a, b, bidirectional=false)` for drops. Node radius would be stored in a parallel array and used as a corridor width.
- **Trade-offs:** deterministic, tiny, easily serialisable (and easy for the design to say "a courier carries a path": a path is a list of node ids plus any added edges). Needs authoring (or generation) and a start-node projection (nearest *edge*, not nearest node, as Pikmin does). The graph and the navmesh can disagree; Pikmin avoids the problem by never using both for the same movement.

### Option D: Budgeted, polled path requests
- **What:** Pikmin hands out a handle, advances every search by a fixed amount per frame, and callers poll.
- **Godot mapping:** `NavigationServer3D.query_path` has an async variant in 4.x (`NavigationPathQueryParameters3D` plus `NavigationServer3D.query_path` with a callback in 4.3+, check availability in 4.6), or hand-rolled: a manager node holding a queue of requests and running up to N A* node expansions or K full queries per physics frame (round-robin, priority by class). With `AStar3D`, a custom stepped search is not available out of the box; one would write A* in GDScript with the open list as a binary heap (Pikmin's linear scan would not scale beyond a few hundred open nodes).
- **Trade-offs:** flat frame cost with thousands of units; adds latency (Pikmin: one node/frame, i.e. visible hesitation on long paths) and needs a "waiting for path" idle state (Pikmin holds the object still). Memory: Pikmin keeps a node array per context (100 x graph size) which is only acceptable for small graphs; a Godot version would use a shared dictionary per search.

### Option E: Fallback ladder for unreachable goals
- **What:** failure becomes "retry with looser rules" (ignore closed gates, allow water, allow unexplored), then walk to the obstacle and wait there (Pikmin's pacing orbit).
- **Godot mapping:** a request carries a flag set; the manager retries with fewer constraints when the result is empty. The unit enters a "waiting at blocker" state when the next path node is flagged closed, re-checking the flag each tick rather than re-pathing.
- **Trade-offs:** gives visible, readable behaviour at rivers (troops pile at the bank instead of silently idling); the stuck-at-river example in the GDD (section 4) could be read directly off this state. Needs a closed-flag source per blocker (see F).

### Option F: Obstacles as flags on nearest graph nodes
- **What:** gates and bridges own one or two nodes; the object's lifecycle toggles `Closed`, with the node moved onto the object (`itemGate.cpp:115-155`).
- **Godot mapping:** with Option C: `AStar3D.set_point_disabled(id, true)`. With Option B: `NavigationLink3D.enabled` or a region enable. Fords and "new paths" that a courier carries could be additional node/edge sets merged into the graph or enabled on arrival.
- **Trade-offs:** decouples gameplay objects from search code; requires the object to find a node at spawn (Pikmin does a nearest-node query once).

### Option G: Corridor-based following with spline direction
- **What:** a path is a tapered tube; steer = blend (spline tangent, vector back to the axis), with a dead zone and a weight rising with lateral offset; spline is for *direction only*, never position.
- **Godot mapping:** compute in the unit's steering step using `Curve3D`/`Curve3D.sample_baked` or a hand-written Catmull-Rom tangent; feed the result to `NavigationAgent3D.set_velocity` (so RVO avoidance still applies) or to the unit's own `velocity`.
- **Trade-offs:** smoother corners and tolerance of knocked-off paths for large objects (a carried body); more code than following `get_next_path_position()`. For infantry the navmesh agent's own funnel path already cuts corners.

### Option H: Cheap spatial queries in GDScript (cell pyramid or flat hash)
- **What:** Pikmin: sphere queries on a multi-layer grid where an object lives in the one layer matching its size; plus a per-unit buffer of 8 nearest neighbours; static things skip their updates.
- **Godot mapping:** a `Dictionary` keyed by `Vector2i` cell for a single-size grid is enough for equal-sized troops. A second coarse grid for large things (towers, bodies being carried) is the pyramid idea. For large worlds, one grid per chunk. Alternatives built into Godot: `Area3D` with a sphere shape and `get_overlapping_bodies` (one physics shape per unit is expensive at scale), `PhysicsServer3D.space_get_direct_state().intersect_shape` for ad-hoc queries, or `NavigationAgent3D` avoidance's own neighbour list (not exposed).
- **Trade-offs:** hash grid is trivial and fast but needs its own update; no engine support for "multi-resolution". Pikmin's `pass stamp` idea (an integer on the object to dedupe multi-cell hits) carries over directly.

### Option I: "Pull" arbitration for contested carry objects
- **What:** a small struct with an owner, strength and a grace timer; a stronger puller takes over after a short freeze.
- **Godot mapping:** a `Node` or `RefCounted` on the carried thing; each frame leaders call `pull(owner, velocity, strength)` and the carried body applies the result.
- **Trade-offs:** fits "bodies carried back to a tower" and captured humans where rival groups might grab the same object; adds one small piece of state, no pathfinding.

### Option J: Level-of-detail by distance to any player-visible event
- **What:** Pikmin 1's `FastGrid.aiCulling` skips AI updates for creatures with no interesting neighbours in the 3x3 cell block.
- **Godot mapping:** run the full AI/steering tick only for units whose cell or neighbours are occupied or observed; others use a coarse tick (e.g. every 0.5 s) or move along their precomputed path in aggregate.
- **Trade-offs:** large savings in a low-information RTS with long marches; behaviour off screen would be approximate. What counts as "interesting" is a design question (see section 3).

---

## 3. Open questions

1. Whether a *carried* path (the GDD courier example) is a data object (list of graph node ids and added edges) or a navmesh change decides between Option C/F (graph edits are small data) and Option B (navmesh edits need chunked bake or link toggles). Only the designer can say how literal "carrying a path" is.
2. What counts as "observed" for cheap off-screen simulation (Option J); the project's low-information premise could make most units unobserved most of the time.
3. Pikmin's levels are small; I did not find any Pikmin mechanism for very large worlds (no hierarchical routing, no streaming). Anything for 2 km and 6 km worlds would be new design.
4. Not read: how `fakePiki` / `Piki` follow the leader and chase targets in detail (assumed direct steering plus collision, consistent with `walkToTarget`); and the `crMove` constants in Pikmin 1 (`pikmin/src/plugPikiKando/aiTransport.cpp:900-1300`), which looked the same as P2 at a skim.
