class_name GameUI extends Node

const _WaypointMarkerManagerScript := preload("res://scripts/UI/waypoint_marker_manager.gd")
const _BattleLogUIScript := preload("res://scripts/UI/battle_log_ui.gd")
const _BattleLogEntryScene := preload("res://prefabs/ui/battle_log_entry.tscn")
const _FormationHelperScript := preload("res://scripts/game_system/formation_helper.gd")
const _HexBorderOverlayScript := preload("res://scripts/map/hex_border_overlay.gd")

@onready var window_size = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
ProjectSettings.get_setting("display/window/size/viewport_height"))
@onready var window_size_label = get_node("%WindowSize")
@onready var mouse_position_label = get_node("%CurrentMousePos")

@onready var win_bar = get_node("%WinBar")
@onready var win_bar_label = get_node("%WinBarLabel")
@onready var enemy_team_win_bar = get_node("%EnemyTeamWinBar")
@onready var enemy_team_win_label = get_node("%EnemyTeamWinLabel")
@onready var unit_points = get_node("%UnitPoints")

@onready var hud_board = get_node("%HUDBoard")
@onready var home_button = get_node(
	"MarginContainer/MainRack/HUDBoard/LeftButtonsContainer/MarginContainer/GridContainer/HomeButton"
)
@onready var hex_info_button = get_node(
	"MarginContainer/MainRack/HUDBoard/LeftButtonsContainer/MarginContainer/GridContainer/HexInfoButton"
)
@onready var unit_editor_button = get_node(
	"MarginContainer/MainRack/HUDBoard/LeftButtonsContainer/MarginContainer/GridContainer/UnitEditorButton"
)
@onready var spread_button = get_node(
	"MarginContainer/MainRack/HUDBoard/RightButtonsContainer/MarginContainer/GridContainer/SpreadButton"
)
@onready var movement_attack_toggle = get_node(
	"MarginContainer/MainRack/HUDBoard/RightButtonsContainer/MarginContainer/GridContainer/ToggleMovementAttack"
)
@onready var auto_attack_button = get_node(
	"MarginContainer/MainRack/HUDBoard/RightButtonsContainer/MarginContainer/GridContainer/ToggleAutoAttackButton"
)
@onready var point_attack_button = get_node(
	"MarginContainer/MainRack/HUDBoard/RightButtonsContainer/MarginContainer/GridContainer/PointAttack"
)
@onready var stop_button = get_node(
	"MarginContainer/MainRack/HUDBoard/RightButtonsContainer/MarginContainer/GridContainer/StopButton"
)
@onready var deploy_button: Button = %DeployButton
@onready var path_button = get_node(
	"MarginContainer/MainRack/HUDBoard/RightButtonsContainer/MarginContainer/GridContainer/PathButton"
)
@onready var circle_patrol_button = get_node(
	"MarginContainer/MainRack/HUDBoard/RightButtonsContainer/MarginContainer/GridContainer/CirclePatrolButton"
)
@onready var line_patrol_button = get_node(
	"MarginContainer/MainRack/HUDBoard/RightButtonsContainer/MarginContainer/GridContainer/LinePatrolButton"
)
@onready var back_move_toggle = get_node(
	"MarginContainer/MainRack/HUDBoard/RightButtonsContainer/MarginContainer/GridContainer/BackMove"
)

enum HUD_ORDER_MODES { NONE, POINT_ATTACK, PATH, CIRCLE_PATROL, LINE_PATROL }

const ROUTE_PATROL_LOOP := 1
const ROUTE_PATROL_PING_PONG := 2

var _auto_attack_button_bg: Panel = null
var _hud_order_mode: int = HUD_ORDER_MODES.NONE
var _hud_mode_button_bgs: Dictionary = {}
var _patrol_session_has_waypoints: bool = false

var unit_editor: UnitEditor = null

@onready var unit_container = get_node("%UnitContainer")

@onready var battle_log_scroll: ScrollContainer = get_node("%BattleLogScroll")
@onready var battle_log_list: VBoxContainer = get_node("%BattleLogList")
@onready var battle_log_clear_button: Button = get_node("%BattleLogClearButton")
@onready var minimap: MiniMap = get_node("%MiniMapContainer")

const BATTLE_LOG_MAX_LINES := 50

var _battle_log_line_count: int = 0
var _battle_log_follow_scroll: bool = true

var _unit_previews: Dictionary = {}

var camera
var world

var fob_panel : FOB_panel = null

enum INPUT_STATES {IDLE, UNITS_CONTROL, FOB_INTERACT}

var selection_box

var fobs = {}

var _victory_points_max: int = 1000
var _last_points_revision: int = -1
var _game_over_screen: Control = null
var _waypoint_marker_manager: Node2D = null
var _hex_info_enabled: bool = false
var _hex_info_button_bg: Panel = null
var _pending_camera_fob_center: bool = false
var _camera_centered_on_fob: bool = false

var input_state:int = INPUT_STATES.IDLE:
	set(value):
		
		if value == input_state:
			return
		# DEBUG
		print("input_state_set: from ",
		INPUT_STATES.keys()[input_state],
		"to",
		INPUT_STATES.keys()[value])
		
		input_state_exit(input_state)
		input_state = value
		input_state_enter(input_state)
		
		
func input_state_exit(STATE:int)->void:
	match STATE:
		INPUT_STATES.IDLE:
			pass
		INPUT_STATES.UNITS_CONTROL:
			pass
		INPUT_STATES.FOB_INTERACT:
			delete_fob_panel()
			
