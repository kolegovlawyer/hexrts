class_name GameManager extends Node

var game_type = "UNKNOWN"
var map
@onready var units_dict: Dictionary[String, BaseUnit] = {}

# Словарь гексов карты: позиция_гекса -> объект Hex
var hexes_dict: Dictionary = {}

# Ссылка на OverlayMap для обновления тайлов захвата
var overlay_map: TileMapLayer

### BOT MANAGEMENT SYSTEM ###

# Список активных ботов
var active_bots: Array[Bot] = []

### POINTS SYSTEM ###

# Конфигурация очков
const VICTORY_POINTS_TO_WIN: int = 5000
const BASE_RECRUITMENT_RATE: float = 1.0  # +1 очко найма в секунду
const UNIT_SPAWN_COST: int = 10
# Убираем UNIT_SPAWN_DELAY - теперь это будет в FOB

# Очки игроков: player_id -> {recruitment_points: float, victory_points: float}
var player_points: Dictionary = {}

# Таймер для обновления очков каждую секунду
var points_timer: Timer



# Called when the node enters the scene tree for the first time.
func _ready():
	set_multiplayer_authority(1)
	Handlers.GameHandler = self
	
	# Инициализируем систему очков только на сервере
	if is_multiplayer_authority():
		setup_points_system()
		
		# Добавляем систему диагностики
		var debug_system = preload("res://scripts/debug_system.gd").new()
		add_child(debug_system)

# Delete handler on scene exit
func _exit_tree():
	Handlers.GameHandler = null

### POINTS SYSTEM FUNCTIONS ###

func setup_points_system() -> void:
	"""
	Инициализирует систему очков на сервере
	"""
	Handlers.dprint("🏆 POINTS: Инициализация системы очков на сервере")
	
	# Создаем таймер для обновления очков
	points_timer = Timer.new()
	points_timer.wait_time = 1.0
	points_timer.timeout.connect(_on_points_timer_timeout)
	points_timer.autostart = true
	add_child(points_timer)
	
	# Инициализируем очки для всех подключенных игроков
	for player_id in multiplayer.get_peers():
		_initialize_player_points(player_id)
	
	# Инициализируем очки для сервера (если он играет)
	var server_id = multiplayer.get_unique_id()
	if server_id != 1:  # Сервер имеет ID = 1, но может играть под другим ID
		_initialize_player_points(server_id)
	
	# Подключаемся к сигналам сети для новых игроков
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)

func _initialize_player_points(player_id: int) -> void:
	"""
	Инициализирует очки для нового игрока
	"""
	Handlers.dprint("🎯 GAME DEBUG: Инициализация очков для player_id: ", player_id)
	
	player_points[player_id] = {
		"recruitment_points": 50.0,  # Начальные очки найма (5 юнитов)
		"victory_points": 0.0
	}
	Handlers.dprint("💰 POINTS: Инициализированы очки для игрока ", player_id)
	Handlers.dprint("  - recruitment_points: ", player_points[player_id]["recruitment_points"])
	Handlers.dprint("  - victory_points: ", player_points[player_id]["victory_points"])
	
	# Проверяем является ли это ботом
	var is_bot = _is_player_bot(player_id)
	if is_bot:
		Handlers.dprint("🤖 GAME DEBUG: Игрок ", player_id, " определен как бот")
	
	# Отправляем начальные очки клиенту (только если это не сервер и не бот)
	if player_id != 1 and not is_bot:
		Handlers.dprint("📡 GAME DEBUG: Отправляем начальные очки RPC игроку ", player_id)
		sync_player_points.rpc_id(player_id, player_points[player_id]["recruitment_points"], player_points[player_id]["victory_points"])
	else:
		Handlers.dprint("🚫 GAME DEBUG: Пропускаем RPC для player_id: ", player_id, " (сервер: ", player_id == 1, ", бот: ", is_bot, ")")

func _on_player_connected(player_id: int) -> void:
	"""
	Обработчик подключения нового игрока
	"""
	_initialize_player_points(player_id)

func _on_player_disconnected(player_id: int) -> void:
	"""
	Обработчик отключения игрока
	"""
	if player_points.has(player_id):
		player_points.erase(player_id)
	Handlers.dprint("👋 POINTS: Удалены очки игрока ", player_id)

