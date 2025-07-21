class_name Bot extends Node

## СИСТЕМА ИСКУССТВЕННОГО ИНТЕЛЛЕКТА
# Управляет поведением ботов в игре, не изменяя существующий код
# Использует signals и groups для интеграции с игровыми системами

# Сигналы для взаимодействия с игровыми системами
signal unit_under_attack(attacker: BaseUnit, victim: BaseUnit)
signal hex_capture_started(hex_position: Vector2i, team: int)
signal emergency_retreat_needed(unit: BaseUnit)

# Константы поведения
const BOT_TEAM_OFFSET: int = 100  # Смещение ID для ботов (100+)
const DECISION_INTERVAL: float = 2.0  # Интервал принятия решений в секундах
const UNIT_SEARCH_RADIUS: float = 500.0  # Радиус поиска союзных юнитов для помощи
const RETREAT_DISTANCE: float = 300.0  # Дистанция отступления
const SAFE_ZONE_RADIUS: float = 200.0  # Радиус безопасной зоны

# Профиль бота
var bot_id: int
var bot_team: GameTypes.Teams
var bot_name: String

# Состояние ботов
var bot_units: Array[BaseUnit] = []  # Все юниты бота
var command_units: Array[CommandUnit] = []  # Командные юниты бота
var controlled_hexes: Array[Vector2i] = []  # Контролируемые гексы
var target_hexes: Array[Vector2i] = []  # Цели для захвата

# Стратегическое планирование
var strategy_mode: String = "expand"  # "expand", "defend", "attack"
var last_decision_time: float = 0.0
var emergency_units: Dictionary = {}  # Юниты в аварийном режиме

# Таймеры
var decision_timer: Timer
var spawn_timer: Timer

func _ready() -> void:
	# Добавляем бота в группу для управления
	add_to_group("bots")
	add_to_group("ai_players")
	
	print("🤖 BOT: Инициализация бота ", bot_name, " (ID: ", bot_id, ", команда: ", bot_team, ")")
	
	# Настройка таймеров
	_setup_timers()
	
	# Подключение к игровым сигналам
	_connect_game_signals()
	
	# Инициализация стратегии
	call_deferred("_initialize_strategy")

func initialize_bot(id: int, team: GameTypes.Teams, name: String) -> void:
	"""
	Инициализирует серверного бота с заданными параметрами
	"""
	bot_id = id
	bot_team = team
	bot_name = name
	
	print("🎯 BOT: Серверный бот ", bot_name, " настроен:")
	print("  - bot_id: ", bot_id)
	print("  - bot_team: ", team, " (", int(team), ")")
	print("  - is_multiplayer_authority(): ", is_multiplayer_authority())
	
	# Серверный бот должен работать только на сервере
	if not is_multiplayer_authority():
		print("❌ BOT ERROR: Попытка создать бота не на сервере!")
		queue_free()
		return

func _setup_timers() -> void:
	"""
	Настраивает таймеры для принятия решений
	"""
	# Таймер для основных решений
	decision_timer = Timer.new()
	decision_timer.wait_time = DECISION_INTERVAL
	decision_timer.timeout.connect(_make_strategic_decisions)
	decision_timer.autostart = true
	add_child(decision_timer)
	
	# Таймер для проверки спавна
	spawn_timer = Timer.new()
	spawn_timer.wait_time = 1.0
	spawn_timer.timeout.connect(_check_spawn_opportunity)
	spawn_timer.autostart = true
	add_child(spawn_timer)

func _connect_game_signals() -> void:
	"""
	Подключается к игровым сигналам для реактивного поведения
	"""
	# Подключение к системе боя (обнаружение атак)
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit.has_signal("under_attack"):
			unit.under_attack.connect(_on_unit_under_attack)