func input_state_enter(STATE:int)->void:
	match STATE:
		INPUT_STATES.IDLE:
			pass
		INPUT_STATES.UNITS_CONTROL:
			pass
		INPUT_STATES.FOB_INTERACT:
			if selection_box != null:
				selection_box.queue_free()
	
func _input(event:InputEvent) -> void:
	
	match input_state:
		INPUT_STATES.IDLE:
			pass #сброс фокуса на юнитах и фобе
		INPUT_STATES.UNITS_CONTROL:
			if event.is_echo():
				print('ВЫДЕЛЕНИЕ')
		INPUT_STATES.FOB_INTERACT:
			if event is InputEventMouseButton and event.button_index == 1:
				if event.pressed == true:
					#print('Я - функция, которая должна закрывать окно ФОБа из _input')
					pass
			
			pass # режима выбора юнитов/точки спавна для юнита
#navagent.target_position = get_global_mouse_position()

func _gui_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton and _is_pointer_over_hud():
		return
	match input_state:
		
		INPUT_STATES.IDLE:
			if event is InputEventMouseButton and event.button_index == 2:
				if event.pressed == false:
					pass
					
			elif event is InputEventMouseButton and event.button_index == 1 and event.pressed == true:
				start_draw_selection_box(camera.get_global_mouse_position())
			
			# Delete bound box for selection
			elif event is InputEventMouseButton and event.button_index == 1 and event.pressed == false:
				input_state = 0
				Handlers.UnitSelectionHandler.clear_selection()
				if selection_box != null:
					end_draw_selection_box()
				if camera.check_maps_bound(camera.get_global_mouse_position()) == true:
					camera.position = camera.get_global_mouse_position()
		
		
		INPUT_STATES.UNITS_CONTROL:
			if event is InputEventMouseButton and event.button_index == 2:
				if event.pressed == false:
					_handle_units_control_rmb()
			elif event is InputEventMouseButton and event.button_index == 1 and event.pressed == true:
				start_draw_selection_box(camera.get_global_mouse_position())
			
			# Delete bound box for selection
			elif event is InputEventMouseButton and event.button_index == 1 and event.pressed == false:
				if Input.is_key_pressed(KEY_SHIFT):
					end_draw_selection_box()
				else:
					input_state = 0
					Handlers.UnitSelectionHandler.clear_selection()
					end_draw_selection_box()
		
		INPUT_STATES.FOB_INTERACT:
			if event is InputEventMouseButton and event.button_index == 1:
				if event.pressed == true:
					if Handlers.UnitSelectionHandler.selected_fob != null:
						Handlers.UnitSelectionHandler.selected_fob.selected = false
						print('Я - функция, которая должна закрывать окно ФОБа из _gui_input')
						input_state = 0		

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_clear_unit_container_placeholders()
	Handlers.UIHandler = self
	get_viewport().connect("size_changed", _on_viewport_size_changed)
	bind_map_world()
	hud_board.connect('mouse_entered', stop_camera_move)
	hud_board.connect('mouse_exited', continue_camera_move)
	if home_button:
		home_button.pressed.connect(_on_home_button_pressed)
	unit_editor_button.pressed.connect(open_unit_editor)
	if hex_info_button:
		hex_info_button.toggle_mode = true
		_hex_info_button_bg = hex_info_button.get_node_or_null("BGPanel") as Panel
		hex_info_button.toggled.connect(_on_hex_info_toggled)
		_set_hex_info_visible(false)
	_setup_hud_mouse_block()
	if spread_button:
		spread_button.pressed.connect(_on_spread_pressed)
	if movement_attack_toggle:
		movement_attack_toggle.toggle_mode = true
		movement_attack_toggle.button_pressed = true
		movement_attack_toggle.toggled.connect(_on_movement_attack_toggled)
		_update_movement_attack_toggle_visual(movement_attack_toggle.button_pressed)
		if Handlers.GameHandler:
			Handlers.GameHandler.rpc("set_movement_attack_enabled", true)
	if back_move_toggle:
		back_move_toggle.toggle_mode = true
		back_move_toggle.button_pressed = false
		back_move_toggle.toggled.connect(_on_back_move_toggled)
		_update_back_move_toggle_visual(back_move_toggle.button_pressed)
		if Handlers.GameHandler:
			Handlers.GameHandler.rpc("set_reverse_move_enabled", false)
	if auto_attack_button:
		_auto_attack_button_bg = auto_attack_button.get_node_or_null("BGPanel") as Panel
		auto_attack_button.pressed.connect(_on_auto_attack_pressed)
		_update_auto_attack_button_visual()
	_setup_hud_order_buttons()
	_initialize_points_display()
	_initialize_battle_log()
	_setup_minimap_mouse_block()

func _setup_hud_order_buttons() -> void:
	_register_hud_mode_button(point_attack_button)
	_register_hud_mode_button(path_button)
	_register_hud_mode_button(circle_patrol_button)
	_register_hud_mode_button(line_patrol_button)
	if point_attack_button:
		point_attack_button.toggle_mode = true
		point_attack_button.toggled.connect(_on_point_attack_toggled)
	if path_button:
		path_button.toggle_mode = true
		path_button.toggled.connect(_on_path_button_toggled)
	if circle_patrol_button:
		circle_patrol_button.toggle_mode = true
		circle_patrol_button.toggled.connect(_on_circle_patrol_toggled)
	if line_patrol_button:
		line_patrol_button.toggle_mode = true
		line_patrol_button.toggled.connect(_on_line_patrol_toggled)
	if stop_button:
		stop_button.pressed.connect(_on_stop_pressed)
	if deploy_button:
		deploy_button.visible = false
		deploy_button.pressed.connect(_on_deploy_pressed)
	_update_hud_mode_button_visuals()

