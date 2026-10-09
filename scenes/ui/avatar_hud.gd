class_name AvatarHUD
extends CanvasLayer

## Per-local-peer HUD shown while controlling the Avatar. Attached as a child
## of avatar_actor.tscn. The avatar is shared across peers and its
## controlling_peer_id changes over time, so the HUD stays alive and toggles
## visibility on GameState.avatar_changed — never queue_freed mid-session.
##
## Widgets are passive views — they subscribe to gameplay signals and render.
## They never write gameplay state.

@onready var _interaction_prompt: RichTextLabel = %InteractionPrompt
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _ability_cross: AbilityCross = %AbilityCross
@onready var _damage_vignette: DamageVignette = %DamageVignette

## PLACEHOLDER: wording — label on the hold bar.
const HOLD_LABEL: String = "Hold"
const HOLD_BAR_SIZE: Vector2 = Vector2(256, 10)
const HOLD_BAR_OFFSET: Vector2 = Vector2(24, -76)
const HOLD_LABEL_OFFSET: Vector2 = Vector2(0, -26)

var _actor: AvatarActor = null
var _ability_cross_initialized: bool = false
## Your hold on him (PaladinHold.hold), above the health bar (GDD §8 Q15).
var _hold_bar: ProgressBar

func _ready() -> void:
	_actor = get_parent() as AvatarActor
	if _actor == null:
		queue_free()
		return
	_actor.hp_changed.connect(_on_hp_changed)
	_health_bar.max_value = _actor.get_max_hp()
	_health_bar.value = _actor.hp
	_damage_vignette.bind(_actor)
	_build_hold_bar()
	GameState.avatar_changed.connect(_on_avatar_changed)
	_try_init_ability_cross()
	_refresh()

func _process(_delta: float) -> void:
	if visible and _actor.hold:
		_hold_bar.value = _actor.hold.hold

func _on_avatar_changed(_old: int, _new: int) -> void:
	_try_init_ability_cross()
	_refresh()

func _try_init_ability_cross() -> void:
	if _ability_cross_initialized:
		return
	if _actor.abilities == null:
		return
	_ability_cross.setup(_actor.abilities)
	_ability_cross_initialized = true

func _refresh() -> void:
	var is_my_avatar := _actor.controlling_peer_id == multiplayer.get_unique_id()
	visible = is_my_avatar
	if is_my_avatar:
		InteractionUI.register_prompt(_interaction_prompt)

func _exit_tree() -> void:
	if _interaction_prompt and is_instance_valid(_interaction_prompt):
		InteractionUI.deregister_prompt(_interaction_prompt)

func _on_hp_changed(new_hp: int) -> void:
	_health_bar.value = new_hp

func _build_hold_bar() -> void:
	_hold_bar = ProgressBar.new()
	_hold_bar.name = "HoldBar"
	_hold_bar.min_value = 0.0
	_hold_bar.max_value = 1.0
	_hold_bar.step = 0.001
	_hold_bar.show_percentage = false
	_hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_bar.anchor_top = 1.0
	_hold_bar.anchor_bottom = 1.0
	_hold_bar.offset_left = HOLD_BAR_OFFSET.x
	_hold_bar.offset_top = HOLD_BAR_OFFSET.y
	_hold_bar.offset_right = HOLD_BAR_OFFSET.x + HOLD_BAR_SIZE.x
	_hold_bar.offset_bottom = HOLD_BAR_OFFSET.y + HOLD_BAR_SIZE.y
	add_child(_hold_bar)
	var label := Label.new()
	label.name = "HoldLabel"
	label.text = HOLD_LABEL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = HOLD_LABEL_OFFSET
	_hold_bar.add_child(label)