func _initialize_strategy() -> void:
	"""
	Инициализирует стратегию бота после полной загрузки игры
	"""
	print("🎯 BOT DEBUG: Инициализация стратегии для бота ", bot_name, " (ID: ", bot_id, ")")
	
	await get_tree().process_frame  # Ждем один кадр для инициализации всех систем
	
	print("🔍 BOT DEBUG: Поиск FOB после ожидания...")
	
	# Ищем стартовый FOB бота
	var bot_fob = _find_bot_fob()
	if bot_fob:
		print("✅ BOT: Найден FOB бота в позиции ", bot_fob.global_position)
		
		# Спавним первый командный юнит как только есть очки
		print("🚀 BOT DEBUG: Запускаем _attempt_initial_spawn")
		call_deferred("_attempt_initial_spawn")
	else:
		print("❌ BOT: FOB бота не найден!")
		print("  - Доступные FOB:")
		var all_fobs = get_tree().get_nodes_in_group("fobs")
		for fob in all_fobs:
			print("    - FOB owner_id: ", fob.owner_id, " team: ", fob.team, " position: ", fob.global_position)

### СТРАТЕГИЧЕСКОЕ ПЛАНИРОВАНИЕ ###

func _make_strategic_decisions() -> void:
	"""
	Основной цикл принятия стратегических решений
	"""
	if not is_multiplayer_authority():
		return
	
	print("🧠 BOT: Принятие стратегических решений для бота ", bot_name)
	
	# Обновляем информацию о состоянии
	_update_bot_state()
	
	# Определяем текущую стратегию
	_evaluate_strategy()
	
	print("  - Текущая стратегия: ", strategy_mode)
	print("  - Юнитов всего: ", bot_units.size())
	print("  - Командных юнитов: ", command_units.size())
	
	# ОТЛАДКА: Показываем состояние юнитов бота
	for unit in bot_units:
		if is_instance_valid(unit):
			print("    * Юнит ", unit.name, " состояние: ", BaseUnit.UNIT_STATES.keys()[unit.unit_state], " приказов: ", unit.orders.size())
	
	# Выполняем действия в зависимости от стратегии
	match strategy_mode:
		"expand":
			print("  - Выполняем стратегию расширения")
			_execute_expansion_strategy()
		"defend":
			print("  - Выполняем стратегию обороны")
			_execute_defense_strategy()
		"attack":
			print("  - Выполняем стратегию атаки")
			_execute_attack_strategy()
	
	# Проверяем аварийные ситуации
	_handle_emergency_situations()

func _update_bot_state() -> void:
	"""
	Обновляет информацию о состоянии бота
	"""
	# Обновляем список юнитов бота
	bot_units.clear()
	command_units.clear()
	
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit is BaseUnit and unit.owner_id == bot_id:
			bot_units.append(unit)
			if unit is CommandUnit:
				command_units.append(unit)
	
	# Обновляем контролируемые гексы
	_update_controlled_hexes()

func _update_controlled_hexes() -> void:
	"""
	Обновляет список контролируемых ботом гексов
	"""
	controlled_hexes.clear()
	
	if not Handlers.GameHandler:
		return
	
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[hex_pos]
		if hex.team_owner == int(bot_team):
			controlled_hexes.append(hex_pos)

func _evaluate_strategy() -> void:
	"""
	Определяет текущую стратегию на основе состояния игры
	"""
	var enemy_threat_level = _assess_enemy_threat()
	var hex_control_ratio = _calculate_hex_control_ratio()
	
	if enemy_threat_level > 0.7:
		strategy_mode = "defend"
	elif hex_control_ratio < 0.3:
		strategy_mode = "expand"
	else:
		strategy_mode = "attack"
	
	# Отладочная информация (только при смене стратегии)
	if strategy_mode != "expand":  # Чтобы не спамить в логи
		print("🧠 BOT: Стратегия изменена на ", strategy_mode, " (угроза: ", enemy_threat_level, ", контроль: ", hex_control_ratio, ")")

### ВЫПОЛНЕНИЕ СТРАТЕГИЙ ###

