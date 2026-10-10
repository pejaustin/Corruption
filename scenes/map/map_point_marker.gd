class_name MapPointMarker extends Interactable

## A known map point drawn on the tower floor. E on it while making an order
## makes it the destination; E on your own tower's point starts an order for a
## courier alone (GDD Q2: couriers can be sent to "go and come back").
## PLACEHOLDER: art — an ink disc with the point's name written beside it.

var floor_map: MapFloor
var point: MapPoint

@onready var _disc: MeshInstance3D = %Disc
@onready var _label: Label3D = %Label

static func create(scene: PackedScene, map: MapFloor, p: MapPoint) -> MapPointMarker:
	## One marker per known map point: an instance of the authored scene.
	var m := scene.instantiate() as MapPointMarker
	m.floor_map = map
	m.point = p
	m.name = "Point_%s" % p.point_id
	return m

func _interactable_ready() -> void:
	(_disc.material_override as StandardMaterial3D).albedo_color = _kind_color(point.kind)
	_label.text = point.get_label()

static func _kind_color(kind: int) -> Color:
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

func _is_home() -> bool:
	var t := floor_map.get_tower()
	return point.kind == MapPoint.Kind.TOWER and t != null and point.tower_slot == t.slot_index

func get_prompt_text() -> String:
	# PLACEHOLDER: wording.
	if floor_map == null or not floor_map.is_active_for_local_peer():
		return ""
	var player := floor_map.local_player()
	if player and player.is_holding_order():
		return "%s (take your orders to the advisor)" % point.get_label()
	if floor_map.authoring:
		if _is_home() and floor_map.selected_groups.is_empty() and floor_map.path_points.is_empty():
			return "%s — walk the route, then E on the destination" % point.get_label()
		return "[E] Destination: %s" % point.get_label()
	if _is_home():
		return "[E] Send a courier from here — %s" % point.get_label()
	return point.get_label()

func get_prompt_color() -> Color:
	return Color(0.95, 0.9, 0.7)

func _on_interact() -> void:
	if floor_map == null or not floor_map.is_active_for_local_peer():
		return
	var player := floor_map.local_player()
	if player and player.is_holding_order():
		return
	if floor_map.authoring:
		if _is_home() and floor_map.selected_groups.is_empty() and floor_map.path_points.is_empty():
			return
		floor_map.finish_at(point)
	elif _is_home():
		floor_map.start_courier_route()
