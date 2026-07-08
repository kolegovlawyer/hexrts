class_name GameUI extends Node

const _WaypointMarkerManagerScript := preload("res://scripts/UI/waypoint_marker_manager.gd")
const _BattleLogUIScript := preload("res://scripts/UI/battle_log_ui.gd")
const _FormationHelperScript := preload("res://scripts/game_system/formation_helper.gd")

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
@onready var unit_editor_button = get_node(
	"MarginContainer/MainRack/HUDBoard/LeftButtonsContainer/MarginContainer/GridContainer/UnitEditorButton"
)
@onready var spread_button = get_node(
	"MarginContainer/MainRack/HUDBoard/RightButtonsContainer/MarginContainer/GridContainer/SpreadButton"
)

var unit_editor: UnitEditor = null

@onready var unit_container = get_node("%UnitContainer")

@onready var battle_log_richtext: RichTextLabel = get_node("%BattleLogRichText")
@onready var battle_log_clear_button: Button = get_node("%BattleLogClearButton")

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
			
			# Right click — 1 юнит ВСЕГДА точно в клик; группа (>=2 уникальных) — разброс
			if event is InputEventMouseButton and event.button_index == 2:
				if event.pressed == false:
					if Handlers.UnitSelectionHandler.selected_units != null:
						var clear_queue := not Input.is_key_pressed(KEY_SHIFT)
						var selected: Array = []
						for n in Handlers.UnitSelectionHandler.selected_units:
							if is_instance_valid(n) and n not in selected:
								selected.append(n)
						if selected.is_empty():
							return
						var mouse_pos: Vector2 = camera.get_global_mouse_position()
						# Одиночный приказ — всегда точная точка клика, без scatter/jitter
						if selected.size() == 1:
							var solo = selected[0]
							var capture_solo: bool = (not clear_queue) and solo.is_command_unit()
							solo.rpc_id(1, "add_order", mouse_pos, clear_queue, capture_solo)
						else:
							var targets: Array[Vector2] = _FormationHelperScript.scatter_around(
								mouse_pos, selected.size()
							)
							for i in range(selected.size()):
								var n = selected[i]
								var target_position: Vector2 = targets[i] if i < targets.size() else mouse_pos
								var capture_at_destination: bool = (not clear_queue) and n.is_command_unit()
								n.rpc_id(1, "add_order", target_position, clear_queue, capture_at_destination)
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
	#home_button.connect('pressed', move_camera_to_fob)
	unit_editor_button.pressed.connect(open_unit_editor)
	if spread_button:
		spread_button.pressed.connect(_on_spread_pressed)
	_initialize_points_display()
	_initialize_battle_log()

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
	if world == null:
		return
	if not is_multiplayer_authority() and Handlers.UIHandler and Handlers.UIHandler.camera:
		Handlers.UIHandler.camera.set_bounds()
	_ensure_waypoint_marker_manager()

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

func move_camera_to_fob():
	print('КНОПКА НАЖАЛАСЬ')

func stop_camera_move():
	#camera.follow_mouse = false
	pass
	
func continue_camera_move():
	#camera.follow_mouse = true
	pass
	
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
	fob_panel.queue_free()


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
	if battle_log_richtext == null:
		return
	battle_log_richtext.bbcode_enabled = true
	battle_log_richtext.scroll_active = true
	battle_log_richtext.scroll_following = true
	battle_log_richtext.mouse_filter = Control.MOUSE_FILTER_STOP
	battle_log_richtext.text = ""
	_battle_log_line_count = 0
	_battle_log_follow_scroll = true

	var log_container := get_node_or_null(
		"MarginContainer/MainRack/TopBoard/BattleLogContainer"
	) as Control
	if log_container:
		log_container.mouse_filter = Control.MOUSE_FILTER_STOP
		if not log_container.gui_input.is_connected(_on_battle_log_gui_input):
			log_container.gui_input.connect(_on_battle_log_gui_input)

	if not battle_log_richtext.gui_input.is_connected(_on_battle_log_gui_input):
		battle_log_richtext.gui_input.connect(_on_battle_log_gui_input)

	var scroll_bar := battle_log_richtext.get_v_scroll_bar()
	if scroll_bar:
		scroll_bar.changed.connect(_on_battle_log_scroll_changed)

	if battle_log_clear_button:
		battle_log_clear_button.pressed.connect(clear_battle_log)


func _on_battle_log_gui_input(event: InputEvent) -> void:
	# Не даём колёсику уйти в камеру — только скролл журнала.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			get_viewport().set_input_as_handled()


func append_battle_log_event(
		event_type: int,
		hex_tile: Vector2i,
		match_seconds: float,
		actor_name: String = ""
	) -> void:
	if battle_log_richtext == null:
		return

	var line := _BattleLogUIScript.format_event(event_type, hex_tile, match_seconds, actor_name)
	if _battle_log_line_count > 0:
		battle_log_richtext.append_text("\n")
	battle_log_richtext.append_text(line)
	_battle_log_line_count += 1
	_trim_battle_log_lines()

	battle_log_richtext.scroll_following = _battle_log_follow_scroll


func clear_battle_log() -> void:
	if battle_log_richtext == null:
		return
	battle_log_richtext.text = ""
	_battle_log_line_count = 0
	_battle_log_follow_scroll = true
	battle_log_richtext.scroll_following = true


func _trim_battle_log_lines() -> void:
	if _battle_log_line_count <= BATTLE_LOG_MAX_LINES:
		return
	var overflow := _battle_log_line_count - BATTLE_LOG_MAX_LINES
	var text := battle_log_richtext.text
	for _i in overflow:
		var newline_index := text.find("\n")
		if newline_index == -1:
			text = ""
			break
		text = text.substr(newline_index + 1)
	battle_log_richtext.text = text
	_battle_log_line_count = BATTLE_LOG_MAX_LINES


func _on_battle_log_scroll_changed() -> void:
	if battle_log_richtext == null:
		return
	var scroll_bar := battle_log_richtext.get_v_scroll_bar()
	if scroll_bar == null:
		return
	var at_bottom := scroll_bar.value >= scroll_bar.max_value - 8.0
	_battle_log_follow_scroll = at_bottom
	battle_log_richtext.scroll_following = _battle_log_follow_scroll


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
