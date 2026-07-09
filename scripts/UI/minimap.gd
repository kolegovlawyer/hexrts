class_name MiniMap extends PanelContainer

const MARKER_TEX_SIZE := 16
const UPDATE_INTERVAL := 0.1
const BACKGROUND_COLOR := Color(0.12, 0.12, 0.16, 1.0)
const HEX_FILL_ALPHA := 0.38
const HEX_RADIUS_TILE_FRACTION := 0.32 * 1.8
const UNIT_MARKER_TILE_FRACTION := 0.22
const NEUTRAL_HEX_COLOR := Color(0.45, 0.45, 0.5, HEX_FILL_ALPHA)

@onready var _aspect_ratio: AspectRatioContainer = $AspectRatio
@onready var _sub_viewport_container: SubViewportContainer = $AspectRatio/SubViewportContainer
@onready var _sub_viewport: SubViewport = $AspectRatio/SubViewportContainer/SubViewport
@onready var _mini_camera: Camera2D = $AspectRatio/SubViewportContainer/SubViewport/Camera2D

var _view_rect_overlay: _ViewRectOverlay = null

var _map_bounds: Rect2 = Rect2()
var _main_camera: Camera2D = null
var _world: Node2D = null

var _mini_map_root: Node2D = null
var _hex_layer: _MiniMapHexLayer = null
var _unit_markers_root: Node2D = null
var _marker_pool: Array[Sprite2D] = []
var _marker_texture: Texture2D = null
var _unit_marker_world_size: float = 48.0

var _update_timer: float = 0.0
var _camera_connected: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _sub_viewport_container:
		_sub_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
		_sub_viewport_container.gui_input.connect(_on_sub_viewport_gui_input)
		_sub_viewport_container.resized.connect(_on_map_area_resized)
	_setup_view_rect_overlay()
	_marker_texture = _create_marker_texture()


func _setup_view_rect_overlay() -> void:
	if _view_rect_overlay and is_instance_valid(_view_rect_overlay):
		_view_rect_overlay.queue_free()
	_view_rect_overlay = _ViewRectOverlay.new()
	_view_rect_overlay.name = "ViewRect"
	_view_rect_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_rect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sub_viewport_container.add_child(_view_rect_overlay)


func setup(world: Node2D, main_camera: Camera2D) -> void:
	_world = world
	_bind_main_camera(main_camera)
	if _world == null:
		return
	_clear_mini_map_world()
	if not _build_map_bounds():
		return
	_apply_aspect_ratio()
	_build_mini_map_world()
	_update_timer = 0.0
	call_deferred("_configure_sub_viewport")
	_refresh_unit_markers()
	_refresh_hex_layer()
	refresh_view_rect()
	call_deferred("_refresh_unit_markers")
	call_deferred("_refresh_hex_layer")


func notify_map_data_ready() -> void:
	_refresh_hex_layer()
	_refresh_unit_markers()
	refresh_view_rect()


func refresh_view_rect() -> void:
	if _view_rect_overlay == null:
		return
	if _main_camera == null or not _main_camera.has_method("get_visible_world_rect"):
		_view_rect_overlay.view_rect = Rect2()
		_view_rect_overlay.queue_redraw()
		return
	var visible_world: Rect2 = _main_camera.get_visible_world_rect()
	var top_left := world_to_minimap(visible_world.position)
	var bottom_right := world_to_minimap(visible_world.position + visible_world.size)
	_view_rect_overlay.view_rect = Rect2(top_left, bottom_right - top_left)
	_view_rect_overlay.queue_redraw()


func world_to_minimap(world_pos: Vector2) -> Vector2:
	var area := _get_map_area_size()
	if _map_bounds.size.x <= 0.0 or _map_bounds.size.y <= 0.0 or area.x <= 0.0 or area.y <= 0.0:
		return Vector2.ZERO
	var t := (world_pos - _map_bounds.position) / _map_bounds.size
	return Vector2(clampf(t.x, 0.0, 1.0), clampf(t.y, 0.0, 1.0)) * area