func _register_hud_mode_button(button: BaseButton) -> void:
	if button == null:
		return
	var bg := button.get_node_or_null("BGPanel") as Panel
	if bg:
		_hud_mode_button_bgs[button] = bg

func _set_hud_order_mode(mode: int) -> void:
	_hud_order_mode = mode
	_update_hud_mode_button_visuals()

func _update_hud_mode_button_visuals() -> void:
	var active_button: BaseButton = null
	match _hud_order_mode:
		HUD_ORDER_MODES.POINT_ATTACK:
			active_button = point_attack_button
		HUD_ORDER_MODES.PATH:
			active_button = path_button
		HUD_ORDER_MODES.CIRCLE_PATROL:
			active_button = circle_patrol_button
		HUD_ORDER_MODES.LINE_PATROL:
			active_button = line_patrol_button
	for button in _hud_mode_button_bgs.keys():
		var bg: Panel = _hud_mode_button_bgs[button]
		if bg == null:
			continue
		var style := StyleBoxFlat.new()
		if button == active_button:
			style.bg_color = Color(0.25, 0.55, 0.85, 0.9)
		else:
			style.bg_color = Color(0.15, 0.15, 0.2, 0.75)
		bg.add_theme_stylebox_override("panel", style)
	if point_attack_button and not point_attack_button.toggled \
			and _hud_order_mode == HUD_ORDER_MODES.POINT_ATTACK:
		point_attack_button.set_pressed_no_signal(true)
	if path_button and not path_button.toggled and _hud_order_mode == HUD_ORDER_MODES.PATH:
		path_button.set_pressed_no_signal(true)
	if circle_patrol_button and not circle_patrol_button.toggled \
			and _hud_order_mode == HUD_ORDER_MODES.CIRCLE_PATROL:
		circle_patrol_button.set_pressed_no_signal(true)
	if line_patrol_button and not line_patrol_button.toggled \
			and _hud_order_mode == HUD_ORDER_MODES.LINE_PATROL:
		line_patrol_button.set_pressed_no_signal(true)
	if circle_patrol_button and _hud_order_mode != HUD_ORDER_MODES.CIRCLE_PATROL:
		circle_patrol_button.set_pressed_no_signal(false)
	if line_patrol_button and _hud_order_mode != HUD_ORDER_MODES.LINE_PATROL:
		line_patrol_button.set_pressed_no_signal(false)

func reset_patrol_hud_on_selection_change() -> void:
	_patrol_session_has_waypoints = false
	if _hud_order_mode == HUD_ORDER_MODES.CIRCLE_PATROL \
			or _hud_order_mode == HUD_ORDER_MODES.LINE_PATROL:
		_hud_order_mode = HUD_ORDER_MODES.NONE
	_update_hud_mode_button_visuals()
	refresh_waypoint_markers()

func _get_own_selected_units() -> Array:
	var result: Array = []
	if Handlers.UnitSelectionHandler == null:
		return result
	var my_id: int = multiplayer.get_unique_id()
	for unit in Handlers.UnitSelectionHandler.selected_units:
		if is_instance_valid(unit) and unit.owner_id == my_id:
			result.append(unit)
	return result

func _snap_mouse_to_hex_center(mouse_pos: Vector2) -> Vector2:
	if Handlers.GameHandler == null or Handlers.GameHandler.overlay_map == null:
		return mouse_pos
	var overlay_map: TileMapLayer = Handlers.GameHandler.overlay_map
	var local_pos: Vector2 = overlay_map.to_local(mouse_pos)
	var tile: Vector2i = overlay_map.local_to_map(local_pos)
	var world_pos: Vector2 = overlay_map.map_to_local(tile)
	return overlay_map.to_global(world_pos)

func _resolve_clear_queue_for_map_order() -> bool:
	if _hud_order_mode == HUD_ORDER_MODES.PATH:
		return false
	return not Input.is_key_pressed(KEY_SHIFT)

func _get_active_patrol_mode() -> int:
	if _hud_order_mode == HUD_ORDER_MODES.LINE_PATROL:
		return ROUTE_PATROL_PING_PONG
	return ROUTE_PATROL_LOOP

func _handle_units_control_rmb() -> void:
	if Handlers.UnitSelectionHandler == null:
		return
	var selected: Array = []
	for n in Handlers.UnitSelectionHandler.selected_units:
		if is_instance_valid(n) and n not in selected:
			selected.append(n)
	if selected.is_empty():
		return
	var mouse_pos: Vector2 = camera.get_global_mouse_position()
	if _hud_order_mode == HUD_ORDER_MODES.POINT_ATTACK:
		_issue_point_attack_orders(selected, _snap_mouse_to_hex_center(mouse_pos))
		return
	if _hud_order_mode == HUD_ORDER_MODES.CIRCLE_PATROL \
			or _hud_order_mode == HUD_ORDER_MODES.LINE_PATROL:
		_issue_patrol_waypoints(selected, mouse_pos, _get_active_patrol_mode())
		return
	var clear_queue := _resolve_clear_queue_for_map_order()
	_issue_move_orders(selected, mouse_pos, clear_queue)