func _execute_expansion_strategy() -> void:
	"""
	Выполняет стратегию расширения (захват новых гексов)
	"""
	# Собираем всех свободных командных юнитов
	var idle_command_units = []
	for command_unit in command_units:
		if _is_unit_idle(command_unit):
			idle_command_units.append(command_unit)
	
	print("📋 BOT: Свободных командных юнитов: ", idle_command_units.size())
	
	# Назначаем уникальные гексы каждому юниту
	var assigned_hexes: Array[Vector2i] = []
	var assigned_command_units = 0
	
	for command_unit in idle_command_units:
		# Ищем ближайший НЕ назначенный гекс
		var nearest_hex = _find_nearest_available_hex_for_unit(command_unit, assigned_hexes)
		if nearest_hex != Vector2i.MAX:
			assigned_hexes.append(nearest_hex)  # Резервируем гекс
			print("🎯 BOT: ", command_unit.name, " → уникальный гекс ", nearest_hex)
			_order_hex_capture(command_unit, nearest_hex)
			assigned_command_units += 1
		else:
			print("🚫 BOT: Для ", command_unit.name, " не найдены свободные гексы")
	
	print("📊 BOT КОМАНДНЫЕ: ", assigned_command_units, "/", idle_command_units.size(), " получили задания")
	
	# Отправляем обычные юниты защищать командные или базу
	_assign_defense_tasks_to_base_units()

func _execute_defense_strategy() -> void:
	"""
	Выполняет оборонительную стратегию
	"""
	# Группируем юнитов возле контролируемых гексов
	for hex_pos in controlled_hexes:
		var defenders = _get_units_near_hex(hex_pos, 100.0)
		if defenders.size() < 2:  # Недостаточно защитников
			_call_reinforcements_to_hex(hex_pos)

func _execute_attack_strategy() -> void:
	"""
	Выполняет атакующую стратегию
	"""
	# Ищем вражеские гексы для атаки
	var enemy_hexes = _find_enemy_hexes()
	
	# Собираем группы для атаки
	var available_units = _get_available_attack_units()
	if available_units.size() >= 3 and enemy_hexes.size() > 0:
		var target_hex = enemy_hexes[0]  # Ближайший вражеский гекс
		_coordinate_group_attack(available_units, target_hex)

### УПРАВЛЕНИЕ СПАВНОМ ###

func _check_spawn_opportunity() -> void:
	"""
	Проверяет возможность спавна новых юнитов
	"""
	if not is_multiplayer_authority():
		return
	
	# НОВАЯ ПРОВЕРКА: Не спавним если есть застрявшие юниты
	var stuck_units = 0
	for unit in bot_units:
		if unit.unit_state == BaseUnit.UNIT_STATES.IDLE and unit.orders.size() > 0:
			stuck_units += 1
	
	if stuck_units > 0:
		print("⏸️ BOT: Отменяем спавн - есть ", stuck_units, " застрявших юнитов")
		return
	
	# Умная отладка только каждые 10 секунд
	var current_time = Time.get_unix_time_from_system()
	if not has_meta("last_spawn_check_log") or (current_time - get_meta("last_spawn_check_log")) > 10:
		set_meta("last_spawn_check_log", current_time)
		print("⏰ BOT: Проверка возможности спавна для бота ", bot_name)
		print("  - Текущих юнитов: ", bot_units.size())
		print("  - Командных юнитов: ", command_units.size())
	
	# Получаем текущие очки найма бота
	var current_points = _get_bot_recruitment_points()
	
	if current_points < 10:  # Недостаточно очков для базового юнита
		return
	
	# Определяем что спавнить
	var unit_type = _decide_unit_to_spawn()
	
	if unit_type:
		print("🎯 BOT: ", bot_name, " решил заспавнить ", unit_type, " (очки: ", current_points, ")")
		_attempt_spawn_unit(unit_type)

func _attempt_initial_spawn() -> void:
	"""
	Пытается заспавнить первый командный юнит
	"""
	print("🚀 BOT DEBUG: Начинаем попытки начального спавна для бота ", bot_name)
	
	var attempts = 0
	while attempts < 10:  # Максимум 10 попыток с интервалом
		await get_tree().create_timer(1.0).timeout
		attempts += 1
		
		print("🔄 BOT DEBUG: Попытка спавна #", attempts, " для бота ", bot_name)
		var current_points = _get_bot_recruitment_points()
		if current_points >= 10:
			print("💰 BOT: Достаточно очков (", current_points, ") для первого спавна")
			_attempt_spawn_unit("command_unit")
			break
		else:
			print("⏰ BOT: Ожидание очков для спавна... (", current_points, "/10), попытка ", attempts)
	
	if attempts >= 10:
		print("❌ BOT DEBUG: Не удалось заспавнить первый юнит за 10 попыток")