func _on_points_timer_timeout() -> void:
	"""
	Обновляет очки всех игроков каждую секунду
	"""
	for player_id in player_points.keys():
		# Пропускаем сервер (ID = 1)
		if player_id == 1:
			continue
		_update_player_points(player_id)
	
	# Обрабатываем очередь отложенного спавна
	# _process_delayed_spawn_queue() # Удалено

func _update_player_points(player_id: int) -> void:
	"""
	Обновляет очки конкретного игрока на основе контролируемых гексов
	"""
	if not player_points.has(player_id):
		Handlers.dprint("⚠️ POINTS DEBUG: player_id ", player_id, " не найден в player_points")
		return
	
	# Подсчитываем количество гексов игрока
	var player_hexes_count = _count_player_hexes(player_id)
	
	# Рассчитываем прирост очков найма (базовый + бонус от гексов)
	var recruitment_bonus = _calculate_recruitment_bonus(player_hexes_count)
	var recruitment_gain = BASE_RECRUITMENT_RATE + recruitment_bonus
	player_points[player_id]["recruitment_points"] += recruitment_gain
	
	# Рассчитываем прирост очков победы (только от гексов)
	var victory_gain = _calculate_victory_gain(player_hexes_count)
	player_points[player_id]["victory_points"] += victory_gain
	
	# Проверяем условие победы
	if player_points[player_id]["victory_points"] >= VICTORY_POINTS_TO_WIN:
		_handle_player_victory(player_id)
	
	# Проверяем является ли это ботом
	var is_bot = _is_player_bot(player_id)
	
	# Отправляем обновленные очки клиенту (только если это не бот и не сервер)
	if not is_bot and player_id != 1:
		sync_player_points.rpc_id(player_id, player_points[player_id]["recruitment_points"], player_points[player_id]["victory_points"])
	
	# Логируем только для ботов или каждые 10 секунд для остальных
	if is_bot or Time.get_unix_time_from_system() as int % 10 == 0:
		Handlers.dprint("📊 POINTS: Игрок ", player_id, " (бот: ", is_bot, ") гексы: ", player_hexes_count, " очки найма: +", recruitment_gain, " очки победы: +", victory_gain)

func _count_player_hexes(player_id: int) -> int:
	"""
	Подсчитывает количество гексов, контролируемых игроком
	"""
	var count = 0
	var player_team = _get_player_team(player_id)
	
	if player_team == -1:
		return 0
	
	for hex in hexes_dict.values():
		if hex.team_owner == player_team:
			count += 1
	
	return count

func _get_player_team(player_id: int) -> int:
	"""
	Получает номер команды игрока через существующую систему команд
	"""
	if not Handlers.TeamHandler:
		Handlers.dprint("⚠️ POINTS: TeamHandler не найден!")
		return -1
	
	# Сначала проверяем является ли это ботом
	var is_bot = _is_player_bot(player_id)
	if is_bot:
		# Для ботов получаем команду напрямую из системы ботов
		for bot in active_bots:
			if bot.bot_id == player_id:
				var team_int = int(bot.bot_team)
				Handlers.dprint("🤖 POINTS: Бот ", player_id, " команда ", team_int)
				return team_int
		Handlers.dprint("❌ POINTS: Бот ", player_id, " не найден в active_bots!")
		return -1
	
	# Для обычных игроков используем TeamHandler
	var player = Handlers.TeamHandler.find_player_by_id(player_id)
	if not player:
		Handlers.dprint("⚠️ POINTS: Игрок ", player_id, " не найден в TeamHandler!")
		return -1
	
	# Конвертируем GameTypes.Teams в int
	var team_int = int(player.Team)
	#Handlers.dprint("🏷️ POINTS: Игрок ", player_id, " команда ", team_int)
	return team_int

func _calculate_recruitment_bonus(hexes_count: int) -> float:
	"""
	Рассчитывает бонус очков найма от количества гексов (нелинейный)
	Максимум +10/сек при большом количестве гексов
	"""
	if hexes_count <= 0:
		return 0.0
	
	# Формула: bonus = hexes * 0.02 - hexes^2 * 0.00002
	# При 500 гексах: 10 - 5 = 5/сек
	# При 707 гексах: 14.14 - 10 = 4.14/сек (пик)
	# При 1000 гексах: 20 - 20 = 0/сек
	var bonus = hexes_count * 0.02 - pow(hexes_count, 2) * 0.00002
	return max(0.0, min(10.0, bonus))

