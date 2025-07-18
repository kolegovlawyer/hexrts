class_name fob extends Node2D

#@onready var FobPanel = get_node("%FobPanel")

@onready var sprite = get_node("%Sprite")
@onready var light = get_node("%Light")

# Система отложенного спавна
const UNIT_SPAWN_DELAY: float = 3.0  # Задержка спавна в секундах

# Очередь заказов на спавн: [{unit_type, unit_cost, player_id, timer}]
var spawn_queue: Array = []

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
	# Добавляем FOB в группу для поиска
	add_to_group("fobs")
	
	if not is_multiplayer_authority():
		connect("input_event", handle_input)
		update_visual()
	else:
		# Серверная логика - обработка очереди спавна
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

### СИСТЕМА ОТЛОЖЕННОГО СПАВНА ###

func add_spawn_order(unit_type: String, unit_cost: int, player_id: int) -> void:
	"""
	Добавляет заказ на спавн юнита в очередь с таймером
	Вызывается только на сервере
	"""
	if not is_multiplayer_authority():
		print("⚠️ FOB SPAWN: add_spawn_order вызвана на клиенте!")
		return
	
	# Создаем таймер для этого заказа
	var spawn_timer = Timer.new()
	spawn_timer.wait_time = UNIT_SPAWN_DELAY
	spawn_timer.one_shot = true
	add_child(spawn_timer)
	
	# Создаем заказ
	var spawn_order = {
		"unit_type": unit_type,
		"unit_cost": unit_cost, 
		"player_id": player_id,
		"timer": spawn_timer
	}
	
	# Подключаем обработчик завершения таймера
	spawn_timer.timeout.connect(_on_spawn_timer_timeout.bind(spawn_order))
	
	# Запускаем таймер
	spawn_timer.start()
	
	# Добавляем в очередь для отслеживания
	spawn_queue.append(spawn_order)
	
	print("⏱️ FOB SPAWN: Заказ на ", unit_type, " добавлен в очередь FOB (", UNIT_SPAWN_DELAY, " сек)")

func _on_spawn_timer_timeout(spawn_order: Dictionary) -> void:
	"""
	Обработчик завершения таймера спавна - выполняет фактический спавн юнита
	"""
	print("🚀 FOB SPAWN: Время вышло, спавним юнита ", spawn_order["unit_type"], " для игрока ", spawn_order["player_id"])
	
	# Вызываем спавн через UnitSpawnHandler
	if Handlers.UnitSpawnHandler:
		Handlers.UnitSpawnHandler._internal_spawn_unit(
			global_position,  # Спавним в позиции FOB
			spawn_order["unit_type"],
			spawn_order["player_id"]
		)
		print("✅ FOB SPAWN: Юнит успешно заспавнен")
	else:
		print("❌ FOB SPAWN: UnitSpawnHandler не найден!")
	
	# Убираем заказ из очереди
	spawn_queue.erase(spawn_order)
	
	# Удаляем таймер
	if spawn_order["timer"]:
		spawn_order["timer"].queue_free()

func get_spawn_queue_size() -> int:
	"""
	Возвращает количество заказов в очереди спавна
	"""
	return spawn_queue.size()