func _issue_move_orders(selected: Array, mouse_pos: Vector2, clear_queue: bool) -> void:
	if selected.size() == 1:
		var solo = selected[0]
		var capture_solo: bool = (not clear_queue) and solo.is_command_unit()
		solo.rpc_id(1, "add_order", mouse_pos, clear_queue, capture_solo)
		return
	var targets: Array[Vector2] = _FormationHelperScript.scatter_around(mouse_pos, selected.size())
	for i in range(selected.size()):
		var n = selected[i]
		var target_position: Vector2 = targets[i] if i < targets.size() else mouse_pos
		var capture_at_destination: bool = (not clear_queue) and n.is_command_unit()
		n.rpc_id(1, "add_order", target_position, clear_queue, capture_at_destination)

func _issue_point_attack_orders(selected: Array, target_pos: Vector2) -> void:
	if selected.size() == 1:
		selected[0].rpc_id(
			1, "add_attack_position_order", target_pos.x, target_pos.y, true
		)
		return
	var targets: Array[Vector2] = _FormationHelperScript.scatter_around(target_pos, selected.size())
	for i in range(selected.size()):
		var scatter_pos: Vector2 = targets[i] if i < targets.size() else target_pos
		selected[i].rpc_id(
			1, "add_attack_position_order", scatter_pos.x, scatter_pos.y, true
		)

func _issue_patrol_waypoints(selected: Array, mouse_pos: Vector2, mode: int) -> void:
	var is_first_marker: bool = not _patrol_session_has_waypoints
	_patrol_session_has_waypoints = true
	var lane_count: int = selected.size()
	for i in range(lane_count):
		selected[i].rpc_id(
			1,
			"add_patrol_waypoint",
			mouse_pos.x,
			mouse_pos.y,
			mode,
			is_first_marker,
			i,
			lane_count
		)

func _on_point_attack_toggled(pressed: bool) -> void:
	if pressed:
		_set_hud_order_mode(HUD_ORDER_MODES.POINT_ATTACK)
		_sync_exclusive_hud_toggles(point_attack_button)
	else:
		if _hud_order_mode == HUD_ORDER_MODES.POINT_ATTACK:
			_set_hud_order_mode(HUD_ORDER_MODES.NONE)

func _on_path_button_toggled(pressed: bool) -> void:
	if pressed:
		_set_hud_order_mode(HUD_ORDER_MODES.PATH)
		_sync_exclusive_hud_toggles(path_button)
	else:
		if _hud_order_mode == HUD_ORDER_MODES.PATH:
			_set_hud_order_mode(HUD_ORDER_MODES.NONE)

func _sync_exclusive_hud_toggles(active: BaseButton) -> void:
	for button in [point_attack_button, path_button, circle_patrol_button, line_patrol_button]:
		if button == null or button == active:
			continue
		if button.toggle_mode:
			button.set_pressed_no_signal(false)

func _on_circle_patrol_toggled(pressed: bool) -> void:
	if pressed:
		_patrol_session_has_waypoints = false
		_set_hud_order_mode(HUD_ORDER_MODES.CIRCLE_PATROL)
		_sync_exclusive_hud_toggles(circle_patrol_button)
	else:
		if _hud_order_mode == HUD_ORDER_MODES.CIRCLE_PATROL:
			_set_hud_order_mode(HUD_ORDER_MODES.NONE)

func _on_line_patrol_toggled(pressed: bool) -> void:
	if pressed:
		_patrol_session_has_waypoints = false
		_set_hud_order_mode(HUD_ORDER_MODES.LINE_PATROL)
		_sync_exclusive_hud_toggles(line_patrol_button)
	else:
		if _hud_order_mode == HUD_ORDER_MODES.LINE_PATROL:
			_set_hud_order_mode(HUD_ORDER_MODES.NONE)

func _on_stop_pressed() -> void:
	for unit in _get_own_selected_units():
		unit.rpc_id(1, "clear_orders")
	reset_patrol_hud_on_selection_change()
	call_deferred("update_deploy_button_visibility")

func _on_spread_pressed() -> void:
	"""Рассредоточить выбранных юнитов от центроида группы."""
	if Handlers.UnitSelectionHandler == null:
		return
	var selected: Array = []
	var positions: Array[Vector2] = []
	for n in Handlers.UnitSelectionHandler.selected_units:
		if is_instance_valid(n):
			selected.append(n)
			positions.append(n.global_position)
	if selected.is_empty():
		return
	var targets: Array[Vector2] = _FormationHelperScript.spread_from_positions(positions)
	for i in range(selected.size()):
		var dest: Vector2 = targets[i] if i < targets.size() else positions[i]
		selected[i].rpc_id(1, "add_order", dest, true)

func _on_movement_attack_toggled(pressed: bool) -> void:
	_update_movement_attack_toggle_visual(pressed)
	if Handlers.GameHandler:
		Handlers.GameHandler.rpc("set_movement_attack_enabled", pressed)

func _update_movement_attack_toggle_visual(pressed: bool) -> void:
	if movement_attack_toggle:
		movement_attack_toggle.modulate = Color(1.2, 1.2, 1.0) if pressed else Color.WHITE

func _on_back_move_toggled(pressed: bool) -> void:
	_update_back_move_toggle_visual(pressed)
	if Handlers.GameHandler:
		Handlers.GameHandler.rpc("set_reverse_move_enabled", pressed)

