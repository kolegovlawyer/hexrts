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
	Отправляет запрос на спавн с указанием типа юнита
	"""
	var spawn_point = Handlers.UnitSelectionHandler.selected_fob.position
	Handlers.UnitSpawnHandler.rpc_id(1, "spawn_unit", spawn_point, "command_unit")
	print("🎖️ КОМАНДА: Запрос на создание командного юнита отправлен") 