func minimap_to_world(minimap_pos: Vector2) -> Vector2:
	var area := _get_map_area_size()
	if _map_bounds.size.x <= 0.0 or _map_bounds.size.y <= 0.0 or area.x <= 0.0 or area.y <= 0.0:
		return _map_bounds.get_center()
	var t := minimap_pos / area
	return _map_bounds.position + t * _map_bounds.size


func _process(delta: float) -> void:
	if _world == null:
		return
	_refresh_unit_markers()
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_refresh_hex_layer()
	elif _hex_layer != null and _hex_layer.entries.is_empty() \
			and Handlers.GameHandler != null \
			and not Handlers.GameHandler.hexes_dict.is_empty():
		_refresh_hex_layer()
	if _main_camera != null:
		refresh_view_rect()


func _on_map_area_resized() -> void:
	call_deferred("_configure_sub_viewport")
	call_deferred("refresh_view_rect")


func _bind_main_camera(main_camera: Camera2D) -> void:
	if _main_camera != null and _camera_connected:
		if _main_camera.camera_moved.is_connected(_on_main_camera_changed):
			_main_camera.camera_moved.disconnect(_on_main_camera_changed)
		if _main_camera.camera_zoomed.is_connected(_on_main_camera_changed):
			_main_camera.camera_zoomed.disconnect(_on_main_camera_changed)
		_camera_connected = false
	_main_camera = main_camera
	if _main_camera == null:
		return
	if not _main_camera.camera_moved.is_connected(_on_main_camera_changed):
		_main_camera.camera_moved.connect(_on_main_camera_changed)
	if not _main_camera.camera_zoomed.is_connected(_on_main_camera_changed):
		_main_camera.camera_zoomed.connect(_on_main_camera_changed)
	_camera_connected = true


func _on_main_camera_changed() -> void:
	refresh_view_rect()


func _build_map_bounds() -> bool:
	var top_left_corner := _world.get_node_or_null("CameraCornerTopLeft") as Node2D
	var bottom_right_corner := _world.get_node_or_null("CameraCornerBottomRight") as Node2D
	if top_left_corner == null or bottom_right_corner == null:
		return false
	var min_corner := top_left_corner.position
	var max_corner := bottom_right_corner.position
	_map_bounds = Rect2(min_corner, max_corner - min_corner)
	return _map_bounds.size.x > 0.0 and _map_bounds.size.y > 0.0


func _apply_aspect_ratio() -> void:
	if _aspect_ratio == null:
		return
	_aspect_ratio.ratio = _map_bounds.size.x / _map_bounds.size.y
	_aspect_ratio.stretch_mode = AspectRatioContainer.STRETCH_WIDTH_CONTROLS_HEIGHT


func _configure_sub_viewport() -> void:
	if _sub_viewport == null or _mini_camera == null:
		return
	if _map_bounds.size.x <= 0.0 or _map_bounds.size.y <= 0.0:
		return
	var area := _get_map_area_size()
	if area.x <= 1.0 or area.y <= 1.0:
		return
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	var zoom_fit := minf(area.x / _map_bounds.size.x, area.y / _map_bounds.size.y)
	if zoom_fit <= 0.0:
		return
	_mini_camera.position = _map_bounds.get_center()
	_mini_camera.zoom = Vector2(zoom_fit, zoom_fit)
	_mini_camera.position_smoothing_enabled = false
	_mini_camera.enabled = true


func _build_mini_map_world() -> void:
	_mini_map_root = Node2D.new()
	_mini_map_root.name = "MiniMapRoot"
	_sub_viewport.add_child(_mini_map_root)

	var background := _MiniMapBackground.new()
	background.bounds = _map_bounds
	background.fill_color = BACKGROUND_COLOR
	background.name = "Background"
	_mini_map_root.add_child(background)
	background.queue_redraw()

	_hex_layer = _MiniMapHexLayer.new()
	_hex_layer.name = "HexLayer"
	_hex_layer.z_index = 1
	_mini_map_root.add_child(_hex_layer)

	_unit_markers_root = Node2D.new()
	_unit_markers_root.name = "UnitMarkers"
	_unit_markers_root.z_index = 2
	_mini_map_root.add_child(_unit_markers_root)


