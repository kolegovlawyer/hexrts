class_name UnitSpawner extends Node2D

func _ready():
	Handlers.UnitSpawnHandler = self

func _exit_tree():
	Handlers.UnitSpawnHandler = null

@rpc("any_peer", "reliable")
func spawn_unit_with_validation(spawn_point, unit_type: String = "base_unit", unit_cost: int = 10):
	"""
	Новая функция спавна с валидацией очков и отложенным спавном через FOB
	"""
	if is_multiplayer_authority():
		var player_id = multiplayer.get_remote_sender_id()
		print("🎯 SPAWN: Получен запрос спавна от игрока ", player_id, " стоимость: ", unit_cost)
		
		# Валидация очков через GameManager
		if Handlers.GameHandler and Handlers.GameHandler.validate_unit_spawn(player_id, unit_cost):
			# Очки списаны, ищем FOB игрока и добавляем заказ в его очередь
			var player_fob = _find_player_fob(player_id)
			if player_fob:
				player_fob.add_spawn_order(unit_type, unit_cost, player_id)
				print("✅ SPAWN: Заказ добавлен в очередь FOB игрока ", player_id)
				
				# Определяем время спавна для сообщения клиенту
				var spawn_delay = 3.0  # Обычные юниты
				if unit_type == "command_unit":
					spawn_delay = 6.0  # Командные юниты
				
				# Отправляем подтверждение клиенту
				confirm_spawn_started.rpc_id(player_id, unit_type, unit_cost, spawn_delay)
			else:
				print("❌ SPAWN: FOB игрока ", player_id, " не найден!")
				reject_spawn.rpc_id(player_id, "FOB не найден")
		else:
			# Валидация не прошла, отправляем отказ клиенту
			print("❌ SPAWN: Валидация не прошла для игрока ", player_id)
			reject_spawn.rpc_id(player_id, "Недостаточно очков найма")

func _find_player_fob(player_id: int) -> fob:
	"""
	Находит FOB принадлежащий игроку
	"""
	var all_fobs = get_tree().get_nodes_in_group("fobs")
	for fob_node in all_fobs:
		if fob_node is fob and fob_node.owner_id == player_id:
			return fob_node
	return null

@rpc("authority", "call_remote", "reliable")
func confirm_spawn_started(unit_type: String, cost: int, spawn_delay: float = 3.0):
	"""
	RPC подтверждения начала спавна для клиента
	"""
	print("✅ CLIENT: Спавн ", unit_type, " начат (списано ", cost, " очков, ожидание ", spawn_delay, " сек)")
	# TODO: Показать визуальную обратную связь (таймер спавна, анимацию и т.д.)

@rpc("authority", "call_remote", "reliable") 
func reject_spawn(reason: String):
	"""
	RPC отказа в спавне для клиента
	"""
	print("❌ CLIENT: Спавн отклонен: ", reason)
	# TODO: Показать уведомление в UI

@rpc("any_peer", "reliable")
func spawn_unit(spawn_point, unit_type: String = "base_unit"):
	if is_multiplayer_authority():
		var player_id = multiplayer.get_remote_sender_id()
		_internal_spawn_unit(spawn_point, unit_type, player_id)

func _internal_spawn_unit(spawn_point: Vector2, unit_type: String, player_id: int):
	"""
	Внутренняя функция спавна, которая может быть вызвана напрямую с указанием player_id
	Используется как для RPC, так и для отложенного спавна
	"""
	if not is_multiplayer_authority():
		return
		
	# Добавляем случайный разброс в пределах 20 пикселей
	var random_offset = Vector2(
		randf_range(-50.0, 50.0),
		randf_range(-50.0, 50.0)
	)
	spawn_point += random_offset
	
	var scene_path := "res://prefabs/units/base_unit.tscn"
	if unit_type == "command_unit":
		scene_path = "res://prefabs/units/command_unit.tscn"
	# TODO: добавить другие типы юнитов по мере расширения
	
	var unit = Handlers.NetworkSpawner.spawn({
		"path": scene_path,
		"resource_info": "null",
		"position": spawn_point,
		"owner_id": player_id
	})
	unit.owner_id = player_id
	print("🏭 СПАВН: Юнит типа '", unit_type, "' создан для игрока ", player_id, " в позиции ", spawn_point)
