extends PanelContainer
class_name CommandUnitCard

var selected : bool = false:
	set(value):
		selected = value
		if value == true:
			# TODO: Phase 2 - Добавить визуальную обратную связь при выборе карточки
			pass
		else:
			pass

func _ready() -> void:
	connect("gui_input", handle_input)
	
func handle_input(event):
	if event is InputEventMouseButton and event.button_index == 1:
		if event.pressed == true:
			activate_card()
			print('Command Unit Card Clicked from GUI_input')
			get_viewport().set_input_as_handled()
			
func activate_card():
	"""
	Активирует создание командного юнита
	Отправляет запрос на спавн с указанием типа юнита и повышенной стоимости
	"""
	# Проверяем достаточно ли очков найма (клиентская проверка для UI feedback)
	var current_points = Handlers.UIHandler.get_current_recruitment_points()
	var command_unit_cost = 20  # Командные юниты стоят в 2 раза дороже
	
	if current_points < command_unit_cost:
		print("❌ UI: Недостаточно очков для спавна командного юнита! (", current_points, "/", command_unit_cost, ")")
		Handlers.UIHandler.show_insufficient_points_message()
		return
	
	var spawn_point = Handlers.UnitSelectionHandler.selected_fob.position
	
	# Отправляем запрос на спавн с валидацией очков на сервере
	print("🎖️ КОМАНДА: Запрос спавна командного юнита (стоимость: ", command_unit_cost, " очков)")
	Handlers.UnitSpawnHandler.rpc_id(1, "spawn_unit_with_validation", spawn_point, "command_unit", command_unit_cost) 