func _update_back_move_toggle_visual(pressed: bool) -> void:
	if back_move_toggle:
		back_move_toggle.modulate = Color(1.2, 1.2, 1.0) if pressed else Color.WHITE

func _on_auto_attack_pressed() -> void:
	if Handlers.UnitSelectionHandler == null:
		return
	var my_id: int = multiplayer.get_unique_id()
	for unit in Handlers.UnitSelectionHandler.selected_units:
		if not is_instance_valid(unit):
			continue
		if unit.owner_id != my_id:
			continue
		unit.rpc_id(1, "toggle_auto_attack")
	call_deferred("_update_auto_attack_button_visual")

func _update_auto_attack_button_visual() -> void:
	if _auto_attack_button_bg == null:
		return
	var style := StyleBoxFlat.new()
	var color: Color
	if Handlers.UnitSelectionHandler == null \
			or Handlers.UnitSelectionHandler.selected_units.is_empty():
		color = Color(0.2, 0.7, 0.3)
	else:
		var my_id: int = multiplayer.get_unique_id()
		var enabled_count: int = 0
		var own_count: int = 0
		for unit in Handlers.UnitSelectionHandler.selected_units:
			if not is_instance_valid(unit) or unit.owner_id != my_id:
				continue
			own_count += 1
			if unit.auto_attack_enabled:
				enabled_count += 1
		if own_count == 0:
			color = Color(0.2, 0.7, 0.3)
		elif enabled_count == own_count:
			color = Color(0.2, 0.7, 0.3)
		elif enabled_count == 0:
			color = Color(0.75, 0.2, 0.2)
		else:
			color = Color(0.85, 0.65, 0.15)
	style.bg_color = color
	_auto_attack_button_bg.add_theme_stylebox_override("panel", style)

func register_unit_preview(uid: String, preview: UnitPreview) -> void:
	if uid == "" or preview == null or preview.is_queued_for_deletion():
		return
	_purge_invalid_unit_previews()
	_unit_previews[uid] = preview

func unregister_unit_preview(uid: String) -> void:
	_unit_previews.erase(uid)

func sync_unit_rack_selection() -> void:
	if not Handlers.UnitSelectionHandler:
		return
	var selected_units: Array = Handlers.UnitSelectionHandler.selected_units
	for child in unit_container.get_children():
		var preview := child as UnitPreview
		if preview == null or not is_instance_valid(preview):
			continue
		var is_selected := is_instance_valid(preview.unit) and preview.unit in selected_units
		preview.set_rack_selected(is_selected)
	_update_auto_attack_button_visual()
	update_deploy_button_visibility()


func update_deploy_button_visibility() -> void:
	if deploy_button == null:
		return
	deploy_button.visible = _get_deployable_command_unit() != null


func _get_deployable_command_unit() -> BaseUnit:
	if Handlers.UnitSelectionHandler == null:
		return null
	var own_selected: Array = _get_own_selected_units()
	if own_selected.size() != 1:
		return null
	var unit: BaseUnit = own_selected[0]
	if not is_instance_valid(unit) or not unit.is_command_unit():
		return null
	if unit.preset_stat_sum != UnitPresetBalance.STAT_SUM_MAX:
		return null
	if unit.has_method("get_order_queue_snapshot"):
		if not unit.get_order_queue_snapshot().is_empty():
			return null
	if not _is_unit_on_friendly_hex(unit):
		return null
	return unit


func _is_unit_on_friendly_hex(unit: BaseUnit) -> bool:
	if not Handlers.GameHandler or unit.owner_team == null:
		return false
	var hex = Handlers.GameHandler.get_hex_at_world_position(unit.global_position)
	if hex == null:
		return false
	return hex.team_owner == int(unit.owner_team)


func _on_deploy_pressed() -> void:
	var unit := _get_deployable_command_unit()
	if unit == null:
		return
	unit.rpc_id(1, "request_deploy_fob")

func get_unit_preview(uid: String) -> UnitPreview:
	return _unit_previews.get(uid, null)

func get_or_create_unit_preview(unit: BaseUnit) -> UnitPreview:
	if not is_instance_valid(unit):
		return null

	_purge_invalid_unit_previews()

	var uid := unit.UID
	if uid != "" and _unit_previews.has(uid):
		var registered_preview: UnitPreview = _unit_previews[uid]
		if is_instance_valid(registered_preview):
			registered_preview.unit = unit
			registered_preview.update_visual()
			return registered_preview
		_unit_previews.erase(uid)

	for child in unit_container.get_children():
		var candidate := child as UnitPreview
		if candidate == null:
			continue
		if candidate.is_queued_for_deletion():
			continue
		if not is_instance_valid(candidate.unit):
			candidate.queue_free()
			continue
		if candidate.unit == unit or (uid != "" and candidate.unit.UID == uid):
			candidate.unit = unit
			candidate.update_visual()
			if uid != "":
				_unit_previews[uid] = candidate
			return candidate

	var new_preview: UnitPreview = preload("res://prefabs/ui/unit_preview.tscn").instantiate()
	new_preview.unit = unit
	unit_container.add_child(new_preview)
	new_preview.update_visual()
	if uid != "":
		_unit_previews[uid] = new_preview
	return new_preview

