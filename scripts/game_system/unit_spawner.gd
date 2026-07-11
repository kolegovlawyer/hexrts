class_name UnitSpawner extends Node2D

const FOB_SCENE_PATH := "res://prefabs/units/base_fob.tscn"

func _ready():
	Handlers.UnitSpawnHandler = self

func _exit_tree():
	Handlers.UnitSpawnHandler = null

@rpc("any_peer", "reliable")
func spawn_unit_with_validation(
		spawn_point,
		unit_type: String = "base_unit",
		unit_cost: int = 10,
		preset_snapshot: Dictionary = {},
		fob_uid: String = ""
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
			var player_fob = _resolve_player_fob(player_id, spawn_point, fob_uid)
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
		if fob_node is fob and fob_node.owner_id == player_id and not fob_node.is_destroyed:
			return fob_node
	return null


func _find_player_fob_by_uid(player_id: int, fob_uid: String) -> fob:
	if fob_uid == "":
		return null
	var all_fobs = get_tree().get_nodes_in_group("fobs")
	for fob_node in all_fobs:
		if fob_node is fob and fob_node.owner_id == player_id and fob_node.UID == fob_uid:
			if not fob_node.is_destroyed:
				return fob_node
	return null


func _find_nearest_player_fob(player_id: int, world_pos: Vector2) -> fob:
	var best: fob = null
	var best_dist: float = INF
	for fob_node in get_tree().get_nodes_in_group("fobs"):
		if not fob_node is fob:
			continue
		var candidate := fob_node as fob
		if candidate.owner_id != player_id or candidate.is_destroyed:
			continue
		var dist: float = candidate.global_position.distance_squared_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best


func _resolve_player_fob(player_id: int, spawn_point, fob_uid: String = "") -> fob:
	var by_uid := _find_player_fob_by_uid(player_id, fob_uid)
	if by_uid:
		return by_uid
	if typeof(spawn_point) == TYPE_VECTOR2:
		var nearest := _find_nearest_player_fob(player_id, spawn_point)
		if nearest:
			return nearest
	return _find_player_fob(player_id)

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


func deploy_command_as_fob(unit: BaseUnit, snapshot: Dictionary) -> void:
	if not is_multiplayer_authority():
		return
	if not is_instance_valid(unit):
		return
	if Handlers.NetworkSpawner == null:
		return

	var spawn_pos := unit.global_position
	var player_id: int = unit.owner_id
	var team_id := 0
	if unit.owner_team != null:
		team_id = int(unit.owner_team)

	var source_snapshot: Dictionary = snapshot.duplicate(true)
	if source_snapshot.is_empty() and not unit.preset_snapshot.is_empty():
		source_snapshot = unit.preset_snapshot.duplicate(true)

	if unit.has_method("despawn_for_transform"):
		unit.despawn_for_transform()
	else:
		unit.queue_free()

	var spawn_data := {
		"path": FOB_SCENE_PATH,
		"position": spawn_pos,
		"owner_id": player_id,
		"team": team_id,
		"is_starting_fob": false,
		"source_preset_snapshot": source_snapshot,
	}
	var fob_node = Handlers.NetworkSpawner.spawn(spawn_data)
	if fob_node is fob:
		fob_node.owner_id = player_id
		fob_node.team = team_id
		fob_node.is_starting_fob = false
		fob_node.is_network_spawned = true
		fob_node.source_preset_snapshot = source_snapshot
	print("🏭 DEPLOY: FOB создан для игрока ", player_id, " в ", spawn_pos)


func undeploy_fob_as_command(fob_node: fob) -> void:
	if not is_multiplayer_authority():
		return
	if not is_instance_valid(fob_node) or fob_node.is_destroyed:
		return

	var spawn_pos := fob_node.global_position
	var player_id: int = fob_node.owner_id
	var snapshot: Dictionary
	if fob_node.is_starting_fob or fob_node.source_preset_snapshot.is_empty():
		snapshot = UnitPresetBalance.starting_fob_pack_snapshot()
	else:
		snapshot = fob_node.source_preset_snapshot.duplicate(true)

	fob_node.pack_fob()
	_internal_spawn_unit(spawn_pos, "command_unit", player_id, snapshot, false)
	Handlers.dprint("🏭 UNDEPLOY: КШМ создан для игрока %s в %s" % [player_id, spawn_pos])


func promote_unit_to_command(unit: BaseUnit) -> void:
	"""Ранг 5 → КШМ на той же позиции; статы сохраняются, HP/щит пропорционально."""
	if not is_multiplayer_authority():
		return
	if not is_instance_valid(unit) or not (unit is BaseUnitServer):
		return
	var server_unit := unit as BaseUnitServer
	if server_unit.is_command_unit() or server_unit.rank < UnitPresetBalance.RANK_THRESHOLDS.size():
		return
	if server_unit._health <= 0:
		return

	var spawn_pos := server_unit.global_position
	var player_id: int = server_unit.owner_id
	var health_ratio: float = float(server_unit._health) / float(maxi(1, server_unit.max_health))
	var shield_ratio: float = float(server_unit._shield) / float(maxi(1, server_unit.max_shield)) if server_unit.max_shield > 0 else 0.0

	var snapshot: Dictionary = server_unit.preset_snapshot.duplicate(true)
	if snapshot.is_empty():
		snapshot = UnitPresetBalance.default_stats()
	snapshot["is_command"] = true
	if str(snapshot.get("preset_name", "")) == "" or str(snapshot.get("preset_name", "")) == UnitPresetBalance.default_preset_name():
		snapshot["preset_name"] = "КШМ"

	if server_unit.has_method("despawn_for_transform"):
		server_unit.despawn_for_transform()
	else:
		server_unit.queue_free()

	var new_unit = _internal_spawn_unit(spawn_pos, "command_unit", player_id, snapshot, false)
	if new_unit is BaseUnitServer:
		var cmd := new_unit as BaseUnitServer
		cmd._health = clampi(int(round(float(cmd.max_health) * health_ratio)), 1, cmd.max_health)
		cmd.health = cmd._health
		cmd._shield = clampi(int(round(float(cmd.max_shield) * shield_ratio)), 0, cmd.max_shield)
		cmd.shield = cmd._shield
		cmd._lock_experience_as_command()
		cmd.update_health_bar()
		cmd.update_shield_bar()
		cmd._push_vitals_to_clients()
	Handlers.dprint("🎖️ PROMOTE: Юнит игрока %s произведён в КШМ в %s" % [player_id, spawn_pos])


func _internal_spawn_unit(
		spawn_point: Vector2,
		unit_type: String,
		player_id: int,
		preset_snapshot: Dictionary = {},
		apply_scatter: bool = true
	):
	"""
	Внутренняя функция спавна, которая может быть вызвана напрямую с указанием player_id
	Используется как для RPC, так и для отложенного спавна
	"""
	if not is_multiplayer_authority():
		return null
		
	if apply_scatter:
		var random_offset = Vector2(
			randf_range(-50.0, 50.0),
			randf_range(-50.0, 50.0)
		)
		spawn_point += random_offset
	else:
		spawn_point += Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	
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
	Handlers.dprint("🏭 СПАВН: Юнит типа '%s' создан для игрока %s в позиции %s" % [unit_type, player_id, spawn_point])
	return unit
