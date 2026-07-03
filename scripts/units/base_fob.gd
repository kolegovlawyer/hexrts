class_name fob extends Node2D

#@onready var FobPanel = get_node("%FobPanel")

@onready var sprite = get_node("%Sprite")
@onready var light = get_node("%Light")
@onready var spawn_bar = get_node("%SpawnProgress")
@onready var spawn_queue_label = get_node("%SpawnQueueLabel")

# Система отложенного спавна
const UNIT_SPAWN_DELAY: float = 3.0  # Задержка спавна обычных юнитов в секундах
const COMMAND_UNIT_SPAWN_DELAY: float = 6.0  # Задержка спавна командных юнитов (в 2 раза дольше)

# Очередь заказов на спавн: [{unit_type, unit_cost, player_id, spawn_delay}]
var spawn_queue: Array = []

# Единый таймер для последовательного спавна
var spawn_timer: Timer

# Таймер для обновления UI спавна
var ui_update_timer: Timer

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
		# Инициализируем UI спавна
		_initialize_spawn_ui()
	else:
		# Серверная логика - обработка очереди спавна
		_setup_spawn_timer()
		_setup_ui_update_timer()
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
	
	# Обновляем UI спавна при изменении владельца
	_update_spawn_ui_visibility()

### СИСТЕМА ОТЛОЖЕННОГО СПАВНА ###

func _setup_spawn_timer() -> void:
	"""
	Настраивает единый таймер для последовательного спавна (только на сервере)
	"""
	if not is_multiplayer_authority():
		return
	
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)
	print("🏭 FOB: Единый таймер спавна создан")

func add_spawn_order(
		unit_type: String,
		unit_cost: int,
		player_id: int,
		spawn_delay: float = -1.0,
		preset_snapshot: Dictionary = {}
	) -> void:
	"""
	Добавляет заказ на спавн юнита в очередь
	Запускает спавн если очередь была пуста
	"""
	if not is_multiplayer_authority():
		print("⚠️ FOB SPAWN: add_spawn_order вызвана на клиенте!")
		return
	
	# Определяем время спавна в зависимости от типа юнита
	var resolved_delay := spawn_delay
	if resolved_delay < 0.0:
		resolved_delay = UNIT_SPAWN_DELAY
		if unit_type == "command_unit":
			resolved_delay = COMMAND_UNIT_SPAWN_DELAY

	# Создаем заказ (без собственного Timer'а)
	var spawn_order = {
		"unit_type": unit_type,
		"unit_cost": unit_cost,
		"player_id": player_id,
		"spawn_delay": resolved_delay,
		"preset_snapshot": preset_snapshot,
	}
	
	# Добавляем в очередь
	spawn_queue.append(spawn_order)
	
	var unit_type_name = "обычного юнита" if unit_type != "command_unit" else "командного юнита"
	print("⏱️ FOB SPAWN: Заказ на ", unit_type_name, " добавлен в очередь FOB (позиция ", spawn_queue.size(), ")")
	
	# Если это первый заказ в очереди - запускаем спавн
	if spawn_queue.size() == 1:
		_start_next_spawn()
	else:
		# Если спавн уже идет - просто обновляем счетчик очереди
		_sync_spawn_ui_to_clients()
	
	# UI обновления запускаются в _start_next_spawn()

func _start_next_spawn() -> void:
	"""
	Запускает спавн следующего юнита в очереди
	"""
	if spawn_queue.size() == 0:
		print("📋 FOB: Очередь пуста, спавн не запущен")
		return
	
	var current_order = spawn_queue[0]
	var spawn_delay = current_order["spawn_delay"]
	
	# Запускаем таймер для текущего юнита
	spawn_timer.wait_time = spawn_delay
	spawn_timer.start()
	
	var unit_type_name = "обычного юнита" if current_order["unit_type"] != "command_unit" else "командного юнита"
	print("🚀 FOB SPAWN: Начат спавн ", unit_type_name, " (", spawn_delay, " сек)")
	
	# Обновляем UI с начальным прогрессом (0%)
	_sync_spawn_ui_to_clients()
	
	# Запускаем обновления UI в реальном времени
	_start_ui_updates()

func _on_spawn_timer_timeout() -> void:
	"""
	Обработчик завершения таймера спавна - спавнит текущий юнит и запускает следующий
	"""
	if spawn_queue.size() == 0:
		print("⚠️ FOB: Таймер завершен, но очередь пуста!")
		return
	
	# Берем первый заказ из очереди
	var current_order = spawn_queue[0]
	
	print("✅ FOB SPAWN: Спавним юнита ", current_order["unit_type"], " для игрока ", current_order["player_id"])
	
	# Вызываем спавн через UnitSpawnHandler
	if Handlers.UnitSpawnHandler:
		Handlers.UnitSpawnHandler._internal_spawn_unit(
			global_position,  # Спавним в позиции FOB
			current_order["unit_type"],
			current_order["player_id"],
			current_order.get("preset_snapshot", {})
		)
		print("🎯 FOB SPAWN: Юнит успешно заспавнен")
	else:
		print("❌ FOB SPAWN: UnitSpawnHandler не найден!")
	
	# Удаляем заказ из очереди
	spawn_queue.pop_front()
	
	# Обновляем UI
	_sync_spawn_ui_to_clients()
	
	# Если в очереди еще есть юниты - запускаем спавн следующего
	if spawn_queue.size() > 0:
		print("📋 FOB: В очереди осталось ", spawn_queue.size(), " юнитов, запускаем следующий")
		_start_next_spawn()
	else:
		print("🏁 FOB: Очередь спавна завершена")
		# Останавливаем обновления UI
		if ui_update_timer:
			ui_update_timer.stop()

