class_name MapPiece extends Interactable

## A chess piece on the map floor: one of your groups (or the Paladin, if you
## hold him) where the last report put it, or enemy units your people saw.
## E selects your own pieces for an order; left mouse picks any piece up to
## move it by hand (GDD Q10). Every own piece stays selectable whatever its
## state. `belief`: &"confirmed" (normal), &"expected" (an order was sent; the
## piece stands where it should be by now; drawn translucent) or &"missing"
## (information contradicted the expectation; a "?" and grey). Age alone only
## makes a piece "old news" in its prompt (Austin, 2026-10-09).
## PLACEHOLDER: the expected and missing looks.
## PLACEHOLDER: art — a primitive chess piece tinted by owner.

var floor_map: MapFloor
var key: int = 0
var owner_peer_id: int = -1
var group_id: int = 0
var count: int = 1
var stale: bool = false
var belief: StringName = &"confirmed"
var selected: bool = false
var status: StringName = &""
var is_avatar: bool = false

@onready var _base: MeshInstance3D = %Base
@onready var _label: Label3D = %Label
@onready var _mat: StandardMaterial3D = _base.material_override as StandardMaterial3D

static func create(scene: PackedScene, map: MapFloor, piece_key: int, owner: int, avatar: bool) -> MapPiece:
	## One piece per reported group: an instance of the authored scene.
	var p := scene.instantiate() as MapPiece
	p.floor_map = map
	p.key = piece_key
	p.owner_peer_id = owner
	p.is_avatar = avatar
	p.name = "Piece_%d" % absi(piece_key)
	return p

func is_mine() -> bool:
	return owner_peer_id == multiplayer.get_unique_id() and group_id != 0

func refresh() -> void:
	var color := GameState.get_player_color(owner_peer_id)
	if selected:
		color = color.lightened(0.5)
	if belief == &"missing":
		color = color.lerp(Color(0.5, 0.5, 0.5), 0.7)
	elif belief == &"expected":
		color.a = 0.5
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if belief == &"expected" else BaseMaterial3D.TRANSPARENCY_DISABLED
	_mat.albedo_color = color
	_mat.emission_enabled = selected
	_mat.emission = color
	var text := ("PALADIN" if is_avatar else str(count))
	if belief == &"missing":
		text += " ?"
	_label.text = text

func get_prompt_text() -> String:
	# PLACEHOLDER: wording.
	if floor_map == null or not floor_map.is_active_for_local_peer():
		return ""
	if floor_map.carried_piece == key:
		return "[LMB] put it down"
	var who := "the Paladin" if is_avatar else ("your group %d" % group_id if is_mine() else "%d of %s" % [count, GameState.get_player_name(owner_peer_id)])
	var lines := "%s%s%s" % [who, (" (%s)" % status) if status != &"" and is_mine() else "", _belief_note()]
	if is_mine():
		var player := floor_map.local_player()
		if player and player.is_holding_order():
			return lines
		return "%s\n[E] %s   [LMB] move by hand" % [lines, "deselect" if selected else "select"]
	return "%s\n[LMB] move by hand" % lines

func _belief_note() -> String:
	# PLACEHOLDER: wording.
	match belief:
		&"expected":
			return " (should be here by now)"
		&"missing":
			return " (missing: nobody has found them)"
	return " — old news" if stale else ""

func get_prompt_color() -> Color:
	return Color(1, 1, 0.6) if is_mine() else Color(0.9, 0.8, 0.8)

func _on_interact() -> void:
	if not is_mine():
		return
	var player := floor_map.local_player()
	if player and player.is_holding_order():
		return
	floor_map.toggle_group(group_id)

func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if not _is_focused or floor_map == null:
		return
	if event.is_action_pressed("primary_ability") and floor_map.carried_piece == 0:
		floor_map.pick_up(key)
		get_viewport().set_input_as_handled()
