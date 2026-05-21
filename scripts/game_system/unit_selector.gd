class_name UnitSelector extends Node

var selected_units:Array[BaseUnit] = []
var selected_fob:fob

func _ready():
	Handlers.UnitSelectionHandler = self

func _exit_tree():
	Handlers.UnitSelectionHandler = null
	
	
func select_fob(fob:Node):
	selected_fob = fob

func clear_selection():
	for unit in selected_units:
		if is_instance_valid(unit):
			if unit.has_method("set_selected"):
				unit.set_selected(false)
			else:
				unit.selected = false
			# Очищаем приказы у юнита при снятии выделения
			# Это позволит юниту автоматически атаковать врагов в зоне видимости
			if unit.has_method("rpc_id"):
				unit.rpc_id(1, "clear_orders")
				print("🗑️ SELECTION: Отправлен clear_orders для юнита ", unit.name)
	selected_units.clear()
	
func edit_unit_state(unit:Node):
	if unit in selected_units:
		remove_selected(unit)
	else:
		add_selected(unit)

func add_selected(unit:Node):
	if is_instance_valid(unit):
		selected_units.append(unit)
		if unit.has_method("set_selected"):
			unit.set_selected(true)
		else:
			unit.selected = true
		Handlers.UIHandler.input_state = 1

func remove_selected(unit:Node):
	if is_instance_valid(unit):
		if selected_units.find(unit) != -1:
			selected_units.remove_at(selected_units.find(unit))
		if unit.has_method("set_selected"):
			unit.set_selected(false)
		else:
			unit.selected = false

func set_selected(unit:Node):
	clear_selection()
	edit_unit_state(unit)

func remove_unit_from_selection(unit: BaseUnit):
	"""Удаляет конкретный юнит из выделения (используется при смерти юнита)"""
	if unit in selected_units:
		selected_units.erase(unit)
		print("🗑️ SELECTION: Погибший юнит ", unit.name, " удален из выделения")
		
		# Если это был последний выделенный юнит, сбрасываем input_state
		if selected_units.is_empty():
			if Handlers.UIHandler:
				Handlers.UIHandler.input_state = 0
