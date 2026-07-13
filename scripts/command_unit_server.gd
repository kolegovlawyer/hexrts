class_name CommandUnitServer extends BaseUnitServer

### СЕРВЕРНАЯ ЛОГИКА КОМАНДНОГО ЮНИТА
# Наследуется от BaseUnitServer и добавляет логику захвата гексов

const _SupplyConsts := preload("res://scripts/supply/supply_system.gd")

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

# Развёртывание КШМ → FOB
var is_deploying_fob: bool = false
var deploy_fob_timer: float = 0.0

func _ready() -> void:
	# Устанавливаем флаг командного юнита
	is_command_unit_flag = true
	
	# Вызываем базовый _ready()
	super._ready()
	
	# КШМ сразу ранг 5, опыт заблокирован (даже до/без snapshot).
	if is_multiplayer_authority():
		_lock_experience_as_command()
	
	# Страховка: доинициализируем команду, если по каким-то причинам еще не установлена
	if is_multiplayer_authority() and owner_team == null:
		_initialize_team_and_visibility()
	
	# КЛИЕНТСКАЯ ЛОГИКА: Управление прогресс-баром только у владельца
	if not is_multiplayer_authority():
		if capture_progress_bar:
			capture_progress_bar.hide()
			capture_progress_bar.value = 0.0
	
	# СЕРВЕРНАЯ ЛОГИКА: Инициализация команды
	if is_multiplayer_authority() and owner_id != 1:
		var player = Handlers.TeamHandler.find_player_by_id(owner_id)
		if player:
			var expected_team = player.team
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

func stop_capture(_reason: String = "") -> void:
	"""Останавливает процесс захвата гекса (серверная логика)"""
	if not is_capturing:
		return
		
	is_capturing = false
	
	# Уведомляем клиентов об остановке захвата
	rpc("client_stop_capture_visual")
	
	# Сбрасываем прогресс захвата в гексе
	if current_hex:
		current_hex.reset_capture()

@rpc("any_peer", "reliable")
func client_start_capture_visual(_hex_position: Vector2i) -> void:
	"""Показывает прогресс-бар захвата у клиента-владельца"""
	# БЕЗОПАСНАЯ ПРОВЕРКА: multiplayer может быть null при уничтожении юнита
	if is_instance_valid(multiplayer) and owner_id == multiplayer.get_unique_id() and capture_progress_bar:
		capture_progress_bar.show()
		capture_progress_bar.value = 0.0
		capture_progress_bar.max_value = 100.0

@rpc("any_peer", "reliable")
func client_stop_capture_visual() -> void:
	"""Скрывает прогресс-бар захвата у клиента-владельца"""
	# БЕЗОПАСНАЯ ПРОВЕРКА: multiplayer может быть null при уничтожении юнита
	if is_instance_valid(multiplayer) and owner_id == multiplayer.get_unique_id() and capture_progress_bar:
		capture_progress_bar.hide()
		capture_progress_bar.value = 0.0

@rpc("any_peer", "unreliable")
func client_update_capture_progress(progress_percent: float) -> void:
	"""Обновляет прогресс захвата у клиента-владельца"""
	# БЕЗОПАСНАЯ ПРОВЕРКА: multiplayer может быть null при уничтожении юнита
	if is_instance_valid(multiplayer) and owner_id == multiplayer.get_unique_id() and capture_progress_bar and capture_progress_bar.visible:
		capture_progress_bar.value = progress_percent

# Переопределяем обработчики изменения состояния для управления захватом
func _unit_state_exit(state: int) -> void:
	"""Обработка выхода из состояния"""
	# Вызываем базовый метод
	super._unit_state_exit(state)
	
	# При выходе из любого состояния где был разрешен захват, ничего не делаем
	# Захват будет проверен в новом состоянии

func _unit_state_enter(state: int) -> void:
	"""Обработка входа в состояние"""
	# Вызываем базовый метод
	super._unit_state_enter(state)
	
	# При входе в состояние движения останавливаем захват
	if state == UNIT_STATES.MOVING and is_capturing:
		stop_capture("начало движения")