func _calculate_victory_gain(hexes_count: int) -> float:
	"""
	Рассчитывает прирост очков победы от количества гексов (убывающая отдача)
	"""
	if hexes_count <= 0:
		return 0.0
	
	# Формула: gain = hexes * 0.5 - hexes^2 * 0.0005
	# При 100 гексах: 50 - 5 = 45/сек
	# При 500 гексах: 250 - 125 = 125/сек (пик)
	# При 1000 гексах: 500 - 500 = 0/сек
	var gain = hexes_count * 0.5 - pow(hexes_count, 2) * 0.0005
	return max(0.0, gain)

func _handle_player_victory(player_id: int) -> void:
	"""
	Обрабатывает победу игрока
	"""
	Handlers.dprint("🏆 VICTORY: Игрок ", player_id, " победил!")
	# TODO: Реализовать логику завершения игры
	announce_victory.rpc(player_id)

@rpc("any_peer", "call_local", "reliable")
func sync_player_points(recruitment_points: float, victory_points: float) -> void:
	"""
	RPC для синхронизации очков с клиентом
	"""
	if is_multiplayer_authority():
		Handlers.dprint("⚠️ POINTS: sync_player_points вызвана на сервере!")
		return
	
	# Обновляем UI на клиенте
	if Handlers.UIHandler:
		Handlers.UIHandler.update_points_display(recruitment_points, victory_points)

@rpc("authority", "call_remote", "reliable")
func announce_victory(winner_player_id: int) -> void:
	"""
	RPC для объявления победы
	"""
	Handlers.dprint("🎉 VICTORY: Игрок ", winner_player_id, " выиграл игру!")
	# TODO: Показать экран победы

### SPAWN VALIDATION SYSTEM ###

func validate_unit_spawn(player_id: int, unit_cost: int = UNIT_SPAWN_COST) -> bool:
	"""
	Проверяет, может ли игрок заспавнить юнита
	Вызывается перед добавлением в очередь отложенного спавна
	"""
	Handlers.dprint("🔍 GAME DEBUG: validate_unit_spawn для player_id: ", player_id, " cost: ", unit_cost)
	Handlers.dprint("  - player_points keys: ", player_points.keys())
	
	if not player_points.has(player_id):
		Handlers.dprint("❌ SPAWN: Игрок ", player_id, " не найден в системе очков")
		return false
	
	var current_points = player_points[player_id]["recruitment_points"]
	Handlers.dprint("💰 GAME DEBUG: Текущие очки игрока ", player_id, ": ", current_points)
	
	if current_points < unit_cost:
		Handlers.dprint("❌ SPAWN: У игрока ", player_id, " недостаточно очков (", current_points, "/", unit_cost, ")")
		return false
	
	# Списываем очки
	player_points[player_id]["recruitment_points"] -= unit_cost
	Handlers.dprint("✅ SPAWN: Списано ", unit_cost, " очков у игрока ", player_id, " (осталось: ", player_points[player_id]["recruitment_points"], ")")
	
	# Проверяем является ли player_id ботом (для отладки RPC ошибки)
	var is_bot = _is_player_bot(player_id)
	
	Handlers.dprint("📡 GAME DEBUG: Отправка RPC player_id: ", player_id, " is_bot: ", is_bot)
	
	# Отправляем обновленные очки клиенту (только если это не бот и не сервер)
	if not is_bot and player_id != 1:
		sync_player_points.rpc_id(player_id, player_points[player_id]["recruitment_points"], player_points[player_id]["victory_points"])
	else:
		Handlers.dprint("🤖 GAME DEBUG: Пропускаем RPC для player_id: ", player_id, " (бот: ", is_bot, ", сервер: ", player_id == 1, ")")
	
	return true

# Удалено: add_delayed_spawn, _process_delayed_spawn_queue, _execute_delayed_spawn

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

	if Handlers.UIHandler:
		Handlers.UIHandler.bind_map_world()

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

### BOT MANAGEMENT FUNCTIONS ###

func _is_player_bot(player_id: int) -> bool:
	"""
	Проверяет является ли игрок ботом
	"""
	for bot in active_bots:
		if bot.bot_id == player_id:
			return true
	return false