func _decide_unit_to_spawn() -> String:
	"""
	Решает какой тип юнита заспавнить
	"""
	var points = _get_bot_recruitment_points()
	
	# Приоритет командным юнитам если их мало
	if command_units.size() < 2 and points >= 10:
		return "command_unit"
	
	# Обычные юниты для поддержки
	if points >= 10:
		return "base_unit"
	
	return ""

func _attempt_spawn_unit(unit_type: String) -> void:
	"""
	Пытается заспавнить юнит через FOB
	"""
	print("🏭 BOT DEBUG: Попытка спавна ", unit_type, " для бота ", bot_name, " (ID: ", bot_id, ")")
	
	var bot_fob = _find_bot_fob()
	if not bot_fob:
		print("❌ BOT: FOB не найден для спавна")
		print("  - Доступные FOB: ")
		var all_fobs = get_tree().get_nodes_in_group("fobs")
		for fob in all_fobs:
			print("    - FOB owner_id: ", fob.owner_id, " position: ", fob.global_position)
		return
	
	print("✅ BOT DEBUG: FOB найден, owner_id: ", bot_fob.owner_id)
	
	# Проверяем валидность спавна через GameManager
	if not Handlers.GameHandler:
		print("❌ BOT DEBUG: GameHandler не найден для валидации спавна")
		return
		
	print("🔍 BOT DEBUG: Вызываем validate_unit_spawn для bot_id: ", bot_id)
	if Handlers.GameHandler.validate_unit_spawn(bot_id, 10):
		# Добавляем заказ в очередь FOB
		print("✅ BOT DEBUG: Валидация прошла, добавляем заказ в FOB")
		bot_fob.add_spawn_order(unit_type, 10, bot_id)
		print("✅ BOT: Заказан спавн ", unit_type, " для бота ", bot_name)
	else:
		print("❌ BOT: Спавн не прошел валидацию для bot_id: ", bot_id)

### ТАКТИЧЕСКОЕ УПРАВЛЕНИЕ ###

func _on_unit_under_attack(attacker: BaseUnit, victim: BaseUnit) -> void:
	"""
	Обрабатывает сигнал о том, что юнит подвергается атаке
	"""
	if not victim or victim.owner_id != bot_id:
		return  # Не наш юнит
	
	# Если это командный юнит - планируем отступление
	if victim is CommandUnit:
		_plan_command_unit_retreat(victim, attacker)
	
	# Вызываем подкрепления
	_call_emergency_reinforcements(victim, attacker)

func _on_attack_started(attacker: BaseUnit, target: BaseUnit) -> void:
	"""
	Обрабатывает сигнал о начале атаки
	Используется для стратегического планирования
	"""
	# Пока просто логируем для отладки
	if attacker and target:
		# Проверяем участвует ли бот в этой атаке
		if attacker.owner_id == bot_id:
			print("⚔️ BOT: Наш юнит ", attacker.name, " атакует ", target.name)
		elif target.owner_id == bot_id:
			print("🛡️ BOT: Наш юнит ", target.name, " подвергается атаке от ", attacker.name)

func _on_unit_died(dead_unit: BaseUnit) -> void:
	"""
	Обрабатывает сигнал смерти юнита
	"""
	if not dead_unit:
		return
	
	# Удаляем из наших списков если это наш юнит
	if dead_unit.owner_id == bot_id:
		if dead_unit in bot_units:
			bot_units.erase(dead_unit)
		if dead_unit in command_units:
			command_units.erase(dead_unit)
		print("💀 BOT: Потерян юнит ", dead_unit.name, " (осталось юнитов: ", bot_units.size(), ")")
		
		# Если потеряли командный юнит - меняем стратегию на оборонительную
		if dead_unit is CommandUnit and command_units.size() == 0:
			strategy_mode = "defend"
			print("🚨 BOT: Потерян последний командный юнит! Переход к обороне.")
	else:
		# Вражеский юнит уничтожен - хорошие новости
		print("✅ BOT: Уничтожен вражеский юнит ", dead_unit.name)