func _purge_invalid_unit_previews() -> void:
	var valid_previews: Dictionary = {}
	var seen_keys: Dictionary = {}
	for child in unit_container.get_children():
		var candidate := child as UnitPreview
		if candidate == null:
			continue
		if candidate.is_queued_for_deletion():
			continue
		if not is_instance_valid(candidate.unit):
			candidate.queue_free()
			continue

		var uid := candidate.unit.UID
		var preview_key := uid if uid != "" else str(candidate.unit.get_instance_id())
		if seen_keys.has(preview_key):
			candidate.queue_free()
			continue

		seen_keys[preview_key] = true
		if uid != "":
			valid_previews[uid] = candidate
	_unit_previews = valid_previews

func _clear_unit_container_placeholders() -> void:
	_unit_previews.clear()
	for child in unit_container.get_children():
		child.queue_free()

func bind_map_world() -> void:
	var map_root: Node = get_parent().get_parent().get_node("%Map")
	world = map_root.get_node_or_null("TestMapWorld")
	if world == null and map_root.get_child_count() > 0:
		world = map_root.get_child(0) as Node2D
	if world == null:
		return
	if not is_multiplayer_authority() and Handlers.UIHandler and Handlers.UIHandler.camera:
		Handlers.UIHandler.camera.set_bounds()
	_ensure_waypoint_marker_manager()
	if _hex_info_enabled:
		_apply_hex_info_overlay(true)
	if minimap:
		minimap.setup(world, camera)
	_try_center_camera_on_own_fob()


func request_center_camera_on_own_fob() -> void:
	if _camera_centered_on_fob:
		return
	_pending_camera_fob_center = true
	call_deferred("_try_center_camera_on_own_fob")


func _get_own_player_id() -> int:
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		return Handlers.TeamHandler.my_profile.PlayerId
	if is_instance_valid(multiplayer):
		return multiplayer.get_unique_id()
	return 0


func _get_own_fobs() -> Array:
	var result: Array = []
	var player_id := _get_own_player_id()
	if player_id == 0:
		return result
	for node in get_tree().get_nodes_in_group("fobs"):
		if not is_instance_valid(node) or not (node is fob):
			continue
		var fob_node: fob = node as fob
		if fob_node.owner_id == player_id and fob_node.is_alive():
			result.append(fob_node)
	return result


func _find_nearest_own_fob_to(world_pos: Vector2) -> fob:
	var best: fob = null
	var best_dist_sq := INF
	for node in _get_own_fobs():
		var fob_node: fob = node as fob
		var dist_sq: float = world_pos.distance_squared_to(fob_node.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = fob_node
	return best


func _move_camera_to_fob(fob_node: fob) -> void:
	if camera == null or fob_node == null:
		return
	if camera.has_method("set_bounds") and camera.TOP_CORNER == null:
		camera.set_bounds()
	if camera.has_method("snap_to_world_position"):
		camera.snap_to_world_position(fob_node.global_position)
	else:
		camera.position = fob_node.global_position


func _try_center_camera_on_own_fob() -> void:
	if not _pending_camera_fob_center or _camera_centered_on_fob:
		return
	if camera == null:
		return
	var own_fobs := _get_own_fobs()
	if own_fobs.is_empty():
		return
	_move_camera_to_fob(own_fobs[0])
	_camera_centered_on_fob = true
	_pending_camera_fob_center = false


func _on_home_button_pressed() -> void:
	move_camera_to_nearest_own_fob()


func move_camera_to_nearest_own_fob() -> void:
	bind_map_world()
	if camera == null:
		return
	var nearest_fob := _find_nearest_own_fob_to(camera.position)
	if nearest_fob:
		_move_camera_to_fob(nearest_fob)


func _on_hex_info_toggled(pressed: bool) -> void:
	_set_hex_info_visible(pressed)


func _set_hex_info_visible(enabled: bool) -> void:
	_hex_info_enabled = enabled
	if hex_info_button and hex_info_button.button_pressed != enabled:
		hex_info_button.set_pressed_no_signal(enabled)
	_update_hex_info_button_visual(enabled)
	_apply_hex_info_overlay(enabled)


func _update_hex_info_button_visual(enabled: bool) -> void:
	if _hex_info_button_bg == null:
		return
	if enabled:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.7, 0.3, 0.85)
		_hex_info_button_bg.add_theme_stylebox_override("panel", style)
	else:
		_hex_info_button_bg.remove_theme_stylebox_override("panel")


func _apply_hex_info_overlay(enabled: bool) -> void:
	if world == null:
		bind_map_world()
	if world == null:
		return
	var label_layer: Node = world.get_node_or_null("HexLabelLayer")
	var border_map: TileMapLayer = world.get_node_or_null("BorderOverlayMap") as TileMapLayer
	var main_map: TileMapLayer = world.get_node_or_null("MainMap") as TileMapLayer
	var overlay_map: TileMapLayer = null
	if Handlers.GameHandler:
		overlay_map = Handlers.GameHandler.overlay_map
	if not enabled:
		if label_layer and label_layer.has_method("clear_labels"):
			label_layer.clear_labels()
		_HexBorderOverlayScript.hide(border_map)
		return
	if label_layer and label_layer.has_method("build_labels") and overlay_map:
		label_layer.build_labels(overlay_map)
	if main_map:
		_HexBorderOverlayScript.show_on_main_map(border_map, main_map)

func _ensure_waypoint_marker_manager() -> void:
	if world == null or _waypoint_marker_manager != null:
		return
	_waypoint_marker_manager = _WaypointMarkerManagerScript.new()
	world.add_child(_waypoint_marker_manager)

