# Changelog

Dated record of shipped work, verification passes, and design calls — newest first. Forward-looking state lives in `build-phases.md`; war-table build history detail in `docs/systems/war-table.md` (numbered steps + map-representation phase plan).

---

## 2026-06-05 — War-table phase 3/4 test pass + multiplayer client fixes

Full verification pass over the phase 3/4 refactor: every harness system (`war_table_test.tscn`) and every main-game system in a 2-peer session. Everything below is **verified working** unless marked otherwise.

### Verified — War Table command flow (harness + 2-peer main game)

- Single-shot-E flow end to end: piece E selects (multi-member stacks open the ghost popup; ghost E selects single members), MapTarget E records a draft at the crosshair point, Paper E promotes drafts → readied, Reset E wipes drafts + selection (readied/dispatched untouched). No camera takeover, no rig pin.
- Stage visuals: red order arrow per leg (draft) → amber in place (readied) → black + light-blue route arrow (dispatched). Same arrow node throughout; both arrows evaporate together on courier despawn or mid-flight death.
- Couriers: batched per `MinionType.max_orders` (N sub-orders ride one courier, multi-leg with TSP-greedy ordering), spawn at the tower's ground-level `CourierSpawn`, per-leg visual-range + loiter delivery check (`courier_visual_range` / `courier_wait_seconds`), walk home, despawn on zone overlap. Failed deliveries report home into `WorldModel.failure_messages`.
- Ghost popup: latch open/close on E, per-ghost selection, 1.5s grace-timer auto-close that survives glancing at the MapTarget, clean handling of member death mid-popup, pending members filtered from re-selection.
- Advisor: idles ≤3.5m / follows / settles at 2.0m, never fights, Hurtbox live (`Shift+K`). Handoff prompt: "confer" (0 readied) / "hand orders (N)" / "Another overlord's Advisor" (non-owner, E no-op).
- Reality overlay (M): yellow spheres track both courier kinds' actual positions; belief layer untouched when off.
- Suppression: no support-staff minion (`courier` / `info_courier` / `advisor` trait) ever renders as a table pawn, own or rival (`KnowledgeManager.UNTRACKED_TRAITS` gate).
- Broadcast-range gating (`INFINITE_BROADCAST_RANGE = false` default): only enemies within 30m of a friendly minion enter the WorldModel; sightings persist at last-known position; stale clusters (>3s, `WarTableMap.STALE_THRESHOLD_SECONDS`) show a red "?" badge that clears on refresh.
- Info-courier (`I`): travel → loiter-observe (12m, 4s) → return → flush; sightings appear on the table even with broadcast gating on. (Premature-retreat-on-damage deferred with the `can_retreat` work.)
- Belief privacy: each table renders only for its owning peer on their own client; rival tables are inert props.
- **Client-peer parity**: the full draft → ready → dispatch → deliver loop works for a non-host overlord (see Fixed below).

### Verified — other systems

- Summoning Circle slot flow: per-roster `SummoningSlot` prompts, cost/cap gating, live faction-cycle rebind, avatar-mode gate.
- Upgrade Altar slot flow: per-upgrade `UpgradeSlot` prompts, host purchase, **client purchase via `_request_upgrade.rpc_id(1)` round trip**, insufficient-funds rejection, `[MAX]`, per-peer resource deduction, cross-tower gating. (Effect multipliers not yet spot-checked — still open in build-phases.)
- Advisor faction binding: own minions no longer read their advisor as NEUTRAL-hostile.
- Camera-rotation leak fix: a peer's overlord body no longer rotates for remote viewers while that peer controls the Avatar / scries.
- Focus fix: tower rig fires no phantom prompts while its peer is Avatar.
- Pause-menu debug toggles (courier visual range / instant commands / broadcast range).

### Fixed — multiplayer client command loop (three stacked bugs)

1. **Client slot resolution** — `MultiplayerManager._player_slot_order` is host-only, so `get_player_slot()` returned -1 for everything on clients, nulling courier-spawn lookups and silently dropping drafts. Clients now learn peer→slot from `_bind_rally_rpc` into `MinionManager._peer_slots` (`_slot_for_peer` consulted by all per-peer lookups).
2. **Host binding heal** — the host's initial bind loop can race slot assignment, and `_request_rally_bindings` only replied to the requester, leaving host-side tower/advisor owner bindings permanently unset. Requests now trigger a full **broadcast** rebind (idempotent), healing host and all clients.
3. **Owner-authoritative dispatch** — `pending_commands` live only in the owner's local WorldModel (models are never replicated), but dispatch ran host-side reading the host's empty copy. Now: Advisor E → `KnowledgeManager.request_dispatch` gathers local readied entries (in-flight latch against double-E) → `_request_dispatch_rpc` to host (owner = sender) → host `_dispatch_entries` batches + spawns → per-entry `_dispatch_confirmed_rpc` back to the owner (confirm with courier_id + route, or reject −1 leaving the entry readied). Delivery-failure reports take the same hop (`_delivery_failures_rpc`).

Plus: pre-placed tower Advisors are now **adopted into `MinionManager._minions_node`** at scene setup — previously each peer had a frozen local copy and only the host saw the advisor follow (no `_sync_all_minions` coverage).

### Design calls

- **Couriers and Advisors never render as table pawns**, own or rival (`UNTRACKED_TRAITS`). Spotting rival runners becomes future interception gameplay (step 14 falsification), not a free broadcast sighting. Reality overlay still shows couriers (`COURIER_TRAITS`).
- **Belief is private to the owner's table on their own client** — rival tables render nothing (was: any player could glance at any table).
- **`INFINITE_BROADCAST_RANGE` and `INSTANT_COMMANDS` both default `false`** — the information-warfare model and courier loop are canonical play; god-view/instant are debug toggles.

### Harness rework — real-scale field

`war_table_test.tscn` playspace expanded 30×30 → **300×300 (production `map_world_size`)**: real broadcast ranges, courier travel times, and visual ranges. Overlord + table + Advisor on a 40m observation platform at the east edge (own nav island); couriers stage at a ground-level `CourierSpawn` below. New hotkeys: `H` time-scale cycle (1/2/4/8×), `K` kill-nearest skips the Advisor, `Shift+K` includes it. PlayspaceBorder removed (`WarTableRange` is the single region marker). HUD/doc text updated to the single-shot-E flow.

### Earlier history

War-table map-representation phases: phase 1 — piece colliders, no camera takeover (2026-04-30); phase 2 — auto-merging stacks (2026-05-02); phases 3/4 — in-world inspect popup + multi-leg batched couriers (2026-05-06, refined through 2026-06-05). Detail in `docs/systems/war-table.md`. Tier 0–2 build history: see git log.