# Переопределяем _physics_process для системы захвата гексов
func _physics_process(delta: float) -> void:
	if is_multiplayer_authority() and orders.size() > 0 and orders[0].type == "move_capture":
		var is_bot := Handlers.GameHandler.get_bot_team_by_id(owner_id) != -1
		if not is_bot and not _should_defer_route_order():
			_process_move_capture_order_immediate(orders[0], delta, is_bot)
	
	# Вызываем базовый _physics_process
	super._physics_process(delta)
	
	# СЕРВЕРНАЯ ЛОГИКА
	if is_multiplayer_authority():
		if is_deploying_fob:
			_process_deploy_fob(delta)

		# СИСТЕМЫ АНТИ-ЗАСТРЕВАНИЯ для CommandUnit (только если не отступаем)
		if not is_retreating and not is_deploying_fob:
			_handle_command_unit_stuck_detection(delta)
		
		# СИСТЕМА ПРОВЕРКИ БЕЗОПАСНОСТИ ПРИ ОТСТУПЛЕНИИ
		if is_retreating or is_under_attack:
			enemy_check_timer += delta
			if enemy_check_timer >= ENEMY_CHECK_INTERVAL:
				enemy_check_timer = 0.0
				_check_retreat_safety()
		
		# Обновляем таймер проверки гексов (каждую секунду) - НЕ во время отступления
		if not is_retreating and not is_deploying_fob:
			check_timer += delta
			if check_timer >= CHECK_INTERVAL:
				check_timer = 0.0
				check_current_hex()
		
		# Обновляем прогресс захвата если юнит захватывает гекс - НЕ во время отступления
		if not is_retreating and not is_deploying_fob and is_capturing and current_hex and current_hex.capturing_team == owner_team:
			var capture_speed = 1.0 / CAPTURE_TIME
			if has_supply_penalties():
				capture_speed *= _SupplyConsts.CAPTURE_PENALTY_MULT
			var old_owner: int = current_hex.team_owner
			var capture_completed = current_hex.update_capture_progress(delta, capture_speed)
			
			# Отправляем обновление прогресса клиентам
			var progress_percent = current_hex.capture_progress * 100.0
			rpc("client_update_capture_progress", progress_percent)
			
			if capture_completed:
				# Завершаем захват без спама логов
				is_capturing = false
				rpc("client_stop_capture_visual")

				if Handlers.GameHandler and Handlers.GameHandler.battle_log:
					Handlers.GameHandler.battle_log.on_hex_captured(
						current_hex.position,
						old_owner,
						current_hex.team_owner,
						self
					)
				
				# Обновляем визуал гекса в OverlayMap
				Handlers.GameHandler.update_hex_overlay(current_hex.position, current_hex.team_owner)
				
				if orders.size() > 0 and orders[0].type == "move_capture":
					if orders[0].get("phase", "moving") == "capturing":
						_pop_current_order()
						_advance_queue_after_move_leg()

func interrupt_capture_for_direct_order(prepare_move: bool = true) -> void:
	"""Сбрасывает захват, чтобы КШМ мог немедленно выполнить прямой приказ движения."""
	if is_deploying_fob:
		_cancel_deploy_fob("новый приказ")
	if is_capturing:
		stop_capture("новый приказ")
	if unit_state == UNIT_STATES.IDLE and orders.size() > 0:
		var first_type: String = str(orders[0].get("type", ""))
		if first_type == "move_capture":
			orders[0]["phase"] = "moving"
	if navagent:
		navagent.target_position = global_position
		navagent.set_velocity(Vector2.ZERO)
	if prepare_move:
		unit_state = UNIT_STATES.MOVING


@rpc("any_peer", "reliable")
func add_order(order_obj, clear_queue: bool = false, capture_at_destination: bool = false) -> void:
	if is_multiplayer_authority() and clear_queue and typeof(order_obj) == TYPE_VECTOR2:
		interrupt_capture_for_direct_order(true)
	super.add_order(order_obj, clear_queue, capture_at_destination)


@rpc("any_peer", "reliable")
func clear_orders() -> void:
	if is_multiplayer_authority():
		interrupt_capture_for_direct_order(false)
	super.clear_orders()


@rpc("any_peer", "reliable")
func request_deploy_fob() -> void:
	if not is_multiplayer_authority():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if owner_id != sender_id:
		return
	if not _can_start_deploy_fob():
		return
	_start_deploy_fob()


@rpc("any_peer", "reliable")
func request_promote_to_command() -> void:
	# КШМ нельзя произвести в КШМ.
	pass


