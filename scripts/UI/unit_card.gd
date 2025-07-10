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
	var spawn_point = Handlers.UnitSelectionHandler.selected_fob.position
	Handlers.UnitSpawnHandler.rpc_id(1, "spawn_unit", spawn_point)
	#Handlers.UnitSpawnHandler.rpc_id(1, "spawn_unit", path)
