# Art Asset Plan — Blender Build Order

A phased, priority-ordered list of models to build in Blender, sequenced so each phase
teaches the skills the next phase needs. Companion to the Tier 5 "Art pass" item in
[build-phases.md](build-phases.md). Pipeline rules (layers, export, import) live in
[3d-asset-pipeline.md](3d-asset-pipeline.md) — follow them for every asset here.

---

## Where we are today (2026-06-05 audit)

### Characters
| What | Current visual | Verdict |
|---|---|---|
| Avatar (Paladin) | `large-male` rig + fantasy skin material, sword.fbx + shield.fbx | Functional. Replace late (Phase 5) — it's the most-watched model but also the hardest. |
| **All 17 minion types** | The **same `Zombie.tscn`** (large-male variant), tint differences only | **Biggest visual gap in the game.** Cultist, eye horror, hellhound, imp, pit fiend, shoggoth, skeleton, sprite, treant, wisp, wraith, ghoul, advisor, courier, scout, info courier — all zombies. |
| Holy Knight | Own variant scene (skin + sword + shield) | OK for now. |
| Guardian Boss / Corrupted Seraph | `large_male.tscn` base with inline skin | Placeholder. Set-piece characters — Phase 5. |
| Overlord (Lich) | Raw `Lich-applying.glb` in a Node3D wrapper; `Lich-arms.glb`, `FPS arms.blend` raw | Partial custom work exists. Needs regularization + polish, not a from-scratch build. |

### Interactables (one model serves all 4 towers — shared `tower.tscn`)
| What | Current visual |
|---|---|
| War Table | **3 BoxMeshes** |
| War table pawns (piece / tower piece / ghost / target / reset / paper) | Cylinders + spheres |
| Palantir | `crystal-ball.glb` (decent) on greybox |
| Summoning Circle | Repurposed `table.glb` |
| Upgrade Altar | Greybox stone + glowing purple pillar |
| Mirror | Mirror3D addon quad, no frame |
| Avatar Claim | Primitive |
| Gem (the win objective!) | **A sphere** |
| Gem Site | Primitives |
| Ritual Site | **No mesh at all** (Editor TODO says "needs a visual mesh") |

### World
- Environment is covered by third-party kits (medieval town kit, mod-castle kit, rocks/roads/terrain via Terrain3D). Towers are kitbashed from mod-castle — fine.
- **Corruption — the title mechanic — has zero world visuals.** Territory state exists only in the debug overlay.

---

## Style target

Match the third-party kits already in the project: **low-poly, flat-shaded or
gradient-palette textured**. This is also the friendliest style for a Blender beginner —
no sculpting, no UV painting, no PBR texturing. One small palette texture (or vertex
colors / flat materials) per asset.