func _can_start_deploy_fob() -> bool:
	if is_deploying_fob or is_retreating:
		return false
	if not is_command_unit():
		return false
	var weight_ok := preset_stat_sum == UnitPresetBalance.STAT_SUM_MAX
	if not weight_ok and not preset_snapshot.is_empty():
		weight_ok = UnitPresetBalance.is_max_weight(preset_snapshot)
	if not weight_ok:
		return false
	if not orders.is_empty():
		return false
	if unit_state != UNIT_STATES.IDLE:
		return false
	if navagent and not navagent.is_navigation_finished():
		return false
	return _is_on_friendly_hex()


func _is_on_friendly_hex() -> bool:
	if not Handlers.GameHandler or owner_team == null:
		return false
	var hex = Handlers.GameHandler.get_hex_at_world_position(global_position)
	if hex == null:
		return false
	return hex.team_owner == int(owner_team)


func _start_deploy_fob() -> void:
	if is_capturing:
		stop_capture("развёртывание FOB")
	orders.clear()
	unit_state = UNIT_STATES.IDLE
	if navagent:
		navagent.target_position = global_position
		navagent.set_velocity(Vector2.ZERO)
	is_deploying_fob = true
	deploy_fob_timer = 0.0
	_sync_order_queue_to_owner()
	rpc("client_start_capture_visual", Vector2i.ZERO)


func _cancel_deploy_fob(_reason: String = "") -> void:
	if not is_deploying_fob:
		return
	is_deploying_fob = false
	deploy_fob_timer = 0.0
	rpc("client_stop_capture_visual")


func _process_deploy_fob(delta: float) -> void:
	if not _is_on_friendly_hex() or not orders.is_empty() or unit_state == UNIT_STATES.MOVING:
		_cancel_deploy_fob("условия нарушены")
		return
	deploy_fob_timer += delta
	var progress := clampf(deploy_fob_timer / UnitPresetBalance.DEPLOY_FOB_DURATION, 0.0, 1.0) * 100.0
	rpc("client_update_capture_progress", progress)
	if deploy_fob_timer >= UnitPresetBalance.DEPLOY_FOB_DURATION:
		_complete_deploy_fob()


func _complete_deploy_fob() -> void:
	is_deploying_fob = false
	deploy_fob_timer = 0.0
	rpc("client_stop_capture_visual")
	var snapshot: Dictionary = preset_snapshot.duplicate(true)
	if Handlers.UnitSpawnHandler and Handlers.UnitSpawnHandler.has_method("deploy_command_as_fob"):
		Handlers.UnitSpawnHandler.deploy_command_as_fob(self, snapshot)


func _should_defer_route_order() -> bool:
	"""
	Откладывает старт маршрута (move_capture), пока идёт пассивный захват гекса.
	Обычный приказ move обрабатывается в базовом классе и прерывает захват сразу.
	"""
	if not is_capturing or orders.is_empty():
		return false
	var first_order: Dictionary = orders[0]
	if first_order.get("type", "") != "move_capture":
		return false
	return first_order.get("phase", "moving") == "moving"

func _process_move_capture_order_immediate(order: Dictionary, delta: float, is_bot: bool) -> void:
	var phase: String = order.get("phase", "moving")
	if phase == "moving":
		_ensure_move_leg_steering(order)
		if unit_state != UNIT_STATES.MOVING:
			unit_state = UNIT_STATES.MOVING
			_set_navigation_avoidance(true)
			_reset_move_progress_tracking(order.position)
		
		var pos: Vector2 = order.position
		navagent.target_position = _route_smart_target(pos)
		
		if not navagent.is_target_reachable():
			var alternative_target = _find_alternative_path_target(pos)
			navagent.target_position = _route_smart_target(alternative_target)
		
		var distance_to_target = global_position.distance_to(pos)
		var close_enough_threshold: float = _get_close_enough_threshold(is_bot)
		var close_enough = distance_to_target < close_enough_threshold
		var nav_done = navagent.is_navigation_finished()
		var moved = global_position.distance_to(last_move_position) > 1.5
		
		if close_enough or nav_done:
			if global_position.distance_to(pos) > close_enough_threshold:
				var next_wp: Vector2 = _route_smart_target(pos)
				if next_wp.distance_to(global_position) <= close_enough_threshold:
					_release_route_wp_keep_side()
					next_wp = pos
				navagent.target_position = next_wp
				stuck_timer = 0.0
				_update_move_progress_or_abort(pos, delta)
			else:
				order["phase"] = "capturing"
				unit_state = UNIT_STATES.IDLE
				_clear_active_route_wp(true)
				_reset_move_steering_state()
				stuck_timer = 0.0
				no_progress_timer = 0.0
				_progress_best_dist = INF
				if navagent:
					navagent.target_position = global_position
					navagent.set_velocity(Vector2.ZERO)
				check_current_hex()
				_evaluate_waypoint_capture(order)
		elif not moved:
			if not _pivot_done and not _reverse_move_active:
				stuck_timer = 0.0
			else:
				stuck_timer += delta
				if stuck_timer > 2.5:
					_execute_smart_unstuck_maneuver(pos)
					stuck_timer = 0.0
			_update_move_progress_or_abort(pos, delta)
		else:
			stuck_timer = 0.0
			_update_move_progress_or_abort(pos, delta)
		last_move_position = global_position
	elif phase == "capturing":
		unit_state = UNIT_STATES.IDLE
		if navagent:
			navagent.target_position = global_position
			navagent.set_velocity(Vector2.ZERO)
		_evaluate_waypoint_capture(order)

