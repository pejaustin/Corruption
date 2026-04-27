class_name AstralProjection extends Control

## Automatic spectator overlay during boss fights.
## When the Avatar engages the Guardian Boss, all Overlords
## see a SubViewport of the fight. They can still heckle via Mirror.
## Similar to the Palantir but triggered automatically.

@export var viewport_container: SubViewportContainer
@export var sub_viewport: SubViewport
@export var spectate_label: Label

const SPECTATE_CAMERA_OFFSET: Vector3 = Vector3(0, 8, 8)
const SPECTATE_CAMERA_LOOK_OFFSET: Vector3 = Vector3(0, 1, 0)
const SPECTATE_CAMERA_LERP_SPEED: float = 5.0

var _spectate_camera: Camera3D
var _is_spectating: bool = false
var _boss: GuardianBoss = null
var _avatar: Node
var _boss_node: Node

func _ready() -> void:
	visible = false
	if sub_viewport:
		_spectate_camera = Camera3D.new()
		_spectate_camera.name = "SpectateCamera"
		sub_viewport.add_child(_spectate_camera)
	_avatar = get_tree().current_scene.get_node_or_null("World/Avatar")
	_boss_node = get_tree().current_scene.get_node_or_null("World/GuardianBoss")

func _process(delta: float) -> void:
	if not _is_spectating:
		_check_boss_fight()
		return

	# Update spectate camera to follow the Avatar
	if _avatar and _avatar is AvatarActor and not _avatar.is_dormant and _spectate_camera:
		var target: Vector3 = _avatar.global_position + SPECTATE_CAMERA_OFFSET
		_spectate_camera.global_position = _spectate_camera.global_position.lerp(target, SPECTATE_CAMERA_LERP_SPEED * delta)
		_spectate_camera.look_at(_avatar.global_position + SPECTATE_CAMERA_LOOK_OFFSET)

	# Update label with boss HP
	if _boss and spectate_label:
		var debuff_pct = int(_boss._get_corruption_debuff() * 100)
		spectate_label.text = "BOSS FIGHT — HP: %d/%d (Corruption debuff: %d%%)" % [
			_boss.hp, _boss.max_hp_effective, debuff_pct
		]

	# Check if boss fight ended
	if not _boss or _boss.hp <= 0:
		_end_spectate()

func _check_boss_fight() -> void:
	# Only activate for non-Avatar players
	var my_id = multiplayer.get_unique_id()
	if GameState.is_avatar(my_id):
		return

	if not _boss_node or not _boss_node is GuardianBoss:
		return

	if not _avatar or not _avatar is AvatarActor or _avatar.is_dormant:
		return

	# Check if Avatar is close to the boss (fight has started)
	if _avatar.global_position.distance_to(_boss_node.global_position) < 15.0:
		_start_spectate(_boss_node)

func _start_spectate(boss: GuardianBoss) -> void:
	_boss = boss
	_is_spectating = true
	visible = true
	if _spectate_camera:
		_spectate_camera.current = false  # Don't take over main camera

func _end_spectate() -> void:
	_is_spectating = false
	_boss = null
	visible = false