func register_bot(bot: Bot) -> void:
	"""
	Регистрирует бота в системе управления
	"""
	Handlers.dprint("📋 GAME DEBUG: Попытка регистрации бота:")
	Handlers.dprint("  - bot_name: ", bot.bot_name if bot.bot_name else "не задано")
	Handlers.dprint("  - bot_id: ", bot.bot_id)
	Handlers.dprint("  - bot_team: ", bot.bot_team)
	Handlers.dprint("  - активных ботов до: ", active_bots.size())
	
	if bot not in active_bots:
		active_bots.append(bot)
		Handlers.dprint("🤖 GAME: Зарегистрирован бот ", bot.bot_name, " (всего ботов: ", active_bots.size(), ")")
		
		# Убеждаемся что у бота есть очки в системе
		if not player_points.has(bot.bot_id):
			Handlers.dprint("💰 GAME DEBUG: Инициализируем очки для нового бота ", bot.bot_id)
			_initialize_player_points(bot.bot_id)
		
		# Подключаем существующие юниты к новому боту
		_connect_existing_units_to_bot(bot)
	else:
		Handlers.dprint("⚠️ GAME DEBUG: Бот уже зарегистрирован")

func unregister_bot(bot: Bot) -> void:
	"""
	Удаляет бота из системы управления
	"""
	if bot in active_bots:
		active_bots.erase(bot)
		
		# Удаляем бота из системы команд
		if Handlers.TeamHandler:
			Handlers.TeamHandler.remove_bot_from_team(bot.bot_id)
		
		Handlers.dprint("👋 GAME: Бот ", bot.bot_name, " удален из системы")

func _connect_existing_units_to_bot(bot: Bot) -> void:
	"""
	Подключает уже существующих юнитов к новому боту
	"""
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit is BaseUnit:
			_connect_unit_signals_to_bots(unit)

func _connect_unit_signals_to_bots(unit: BaseUnit) -> void:
	"""
	Подключает сигналы юнита ко всем активным ботам
	"""
	Handlers.dprint("📡 GAME: Подключение сигналов юнита ", unit.name, " к ботам (", active_bots.size(), " ботов)")
	
	for bot in active_bots:
		Handlers.dprint("  - Подключение к боту ", bot.bot_name)
		
		# Подключаем сигнал атаки
		if not unit.under_attack.is_connected(bot._on_unit_under_attack):
			unit.under_attack.connect(bot._on_unit_under_attack)
			Handlers.dprint("    ✅ Подключен сигнал under_attack")
		
		# Подключаем сигнал начала атаки
		if not unit.attack_started.is_connected(bot._on_attack_started):
			unit.attack_started.connect(bot._on_attack_started)
			Handlers.dprint("    ✅ Подключен сигнал attack_started")
		
		# Подключаем сигнал смерти
		if not unit.unit_died.is_connected(bot._on_unit_died):
			unit.unit_died.connect(bot._on_unit_died)
			Handlers.dprint("    ✅ Подключен сигнал unit_died")

func _on_new_unit_spawned(unit: BaseUnit) -> void:
	"""
	Вызывается при спавне нового юнита для подключения к ботам
	"""
	if is_multiplayer_authority():
		Handlers.dprint("🎯 GAME: Новый юнит заспавнен: ", unit.name, " owner_id: ", unit.owner_id)
		_connect_unit_signals_to_bots(unit)

func register_new_unit(unit: BaseUnit) -> void:
	"""
	Регистрирует новый юнит в системе и подключает к ботам
	Вызывается из _ready() юнита на сервере
	"""
	if is_multiplayer_authority():
		_on_new_unit_spawned(unit)

### HEX CAPTURE SYSTEM ###

