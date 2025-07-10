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
		unit.selected = false
	selected_units.clear()
	
func edit_unit_state(unit:Node):
	if unit in selected_units:
		remove_selected(unit)
	else:
		add_selected(unit)

func add_selected(unit:Node):
	selected_units.append(unit)
	Handlers.UIHandler.input_state = 1

func remove_selected(unit:Node):
	if selected_units.find(unit) != -1:
		selected_units.remove_at(selected_units.find(unit))
	unit.selected = false

func set_selected(unit:Node):
	clear_selection()
	edit_unit_state(unit)