func _plan_command_unit_retreat(command_unit: CommandUnit, attacker: BaseUnit) -> void:
	"""
	Планирует отступление командного юнита в безопасную зону
	"""
	var safe_position = _find_safe_retreat_position(command_unit, attacker)
	if safe_position != Vector2.ZERO:
		# Отдаем приказ на отступление
		command_unit.rpc_id(1, "add_order", safe_position, true)
		print("🏃 BOT: Командный юнит отступает в безопасную зону")
	else:
		print("⚠️ BOT: Безопасная зона для отступления не найдена")

func _call_emergency_reinforcements(victim: BaseUnit, attacker: BaseUnit) -> void:
	"""
	Вызывает ближайшие юниты на помощь атакуемому
	"""
	var nearby_units = _find_nearby_friendly_units(victim.global_position, UNIT_SEARCH_RADIUS)
	
	var reinforcements_sent = 0
	for unit in nearby_units:
		if unit != victim and _is_unit_available_for_help(unit):
			# Отдаем приказ атаковать врага
			if attacker and is_instance_valid(attacker):
				# ИСПРАВЛЕНИЕ: Используем прямой вызов для ботов на сервере
				if is_multiplayer_authority():
					unit.add_order(attacker.UID, true)
				else:
					unit.rpc_id(1, "add_order", attacker.UID, true)
				
				reinforcements_sent += 1
	
	# Логируем только результат
	if reinforcements_sent > 0:
		print("🚁 BOT: Отправлено подкрепление к позиции ", victim.global_position)
	
	# Если командный юнит нуждается в защите, логируем это
	if victim is CommandUnit and reinforcements_sent > 0:
		print("🚨 BOT: Командный юнит нуждается в защите!")

### ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ###

func _find_bot_fob() -> Node:
	"""
	Находит FOB принадлежащий боту
	"""
	var fobs = get_tree().get_nodes_in_group("fobs")
	for fob in fobs:
		if fob.owner_id == bot_id:
			return fob
	return null

func _get_bot_recruitment_points() -> float:
	"""
	Получает текущие очки найма бота
	"""
	if not Handlers.GameHandler:
		if not has_meta("no_gamehandler_logged"):
			set_meta("no_gamehandler_logged", true)
			print("❌ BOT DEBUG: GameHandler не найден")
		return 0.0
	
	if not Handlers.GameHandler.player_points.has(bot_id):
		if not has_meta("no_points_logged"):
			set_meta("no_points_logged", true)
			print("❌ BOT DEBUG: bot_id ", bot_id, " не найден в player_points")
			print("  - Доступные player_points keys: ", Handlers.GameHandler.player_points.keys())
		return 0.0
	
	var points = Handlers.GameHandler.player_points[bot_id]["recruitment_points"]
	return points

func _get_controlled_hexes() -> Array[Vector2i]:
	"""
	Возвращает список координат гексов, контролируемых ботом
	"""
	var controlled_hexes: Array[Vector2i] = []
	
	if not Handlers.GameHandler or not Handlers.GameHandler.hexes_dict:
		return controlled_hexes
	
	var bot_team_int = int(bot_team)
	
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[hex_pos]
		if hex.team_owner == bot_team_int:
			controlled_hexes.append(hex_pos)
	
	return controlled_hexes

func _find_nearby_neutral_hexes() -> Array[Vector2i]:
	"""
	Находит ближайшие нейтральные гексы для захвата
	"""
	var neutral_hexes: Array[Vector2i] = []
	
	if not Handlers.GameHandler:
		return neutral_hexes
	
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[hex_pos]
		if hex.team_owner == -1:  # Нейтральный гекс
			neutral_hexes.append(hex_pos)
	
	# Сортируем по расстоянию до наших юнитов (упрощенно)
	return neutral_hexes.slice(0, 5)  # Возвращаем первые 5