func initialize_hexes() -> void:
	"""
	Инициализирует словарь гексов на основе MainMap (где определены позиции)
	OverlayMap используется только для отображения статуса захвата
	Вызывается и на сервере, и на клиентах
	"""
	var server_or_client = "СЕРВЕР" if is_multiplayer_authority() else "КЛИЕНТ"
	Handlers.dprint("🔧 DEBUG: initialize_hexes вызвана на ", server_or_client)
	
	var map_node = get_node("Map").get_child(0) # test_world_1
	Handlers.dprint("🔧 DEBUG: map_node найден: ", map_node)
	
	# Ищем MainMap для получения позиций гексов
	var main_map = map_node.get_node("MainMap")
	if not main_map:
		Handlers.dprint("⚠️ ГЕКСЫ: MainMap не найден!")
		return
	else:
		Handlers.dprint("✅ DEBUG: MainMap найден: ", main_map)
	
	# Ищем OverlayMap для управления визуалом
	overlay_map = map_node.get_node("OverlayMap")
	if not overlay_map:
		Handlers.dprint("⚠️ ГЕКСЫ: OverlayMap не найден!")
		return
	else:
		Handlers.dprint("✅ DEBUG: OverlayMap найден: ", overlay_map)
		Handlers.dprint("📍 DEBUG: OverlayMap position: ", overlay_map.position)
	
	# Получаем все используемые ячейки из MainMap (фактические позиции гексов)
	var used_cells = main_map.get_used_cells()
	Handlers.dprint("📊 DEBUG: Найдено гексов в MainMap: ", used_cells.size())
	hexes_dict.clear()
	
	for cell_pos in used_cells:
		# Проверяем есть ли соответствующий тайл в OverlayMap для определения статуса
		var overlay_atlas_coords = overlay_map.get_cell_atlas_coords(cell_pos)
		var initial_team = -1  # По умолчанию нейтральный
		
		#Handlers.dprint("🎨 DEBUG: Гекс ", cell_pos, " OverlayMap atlas_coords: ", overlay_atlas_coords)
		
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
		#Handlers.dprint("🎯 DEBUG: Создан гекс ", cell_pos, " команда ", initial_team)
	
	Handlers.dprint("🗺️ ГЕКСЫ: Инициализировано ", hexes_dict.size(), " гексов на ", server_or_client)
	if hexes_dict.size() <= 20:  # Показываем список только если гексов немного
		Handlers.dprint("📋 DEBUG: Список всех гексов:")
		for pos in hexes_dict.keys():
			var team_str = ""
			match hexes_dict[pos].team_owner:
				0: team_str = "A"
				1: team_str = "B"
				-1: team_str = "нейтральный"
				_: team_str = str(hexes_dict[pos].team_owner)
			Handlers.dprint("  - Гекс ", pos, " команда ", team_str, " (", hexes_dict[pos].team_owner, ")")
	else:
		Handlers.dprint("📊 DEBUG: Слишком много гексов для детального отображения (", hexes_dict.size(), ")")

func get_hex_at_position(hex_position: Vector2i):
	"""Возвращает объект гекса по позиции или null если гекса нет"""
	var hex = hexes_dict.get(hex_position, null)
	
	if not hex:
		Handlers.dprint("❌ DEBUG: Гекс с координатами ", hex_position, " не найден!")
		Handlers.dprint("🔍 DEBUG: Ближайшие гексы:")
		for pos in hexes_dict.keys():
			var distance = hex_position.distance_to(pos)
			if distance <= 3:  # Показываем гексы в радиусе 3 тайлов
				Handlers.dprint("  - ", pos, " (расстояние: ", distance, ")")
	
	return hex

func update_hex_overlay(hex_position: Vector2i, team_owner: int) -> void:
	"""
	Обновляет тайл в OverlayMap на СЕРВЕРЕ и отправляет RPC клиентам
	Вызывается только на сервере при захвате гекса
	"""
	if not is_multiplayer_authority():
		Handlers.dprint("⚠️ ГЕКСЫ: update_hex_overlay должна вызываться только на сервере!")
		return
		
	if not overlay_map:
		Handlers.dprint("⚠️ ГЕКСЫ: OverlayMap не найден для обновления!")
		return
	
	Handlers.dprint("🔧 DEBUG: update_hex_overlay (СЕРВЕР) для гекса ", hex_position, " команда ", team_owner)
	
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
	Handlers.dprint("📡 ГЕКСЫ: RPC отправлен всем клиентам о захвате гекса ", hex_position, " командой ", team_str)

@rpc("authority", "call_remote", "reliable")
func sync_hex_capture(hex_position: Vector2i, new_owner_team: int) -> void:
	"""
	RPC функция для синхронизации захвата гекса на клиентах
	Каждый клиент обновляет визуал в зависимости от своей команды
	"""
	if is_multiplayer_authority():
		Handlers.dprint("⚠️ ГЕКСЫ: sync_hex_capture не должна вызываться на сервере!")
		return
	
	Handlers.dprint("📨 КЛИЕНТ: Получен RPC о захвате гекса ", hex_position, " командой ", new_owner_team)
	
	# Обновляем объект гекса в локальном словаре
	var hex = get_hex_at_position(hex_position)
	if hex:
		hex.team_owner = new_owner_team
		Handlers.dprint("✅ КЛИЕНТ: Обновлен локальный объект гекса ", hex_position)
	
	# Определяем как отображать гекс с точки зрения этого клиента
	var my_team = -1
	if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
		my_team = Handlers.TeamHandler.my_profile.Team
		Handlers.dprint("👤 КЛИЕНТ: Моя команда = ", my_team)
	else:
		Handlers.dprint("❌ КЛИЕНТ: TeamHandler или my_profile не найден!")
	
	# Обновляем визуал OverlayMap для клиента
	_update_overlay_visual(hex_position, new_owner_team, my_team)

