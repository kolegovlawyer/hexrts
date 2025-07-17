class_name GameManager extends Node

var game_type = "UNKNOWN"
var map
@onready var units_dict: Dictionary[String, BaseUnit] = {}

# Словарь гексов карты: позиция_гекса -> объект Hex
var hexes_dict: Dictionary = {}

# Ссылка на OverlayMap для обновления тайлов захвата
var overlay_map: TileMapLayer

# Called when the node enters the scene tree for the first time.
func _ready():
	set_multiplayer_authority(1)
	Handlers.GameHandler = self

# Delete handler on scene exit
func _exit_tree():
	Handlers.GameHandler = null

func instantiate_network():
	if game_type.to_lower() == "server":
		add_child(load("res://scenes/server/server.tscn").instantiate())
	else:
		add_child(load("res://scenes/client/client.tscn").instantiate())

func set_map(map_name:String):
	map = map_name
	#var map_obj = load("res://scenes/maps/%s.tscn" % map).instantiate()
	var map_obj = load("res://scenes/maps/test_world_1.tscn").instantiate()
	for map_node in get_node("Map").get_children():
		map_node.queue_free()
	get_node("Map").add_child(map_obj)
	#$MultiplayerSpawner.spawn_path = map_obj
	
	# Инициализируем систему гексов после загрузки карты
	call_deferred("initialize_hexes")

func create_camera(game_type):
	if game_type == 'Client':
		var camera = load("res://scenes/client/camera_2d.tscn").instantiate()
		add_child(camera)
		Handlers.UIHandler.camera = camera
	elif game_type == 'Server':
		var camera = load("res://scenes/client/camera_2d.tscn").instantiate()
		add_child(camera)

func create_ui():
	var ui = load("res://scenes/client/base_ui.tscn").instantiate()
	$"%UICanvasLayer".add_child(ui)

func set_type_server(port:int):
	game_type = "Server"
	
	instantiate_network()
	create_camera(game_type)

	Handlers.NetworkHandler.start_server(port)

func set_type_client(host:String, port:int, nickname:String):
	game_type = "Client"
	
	instantiate_network()
	create_ui()
	create_camera(game_type)
	
	Handlers.NetworkHandler.start_client(host, port, nickname)


	
### UNIT FUNCTIONS ###


func get_unit_by_name(node_name):
	return get_node("Spawnables").get_node_or_null(str(node_name))
	
func get_all_units():
	return get_node("Spawnables").get_children()

### HEX CAPTURE SYSTEM ###

func initialize_hexes() -> void:
	"""
	Инициализирует словарь гексов на основе MainMap (где определены позиции)
	OverlayMap используется только для отображения статуса захвата
	Вызывается и на сервере, и на клиентах
	"""
	var server_or_client = "СЕРВЕР" if is_multiplayer_authority() else "КЛИЕНТ"
	print("🔧 DEBUG: initialize_hexes вызвана на ", server_or_client)
	
	var map_node = get_node("Map").get_child(0) # test_world_1
	print("🔧 DEBUG: map_node найден: ", map_node)
	
	# Ищем MainMap для получения позиций гексов
	var main_map = map_node.get_node("MainMap")
	if not main_map:
		print("⚠️ ГЕКСЫ: MainMap не найден!")
		return
	else:
		print("✅ DEBUG: MainMap найден: ", main_map)
	
	# Ищем OverlayMap для управления визуалом
	overlay_map = map_node.get_node("OverlayMap")
	if not overlay_map:
		print("⚠️ ГЕКСЫ: OverlayMap не найден!")
		return
	else:
		print("✅ DEBUG: OverlayMap найден: ", overlay_map)
		print("📍 DEBUG: OverlayMap position: ", overlay_map.position)
	
	# Получаем все используемые ячейки из MainMap (фактические позиции гексов)
	var used_cells = main_map.get_used_cells()
	print("📊 DEBUG: Найдено гексов в MainMap: ", used_cells.size())
	hexes_dict.clear()
	
	for cell_pos in used_cells:
		# Проверяем есть ли соответствующий тайл в OverlayMap для определения статуса
		var overlay_atlas_coords = overlay_map.get_cell_atlas_coords(cell_pos)
		var initial_team = -1  # По умолчанию нейтральный
		
		print("🎨 DEBUG: Гекс ", cell_pos, " OverlayMap atlas_coords: ", overlay_atlas_coords)
		
		# Определяем команду по atlas координатам OverlayMap
		# (0,0) - команда A (0), (1,0) - команда B (1), (2,0) - нейтральный (-1)
		match overlay_atlas_coords:
			Vector2i(0, 0): initial_team = 0  # Команда A
			Vector2i(1, 0): initial_team = 1  # Команда B  
			Vector2i(2, 0): initial_team = -1 # Нейтральный
			Vector2i(-1, -1): initial_team = -1 # Нет тайла в OverlayMap = нейтральный
			_: initial_team = -1
		
		# Создаем объект гекса
		var hex = preload("res://scripts/singletons/hex.gd").new(cell_pos, initial_team)
		hexes_dict[cell_pos] = hex
		print("🎯 DEBUG: Создан гекс ", cell_pos, " команда ", initial_team)
	
	print("🗺️ ГЕКСЫ: Инициализировано ", hexes_dict.size(), " гексов на ", server_or_client)
	if hexes_dict.size() <= 20:  # Показываем список только если гексов немного
		print("📋 DEBUG: Список всех гексов:")
		for pos in hexes_dict.keys():
			var team_str = ""
			match hexes_dict[pos].team_owner:
				0: team_str = "A"
				1: team_str = "B"
				-1: team_str = "нейтральный"
				_: team_str = str(hexes_dict[pos].team_owner)
			print("  - Гекс ", pos, " команда ", team_str, " (", hexes_dict[pos].team_owner, ")")
	else:
		print("📊 DEBUG: Слишком много гексов для детального отображения (", hexes_dict.size(), ")")

