class_name UnitPreview extends PanelContainer

var unit : BaseUnit:
	set(value):
		unit = value
		update_visual()
		
@onready var sprite = get_node("MainRack/SpriteIcon")
@onready var rank = get_node("MainRack/StatusBoard/RankIcon")
@onready var hp_bar = get_node("MainRack/StatusBoard/Control/BarsDeck/HPBar")
@onready var shield_bar = get_node("MainRack/StatusBoard/Control/BarsDeck/ShieldBar")
@onready var name_label = get_node("MainRack/NameLabel")

func _ready() -> void:
	connect("gui_input", handle_input)
	
func handle_input(event):
	if event is InputEventMouseButton and event.button_index == 1 and event.pressed == false:
		if Input.is_key_pressed(KEY_SHIFT):
			Handlers.UnitSelectionHandler.add_selected(unit)
			unit.selected = true
			get_viewport().set_input_as_handled()
			return
		Handlers.UIHandler.camera.position = unit.position
		Handlers.UnitSelectionHandler.clear_selection()
		Handlers.UnitSelectionHandler.add_selected(unit)
		unit.selected = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == 1 and event.pressed == true:
		get_viewport().set_input_as_handled()

func update_visual():
	print('обновление визуала превьюшки')