func _update_overlay_visual(hex_position: Vector2i, hex_owner_team: int, viewer_team: int) -> void:
	"""
	Внутренняя функция для обновления визуала OverlayMap
	hex_owner_team - кому принадлежит гекс
	viewer_team - кто смотрит (для определения союзник/враг)
	"""
	if not overlay_map:
		Handlers.dprint("⚠️ ГЕКСЫ: OverlayMap не найден!")
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
	
	Handlers.dprint("🎨 ВИЗУАЛ: Гекс ", hex_position, " владелец=", owner_str, " наблюдатель=", viewer_str, " atlas=", atlas_coords)

func get_hex_at_world_position(world_position: Vector2):
	"""
	Возвращает гекс по мировым координатам
	Конвертирует мировые координаты в координаты тайла
	"""
	if not overlay_map:
		return null
	
	# Конвертируем мировые координаты в локальные координаты OverlayMap
	var local_position = overlay_map.to_local(world_position)
	var hex_coords = overlay_map.local_to_map(local_position)
	
	var hex = get_hex_at_position(hex_coords)
	return hex

### LATE JOINER SYNCHRONIZATION ###

func send_full_map_state_to_new_player(player_id: int):
	"""
	Отправляет новому игроку полное состояние всех захваченных гексов
	И НАЧАЛЬНЫЕ ОЧКИ
	Вызывается только на сервере при подключении нового игрока
	"""
	if not is_multiplayer_authority():
		Handlers.dprint("⚠️ SYNC: send_full_map_state_to_new_player вызвана не на сервере!")
		return
	
	# Проверяем является ли это ботом
	var is_bot = _is_player_bot(player_id)
	Handlers.dprint("🔍 SYNC DEBUG: send_full_map_state для player_id: ", player_id, " is_bot: ", is_bot)
	
	# Отправляем очки новому игроку (только если не бот)
	if player_points.has(player_id) and not is_bot:
		sync_player_points.rpc_id(player_id, player_points[player_id]["recruitment_points"], player_points[player_id]["victory_points"])
		Handlers.dprint("📡 SYNC: Отправлены очки игроку ", player_id)
	elif is_bot:
		Handlers.dprint("🤖 SYNC: Пропускаем отправку очков боту ", player_id)
	
	# Проверяем что гексы инициализированы
	if hexes_dict.is_empty():
		Handlers.dprint("⚠️ SYNC: Гексы еще не инициализированы, пропускаем синхронизацию")
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
	
	# Отправляем состояние карты (ботам тоже нужно знать состояние карты)
	Handlers.dprint("📡 SYNC: Отправляем ", captured_hexes.size(), " захваченных гексов игроку ", player_id)
	sync_full_map_state.rpc_id(player_id, captured_hexes)

@rpc("authority", "call_remote", "reliable")
func sync_full_map_state(captured_hexes_data: Array):
	"""
	RPC функция для получения полного состояния карты на клиенте
	Вызывается только на клиентах при подключении к серверу
	"""
	if is_multiplayer_authority():
		Handlers.dprint("⚠️ SYNC: sync_full_map_state вызвана на сервере, пропускаем")
		return
	
	Handlers.dprint("📥 SYNC: Получили данные о ", captured_hexes_data.size(), " захваченных гексах")
	
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
			
			Handlers.dprint("✅ SYNC: Обновлен гекс ", hex_pos, " team: ", hex.team_owner, " progress: ", hex.capture_progress)
			
			# Обновляем визуал для этого гекса
			# Получаем команду локального игрока для правильного отображения
			var local_player_team = 0  # По умолчанию команда A
			if Handlers.TeamHandler and Handlers.TeamHandler.my_profile:
				local_player_team = Handlers.TeamHandler.my_profile.Team
			_update_overlay_visual(hex_pos, hex.team_owner, local_player_team)
		else:
			Handlers.dprint("❌ SYNC: Гекс не найден по позиции ", hex_pos)
	
	Handlers.dprint("🎯 SYNC: Синхронизация состояния карты завершена")
