@tool
class_name MapPointMarker extends Interactable

## A map point drawn on the tower floor. Authored in map_floor.tscn under Markers, one per world MapPoint (MapFloor's
## "Copy map points and links" button adds the missing ones); move it, rename its label or recolour it there by hand.
## In play it shows only once its owner knows the point, lights up when an order's route passes it, and E on it picks
## the destination; E on your own tower's point starts an order for a courier alone (GDD Q2: couriers can be sent to
## "go and come back").
## PLACEHOLDER: art — an ink disc with the point's name written beside it, a ring when on the route.

## The MapPoint (World/MapPoints) this marker stands for.
@export var point_id: StringName
@export var label_text: String = "":
	set(value):
		label_text = value
		_apply_look()
@export var disc_color: Color = Color(0.25, 0.2, 0.15):
	set(value):
		disc_color = value
		_apply_look()

var floor_map: MapFloor
## The world's MapPoint, found by id once the world is up (null until then, or when it no longer exists).
var point: MapPoint
var highlighted: bool = false

@onready var _disc: MeshInstance3D = %Disc
@onready var _label: Label3D = %Label
@onready var _highlight: Node3D = %Highlight
@onready var _shape: CollisionShape3D = %Shape

func _interactable_ready() -> void:
	_apply_look()
	_highlight.visible = false

func _apply_look() -> void:
	if not is_node_ready():
		return
	_label.text = label_text
	(_disc.material_override as StandardMaterial3D).albedo_color = disc_color

static func kind_color(kind: int) -> Color:
	## The disc colour a copied marker starts with, by the point's kind.
	## PLACEHOLDER: art direction — ink colours per kind.
	match kind:
		MapPoint.Kind.SITE:
			return Color(0.35, 0.1, 0.35)
		MapPoint.Kind.TOWER:
			return Color(0.1, 0.1, 0.1)
		MapPoint.Kind.CITY:
			return Color(0.6, 0.5, 0.1)
		MapPoint.Kind.SETTLEMENT:
			return Color(0.45, 0.3, 0.15)
		MapPoint.Kind.RESOURCE:
			return Color(0.2, 0.35, 0.2)
		MapPoint.Kind.CROSSING:
			return Color(0.15, 0.25, 0.45)
	return Color(0.25, 0.2, 0.15)

func set_shown(show: bool) -> void:
	## Unknown points are neither drawn nor aimed at.
	if visible != show:
		visible = show
	if _shape.disabled == show:
		_shape.set_deferred(&"disabled", not show)

func set_highlighted(on: bool) -> void:
	highlighted = on
	_highlight.visible = on

func set_focused(focused: bool, who: Node3D = null) -> void:
	if floor_map and focused != _is_focused:
		floor_map.preview_destination(self if focused else null)
	super(focused, who)

func _is_home() -> bool:
	var t := floor_map.get_tower()
	return point != null and point.kind == MapPoint.Kind.TOWER and t != null and point.tower_slot == t.slot_index

func get_prompt_text() -> String:
	# PLACEHOLDER: wording.
	if floor_map == null or point == null or not floor_map.is_active_for_local_peer():
		return ""
	var player := floor_map.local_player()
	if player and player.is_holding_order():
		return "%s (take your orders to the advisor)" % point.get_label()
	if floor_map.authoring:
		if _is_home() and floor_map.selected_groups.is_empty():
			return "%s — now E on where the courier should go" % point.get_label()
		if floor_map.way_to(point).is_empty():
			return "%s — no way you know leads there" % point.get_label()
		return "[E] Destination: %s" % point.get_label()
	if _is_home():
		return "[E] Send a courier from here — %s" % point.get_label()
	return point.get_label()

func get_prompt_color() -> Color:
	return Color(0.95, 0.9, 0.7)

func _on_interact() -> void:
	if floor_map == null or point == null or not floor_map.is_active_for_local_peer():
		return
	var player := floor_map.local_player()
	if player and player.is_holding_order():
		return
	if floor_map.authoring:
		if _is_home() and floor_map.selected_groups.is_empty():
			return
		floor_map.finish_at(point)
	elif _is_home():
		floor_map.start_courier_route()
