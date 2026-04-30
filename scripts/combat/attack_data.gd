class_name AttackData extends Resource

## Per-swing balance data for a single attack. Authored as `.tres` files under
## `res://data/attacks/`. Tier D (avatar combat) extracted these out of the
## per-state `@export`s so:
##
##   1. The same data shape covers light_1/2/3, heavy_1, charge releases,
##      sprint attack, jump attack, and the riposte execution.
##   2. Designers tune values in the inspector (or via the balance CSV pipeline
##      once `balance_csv.gd` adds AttackData to its TARGETS table) without
##      cracking open code.
##   3. Combo strings chain by `next_attack_id` lookups against a flat catalog
##      rather than a hard-coded transition table.
##
## Lookup at runtime is via `AttackData.lookup(id)`, which scans
## `res://data/attacks/` once on first call and caches the result. Each state
## takes an `@export var attack_data: AttackData` so the scene authors can drag-
## drop a `.tres`; the `next_attack_id` chain is resolved lazily at combo time.
##
## This resource is consumed by:
##   - `light_attack_state.gd`, `heavy_attack_state.gd`, `charge_release_state.gd`,
##     `sprint_attack_state.gd`, `jump_attack_state.gd`, `riposte_attacker_state.gd`
##   - The hitbox enable/disable path inside those states reads `hitbox_profile`,
##     `damage_mult`, and `posture_damage_mult`.

## StringName id for catalog lookups (e.g. `&"light_1"`, `&"heavy_1"`).
## Authoring: must match the `.tres` filename minus extension for
## `AttackData.lookup()` to find it.
@export var id: StringName = &""

## Human-readable label for debug overlays + balance CSVs.
@export var display_name: String = ""

# --- Animation ---

## `<library>/<clip>` — same convention as existing state animation_name fields.
## Empty = the state falls back to its configured `animation_name` export.
@export var animation_name: String = ""

# --- Damage ---

## Multiplier on `actor.get_attack_damage()`. 1.0 = baseline.
@export var damage_mult: float = 1.0

## Multiplier on the base posture amount inflicted by a hit. The base lives
## in `Actor.HIT_POSTURE_PER_HIT` (Tier C). 0.0 = bypass posture entirely
## (set on riposte AttackData since the victim is already broken).
@export var posture_damage_mult: float = 1.0

## When true, the active window is treated as hyper-armor — the wielding state
## will hold `stagger_immune = true` between hitbox_start_ratio and
## hitbox_end_ratio. Independent of the animation method-track flow so the
## resource can drive it without re-authoring clips.
@export var hyper_armor: bool = false

## Tier G consumer: damage type for resistance/status. Defaults to physical;
## faction abilities set their own (fire, corruption, divine, nature, etc.).
@export var damage_type: StringName = &"physical"

# --- Hitbox window ---

## Hitbox activates at this fraction of the animation. Mirrors the legacy
## `attack_state.gd` export so values port 1:1.
@export var hitbox_start_ratio: float = 0.25

## Hitbox deactivates at this fraction. See note above.
@export var hitbox_end_ratio: float = 0.6

## Profile name forwarded to `AttackHitbox.enable(profile)`. Empty = first
## CollisionShape3D child (the existing single-shape default).
@export var hitbox_profile: StringName = &""

# --- Combo ---

## Earliest fraction within the animation where a buffered next-press chains
## into the next combo step. Must be ≥ hitbox_end_ratio so the chain doesn't
## skip the active window.
@export var combo_window_start_ratio: float = 0.55

## Latest fraction; after this the buffered press is dropped and the state
## winds down to IdleState.
@export var combo_window_end_ratio: float = 0.85

## AttackData id of the next swing in the combo. Empty = combo end (the
## current swing is the last one in the string). LightAttackState consumes
## this; non-light states ignore it (no chain on heavy / sprint / jump in
## Tier D — Tier E may extend).
@export var next_attack_id: StringName = &""

# --- Movement ---

## Forward distance the actor lunges over the active window. Applied as a
## velocity ramp in the consuming state; 0.0 = no lunge (current behavior).
## Used for sprint attack (carries momentum) and riposte (small snap-in).
@export var lunge_distance: float = 0.0

# --- Catalog ---

## Lazy in-process catalog of every AttackData under `res://data/attacks/`,
## keyed by `id`. The first call walks the directory; subsequent calls are
## dictionary lookups. State scripts use this to resolve `next_attack_id`
## without holding direct references to every chained resource.
##
## The cache is editor-only safe — it's not serialized into resources. If new
## AttackData entries are added at runtime (highly unusual; this is data-driven
## in the editor), call `clear_catalog()` to force a re-scan.
static var _catalog: Dictionary[StringName, AttackData] = {}
static var _catalog_loaded: bool = false

const _ATTACK_DIR: String = "res://data/attacks/"

static func lookup(id: StringName) -> AttackData:
	if not _catalog_loaded:
		_load_catalog()
	return _catalog.get(id, null)

static func clear_catalog() -> void:
	_catalog.clear()
	_catalog_loaded = false

static func _load_catalog() -> void:
	_catalog.clear()
	_catalog_loaded = true
	var d: DirAccess = DirAccess.open(_ATTACK_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".tres"):
			var path: String = _ATTACK_DIR + name
			var res := load(path) as AttackData
			if res != null and res.id != &"":
				_catalog[res.id] = res
		name = d.get_next()
