class_name CombatBoxDebug extends Object

## Shared debug-visual builder for AttackHitbox and Hurtbox. Each component
## calls build_visuals() once at _ready() to spawn a child MeshInstance3D
## per CollisionShape3D, then toggles visibility via
## DebugManager.combat_boxes_toggled.
##
## Meshes are added as children of their CollisionShape3D so they follow
## any parent transform (including bone-attached hitboxes) automatically.

const DEBUG_VISUAL_NAME: StringName = &"_DebugVisual"
const META_ACTIVE_COLOR: StringName = &"_debug_active_color"

## Alpha applied on top of the caller's color when the shape is enabled
## (actively registering / presenting hits). Bright, opaque enough to read.
const ACTIVE_ALPHA: float = 0.6
## Alpha used when the shape is disabled — still visible for placement, but
## clearly "off". Combined with the effect below this is unmistakable.
const INACTIVE_ALPHA: float = 0.08

static func build_visuals(owner_area: Area3D, color: Color) -> Array[MeshInstance3D]:
	var visuals: Array[MeshInstance3D] = []
	for c in owner_area.get_children():
		if c is CollisionShape3D:
			var shape_node := c as CollisionShape3D
			if shape_node.get_node_or_null(NodePath(DEBUG_VISUAL_NAME)):
				continue
			var visual := _build_visual(shape_node, color)
			if visual:
				shape_node.add_child(visual)
				visuals.append(visual)
	return visuals

static func set_visibility(visuals: Array[MeshInstance3D], is_visible: bool) -> void:
	for v in visuals:
		if is_instance_valid(v):
			v.visible = is_visible
	if is_visible:
		refresh_active_state(visuals)

## Recolor each visual based on its parent CollisionShape3D's `disabled`
## flag: enabled shapes glow at full alpha, disabled shapes fade out.
## Call after toggling shapes in AttackHitbox / Hurtbox enable/disable.
static func refresh_active_state(visuals: Array[MeshInstance3D]) -> void:
	for v in visuals:
		if not is_instance_valid(v):
			continue
		var shape := v.get_parent() as CollisionShape3D
		if shape == null:
			continue
		var mat := v.material_override as StandardMaterial3D
		if mat == null:
			continue
		var base: Color = v.get_meta(META_ACTIVE_COLOR, mat.albedo_color)
		var tinted := base
		tinted.a = INACTIVE_ALPHA if shape.disabled else ACTIVE_ALPHA
		mat.albedo_color = tinted

static func _build_visual(shape_node: CollisionShape3D, color: Color) -> MeshInstance3D:
	var mesh := _shape_to_mesh(shape_node.shape)
	if mesh == null:
		return null
	var inst := MeshInstance3D.new()
	inst.name = DEBUG_VISUAL_NAME
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	inst.material_override = mat
	inst.visible = false
	inst.set_meta(META_ACTIVE_COLOR, color)
	return inst

static func _shape_to_mesh(shape: Shape3D) -> Mesh:
	if shape is SphereShape3D:
		var s := shape as SphereShape3D
		var m := SphereMesh.new()
		m.radius = s.radius
		m.height = s.radius * 2.0
		return m
	if shape is BoxShape3D:
		var b := shape as BoxShape3D
		var m := BoxMesh.new()
		m.size = b.size
		return m
	if shape is CapsuleShape3D:
		var c := shape as CapsuleShape3D
		var m := CapsuleMesh.new()
		m.radius = c.radius
		m.height = c.height
		return m
	if shape is CylinderShape3D:
		var cy := shape as CylinderShape3D
		var m := CylinderMesh.new()
		m.top_radius = cy.radius
		m.bottom_radius = cy.radius
		m.height = cy.height
		return m
	return null
