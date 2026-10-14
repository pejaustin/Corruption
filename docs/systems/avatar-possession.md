> Superseded by docs/GDD.md (v2, 2026-10-08). Reference only: where this disagrees with the GDD, the GDD wins.

# Avatar Possession Rework — ownership/control split

**Build status:** Phases A + B implemented 2026-06-05; Phase C implemented 2026-06-09; D re-speced 2026-06-10 (corruption upkeep, escalating rate), not built
**Test plan:** `docs/technical/test-plan-corruption-avatar.md` (cold-start manual steps)
**Flag:** none — this IS the avatar model. The `AVATAR_AS_MINION` flag and the legacy hot-seat path (claim = control, round-robin transfer, corruption fallback) were deleted 2026-06-09 after first hands-on testing confirmed the possession loop functions.

---

## Design

The Avatar stops being a hot seat that some overlord ALWAYS occupies. It becomes an **optionally controllable minion**:

- **Ownership** (whose pawn is it) and **control** (who is driving it right now) are separate.
- The Avatar starts the match **neutral and unowned** near the Capitol. The first overlord to claim it owns it.
- The owner can **possess** it (take direct 3rd-person control, as today) and **release** it with Q — returning to overlord mode while *keeping ownership*. No round-robin. Nobody is forced into the seat.
- While owned-but-uncontrolled, the Avatar runs **full minion AI**: it appears as a pawn on the owner's war table, is selectable and commandable through the same draft → courier flow as any minion, walks to waypoints, aggros, and fights.
- Ownership moves ONLY two ways:
  1. **Defeated in combat** — killer minion's owner takes ownership (hostile takeover); killed by neutrals → reverts to unowned/neutral.
  2. **Upkeep lapses** — the owner's corruption can't pay the upkeep (see below).

### Upkeep (ambient corruption) — re-speced 2026-06-10

No separate gauge. Under the one-currency model (corruption IS the money — see `mvp-roadmap.md` W3), owning the Avatar drains the owner's **corruption** directly, host-ticked on `GameState`:

- **Drains while owned** — possession costs upkeep, paid from the same pool that buys minions and upgrades.
- **The rate escalates** the longer ownership is held — nobody can hold the Avatar forever.
- **Escalates faster while released-to-AI** than while directly possessed — hands-on piloting is rewarded; parking it on autopilot is the expensive way to keep it.
- **Can't pay → ownership reverts to neutral.** The Avatar walks free; anyone may claim it. The escalation clock resets for the next owner.

This chains the whole loop together: hold gem sites → corruption income → afford the Avatar's upkeep *and* an army → capture power → more gem sites.

### What died (removed 2026-06-09)

