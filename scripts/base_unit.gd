class_name BaseUnit extends CharacterBody2D

### SERVER AND UNIT CODE

const SPEED = 300.0

@onready var collision = get_node("%CollisionShape2D")
@onready var selection_ring = get_node("%UnitSelectionRing")
@onready var sprite = get_node("%UnitSelfSprite")
@onready var arrow = get_node("%ArrowSprite")
@onready var light = get_node("%Light")
@onready var synchronizer = get_node("%MultiplayerSynchronizer")
@onready var visibility_area = get_node("%VisibilityArea")

@onready var navagent : NavigationAgent2D = $NavigationAgent2D
var path_points : Array[Vector2] = []


var unit_profile = ''
@export var owner_id : int = 1:
	set(value):
		if value == 1:
			print('WHO I AM???')
			return
		else:
			owner_id = value
		if not is_multiplayer_authority():
			#update_visual()
			pass
		else:
			synchronizer.owner_id = value
			owner_team = Handlers.TeamHandler.find_player_by_id(owner_id).Team
			update_visibility()
			
var owner_team

#@export var health : float

var visible_by : Array[BaseUnit] = []
var has_vision_on : Array[BaseUnit] = []

var orders = {}
var current_order

var current_order_position
var current_order_target

var preselected : bool = false:
	set(value):
		preselected = value
		if value == true:
			selection_ring.show()
		else:
			selection_ring.hide()
			
var selected : bool = false:
	set(value):
		### DEBUG
		print('Unit selected is ', value)
		
		selected = value
		if value == true:
			$UnitSelfSprite.self_modulate = Color(0.37, 0.37, 0.37)#(255, 50, 255, 255)
		if value == false:
			$UnitSelfSprite.self_modulate = Color(1, 1, 1)
			
			
### Характеристики, которые должны заполняться из unit_profile
			
var accel = 7
@export var speed = 300
@export var health = 30
@export var damage = 5
@export var reload_time = 3

var preview


func _ready() -> void:
	
	if not is_multiplayer_authority():
		connect("input_event", handle_input)
		connect("mouse_entered", preseclect)
		connect("mouse_exited", depreselect)
		navagent.queue_free()
		update_visual()
	else:
		$DebugLabel.text = "СЕРВЕРНЫЙ ЧЕЛИКС"
		navagent.connect("velocity_computed", on_velocity_computed)
		visibility_area.connect("body_entered", visibility_check_in)
		visibility_area.connect("body_exited", visibility_check_out)
		print('ОВНЕР АЙДИ ПЕРЕД ТЕМ КАК СЛОМАТЬСЯ ', owner_id)
		print(Handlers.TeamHandler.find_player_by_id(owner_id))
		#owner_team = Handlers.TeamHandler.find_player_by_id(owner_id).Team
	
	update_visual()
	
func visibility_check_in(body):
	print('owner team in check ', owner_team)
	var team = Handlers.TeamHandler.get_team(owner_team)
	print(team)
	if body == self:
		return
	if body is BaseUnit:
		if not has_vision_on.has(body):
			print('ЗАМЕЧЕН ВРАГ')
			has_vision_on.append(body)
		if not body.visible_by.has(self):
			body.visible_by.append(self)
	
	
func visibility_check_out(body):
	pass
		

	
func on_velocity_computed(safe_velocity):
	velocity = safe_velocity
	
func preseclect():
	preselected = true
	
func depreselect():
	preselected = false
	
func handle_input(viewport, event, shape_idx):
	if self in get_tree().get_nodes_in_group("own_units"):
		if event is InputEventMouseButton and event.button_index == 1:
			if event.pressed == false:
				print('we there')
				selected = true
				Handlers.UnitSelectionHandler.add_selected(self)
				get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		
		if visible_by:
			set_visibility_for_enemy(true)
		else:
			set_visibility_for_enemy(false)
		
		if navagent.is_navigation_finished():
			return
		var current_unit_position = global_position
		var next_path_position = navagent.get_next_path_position()
		#arrow.look_at(to_global(navagent.target_position)) # TODO : пофиксить вращение стрелки к цели
		# arrow.rotate(arrow.get_angle_to(navagent.target_position))
		velocity = current_unit_position.direction_to(next_path_position)*speed
		move_and_slide()
		$DebugLabel.text = str(global_position)
		$DebugLabel2.text = str(position)
		
		### проверка целей для атаки
		
		
		
@rpc("any_peer", "reliable")
func add_order(order_obj, clear_queue:bool=false) -> void:
	if owner_id != multiplayer.get_remote_sender_id(): # this must be in all units add_order
		return
	if is_multiplayer_authority():
		match typeof(order_obj):
			TYPE_VECTOR2:
				navagent.target_position = order_obj
		
@rpc("any_peer", "reliable")
func get_unit_info() -> void:
	#print("User ", multiplayer.get_remote_sender_id(), " requested unit info")
	rpc_id(multiplayer.get_remote_sender_id(), "set_unit_info", unit_profile.resource_path)
	
	
func get_target_position():
	return(get_global_mouse_position())
	
func update_visual():
	print("update_visual", owner_id, Handlers.TeamHandler.my_profile)
	if not Handlers.TeamHandler.my_profile:
		return
	if owner_id == 1:
		if not is_multiplayer_authority():
			print("А ВОТ И Я!!!")
		return
		
	var player = Handlers.TeamHandler.find_player_by_id(owner_id)
	if not player:  # Добавляем проверку
		print("Player not found for owner_id: ", owner_id)
		return
		
	owner_team = player.Team
	if owner_id == Handlers.TeamHandler.my_profile.PlayerId:
		add_to_group("own_units")
		if not preview:
			var self_preview = preload("res://prefabs/ui/unit_preview.tscn").instantiate()
			preview = self_preview
		#preview.update_visual()
		Handlers.UIHandler.unit_container.add_child(preview)
		preview.unit = self
		return
	elif Handlers.TeamHandler.find_player_by_id(owner_id).Team == Handlers.TeamHandler.my_profile.Team:
		sprite.self_modulate = Color(0, 0, 1)
		print('ALLY')
	else:
		if sprite:
			sprite.self_modulate = Color(1, 0, 0)
			light.hide()
			sprite.light_mask = 2
			sprite.visibility_layer = 2
			print('check')
		
func update_visibility():
	if is_multiplayer_authority():
		for player in Handlers.TeamHandler.get_team_players(Handlers.TeamHandler.find_player_by_id(owner_id).Team):
			synchronizer.set_visibility_for(player.PlayerId, true)
			
func set_visibility_for_enemy(is_visible:bool) -> void:
	if is_multiplayer_authority():
		for player in Handlers.TeamHandler.get_enemy_team_players(Handlers.TeamHandler.find_player_by_id(owner_id).Team):
			synchronizer.set_visibility_for(player.PlayerId, is_visible)
