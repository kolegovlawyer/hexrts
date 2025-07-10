class_name fob extends Node2D

#@onready var FobPanel = get_node("%FobPanel")

@onready var sprite = get_node("%Sprite")
@onready var light = get_node("%Light")

@export var team : int
var owner_id = 0:
	set(value):
		owner_id = value
		update_visual()

var selected : bool = false:
	set(value):
		selected = value
		if value == true:
			show_fob_panel()
			print('FOB clicked')
			Handlers.UnitSelectionHandler.selected_fob = self
		else:
			Handlers.UIHandler.delete_fob_panel()
			Handlers.UnitSelectionHandler.selected_fob = null

func _ready() -> void:
	if not is_multiplayer_authority():
		connect("input_event", handle_input)
		update_visual()
	else:
		pass
		# здесь должно быть какое-то разделение по функциям в зависимости от принадлежности
	
func handle_input(viewport, event, shape_idx):
	if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
		if event is InputEventMouseButton and event.button_index == 1:
			if event.pressed == true:
				selected = true
				Handlers.UIHandler.input_state = 2
				Handlers.UIHandler.get_viewport().set_input_as_handled()
		
			
func show_fob_panel():
	Handlers.UIHandler.create_fob_panel(self)
	
func update_visual():
	if owner_id == 0:
		print('enemy FOB at start')
		sprite.modulate = GameTypes.enemy_color
		light.hide()
		sprite.light_mask = 2
		sprite.visibility_layer = 2
		return
	if Handlers.TeamHandler.my_profile:
		if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
			sprite.modulate = GameTypes.own_color
			light.show()
			sprite.light_mask = 1
			sprite.visibility_layer = 1
		elif owner_id in Handlers.TeamHandler.get_team_players(Handlers.TeamHandler.my_profile.PlayerId):
			print('ally')
		else:
			print('enemy FOB')
			sprite.modulate = GameTypes.enemy_color
			light.hide()
			sprite.light_mask = 2
			sprite.visibility_layer = 2