func _clear_mini_map_world() -> void:
	if _mini_map_root and is_instance_valid(_mini_map_root):
		_mini_map_root.queue_free()
	_mini_map_root = null
	_hex_layer = null
	_unit_markers_root = null
	_marker_pool.clear()


func _refresh_unit_markers() -> void:
	if _unit_markers_root == null or Handlers.GameHandler == null:
		return
	var overlay_map: TileMapLayer = Handlers.GameHandler.overlay_map
	if overlay_map:
		_update_unit_marker_world_size(overlay_map)
	var units: Array = Handlers.GameHandler.get_all_units()
	var active_count := 0
	for unit in units:
		if not _should_show_unit(unit):
			continue
		var marker := _get_marker(active_count)
		marker.position = unit.global_position
		marker.modulate = _get_unit_dot_color(unit)
		_apply_marker_scale(marker)
		marker.visible = true
		active_count += 1
	for i in range(active_count, _marker_pool.size()):
		_marker_pool[i].visible = false


func _update_unit_marker_world_size(overlay_map: TileMapLayer) -> void:
	var tile_size := Vector2(overlay_map.tile_set.tile_size)
	_unit_marker_world_size = minf(tile_size.x, tile_size.y) * UNIT_MARKER_TILE_FRACTION


func _apply_marker_scale(marker: Sprite2D) -> void:
	var scale_factor := _unit_marker_world_size / float(MARKER_TEX_SIZE)
	marker.scale = Vector2(scale_factor, scale_factor)


func _refresh_hex_layer() -> void:
	if _hex_layer == null or Handlers.GameHandler == null:
		return
	var overlay_map: TileMapLayer = Handlers.GameHandler.overlay_map
	if overlay_map == null:
		return
	_hex_layer.hex_radius = _estimate_hex_radius(overlay_map)
	_hex_layer.entries = _collect_hex_entries(overlay_map)
	_hex_layer.queue_redraw()


func _collect_hex_entries(overlay_map: TileMapLayer) -> Array:
	var entries: Array = []
	var my_team: int = -1
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		my_team = Handlers.TeamHandler.my_profile.team
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex: Hex = Handlers.GameHandler.hexes_dict[hex_pos]
		if hex == null or hex.team_owner == -1:
			continue
		if not _should_show_hex(hex, my_team):
			continue
		var tile_size := Vector2(overlay_map.tile_set.tile_size)
		var world_center := overlay_map.to_global(
			overlay_map.map_to_local(hex_pos) + tile_size * 0.5
		)
		entries.append({
			"position": world_center,
			"color": _get_hex_fill_color(hex.team_owner, my_team),
		})
	return entries


func _should_show_hex(hex: Hex, my_team: int) -> bool:
	if hex.team_owner == -1:
		return false
	if my_team == -1:
		return true
	if hex.team_owner == my_team:
		return true
	return _has_vision_at_hex(hex.position)


func _has_vision_at_hex(hex_tile: Vector2i) -> bool:
	if Handlers.GameHandler == null or Handlers.GameHandler.overlay_map == null:
		return false
	if Handlers.TeamHandler == null or Handlers.TeamHandler.my_profile == null:
		return false
	var player_id: int = Handlers.TeamHandler.my_profile.PlayerId
	var overlay_map: TileMapLayer = Handlers.GameHandler.overlay_map
	var world_pos := overlay_map.to_global(
		overlay_map.map_to_local(hex_tile) + Vector2(overlay_map.tile_set.tile_size) * 0.5
	)
	for unit in Handlers.GameHandler.get_all_units():
		if not is_instance_valid(unit) or not (unit is BaseUnit):
			continue
		if unit.owner_id != player_id:
			continue
		var radius: float = unit.vision_radius
		if unit.global_position.distance_squared_to(world_pos) <= radius * radius:
			return true
	for fob_node in Handlers.GameHandler.fobs_dict.values():
		if not is_instance_valid(fob_node):
			continue
		if fob_node.owner_id != player_id:
			continue
		var fob_radius: float = fob_node.vision_radius
		if fob_node.global_position.distance_squared_to(world_pos) <= fob_radius * fob_radius:
			return true
	return false