func get_hex_at_position(hex_position: Vector2i):
	"""Возвращает объект гекса по позиции или null если гекса нет"""
	var hex = hexes_dict.get(hex_position, null)
	
	if not hex:
		print("❌ DEBUG: Гекс с координатами ", hex_position, " не найден!")
		print("🔍 DEBUG: Ближайшие гексы:")
		for pos in hexes_dict.keys():
			var distance = hex_position.distance_to(pos)
			if distance <= 3:  # Показываем гексы в радиусе 3 тайлов
				print("  - ", pos, " (расстояние: ", distance, ")")
	
	return hex

func update_hex_overlay(hex_position: Vector2i, team_owner: int) -> void:
	"""
	Обновляет тайл в OverlayMap на СЕРВЕРЕ и отправляет RPC клиентам
	Вызывается только на сервере при захвате гекса
	"""
	if not is_multiplayer_authority():
		print("⚠️ ГЕКСЫ: update_hex_overlay должна вызываться только на сервере!")
		return
		
	if not overlay_map:
		print("⚠️ ГЕКСЫ: OverlayMap не найден для обновления!")
		return
	
	print("🔧 DEBUG: update_hex_overlay (СЕРВЕР) для гекса ", hex_position, " команда ", team_owner)
	
	# Обновляем серверную OverlayMap
	_update_overlay_visual(hex_position, team_owner, team_owner)
	
	# Отправляем RPC всем клиентам о захвате гекса
	sync_hex_capture.rpc(hex_position, team_owner)
	
	var team_str = ""
	match team_owner:
		0: team_str = "A"
		1: team_str = "B"
		-1: team_str = "нейтральный"
		_: team_str = str(team_owner)
	print("📡 ГЕКСЫ: RPC отправлен всем клиентам о захвате гекса ", hex_position, " командой ", team_str)

@rpc("authority", "call_remote", "reliable")
func sync_hex_capture(hex_position: Vector2i, new_owner_team: int) -> void:
	"""
	RPC функция для синхронизации захвата гекса на клиентах
	Каждый клиент обновляет визуал в зависимости от своей команды
	"""
	if is_multiplayer_authority():
		print("⚠️ ГЕКСЫ: sync_hex_capture не должна вызываться на сервере!")
		return
	
	print("📨 КЛИЕНТ: Получен RPC о захвате гекса ", hex_position, " командой ", new_owner_team)
	
	# Обновляем объект гекса в локальном словаре
	var hex = get_hex_at_position(hex_position)
	if hex:
		hex.team_owner = new_owner_team
		print("✅ КЛИЕНТ: Обновлен локальный объект гекса ", hex_position)
	
	# Определяем как отображать гекс с точки зрения этого клиента
	var my_team = -1
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		my_team = Handlers.TeamHandler.my_profile.Team
		print("👤 КЛИЕНТ: Моя команда = ", my_team)
	else:
		print("❌ КЛИЕНТ: TeamHandler или my_profile не найден!")
	
	# Обновляем визуал OverlayMap для клиента
	_update_overlay_visual(hex_position, new_owner_team, my_team)

