class_name GameUI extends Node

@onready var window_size = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
ProjectSettings.get_setting("display/window/size/viewport_height"))
@onready var window_size_label = get_node("%WindowSize")
@onready var mouse_position_label = get_node("%CurrentMousePos")

@onready var win_bar = get_node("%WinBar")
@onready var unit_points = get_node("%UnitPoints")

@onready var hud_board = get_node("%HUDBoard")
@onready var home_button = get_node(
	"MarginContainer/MainRack/HUDBoard/LeftButtonsContainer/MarginContainer/GridContainer/HomeButton"
)
@onready var unit_editor_button = get_node(
	"MarginContainer/MainRack/HUDBoard/LeftButtonsContainer/MarginContainer/GridContainer/UnitEditorButton"
)

var unit_editor: UnitEditor = null

@onready var unit_container = get_node("%UnitContainer")

var _unit_previews: Dictionary = {}

var camera
var world

var fob_panel : FOB_panel = null

enum INPUT_STATES {IDLE, UNITS_CONTROL, FOB_INTERACT}

var selection_box

var fobs = {}

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
			
			# Right click
			if event is InputEventMouseButton and event.button_index == 2:
				if event.pressed == false:
					if Handlers.UnitSelectionHandler.selected_units != null:
						for n in Handlers.UnitSelectionHandler.selected_units:
							if is_instance_valid(n):
								var target_position = camera.get_global_mouse_position()
								#n.navagent.target_position = target_position
								#print('GLOBAL MOUSE POSITION: ', get_global_mouse_position())
								print('Через UI отправлен приказ на движение серверному юниту')
								n.rpc_id(1, "add_order", target_position, true)
							#{"order": GameTypes.OrderTypes.MOVE_FORWARD,
						#"target":cursor_pos}
							
				## Vot eto polni pizdec
			# Create bound box for selection
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
	_initialize_points_display()

func register_unit_preview(uid: String, preview: UnitPreview) -> void:
	if uid == "" or preview == null:
		return
	_unit_previews[uid] = preview

func unregister_unit_preview(uid: String) -> void:
	_unit_previews.erase(uid)

func get_unit_preview(uid: String) -> UnitPreview:
	return _unit_previews.get(uid, null)

func _clear_unit_container_placeholders() -> void:
	for child in unit_container.get_children():
		child.queue_free()

func bind_map_world() -> void:
	var map_root: Node = get_parent().get_parent().get_node("%Map")
	world = map_root.get_node_or_null("TestMapWorld")
	if world == null:
		return
	if not is_multiplayer_authority() and Handlers.UIHandler and Handlers.UIHandler.camera:
		Handlers.UIHandler.camera.set_bounds()

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
	camera.un_zoomed_viewport_size = get_viewport().size
	
func _exit_tree():
	Handlers.UIHandler = null
	
### POINTS DISPLAY FUNCTIONS ###

func update_points_display(recruitment_points: float, victory_points: float) -> void:
	"""
	Обновляет отображение очков в UI
	Вызывается через RPC от сервера
	"""
	# Обновляем очки найма в label
	unit_points.text = str(int(recruitment_points))
	
	# Обновляем прогресс-бар очков победы
	var victory_percentage = (victory_points / 500.0) * 100.0  # 500 - цель для победы
	win_bar.value = victory_percentage
	
	#print("🎯 UI: Обновлены очки - найм: ", int(recruitment_points), " победа: ", int(victory_points), "/500 (", int(victory_percentage), "%)")

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
	"""
	Инициализирует отображение очков начальными значениями
	"""
	# Устанавливаем начальные значения (будут обновлены сервером)
	unit_points.text = "0"
	win_bar.value = 0.0
	win_bar.max_value = 100.0  # Для процентов (0-100%)
	win_bar.min_value = 0.0
	print("🎯 UI: Инициализированы начальные значения очков")
	
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
	
	
	
func handle_input(event):
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


### DEBUG SECTION

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	window_size = get_viewport().size
	window_size_label.text = str(window_size, window_size.x, window_size.y)
	mouse_position_label.text = str(
		"VIEWPORT_MOUSE_POS: ", get_viewport().get_mouse_position(),
		"GLOBAL_MOUSE_POS", camera.get_global_mouse_position(),
		"CAMERA_POS:", camera.position,
		"INPUT_STATE: ", input_state)
