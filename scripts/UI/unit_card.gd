extends PanelContainer

var selected : bool = false:
	set(value):
		selected = value
		if value == true:
			pass
		else:
			pass

func _ready() -> void:
	connect("gui_input", handle_input)
	
#func _input(event: InputEvent) -> void:
	#if event is InputEventMouseButton and event.button_index == 1:
		#if event.pressed == true:
			#print('Card Clicked from _input of UnitCard')
			#activate_card()
			#get_viewport().set_input_as_handled()
	
func handle_input(event):
	if event is InputEventMouseButton and event.button_index == 1:
		if event.pressed == true:
			activate_card()
			print('Card Clicked from GUI_input of UnitCard')
			get_viewport().set_input_as_handled()
			
func activate_card():
	# Проверяем достаточно ли очков найма (клиентская проверка для UI feedback)
	var current_points = Handlers.UIHandler.get_current_recruitment_points()
	var spawn_cost = 10  # Базовая стоимость спавна
	
	if current_points < spawn_cost:
		#print("❌ UI: Недостаточно очков для спавна! (", current_points, "/", spawn_cost, ")")
		Handlers.UIHandler.show_insufficient_points_message()
		return
	
	var spawn_point = Handlers.UnitSelectionHandler.selected_fob.position
	
	# Отправляем запрос на спавн с валидацией очков на сервере
	print("💰 UI: Запрос спавна юнита (стоимость: ", spawn_cost, " очков)")
	Handlers.UnitSpawnHandler.rpc_id(1, "spawn_unit_with_validation", spawn_point, "base_unit", spawn_cost)
