class_name UnitSpawner extends Node2D

func _ready():
	Handlers.UnitSpawnHandler = self

func _exit_tree():
	Handlers.UnitSpawnHandler = null

@rpc("any_peer", "reliable")
func spawn_unit_with_validation(
		spawn_point,
		unit_type: String = "base_unit",
		unit_cost: int = 10,
		preset_snapshot: Dictionary = {}
	):
	"""
	Новая функция спавна с валидацией очков и отложенным спавном через FOB
	"""
	if is_multiplayer_authority():
		var player_id = multiplayer.get_remote_sender_id()
		print("🎯 SPAWN: Получен запрос спавна от игрока ", player_id, " стоимость: ", unit_cost)

		if not preset_snapshot.is_empty():
			var is_command := bool(preset_snapshot.get("is_command", false))
			if not UnitPresetBalance.validate_spawn_request(preset_snapshot, is_command, unit_cost):
				print("❌ SPAWN: Неверная стоимость пресета для игрока ", player_id)
				reject_spawn.rpc_id(player_id, "Неверные параметры пресета")
				return
			unit_type = "command_unit" if is_command else "base_unit"

		# Валидация очков через GameManager
		if Handlers.GameHandler and Handlers.GameHandler.validate_unit_spawn(player_id, unit_cost):
			# Очки списаны, ищем FOB игрока и добавляем заказ в его очередь
			var player_fob = _find_player_fob(player_id)
			if player_fob:
				var spawn_delay := 3.0
				if not preset_snapshot.is_empty():
					spawn_delay = UnitPresetBalance.calculate_spawn_time(unit_cost)
				player_fob.add_spawn_order(unit_type, unit_cost, player_id, spawn_delay, preset_snapshot)
				print("✅ SPAWN: Заказ добавлен в очередь FOB игрока ", player_id)

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

func _internal_spawn_unit(
		spawn_point: Vector2,
		unit_type: String,
		player_id: int,
		preset_snapshot: Dictionary = {}
	):
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

	var spawn_data: Dictionary = {
		"path": scene_path,
		"resource_info": null,
		"position": spawn_point,
		"owner_id": player_id,
	}

	if not preset_snapshot.is_empty():
		var preset_id := str(preset_snapshot.get("preset_id", "default"))
		var display_name := str(preset_snapshot.get("preset_name", UnitPresetBalance.default_preset_name()))
		var instance_number := UnitPresetManager.next_instance_number(player_id, preset_id)
		var icon_path := UnitIconUtil.get_icon_path_from_stats(
			preset_snapshot, bool(preset_snapshot.get("is_command", false))
		)
		spawn_data["preset_display_name"] = display_name
		spawn_data["preset_instance_number"] = instance_number
		spawn_data["preset_icon_path"] = icon_path
		var range_stat := int(preset_snapshot.get("range", UnitPresetBalance.DEFAULT_STAT))
		spawn_data["vision_radius"] = UnitPresetBalance.to_game_vision_radius(range_stat)

	var unit = Handlers.NetworkSpawner.spawn(spawn_data)
	unit.owner_id = player_id
	if not preset_snapshot.is_empty() and unit.has_method("apply_preset_snapshot"):
		unit.apply_preset_snapshot(preset_snapshot)
	elif unit.has_method("_ensure_unique_vision_shape"):
		# Дефолтные юниты без пресета: дублируем shape немедленно,
		# чтобы не делить CircleShape2D с другими инстансами
		unit._ensure_unique_vision_shape()
	print("🏭 СПАВН: Юнит типа '", unit_type, "' создан для игрока ", player_id, " в позиции ", spawn_point)