func _find_nearest_available_hex_for_unit(unit: BaseUnit, assigned_hexes: Array[Vector2i]) -> Vector2i:
	"""
	Ищет ближайший нейтральный гекс для конкретного юнита, исключая уже назначенные
	"""
	if not Handlers.GameHandler or not Handlers.GameHandler.overlay_map:
		return Vector2i.MAX
	
	var unit_world_pos = unit.global_position
	var nearest_hex = Vector2i.MAX
	var min_distance = INF
	
	# Проходим по всем гексам на карте
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[hex_pos]
		
		# Проверяем что гекс нейтральный И не назначен другому юниту
		if hex.team_owner == -1 and hex_pos not in assigned_hexes:
			# Конвертируем координаты гекса в мировые
			var hex_world_pos = Handlers.GameHandler.overlay_map.map_to_local(hex_pos)
			hex_world_pos = Handlers.GameHandler.overlay_map.to_global(hex_world_pos)
			
			# Вычисляем расстояние
			var distance = unit_world_pos.distance_to(hex_world_pos)
			if distance < min_distance:
				min_distance = distance
				nearest_hex = hex_pos
	
	if nearest_hex != Vector2i.MAX:
		print("📍 BOT: Для ", unit.name, " ближайший СВОБОДНЫЙ гекс ", nearest_hex, " (расстояние: ", int(min_distance), ")")
	else:
		print("🚫 BOT: Для ", unit.name, " не найдено свободных гексов (назначено: ", assigned_hexes.size(), ")")
	
	return nearest_hex

func _assign_defense_tasks_to_base_units() -> void:
	"""
	Назначает задачи защиты обычным юнитам (BaseUnit)
	"""
	var idle_base_units = []
	var assigned_defenders = 0
	
	# Собираем свободные обычные юниты
	for unit in bot_units:
		if unit is BaseUnit and not (unit is CommandUnit):
			if _is_unit_idle(unit):
				idle_base_units.append(unit)
	
	if idle_base_units.is_empty():
		return
	
	# ИСПРАВЛЕНИЕ: Отправляем защитников к СТАТИЧНЫМ позициям, а не к движущимся юнитам
	# Ищем захваченные гексы для патрулирования
	var controlled_hexes = _get_controlled_hexes()
	
	if controlled_hexes.size() > 0:
		# Распределяем защитников по захваченным гексам
		for i in range(idle_base_units.size()):
			var defender = idle_base_units[i]
			var hex_index = i % controlled_hexes.size()  # Равномерное распределение
			var hex_pos = controlled_hexes[hex_index]
			
			# Конвертируем координаты гекса в мировые
			var hex_world_pos = Handlers.GameHandler.overlay_map.map_to_local(hex_pos)
			hex_world_pos = Handlers.GameHandler.overlay_map.to_global(hex_world_pos)
			
			# Добавляем случайное смещение чтобы защитники не стояли в одной точке
			var patrol_offset = Vector2(randf_range(-60, 60), randf_range(-60, 60))
			var patrol_position = hex_world_pos + patrol_offset
			
			_order_unit_move(defender, patrol_position)
			assigned_defenders += 1
	else:
		# Если нет захваченных гексов, патрулируем вокруг FOB
		var bot_fob = _find_bot_fob()
		if bot_fob:
			for defender in idle_base_units:
				var patrol_position = bot_fob.global_position + Vector2(randf_range(-120, 120), randf_range(-120, 120))
				_order_unit_move(defender, patrol_position)
				assigned_defenders += 1
	
	# Логируем только общий результат без спама
	if assigned_defenders > 0:
		print("🛡️ BOT: Назначено ", assigned_defenders, " защитников на оборону")

func _order_unit_move(unit: BaseUnit, world_position: Vector2) -> void:
	"""
	Отдает приказ любому юниту двигаться к позиции
	"""
	if is_multiplayer_authority():
		unit.add_order(world_position, true)
	else:
		unit.rpc_id(1, "add_order", world_position, true)

func _find_nearby_friendly_units(position: Vector2, radius: float) -> Array[BaseUnit]:
	"""
	Находит дружественные юниты в радиусе от позиции
	"""
	var nearby_units: Array[BaseUnit] = []
	
	for unit in bot_units:
		if unit.global_position.distance_to(position) <= radius:
			nearby_units.append(unit)
	
	return nearby_units

