class_name UnitTrackVisualService
extends Node

## Глобальная отрисовка следов: не зависит от видимости юнита у клиента.

var _renderers: Dictionary = {}


func _ready() -> void:
	Handlers.UnitTrackVisualHandler = self


func _exit_tree() -> void:
	Handlers.UnitTrackVisualHandler = null


func broadcast_sample(
		unit_uid: String,
		from_pos: Vector2,
		to_pos: Vector2,
		settings: UnitTrackSettings
	) -> void:
	if unit_uid == "":
		return
	if not multiplayer.is_server():
		return
	# Dedicated headless: только RPC клиентам. Host (с дисплеем) рисует локально как клиент.
	if DisplayServer.get_name() != "headless":
		_add_sample_local(unit_uid, from_pos, to_pos, settings)
	rpc(
		"receive_track_sample",
		unit_uid,
		from_pos.x,
		from_pos.y,
		to_pos.x,
		to_pos.y,
		settings.line_width,
		settings.lifetime_sec,
		settings.fade_window_sec,
		settings.line_half_spacing,
		settings.track_color,
		settings.dissolve_color
	)


func stop_unit_tracks(unit_uid: String) -> void:
	if unit_uid == "":
		return
	if _renderers.has(unit_uid):
		var renderer: Variant = _renderers[unit_uid]
		if renderer is UnitTrackRenderer and is_instance_valid(renderer):
			(renderer as UnitTrackRenderer).stop_sampling()
	_renderers.erase(unit_uid)


@rpc("authority", "call_remote", "unreliable")
func receive_track_sample(
		unit_uid: String,
		from_x: float,
		from_y: float,
		to_x: float,
		to_y: float,
		line_width: float,
		lifetime_sec: float,
		fade_window_sec: float,
		line_half_spacing: float,
		track_color: Color,
		dissolve_color: Color
	) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var settings := UnitTrackSettings.new()
	settings.line_width = line_width
	settings.lifetime_sec = lifetime_sec
	settings.fade_window_sec = fade_window_sec
	settings.line_half_spacing = line_half_spacing
	settings.track_color = track_color
	settings.dissolve_color = dissolve_color
	_add_sample_local(
		unit_uid,
		Vector2(from_x, from_y),
		Vector2(to_x, to_y),
		settings
	)


func _add_sample_local(
		unit_uid: String,
		from_pos: Vector2,
		to_pos: Vector2,
		settings: UnitTrackSettings
	) -> void:
	var renderer := _get_or_create_renderer(unit_uid)
	renderer.apply_settings(settings)
	renderer.add_movement_sample(from_pos, to_pos, settings)


func _get_or_create_renderer(unit_uid: String) -> UnitTrackRenderer:
	if _renderers.has(unit_uid):
		var existing: Variant = _renderers[unit_uid]
		if existing is UnitTrackRenderer and is_instance_valid(existing):
			return existing as UnitTrackRenderer

	var track_layer := _find_track_layer()
	if track_layer == null:
		push_warning("UnitTrackVisualService: TrackLayer not found")
		var fallback := UnitTrackRenderer.new()
		fallback.name = "Tracks_%s" % unit_uid
		add_child(fallback)
		_renderers[unit_uid] = fallback
		return fallback

	var renderer := UnitTrackRenderer.new()
	renderer.name = "Tracks_%s" % unit_uid
	track_layer.add_child(renderer)
	_renderers[unit_uid] = renderer
	return renderer


func _find_track_layer() -> Node2D:
	if Handlers.GameHandler:
		var map_node: Node = Handlers.GameHandler.get_node_or_null("%Map")
		if map_node:
			var layer := map_node.find_child("TrackLayer", true, false)
			if layer is Node2D:
				return layer as Node2D
	return get_tree().root.find_child("TrackLayer", true, false) as Node2D
