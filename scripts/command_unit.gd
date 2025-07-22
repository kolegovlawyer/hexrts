extends BaseUnit
class_name CommandUnit

# TODO: Phase 2 - Заменить временное увеличение спрайта (1.25x) на специальный визуальный индикатор
# Временное решение: спрайт командного юнита увеличен в 1.25 раза в command_unit.tscn
# для визуального отличия от обычных юнитов

# Параметры захвата гексов
const CAPTURE_TIME: float = 5.0  # Время захвата гекса в секундах
const CHECK_INTERVAL: float = 1.0  # Проверка каждую секунду (60 фреймов при 60 FPS)

@onready var capture_progress_bar = get_node("%CaptureProgress")

# Текущий гекс, на котором находится юнит
var current_hex = null
var check_timer: float = 0.0
var is_capturing: bool = false  # Флаг активного захвата (серверная логика)

# СИСТЕМЫ АНТИ-ЗАСТРЕВАНИЯ для CommandUnit
var command_stuck_timer: float = 0.0
var last_command_position: Vector2 = Vector2.ZERO
var emergency_escape_attempts: int = 0
const MAX_ESCAPE_ATTEMPTS: int = 3
const COMMAND_STUCK_THRESHOLD: float = 4.0  # Больше времени для командных юнитов

# СИСТЕМА ОТСТУПЛЕНИЯ ПРИ АТАКЕ
var is_under_attack: bool = false
var is_retreating: bool = false
var retreat_target_position: Vector2 = Vector2.ZERO
const SAFE_RETREAT_DISTANCE: float = 400.0  # Дистанция отступления
var enemy_check_timer: float = 0.0
const ENEMY_CHECK_INTERVAL: float = 1.0  # Проверка врагов каждую секунду

func _ready() -> void:
	super._ready()
	
	# КЛИЕНТСКАЯ ЛОГИКА: Управление прогресс-баром только у владельца
	if not is_multiplayer_authority():
		if capture_progress_bar:
			capture_progress_bar.hide()
			capture_progress_bar.value = 0.0
	
	# СЕРВЕРНАЯ ЛОГИКА: Инициализация команды
	if is_multiplayer_authority() and owner_id != 1:
		var player = Handlers.TeamHandler.find_player_by_id(owner_id)
		if player:
			var expected_team = player.Team
			if owner_team != expected_team:
				owner_team = expected_team
		
		# Инициализируем позицию для анти-застревания
		last_command_position = global_position
		
		# Подключаемся к собственному сигналу атаки для отступления
		if not under_attack.is_connected(_on_command_unit_under_attack):
			under_attack.connect(_on_command_unit_under_attack)

func can_capture_while_in_state(state: int) -> bool:
	"""
	Определяет, может ли командный юнит захватывать территорию в данном состоянии
	Захват возможен во всех состояниях кроме движения
	"""
	match state:
		UNIT_STATES.IDLE:
			return true  # Неподвижен - может захватывать
		UNIT_STATES.MOVING:
			return false  # В движении - не может захватывать
		UNIT_STATES.ATTACKING:
			return true  # Атакует стоя на месте - может захватывать
		UNIT_STATES.AUTO_ATTACKING:
			return true  # Автоатака стоя на месте - может захватывать
		_:
			return false  # Неизвестное состояние - не рискуем

# Функция для проверки текущего гекса
func check_current_hex() -> void:
	"""
	Проверяет гекс под юнитом и обновляет информацию о присутствии
	Вызывается каждую секунду на сервере
	"""
	if not Handlers.GameHandler:
		return
		
	# Получаем гекс по текущей позиции юнита
	var hex = Handlers.GameHandler.get_hex_at_world_position(global_position)
	
	# Если юнит сменил гекс
	if hex != current_hex:
		# Останавливаем захват предыдущего гекса
		if current_hex and is_capturing:
			stop_capture("смена гекса")
		
		# Удаляем из предыдущего гекса
		if current_hex:
			current_hex.remove_command_unit(self)
		
		# Добавляем в новый гекс
		current_hex = hex
		if current_hex:
			current_hex.add_command_unit(self)
	
	# Если юнит на гексе, проверяем возможность захвата
	if current_hex:
		# УЛУЧШЕННАЯ ЛОГИКА: Захват возможен во всех состояниях кроме движения
		if can_capture_while_in_state(unit_state) and current_hex.can_be_captured_by_team(owner_team):
			if current_hex.capturing_team != owner_team:
				start_capture()
		else:
			if not can_capture_while_in_state(unit_state):
				if is_capturing:
					stop_capture("нельзя захватывать в состоянии " + UNIT_STATES.keys()[unit_state])
	else:
		if is_capturing:
			stop_capture("юнит покинул гекс")

