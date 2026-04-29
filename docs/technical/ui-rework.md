# UI / UX Rework Tracker

Concrete tracker for the "UI/UX pass" listed in `build-phases.md` Tier 5. Components are added here as their target design solidifies — each entry captures the current state, the target state, and any dependencies blocking the rewrite. Build order across components is opportunistic; entries are not strictly tiered.

This doc is a **transition tracker**, not a permanent system spec. Once a component lands in its target form, move its spec to the appropriate `docs/systems/*.md` and remove the entry here.

---

## Palantir — multi-target scry picker

**Status:** Not started. Current `scripts/interactibles/palantir.gd` is single-target (Paladin only), one orb per tower, no watcher cap, no picker.

**Target design:** see `docs/systems/war-table.md` § "Scout & Scry" for the gameplay spec. UI/UX deltas:

- **Target picker on interact.** Pressing E on the Palantir opens a list of every currently active scryable target in the match — the Paladin (when one exists) plus every living Scout owned by any peer. Each row shows: target name (Paladin / "<Owner>'s Scout"), faction tint, current watcher count, and "FULL" badge if at cap.
- **Bandwidth gating.** Each scryable target has `@export var max_concurrent_watchers: int = 4` on its actor scene (Scout actor, Paladin/Avatar actor). Picker rows for full targets are disabled. Slots free immediately on watcher disconnect (Q exit, watcher's tower destroyed, target dies) — no queue.
- **Switch-target flow.** While scrying, Q exits to picker (not all the way back to overlord mode); choosing a new target starts a fresh scry. ESC / a second Q fully exits.
- **Watcher visibility on the target.** Multiple watchers each render their own ghost cube on the target — no aggregation, no count abstraction. Matches today's single-watcher rendering, just N times over.
- **Cross-faction visibility is intentional.** The picker lists rival players' Scouts. Deploying a Scout offers free intel to enemies. First build keeps scry fully public; alliance gating is deferred (see war-table.md open questions).

**Dependencies:**
- Scout actor scene + behavior (war-table.md build order steps 5/8) — picker has nothing to list until Scouts can be deployed.
- Multi-watcher bookkeeping in whatever owns the watcher table today (`GameState.watcher_positions` is keyed by peer, so already supports N peers; the missing piece is per-target binding rather than the global Avatar binding).

**Files this rewrite will touch:**
- `scripts/interactibles/palantir.gd` — target picker, multi-target streaming, cap enforcement.
- `scenes/interactibles/palantir.tscn` — picker UI children.
- New scryable-target component (or scriptlet) on `scout_actor.tscn` + `avatar_actor.tscn` exporting `max_concurrent_watchers`.
- `GameState` watcher table — keys may need to change from `peer_id → position` to `(target_id, peer_id) → position`.

---

## (Future components)

Add new entries here as the rework scope grows. Suggested template:

```
## <Component> — <one-line summary>
**Status:** ...
**Target design:** ...
**Dependencies:** ...
**Files this rewrite will touch:** ...
```
