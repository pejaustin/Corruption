# 3D Asset Pipeline

How imported `.glb` / `.fbx` files become usable game nodes in this project, and how to keep customizations from being wiped on re-import.

---

## Why this exists

Godot treats every imported `.glb`/`.fbx` as a read-only `PackedScene` — editing it directly in the editor or saving over it doesn't work. Customizations (materials, bone attachments, scale tweaks) made by instancing the raw import in another scene will often survive, but they're fragile:

- Bone indexes shift if the skeleton changes in the DCC source.
- Animation tracks get re-generated on re-import, wiping any inline `AnimationPlayer` edits.
- Material overrides set inline on an instance get re-pathed if mesh nodes are renamed.

The fix is to **never reference the raw import directly in gameplay scenes**. Every imported asset gets a sibling `.tscn` that inherits from the import, and all customization lives on the inherited scene.

---

## Directory layout

```
assets/<category>/<base_name>/
├── <base_name>.glb              # Raw import — DCC source of truth
├── <base_name>.glb.import       # Godot import settings (committed)
├── <base_name>.tscn             # Inherited scene — PROJECT source of truth
├── <base_name>.res              # External AnimationLibrary (if animated, baked-in variant)
└── animations/                  # Optional: per-clip glbs + extracted .res Animation resources
    ├── <clip>.glb
    ├── <clip>.glb.import
    └── <clip>.res
```

For shared base models that multiple variants skin:

```
assets/characters/<base>/
├── <base>.glb / .tscn / .res    # as above
└── variants/                    # Or sibling directories like enemies/
    └── <variant>.tscn           # Inherits from <base>.tscn, adds material override / skin
```

Examples already in the project following this pattern:
- `assets/characters/large-male/large-male.glb` + `large_male.tscn` + `large-male.res`
- `assets/characters/enemies/ZombieModel.tscn` (inherits `large_male.tscn`, adds material)

---

## The three layers

```
imported .glb  →  base .tscn  →  variant .tscn  →  actor .tscn
(read-only)      (shared rig,   (skin / material  (gameplay — body,
                  animations)    per-character)    state machine, AI)
```

Each layer adds exactly one concern. Skipping a layer (e.g. actor directly instances the raw `.glb`) is what causes re-import pain.

### Layer 1 — Raw import
The `.glb` / `.fbx` itself. Never referenced directly by gameplay scenes.

### Layer 2 — Base model `.tscn` (inherited from import)
Created via **Scene → New Inherited Scene** in the editor with the `.glb` selected. Owns:
- The `AnimationPlayer` and its `AnimationLibrary` references (bake-in animations or reference external libraries).
- The `Skeleton3D` bone-rest adjustments if the DCC export is consistently wrong.
- Any `BoneAttachment3D` that is **intrinsic to the skeleton** and will be reused by every variant (e.g. a "hand" attachment on the lich).
- Autoplay of the idle/default pose so the model looks alive in the editor.

Owns nothing actor-specific — no hitboxes, hurtboxes, combat scripts, or character-unique skins.

### Layer 3 — Variant `.tscn` (inherited from base model)
Created via **New Inherited Scene** on the base `.tscn`. Owns:
- `surface_material_override/0` for the character-specific skin (texture + albedo tint).
- Per-variant bone rest tweaks if the skin deforms oddly (rare).
- Variant-specific `BoneAttachment3D` **only if that attachment is part of the character's identity** (e.g. a permanent horn, a fixed weapon). Temporary equipment belongs on the actor.

Owns no gameplay — no physics body, no state machine.

### Layer 4 — Actor `.tscn`
The gameplay entity. Inherits from `actor.tscn` / `minion_actor.tscn` / `player_actor.tscn` and instances the variant (or base) model scene under its `Model` node. Owns:
- `CharacterBody3D` collision for navigation/physics.
- `Hurtbox` and `AttackHitbox` (see `hurtboxes.md`, `attack-hitboxes.md`).
- `BoneAttachment3D`s for gameplay equipment the actor wields (swords, shields, effect anchors).
- State machine, AI, network sync, HUD.

---

## Animations — two supported patterns

Pick one per base model. Don't mix within a single base.

### Pattern A — Baked animations + external `AnimationLibrary`
Used when the DCC file exports all animations in a single `.glb`. Godot's import dock extracts them; save the library externally so it can be re-referenced.

1. Select the `.glb` in FileSystem, open the import dock.
2. Under **Animation → Save to File**, export the AnimationLibrary to `<base>.res` next to the glb.
3. In the inherited scene (`<base>.tscn`), the `AnimationPlayer` references `<base>.res` via its `libraries/<name>` slot.
4. Code calls animations as `<library_name>/<clip_name>` — e.g. `large-male/Attack`.

Example: `large-male.glb` → `large-male.res` → referenced by `large_male.tscn` → `autoplay = &"large-male/Idle"`.

### Pattern B — Per-clip glbs + hand-authored `AnimationLibrary`
Used when animations come as separate files from a mocap library or asset store.

1. Each clip `.glb` is imported; extract its single animation to `<clip>.res` via the import dock.
2. Create a `.tres` `AnimationLibrary` resource that aggregates the `.res` files under meaningful keys.
3. Base model `.tscn` references the `.tres` library from its `AnimationPlayer`.
4. Code calls animations as `<library_name>/<clip_name>` — e.g. `male_animation_lib/idle`.

Example: `assets/characters/animations/male_animation_lib.tres` aggregates `idle.res`, `walk.res`, `jump.res`, etc.

### Which to use