func start_capture() -> void:
	"""Начинает процесс захвата гекса (серверная логика)"""
	if not current_hex:
		return
		
	current_hex.start_capture(owner_team)
	is_capturing = true
	
	# Уведомляем клиентов о начале захвата
	rpc("client_start_capture_visual", current_hex.position)

func stop_capture(reason: String = "") -> void:
	"""Останавливает процесс захвата гекса (серверная логика)"""
	if not is_capturing:
		return
		
	is_capturing = false
	
	# Уведомляем клиентов об остановке захвата
	rpc("client_stop_capture_visual")
	
	# Сбрасываем прогресс захвата в гексе
	if current_hex:
		current_hex.reset_capture()

@rpc("authority", "reliable")
func client_start_capture_visual(hex_position: Vector2i) -> void:
	"""Показывает прогресс-бар захвата у клиента-владельца"""
	# БЕЗОПАСНАЯ ПРОВЕРКА: multiplayer может быть null при уничтожении юнита
	if is_instance_valid(multiplayer) and owner_id == multiplayer.get_unique_id() and capture_progress_bar:
		capture_progress_bar.show()
		capture_progress_bar.value = 0.0
		capture_progress_bar.max_value = 100.0

@rpc("authority", "reliable")
func client_stop_capture_visual() -> void:
	"""Скрывает прогресс-бар захвата у клиента-владельца"""
	# БЕЗОПАСНАЯ ПРОВЕРКА: multiplayer может быть null при уничтожении юнита
	if is_instance_valid(multiplayer) and owner_id == multiplayer.get_unique_id() and capture_progress_bar:
		capture_progress_bar.hide()
		capture_progress_bar.value = 0.0

@rpc("authority", "unreliable")
func client_update_capture_progress(progress_percent: float) -> void:
	"""Обновляет прогресс захвата у клиента-владельца"""
	# БЕЗОПАСНАЯ ПРОВЕРКА: multiplayer может быть null при уничтожении юнита
	if is_instance_valid(multiplayer) and owner_id == multiplayer.get_unique_id() and capture_progress_bar and capture_progress_bar.visible:
		capture_progress_bar.value = progress_percent

# Переопределяем обработчики изменения состояния для управления захватом
func _unit_state_exit(state: int) -> void:
	"""Обработка выхода из состояния"""
	super._unit_state_exit(state)
	
	# При выходе из любого состояния где был разрешен захват, ничего не делаем
	# Захват будет проверен в новом состоянии

func _unit_state_enter(state: int) -> void:
	"""Обработка входа в состояние"""
	super._unit_state_enter(state)
	
	# При входе в состояние движения останавливаем захват
	if state == UNIT_STATES.MOVING and is_capturing:
		stop_capture("начало движения")

# Переопределяем _physics_process для системы захвата гексов
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# СЕРВЕРНАЯ ЛОГИКА
	if is_multiplayer_authority():
		# СИСТЕМЫ АНТИ-ЗАСТРЕВАНИЯ для CommandUnit (только если не отступаем)
		if not is_retreating:
			_handle_command_unit_stuck_detection(delta)
		
		# СИСТЕМА ПРОВЕРКИ БЕЗОПАСНОСТИ ПРИ ОТСТУПЛЕНИИ
		if is_retreating or is_under_attack:
			enemy_check_timer += delta
			if enemy_check_timer >= ENEMY_CHECK_INTERVAL:
				enemy_check_timer = 0.0
				_check_retreat_safety()
		
		# Обновляем таймер проверки гексов (каждую секунду) - НЕ во время отступления
		if not is_retreating:
			check_timer += delta
			if check_timer >= CHECK_INTERVAL:
				check_timer = 0.0
				check_current_hex()
		
		# Обновляем прогресс захвата если юнит захватывает гекс - НЕ во время отступления
		if not is_retreating and is_capturing and current_hex and current_hex.capturing_team == owner_team:
			var capture_speed = 1.0 / CAPTURE_TIME  # Скорость захвата
			var capture_completed = current_hex.update_capture_progress(delta, capture_speed)
			
			# Отправляем обновление прогресса клиентам
			var progress_percent = current_hex.capture_progress * 100.0
			rpc("client_update_capture_progress", progress_percent)
			
			if capture_completed:
				# Завершаем захват без спама логов
				is_capturing = false
				rpc("client_stop_capture_visual")
				
				# Обновляем визуал гекса в OverlayMap
				Handlers.GameHandler.update_hex_overlay(current_hex.position, current_hex.team_owner)