func _evaluate_waypoint_capture(_order: Dictionary) -> void:
	if not Handlers.GameHandler:
		_pop_current_order()
		return
	
	var hex = Handlers.GameHandler.get_hex_at_world_position(global_position)
	if hex == null:
		_pop_current_order()
		_advance_queue_after_move_leg()
		return
	
	if hex.team_owner == owner_team:
		_pop_current_order()
		_advance_queue_after_move_leg()
		return
	
	if not hex.can_be_captured_by_team(owner_team):
		_pop_current_order()
		_advance_queue_after_move_leg()
		return
	
	if hex != current_hex:
		if current_hex:
			current_hex.remove_command_unit(self)
		current_hex = hex
		current_hex.add_command_unit(self)
	
	if not is_capturing:
		start_capture()

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
	var is_active_move := false
	if orders.size() > 0:
		var active_order = orders[0]
		is_active_move = active_order.type == "move" or (
			active_order.type == "move_capture" and active_order.get("phase", "moving") == "moving"
		)
	if is_active_move:
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
		if unit is BaseUnitServer and unit != self:
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
		if unit is BaseUnitServer and unit != self and unit.owner_id == owner_id:
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

func _on_command_unit_under_attack(_attacker: BaseUnit, victim: BaseUnit) -> void:
	"""
	Авто-отступление к ФОБу только для бот-КШМ.
	Игрок управляет своим КШМ сам — не угоняем его приём.
	"""
	if victim != self:
		return

	if is_deploying_fob:
		_cancel_deploy_fob("под атакой")

	# Игровой КШМ: не вмешиваемся в приказы владельца.
	var is_bot := Handlers.GameHandler.get_bot_team_by_id(owner_id) != -1
	if not is_bot:
		return

	is_under_attack = true

	if is_capturing:
		stop_capture("под атакой")

	_initiate_retreat()

func _initiate_retreat() -> void:
	"""
	Инициирует отступление CommandUnit к безопасной позиции
	"""
	if is_retreating:
		return  # Уже отступаем

	if is_deploying_fob:
		_cancel_deploy_fob("отступление")
	
	is_retreating = true
	
	# Находим позицию для отступления (база или безопасная зона)
	retreat_target_position = _find_safe_retreat_position()
	
	# Очищаем текущие приказы и отступаем (plain move — без захвата по пути)
	orders.clear()
	_sync_order_queue_to_owner()
	orders.append({"type": "move", "position": retreat_target_position})
	_reset_move_progress_tracking(retreat_target_position)
	_sync_order_queue_to_owner()
	unit_state = UNIT_STATES.MOVING
	
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
	for fob_node in all_fobs:
		if fob_node.has_method("get") and fob_node.owner_id == owner_id:
			return fob_node
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

func _is_enemy_for_command_unit(unit: BaseUnitServer) -> bool:
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

func die() -> void:
	if is_deploying_fob:
		_cancel_deploy_fob("смерть")
	var owner_player_id := owner_id
	super.die()
	if Handlers.GameHandler and Handlers.GameHandler.has_method("handle_command_unit_lost"):
		Handlers.GameHandler.call_deferred("handle_command_unit_lost", owner_player_id)


func _exit_tree() -> void:
	"""Очищаем ссылки при удалении юнита"""
	if current_hex:
		current_hex.remove_command_unit(self)
		
	# Останавливаем захват при удалении юнита
	if is_capturing:
		stop_capture("удаление юнита")
	super._exit_tree()