**Blender setup before anything else (Phase 0):**
1. Scene units: metric, 1 unit = 1 m (Godot's scale).
2. Import `assets/characters/large-male/large-male.glb` into Blender once and keep it as a
   **scale/proportion reference** in every working file.
3. Export preset: glTF 2.0 (`.glb`), +Y up (default), apply modifiers.
4. Land each export per [3d-asset-pipeline.md](3d-asset-pipeline.md): raw `.glb` →
   inherited `.tscn` → variant → actor. Keep `.blend` sources next to the glb.
5. Trial run: model a trivial prop (candle, crate), export, import, instance in the tower,
   verify scale and orientation in-editor. Do this before investing in a real asset.

---

## Phase 1 — The War Table set 🎯 *(start here)*

**Why first:** 3 of 4 players are Overlords; the table is the centerpiece they stare at
for minutes at a time. The pieces are tiny, simple, hard-surface objects — ideal first
Blender projects — and every one replaces a literal cylinder. Highest visibility per hour
of effort in the whole project.

| Asset | Replaces | Notes | Effort |
|---|---|---|---|
| Friendly minion pawn | `war_table_piece.tscn` cylinder+sphere | Chess-pawn silhouette. Keep material tintable — selection glow / faction color is applied in-engine. | ★ |
| Believed-enemy pawn | same scene, enemy bucket | Different silhouette (e.g., spiked), so belief reads at a glance. | ★ |
| Courier pawn | midpoint-pawn-on-arrow visual | Tiny rider/runner abstraction. | ★ |
| Tower piece | `war_table_tower_piece.tscn` | Rook-like. One per faction is overkill — one shape, engine tint. | ★ |
| Target / ghost markers | `war_table_map_target.tscn`, `war_table_ghost.tscn` | Flag, X-marker, translucent ghost variant of pawn. | ★ |
| Reset lever / bell | `war_table_reset.tscn` | Small desk prop. | ★ |
| The table itself | 3 BoxMeshes in `war_table.tscn` | Heavy wooden legs, carved frame around the map surface. Keep the map surface a flat quad at the same height/size — `WarTableMap` does piece math against `table_surface_size`. | ★★ |
| Paper/scroll stack | `war_table_paper.tscn` | Rolled maps, quill. Pure flavor. | ★ |

**Skills learned:** box modeling, bevels, mirror modifier, multi-object export, the full
Blender→Godot loop.

---

## Phase 2 — Tower interior interactables

**Why second:** the rest of the Overlord's home. Each is a single static prop with an
emissive accent — one step up in shape complexity. The Ritual Site is on this list
because it needs a mesh *anyway* before it can even be placed (Editor TODO).

| Asset | Replaces | Notes | Effort |
|---|---|---|---|
| **The Gem** | a sphere | The win objective of the entire game. Faceted crystal on an ornate base, strong emissive. Deserves to be iconic. | ★★ |
| Ritual Site | nothing (blocked TODO) | Circle of rune stones, 3 placements in world. Unblocks Tier 4 testing. | ★★ |
| Gem Site marker | primitives | Smaller shrine variant of the gem pedestal. | ★ |
| Summoning circle | `table.glb` | Floor disc with engraved runes + 2–3 braziers. Engine handles glow/particles. | ★★ |
| Palantir pedestal | greybox under crystal-ball.glb | Clawed/twisted pedestal; keep using the existing crystal ball on top. | ★★ |
| Upgrade altar | greybox + pillar | Dark stone altar, skull motifs, slot for the glowing pillar (keep the engine glow). | ★★ |
| Mirror frame | bare Mirror3D quad | Ornate gothic frame sized around the existing quad. | ★★ |
| Avatar claim shrine | primitive | Pedestal + empty armor stand or kneeling-altar. | ★★ |

**Skills learned:** curves/lattices for ornament, emissive materials, organic-ish stone
shapes.

---

## Phase 3 — Corruption set dressing

**Why third:** corruption is the *name of the game* and currently invisible outside F3.
These are small organic statics, scattered by the territory system (engine work to spawn
them per corrupted cell can come later — the assets unblock it). Huge thematic payoff,
still no rigging.

| Asset | Notes | Effort |
|---|---|---|
| Corruption crystal cluster ×3 sizes | The workhorse — scatter density maps to corruption level. | ★★ |
| Tendril / root clump ×2 | Twisted ground-breakers. | ★★ |
| Pustule / egg sac | Gross accent piece. | ★ |
| Corrupted ground patch | Low flat mesh with torn edges, to layer over Terrain3D. | ★ |
| Dead/corrupted tree | Counterpart to the kit's living trees. | ★★ |
| 4 faction territory totems | Undeath: bone pile/grave. Demonic: spiked iron brand. Eldritch: warped obelisk. Nature/Fey: dark mushroom ring. Marks *whose* corruption a region is. | ★★ each |

**Skills learned:** organic modeling with subdivision + proportional editing, first
sculpt-lite work.

---

## Phase 4 — Minion readability (the cheap way)

The 17-zombies problem, attacked in two waves ordered by difficulty, **not** by building
17 rigged characters.

### 4a — Floaters: no rig needed ★★
These five hover/drift, so they need **no skeleton and no walk cycle** — engine-side
bobbing/particles do the animation. They immediately differentiate Nature/Fey and
Eldritch rosters:

| Minion | Faction | Shape |
|---|---|---|
| Wisp | Nature/Fey | Glowing orb + trailing wicker husk (engine particles do the rest) |
| Sprite | Nature/Fey | Tiny winged sliver of light |
| Eye Horror | Eldritch | Floating eye, tentacle fringe |
| Wraith | neutral/Undeath-flavored | Hooded shroud tapering to nothing |
| Shoggoth | Eldritch | Lumpy blob with eyes — engine squash-and-stretch sells it |

### 4b — Humanoids skinned to the existing rig ★★★ *(the big skill jump: weight painting)*
The project already owns a **complete animation library on the large-male skeleton**
(idle, walk, run, attack, death, stagger, interact…). Any mesh you skin to that skeleton
gets every animation for free. Model in A/T-pose at large-male proportions, parent to the
imported skeleton, weight paint, export.

Priority order within this wave:
1. **Skeleton** — Undeath's core unit AND the raise-dead spawn; most-seen minion in the game.
2. **Advisor** — robed vizier; follows the Overlord around the tower, on-screen constantly.
3. **Cultist** — robed humanoid (reuses Advisor learnings), Eldritch bread-and-butter.
4. **Ghoul** — hunched zombie-eater, Undeath.
5. **Imp** (scale down) and **Pit Fiend** (scale up) — Demonic pair; same session.
6. **Courier / Scout / Info Courier** — one shared "runner with satchel" mesh, engine tint per role.
7. Holy Knight armor upgrade (existing variant works; polish only).

**After 4a + 4b, every faction roster reads at a glance** except Hellhound and Treant,
which need their own rigs (deferred to Phase 5).

---

## Phase 5 — Hero characters

The faces of the game. Save them for when your character skills are proven — these are
the models everyone screenshots.

| Asset | Notes | Effort |
|---|---|---|
| **Paladin (Avatar)** | Most-watched model: 3rd-person camera, Palantir feeds, boss fights. Skin to large-male rig to inherit the full combat animation set. | ★★★ |
| **Lich (Overlord)** | You already have `Lich-applying.glb` / `Lich-arms.glb` / `FPS arms.blend` — this is a *cleanup + polish* job: rebuild to pipeline layout (`assets/characters/lich/`), fix the Node3D-wrapper anti-pattern, polish first-person arms (always on screen) and the mirror-view body. | ★★ |
| **Capitol Guardian** | Set-piece boss. Large-male rig at heroic scale, radiant armor. | ★★★ |
| **Corrupted Seraph** | Inherited variant of the Guardian (matches the scene inheritance!): same rig + wings + corruption growths. | ★★★ |
| Hellhound | Quadruped — first custom rig + custom anims. Hardest character in the project. | ★★★★ |
| Treant | Custom rig, but slow/stompy so animation is forgiving. | ★★★★ |
| Sword/shield upgrade tiers | Easy palate cleansers between characters. | ★ |

---

## Phase 6 — Environment identity (mostly kitbash, model only hero pieces)

- **Capitol set piece** — the arena around the Gem and boss fight. Kitbash from mod-castle; model 1–2 hero pieces (broken god-statue, gem dais).
- **Per-faction tower exterior dressings** — silhouette accents so towers read as owned.
- Second map (Tier 5 line item) — defer entirely.

---

## Working agreements

- **One asset, fully landed, beats three half-done.** "Landed" = exported, inherited
  `.tscn` made, instanced in the live scene, verified in-editor.
- Don't animate in Blender until Phase 5 — the animation libraries already exist; reuse
  the rig instead.
- Keep every material tintable (no baked-in faction colors) — faction tint, selection
  glow, and corruption shading are applied in-engine.
- Keep `.blend` sources committed next to the `.glb` exports.