- Round-robin transfer (`GameState.release_avatar()`'s auto-next, `_get_next_peer`).
- The "always controlled" enforcement and the recall-passes-the-torch semantics. Q is now "let go of the wheel", not "give it to the next player".
- Corruption fallback on neutral death (highest-corruption peer auto-takes) — replaced by revert-to-neutral + re-claim. (The corruption *score* still gates nothing here; it feeds the gauge instead.)
- The `AVATAR_AS_MINION` flag itself and its pause-menu toggle/RPC.

---

## Implementation phases

Each phase lands behind the flag and is testable in `scenes/test/war_table_test.tscn` (extended with the real Avatar + a claim/possess hotkey).

### Phase A — ownership/control split [IMPLEMENTED 2026-06-05, untested]
- `GameState`: `avatar_owner_peer_id` (-1 = neutral) alongside `avatar_peer_id` (controller, -1 = uncontrolled), `_set_avatar_owner` RPC + `avatar_owner_changed` signal. `request_claim_avatar` = own+possess (unowned) or re-possess (own, uncontrolled); `request_recall_avatar` (Q) clears controller only.
- `AvatarActor`: `possess(peer)` / `release_control()` (control-scoped — no HP/faction touch) vs `_on_avatar_owner_changed` (ownership-scoped — faction, fresh HP on new owner, dormant neutral husk when unowned). Death: killer-minion owner gains ownership (no auto-possess; own-minion kills don't transfer); neutral kill → unowned. Round-robin and corruption-fallback skipped under the flag.
- `MultiplayerManager._on_avatar_changed`: controller −1 with an owner → `release_control()` (pawn stays in the field); unowned → `deactivate()`.
- `avatar_claim.gd`: claim / "possess your Avatar" / "Avatar sworn to <faction>" prompts.
- Debug: pause-menu "Toggle Avatar-as-Minion" (host → RPC all peers); F3 shows Owner | Controller.

### Phase B — AI brain (host-driven input) [IMPLEMENTED 2026-06-05, untested]
- `AvatarAI` node (`scenes/actors/player/avatar/avatar_ai.gd`) + `NavAgent` (NavigationAgent3D) on `avatar_actor.tscn`. `AvatarInput._gather` delegates to `ai_driver.drive()` while `is_driving()` (flag on, owned, uncontrolled, alive, host) — the host is input authority then, so AI input rides the normal rollback sync.
- Steering: the AI points the **camera mount** at the nav path and pushes `input_dir = (0, -1)` — `camera_basis` is already a synced input property, so movement and model-facing replay identically on every peer. Targets: nearest `FactionRelations.is_hostile` minion within `AGGRO_RADIUS` 10 (sticky to `LEASH_RADIUS` 15), melee at `ATTACK_RANGE` 2 by holding attack input. Waypoints via `command_move(pos)` (cleared on possess and on ownership change).
- Debug: pause menu → **"Order Avatar to Camera"** (host) drives `command_move` — the same entry point Phase C's war-table routing will use.

### Phase C — war-table pawn + commands [IMPLEMENTED 2026-06-09, untested]
- `KnowledgeManager`: the Avatar enters WorldModels as a sighting with the reserved id `AVATAR_ID` (-100; minion ids are positive). Its owner always sees it (a broadcasting unit self-reports, like a friendly minion observing itself); rivals see it under the normal broadcast-range rules. Untracked (unowned / dormant / dead / flag off) → forgotten from all models, parity with minion death; a mere ownership flip just lets the loser's entry go stale ("?").
- `WarTableMap`: the avatar never merges into a stack — always its own cluster, rendered 1.6× scale with an "AVATAR" Label3D badge. Selection/tinting/pending-lock reuse the generic id machinery; `WarTablePiece` prompts "[E] select Avatar" and the existing owner check makes rival pieces unselectable.
- Command routing: `issue_move_command` splits `AVATAR_ID` out — instant path goes through `KnowledgeManager.request_avatar_move` (host-validated RPC → `AvatarAI.command_move`); the courier path needs no draft-side change (`_build_legs` reads the believed sighting like any id) and `courier_arrival_state` delivers the avatar leg straight to `AvatarAI` after the usual visual-range + ownership checks (ownership flipped in transit = failed delivery, same as a dominated minion).

### Phase D — corruption upkeep (re-speced 2026-06-10)
- Host ticks a corruption drain on the owner while `avatar_owner_peer_id != -1`: base rate × an escalation factor that grows with time-since-claim, with a higher escalation multiplier while uncontrolled (`avatar_peer_id == -1`, AI driving) than while possessed.
- Corruption can't cover the tick → host reverts ownership to neutral (same revert path as a neutral kill); escalation clock resets for the next owner.
- Numbers (base drain, escalation curve, AI multiplier) tuned in the harness. F3 line + owner-side HUD pip showing current drain rate.
- Depends on the W3 one-currency rework (corruption must be spendable before it can be drained).

## Open questions

- Does the *neutral* (unowned) Avatar do anything, or stand dormant where it was lost? (v1: stands dormant/idle, claimable by walk-up E in the world — not just the tower interactable?)
- Upkeep numbers: base drain, escalation curve, AI-mode multiplier — pick after Phase D harness play. (~~Should possessing pause the drain?~~ Answered 2026-06-10: no pause — direct control slows the *escalation*, AI mode speeds it.)
- Boss-fight interaction: astral projection assumed "the Avatar peer" — with possession optional, spectate keys off the *controller*, falls back to owner.