func _find_safe_retreat_position(unit: BaseUnit, threat: BaseUnit) -> Vector2:
	"""
	Находит безопасную позицию для отступления
	"""
	# Направление от угрозы
	var threat_direction = unit.global_position.direction_to(threat.global_position)
	var retreat_direction = -threat_direction
	
	# Пытаемся найти позицию в радиусе союзных юнитов
	var retreat_position = unit.global_position + retreat_direction * RETREAT_DISTANCE
	
	# Проверяем что позиция в пределах карты (упрощенная проверка)
	# TODO: Добавить более сложную логику проверки безопасности
	
	return retreat_position

func _is_unit_idle(unit: BaseUnit) -> bool:
	"""
	Проверяет свободен ли юнит для выполнения новых заданий
	"""
	return unit.orders.is_empty() and unit.unit_state == BaseUnit.UNIT_STATES.IDLE

func _is_unit_available_for_help(unit: BaseUnit) -> bool:
	"""
	Проверяет может ли юнит прийти на помощь
	"""
	# Юнит свободен или выполняет некритичные задачи
	return _is_unit_idle(unit) or unit.unit_state != BaseUnit.UNIT_STATES.ATTACKING

func _order_hex_capture(command_unit: CommandUnit, hex_position: Vector2i) -> void:
	"""
	Отдает приказ командному юниту захватить гекс
	"""
	if not Handlers.GameHandler or not Handlers.GameHandler.overlay_map:
		print("❌ BOT: GameHandler или overlay_map не найден")
		return
	
	# Конвертируем координаты гекса в мировые координаты
	var world_position = Handlers.GameHandler.overlay_map.map_to_local(hex_position)
	world_position = Handlers.GameHandler.overlay_map.to_global(world_position)
	
	# УМНАЯ ПРОВЕРКА: Не отправляем приказ если юнит уже очень близко к гексу
	var distance_to_hex = command_unit.global_position.distance_to(world_position)
	if distance_to_hex < 40.0:  # Если юнит уже на гексе
		print("🚫 BOT: ", command_unit.name, " уже на гексе ", hex_position, " (расстояние: ", int(distance_to_hex), ")")
		return
	
	# Отладка: текущее состояние юнита
	print("🔍 BOT DEBUG: ", command_unit.name, " ПЕРЕД приказом:")
	print("  - Позиция: ", command_unit.global_position)
	print("  - Состояние: ", command_unit.unit_state)
	print("  - Приказов в очереди: ", command_unit.orders.size())
	print("  - Гекс: ", hex_position, " → мировые: ", world_position)
	print("  - Расстояние: ", int(distance_to_hex))
	
	# ИСПРАВЛЕНИЕ: Бот на сервере - вызываем функцию напрямую
	if is_multiplayer_authority():
		command_unit.add_order(world_position, true)
	else:
		# Если бот на клиенте (не используется сейчас)
		command_unit.rpc_id(1, "add_order", world_position, true)
	
	print("🎯 BOT: ", command_unit.name, " → гекс ", hex_position, " (расстояние: ", int(distance_to_hex), ")")
	
	# Отладка: состояние юнита ПОСЛЕ приказа
	call_deferred("_debug_unit_state_after_order", command_unit)

func _debug_unit_state_after_order(command_unit: CommandUnit) -> void:
	"""
	Отладочная функция для проверки состояния юнита после получения приказа
	"""
	# Проверяем что юнит не застрял - это главное
	if command_unit.unit_state == BaseUnit.UNIT_STATES.IDLE and command_unit.orders.size() > 0:
		print("⚠️ BOT WARNING: Юнит ", command_unit.name, " застрял в IDLE с приказами!")
		print("  - Состояние: ", command_unit.unit_state)
		print("  - Приказов в очереди: ", command_unit.orders.size())
		if command_unit.orders.size() > 0:
			print("  - Первый приказ: ", command_unit.orders[0])

### ФУНКЦИИ ОЦЕНКИ СИТУАЦИИ ###

func _assess_enemy_threat() -> float:
	"""
	Оценивает уровень вражеской угрозы (0.0 - 1.0)
	"""
	# Упрощенная оценка: соотношение вражеских к союзным юнитам
	var enemy_units = _count_enemy_units_nearby()
	var friendly_units = bot_units.size()
	
	if friendly_units == 0:
		return 1.0
	
	return min(float(enemy_units) / friendly_units, 1.0)

