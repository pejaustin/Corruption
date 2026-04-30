class_name TelegraphArc extends Node3D

## Tier G — boss-attack telegraph cosmetic.
##
## A flat ground-aligned indicator that fades in over the attack's windup, then
## flashes red at the active frame and self-frees on cancel or after the
## active window. Purely cosmetic — never gates damage. Local-only feedback,
## skipped during rollback resimulation.
##
## Boss state authoring:
##   var arc := TELEGRAPH_SCENE.instantiate() as TelegraphArc
##   get_tree().current_scene.add_child(arc)
##   arc.setup(active_pos, facing_dir, windup_seconds)
##   # ... at active frame:
##   arc.cancel()
##
## The `width` and `range` exports drive the placeholder PlaneMesh; replace
## the mesh / material with an authored VFX scene without touching the script
## API.

const FADE_IN_BIAS: float = 0.6  # how much of the windup is fade-in
const FLASH_DURATION: float = 0.18  # post-active-frame red flash

@export var width: float = 4.0
@export var range_: float = 5.0

var _windup_duration: float = 1.0
var _elapsed: float = 0.0
var _active: bool = true

@onready var _mesh: MeshInstance3D = %Mesh

func setup(world_pos: Vector3, facing: Vector3, windup_sec: float) -> void:
	_windup_duration = max(0.05, windup_sec)
	global_position = world_pos
	if facing.length() > 0.01:
		# Flatten facing onto XZ and orient the arc so its long axis points away
		# from the boss. The PlaneMesh is XZ-aligned by default.
		var f: Vector3 = facing
		f.y = 0.0
		f = f.normalized()
		look_at(world_pos + f, Vector3.UP)

func cancel() -> void:
	if not _active:
		return
	_active = false
	_start_flash()

func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	if _mesh == null:
		return
	var fade_in_end: float = _windup_duration * FADE_IN_BIAS
	var t: float = clamp(_elapsed / max(fade_in_end, 0.001), 0.0, 1.0)
	# Lerp from translucent yellow to opaque red as the windup completes.
	var col: Color = Color(1.0, 0.6, 0.1, 0.15).lerp(Color(1.0, 0.1, 0.1, 0.65), t)
	_apply_color(col)
	if _elapsed >= _windup_duration:
		# Reached active frame without explicit cancel; flash and self-free.
		cancel()

func _start_flash() -> void:
	_apply_color(Color(1.0, 0.95, 0.2, 0.85))
	var t: SceneTreeTimer = get_tree().create_timer(FLASH_DURATION)
	t.timeout.connect(queue_free)

func _apply_color(c: Color) -> void:
	if _mesh == null:
		return
	var mat: StandardMaterial3D = _mesh.get_active_material(0) as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = c
