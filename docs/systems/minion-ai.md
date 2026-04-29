# Minion AI / Behavior Architecture

**Build status:** Design proposal — not yet implemented. The current per-state-script-override pattern (see § "Today") still works for the four minion roles in flight (combat fighter, advisor, courier, info-courier). This doc captures the architecture we'll migrate toward when role count or composition complexity makes the override pattern hurt.

---

## Today: per-minion-type state-script overrides

Each `MinionActor` instance currently shares a single `RewindableStateMachine` with four states inherited from `minion_actor.tscn`:

```
RewindableStateMachine
├── IdleState   (script: idle_state.gd)
├── ChaseState  (script: chase_state.gd)
├── AttackState (script: attack_state.gd)
└── JumpState   (script: jump_state.gd)
```

For non-combat roles, individual minion-type scenes **override the script** on specific inherited state nodes:

| Type | IdleState script | ChaseState script | AttackState | JumpState |
|---|---|---|---|---|
| Combat fighter (skeleton, imp, sprite, cultist, …) | inherited | inherited | inherited | inherited |
| Advisor | `advisor_idle_state.gd` | `advisor_follow_state.gd` | inherited (unreachable) | inherited (unreachable) |
| Courier | `courier_arrival_state.gd` | inherited (used for travel) | inherited (unreachable) | inherited (unreachable) |

This works because:

- Combat fighters never override — shared logic.
- Specialty roles override the specific state(s) they need to repurpose, leave the rest dormant. Their stat blocks (`aggro_radius=0`, `damage=0`, `attack_range=0`) ensure the unreachable states are never entered.

**Pros:** zero new abstraction; .tscn property override is a Godot-native pattern; advisor/courier each cost ~1 .tres + 1 .tscn + ~1 state script.

**Cons that bite at scale:**

1. **No composition.** "Combat fighter that also retreats" is not a state-script override — it's the standard combat tree *plus* a Retreat trigger that any state can fire. Today this is solved by hand-editing each combat state to add a check.
2. **No mission-shape policies.** "Travel → observe N seconds → return → flush log" is a sequence of state transitions; you can't easily say "this minion's mission is X, run that script." The advisor and courier each encode their mission inside their state scripts directly, mixing motor and policy.
3. **Adding a role = touching multiple shared files.** Retreat-from-combat needs an edit in `idle_state.gd`, `chase_state.gd`, *and* `attack_state.gd` to add the trigger. That's a recurring tax on every shared state.
4. **No declarative composition.** You can't author a "behavior" as a `.tres` and assign it on a `MinionType` resource the way other game data is authored.

---

## Where it currently strains

**Forced retreat (war-table.md step 6).** Conceptually a *cross-cutting trigger* that any combat state should yield to. Forces edits in three shared scripts unless we factor it out.

**Info-courier (step 8).** A multi-stage mission: Travel → Observe → Return → Flush. Today's pattern would be three more state-script overrides on top of the courier scene, with bespoke transition logic encoded in each.

**Future: scout-mission, defend-position, patrol-route, follow-target, kamikaze, hold-line, escort-courier.** Each is a "policy" composed of a few motor states and a control loop. Without an abstraction they each need ~1 actor scene + ~3 state scripts + transition logic.

---

## Proposed: Resource-based `MinionBehavior`

A `MinionBehavior` is a **policy controller** authored as a `.tres`. It runs alongside the state machine, reads the minion's situation each tick, and decides which state to be in. States stay as **motor primitives** (move, attack, navigate, idle) — they don't decide goals.

### Schema sketch

```gdscript
class_name MinionBehavior extends Resource

## Per-minion runtime instance — behavior state lives here, not on the actor.
## The behavior creates one of these in setup() and owns it for the minion's
## lifetime. This keeps the .tres immutable and the per-instance bookkeeping
## (timers, mission progress, accumulated logs) out of the resource.
class Instance:
    var minion: MinionActor
    var behavior: MinionBehavior

func setup(minion: MinionActor) -> Instance:
    var inst := Instance.new()
    inst.minion = minion
    inst.behavior = self
    return inst

func tick(inst: Instance, delta: float) -> void:
    pass  # override

func enter(inst: Instance) -> void:
    pass  # override
```

`MinionType` gains:

