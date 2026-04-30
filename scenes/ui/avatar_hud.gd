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
@onready var _capture_progress: CaptureProgress = %CaptureProgress
@onready var _posture_bar: PostureBar = %PostureBar

var _actor: AvatarActor = null
var _ability_cross_initialized: bool = false

func _ready() -> void:
	_actor = get_parent() as AvatarActor
	if _actor == null:
		queue_free()
		return
	_actor.hp_changed.connect(_on_hp_changed)
	_health_bar.max_value = _actor.get_max_hp()
	_health_bar.value = _actor.hp
	_damage_vignette.bind(_actor)
	_capture_progress.bind(_actor)
	# Posture bar binds explicitly here so it doesn't have to walk the parent
	# chain looking for an Actor — saves one process tick of "no target".
	if _posture_bar:
		_posture_bar.target_actor = _actor
	GameState.avatar_changed.connect(_on_avatar_changed)
	_try_init_ability_cross()
	_refresh()

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
