class_name FactionProfile extends Resource

## Identity + avatar data for one faction. Minion rosters are NOT listed here —
## they are derived at runtime from the MinionCatalog by reading each scene's
## MinionType.faction export. Authored as .tres files under res://data/factions/.

@export var id: GameConstants.Faction = GameConstants.Faction.NEUTRAL
@export var display_name: String
@export var color: Color = Color.WHITE
@export var avatar_abilities: Array[AvatarAbility] = []

## Optional: swap in faction-specific Avatar art/abilities on activation.
## Empty means "use the default Paladin scene".
@export var default_avatar_scene: PackedScene

# --- Tier E: Avatar combat stats ---
# Read by AvatarActor._apply_faction_combat_stats() on claim. None of these
# touch the rollback synchronizer — they configure the actor's combat numbers
# at activation time and stay constant through the life of the claim. (Switching
# faction mid-claim is not a supported flow; the avatar is recalled on faction
# change.)

@export_group("Avatar Combat Stats")
## Avatar HP cap when this faction is the controller. Overrides the default
## `Actor.get_max_hp()` return (100). Authoring guidance:
## - Demonic: 120 (the brawler)
## - Undeath: 100 (median attrition)
## - Nature/Fey: 80 (the evader)
## - Eldritch: 80 (the caster)
@export var avatar_hp: int = 100

## Base damage per-swing — multiplied by AttackData.damage_mult, then by ability
## buffs etc. Overrides `Actor.get_attack_damage()` return (25). Authoring:
## - Demonic: 32 (highest)
## - Undeath: 25 (baseline)
## - Nature/Fey: 22
## - Eldritch: 18 (weakest melee, leans on abilities)
@export var avatar_base_damage: int = 25

## Multiplier applied to AnimationPlayer.speed_scale during attack states
## (light / heavy / charge / sprint / jump). 1.0 = no change. Authoring:
## - Nature/Fey: 1.20 (faster, lighter swings)
## - Demonic: 0.95 (slightly heavier)
## - Others: 1.0
@export var attack_speed_mult: float = 1.0

## Override on RollState.ROLL_DISTANCE-implied distance budget. The roll
## moves at ROLL_SPEED for ROLL_DURATION_TICKS, so distance ≈ speed × duration.
## We don't expose ROLL_SPEED here; we multiply the duration in _apply by
## (this / default_distance). Net effect: longer-rolling factions cover more
## ground per dodge. Default = 6.0 m (ROLL_SPEED 8.0 × 12 ticks @ 30Hz × 0.0333s
## ≈ 3.2 m * 2 historic factor). Authored values:
## - Nature/Fey: 8.0 (mobility)
## - Others: 6.0 (baseline)
@export var roll_distance: float = 6.0

## Override on RollState.ROLL_DURATION_TICKS i-frame ticks. The full roll is
## stagger_immune. Authoring:
## - Nature/Fey: 16 (~0.53s i-frames; the evader)
## - Others: 12 (baseline ~0.4s)
@export var roll_iframe_ticks: int = 12

## Override on `Actor.max_posture` (Tier C). Higher = takes more pressure to
## break. Authoring:
## - Demonic: 130 (built like a tank)
## - Undeath: 100
## - Nature/Fey: 90
## - Eldritch: 90
@export var max_posture: int = 100

## Faction passive resource — see scripts/faction_passive.gd. May be null
## (NEUTRAL has none). Resolved at activate time and cached on the actor as
## `actor._faction_passive`.
@export var passive: FactionPassive

# --- Tier E: Asset library ---

@export_group("Asset Library")
## Animation library prefix the avatar reads its clips from. Convention is
## `<library>/<clip>` (e.g. "demonic-male/Attack"). When empty, the actor
## scene's configured per-state `animation_name` carries through unchanged
## (current behavior). Set this when shipping per-faction skins/animations.
##
## Ties into `docs/technical/3d-asset-pipeline.md` — each faction's avatar
## is an inherited scene of the base avatar with this library swapped in.
@export var animation_library_name: String = ""