```gdscript
@export var behavior: MinionBehavior  # null = use the default CombatBehavior
```

`MinionActor._physics_process` (host) calls `_behavior_instance.behavior.tick(_behavior_instance, delta)` after gravity and before the state-machine tick.

### Behavior catalog (current + planned)

| Behavior | Used by | Decides |
|---|---|---|
| `CombatBehavior` (default) | skeleton, imp, sprite, cultist, ghoul, … | Idle ↔ Chase ↔ Attack based on hostiles in `aggro_radius` and `attack_range` |
| `AdvisorBehavior` | advisor | Idle (within follow distance) ↔ Chase (toward owner overlord) |
| `CourierMissionBehavior` | courier | Travel-to-waypoint → ArrivalAction → Despawn |
| `RetreatableBehavior(wraps: MinionBehavior)` | any combat fighter with `can_retreat = true` | Delegates to wrapped behavior; intercepts when HP < threshold and switches to RetreatState |
| `InfoCourierMissionBehavior` (planned, step 8) | info_courier | Travel → Observe(N sec) → Retreat-and-flush |
| `ScoutBehavior` (planned, scout) | scout | Maintain station at broadcast-range edge; passive observation |
| `PatrolBehavior` (planned) | future | Cycle waypoints; engage hostiles if encountered |
| `EscortBehavior(target_id)` (planned) | future | Stay near target id; engage threats to it |

The wrapping pattern (`RetreatableBehavior`) is what makes this scale: composable, optional, doesn't pollute the wrapped behavior.

### Where states live in the new world

States become small, single-purpose, motor-only:

- `IdleState` — animation + zero velocity.
- `ChaseState` — navigate to a waypoint provided by the behavior. (Today's ChaseState already does this, but it also picks targets — we'd move target selection into CombatBehavior.)
- `AttackState` — perform the attack animation; once.
- `RetreatState` (new, step 6) — navigate to owner spawn marker; flush observation log on arrival.
- `JumpState` — over a NavigationLink3D.
- `ObserveState` (new, step 8) — stand still, accumulate sightings into the actor's `_field_log`.
- (More as missions need them.)

Behaviors compose these states; states don't know about behaviors.

---

## Migration path

We don't migrate now. Triggers for the migration:

- **8+ distinct AI roles** in flight (we're at ~4: combat, advisor, courier, info-courier-incoming).
- **A behavior we'd want to compose** (e.g. retreat + combat, scout + retreat) where the override pattern forces a new state-script set per combination.
- **Modders / designers wanting to author behaviors as data** (probably never; not a game with a public modding surface).

Two-phase migration when we do:

1. **Introduce `MinionBehavior` alongside states**, default-null on existing `MinionType`s. Existing minions keep working unchanged. New roles use the abstraction directly.
2. **Refactor existing types** one-at-a-time onto behaviors. Combat fighters → `CombatBehavior`. Advisor/courier → their behaviors. Delete the per-scene state-script overrides as each migrates.

Steps 6 (retreat) and 8 (info-courier) ship with the **current** pattern (one-off scripts). They'll be the first refactor candidates when we cross the trigger threshold — both naturally compose, and retreat-as-wrapper is the canonical composition example.

---

## Open questions

- **Where does behavior state live?** Two options: (a) on the `Instance` class above (preferred — clean separation, behaviors are pure data), (b) on the `MinionActor` directly via dynamic property bag (looser, more Godot-typical). Going with (a) for type-safety.
- **Behavior + RewindableStateMachine.** The state machine is networked-rollback (netfox). Behaviors are host-authoritative for now (only the host runs them; clients sync state via `MinionManager._sync_minion_actor`). If behaviors ever need to be rollback-aware (e.g. predicted client-side mission timers), this gets harder. Not in scope until we have a concrete need.
- **Scope of behavior decisions.** Combat target selection, waypoint choice, retreat triggers — all behavior-driven. Should "should I jump this gap" also be? Probably not — that's reactive motor work, lives in `_on_link_reached` → JumpState as today.
- **Data-driven authoring.** Could a designer author a `PatrolBehavior` from a `.tres` with a `waypoints: Array[Vector3]` and `repeat: bool` and not need to touch GDScript? Yes for trivial cases; complex behaviors will still need scripts. Design for the simple cases.