### UI УПРАВЛЕНИЕ СПАВНОМ ###

func _initialize_spawn_ui() -> void:
	"""
	Инициализирует UI элементы спавна на клиенте
	"""
	if spawn_bar:
		spawn_bar.min_value = 0.0
		spawn_bar.max_value = 100.0
		spawn_bar.value = 0.0
		spawn_bar.visible = false
	
	if spawn_queue_label:
		spawn_queue_label.text = "0"
		spawn_queue_label.visible = false

func _update_spawn_ui_visibility() -> void:
	"""
	Обновляет видимость UI спавна на основе владения FOB
	Вызывается на клиенте при изменении владения
	"""
	if is_multiplayer_authority():
		return  # На сервере UI не нужен
	
	# Проверяем, принадлежит ли FOB текущему игроку
	var is_my_fob = false
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		is_my_fob = (owner_id == Handlers.TeamHandler.my_profile.PlayerId)
	
	if not is_my_fob:
		# Скрываем UI если FOB не принадлежит игроку
		if spawn_bar:
			spawn_bar.visible = false
		if spawn_queue_label:
			spawn_queue_label.visible = false
	# Если FOB принадлежит игроку, UI будет обновлен через RPC от сервера

func _sync_spawn_ui_to_clients() -> void:
	"""
	Синхронизирует состояние UI спавна со всеми клиентами
	Вызывается только на сервере
	"""
	if not is_multiplayer_authority():
		return
	
	var queue_size = spawn_queue.size()
	var current_progress = 0.0
	
	# Если есть активный спавн, получаем прогресс из единого таймера
	if queue_size > 0 and spawn_timer and spawn_timer.time_left > 0.0:
		var current_order = spawn_queue[0]  # Первый в очереди = текущий спавн
		var spawn_delay = current_order["spawn_delay"]
		
		var elapsed_time = spawn_delay - spawn_timer.time_left
		current_progress = (elapsed_time / spawn_delay) * 100.0
		current_progress = clamp(current_progress, 0.0, 100.0)
		
		# Дебаг информация
		# print("🔄 FOB UI: Прогресс ", current_progress, "% (", elapsed_time, "/", spawn_delay, " сек)")
	
	# Отправляем обновление всем клиентам
	update_spawn_ui.rpc(queue_size, current_progress)

@rpc("authority", "call_remote", "reliable")
func update_spawn_ui(queue_size: int, progress: float) -> void:
	"""
	RPC для обновления UI спавна на клиентах
	"""
	if is_multiplayer_authority():
		print("⚠️ FOB UI: update_spawn_ui вызвана на сервере!")
		return
	
	# Проверяем, принадлежит ли FOB текущему игроку
	var is_my_fob = false
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		is_my_fob = (owner_id == Handlers.TeamHandler.my_profile.PlayerId)
	
	if not is_my_fob:
		# Скрываем UI если FOB не принадлежит игроку
		if spawn_bar:
			spawn_bar.visible = false
		if spawn_queue_label:
			spawn_queue_label.visible = false
		return
	
	# Обновляем UI для владельца FOB
	if queue_size > 0:
		# Есть юниты в очереди - показываем UI
		if spawn_queue_label:
			spawn_queue_label.text = str(queue_size)
			spawn_queue_label.visible = true
		
		if spawn_bar:
			spawn_bar.value = progress
			spawn_bar.visible = true
	else:
		# Очередь пуста - скрываем UI
		if spawn_queue_label:
			spawn_queue_label.visible = false
		if spawn_bar:
			spawn_bar.visible = false

func get_spawn_queue_size() -> int:
	"""
	Возвращает количество заказов в очереди спавна
	"""
	return spawn_queue.size()

### ОБНОВЛЕНИЕ UI В РЕАЛЬНОМ ВРЕМЕНИ ###

func _setup_ui_update_timer() -> void:
	"""
	Настраивает таймер для обновления UI спавна (только на сервере)
	"""
	if not is_multiplayer_authority():
		return
	
	ui_update_timer = Timer.new()
	ui_update_timer.wait_time = 0.1  # Обновляем каждые 100ms
	ui_update_timer.timeout.connect(_on_ui_update_timer_timeout)
	ui_update_timer.autostart = false  # Запускаем только когда есть спавны
	add_child(ui_update_timer)

func _on_ui_update_timer_timeout() -> void:
	"""
	Обработчик таймера обновления UI
	"""
	if spawn_queue.size() > 0 and spawn_timer and spawn_timer.time_left > 0.0:
		# Есть активный спавн - обновляем UI
		_sync_spawn_ui_to_clients()
	else:
		# Нет активного спавна - останавливаем обновления
		ui_update_timer.stop()

func _start_ui_updates() -> void:
	"""
	Запускает обновления UI если они не активны
	"""
	if ui_update_timer and ui_update_timer.time_left > 0.0:
		return  # Таймер уже работает
	if ui_update_timer and spawn_queue.size() > 0:
		ui_update_timer.start()

func _process(delta: float) -> void:
	"""
	Удаляем старую реализацию _process
	"""
	pass