func refresh_waypoint_markers() -> void:
	if world == null:
		bind_map_world()
	if _waypoint_marker_manager and is_instance_valid(_waypoint_marker_manager):
		_waypoint_marker_manager.refresh_for_selection()

func move_camera_to_fob() -> void:
	move_camera_to_nearest_own_fob()


func stop_camera_move() -> void:
	if camera:
		camera.follow_mouse = false


func continue_camera_move() -> void:
	if camera:
		camera.follow_mouse = true


func _setup_hud_mouse_block() -> void:
	if hud_board == null:
		return
	for container_name in ["LeftButtonsContainer", "RightButtonsContainer"]:
		var container := hud_board.get_node_or_null(container_name) as Control
		if container:
			container.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_hud_buttons_mouse_filter_stop(hud_board)


func _setup_minimap_mouse_block() -> void:
	if minimap == null:
		return
	minimap.mouse_entered.connect(stop_camera_move)
	minimap.mouse_exited.connect(continue_camera_move)


func _set_hud_buttons_mouse_filter_stop(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).mouse_filter = Control.MOUSE_FILTER_STOP
	for child in node.get_children():
		_set_hud_buttons_mouse_filter_stop(child)


func _is_pointer_over_hud() -> bool:
	if hud_board == null or not is_instance_valid(hud_board):
		return false
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	if minimap and is_instance_valid(minimap):
		if hovered == minimap or minimap.is_ancestor_of(hovered):
			return true
	return hovered == hud_board or hud_board.is_ancestor_of(hovered)
	
func update_visible_units():
	for n in Handlers.GameHandler.get_all_units():
		n.update_visual()
	
func _on_viewport_size_changed():
	if camera:
		camera.un_zoomed_viewport_size = get_viewport().size
	
func _exit_tree():
	Handlers.UIHandler = null
	
### POINTS DISPLAY FUNCTIONS ###

func init_match_balance(balance: Dictionary) -> void:
	_victory_points_max = int(balance.get("victory_points_to_win", 1000))
	_last_points_revision = -1
	unit_points.text = "0"
	win_bar.min_value = 0.0
	win_bar.max_value = 100.0
	win_bar.value = 0.0
	if win_bar_label:
		win_bar_label.text = "0 / %d" % _victory_points_max
	if enemy_team_win_bar:
		enemy_team_win_bar.min_value = 0.0
		enemy_team_win_bar.max_value = 100.0
		enemy_team_win_bar.value = 0.0
	if enemy_team_win_label:
		enemy_team_win_label.text = "0 / %d" % _victory_points_max


func _update_victory_bars(own_victory: float, enemy_victory: float) -> void:
	var max_vp := maxf(1.0, float(_victory_points_max))
	var own_pct := clampf((own_victory / max_vp) * 100.0, 0.0, 100.0)
	win_bar.value = own_pct
	if win_bar_label:
		win_bar_label.text = "%d / %d" % [int(own_victory), _victory_points_max]
	if enemy_team_win_bar:
		var enemy_pct := clampf((enemy_victory / max_vp) * 100.0, 0.0, 100.0)
		enemy_team_win_bar.value = enemy_pct
	if enemy_team_win_label:
		enemy_team_win_label.text = "%d / %d" % [int(enemy_victory), _victory_points_max]


func update_points_display(
		recruitment_points: float,
		victory_points: float,
		revision: int = -1,
		victory_max: int = -1,
		enemy_victory_points: float = -1.0
	) -> void:
	if revision >= 0 and revision <= _last_points_revision:
		return
	if revision >= 0:
		_last_points_revision = revision
	if victory_max > 0:
		_victory_points_max = victory_max

	unit_points.text = str(int(recruitment_points))

	var enemy_vp := enemy_victory_points if enemy_victory_points >= 0.0 else 0.0
	_update_victory_bars(victory_points, enemy_vp)


func get_current_recruitment_points() -> int:
	"""
	Возвращает текущие очки найма для UI (для проверки доступности спавна)
	"""
	var text = unit_points.text
	if text.is_valid_int():
		return text.to_int()
	return 0

func show_insufficient_points_message() -> void:
	"""
	Показывает сообщение о недостаточности очков для спавна
	"""
	print("⚠️ UI: Недостаточно очков для спавна юнита!")
	# TODO: Добавить визуальное уведомление в UI (тост, анимация и т.д.)

func _initialize_points_display() -> void:
	init_match_balance({"victory_points_to_win": 1000})
	print("🎯 UI: Инициализированы начальные значения очков")


func show_game_over(is_winner: bool, reason: String, is_draw: bool = false) -> void:
	if _game_over_screen and is_instance_valid(_game_over_screen):
		return
	var screen: Control = preload("res://prefabs/ui/game_over_screen.tscn").instantiate()
	_game_over_screen = screen
	add_child(screen)
	if screen.has_method("setup"):
		screen.setup(is_winner, reason, is_draw)
	
func start_draw_selection_box(init_position):
	if world == null:
		bind_map_world()
	if world == null:
		return
	var new_selection_box = preload("res://prefabs/ui/selectoin_box.tscn").instantiate()
	world.add_child(new_selection_box)
	selection_box = new_selection_box
	selection_box.init_draw_position = init_position
	print('start draw selection box')
	
func end_draw_selection_box():
	selection_box.select_units()
	selection_box.queue_free()
	print('end draw selection box')
	
	