func _handle_command_unit_stuck_detection(delta: float) -> void:
	"""
	Специальная система анти-застревания для CommandUnit
	Обнаруживает застревание и применяет экстренные меры спасения
	"""
	# Проверяем движение CommandUnit
	var current_position = global_position
	var moved_distance = current_position.distance_to(last_command_position)
	
	# Если CommandUnit движется (> 3 пикселей), сбрасываем таймер
	if moved_distance > 3.0:
		command_stuck_timer = 0.0
		emergency_escape_attempts = 0
		last_command_position = current_position
		return
	
	# Если CommandUnit должен двигаться, но не движется
	if orders.size() > 0 and orders[0].type == "move":
		command_stuck_timer += delta
		
		# КРИТИЧЕСКАЯ СИТУАЦИЯ: CommandUnit застрял
		if command_stuck_timer >= COMMAND_STUCK_THRESHOLD:
			_execute_emergency_escape()
			command_stuck_timer = 0.0  # Сбрасываем таймер
	else:
		# Если нет приказов движения, сбрасываем таймер
		command_stuck_timer = 0.0
		emergency_escape_attempts = 0

func _execute_emergency_escape() -> void:
	"""
	Экстренное спасение CommandUnit из застревания
	Применяет различные стратегии в зависимости от попытки
	"""
	emergency_escape_attempts += 1
	
	match emergency_escape_attempts:
		1:
			# ПОПЫТКА 1: Отгоняем защитников
			_clear_nearby_defenders()
		2:
			# ПОПЫТКА 2: Телепортируемся на небольшое расстояние
			_emergency_teleport_short()
		3:
			# ПОПЫТКА 3: Телепортируемся к ближайшему союзному юниту
			_emergency_teleport_to_ally()
		_:
			# ПОПЫТКА 4+: Случайная телепортация
			_emergency_teleport_random()
			emergency_escape_attempts = MAX_ESCAPE_ATTEMPTS  # Не увеличиваем дальше

func _clear_nearby_defenders() -> void:
	"""
	Отгоняет ближайших союзных юнитов чтобы освободить место для CommandUnit
	"""
	var nearby_units = get_tree().get_nodes_in_group("units")
	var cleared_count = 0
	
	for unit in nearby_units:
		if unit is BaseUnit and unit != self:
			var distance = global_position.distance_to(unit.global_position)
			if distance <= 80.0 and unit.owner_id == owner_id:  # Союзные юниты в радиусе 80px
				# Отправляем защитника на случайную позицию в стороне
				var escape_direction = (unit.global_position - global_position).normalized()
				var escape_position = unit.global_position + escape_direction * 150.0
				
				# Очищаем приказы и отправляем в сторону
				unit.orders.clear()
				unit.add_order(escape_position, true)
				cleared_count += 1
	
	if cleared_count > 0 and not has_meta("defenders_cleared_logged"):
		set_meta("defenders_cleared_logged", true)
		print("🚨 COMMAND ESCAPE: Отогнано ", cleared_count, " защитников от застрявшего CommandUnit")

func _emergency_teleport_short() -> void:
	"""
	Короткая телепортация на 100-150 пикселей в случайном направлении
	"""
	var random_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var teleport_distance = randf_range(100, 150)
	var new_position = global_position + random_direction * teleport_distance
	
	global_position = new_position
	
	if not has_meta("short_teleport_logged"):
		set_meta("short_teleport_logged", true)
		print("🔄 COMMAND ESCAPE: Короткая телепортация CommandUnit на ", int(teleport_distance), "px")

func _emergency_teleport_to_ally() -> void:
	"""
	Телепортация к ближайшему союзному юниту
	"""
	var allied_units = get_tree().get_nodes_in_group("units")
	var closest_ally = null
	var min_distance = 9999.0
	
	for unit in allied_units:
		if unit is BaseUnit and unit != self and unit.owner_id == owner_id:
			var distance = global_position.distance_to(unit.global_position)
			if distance < min_distance and distance > 100.0:  # Не слишком близко
				min_distance = distance
				closest_ally = unit
	
	if closest_ally:
		# Телепортируемся рядом с союзником (не на него)
		var offset = Vector2(randf_range(-60, 60), randf_range(-60, 60))
		global_position = closest_ally.global_position + offset
		
		if not has_meta("ally_teleport_logged"):
			set_meta("ally_teleport_logged", true)
			print("🤝 COMMAND ESCAPE: Телепортация CommandUnit к союзнику")
	else:
		# Если союзников нет, делаем случайную телепортацию
		_emergency_teleport_random()