func _calculate_hex_control_ratio() -> float:
	"""
	Вычисляет долю контролируемых гексов (0.0 - 1.0)
	"""
	if not Handlers.GameHandler:
		return 0.0
	
	var total_hexes = Handlers.GameHandler.hexes_dict.size()
	if total_hexes == 0:
		return 0.0
	
	return float(controlled_hexes.size()) / total_hexes

func _count_enemy_units_nearby() -> int:
	"""
	Подсчитывает количество вражеских юнитов рядом с нашими
	"""
	var enemy_count = 0
	var all_units = get_tree().get_nodes_in_group("units")
	
	for unit in all_units:
		if unit is BaseUnit and unit.owner_team != bot_team:
			# Проверяем есть ли наши юниты поблизости
			for bot_unit in bot_units:
				if bot_unit.global_position.distance_to(unit.global_position) < 200.0:
					enemy_count += 1
					break
	
	return enemy_count

func _find_enemy_hexes() -> Array[Vector2i]:
	"""
	Находит вражеские гексы для атаки
	"""
	var enemy_hexes: Array[Vector2i] = []
	
	if not Handlers.GameHandler:
		return enemy_hexes
	
	for hex_pos in Handlers.GameHandler.hexes_dict.keys():
		var hex = Handlers.GameHandler.hexes_dict[hex_pos]
		if hex.team_owner != -1 and hex.team_owner != int(bot_team):
			enemy_hexes.append(hex_pos)
	
	return enemy_hexes

func _get_available_attack_units() -> Array[BaseUnit]:
	"""
	Получает юниты доступные для атаки
	"""
	var available_units: Array[BaseUnit] = []
	
	for unit in bot_units:
		if _is_unit_available_for_help(unit) and not (unit is CommandUnit):
			available_units.append(unit)
	
	return available_units

func _get_units_near_hex(hex_position: Vector2i, radius: float) -> Array[BaseUnit]:
	"""
	Получает юниты рядом с указанным гексом
	"""
	var nearby_units: Array[BaseUnit] = []
	
	if not Handlers.GameHandler or not Handlers.GameHandler.overlay_map:
		return nearby_units
	
	var world_position = Handlers.GameHandler.overlay_map.map_to_local(hex_position)
	world_position = Handlers.GameHandler.overlay_map.to_global(world_position)
	
	for unit in bot_units:
		if unit.global_position.distance_to(world_position) <= radius:
			nearby_units.append(unit)
	
	return nearby_units

func _call_reinforcements_to_hex(hex_position: Vector2i) -> void:
	"""
	Вызывает подкрепления к указанному гексу
	"""
	var available_units = _get_available_attack_units()
	if available_units.size() > 0:
		var reinforcement = available_units[0]
		_order_hex_capture(reinforcement, hex_position)
		print("🚁 BOT: Отправлено подкрепление к гексу ", hex_position)

func _coordinate_group_attack(units: Array[BaseUnit], target_hex: Vector2i) -> void:
	"""
	Координирует групповую атаку на цель
	"""
	for unit in units:
		_order_hex_capture(unit, target_hex)
	print("⚔️ BOT: Координирована групповая атака на гекс ", target_hex, " силами ", units.size(), " юнитов")

func _handle_emergency_situations() -> void:
	"""
	Обрабатывает аварийные ситуации
	"""
	# Проверяем не остались ли командные юниты без защиты
	for command_unit in command_units:
		var nearby_defenders = _find_nearby_friendly_units(command_unit.global_position, 150.0)
		if nearby_defenders.size() < 2:  # Менее 2 защитников включая сам командный юнит
			print("🚨 BOT: Командный юнит нуждается в защите!")
			_call_reinforcements_to_position(command_unit.global_position)

func _call_reinforcements_to_position(position: Vector2) -> void:
	"""
	Вызывает подкрепления к указанной позиции
	"""
	var available_units = _get_available_attack_units()
	if available_units.size() > 0:
		var reinforcement = available_units[0]
		reinforcement.rpc_id(1, "add_order", position, true)
		print("🚁 BOT: Отправлено подкрепление к позиции ", position)

func _exit_tree() -> void:
	"""
	Очистка при удалении бота
	"""
	print("👋 BOT: Бот ", bot_name, " завершает работу") 