- **Pattern A** is preferred when one `.glb` holds everything — fewer files, automatic.
- **Pattern B** is preferred when clips come from different sources or need to be hot-swapped per character without re-exporting the whole DCC file.

Do not reference animations from a raw `.glb` via `$AnimationPlayer/<animation_name>` in code — always go through the library so the animation source can be swapped.

---

## Static meshes (props, accessories, buildings)

Simple static meshes don't always need all four layers. Decision rule:

| If the asset is… | Pattern |
|---|---|
| A one-off static mesh with no per-instance tweaks (sword, shield) | Instance the raw `.fbx`/`.glb` directly where used. Accept that material edits live on the instance. |
| A static mesh with a shared material or collision shape | Make an inherited `.tscn` that sets material + adds `StaticBody3D` + `CollisionShape3D`. Gameplay scenes instance the `.tscn`. |
| A static mesh the designer will frequently re-tint / re-skin | Always make an inherited `.tscn` with exposed `@export` material slots. |
| Terrain, large buildings, anything with collision | Always an inherited `.tscn` — collision lives on the inherited scene, not inline at every placement. |

Currently OK as raw instances: `assets/characters/accessories/sword.fbx`, `shield.fbx` (instanced directly by actor scenes that hold them).

---

## Bone attachments — where they belong

| Attachment | Lives on |
|---|---|
| Skeleton-intrinsic (any variant could use it — "hand", "head") | Base model `.tscn` |
| Character-identity (fixed horn, permanent mount point) | Variant `.tscn` |
| Gameplay equipment (sword, hitbox, effect anchor, weapon the actor could theoretically swap) | Actor `.tscn` |

`BoneAttachment3D` resolves `bone_idx` at load by looking up `bone_name`. Keep `bone_name` set (not just `bone_idx`) so re-imports that renumber bones still find the right target.

---

## Creating a new animated character — checklist

1. Drop `<new_char>.glb` into `assets/characters/<new_char>/`.
2. Open the `.glb` in FileSystem → import dock. Check scale, animation import settings, and **Save to File** the AnimationLibrary to `<new_char>.res` next to it (Pattern A). Reimport.
3. Right-click `<new_char>.glb` → **New Inherited Scene**. Save as `<new_char>.tscn` next to the glb.
4. In the inherited scene, confirm the `AnimationPlayer` shows the external library in its `libraries/` slot. Set `autoplay` to the idle clip.
5. If multiple variants need different skins, create `<variant>.tscn` as **New Inherited Scene** of `<new_char>.tscn` and set `surface_material_override/0` on the relevant `MeshInstance3D`.
6. Actor scene instances the variant (or base) under its `Model` node. Add gameplay bone attachments here, not in the model scene.

## Creating a new static prop — checklist

1. Drop `<prop>.glb` / `.fbx` into `assets/props/<category>/`.
2. If the prop needs collision, per-instance exports, or a shared material: **New Inherited Scene** → `<prop>.tscn`. Add `StaticBody3D` + `CollisionShape3D` as needed.
3. If it's just a visual and never customized: skip the inherited scene and instance the raw import directly.

---

## Anti-patterns — what to avoid

- **Instancing raw `.glb`/`.fbx` in a gameplay scene and editing it there.** Changes survive but are brittle to re-imports.
- **Re-declaring an `AnimationPlayer` inside an inherited scene** that already got one from the glb. The old player gets shadowed, animation tracks mismatch. (`guardian_model.tscn` did this before regularization.)
- **Wrapping a glb in a plain `Node3D` container** instead of using New Inherited Scene (as `scenes/player/player_model.tscn` does). Works but diverges — no way to override the glb's `AnimationPlayer` or add intrinsic bone attachments in one place.
- **Inline material overrides on the actor scene** when every instance of that actor uses the same skin. Push the material down to a variant `.tscn`.
- **Bone attachments in the actor scene with hard-coded `bone_idx` and no `bone_name`.** Breaks on re-import.
- **Mixing animation patterns** within one base model (half baked library, half per-clip).

---

## Current status (2026-04-24 audit)

Survey of actors against this procedure:

| Actor | Compliance |
|---|---|
| `zombie_actor.tscn` + 11 placeholder minions (cultist, eye_horror, hellhound, imp, pit_fiend, shoggoth, skeleton, sprite, treant, wisp, wraith) | ✅ Using `ZombieModel.tscn` variant scene |
| `corrupted_seraph.tscn` | ✅ Inherited from `guardian_boss.tscn` |
| `avatar_actor.tscn` | ✅ Uses `assets/characters/avatar/avatar.tscn` variant (skin material + hand bone attachments). |
| `holy_knight.tscn` | ✅ Uses `assets/characters/holy-knight/holy_knight.tscn` variant (skin material). |
| `ghoul_actor.tscn`, `guardian_boss.tscn` | ⚠️ Instance `large_male.tscn` (base) directly and add inline skin + bone attachments. Works, but these skins should live in variant scenes if they're fixed per-character. |
| `overlord_actor.tscn` via `scenes/player/player_model.tscn` | ❌ `player_model.tscn` is a `Node3D` wrapper, not an inherited scene. No external AnimationLibrary. Refactor to `assets/characters/lich.tscn` as inherited scene. |
| `assets/characters/enemies/guardian_model.tscn` | ❌ Orphaned — no actor uses it. Either delete or adopt it as the model for `guardian_boss.tscn`. |
| `assets/characters/Lich-applying.glb`, `Lich-arms.glb`, `arms.fbx`, `FPS arms.blend.glb` | ❌ Raw imports with no sibling `.tscn`. Create inherited scenes before using in new gameplay work. |

These are cleanup items, not blockers — the game runs. Tackle when touching the relevant asset.