#func _unhandled_input(event: InputEvent) -> void:
	#if event is InputEventMouseButton:
		#print('Я - Unhandled_input в BaseUI', event)
	
	#if event is InputEventMouseButton and event.button_index == 1:
		#if event.pressed == true:
			#print('Я - _input в BaseUI')
			#if fob_panel != null:
				#fob_panel.queue_free()
	
	
	
func handle_input(_event):
	pass

func create_fob_panel(_fob_node) -> void:
	var new_fob_panel = preload("res://prefabs/ui/fob_panel.tscn").instantiate()
	add_child(new_fob_panel)
	new_fob_panel.position = get_viewport().get_mouse_position()
	fob_panel = new_fob_panel
	

func delete_fob_panel():
	if fob_panel and is_instance_valid(fob_panel):
		fob_panel.queue_free()
	fob_panel = null


func open_unit_editor() -> void:
	if unit_editor and is_instance_valid(unit_editor):
		return
	unit_editor = preload("res://prefabs/ui/unit_editor.tscn").instantiate() as UnitEditor
	add_child(unit_editor)
	unit_editor.tree_exited.connect(func() -> void:
		unit_editor = null
	)


### BATTLE LOG ###

func _initialize_battle_log() -> void:
	if battle_log_scroll == null or battle_log_list == null:
		return
	_battle_log_line_count = 0
	_battle_log_follow_scroll = true

	var log_container := get_node_or_null(
		"MarginContainer/MainRack/TopBoard/BattleLogContainer"
	) as Control
	if log_container:
		log_container.mouse_filter = Control.MOUSE_FILTER_STOP

	battle_log_scroll.mouse_filter = Control.MOUSE_FILTER_STOP

	var scroll_bar := battle_log_scroll.get_v_scroll_bar()
	if scroll_bar:
		scroll_bar.changed.connect(_on_battle_log_scroll_changed)

	if battle_log_clear_button:
		battle_log_clear_button.pressed.connect(clear_battle_log)


func append_battle_log_event(
		event_type: int,
		hex_tile: Vector2i,
		match_seconds: float,
		actor_name: String = ""
	) -> void:
	if battle_log_list == null:
		return

	var line := _BattleLogUIScript.format_event(event_type, hex_tile, match_seconds, actor_name)
	var entry = _BattleLogEntryScene.instantiate()
	entry.setup(line, hex_tile)
	entry.clicked.connect(_on_battle_log_entry_clicked)
	battle_log_list.add_child(entry)
	_battle_log_line_count += 1
	_trim_battle_log_lines()

	if _battle_log_follow_scroll:
		call_deferred("_scroll_battle_log_to_bottom")


func clear_battle_log() -> void:
	if battle_log_list == null:
		return
	for child in battle_log_list.get_children():
		child.queue_free()
	_battle_log_line_count = 0
	_battle_log_follow_scroll = true
	call_deferred("_scroll_battle_log_to_bottom")


func _trim_battle_log_lines() -> void:
	if battle_log_list == null or _battle_log_line_count <= BATTLE_LOG_MAX_LINES:
		return
	var overflow := _battle_log_line_count - BATTLE_LOG_MAX_LINES
	for _i in overflow:
		var children := battle_log_list.get_children()
		if children.is_empty():
			break
		children[0].queue_free()
	_battle_log_line_count = BATTLE_LOG_MAX_LINES


func _scroll_battle_log_to_bottom() -> void:
	if battle_log_scroll == null:
		return
	var scroll_bar := battle_log_scroll.get_v_scroll_bar()
	if scroll_bar:
		scroll_bar.value = scroll_bar.max_value


func _on_battle_log_scroll_changed() -> void:
	if battle_log_scroll == null:
		return
	var scroll_bar := battle_log_scroll.get_v_scroll_bar()
	if scroll_bar == null:
		return
	var at_bottom := scroll_bar.max_value <= 0.0 or scroll_bar.value >= scroll_bar.max_value - 8.0
	_battle_log_follow_scroll = at_bottom


func _hex_tile_to_world_center(hex_tile: Vector2i) -> Vector2:
	if Handlers.GameHandler == null or Handlers.GameHandler.overlay_map == null:
		return Vector2.ZERO
	var overlay_map: TileMapLayer = Handlers.GameHandler.overlay_map
	var half_size := Vector2(overlay_map.tile_set.tile_size) * 0.5
	return overlay_map.to_global(overlay_map.map_to_local(hex_tile) + half_size)


func _on_battle_log_entry_clicked(hex_tile: Vector2i) -> void:
	if camera == null:
		return
	var world_pos := _hex_tile_to_world_center(hex_tile)
	if world_pos == Vector2.ZERO:
		return
	if camera.has_method("set_bounds") and camera.TOP_CORNER == null:
		camera.set_bounds()
	if camera.has_method("snap_to_world_position"):
		camera.snap_to_world_position(world_pos)
	else:
		camera.position = world_pos


### DEBUG SECTION

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	window_size = get_viewport().size
	window_size_label.text = str(window_size, window_size.x, window_size.y)
	if camera == null:
		mouse_position_label.text = "CAMERA: not ready"
		return
	mouse_position_label.text = str(
		"VIEWPORT_MOUSE_POS: ", get_viewport().get_mouse_position(),
		"GLOBAL_MOUSE_POS", camera.get_global_mouse_position(),
		"CAMERA_POS:", camera.position,
		"INPUT_STATE: ", input_state)
