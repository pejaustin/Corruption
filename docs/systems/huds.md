# HUDs — Avatar & Overlord

**Build status:** Phase 0 shipped (AvatarHUD + OverlordHUD with InteractionPrompt; AvatarHUD adds HealthBar). Phase 1 shipped: AbilityCross (4-slot diamond, bottom-right), Crosshair (centered free-aim), DamageVignette (fullscreen red flash), CaptureProgress (channel bar, centered). Input actions migrated to `primary_ability` / `secondary_ability` / `item_1` / `item_2` / `interaction` / `cancel` / `roll` so bindings are reconfigurable.

---

## Design goal

Each local peer has exactly one HUD active at a time, matching their current mode:

- **AvatarHUD** — while the local peer controls the Avatar (3rd-person combat).
- **OverlordHUD** — while the local peer is in their tower (1st-person overlord).

The HUD is a **passive view**. It owns no gameplay state. Every widget subscribes to an existing signal or reads an existing value and renders it — if a widget has to invent new state, that state belongs somewhere else (Actor, GameState, KnowledgeManager, etc.).

```
┌──────── GAMEPLAY STATE ────────┐       ┌──────── HUD ────────┐
│                                │       │                     │
│  Actor (hp, stagger)           │       │  AvatarHUD          │
│  AvatarAbilities               │  ───▶ │  OverlordHUD        │
│  GameState (influence, buffs)  │       │  (passive widgets,  │
│  CaptureChannel                │       │   signal-driven)    │
│  BossManager / GuardianBoss    │       │                     │
└────────────────────────────────┘       └─────────────────────┘
         Source of truth                        Renders belief-about-self
```

World-scoped UI (DebugOverlay, WinScreen, post-process `ColorRect`) stays on `world.tscn`'s CanvasLayer. The HUDs are per-local-peer and live/die with the player scene they're attached to.

---

## Architecture

### Scene layout

- `scenes/ui/avatar_hud.tscn` — `class_name AvatarHUD extends CanvasLayer`
- `scenes/ui/overlord_hud.tscn` — `class_name OverlordHUD extends CanvasLayer`

Each HUD is instanced as a child of the matching player actor scene (`avatar_actor.tscn`, `overlord_actor.tscn`).

Gating differs per HUD because the actors don't share an authority model:

- **OverlordHUD** — every peer has its own overlord, named with that peer's id. The HUD's `_ready` queue_frees unless `multiplayer.get_unique_id() == str(parent.name).to_int()`. Visibility tracks "in tower" — hidden while this peer controls the avatar so AvatarHUD owns the prompt slot.
- **AvatarHUD** — single shared avatar across peers. The HUD stays alive on every peer for the whole session and toggles visibility on `GameState.avatar_changed`, showing only when `_actor.controlling_peer_id == multiplayer.get_unique_id()`. Both HUDs call `InteractionUI.register_prompt(...)` when they become the visible one; "most recent registration wins" in the autoload routes the prompt to the right surface.

Note: do **not** gate either HUD on `parent.is_multiplayer_authority()` — neither actor's root has its authority transferred per-peer (Avatar transfers only its `AvatarInput` child; Overlord transfers only `_player_input` / `_camera_input`). That gate looks correct on the host because the host is authority for both, but breaks for every client.

### Widget pattern

Each widget is a small sub-scene (`scenes/ui/widgets/health_bar.tscn`, etc.) with its own script. In `_ready`:

1. Resolve its data source (parent Actor, a manager, an autoload).
2. Connect the relevant signal.
3. Initialize from the current value.

No widget pokes at gameplay nodes, writes to managers, or reaches across the tree.

### Interaction prompt

`InteractionPrompt` moves off `world.tscn` and onto both HUDs. The `InteractionUI` autoload gains `register_prompt(label)` / `deregister_prompt(label)` — each HUD registers in `_ready`, deregisters in `_exit_tree`. Interactables keep calling `InteractionUI.set_prompt / clear_prompt` unchanged.

---

## Widget catalog

Legend: ✅ built · 🚧 in progress · ⬜ planned · ❓ open question

### AvatarHUD