func _emergency_teleport_random() -> void:
	"""
	Случайная телепортация на большое расстояние (200-300 пикселей)
	"""
	var random_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var teleport_distance = randf_range(200, 300)
	var new_position = global_position + random_direction * teleport_distance
	
	global_position = new_position
	
	if not has_meta("random_teleport_logged"):
		set_meta("random_teleport_logged", true)
		print("🎲 COMMAND ESCAPE: Случайная телепортация CommandUnit на ", int(teleport_distance), "px")

func _on_command_unit_under_attack(attacker: BaseUnit, victim: BaseUnit) -> void:
	"""
	Обработчик атаки на CommandUnit - инициирует отступление
	"""
	if victim != self:
		return  # Не наш CommandUnit
	
	is_under_attack = true
	
	# Останавливаем захват при атаке
	if is_capturing:
		stop_capture("под атакой")
	
	# Начинаем отступление к базе
	_initiate_retreat()

func _initiate_retreat() -> void:
	"""
	Инициирует отступление CommandUnit к безопасной позиции
	"""
	if is_retreating:
		return  # Уже отступаем
	
	is_retreating = true
	
	# Находим позицию для отступления (база или безопасная зона)
	retreat_target_position = _find_safe_retreat_position()
	
	# Очищаем текущие приказы и отступаем
	orders.clear()
	add_order(retreat_target_position, true)
	
	print("🏃 RETREAT: CommandUnit ", name, " начинает отступление к безопасной позиции")

func _find_safe_retreat_position() -> Vector2:
	"""
	Находит безопасную позицию для отступления (база или удаленная от врагов зона)
	"""
	# Пытаемся найти свою базу (FOB)
	var bot_fob = _find_own_fob()
	if bot_fob:
		return bot_fob.global_position
	
	# Если база не найдена, отступаем в противоположную сторону от врагов
	var enemy_center = _calculate_enemy_center_position()
	if enemy_center != Vector2.ZERO:
		var retreat_direction = (global_position - enemy_center).normalized()
		return global_position + retreat_direction * SAFE_RETREAT_DISTANCE
	
	# Fallback: отступаем в случайном направлении
	var random_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	return global_position + random_direction * SAFE_RETREAT_DISTANCE

func _find_own_fob() -> Node:
	"""
	Находит собственную базу (FOB) по owner_id
	"""
	var all_fobs = get_tree().get_nodes_in_group("fobs")
	for fob in all_fobs:
		if fob.has_method("get") and fob.owner_id == owner_id:
			return fob
	return null

func _calculate_enemy_center_position() -> Vector2:
	"""
	Вычисляет центр позиций всех видимых врагов
	"""
	var enemy_positions: Array[Vector2] = []
	
	for visible_unit in has_vision_on:
		if is_instance_valid(visible_unit) and _is_enemy_for_command_unit(visible_unit):
			enemy_positions.append(visible_unit.global_position)
	
	if enemy_positions.is_empty():
		return Vector2.ZERO
	
	# Вычисляем центр
	var center = Vector2.ZERO
	for pos in enemy_positions:
		center += pos
	center /= enemy_positions.size()
	
	return center

func _is_enemy_for_command_unit(unit: BaseUnit) -> bool:
	"""
	Проверяет, является ли юнит вражеским для данного CommandUnit
	"""
	if not is_instance_valid(unit):
		return false
	
	# Проверяем команды
	if owner_team != null and unit.owner_team != null:
		return owner_team != unit.owner_team
	
	# Fallback: проверяем owner_id
	return owner_id != unit.owner_id

func _check_retreat_safety() -> void:
	"""
	Проверяет безопасность - завершает отступление если врагов не видно
	"""
	var enemies_visible = false
	
	for visible_unit in has_vision_on:
		if is_instance_valid(visible_unit) and _is_enemy_for_command_unit(visible_unit):
			enemies_visible = true
			break
	
	if not enemies_visible:
		# Враги исчезли - завершаем отступление
		is_under_attack = false
		is_retreating = false
		retreat_target_position = Vector2.ZERO
		print("✅ RETREAT: CommandUnit ", name, " в безопасности, отступление завершено")

func _exit_tree() -> void:
	"""Очищаем ссылки при удалении юнита"""
	if current_hex:
		current_hex.remove_command_unit(self)
		
	# Останавливаем захват при удалении юнита
	if is_capturing:
		stop_capture("удаление юнита")
