class_name UnitSelector extends Node

var selected_units:Array[BaseUnit] = []
var selected_fob:fob

func _ready():
	Handlers.UnitSelectionHandler = self

func _exit_tree():
	Handlers.UnitSelectionHandler = null
	
	
func select_fob(fob_node: Node) -> void:
	selected_fob = fob_node

func _prune_selected_units() -> void:
	var valid: Array[BaseUnit] = []
	for unit in selected_units:
		if is_instance_valid(unit):
			valid.append(unit)
	selected_units = valid

func clear_selection():
	_prune_selected_units()
	for unit in selected_units:
		if is_instance_valid(unit):
			if unit.has_method("set_selected"):
				unit.set_selected(false)
			else:
				unit.selected = false
	selected_units.clear()
	_refresh_waypoint_markers()
	
func edit_unit_state(unit:Node):
	if not is_instance_valid(unit):
		return
	if unit in selected_units:
		remove_selected(unit)
	else:
		add_selected(unit)

func add_selected(unit:Node):
	_prune_selected_units()
	if is_instance_valid(unit):
		selected_units.append(unit)
		if unit.has_method("set_selected"):
			unit.set_selected(true)
		else:
			unit.selected = true
		Handlers.UIHandler.input_state = 1
		if unit.has_method("rpc_id") and _is_own_unit(unit):
			unit.rpc_id(1, "request_order_queue")
	_refresh_waypoint_markers()

func remove_selected(unit:Node):
	if is_instance_valid(unit):
		if selected_units.find(unit) != -1:
			selected_units.remove_at(selected_units.find(unit))
		if unit.has_method("set_selected"):
			unit.set_selected(false)
		else:
			unit.selected = false
	_refresh_waypoint_markers()

func _is_own_unit(unit: Node) -> bool:
	if not Handlers.TeamHandler or not Handlers.TeamHandler.my_profile:
		return false
	return unit.get("owner_id") == Handlers.TeamHandler.my_profile.PlayerId

func _refresh_waypoint_markers() -> void:
	if Handlers.UIHandler and Handlers.UIHandler.has_method("refresh_waypoint_markers"):
		Handlers.UIHandler.refresh_waypoint_markers()

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
	_refresh_waypoint_markers()