| Widget              | Status | Data source                                        | Notes                                              |
|---------------------|--------|----------------------------------------------------|----------------------------------------------------|
| InteractionPrompt   | ✅     | `InteractionUI` autoload                           | Moved from `world.tscn`. Bottom-center.            |
| HealthBar           | ✅     | `Actor.hp_changed`, `Actor.hp`, `Actor.max_hp`     | Bottom-left. Plain `ProgressBar` for v0.           |
| AbilityCross        | ✅     | `AvatarAbilities.ability_ready / abilities_initialized`, `InputMap` | Bottom-right diamond. Right slot fixed to `primary_ability` (attack). Radial-sweep cooldown via `CooldownPie`. |
| Crosshair           | ✅     | N/A (static)                                       | Free-aim dot + plus marks, drawn in `_draw`.       |
| DamageVignette      | ✅     | `Actor.hp_changed` (delta vs prev HP)              | Red fullscreen flash, intensity scales with damage fraction. |
| CaptureProgress     | ✅     | `AvatarActor.active_channel.get_progress()`        | Centered bar above HealthBar. Visible only while channel active. |
| StaminaBar          | ❓     | TBD (stamina system not built)                     | Reserved slot once stamina lands.                  |
| BuffTray            | ❓     | `GameState.grant_eldritch_vision`, future buffs    | Temp buffs with ticking remaining-time pill.       |
| InfluenceReadout    | ❓     | `GameState.influence_changed(peer_id)`             | Possibly Overlord-only — influence is tower-side.  |
| BossBar             | ❓     | `BossManager` + `GuardianBoss.hp_changed`          | Candidate for world-scoped instead of per-HUD.     |
| Reticle / lock-on   | ❓     | TBD                                                | Blocked on lock-on targeting decision.             |

### OverlordHUD

| Widget              | Status | Data source                                        | Notes                                              |
|---------------------|--------|----------------------------------------------------|----------------------------------------------------|
| InteractionPrompt   | ⬜     | `InteractionUI` autoload                           | Same widget as avatar, shared sub-scene.           |
| InfluenceReadout    | ❓     | `GameState.influence_changed(peer_id)`             | Primary overlord resource.                         |
| MinionRoster        | ❓     | `MinionManager` (peer-owned count by type)         | How many of each minion type are alive & where.    |
| CommandFeedback     | ❓     | `KnowledgeManager.pending_commands`                | "Courier en route", "orders undelivered", etc.     |
| AdvisorTicker       | ❓     | Advisor system (see `docs/systems/advisor.md`)     | Short-form advisor lines.                          |
| AvatarStatus        | ❓     | `GameState.avatar_changed`, Avatar `hp_changed`    | "Avatar: <faction> @ 60%" while not controlling.   |
| BossBar             | ❓     | `BossManager` + `GuardianBoss.hp_changed`          | Same question as above — shared or world-scoped.   |

---

## Per-mechanic checklist

When a new mechanic lands, update this doc:

1. Add a row to the relevant widget table (or confirm an existing one).
2. Mark status on ship (`⬜ → ✅`).
3. Link its signal / data source so the HUD's dependency surface stays auditable.
4. If the widget needs new state, add that state to the gameplay system first — never to the HUD.

---

## Build phases

### Phase 0 — Scaffold (minimal) ✅

- Create both HUD scenes with only `InteractionPrompt`.
- Move `InteractionPrompt` off `world.tscn`, update `InteractionUI` autoload to use a register/deregister API.
- Add `HealthBar` to AvatarHUD bound to `Actor.hp_changed`.

### Phase 1 — Combat feedback ✅

- AbilityCross (4-slot diamond, primary=attack fixed on right).
- Input action migration to named actions (`primary_ability` / `secondary_ability` / `item_1` / `item_2` / `interaction` / `cancel`).
- Crosshair (drawn primitive).
- DamageVignette (red fullscreen flash on HP drop).

### Phase 2 — Resource & buff surface

- InfluenceReadout on OverlordHUD, BuffTray on AvatarHUD.

### Phase 3 — Information-warfare integration

- OverlordHUD CommandFeedback (wired to `KnowledgeManager`), AdvisorTicker, MinionRoster.

### Phase 4 — Boss fights

- Decide BossBar ownership (world vs. HUD), wire to `BossManager`.

---

## Open questions

- **BossBar ownership** — world-scoped (all peers see identical bar, like a raid UI) or per-HUD (belief-aware, shows what your overlord thinks the boss's state is)? Information-warfare argument points to per-HUD.
- **InfluenceReadout** — Avatar-visible or Overlord-only? Influence is a tower resource but also drives Avatar succession.
- **Crosshair / lock-on** — blocked on the `avatar-combat.md` open question about aim model.
- **HUD ownership on avatar transfer** — attached-to-actor (simpler, current plan) vs. instanced-from-`MultiplayerManager` (survives mode swaps without re-instancing). Start with attached-to-actor; revisit if transfer-flicker shows up.
- **Art direction** — placeholder rectangles for v0. Faction-themed theme resource once art exists.
