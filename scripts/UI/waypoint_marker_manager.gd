class_name WaypointMarkerManager extends Node2D

const MARKER_SCENE := preload("res://prefabs/ui/waypoint_marker.tscn")
const POSITION_EPSILON := 12.0

var _markers: Array[Node2D] = []

func clear_all_markers() -> void:
	for marker in _markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_markers.clear()

func refresh_for_selection() -> void:
	clear_all_markers()
	if not Handlers.UnitSelectionHandler:
		return
	if not is_instance_valid(multiplayer):
		return
	
	var local_id := multiplayer.get_unique_id()
	var seen_positions: Array[Vector2] = []
	var marker_index := 0
	
	for unit in Handlers.UnitSelectionHandler.selected_units:
		if not is_instance_valid(unit):
			continue
		if unit.owner_id != local_id:
			continue
		if not unit.has_method("get_order_queue_snapshot"):
			continue
		
		for entry in unit.get_order_queue_snapshot():
			if not entry is Dictionary or not entry.has("position"):
				continue
			var pos: Vector2 = entry.position
			if _is_duplicate_position(pos, seen_positions):
				continue
			seen_positions.append(pos)
			marker_index += 1
			_spawn_marker(pos, marker_index)

func _is_duplicate_position(pos: Vector2, seen_positions: Array[Vector2]) -> bool:
	for seen in seen_positions:
		if seen.distance_to(pos) < POSITION_EPSILON:
			return true
	return false

func _spawn_marker(world_position: Vector2, index: int) -> void:
	var marker: Node2D = MARKER_SCENE.instantiate()
	marker.global_position = world_position
	add_child(marker)
	if marker.has_method("set_index"):
		marker.set_index(index)
	_markers.append(marker)