func _update_overlay_visual(hex_position: Vector2i, hex_owner_team: int, viewer_team: int) -> void:
	"""
	Внутренняя функция для обновления визуала OverlayMap
	hex_owner_team - кому принадлежит гекс
	viewer_team - кто смотрит (для определения союзник/враг)
	"""
	if not overlay_map:
		print("⚠️ ГЕКСЫ: OverlayMap не найден!")
		return
	
	var atlas_coords = Vector2i(2, 0)  # По умолчанию нейтральный
	
	# Определяем atlas координаты с точки зрения viewer_team
	if hex_owner_team == -1:
		# Нейтральный гекс
		atlas_coords = Vector2i(2, 0)
	elif hex_owner_team == viewer_team:
		# Мой гекс (союзный)
		atlas_coords = Vector2i(0, 0)
	else:
		# Вражеский гекс
		atlas_coords = Vector2i(1, 0)
	
	# Обновляем тайл в OverlayMap
	overlay_map.set_cell(hex_position, 0, atlas_coords, 0)
	overlay_map.notify_runtime_tile_data_update()
	
	var owner_str = ""
	var viewer_str = ""
	match hex_owner_team:
		0: owner_str = "A"
		1: owner_str = "B"
		-1: owner_str = "нейтральный"
		_: owner_str = str(hex_owner_team)
	match viewer_team:
		0: viewer_str = "A"
		1: viewer_str = "B"
		-1: viewer_str = "нейтральный"
		_: viewer_str = str(viewer_team)
	
	print("🎨 ВИЗУАЛ: Гекс ", hex_position, " владелец=", owner_str, " наблюдатель=", viewer_str, " atlas=", atlas_coords)

func get_hex_at_world_position(world_position: Vector2):
	"""
	Возвращает гекс по мировым координатам
	Конвертирует мировые координаты в координаты тайла
	"""
	if not overlay_map:
		print("❌ DEBUG: overlay_map равен null в get_hex_at_world_position")
		return null
	
	# Конвертируем мировые координаты в локальные координаты OverlayMap
	var local_position = overlay_map.to_local(world_position)
	var hex_coords = overlay_map.local_to_map(local_position)
	
	print("🗺️ DEBUG: world_position ", world_position, " -> local_position ", local_position, " -> hex_coords ", hex_coords)
	
	var hex = get_hex_at_position(hex_coords)
	print("🎯 DEBUG: hex_coords ", hex_coords, " -> hex ", hex)
	return hex

### LATE JOINER SYNCHRONIZATION ###

func send_full_map_state_to_new_player(player_id: int):
	"""
	Отправляет новому игроку полное состояние всех захваченных гексов
	Вызывается только на сервере при подключении нового игрока
	"""
	if not is_multiplayer_authority():
		print("⚠️ SYNC: send_full_map_state_to_new_player вызвана не на сервере!")
		return
	
	# Проверяем что гексы инициализированы
	if hexes_dict.is_empty():
		print("⚠️ SYNC: Гексы еще не инициализированы, пропускаем синхронизацию")
		return
	
	# Собираем данные о всех захваченных гексах
	var captured_hexes: Array = []
	
	for hex_pos in hexes_dict.keys():
		var hex = hexes_dict[hex_pos]
		if hex.team_owner != -1:  # Только захваченные гексы
			captured_hexes.append({
				"position": hex_pos,
				"team_owner": hex.team_owner,
				"capture_progress": hex.capture_progress,
				"capturing_team": hex.capturing_team,
				"command_units": hex.command_units.map(func(unit): return unit.name if unit else "")
			})
	
	print("📡 SYNC: Отправляем ", captured_hexes.size(), " захваченных гексов игроку ", player_id)
	sync_full_map_state.rpc_id(player_id, captured_hexes)

@rpc("authority", "call_remote", "reliable")
func sync_full_map_state(captured_hexes_data: Array):
	"""
	RPC функция для получения полного состояния карты на клиенте
	Вызывается только на клиентах при подключении к серверу
	"""
	if is_multiplayer_authority():
		print("⚠️ SYNC: sync_full_map_state вызвана на сервере, пропускаем")
		return
	
	print("📥 SYNC: Получили данные о ", captured_hexes_data.size(), " захваченных гексах")
	
	# Применяем состояние к каждому гексу
	for hex_data in captured_hexes_data:
		var hex_pos = hex_data["position"]
		var hex = get_hex_at_position(hex_pos)
		
		if hex:
			hex.team_owner = hex_data["team_owner"]
			hex.capture_progress = hex_data["capture_progress"]
			hex.capturing_team = hex_data["capturing_team"]
			
			# Очищаем старые ссылки на command_units
			hex.command_units.clear()
			
			# Восстанавливаем ссылки на command_units по именам
			for unit_name in hex_data["command_units"]:
				if unit_name and unit_name != "":
					var unit = get_unit_by_name(unit_name)
					if unit:
						hex.command_units.append(unit)
			
			print("✅ SYNC: Обновлен гекс ", hex_pos, " team: ", hex.team_owner, " progress: ", hex.capture_progress)
			
			# Обновляем визуал для этого гекса
			# Получаем команду локального игрока для правильного отображения
			var local_player_team = 0  # По умолчанию команда A
			if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
				local_player_team = Handlers.TeamHandler.my_profile.Team
			_update_overlay_visual(hex_pos, hex.team_owner, local_player_team)
		else:
			print("❌ SYNC: Гекс не найден по позиции ", hex_pos)
	
	print("🎯 SYNC: Синхронизация состояния карты завершена")