func _get_hex_fill_color(team_owner: int, my_team: int) -> Color:
	if team_owner == -1:
		return NEUTRAL_HEX_COLOR
	if my_team != -1 and team_owner == my_team:
		var color: Color = GameTypes.own_color
		color.a = HEX_FILL_ALPHA
		return color
	var enemy_color: Color = GameTypes.enemy_color
	enemy_color.a = HEX_FILL_ALPHA
	return enemy_color


func _estimate_hex_radius(overlay_map: TileMapLayer) -> float:
	var tile_size := Vector2(overlay_map.tile_set.tile_size)
	return minf(tile_size.x, tile_size.y) * HEX_RADIUS_TILE_FRACTION


func _should_show_unit(unit: Node) -> bool:
	if not is_instance_valid(unit) or not (unit is BaseUnit):
		return false
	if not unit.is_inside_tree():
		return false
	var base_unit: BaseUnit = unit as BaseUnit
	if base_unit.owner_id == 1:
		return false
	return true


func _get_unit_dot_color(unit: BaseUnit) -> Color:
	if not Handlers.TeamHandler or not Handlers.TeamHandler.my_profile:
		return Color.WHITE
	if unit.owner_id == Handlers.TeamHandler.my_profile.PlayerId:
		return GameTypes.own_color
	var unit_team = unit.owner_team
	if unit_team == null:
		var player = Handlers.TeamHandler.find_player_by_id(unit.owner_id)
		if player:
			unit_team = player.team
	if unit_team != null and unit_team == Handlers.TeamHandler.my_profile.team:
		return GameTypes.own_color
	return GameTypes.enemy_color


func _get_marker(index: int) -> Sprite2D:
	while index >= _marker_pool.size():
		var marker := Sprite2D.new()
		marker.texture = _marker_texture
		marker.centered = true
		marker.scale = Vector2.ONE
		_unit_markers_root.add_child(marker)
		_marker_pool.append(marker)
	return _marker_pool[index]


func _get_map_area_size() -> Vector2:
	if _sub_viewport_container:
		var area := _sub_viewport_container.size
		if area.x > 1.0 and area.y > 1.0:
			return area
	return Vector2(256, 256)


func _on_sub_viewport_gui_input(event: InputEvent) -> void:
	if _main_camera == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local_pos := _sub_viewport_container.get_local_mouse_position()
		var world_pos := minimap_to_world(local_pos)
		if _main_camera.has_method("snap_to_world_position"):
			_main_camera.snap_to_world_position(world_pos)
		else:
			_main_camera.position = world_pos
		accept_event()


func _create_marker_texture() -> Texture2D:
	var image := Image.create(MARKER_TEX_SIZE, MARKER_TEX_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(MARKER_TEX_SIZE - 1, MARKER_TEX_SIZE - 1) * 0.5
	var radius := MARKER_TEX_SIZE * 0.42
	for y in MARKER_TEX_SIZE:
		for x in MARKER_TEX_SIZE:
			if Vector2(x, y).distance_to(center) <= radius:
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)


class _ViewRectOverlay extends Control:
	var view_rect: Rect2 = Rect2()
	var border_color: Color = Color(1.0, 1.0, 0.85, 0.9)

	func _draw() -> void:
		if view_rect.size.x <= 0.0 or view_rect.size.y <= 0.0:
			return
		draw_rect(view_rect, border_color, false, 2.0)


class _MiniMapBackground extends Node2D:
	var bounds: Rect2 = Rect2()
	var fill_color: Color = Color(0.12, 0.12, 0.16, 1.0)

	func _draw() -> void:
		draw_rect(bounds, fill_color, true)


class _MiniMapHexLayer extends Node2D:
	var entries: Array = []
	var hex_radius: float = 8.0

	func _draw() -> void:
		for entry in entries:
			var pos: Vector2 = entry.get("position", Vector2.ZERO)
			var color: Color = entry.get("color", Color.WHITE)
			draw_circle(pos, hex_radius, color)
