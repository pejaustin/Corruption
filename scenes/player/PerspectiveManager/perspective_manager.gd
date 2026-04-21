class_name PerspectiveManager
extends Node3D

@export var current_perspective : PerspectiveResource

@export var player : CharacterBody3D

@export var bullet_raycast : RayCast3D


@export var view_model_container : Node3D
@export var world_model_container : Node3D

var current_view_model : Node3D
var current_world_model : Node3D

func update_model() -> void:
	if current_perspective != null:
		if view_model_container and current_perspective.view_model:
			current_view_model = current_perspective.view_model.instantiate()
			view_model_container.add_child(current_view_model)
			current_view_model.rotation = current_perspective.view_model_rot
			current_view_model.scale = current_perspective.view_model_scale
			current_view_model.position = current_perspective.view_model_pos
			current_view_model.start_animations()
		if world_model_container and current_perspective.world_model:
			current_world_model = current_perspective.world_model.instantiate()
			world_model_container.add_child(current_world_model)
			current_world_model.start_animations()

func _ready() -> void:
	update_model()
