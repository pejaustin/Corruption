# Test Plan — Corruption rework + Avatar possession (resume point)

**Status as of 2026-06-10:** implemented. A first hands-on smoke pass (2026-06-09) confirmed the possession loop end to end — enough to delete the `AVATAR_AS_MINION` flag and make this THE avatar model — but the **formal checklists below are unticked**. This doc is the cold-start guide — read it after clearing the session to pick the work back up. Detail lives in `corruption-and-gems.md`, `avatar-possession.md`, and the dated entries in `changelog.md`.

---

## What was built (and the files that hold it)

Three changes stacked on top of the corruption-unification commit:

### 1. Gem-site capture rework — contest gate + ceiling/regen
- `scripts/interactibles/gem_site.gd` — capture is blocked by **hostile** minions in `contest_radius` (not gated on friendlies); a held site raises the holder's MAX corruption by `max_corruption_contribution` (7) and regens 0.5/s toward it; sites never deplete.
- `scripts/game_state.gd` — `get_max_corruption(peer)` = Σ held-site contributions.
- `scripts/interactibles/capture_channel.gd` — new `interrupt(reason)` for host-side breaks.
- `scripts/test/capture_channel_test_controller.gd` + `scenes/test/capture_channel_test.tscn` — harness updated ([2] now spawns a hostile AT the site).

### 2. Avatar possession Phase A — ownership/control split
- `scripts/game_state.gd` — `avatar_owner_peer_id`, `_set_avatar_owner` RPC, `avatar_owner_changed` signal; claim/recall rewritten for the ownership/control split. (Originally shipped behind an `AVATAR_AS_MINION` flag; flag + legacy hot-seat path REMOVED 2026-06-09 — this is the only model now.)
- `scenes/actors/player/avatar/avatar_actor.gd` — `possess()` / `release_control()` (control-scoped) vs `_on_avatar_owner_changed` (ownership-scoped); new death rules.
- `scripts/network/multiplayer_manager.gd` — released-but-owned avatar stays in the field.
- `scripts/interactibles/avatar_claim.gd` — claim / possess / "sworn to <faction>" prompts.

### 3. Avatar possession Phase B — host-driven AI brain
- `scenes/actors/player/avatar/avatar_ai.gd` (NEW) + `NavAgent`/`AvatarAI` nodes in `avatar_actor.tscn`.
- `scripts/avatar_input.gd` — `_gather` delegates to `ai_driver.drive()` when owned-but-uncontrolled.

### 4. Avatar possession Phase C — war-table pawn (added 2026-06-09)
- `scripts/knowledge/knowledge_manager.gd` — reserved `AVATAR_ID` (-100) sighting in WorldModels; `request_avatar_move` RPC (instant path); courier-dispatch diagnostics.
- `scripts/interactibles/war_table_map.gd` / `war_table_piece.gd` — oversized "AVATAR"-badged piece, owner-only selection.
- `scenes/actors/minion/states/courier_arrival_state.gd` — courier delivers the avatar leg to `AvatarAI.command_move`.

### Debug surface (all in `debug_manager.gd` + `in_game_menu.gd`/`.tscn`, host-only)
- **Order Avatar to Camera** — drives `AvatarAI.command_move` (the same entry point as the war-table routing).
- Spawn/order buttons raycast the crosshair against world geometry (`_aim_world_point`) so they work on heightmapped terrain, not just y=0.
- F3 overlay: Corruption shows `current / max`; Game State always shows `Avatar Owner | Controller`.

> **Commit scope:** the terrain/cania churn landed separately (`8bec331 new terrain stuff`). The current working tree holds exactly the gem-rework + possession Phases A–C + debug-aim work described here — commit as one unit once tested.

---

## Step 0 — Editor sanity (do first, ~2 min)

Open the project, watch Output/Errors:
- [ ] No parse errors in `avatar_ai.gd` / `avatar_input.gd` (they cross-reference each other's types — fine on Godot 4.2+; if it complains about cyclic resolution, retype `ai_driver` as `Node` and tell Claude).
- [ ] `avatar_actor.tscn` opens clean; `NavAgent` + `AvatarAI` nodes present at the root, nothing red.
- [ ] `in_game_menu.tscn` shows the "Order Avatar to Camera" button (no avatar-as-minion toggle — the flag is gone, possession is the only model).

---

## Step 1 — Gem sites (harness: run `scenes/test/capture_channel_test.tscn`)

- [ ] Walk to GemSite, press E → channel starts **immediately** (no pre-clear step).
- [ ] Channel completes → prompt `CAPTURED (+7 max)`; HUD "My corruption" climbs 0.5/s and **stops at 7.0 / 7.0 max**.
- [ ] `R` to reset, `[2]` → hostile sprite at the site; prompt reads **"contested"**, E does nothing.
- [ ] `K` (clear), E to start a channel, `[2]` mid-channel → channel **breaks**.
- [ ] `[3]` during a channel → damage still interrupts (regression).

---

## Step 2 — Avatar possession, solo host (main game)

Host a game. (Possession is the default model as of 2026-06-09 — no flag to toggle. F3 shows `Avatar Owner: neutral | Controller: released` from the start.)

- [ ] Tower claim station → E → 3rd-person control; avatar does NOT teleport to you (you take it where it stands).
- [ ] Move it, take a couple hits from a Holy Knight, then **Q** → back in tower body; F3 `Owner: 1 | Controller: released`; avatar stands in the field in your faction.
- [ ] **AI aggro:** aim near the avatar, Esc → Spawn Enemy at Camera → avatar chases + melees it dead, then idles. (Spinning/moonwalking = facing bug; inert = AI not driving, check console.)
- [ ] **AI orders:** aim at distant ground, Esc → Order Avatar to Camera → it travels there, fighting en route, stops on arrival.
- [ ] **Re-possess:** station reads "possess your Avatar" → E → **HP did NOT refill** from the earlier damage.
- [ ] **Neutral death:** Q out, Esc → Kill Avatar → ~2s later F3 `Owner: neutral`, dormant husk at origin, station back to "claim".

---

## Step 2.5 — Avatar on the war table (Phase C, added 2026-06-09)

Still solo host, avatar claimed then Q'd out (AI-driven):

- [ ] Walk to your tower's war table → the avatar shows as an **oversized faction-tinted piece with an "AVATAR" badge** (regular minions unchanged).
- [ ] Aim at it → prompt "[E] select Avatar" → E → piece tints yellow (selected).
- [ ] E on empty map → red draft arrow; Paper → Advisor (E) → courier walks out, reaches the avatar, avatar travels to the ordered point. (`INSTANT_COMMANDS` toggle for the no-courier shortcut.)
- [ ] Mixed selection (avatar + a couple of minions) → single draft, all arrive.
- [ ] Possess the avatar → pending order voided, piece stays on the board; Q → AI resumes idle.
- [ ] Kill Avatar (neutral death) → piece disappears from the table; re-claim → reappears.

## Step 3 — Two instances (Debug → Run Multiple Instances → 2)

- [ ] Host possesses + moves → client sees smooth movement (regression).
- [ ] **(highest risk)** Host Qs out, spawns enemy near AI avatar → **client watches the AI fight smoothly** — rubberbanding/teleporting here = input-authority problem, report it.
- [ ] **Hostile takeover:** client claims + Qs out; host spawns 2-3 of its OWN minions next to the AI avatar; on its death → F3 `Owner: 1` (host), nobody auto-possesses, host can possess at its station.

---

## When you come back

1. Skim `changelog.md` top entries (2026-06-05 → 06-09) for the why. Note: avatar-as-minion is the DEFAULT model now (flag removed 2026-06-09).
2. Run Step 0, then Steps 1→3.
3. Tick results in `build-phases.md` ("Minor gem sites", "Avatar Possession Rework" Phase A/B/C sections — this doc mirrors those).
4. Report pass/fail to Claude. Known open item: courier dispatch for an avatar order reportedly produced no courier (2026-06-09) — diagnostics added, watch the console for `[KnowledgeManager] Courier N dispatched...` vs the draft warnings. If A–C hold, next build work is **Phase D** (upkeep gauge) — speced in `avatar-possession.md`.
